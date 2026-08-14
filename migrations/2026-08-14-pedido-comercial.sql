-- =========================================================================
-- 2026-08-14 — Pedido Comercial (confirmacao formal do pedido pro cliente)
-- =========================================================================
-- POR QUE ESTA MIGRATION EXISTE
--   Hoje existem dois documentos e falta o do meio:
--     Proposta Comercial  -> cliente  · tem precos   (#cot-page)
--     Pedido de Producao  -> fabrica  · sem precos   (#prod-page)
--     Pedido Comercial    -> cliente  · CONFIRMA o pedido fechado  <— falta
--
--   O cliente emite uma OC (ordem/pedido de compra) com um numero PROPRIO, e
--   e por esse numero que ele cobra, confere e paga. Sem guardar esse numero,
--   quando ele liga falando "pedido 4500123789" ninguem acha nada no CRM.
--
-- POR QUE EM COLUNA E NAO NO SNAPSHOT
--   O snapshot e o que foi NEGOCIADO, congelado no momento da proposta. Estes
--   campos sao de CUMPRIMENTO e chegam depois (as vezes dias depois), igual ao
--   nf_numero e transportadora que ja moram em coluna desde o Sprint 6.8.
--   Enfia-los no snapshot obrigaria a mexer num documento que e imutavel.
--
-- SEGURO DE RODAR: so ADIciona colunas. Nao apaga, nao altera tipo, nao mexe
-- em dado existente. Idempotente (pode rodar 2x).
--
-- ANTES DE RODAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
-- =========================================================================

BEGIN;

ALTER TABLE public.proposals
  -- Numero da OC/pedido de compra NO SISTEMA DO CLIENTE. text e nao int: vem
  -- com zeros a esquerda, letras e barras dependendo do ERP dele.
  ADD COLUMN IF NOT EXISTS oc_numero        text,
  -- Onde entregar. Default vem da obra da oportunidade, mas o cliente muda o
  -- destino direto no telefone com frequencia — precisa ser editavel.
  ADD COLUMN IF NOT EXISTS entrega_local    text,
  ADD COLUMN IF NOT EXISTS entrega_previsao date;

-- Busca por numero de OC: o cliente liga citando o numero DELE, nunca o nosso.
-- Indice parcial — a esmagadora maioria das propostas nunca vira pedido com OC.
CREATE INDEX IF NOT EXISTS idx_proposals_oc
  ON public.proposals(org_id, oc_numero)
  WHERE oc_numero IS NOT NULL;

COMMIT;

-- Nada de policy nova: os campos moram em proposals, que ja tem RLS por org
-- desde a etapa 91f (proposals_update_status cobre o UPDATE por nao-leitor).

-- =========================================================================
-- CONFERENCIA
-- =========================================================================
--   SELECT numero, ano, oc_numero, entrega_local, entrega_previsao
--     FROM public.proposals ORDER BY created_at DESC LIMIT 5;
--
-- ROLLBACK:
--   BEGIN;
--   DROP INDEX IF EXISTS public.idx_proposals_oc;
--   ALTER TABLE public.proposals
--     DROP COLUMN IF EXISTS oc_numero,
--     DROP COLUMN IF EXISTS entrega_local,
--     DROP COLUMN IF EXISTS entrega_previsao;
--   COMMIT;
-- =========================================================================
