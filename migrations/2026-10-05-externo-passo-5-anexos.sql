-- =========================================================================
-- VENDEDOR EXTERNO — PASSO 5 de 5: arquivos anexados (Storage)
-- =========================================================================
-- Último passo.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- A última linha do resultado diz OK ou ERRO. Só siga para o próximo passo com OK.
-- Origem: 2026-10-05-vendedor-externo.sql (o mesmo SQL, fatiado).
-- =========================================================================
-- BLOCO 5 — Storage dos anexos + view companies_with_tier
-- =========================================================================
BEGIN;

-- O caminho é {org_id}/proposals/{proposal_id}/{arquivo}: a pasta [3] é a
-- proposta. Sem isto o externo abriria a OC assinada de cliente alheio
-- sabendo (ou adivinhando) o caminho.
CREATE OR REPLACE FUNCTION public.alcanca_anexo(p_name text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE v_pasta text;
BEGIN
  IF NOT public.is_externo() THEN RETURN true; END IF;
  v_pasta := (storage.foldername(p_name))[3];
  IF v_pasta IS NULL OR v_pasta !~ '^[0-9a-f-]{36}$' THEN RETURN false; END IF;
  RETURN public.alcanca_proposta(v_pasta::uuid);
END $$;
GRANT EXECUTE ON FUNCTION public.alcanca_anexo(text) TO authenticated;

DROP POLICY IF EXISTS "anexos_obj_select" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_insert" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_delete" ON storage.objects;
CREATE POLICY "anexos_obj_select" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text
         AND public.alcanca_anexo(name));
CREATE POLICY "anexos_obj_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'anexos'
              AND (storage.foldername(name))[1] = public.current_org()::text
              AND NOT public.is_leitor()
              AND public.alcanca_anexo(name));
CREATE POLICY "anexos_obj_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text
         AND public.alcanca_anexo(name));

-- A view foi criada sem security_invoker: roda com o dono (postgres) e
-- IGNORA o RLS de companies. O app só a usa no checkSchema, mas pela API
-- qualquer usuário logado leria a lista inteira com valor de pipeline.
-- Exige Postgres 15+ (Bloco 0a).
ALTER VIEW public.companies_with_tier SET (security_invoker = true);

COMMIT;
-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN n = 3 THEN 'OK — pode seguir'
            ELSE 'ERRO: esperado 3, veio ' || n || ' — NÃO siga, mande o print' END AS passo_5
  FROM (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'anexos_obj_%' AND (coalesce(qual,'')||coalesce(with_check,'')) LIKE '%alcanca_anexo%') t(n);
