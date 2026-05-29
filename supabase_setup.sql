-- =========================================================================
-- CRM Adiblock — Setup completo (Sprint 3: modelo B2B)
-- Empresa → Contatos → Oportunidades, com tier automático
-- =========================================================================
--
-- ⚠  Atenção: este script APAGA todos os dados de clientes/contatos/
-- propostas antigos para começar do zero no novo modelo B2B.
-- Catálogo de produtos e perfis de usuários são preservados.
--
-- ✓ O JS está sincronizado (Sprint 3.2). Pode rodar com segurança.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 0) Profiles (vendedores) — preservados, só garante colunas
-- -------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS seller_status      text DEFAULT 'Disponível',
  ADD COLUMN IF NOT EXISTS telefone           text,
  ADD COLUMN IF NOT EXISTS office_nome        text,
  ADD COLUMN IF NOT EXISTS office_email       text,
  ADD COLUMN IF NOT EXISTS office_telefone    text;

-- Sprint 5.1: garante valores válidos pro campo role (admin/vendedor/leitor)
-- O default fica 'vendedor' pra novos usuários criados via trigger handle_new_user
DO $$ BEGIN
  ALTER TABLE public.profiles
    ALTER COLUMN role SET DEFAULT 'vendedor';
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- Atualiza valores legados (admin/Admin/etc.) pra valores canônicos
UPDATE public.profiles SET role = 'admin'    WHERE lower(role) IN ('admin','administrador');
UPDATE public.profiles SET role = 'vendedor' WHERE role IS NULL OR lower(role) NOT IN ('admin','vendedor','leitor');

-- Função helper: retorna o role do usuário logado
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE(role, 'vendedor') FROM public.profiles WHERE id = auth.uid();
$$;

-- Função helper: é admin?
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT public.current_user_role() = 'admin';
$$;

-- Função helper: é leitor (read-only)?
CREATE OR REPLACE FUNCTION public.is_leitor()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT public.current_user_role() = 'leitor';
$$;

GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_leitor() TO authenticated;

-- RLS de profiles: todos veem, cada um edita o próprio, admin edita qualquer um
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_select"      ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_self" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin"ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_admin"ON public.profiles;
CREATE POLICY "profiles_select"      ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid() AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));
-- Nota: a policy update_self proíbe usuário comum de mudar PRÓPRIO role
CREATE POLICY "profiles_update_admin" ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "profiles_delete_admin" ON public.profiles FOR DELETE TO authenticated
  USING (public.is_admin());


-- -------------------------------------------------------------------------
-- 1) DROP do modelo antigo (clients + tabelas dependentes)
-- -------------------------------------------------------------------------
-- Remove tabelas antigas do realtime antes de dropar (evita lock)
DO $$ BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.clients;         EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.client_products; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.call_history;    EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.proposals;       EXCEPTION WHEN OTHERS THEN NULL; END $$;

DROP TABLE IF EXISTS public.lgpd_requests    CASCADE;
DROP TABLE IF EXISTS public.client_products  CASCADE;
DROP TABLE IF EXISTS public.call_history     CASCADE;
DROP TABLE IF EXISTS public.proposals        CASCADE;
DROP TABLE IF EXISTS public.clients          CASCADE;
DROP VIEW  IF EXISTS public.companies_with_tier;


-- -------------------------------------------------------------------------
-- 2) companies — empresa B2B (substitui clients)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  razao_social             text NOT NULL,
  nome_fantasia            text,
  cnpj                     text,
  ie                       text,
  email                    text,
  telefone                 text,
  website                  text,
  industria                text,        -- ex: "Construtora", "Pré-fabricado", "Indústria química"
  faturamento_estimado     numeric(14,2),
  endereco                 text,
  cidade                   text,
  uf                       text,
  cep                      text,
  observacoes              text,
  internal_notes           text,
  -- LGPD
  lgpd_consent_at          timestamptz,
  lgpd_consent_by          text,
  lgpd_delete_requested_at timestamptz,
  lgpd_delete_requested_by text,
  -- Audit
  created_by               uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cnpj)
);

CREATE INDEX IF NOT EXISTS idx_companies_razao_social ON public.companies(razao_social);
CREATE INDEX IF NOT EXISTS idx_companies_cidade_uf    ON public.companies(cidade, uf);

-- Sprint 4.1: classificação manual escolhida pelo vendedor (paralela ao tier auto)
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS classificacao text;
-- Valores aceitos: 'lead_novo','prospect','cliente_ativo','inativo','indicacao' (text livre por flexibilidade)
CREATE INDEX IF NOT EXISTS idx_companies_classificacao ON public.companies(classificacao);

-- Sprint 6 (campo pedido apos auditoria): vendedor responsavel pela empresa
-- (independente das oportunidades — segue a empresa mesmo quando nao ha opp aberta)
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS vendedor_responsavel_id   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS vendedor_responsavel_nome text;  -- denormalizado pra display rapido sem join
CREATE INDEX IF NOT EXISTS idx_companies_vendedor_responsavel_id ON public.companies(vendedor_responsavel_id);

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
-- Sprint 5.1: RLS granular por role
DROP POLICY IF EXISTS "auth_all_companies"      ON public.companies;
DROP POLICY IF EXISTS "companies_select"        ON public.companies;
DROP POLICY IF EXISTS "companies_insert"        ON public.companies;
DROP POLICY IF EXISTS "companies_update_owner"  ON public.companies;
DROP POLICY IF EXISTS "companies_delete_owner"  ON public.companies;
-- SELECT: todos autenticados leem (transparência interna)
CREATE POLICY "companies_select" ON public.companies
  FOR SELECT TO authenticated USING (true);
-- INSERT: admin e vendedor podem criar (leitor não)
CREATE POLICY "companies_insert" ON public.companies
  FOR INSERT TO authenticated WITH CHECK (NOT public.is_leitor());
