-- =========================================================================
-- Sprint 9.1 — Etapa A: tabela organizations + seed Adiblock
-- =========================================================================
-- SEGURA: cria tabela nova; NAO afeta tabelas existentes nem o funcionamento
-- atual do app. Idempotente. Pode rodar em producao com tranquilidade.
-- Ref: docs/MULTI-TENANT.md (Etapa A).
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.organizations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome       text NOT NULL,
  cnpj       text,
  plano      text NOT NULL DEFAULT 'free',     -- free | pro | ...
  status     text NOT NULL DEFAULT 'ativo',    -- ativo | suspenso | cancelado
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed da Adiblock com id FIXO (usado no backfill da Etapa C e no rollback).
INSERT INTO public.organizations (id, nome, cnpj, plano, status)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'Adiblock',
        '31.458.997/0001-51', 'pro', 'ativo')
ON CONFLICT (id) DO NOTHING;

GRANT ALL ON TABLE public.organizations TO authenticated, service_role;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
-- Policy TEMPORARIA (todos os autenticados leem). Sera ENDURECIDA na Etapa F
-- para: USING (id = public.current_org()). Como so existe a Adiblock agora,
-- nao ha exposicao real ainda.
DROP POLICY IF EXISTS "orgs_select_tmp"  ON public.organizations;
DROP POLICY IF EXISTS "orgs_select_own"  ON public.organizations;
CREATE POLICY "orgs_select_tmp" ON public.organizations
  FOR SELECT TO authenticated USING (true);

NOTIFY pgrst, 'reload schema';

-- Conferencia:
--   SELECT * FROM public.organizations;   -- deve listar a Adiblock

-- =========================================================================
-- ROLLBACK (Etapa A):
--   DROP TABLE public.organizations CASCADE;
-- =========================================================================
