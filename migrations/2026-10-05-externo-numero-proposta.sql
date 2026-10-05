-- =========================================================================
-- VENDEDOR EXTERNO — número de proposta repetido (05/10/2026)
-- =========================================================================
-- Sintoma: externo gera proposta e recebe
--   duplicate key value violates unique constraint "proposals_org_ano_numero_key"
--
-- Causa: atribui_numero_proposta() calcula MAX(numero)+1 rodando com as
-- permissões de QUEM ESTÁ LOGADO. Até o externo, todo mundo via todas as
-- propostas da org, então o MAX era o real. O externo vê só as dele: o MAX
-- que ele enxerga é baixo e o número sai repetido. É o RLS fazendo o
-- trabalho dele — o erro era a função depender de enxergar tudo.
--
-- Correção:
--   * SECURITY DEFINER: o cálculo vê todas as propostas, seja quem for.
--     A função só devolve um NÚMERO; nenhum dado de outra proposta sai dela.
--   * Filtra pela org e trava por (org, ano). A versão antiga contava todas
--     as orgs juntas — herança de antes do multi-tenant.
--   * COALESCE(NEW.org_id, current_org()): os triggers rodam em ordem
--     alfabética e tg_set_org_id vem DEPOIS deste, então aqui NEW.org_id
--     ainda pode estar vazio.
--
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- O resultado na tela deve ser "OK".
-- =========================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.atribui_numero_proposta()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_org uuid;
BEGIN
  IF NEW.numero IS NULL OR NEW.numero = 0 THEN
    v_org := COALESCE(NEW.org_id, public.current_org());
    PERFORM pg_advisory_xact_lock(hashtext('proposta_' || coalesce(v_org::text, '-') || '_' || NEW.ano));
    SELECT COALESCE(MAX(numero), 0) + 1 INTO NEW.numero
      FROM public.proposals
     WHERE ano = NEW.ano
       AND org_id IS NOT DISTINCT FROM v_org;
  END IF;
  RETURN NEW;
END;
$$;

COMMIT;

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN p.prosecdef AND pg_get_functiondef(p.oid) LIKE '%v_org%'
            THEN 'OK — numeração de proposta corrigida'
            ELSE 'ERRO — mande o print' END AS resultado
  FROM pg_proc p
 WHERE p.proname = 'atribui_numero_proposta' AND p.pronamespace = 'public'::regnamespace;