-- UPDATE: admin ou owner (created_by)
CREATE POLICY "companies_update_owner" ON public.companies
  FOR UPDATE TO authenticated
  USING (public.is_admin() OR created_by = auth.uid())
  WITH CHECK (public.is_admin() OR created_by = auth.uid());
-- DELETE: admin ou owner
CREATE POLICY "companies_delete_owner" ON public.companies
  FOR DELETE TO authenticated
  USING (public.is_admin() OR created_by = auth.uid());


-- -------------------------------------------------------------------------
-- 3) contacts — pessoas dentro de uma empresa (N por empresa)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contacts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  nome        text NOT NULL,
  cargo       text,
  email       text,
  telefone    text,
  papel       text CHECK (papel IN ('comprador','decisor','tecnico','engenheiro','financeiro','outro')),
  principal   boolean NOT NULL DEFAULT false,
  observacoes text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contacts_company_id ON public.contacts(company_id);

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_contacts"  ON public.contacts;
DROP POLICY IF EXISTS "contacts_select"    ON public.contacts;
DROP POLICY IF EXISTS "contacts_write"     ON public.contacts;
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated USING (true);
CREATE POLICY "contacts_write"  ON public.contacts FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());


-- -------------------------------------------------------------------------
-- 4) opportunities — negociações ativas (N por empresa)
--    Estágios do funil B2B: Lead → Qualificado → Proposta → Negociação → Ganha/Perdida
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.opportunities (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  contact_id          uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  seller_id           uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  seller_name         text,
  titulo              text NOT NULL,         -- ex: "Aditivo p/ obra Mirataia"
  obra                text,                  -- nome/identificação da obra
  estagio             text NOT NULL DEFAULT 'lead' CHECK (estagio IN ('lead','qualificado','proposta_enviada','em_negociacao','ganha','perdida')),
  valor_estimado      numeric(12,2),
  callback_date       date,
  perda_motivo        text,
  observation         text,
  estagio_changed_at  timestamptz DEFAULT now(),
  closed_at           timestamptz,           -- preenchido quando estagio = ganha/perdida
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_opportunities_company_id ON public.opportunities(company_id);
CREATE INDEX IF NOT EXISTS idx_opportunities_seller_id  ON public.opportunities(seller_id);
CREATE INDEX IF NOT EXISTS idx_opportunities_estagio    ON public.opportunities(estagio);

-- Trigger: quando estágio vira ganha/perdida, marca closed_at automaticamente
CREATE OR REPLACE FUNCTION public.opportunity_estagio_changed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.estagio IS DISTINCT FROM OLD.estagio THEN
    NEW.estagio_changed_at = now();
    IF NEW.estagio IN ('ganha','perdida') AND OLD.estagio NOT IN ('ganha','perdida') THEN
      NEW.closed_at = now();
    ELSIF NEW.estagio NOT IN ('ganha','perdida') THEN
      NEW.closed_at = NULL;
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_opportunity_estagio_changed ON public.opportunities;
CREATE TRIGGER tg_opportunity_estagio_changed
  BEFORE UPDATE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.opportunity_estagio_changed();

ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_opportunities" ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_select"   ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_write"    ON public.opportunities;
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated USING (true);
CREATE POLICY "opportunities_write"  ON public.opportunities FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());


-- -------------------------------------------------------------------------
-- 5) opportunity_products — produtos de uma oportunidade
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.opportunity_products (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id  uuid NOT NULL REFERENCES public.opportunities(id) ON DELETE CASCADE,
  produto         text NOT NULL,
  embalagem       text,
  qtd_kg          numeric(12,2),
  preco_kg        numeric(10,2),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_opportunity_products_opp_id ON public.opportunity_products(opportunity_id);

ALTER TABLE public.opportunity_products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_opp_products"   ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_select"     ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_write"      ON public.opportunity_products;
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated USING (true);
CREATE POLICY "opp_products_write"  ON public.opportunity_products FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());


-- -------------------------------------------------------------------------
-- 6) interactions — histórico de contatos por oportunidade
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interactions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id  uuid NOT NULL REFERENCES public.opportunities(id) ON DELETE CASCADE,
  contact_id      uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  seller_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  datetime        timestamptz NOT NULL DEFAULT now(),
  result          text,
  next_callback   date,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_interactions_opp_id ON public.interactions(opportunity_id);

ALTER TABLE public.interactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_interactions" ON public.interactions;
DROP POLICY IF EXISTS "interactions_select"   ON public.interactions;
DROP POLICY IF EXISTS "interactions_write"    ON public.interactions;
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "interactions_write"  ON public.interactions FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());


-- -------------------------------------------------------------------------
-- 7) proposals — propostas comerciais (agora ligadas à oportunidade)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.proposals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ano             int  NOT NULL DEFAULT EXTRACT(YEAR FROM now())::int,
  numero          int  NOT NULL,
  opportunity_id  uuid REFERENCES public.opportunities(id) ON DELETE SET NULL,
  company_id      uuid REFERENCES public.companies(id) ON DELETE SET NULL, -- redundante p/ análise
  seller_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  snapshot        jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ano, numero)
);

CREATE INDEX IF NOT EXISTS idx_proposals_opp_id ON public.proposals(opportunity_id);
CREATE INDEX IF NOT EXISTS idx_proposals_company_id ON public.proposals(company_id);
CREATE INDEX IF NOT EXISTS idx_proposals_ano_numero ON public.proposals(ano, numero DESC);

-- Trigger: numeração sequencial atômica por ano (mesma lógica de antes)
CREATE OR REPLACE FUNCTION public.atribui_numero_proposta()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.numero IS NULL OR NEW.numero = 0 THEN
    PERFORM pg_advisory_xact_lock(hashtext('proposta_ano_' || NEW.ano));
    SELECT COALESCE(MAX(numero), 0) + 1 INTO NEW.numero
      FROM public.proposals WHERE ano = NEW.ano;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_atribui_numero_proposta ON public.proposals;
