-- =========================================================================
-- Sprint 9.1 — Etapa C: backfill org_id = Adiblock nos dados existentes
-- =========================================================================
-- SEGURA: todos os dados atuais sao da Adiblock. So preenche org_id onde
-- esta NULL. Nao muda comportamento (app ainda ignora org_id ate a Etapa F).
-- Idempotente (WHERE org_id IS NULL). Rodar DEPOIS da Etapa B.
-- Ref: docs/MULTI-TENANT.md (Etapa C).
-- =========================================================================

DO $$
DECLARE adi uuid := '00000000-0000-0000-0000-0000000000a1';
BEGIN
  UPDATE public.profiles             SET org_id = adi WHERE org_id IS NULL;
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
  UPDATE public.audit_log            SET org_id = adi WHERE org_id IS NULL;
END $$;

NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- VERIFICACAO OBRIGATORIA antes da Etapa D — todos os "nulos" devem ser 0:
-- =========================================================================
--   SELECT 'profiles' t,             count(*) FILTER (WHERE org_id IS NULL) nulos FROM public.profiles
--   UNION ALL SELECT 'companies',            count(*) FILTER (WHERE org_id IS NULL) FROM public.companies
--   UNION ALL SELECT 'contacts',             count(*) FILTER (WHERE org_id IS NULL) FROM public.contacts
--   UNION ALL SELECT 'opportunities',        count(*) FILTER (WHERE org_id IS NULL) FROM public.opportunities
--   UNION ALL SELECT 'opportunity_products', count(*) FILTER (WHERE org_id IS NULL) FROM public.opportunity_products
--   UNION ALL SELECT 'interactions',         count(*) FILTER (WHERE org_id IS NULL) FROM public.interactions
--   UNION ALL SELECT 'proposals',            count(*) FILTER (WHERE org_id IS NULL) FROM public.proposals
--   UNION ALL SELECT 'tasks',                count(*) FILTER (WHERE org_id IS NULL) FROM public.tasks
--   UNION ALL SELECT 'products',             count(*) FILTER (WHERE org_id IS NULL) FROM public.products
--   UNION ALL SELECT 'lgpd_requests',        count(*) FILTER (WHERE org_id IS NULL) FROM public.lgpd_requests
--   UNION ALL SELECT 'pedido_sequences',     count(*) FILTER (WHERE org_id IS NULL) FROM public.pedido_sequences
--   UNION ALL SELECT 'audit_log',            count(*) FILTER (WHERE org_id IS NULL) FROM public.audit_log;
--
-- Tambem confirmar os nomes reais das constraints UNIQUE (para a Etapa D):
--   SELECT conrelid::regclass tabela, conname FROM pg_constraint
--    WHERE contype='u' AND conrelid::regclass::text IN
--      ('public.proposals','public.products','public.companies')
--    ORDER BY 1;

-- =========================================================================
-- ROLLBACK (Etapa C):
--   UPDATE public.profiles SET org_id=NULL WHERE org_id='00000000-0000-0000-0000-0000000000a1';
--   (idem para as demais tabelas) — volta ao estado da Etapa B.
-- =========================================================================
