-- #########################################################################
-- ##  NÃO RODE ESTE ARQUIVO NO SUPABASE.                                  ##
-- ##  Em 05/10/2026 ele foi rodado inteiro junto com o ROLLBACK, e um     ##
-- ##  desfez o outro. Para aplicar, use os 5 arquivos                     ##
-- ##  2026-10-05-externo-passo-1 ... passo-5, um de cada vez.             ##
-- ##  Este fica como documentação do desenho completo.                    ##
-- #########################################################################
-- =========================================================================
-- 2026-10-05 — Vendedor EXTERNO: papel novo que só enxerga a própria carteira
-- =========================================================================
-- O QUE MUDA
--   * Papel `externo` em profiles.role. `vendedor` NÃO muda: o escritório
--     continua vendo e acatando pedidos de todo mundo.
--   * O que é "dele": empresa cujo vendedor_responsavel_id é ele, OU empresa
--     em que o escritório o incluiu (tabela company_access). Contatos,
--     oportunidades, interações, propostas, revisões e anexos herdam da
--     empresa — a regra mora numa função só, alcanca_empresa().
--   * Externo SÓ enxerga qualquer coisa com 2FA (sessão aal2). Sem 2FA, o
--     banco devolve vazio — o app força o cadastro do autenticador.
--   * CNPJ já cadastrado vira PEDIDO DE ACESSO para o escritório
--     (company_access_requests), sem revelar a quem a empresa pertence.
--   * Pedido fechado pelo externo vai para `aguardando_aceite`. Só o
--     escritório leva a `pedido` — e é aí que nasce o nº do pedido.
--   * Fecha 4 brechas que já existiam para qualquer usuário e que o externo
--     tornaria graves: view companies_with_tier ignorando RLS, custo de
--     matéria-prima legível, audit_log inteiro legível, anexos por org só.
--
-- COMO RODAR (ver CLAUDE.md, "O SQL Editor do Supabase é traiçoeiro"):
--   * UM BLOCO POR VEZ, na ordem. Cada um termina com uma conferência que
--     devolve número na tela. "Success. No rows returned" NÃO é confirmação.
--   * Antes do Bloco 1: "Baixar Backup" no Dashboard.
--   * Tenha aberto o 2026-10-05-vendedor-externo-ROLLBACK.sql.
--   * Os Blocos 1–3 não mudam nada para quem já usa (não existe externo).
--     O Bloco 4 troca as policies: depois dele, entre no app como admin e
--     como vendedor e confira que tudo continua aparecendo.
-- =========================================================================


-- =========================================================================
-- BLOCO 0 — DIAGNÓSTICO (só leitura). Rode e mande a saída antes de seguir.
-- =========================================================================
-- 0a) Versão do Postgres. security_invoker em view exige 15+.
-- SHOW server_version;
--
-- 0b) Existe CHECK em profiles.role? (se existir, o Bloco 1 troca por um
--     que aceite 'externo'; se não existir, o Bloco 1 cria)
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--  WHERE conrelid = 'public.profiles'::regclass AND contype = 'c';
--
-- 0c) Nome do CHECK de proposals.status (esperado: proposals_status_check)
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--  WHERE conrelid = 'public.proposals'::regclass AND contype = 'c';
--
-- 0d) Empresas SEM vendedor responsável — nenhum externo vai vê-las.
-- SELECT count(*) AS sem_responsavel FROM public.companies WHERE vendedor_responsavel_id IS NULL;
--
-- 0e) Propostas sem company_id — externo também não vê (a não ser as que ele criar).
-- SELECT count(*) AS proposta_sem_empresa FROM public.proposals WHERE company_id IS NULL;


-- =========================================================================
-- BLOCO 1 — papel, helpers e tabelas novas (não muda nada para quem já usa)
-- =========================================================================
BEGIN;

-- 1a) CHECK de role aceitando 'externo' (troca qualquer CHECK antigo de role)
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.profiles'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin','vendedor','leitor','externo'));

