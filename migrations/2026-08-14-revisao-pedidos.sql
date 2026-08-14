-- =========================================================================
-- 2026-08-14 — Revisao de pedidos (editar pedido ja fechado, sem perder o
--              que foi combinado antes)
-- =========================================================================
-- POR QUE ESTA MIGRATION EXISTE
--   Cliente pede desconto ao trocar a forma de pagamento; cliente pede pra
--   acrescentar outro material num pedido que ja esta fechado. Isso e rotina,
--   nao excecao. Mas o `proposals.snapshot` e IMUTAVEL de proposito (proposta
--   e documento legal — ver CLAUDE.md secao 11): sobrescrever apaga a prova
--   do que valia antes, e o audit_log nao cobre esse buraco porque ignora o
--   campo snapshot.
--
--   Solucao: editar nao sobrescreve, VERSIONA. O pedido continua sendo o
--   0336-26 (o cliente ja tem esse numero na mao); ele passa a ser
--   "0336-26 rev. 2", e a rev. 1 fica guardada inteira em proposal_revisions.
--
-- SEGURO DE RODAR: so ADIciona coluna e tabela. Nao apaga, nao altera tipo,
-- nao mexe em dado existente. Idempotente (pode rodar 2x).
--
-- ANTES DE RODAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
-- =========================================================================

BEGIN;

-- ── 1) Contador de revisao na propria proposta ───────────────────────────
-- Fica na proposals (e nao so na tabela de historico) porque a tela precisa
-- do numero da revisao ATUAL em toda listagem, sem um JOIN por card.
-- DEFAULT 1 = tudo que ja existe hoje e a revisao 1 (o original).
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS revisao int NOT NULL DEFAULT 1;

-- ── 2) Historico imutavel das revisoes ───────────────────────────────────
-- Cada linha guarda o snapshot COMO ERA ANTES da edicao. Ou seja: ao salvar
-- a rev. 2, nasce aqui uma linha com revisao=1 e o snapshot original.
-- A revisao vigente vive sempre em proposals.snapshot — aqui so mora passado.
CREATE TABLE IF NOT EXISTS public.proposal_revisions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  proposal_id  uuid NOT NULL REFERENCES public.proposals(id) ON DELETE CASCADE,
  revisao      int  NOT NULL,
  snapshot     jsonb NOT NULL,
  -- Por que o pedido mudou. Obrigatorio no front (campo required), mas
  -- deixado NULLable no banco pra nao quebrar carga/restauracao de backup.
  motivo       text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  UNIQUE (proposal_id, revisao)
);

CREATE INDEX IF NOT EXISTS idx_prop_rev_proposal
  ON public.proposal_revisions(proposal_id, revisao DESC);
CREATE INDEX IF NOT EXISTS idx_prop_rev_org
  ON public.proposal_revisions(org_id);

-- ── 3) org_id automatico (mesmo padrao da etapa 91d) ─────────────────────
-- O front nao manda org_id em lugar nenhum; quem preenche e o trigger.
DROP TRIGGER IF EXISTS tg_set_org_id ON public.proposal_revisions;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.proposal_revisions
  FOR EACH ROW EXECUTE FUNCTION public.set_org_id();

-- ── 4) RLS por organizacao (mesmo padrao da etapa 91f) ───────────────────
-- SELECT e INSERT so. Nao existe UPDATE nem DELETE de proposito: historico
-- que pode ser reescrito nao e historico. Nem admin apaga — a unica forma de
-- sumir com uma revisao e excluindo a proposta inteira (ON DELETE CASCADE).
ALTER TABLE public.proposal_revisions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prop_rev_select" ON public.proposal_revisions;
DROP POLICY IF EXISTS "prop_rev_insert" ON public.proposal_revisions;
CREATE POLICY "prop_rev_select" ON public.proposal_revisions FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "prop_rev_insert" ON public.proposal_revisions FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

COMMIT;

-- =========================================================================
-- CONFERENCIA (rode depois; deve devolver 1 linha com revisao = 1)
-- =========================================================================
--   SELECT numero, ano, revisao FROM public.proposals ORDER BY created_at DESC LIMIT 5;
--   SELECT count(*) FROM public.proposal_revisions;   -- 0 ate a 1a edicao
--
-- ROLLBACK (se precisar desfazer — perde o historico de revisoes):
--   BEGIN;
--   DROP TABLE IF EXISTS public.proposal_revisions;
--   ALTER TABLE public.proposals DROP COLUMN IF EXISTS revisao;
--   COMMIT;
-- =========================================================================