CREATE TRIGGER tg_atribui_numero_proposta
  BEFORE INSERT ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.atribui_numero_proposta();

ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;
-- Sprint 5.1: propostas geradas SO podem ser deletadas por admin (rastreabilidade)
DROP POLICY IF EXISTS "auth_all_proposals" ON public.proposals;
DROP POLICY IF EXISTS "proposals_select"   ON public.proposals;
DROP POLICY IF EXISTS "proposals_insert"   ON public.proposals;
DROP POLICY IF EXISTS "proposals_delete"   ON public.proposals;
CREATE POLICY "proposals_select" ON public.proposals FOR SELECT TO authenticated USING (true);
CREATE POLICY "proposals_insert" ON public.proposals FOR INSERT TO authenticated WITH CHECK (NOT public.is_leitor());
-- Propostas NÃO podem ser editadas (snapshot imutável) — somente admin pode deletar (correção de erro)
CREATE POLICY "proposals_delete" ON public.proposals FOR DELETE TO authenticated USING (public.is_admin());


-- -------------------------------------------------------------------------
-- 7b) audit_log — log imutavel de alteracoes (Sprint 5.2)
--     Trigger generico em companies/contacts/opportunities/opportunity_products
--     captura INSERT/UPDATE/DELETE com snapshot before/after em jsonb.
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name  text NOT NULL,
  row_id      uuid,
  action      text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  user_id     uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  user_name   text,
  user_role   text,
  old_data    jsonb,
  new_data    jsonb,
  changes     jsonb,             -- diff calculado: lista de {field, from, to}
  created_at  timestamptz NOT NULL DEFAULT now(),
  -- Atalho para filtrar histórico por empresa (sem FK: audit log sobrevive à exclusão)
  company_id  uuid
);

-- Migracao: se a tabela ja existe com FK, remove pra permitir DELETE em companies
ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_company_id_fkey;

CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_table_row  ON public.audit_log(table_name, row_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at DESC);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "audit_select" ON public.audit_log;
DROP POLICY IF EXISTS "audit_insert" ON public.audit_log;
-- SELECT: todos veem. INSERT: trigger faz com SECURITY DEFINER. NO UPDATE/DELETE: log imutavel.
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated USING (true);
CREATE POLICY "audit_insert" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (true);

-- Funcao trigger generica
CREATE OR REPLACE FUNCTION public.log_audit_changes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id    uuid;
  v_user_name  text;
  v_user_role  text;
  v_row_id     uuid;
  v_company_id uuid;
  v_old_jsonb  jsonb;
  v_new_jsonb  jsonb;
  v_changes    jsonb;
  k            text;
BEGIN
  v_user_id := auth.uid();
  SELECT name, role INTO v_user_name, v_user_role FROM public.profiles WHERE id = v_user_id;

  IF TG_OP = 'DELETE' THEN
    v_old_jsonb := to_jsonb(OLD);
    v_row_id := (v_old_jsonb->>'id')::uuid;
    v_company_id := COALESCE(
      NULLIF(v_old_jsonb->>'company_id','')::uuid,
      CASE WHEN TG_TABLE_NAME = 'companies' THEN v_row_id ELSE NULL END
    );
  ELSE
    v_new_jsonb := to_jsonb(NEW);
    v_row_id := (v_new_jsonb->>'id')::uuid;
    v_company_id := COALESCE(
      NULLIF(v_new_jsonb->>'company_id','')::uuid,
      CASE WHEN TG_TABLE_NAME = 'companies' THEN v_row_id ELSE NULL END
    );
    IF TG_OP = 'UPDATE' THEN
      v_old_jsonb := to_jsonb(OLD);
      -- Calcula diff campo-a-campo (ignora updated_at/estagio_changed_at que mudam sozinhos)
      v_changes := '[]'::jsonb;
      FOR k IN SELECT jsonb_object_keys(v_new_jsonb) LOOP
        IF k IN ('updated_at','estagio_changed_at','closed_at') THEN CONTINUE; END IF;
        IF (v_new_jsonb->k) IS DISTINCT FROM (v_old_jsonb->k) THEN
          v_changes := v_changes || jsonb_build_array(jsonb_build_object('field', k, 'from', v_old_jsonb->k, 'to', v_new_jsonb->k));
        END IF;
      END LOOP;
      -- Se nada mudou (só timestamps), nao loga
      IF jsonb_array_length(v_changes) = 0 THEN RETURN NEW; END IF;
    END IF;
  END IF;

  INSERT INTO public.audit_log (table_name, row_id, action, user_id, user_name, user_role, old_data, new_data, changes, company_id)
  VALUES (TG_TABLE_NAME, v_row_id, TG_OP, v_user_id, v_user_name, v_user_role, v_old_jsonb, v_new_jsonb, v_changes, v_company_id);

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- Aplica em todas as tabelas críticas
DROP TRIGGER IF EXISTS tg_audit_companies            ON public.companies;
DROP TRIGGER IF EXISTS tg_audit_contacts             ON public.contacts;
DROP TRIGGER IF EXISTS tg_audit_opportunities        ON public.opportunities;
DROP TRIGGER IF EXISTS tg_audit_opportunity_products ON public.opportunity_products;
DROP TRIGGER IF EXISTS tg_audit_proposals            ON public.proposals;

CREATE TRIGGER tg_audit_companies
  AFTER INSERT OR UPDATE OR DELETE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();
CREATE TRIGGER tg_audit_contacts
  AFTER INSERT OR UPDATE OR DELETE ON public.contacts
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();
CREATE TRIGGER tg_audit_opportunities
  AFTER INSERT OR UPDATE OR DELETE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();