-- 1b) helpers
CREATE OR REPLACE FUNCTION public.is_externo()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT public.current_user_role() = 'externo';
$$;

-- Sessão confirmada com 2FA? Supabase grava o nível no JWT (aal1 / aal2).
CREATE OR REPLACE FUNCTION public.sessao_com_2fa()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

GRANT EXECUTE ON FUNCTION public.is_externo()     TO authenticated;
GRANT EXECUTE ON FUNCTION public.sessao_com_2fa() TO authenticated;

-- 1c) acesso extra de um externo a uma empresa (dada pelo escritório)
CREATE TABLE IF NOT EXISTS public.company_access (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  company_id  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id  uuid NOT NULL REFERENCES public.profiles(id)  ON DELETE CASCADE,
  granted_by  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, profile_id)
);
CREATE INDEX IF NOT EXISTS idx_company_access_profile ON public.company_access(profile_id);
DROP TRIGGER IF EXISTS tg_set_org_id ON public.company_access;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.company_access
  FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
-- quem deu acesso a quem fica no audit_log (tem company_id, então aparece no perfil)
DROP TRIGGER IF EXISTS tg_audit ON public.company_access;
CREATE TRIGGER tg_audit AFTER INSERT OR UPDATE OR DELETE ON public.company_access
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();

-- 1d) pedidos de acesso (externo tentou cadastrar CNPJ que já existe)
CREATE TABLE IF NOT EXISTS public.company_access_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  company_id    uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  requester_id  uuid NOT NULL REFERENCES public.profiles(id)  ON DELETE CASCADE,
  cnpj_digitado text,
  razao_digitada text,
  status        text NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','aprovado','recusado')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  decided_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  decided_at    timestamptz
);
-- um pedido pendente por (empresa, externo): pedir de novo não duplica
CREATE UNIQUE INDEX IF NOT EXISTS uq_access_req_pendente
  ON public.company_access_requests(company_id, requester_id) WHERE status = 'pendente';
DROP TRIGGER IF EXISTS tg_set_org_id ON public.company_access_requests;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.company_access_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_org_id();

-- 1e) A regra única de alcance. SECURITY DEFINER: lê companies/company_access
--     sem passar pelo RLS delas (senão a policy chamaria a si mesma).
--     Para quem NÃO é externo devolve true — o filtro por org continua na
--     própria policy, como antes.
CREATE OR REPLACE FUNCTION public.alcanca_empresa(p_company uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN NOT public.is_externo()     THEN true
    WHEN NOT public.sessao_com_2fa() THEN false
    WHEN p_company IS NULL           THEN false
    ELSE EXISTS (SELECT 1 FROM public.companies c
                  WHERE c.id = p_company AND c.org_id = public.current_org()
                    AND c.vendedor_responsavel_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.company_access a
                  WHERE a.company_id = p_company AND a.profile_id = auth.uid())
  END;
$$;

CREATE OR REPLACE FUNCTION public.alcanca_opp(p_opp uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN NOT public.is_externo() THEN true
    ELSE coalesce((SELECT public.alcanca_empresa(o.company_id)
                     FROM public.opportunities o WHERE o.id = p_opp), false)
  END;
$$;

-- Proposta sem empresa (company_id ficou NULL porque a empresa foi apagada)
-- só é visível a quem a criou.
CREATE OR REPLACE FUNCTION public.alcanca_proposta(p_prop uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN NOT public.is_externo()     THEN true
    WHEN NOT public.sessao_com_2fa() THEN false
    ELSE coalesce((SELECT CASE WHEN p.company_id IS NULL THEN p.seller_id = auth.uid()
                               ELSE public.alcanca_empresa(p.company_id) END
                     FROM public.proposals p WHERE p.id = p_prop), false)
  END;
$$;

GRANT EXECUTE ON FUNCTION public.alcanca_empresa(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.alcanca_opp(uuid)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.alcanca_proposta(uuid) TO authenticated;

-- 1f) RLS das tabelas novas
ALTER TABLE public.company_access          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_access_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cacc_select" ON public.company_access;
DROP POLICY IF EXISTS "cacc_insert" ON public.company_access;
DROP POLICY IF EXISTS "cacc_delete" ON public.company_access;
CREATE POLICY "cacc_select" ON public.company_access FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR profile_id = auth.uid()));
-- dar/tirar acesso é coisa do escritório (não externo, não leitor)
CREATE POLICY "cacc_insert" ON public.company_access FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_externo() AND NOT public.is_leitor());
CREATE POLICY "cacc_delete" ON public.company_access FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_externo() AND NOT public.is_leitor());

