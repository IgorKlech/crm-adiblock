-- =========================================================================
-- VENDEDOR EXTERNO — PASSO 2 de 5: guarda do cadastro de empresa + funções de acesso
-- =========================================================================
-- Não muda nada para quem já usa o CRM.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- A última linha do resultado diz OK ou ERRO. Só siga para o próximo passo com OK.
-- Origem: 2026-10-05-vendedor-externo.sql (o mesmo SQL, fatiado).
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

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN n = 2 THEN 'OK — pode seguir'
            ELSE 'ERRO: esperado 2, veio ' || n || ' — NÃO siga, mande o print' END AS passo_2
  FROM (SELECT count(*) FROM pg_trigger WHERE tgname='tg_aa_guarda_externo') t(n);