CREATE TRIGGER tg_audit_opportunity_products
  AFTER INSERT OR UPDATE OR DELETE ON public.opportunity_products
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();
CREATE TRIGGER tg_audit_proposals
  AFTER INSERT OR UPDATE OR DELETE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.log_audit_changes();


-- -------------------------------------------------------------------------
-- 8) lgpd_requests — log de ações LGPD (agora liga a empresa)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.lgpd_requests (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  company_name      text NOT NULL,
  acao              text NOT NULL CHECK (acao IN ('consentimento','exclusao_solicitada','exclusao_executada','revogacao_consentimento')),
  detalhes          text,
  requested_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  requested_by_name text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lgpd_requests_company_id ON public.lgpd_requests(company_id);

ALTER TABLE public.lgpd_requests ENABLE ROW LEVEL SECURITY;
-- Sprint 5.1: log LGPD imutável (todos veem, qualquer um insere, NINGUÉM edita/deleta)
DROP POLICY IF EXISTS "auth_all_lgpd"      ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_select"        ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_insert"        ON public.lgpd_requests;
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated USING (true);
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated WITH CHECK (true);


-- -------------------------------------------------------------------------
-- 9) View companies_with_tier — calcula tier automático
--    Lead: 0 oportunidades ganhas
--    Cliente: 1+ ganhas em qualquer época
--    Conta: 3+ ganhas nos últimos 12 meses
-- -------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.companies_with_tier AS
SELECT
  c.*,
  COALESCE(s.opps_total,        0) AS opps_total,
  COALESCE(s.opps_abertas,      0) AS opps_abertas,
  COALESCE(s.opps_ganhas,       0) AS opps_ganhas_total,
  COALESCE(s.opps_ganhas_12m,   0) AS opps_ganhas_12m,
  COALESCE(s.valor_pipeline,    0) AS valor_pipeline,
  CASE
    WHEN COALESCE(s.opps_ganhas_12m, 0) >= 3 THEN 'conta'
    WHEN COALESCE(s.opps_ganhas,     0) >= 1 THEN 'cliente'
    ELSE 'lead'
  END AS tier
FROM public.companies c
LEFT JOIN (
  SELECT
    company_id,
    COUNT(*)                                                                       AS opps_total,
    COUNT(*) FILTER (WHERE estagio NOT IN ('ganha','perdida'))                     AS opps_abertas,
    COUNT(*) FILTER (WHERE estagio = 'ganha')                                      AS opps_ganhas,
    COUNT(*) FILTER (WHERE estagio = 'ganha' AND closed_at >= now() - interval '12 months') AS opps_ganhas_12m,
    SUM(valor_estimado) FILTER (WHERE estagio NOT IN ('ganha','perdida'))          AS valor_pipeline
  FROM public.opportunities
  GROUP BY company_id
) s ON s.company_id = c.id;


-- -------------------------------------------------------------------------
-- 10) products — catálogo Tabela de Preços 2025 (preservado, recria se faltar)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                 text NOT NULL,
  embalagem            text NOT NULL,
  preco_materia_prima  numeric(10,3) NOT NULL,
  preco_office         numeric(10,2) NOT NULL,
  preco_pj             numeric(10,2) NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (nome, embalagem)
);