-- pedidos: externo vê só os próprios; ninguém escreve direto — só pelas RPCs
DROP POLICY IF EXISTS "cacc_req_select" ON public.company_access_requests;
CREATE POLICY "cacc_req_select" ON public.company_access_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR requester_id = auth.uid()));

COMMIT;

-- CONFERÊNCIA DO BLOCO 1 (rode separado; deve devolver 2 linhas com total 0
-- e as 4 funções):
-- SELECT 'company_access' t, count(*) FROM public.company_access
-- UNION ALL SELECT 'company_access_requests', count(*) FROM public.company_access_requests;
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('is_externo','sessao_com_2fa','alcanca_empresa','alcanca_opp','alcanca_proposta') ORDER BY 1;


-- =========================================================================
-- BLOCO 2 — aceite de pedido (status novo + guarda do externo em proposals)
-- =========================================================================
BEGIN;

-- 2a) status 'aguardando_aceite'. Troca o CHECK antigo (achado pela definição,
--     não pelo nome, pra não depender de como o Postgres o batizou).
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.proposals'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%em_andamento%'
  LOOP
    EXECUTE format('ALTER TABLE public.proposals DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
ALTER TABLE public.proposals ADD CONSTRAINT proposals_status_check
  CHECK (status IN ('em_andamento','aguardando_aceite','pedido','expedido','cancelada'));

-- 2b) rastro do aceite. Em coluna (não no snapshot): é cumprimento, não negociação.
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS aceite_solicitado_em  timestamptz,
  ADD COLUMN IF NOT EXISTS aceite_solicitado_por uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aceite_em             timestamptz,
  ADD COLUMN IF NOT EXISTS aceite_por            uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aceite_recusa_motivo  text;

-- 2c) guarda. A trava de "externo não fecha pedido sozinho" mora AQUI, não
--     no botão: quem chamar a API pelo console esbarra na exceção.
CREATE OR REPLACE FUNCTION public.proposals_guarda_externo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_externo() THEN
    -- escritório aceitando: registra quem e quando
    IF TG_OP = 'UPDATE' AND OLD.status = 'aguardando_aceite' AND NEW.status = 'pedido' THEN
      NEW.aceite_em  := now();
      NEW.aceite_por := auth.uid();
      NEW.aceite_recusa_motivo := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.seller_id := auth.uid();
    IF coalesce(NEW.status, 'em_andamento') <> 'em_andamento' THEN
      RAISE EXCEPTION 'Proposta nova começa em andamento.';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status NOT IN ('em_andamento','aguardando_aceite') THEN
    RAISE EXCEPTION 'Este pedido já foi aceito pelo escritório — alterações passam pelo escritório.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'em_andamento'      AND NEW.status IN ('aguardando_aceite','cancelada'))
    OR (OLD.status = 'aguardando_aceite' AND NEW.status IN ('em_andamento','cancelada'))
  ) THEN
    RAISE EXCEPTION 'Vendedor externo não pode passar para "%": o pedido precisa do aceite do escritório.', NEW.status;
  END IF;
  IF NEW.status = 'aguardando_aceite' AND OLD.status <> 'aguardando_aceite' THEN
    NEW.aceite_solicitado_em  := now();
    NEW.aceite_solicitado_por := auth.uid();
    NEW.aceite_recusa_motivo  := NULL;
  END IF;
  -- campos que só o escritório escreve
  NEW.seller_id      := OLD.seller_id;
  NEW.pedido_numero  := OLD.pedido_numero;
  NEW.pedido_ano     := OLD.pedido_ano;
  NEW.nf_numero      := OLD.nf_numero;
  NEW.transportadora := OLD.transportadora;
  NEW.aceite_em      := OLD.aceite_em;
  NEW.aceite_por     := OLD.aceite_por;
  RETURN NEW;
