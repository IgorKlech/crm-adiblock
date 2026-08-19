-- =========================================================================
-- 2026-08-17 — closed_at retroativo nas oportunidades fechadas
-- =========================================================================
-- POR QUE
--   62 oportunidades GANHAS estao com `closed_at` nulo. Elas sao anteriores ao
--   trigger `opportunity_estagio_changed()`, que passou a preencher o campo
--   quando o estagio muda pra ganha/perdida.
--
--   Quem sofre com isso e o Radar de Reativacao: sem closed_at ele cai no
--   fallback de `created_at`, ou seja, assume que o cliente comprou no dia em
--   que foi CADASTRADO. Numa negociacao que levou tres meses, o Radar erra por
--   tres meses ao calcular ha quanto tempo aquele cliente esta dormente — e
--   prioriza a lista errada.
--
-- DE ONDE VEM A DATA
--   `estagio_changed_at`, que registra quando o estagio mudou pela ultima vez.
--   Numa oportunidade ganha, a ultima mudanca FOI pra "ganha". Conferido antes
--   de escrever: as 62 tem esse campo preenchido, nenhuma precisa de chute.
--   Nao ha aproximacao aqui — se houvesse, esta migration seria outra conversa.
--
-- SEGURANCA
--   - So UPDATE, sem DDL. Nao cria, nao apaga, nao altera tipo.
--   - Idempotente: o `WHERE closed_at IS NULL` faz a segunda execucao nao
--     tocar em nada.
--   - Nao mexe em linha que ja tem closed_at.
--
-- ⚠ ANTES DE RODAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
--   Esta migration ESCREVE em dado de producao.
--
-- ⚠ O audit_log NAO cobre esta mudanca — conferido em 19/08/2026.
--   `log_audit_changes()` tem `closed_at` na lista de campos ignorados, junto
--   com updated_at e estagio_changed_at. E como este UPDATE mexe SO nesse
--   campo, o diff sai vazio e o trigger retorna antes de inserir: nao fica
--   nem uma linha de log. Nao e defeito do trigger (o campo muda sozinho, e
--   logar isso encheria o historico de ruido) — e so um limite que precisa
--   ser dito, porque a rede de seguranca que a gente supoe existir, aqui nao
--   existe.
--
--   Por isso o passo 1 abaixo guarda os ids afetados numa tabela antes de
--   escrever. Sao 62 linhas; o rollback exato fica no fim do arquivo.
-- =========================================================================

BEGIN;

-- ── 1) Rede de seguranca: quem vai ser tocada ────────────────────────────
-- Sem isto, depois do UPDATE nao ha como saber quais linhas estavam nulas —
-- e restaurar do backup significaria voltar o banco INTEIRO por causa de uma
-- coluna. A tabela e descartavel: apague-a quando o resultado estiver
-- confirmado (comando no fim do arquivo).
CREATE TABLE IF NOT EXISTS public._bkp_closed_at_20260819 AS
SELECT id, estagio, closed_at AS closed_at_antigo, estagio_changed_at
  FROM public.opportunities
 WHERE estagio IN ('ganha','perdida')
   AND closed_at IS NULL
   AND estagio_changed_at IS NOT NULL;

-- ── Antes: quantas serao tocadas ─────────────────────────────────────────
SELECT 'ANTES' AS momento,
       count(*) FILTER (WHERE estagio = 'ganha'   AND closed_at IS NULL) AS ganhas_sem_closed_at,
       count(*) FILTER (WHERE estagio = 'perdida' AND closed_at IS NULL) AS perdidas_sem_closed_at,
       (SELECT count(*) FROM public._bkp_closed_at_20260819)             AS guardadas_pro_rollback
  FROM public.opportunities;

-- ── A correcao ───────────────────────────────────────────────────────────
-- Ganhas e perdidas juntas: as duas sao "fechadas" e as duas alimentam
-- relatorio. O criterio e o mesmo.
UPDATE public.opportunities
   SET closed_at = estagio_changed_at
 WHERE estagio IN ('ganha','perdida')
   AND closed_at IS NULL
   AND estagio_changed_at IS NOT NULL;

-- ── Depois: tem que dar zero, fora as que nao tinham estagio_changed_at ──
SELECT 'DEPOIS' AS momento,
       count(*) FILTER (WHERE estagio = 'ganha'   AND closed_at IS NULL) AS ganhas_sem_closed_at,
       count(*) FILTER (WHERE estagio = 'perdida' AND closed_at IS NULL) AS perdidas_sem_closed_at,
       count(*) FILTER (WHERE estagio IN ('ganha','perdida')
                          AND closed_at IS NULL
                          AND estagio_changed_at IS NULL)               AS sem_data_nenhuma
  FROM public.opportunities;

COMMIT;

-- =========================================================================
-- CONFERENCIA (rode depois — o Radar passa a enxergar a data certa)
-- =========================================================================
--   SELECT date_trunc('month', closed_at)::date AS mes, count(*)
--     FROM public.opportunities WHERE estagio = 'ganha'
--    GROUP BY 1 ORDER BY 1;
--
--   Se aparecerem meses distribuidos ao longo de 2026 em vez de tudo
--   amontoado na data de cadastro, funcionou.
--
-- =========================================================================
-- ROLLBACK EXATO (so funciona enquanto a tabela do passo 1 existir)
-- =========================================================================
--   BEGIN;
--   UPDATE public.opportunities o
--      SET closed_at = b.closed_at_antigo          -- ou seja, de volta pra NULL
--     FROM public._bkp_closed_at_20260819 b
--    WHERE o.id = b.id;
--   COMMIT;
--
-- LIMPEZA (rode so depois de confirmar que o Radar e o Dashboard ficaram
-- certos — uma semana e um prazo razoavel):
--   DROP TABLE public._bkp_closed_at_20260819;
-- =========================================================================