CREATE INDEX IF NOT EXISTS idx_products_nome ON public.products(nome);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
-- Sprint 5.1: catálogo é lido por todos, mas só admin altera preços/produtos
DROP POLICY IF EXISTS "auth_read_products" ON public.products;
DROP POLICY IF EXISTS "products_select"    ON public.products;
DROP POLICY IF EXISTS "products_write"     ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_write"  ON public.products FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Seed do catálogo (re-runnable via ON CONFLICT). Só insere se ainda não houver.
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES
('ACCELIK AS','Bombona 20',1.492,6.98,7.12),
('ACCELIK AS','Bombona 50',1.492,6.68,6.82),
('ACCELIK AS','Tambor',1.492,6.24,6.38),
('ACCELIK AS','CNT',1.492,6.42,6.56),
('ACCELIK SF','Bombona 20',2.923,10.61,10.75),
('ACCELIK SF','Bombona 50',2.923,10.31,10.45),
('ACCELIK SF','Tambor',2.923,9.87,10.01),
('ACCELIK SF','CNT',2.923,10.04,10.19),
('ACCETIVE FC POWDER','Saco 20',3.708,11.09,11.23),
('ACEPESS FAST','Bombona 20',2.923,10.61,10.75),
('ACEPESS FAST','Bombona 50',2.923,10.31,10.45),
('ACEPESS FAST','Tambor',2.923,9.87,10.01),
('ACEPESS FAST','CNT',2.923,10.04,10.19),
('ACS 800','Bombona 20',1.250,6.37,6.51),
('ACS 800','Bombona 50',1.250,6.07,6.21),
('ACS 800','Tambor',1.250,5.63,5.77),
('ACS 800','CNT',1.250,5.80,5.95),
('ADIGROUT AR','Saco 25',0.840,3.82,3.97),
('ADIGROUT AR COMPLETE','Saco 25',0.585,3.18,3.32),
('ADIGROUT MC','Saco 25',1.688,5.97,6.12),
('ADIGROUT MIX','Saco 10',8.000,21.97,22.11),
('ADIGROUT MIX CONCRETE','Saco 10',8.400,22.98,23.12),
('ADIGROUT TIX','Saco 25',0.787,3.72,3.86),
('ADIGROUT UFR','Saco 25',1.992,6.74,6.89),
('ADIGROUT WHITE','Saco 25',2.511,8.06,8.20),
('ADIPOX','Conjunto',3.500,20.38,20.52),
('AGRECON POWDER','Saco 8',50.000,128.39,128.53),
('ARGAPOL 592 IC Conjunto','Conjunto',0.950,6.00,6.14),
('ARGAPOL 992 Conjunto','Conjunto',2.750,10.56,10.70),
('ARGAPOL BC Conjunto','Conjunto',1.200,6.63,6.77),
('ARGAPOL MRI','Saco 20',1.200,4.74,4.88),
('ARGAPOL RE 642','Saco 25',0.631,3.32,3.47),
('CEPAS INJECT','Saco 20',2.500,8.03,8.17),
('CEPAS INJECT BC','Saco 30',3.500,10.56,10.71),
('CI 900','Bombona 20',2.456,9.43,9.57),
('CI 900','Bombona 50',2.456,9.12,9.27),
('CI 900','Tambor',2.456,8.68,8.82),
('CI 900','CNT',2.456,8.86,9.00),
('CURE CA','Bombona 20',2.761,10.20,10.34),
('CURE CA','Bombona 50',2.761,9.90,10.04),
('CURE CA','Tambor',2.761,9.45,9.60),
('CURE CA','CNT',2.761,9.63,9.77),
('DRAMOR POWDER','Saco 20',5.702,16.14,16.29),
('EDIMPER M','Bombona 20',5.753,17.78,17.92),
('EDIMPER M','Bombona 50',5.753,17.48,17.62),
('EDIMPER M','Tambor',5.753,17.04,17.18),
('EDIMPER M','CNT',5.753,17.21,17.36),
('EDIMPER PLUS','Bombona 20',9.092,26.24,26.38),
('EDIMPER PLUS','Bombona 50',9.092,25.94,26.08),
('EDIMPER PLUS','Tambor',9.092,25.50,25.64),
('EDIMPER PLUS','CNT',9.092,25.67,25.82),
('EXPANDER 2019','Saco 10',2.350,7.77,7.92),
('EXPANFLUID IC','Saco 10',5.670,16.19,16.33),
('FASTER','Bombona 20',1.190,6.22,6.36),
('FASTER','Bombona 50',1.190,5.91,6.06),
('FASTER','Tambor',1.190,5.47,5.62),
('FASTER','CNT',1.190,5.65,5.79),
('FLUXYGROUT HMR CONJUNTO','Conjunto',22.000,65.95,66.09),
('FLUXYGROUT SOFT CONJUNTO','Conjunto',17.000,53.28,53.42),
('HYDROFLEX S A','Bombona 20',3.381,11.77,11.91),
('HYDROFLEX S A','Bombona 50',3.381,11.47,11.61),
('HYDROFLEX S A','Tambor',3.381,11.02,11.17),
('HYDROFLEX S A','CNT',3.381,11.20,11.35),
('HYDROFLEX SEL','Bombona 20',6.260,19.06,19.21),
('HYDROFLEX SEL','Bombona 50',6.260,18.76,18.90),
('HYDROFLEX RR','Bombona 20',30.000,79.22,79.36),
('HYDROFLEX RR','Bombona 50',30.000,78.92,79.06),
('HYDROFLEX RR','Tambor',30.000,78.48,78.62),
('HYDROFLEX RR','CNT',30.000,78.65,78.80),
('HYDROFLEX RS','Bombona 20',4.427,14.42,14.56),
('HYDROFLEX RS','Bombona 50',4.427,14.12,14.26),
('HYDROFLEX RS','Tambor',4.427,13.68,13.82),
('HYDROFLEX RS','CNT',4.427,13.85,14.00),
('HYDROFLEX S','Bombona 20',19.799,53.37,53.51),
('HYDROFLEX S','Bombona 50',19.799,53.07,53.21),
('HYDROFLEX S','Tambor',19.799,52.63,52.77),
('HYDROFLEX S','CNT',19.799,52.80,52.95),
('HYDROFLEX V2','Bombona 20',5.817,17.94,18.08),
('HYDROFLEX V2','Bombona 50',5.817,17.64,17.78),
('INCORPOR BS PLUS','Bombona 20',3.189,11.28,11.43),
('INCORPOR BS PLUS','Bombona 50',3.189,10.98,11.12),
('INCORPOR BS PLUS','Tambor',3.189,10.54,10.68),
('INCORPOR BS PLUS','CNT',3.189,10.72,10.86),
('INCORPOR BS-D','Bombona 20',1.602,7.26,7.41),
('INCORPOR BS-D','Bombona 50',1.602,6.96,7.10),
('INCORPOR BS-D','Tambor',1.602,6.52,6.66),
('INCORPOR BS-D','CNT',1.602,6.70,6.84),
('KOLA','Bombona 20',2.015,8.31,8.45),
('KOLA','Bombona 50',2.015,8.00,8.15),
('KOLA','Tambor',2.015,7.56,7.71),
('KOLA','CNT',2.015,7.74,7.88),
('KOLA PLUS TIX','Bombona 20',8.218,24.02,24.17),
('KOLA PLUS TIX','Bombona 50',8.218,23.72,23.87),
('KOLA PLUS TIX','Tambor',8.218,23.28,23.42),
('KOLA PLUS TIX','CNT',8.218,23.46,23.60),
('KOLA PVA','Bombona 20',1.087,5.96,6.10),
('KOLA PVA','Bombona 50',1.087,5.65,5.80),
('KOLA PVA','Tambor',1.087,5.21,5.35),
('KOLA SBR','Bombona 20',4.145,13.70,13.85),
('KOLA SBR','Bombona 50',4.145,13.40,13.54),
('KOLA SBR','Tambor',4.145,12.96,13.10),
('KOLA SBR','CNT',4.145,13.14,13.28),
('KOLA SUPER','Bombona 20',8.218,24.02,24.17),
('KOLA SUPER','Bombona 50',8.218,23.72,23.87),
('KOLA SUPER','Tambor',8.218,23.28,23.42),
('KOLA SUPER','CNT',8.218,23.46,23.60),
('LIKTIVE ACEP UF','Bombona 25',2.725,10.88,10.25),
('LIKTIVE ACEP UF','Bombona 60',2.725,9.81,9.95),
('LIKTIVE ACEP UF','Tambor',2.725,9.36,9.51),
('MINERAL REPAIR 132 Conjunto','Conjunto',2.205,8.00,8.80),
('MINERAL REPAIR 333 Conjunto','Conjunto',2.232,8.40,9.24),
('MINERAL REPAIR 499 Conjunto','Conjunto',3.086,8.00,8.80),
('MORFLOOR HR','Saco',0.749,3.72,3.86),
('PLASTICIZER BINDER','Bombona 20',2.419,9.33,9.47),
('PLASTICIZER BINDER','Bombona 50',2.419,9.03,9.17),
('PLASTICIZER BINDER','Tambor',2.419,8.59,8.73),
('PLASTICIZER BINDER','CNT',2.419,8.76,8.91),
('PLASTICIZER CW','Bombona 20',5.040,15.97,16.12),
('PLASTICIZER CW','Bombona 50',5.040,15.67,15.81),
('PLASTICIZER CW','Tambor',5.040,15.23,15.37),
('PLASTICIZER CW','CNT',5.040,15.41,15.55),
('PLASTICIZER HC','Bombona 20',4.822,15.42,15.56),
('PLASTICIZER HC','Bombona 50',4.822,15.12,15.26),
('PLASTICIZER HC','Tambor',4.822,14.99,15.14),
('PLASTICIZER HC','CNT',4.822,14.85,15.00),
('PLASTICIZER PREMIUM','Bombona 20',1.609,7.28,7.42),
('PLASTICIZER PREMIUM','Bombona 50',1.609,6.98,7.12),
('PLASTICIZER PREMIUM','Tambor',1.609,6.54,6.68),
('PLASTICIZER PREMIUM','CNT',1.609,6.71,6.86),
('PLASTICIZER SAD','Bombona 20',1.770,7.69,7.83),
('PLASTICIZER SAD','Bombona 50',1.770,7.38,7.53),
('PLASTICIZER SAD','Tambor',1.770,6.94,7.09),
('PLASTICIZER SAD','CNT',1.770,7.12,7.26),
('PLASTICIZER SAD 20','Bombona 20',1.270,6.42,6.56),
('PLASTICIZER SAD 20','Bombona 50',1.270,6.12,6.26),
('PLASTICIZER SAD 20','Tambor',1.270,5.68,5.82),
('PLASTICIZER SAD 20','CNT',1.270,5.85,6.00),
('POLYPLAST 146','Bombona 24',3.878,13.03,13.17),
('POLYPLAST 146','Bombona 60',3.878,12.73,12.87),
('POLYPLAST 146','Tambor',3.878,12.29,12.43),
('POLYPLAST 146','CNT',3.878,12.46,12.61),
('POLYPLAST 151','Bombona 24',3.900,13.08,13.23),
('POLYPLAST 151','Bombona 60',3.900,12.78,12.92),
('POLYPLAST 151','Tambor',3.900,12.34,12.48),
('POLYPLAST 151','CNT',3.900,12.52,12.66),
('POLYPLAST 167','Bombona 24',3.761,12.73,12.88),
('POLYPLAST 167','Bombona 60',3.761,12.43,12.57),
('POLYPLAST 167','Tambor',3.761,11.99,12.13),
('POLYPLAST 167','CNT',3.761,12.17,12.31),
('POLYPLAST 170 D','Bombona 24',2.672,9.97,10.12),
('POLYPLAST 170 D','Bombona 60',2.672,9.67,9.81),
('POLYPLAST 170 D','Tambor',2.672,9.23,9.37),
('POLYPLAST 170 D','CNT',2.672,9.41,9.55),
('POLYPLAST 170 PLUS','Bombona 24',2.834,10.38,10.53),
('POLYPLAST 170 PLUS','Bombona 60',2.834,10.08,10.22),
('POLYPLAST 170 PLUS','Tambor',2.834,9.64,9.78),
('POLYPLAST 170 PLUS','CNT',2.834,9.82,9.96),
('POLYPLAST 4300','Bombona 24',3.857,12.97,13.12),
('POLYPLAST 4300','Bombona 60',3.857,12.67,12.82),
('POLYPLAST 4300','Tambor',3.857,12.23,12.37),
('POLYPLAST 4300','CNT',3.857,12.41,12.55),
('POLYSEL CONJUNTO','Conjunto',85.000,224.38,224.52),
('PRIME JD CONJUNTO 1KG','Conjunto',100.353,267.57,267.71),
('RELEASE WAX','Balde',8.349,24.98,25.12),
('RELENT','Bombona 20',8.089,23.70,23.84),
('RELENT','Bombona 50',8.089,23.40,23.54),
('RELENT','Tambor',8.089,22.96,23.10),
('RELENT','CNT',8.089,23.13,23.28),
('RELENT AD','Bombona 20',23.998,86.90,87.15),
('RELENT AD','Bombona 50',23.060,86.30,86.80),
('RELENT AD','Tambor',23.998,83.00,83.30),
('RELENT AD','CNT',23.060,61.07,61.21),
('RELENT BASE','Tambor',17.000,45.35,45.49),
('RELENT BIO-VO','Bombona 20',11.896,33.34,33.49),
('RELENT BIO-VO','Bombona 50',11.896,33.04,33.19),
('RELENT BIO-VO','Tambor',11.896,32.60,32.74),
('RELENT BIO-VO','CNT',11.896,32.78,32.92),
('RELENT CONCENTRATE','Bombona 20',18.000,48.81,48.96),
('RELENT CONCENTRATE','Bombona 50',18.000,48.51,48.65),
('RELENT CONCENTRATE','Tambor',18.000,48.07,48.21),
('RELENT CONCENTRATE','CNT',18.000,48.25,48.39),
('RELENT RTU','Bombona 20',1.287,6.46,6.61),
('RELENT RTU','Bombona 50',1.287,6.16,6.30),
('RELENT RTU','Tambor',1.287,5.72,5.86),
('RELENT RTU','CNT',1.287,5.90,6.04),
('RELENT S','Bombona 20',2.149,8.65,8.79),
('RELENT S','Bombona 50',2.149,8.35,8.49),
('RELENT S','Tambor',2.149,7.72,7.86),
('RELENT SMO','Bombona 20',7.656,22.60,22.74),
('RELENT SMO','Bombona 50',7.656,22.30,22.44),
('RELENT SMO','Tambor',7.656,21.86,22.00),
('RELENT SUPER','Bombona 20',10.516,29.85,29.99),
('RELENT SUPER','Bombona 50',10.516,29.55,29.69),
('RELENT SUPER','Tambor',10.516,29.11,29.25),
('RELENT W','Bombona 20',8.176,23.92,24.06),
('RELENT W','Bombona 50',8.176,23.62,23.76),
('RELENT W','Tambor',8.176,23.18,23.32),
('RETARPEG S','Bombona 20',5.140,16.23,16.37),
('RETARPEG S','Bombona 50',5.140,15.93,16.07),
('RETARPEG S','Tambor',5.140,15.48,15.63),
('RETARTIVE WR 2010','Bombona 20',2.916,10.59,10.73),
('RETARTIVE WR 2010','Bombona 50',2.916,10.29,10.43),
('RETARTIVE WR 2010','Tambor',2.916,9.85,9.99),
('RETARTIVE WR 2010','CNT',2.916,10.03,10.17),
('RETARTIVE WR 2048','Bombona 20',2.410,9.31,9.45),
('RETARTIVE WR 2048','Bombona 50',2.410,9.01,9.15),
('RETARTIVE WR 2048','Tambor',2.410,8.56,8.71),
('RETARTIVE WR 2048','CNT',2.410,8.74,8.88),
('RUST CONVERTER','Bombona 25',11.284,31.79,31.94),
('RUST CONVERTER','Bombona 60',11.284,31.49,31.64),
('STRUCTURAL AD CONJUNTO','Conjunto',29.716,84.19,84.34),
('STRUCTURAL TF CONJUNTO','Conjunto',72.477,192.55,192.69),
('SUPERFLUID AC','Bombona 24',4.370,14.27,14.42),
('SUPERFLUID AC','Bombona 60',4.370,13.97,14.12),
('SUPERFLUID AC','Tambor',4.370,13.53,13.67),
('SUPERFLUID AC','CNT',4.370,13.71,13.85),
('VERTICAL CURE','Bombona 20',3.089,11.03,11.17),
('VERTICAL CURE','Bombona 50',3.089,10.73,10.87),
('VERTICAL CURE','Tambor',3.089,10.29,10.43),
('WHITE MINERAL REPAIR CONJUNTO','Conjunto',5.500,17.26,17.41),
('WP ARCON','Bombona 20',0.567,4.64,4.78),
('WP ARCON','Bombona 50',0.567,4.34,4.48),
('WP ARCON','Tambor',0.567,3.90,4.04),
('WP ARPOMON','Saco 20',0.933,4.06,4.20),
('WP CRYSTAL','Saco 25',1.957,6.65,6.80),
('WP FLEXIBLE','Bombona 18',4.125,13.65,13.80),
('WP FLEXIBLE','Bombona 42',3.102,10.76,10.90),
('WP FLEXIBLE','Tambor',4.125,12.91,13.05),
('WP HYDRACEM UF','Saco 25',5.075,14.55,14.70),
('SUFLEX GREY RA','Balde 18',8.193,24.44,24.59),
('SUFLEXIBLE RA','Balde 18',8.193,24.44,24.59),
('SUPROFLEX CONJUNTO','Conjunto',0.769,6.07,6.21),
('WP TILE PRO','Bombona 20',3.255,11.45,11.59),
('WP TILE PRO','Bombona 50',3.255,11.15,11.29),
('WP TILE PRO','Tambor',3.255,10.71,10.85)
ON CONFLICT (nome, embalagem) DO UPDATE SET
  preco_materia_prima = EXCLUDED.preco_materia_prima,
  preco_office        = EXCLUDED.preco_office,
  preco_pj            = EXCLUDED.preco_pj;