END $$;

-- "tg_aa_" ordena antes de "tg_atribui_numero_pedido": a guarda roda primeiro.
DROP TRIGGER IF EXISTS tg_aa_guarda_externo ON public.proposals;
CREATE TRIGGER tg_aa_guarda_externo BEFORE INSERT OR UPDATE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.proposals_guarda_externo();

COMMIT;

-- CONFERÊNCIA DO BLOCO 2 (deve listar os 5 status e 1 trigger):
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'proposals_status_check';
-- SELECT tgname FROM pg_trigger WHERE tgname = 'tg_aa_guarda_externo';


-- =========================================================================
-- BLOCO 3 — guarda em companies + RPCs (pedido de acesso, decisão, produtos)
-- =========================================================================
BEGIN;

-- 3a) Externo cadastra empresa SEMPRE como dele e não troca o responsável.
CREATE OR REPLACE FUNCTION public.companies_guarda_externo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_externo() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.vendedor_responsavel_id   := auth.uid();
    NEW.vendedor_responsavel_nome := (SELECT name FROM public.profiles WHERE id = auth.uid());
    NEW.created_by                := auth.uid();
  ELSE
    NEW.vendedor_responsavel_id   := OLD.vendedor_responsavel_id;
    NEW.vendedor_responsavel_nome := OLD.vendedor_responsavel_nome;
    NEW.created_by                := OLD.created_by;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tg_aa_guarda_externo ON public.companies;
CREATE TRIGGER tg_aa_guarda_externo BEFORE INSERT OR UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.companies_guarda_externo();

