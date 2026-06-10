-- =========================================================================
-- Sprint 9.1 — Etapa D (executa 2º): NOT NULL + índices + numeração por org
-- =========================================================================
-- Roda DEPOIS de 91d (que garante org_id auto-preenchido em novos registros).
-- Aqui o org_id passa a ser OBRIGATORIO e as unicidades/numeracao viram
-- por-organizacao. Idempotente. NAO muda o que o usuario ve (isolamento so
-- liga na 91f) — mas mexe em constraints/PK, entao: backup antes + baixo uso.
-- Ref: docs/MULTI-TENANT.md (Etapa D). Nomes das UNIQUE confirmados via query.
-- =========================================================================

-- 0) Backfill defensivo (garante 0 nulos mesmo que algo tenha escapado entre etapas)
DO $$ DECLARE adi uuid := '00000000-0000-0000-0000-0000000000a1'; BEGIN
  UPDATE public.companies            SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.contacts             SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.opportunities        SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.opportunity_products SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.interactions         SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.proposals            SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.tasks                SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.products             SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.lgpd_requests        SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.pedido_sequences     SET org_id = adi WHERE org_id IS NULL;
END $$;

-- 1) NOT NULL nas tabelas de dados.
--    profiles e audit_log ficam NULLABLE de proposito:
--    - profiles: novos usuarios (handle_new_user) nascem sem org ate o admin
--      atribuir; tratado na policy da 91f. (onboarding/convites = fase 2)
--    - audit_log: registros de exclusao podem nao ter org resolvida.
ALTER TABLE public.companies            ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.contacts             ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.opportunities        ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.opportunity_products ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.interactions         ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.proposals            ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.tasks                ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.products             ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.lgpd_requests        ALTER COLUMN org_id SET NOT NULL;

-- 2) Indices compostos (org_id primeiro = filtro mais seletivo do RLS)
CREATE INDEX IF NOT EXISTS idx_companies_org      ON public.companies(org_id, razao_social);
CREATE INDEX IF NOT EXISTS idx_contacts_org       ON public.contacts(org_id, company_id);
CREATE INDEX IF NOT EXISTS idx_opps_org           ON public.opportunities(org_id, estagio);
CREATE INDEX IF NOT EXISTS idx_opps_org_callback  ON public.opportunities(org_id, callback_date) WHERE estagio NOT IN ('ganha','perdida');
CREATE INDEX IF NOT EXISTS idx_oppprod_org        ON public.opportunity_products(org_id, opportunity_id);
CREATE INDEX IF NOT EXISTS idx_inter_org          ON public.interactions(org_id, datetime);
CREATE INDEX IF NOT EXISTS idx_proposals_org      ON public.proposals(org_id, ano, numero);
CREATE INDEX IF NOT EXISTS idx_tasks_org          ON public.tasks(org_id, seller_id, due_at);
CREATE INDEX IF NOT EXISTS idx_products_org       ON public.products(org_id, nome);
CREATE INDEX IF NOT EXISTS idx_audit_org          ON public.audit_log(org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lgpd_org           ON public.lgpd_requests(org_id);

-- 3) UNICIDADES viram por-org (nomes confirmados via pg_constraint)
ALTER TABLE public.proposals DROP CONSTRAINT IF EXISTS proposals_ano_numero_key;
ALTER TABLE public.proposals ADD  CONSTRAINT proposals_org_ano_numero_key UNIQUE (org_id, ano, numero);

ALTER TABLE public.products  DROP CONSTRAINT IF EXISTS products_nome_embalagem_key;
ALTER TABLE public.products  ADD  CONSTRAINT products_org_nome_emb_key UNIQUE (org_id, nome, embalagem);

ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_cnpj_key;
ALTER TABLE public.companies ADD  CONSTRAINT companies_org_cnpj_key UNIQUE (org_id, cnpj);

-- 4) pedido_sequences: numeracao POR ORG. PK (ano) -> (org_id, ano)
ALTER TABLE public.pedido_sequences ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.pedido_sequences DROP CONSTRAINT IF EXISTS pedido_sequences_pkey;
ALTER TABLE public.pedido_sequences ADD  PRIMARY KEY (org_id, ano);

-- 4b) atribui_numero_pedido(): conta por (org_id, ano). So muda o ON CONFLICT
--     e o INSERT pra incluir org_id; o resto da logica e identico.
CREATE OR REPLACE FUNCTION public.atribui_numero_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_ano int; v_num int;
BEGIN
  IF NEW.status = 'pedido'
     AND (OLD.status IS DISTINCT FROM 'pedido')
     AND NEW.pedido_numero IS NULL
  THEN
    v_ano := EXTRACT(YEAR FROM now())::int;
    INSERT INTO public.pedido_sequences (org_id, ano, ultimo)
      VALUES (NEW.org_id, v_ano, 1)
      ON CONFLICT (org_id, ano) DO UPDATE
        SET ultimo = pedido_sequences.ultimo + 1
      RETURNING ultimo INTO v_num;
    NEW.pedido_numero := v_num;
    NEW.pedido_ano    := v_ano;
  END IF;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- TESTE antes da 91f (o app deve continuar 100% normal — isolamento ainda NAO ligou):
--   1) Criar empresa pelo app -> ok, nasce com org_id.
--   2) Gerar uma proposta e "Marcar como Pedido" -> numero de pedido segue a
--      sequencia (NEW: por org). Conferir:
--        SELECT org_id, ano, ultimo FROM public.pedido_sequences;
--   3) App inteiro navegavel (Empresas, Pipeline, Propostas, Dashboard).
-- =========================================================================

-- =========================================================================
-- ROLLBACK (Etapa D):
--   ALTER TABLE public.companies ALTER COLUMN org_id DROP NOT NULL; (idem demais)
--   DROP INDEX IF EXISTS idx_companies_org; (idem demais idx_*_org)
--   ALTER TABLE public.proposals DROP CONSTRAINT proposals_org_ano_numero_key;
--   ALTER TABLE public.proposals ADD CONSTRAINT proposals_ano_numero_key UNIQUE (ano, numero);
--   ALTER TABLE public.products  DROP CONSTRAINT products_org_nome_emb_key;
--   ALTER TABLE public.products  ADD CONSTRAINT products_nome_embalagem_key UNIQUE (nome, embalagem);
--   ALTER TABLE public.companies DROP CONSTRAINT companies_org_cnpj_key;
--   ALTER TABLE public.companies ADD CONSTRAINT companies_cnpj_key UNIQUE (cnpj);
--   ALTER TABLE public.pedido_sequences DROP CONSTRAINT pedido_sequences_pkey;
--   ALTER TABLE public.pedido_sequences ADD PRIMARY KEY (ano);
--   -- restaurar atribui_numero_pedido com ON CONFLICT (ano) — ver migration 6.7
-- =========================================================================