-- -------------------------------------------------------------------------
-- 11) Realtime — adiciona as novas tabelas à publicação
-- -------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.companies;            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.contacts;             EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.opportunities;        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.opportunity_products; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.interactions;         EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.proposals;            EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- -------------------------------------------------------------------------
-- Sprint 6.1: callback ganha HORA (date -> timestamptz)
-- Vendedor agora agenda "retorno 14:30", nao so "retorno dia 5".
-- Para dados antigos (date puro), assume 09:00 horario local (America/Sao_Paulo).
-- Idempotente: detecta tipo atual e so converte se ainda for date.
-- (Concatenar ' 09:00:00-03' numa coluna que ja eh timestamptz produz string
-- invalida tipo "2026-05-29 12:00:00+00 09:00:00-03" — por isso o check.)
-- -------------------------------------------------------------------------
DO $$
DECLARE v_type text;
BEGIN
  SELECT data_type INTO v_type FROM information_schema.columns
   WHERE table_schema='public' AND table_name='opportunities' AND column_name='callback_date';
  IF v_type = 'date' THEN
    ALTER TABLE public.opportunities
      ALTER COLUMN callback_date TYPE timestamptz
      USING (callback_date::text || ' 09:00:00-03')::timestamptz;
  END IF;
END $$;

DO $$
DECLARE v_type text;
BEGIN
  SELECT data_type INTO v_type FROM information_schema.columns
   WHERE table_schema='public' AND table_name='interactions' AND column_name='next_callback';
  IF v_type = 'date' THEN
    ALTER TABLE public.interactions
      ALTER COLUMN next_callback TYPE timestamptz
      USING (next_callback::text || ' 09:00:00-03')::timestamptz;
  END IF;