-- 3b) Externo informa um CNPJ. Compara só os DÍGITOS (o banco guarda com e
--     sem máscara). Devolve um código, nunca o nome nem o dono da empresa:
--       'livre'           não existe, pode cadastrar
--       'ja_tem_acesso'   já é dele
--       'solicitado'      existia: pedido de acesso aberto pro escritório
--       'ja_solicitado'   já havia um pedido pendente
CREATE OR REPLACE FUNCTION public.externo_checa_cnpj(p_cnpj text, p_razao text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_dig text; v_company uuid;
BEGIN
  IF NOT public.is_externo() THEN RETURN 'livre'; END IF;
  IF NOT public.sessao_com_2fa() THEN RAISE EXCEPTION 'Ative o 2FA para continuar.'; END IF;
  v_dig := regexp_replace(coalesce(p_cnpj, ''), '\D', '', 'g');
  IF length(v_dig) < 11 THEN RETURN 'livre'; END IF;

  SELECT id INTO v_company FROM public.companies
   WHERE org_id = public.current_org()
     AND regexp_replace(coalesce(cnpj, ''), '\D', '', 'g') = v_dig
   LIMIT 1;
  IF v_company IS NULL THEN RETURN 'livre'; END IF;
  IF public.alcanca_empresa(v_company) THEN RETURN 'ja_tem_acesso'; END IF;

  BEGIN
    INSERT INTO public.company_access_requests (company_id, requester_id, cnpj_digitado, razao_digitada)
    VALUES (v_company, auth.uid(), p_cnpj, p_razao);
  EXCEPTION WHEN unique_violation THEN
    RETURN 'ja_solicitado';
  END;
  RETURN 'solicitado';
END $$;

-- 3c) Escritório decide. Aprovar = criar o company_access, na mesma transação.
CREATE OR REPLACE FUNCTION public.decidir_acesso(p_req uuid, p_aprovar boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.company_access_requests%ROWTYPE;
BEGIN
  IF public.is_externo() OR public.is_leitor() THEN
    RAISE EXCEPTION 'Só o escritório decide pedidos de acesso.';
  END IF;
  SELECT * INTO r FROM public.company_access_requests
   WHERE id = p_req AND org_id = public.current_org() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido não encontrado.'; END IF;
  IF r.status <> 'pendente' THEN RETURN r.status; END IF;

  UPDATE public.company_access_requests
     SET status = CASE WHEN p_aprovar THEN 'aprovado' ELSE 'recusado' END,
         decided_by = auth.uid(), decided_at = now()
   WHERE id = p_req;
  IF p_aprovar THEN
    INSERT INTO public.company_access (org_id, company_id, profile_id, granted_by)
    VALUES (r.org_id, r.company_id, r.requester_id, auth.uid())
    ON CONFLICT (company_id, profile_id) DO NOTHING;
  END IF;
  RETURN CASE WHEN p_aprovar THEN 'aprovado' ELSE 'recusado' END;
END $$;

-- 3d) Catálogo para venda. RLS filtra LINHA, não coluna: dar SELECT em
--     products ao externo entregaria preco_materia_prima (custo interno).
--     Ele lê por aqui, que só devolve as colunas de venda.
CREATE OR REPLACE FUNCTION public.produtos_venda()
RETURNS TABLE (id uuid, nome text, embalagem text, preco_office numeric, preco_pj numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT p.id, p.nome, p.embalagem, p.preco_office::numeric, p.preco_pj::numeric
    FROM public.products p
   WHERE p.org_id = public.current_org()
     AND (NOT public.is_externo() OR public.sessao_com_2fa())
   ORDER BY p.nome, p.embalagem;
$$;

GRANT EXECUTE ON FUNCTION public.externo_checa_cnpj(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decidir_acesso(uuid, boolean)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.produtos_venda()               TO authenticated;

COMMIT;

-- CONFERÊNCIA DO BLOCO 3 (logado como admin no SQL Editor auth.uid() é NULL,
-- então só confira que existem — 4 linhas):
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('companies_guarda_externo','externo_checa_cnpj','decidir_acesso','produtos_venda') ORDER BY 1;


-- =========================================================================
-- BLOCO 4 — POLICIES. É ESTE que muda comportamento.
-- Para quem não é externo, cada policy fica EQUIVALENTE à da 91f: o termo
-- novo é `NOT (SELECT is_externo()) OR ...`, verdadeiro para todo interno.
-- `(SELECT ...)` vira initplan: avaliado uma vez por consulta, não por linha.
-- =========================================================================
BEGIN;

-- companies — inline (não via alcanca_empresa) para o INSERT ... RETURNING
-- do próprio cadastro enxergar a linha recém-criada.
DROP POLICY IF EXISTS "companies_select"       ON public.companies;
DROP POLICY IF EXISTS "companies_insert"       ON public.companies;
DROP POLICY IF EXISTS "companies_update_owner" ON public.companies;
DROP POLICY IF EXISTS "companies_delete_owner" ON public.companies;
CREATE POLICY "companies_select" ON public.companies FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND (
    NOT (SELECT public.is_externo())
    OR ((SELECT public.sessao_com_2fa()) AND (
         vendedor_responsavel_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.company_access a
                     WHERE a.company_id = companies.id AND a.profile_id = auth.uid())))));
CREATE POLICY "companies_insert" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo())
                   OR ((SELECT public.sessao_com_2fa()) AND vendedor_responsavel_id = auth.uid())));
CREATE POLICY "companies_update_owner" ON public.companies FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND public.alcanca_empresa(id))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
              AND public.alcanca_empresa(id));
