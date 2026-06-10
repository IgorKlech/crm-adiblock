-- =========================================================================
-- Sprint 9.1 — Etapa B: adiciona org_id NULLABLE em todas as tabelas de dados
-- =========================================================================
-- SEGURA: coluna nullable, sem default, sem uso pelo app. O CRM continua
-- funcionando identico (o RLS so passa a filtrar por org na Etapa F).
-- Idempotente (ADD COLUMN IF NOT EXISTS). Rodar DEPOIS da Etapa A.
-- Ref: docs/MULTI-TENANT.md (Etapa B).
-- =========================================================================

ALTER TABLE public.profiles             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.companies            ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.contacts             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.opportunities        ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.opportunity_products ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.interactions         ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.proposals            ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.tasks                ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.products             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.lgpd_requests        ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.pedido_sequences     ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
-- audit_log: SEM FK (audit sobrevive a exclusao — padrao do projeto)
ALTER TABLE public.audit_log            ADD COLUMN IF NOT EXISTS org_id uuid;

NOTIFY pgrst, 'reload schema';

-- Conferencia (todas as colunas devem existir):
--   SELECT table_name FROM information_schema.columns
--    WHERE table_schema='public' AND column_name='org_id' ORDER BY table_name;

-- =========================================================================
-- ROLLBACK (Etapa B):
--   ALTER TABLE public.profiles             DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.companies            DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.contacts             DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.opportunities        DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.opportunity_products DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.interactions         DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.proposals            DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.tasks                DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.products             DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.lgpd_requests        DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.pedido_sequences     DROP COLUMN IF EXISTS org_id;
--   ALTER TABLE public.audit_log            DROP COLUMN IF EXISTS org_id;
-- =========================================================================