END $$;

-- Indice para acelerar a tela "Hoje" (filtro por intervalo de tempo + status aberto)
CREATE INDEX IF NOT EXISTS idx_opportunities_callback_at
  ON public.opportunities(callback_date)
  WHERE estagio NOT IN ('ganha','perdida');


-- -------------------------------------------------------------------------
-- Sprint 6.2: tarefas livres (nao atreladas a oportunidade)
-- Ex: "ligar pro fornecedor X", "revisar tabela de precos"
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tasks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id   uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id  uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  titulo      text NOT NULL,
  descricao   text,
  due_at      timestamptz NOT NULL,
  done        boolean NOT NULL DEFAULT false,
  done_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_seller_due ON public.tasks(seller_id, due_at) WHERE NOT done;
CREATE INDEX IF NOT EXISTS idx_tasks_company   ON public.tasks(company_id) WHERE company_id IS NOT NULL;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tasks_select"      ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert"      ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_own"  ON public.tasks;
DROP POLICY IF EXISTS "tasks_delete_own"  ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks FOR SELECT TO authenticated USING (true);
CREATE POLICY "tasks_insert" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_leitor() AND (seller_id = auth.uid() OR public.is_admin()));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (public.is_admin() OR seller_id = auth.uid())
  WITH CHECK (public.is_admin() OR seller_id = auth.uid());
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (public.is_admin() OR seller_id = auth.uid());