-- excluir empresa (e o fluxo LGPD) fica com o escritório
CREATE POLICY "companies_delete_owner" ON public.companies FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND NOT (SELECT public.is_externo()));

-- contacts
DROP POLICY IF EXISTS "contacts_select" ON public.contacts;
DROP POLICY IF EXISTS "contacts_write"  ON public.contacts;
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "contacts_write" ON public.contacts FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- opportunities
DROP POLICY IF EXISTS "opportunities_select" ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_write"  ON public.opportunities;
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "opportunities_write" ON public.opportunities FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- opportunity_products
DROP POLICY IF EXISTS "opp_products_select" ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_write"  ON public.opportunity_products;
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));
CREATE POLICY "opp_products_write" ON public.opportunity_products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));

-- interactions
DROP POLICY IF EXISTS "interactions_select" ON public.interactions;
DROP POLICY IF EXISTS "interactions_write"  ON public.interactions;
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));
CREATE POLICY "interactions_write" ON public.interactions FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));

-- proposals — inline pelo mesmo motivo de companies (INSERT ... RETURNING)
DROP POLICY IF EXISTS "proposals_select"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_insert"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_delete"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_update_status" ON public.proposals;
CREATE POLICY "proposals_select" ON public.proposals FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND (
    NOT (SELECT public.is_externo())
    OR ((SELECT public.sessao_com_2fa()) AND CASE
          WHEN company_id IS NULL THEN seller_id = auth.uid()
          ELSE public.alcanca_empresa(company_id) END)));
CREATE POLICY "proposals_insert" ON public.proposals FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "proposals_delete" ON public.proposals FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND public.is_admin());
CREATE POLICY "proposals_update_status" ON public.proposals FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- proposal_revisions (continua só SELECT + INSERT — histórico não se reescreve)
DROP POLICY IF EXISTS "prop_rev_select" ON public.proposal_revisions;
DROP POLICY IF EXISTS "prop_rev_insert" ON public.proposal_revisions;
CREATE POLICY "prop_rev_select" ON public.proposal_revisions FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "prop_rev_insert" ON public.proposal_revisions FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));

-- attachments (metadado)
DROP POLICY IF EXISTS "anexos_select" ON public.attachments;
DROP POLICY IF EXISTS "anexos_insert" ON public.attachments;
DROP POLICY IF EXISTS "anexos_delete" ON public.attachments;
CREATE POLICY "anexos_select" ON public.attachments FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "anexos_insert" ON public.attachments FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "anexos_delete" ON public.attachments FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));

-- tasks — externo vê só as próprias (interno continua vendo as da org)
DROP POLICY IF EXISTS "tasks_select"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_own" ON public.tasks;
DROP POLICY IF EXISTS "tasks_delete_own" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo())
              OR ((SELECT public.sessao_com_2fa()) AND seller_id = auth.uid())));
CREATE POLICY "tasks_insert" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (seller_id = auth.uid() OR public.is_admin())
              AND (NOT (SELECT public.is_externo())
                   OR company_id IS NULL OR public.alcanca_empresa(company_id)));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid())
              AND (NOT (SELECT public.is_externo())
                   OR company_id IS NULL OR public.alcanca_empresa(company_id)));
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));

-- products — externo NÃO lê a tabela (tem o custo); lê produtos_venda()
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND NOT (SELECT public.is_externo()));

-- audit_log — guarda old_data/new_data de TUDO: externo só das empresas dele
DROP POLICY IF EXISTS "audit_select" ON public.audit_log;
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo())
              OR (company_id IS NOT NULL AND public.alcanca_empresa(company_id))));

