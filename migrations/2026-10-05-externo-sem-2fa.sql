-- =========================================================================
-- VENDEDOR EXTERNO — tira a exigência de 2FA (decisão do Igor, 05/10/2026)
-- =========================================================================
-- Motivo: o vendedor de rua teria dificuldade com o app autenticador.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- O resultado na tela deve ser "OK".
--
-- Por que só esta função: TODA exigência de 2FA do externo passa por
-- sessao_com_2fa() — nas policies, em alcanca_*(), em produtos_venda() e em
-- externo_checa_cnpj(). Ela vira um INTERRUPTOR: devolve sempre true.
-- O nome ficou (renomear obrigaria a refazer todas as policies), por isso o
-- COMMENT abaixo — quem ler a policy e estranhar acha a explicação no banco.
--
-- PARA RELIGAR o 2FA: rodar de novo o corpo original:
--   SELECT coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
-- (e devolver no app o garantir2faExterno() — ver commit 174a082)
-- =========================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.sessao_com_2fa()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT true;
$$;

COMMENT ON FUNCTION public.sessao_com_2fa() IS
  'INTERRUPTOR do 2FA do vendedor externo. DESLIGADO em 05/10/2026 (devolve sempre true). '
  'Para religar: corpo = coalesce(auth.jwt() ->> ''aal'', '''') = ''aal2''. '
  'Ver migrations/2026-10-05-externo-sem-2fa.sql.';

COMMIT;

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN public.sessao_com_2fa() THEN 'OK — 2FA não é mais exigido do externo'
            ELSE 'ERRO — mande o print' END AS resultado;