CREATE OR REPLACE FUNCTION public.tasks_set_updated()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  IF NEW.done IS DISTINCT FROM OLD.done THEN
    NEW.done_at = CASE WHEN NEW.done THEN now() ELSE NULL END;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_tasks_updated ON public.tasks;
CREATE TRIGGER tg_tasks_updated BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.tasks_set_updated();

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- -------------------------------------------------------------------------
-- Sprint 6.7: numeracao de pedidos independente das propostas
-- Proposta tem seu proprio numero sequencial (ja existia).
-- Pedido ganha numero separado, atribuido ao "Marcar como Pedido".
-- Seed: ultimo pedido emitido foi 335-26, entao proximo sera 336-26.
-- -------------------------------------------------------------------------

-- Tabela de contadores por ano (1 linha por ano, atomica via UPDATE)
CREATE TABLE IF NOT EXISTS public.pedido_sequences (
  ano    int PRIMARY KEY,
  ultimo int NOT NULL DEFAULT 0
);

-- Seed: garante que o proximo pedido de 2026 sera 336
INSERT INTO public.pedido_sequences (ano, ultimo)
  VALUES (2026, 335)
  ON CONFLICT (ano) DO UPDATE
    SET ultimo = GREATEST(pedido_sequences.ultimo, EXCLUDED.ultimo);

-- Colunas na tabela proposals
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS pedido_numero int,
  ADD COLUMN IF NOT EXISTS pedido_ano    int;

CREATE INDEX IF NOT EXISTS idx_proposals_pedido ON public.proposals(pedido_ano, pedido_numero)
  WHERE pedido_numero IS NOT NULL;

-- RLS: pedido_sequences e lida pelo trigger (SECURITY DEFINER) — vendedor nao acessa diretamente
ALTER TABLE public.pedido_sequences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pedido_seq_admin" ON public.pedido_sequences;
CREATE POLICY "pedido_seq_admin" ON public.pedido_sequences
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Trigger: atribui pedido_numero quando status muda para 'pedido'
CREATE OR REPLACE FUNCTION public.atribui_numero_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ano int;
  v_num int;
BEGIN
  IF NEW.status = 'pedido'
     AND (OLD.status IS DISTINCT FROM 'pedido')
     AND NEW.pedido_numero IS NULL
  THEN
    v_ano := EXTRACT(YEAR FROM now())::int;
    -- Incrementa atomicamente e pega o novo valor
    INSERT INTO public.pedido_sequences (ano, ultimo)
      VALUES (v_ano, 1)
      ON CONFLICT (ano) DO UPDATE
        SET ultimo = pedido_sequences.ultimo + 1
      RETURNING ultimo INTO v_num;
    NEW.pedido_numero := v_num;
    NEW.pedido_ano    := v_ano;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_atribui_numero_pedido ON public.proposals;
CREATE TRIGGER tg_atribui_numero_pedido
  BEFORE UPDATE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.atribui_numero_pedido();


-- -------------------------------------------------------------------------
-- Sprint 6.5: status da proposta (em_andamento / pedido / cancelada)
-- Permite filtrar propostas em andamento vs finalizadas como pedido.
-- -------------------------------------------------------------------------
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'em_andamento'
  CHECK (status IN ('em_andamento','pedido','cancelada')),
  ADD COLUMN IF NOT EXISTS status_changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS status_changed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_proposals_status ON public.proposals(status);

-- Permite UPDATE do status (RLS antigo so deixava DELETE pra admin)
DROP POLICY IF EXISTS "proposals_update_status" ON public.proposals;
CREATE POLICY "proposals_update_status" ON public.proposals
  FOR UPDATE TO authenticated
  USING (NOT public.is_leitor() AND (public.is_admin() OR seller_id = auth.uid()))
  WITH CHECK (NOT public.is_leitor() AND (public.is_admin() OR seller_id = auth.uid()));


-- -------------------------------------------------------------------------
-- 12) Recarrega o schema do PostgREST
-- -------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