-- lgpd_requests
DROP POLICY IF EXISTS "lgpd_select" ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_insert" ON public.lgpd_requests;
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CONFERÊNCIA DO BLOCO 4 — rode separado. Deve devolver 0: nenhuma policy
-- das tabelas tocadas ficou sem o termo de externo (exceto as listadas).
-- SELECT tablename, policyname FROM pg_policies
--  WHERE schemaname = 'public'
--    AND tablename IN ('companies','contacts','opportunities','opportunity_products',
--                      'interactions','proposals','proposal_revisions','attachments',
--                      'tasks','products','audit_log','lgpd_requests')
--    AND coalesce(qual,'') || coalesce(with_check,'') NOT ILIKE '%externo%'
--    AND policyname NOT IN ('proposals_delete','tasks_delete_own','audit_insert','products_write');
-- E depois: ABRA O APP como admin e como vendedor. Empresas, Pipeline,
-- Propostas e Dashboard devem estar exatamente como antes.


-- =========================================================================
-- BLOCO 5 — Storage dos anexos + view companies_with_tier
-- =========================================================================
BEGIN;

-- O caminho é {org_id}/proposals/{proposal_id}/{arquivo}: a pasta [3] é a
-- proposta. Sem isto o externo abriria a OC assinada de cliente alheio
-- sabendo (ou adivinhando) o caminho.
CREATE OR REPLACE FUNCTION public.alcanca_anexo(p_name text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_pasta text;
BEGIN
  IF NOT public.is_externo() THEN RETURN true; END IF;
  v_pasta := (storage.foldername(p_name))[3];
  IF v_pasta IS NULL OR v_pasta !~ '^[0-9a-f-]{36}$' THEN RETURN false; END IF;
  RETURN public.alcanca_proposta(v_pasta::uuid);
END $$;
GRANT EXECUTE ON FUNCTION public.alcanca_anexo(text) TO authenticated;

DROP POLICY IF EXISTS "anexos_obj_select" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_insert" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_delete" ON storage.objects;
CREATE POLICY "anexos_obj_select" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text
         AND public.alcanca_anexo(name));
CREATE POLICY "anexos_obj_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'anexos'
              AND (storage.foldername(name))[1] = public.current_org()::text
              AND NOT public.is_leitor()
              AND public.alcanca_anexo(name));
CREATE POLICY "anexos_obj_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text
         AND public.alcanca_anexo(name));

-- A view foi criada sem security_invoker: roda com o dono (postgres) e
-- IGNORA o RLS de companies. O app só a usa no checkSchema, mas pela API
-- qualquer usuário logado leria a lista inteira com valor de pipeline.
-- Exige Postgres 15+ (Bloco 0a).
ALTER VIEW public.companies_with_tier SET (security_invoker = true);

COMMIT;

-- CONFERÊNCIA DO BLOCO 5 (deve devolver 3 policies e 'security_invoker=true'):
-- SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE 'anexos_obj_%';
-- SELECT reloptions FROM pg_class WHERE relname = 'companies_with_tier';


-- =========================================================================
-- DEPOIS DE TUDO — criar o primeiro externo (conta de TESTE antes da real)
-- =========================================================================
-- 1) Supabase > Authentication > Users > Add user (Auto Confirm).
-- 2) No app, aba Equipe, troque o papel dele para "Externo".
--    (ou: UPDATE public.profiles SET role = 'externo' WHERE email = '...';)
-- 3) Entre com ele: o app exige cadastrar o 2FA antes de mostrar qualquer coisa.
-- 4) CHECKLIST de isolamento — logado como o externo de teste:
--    a) Empresas: só as que têm ele como responsável (ou acesso dado).
--    b) Console: await api('GET','products','select=preco_materia_prima&limit=1')  → []
--    c) Console: await api('GET','audit_log','select=id&limit=5')                   → só das empresas dele
--    d) Console: await api('GET','companies_with_tier','select=id')                 → só as dele
--    e) Marcar proposta como pedido → fica "Aguardando aceite", sem nº de pedido.
--    f) Console: await api('PATCH','proposals','id=eq.<id>',{status:'pedido'})     → erro de aceite
--    g) Cadastrar empresa com CNPJ de cliente de outro vendedor → aviso de acesso solicitado.
-- =========================================================================
