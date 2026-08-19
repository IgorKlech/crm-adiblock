-- =========================================================================
-- 2026-08-17 — Anexos (O4): bucket no Storage + tabela de metadados
-- =========================================================================
-- POR QUE
--   Hoje a OC assinada, a foto da obra e o comprovante vivem na caixa de
--   e-mail de quem recebeu. Quem precisa depois nao acha, e quando a pessoa
--   esta de folga ninguem acha. O CRM ja guarda o pedido; falta guardar o
--   papel que veio junto.
--
-- DESENHO — as tres decisoes que sustentam o resto:
--
--   1. BUCKET PRIVADO, nao publico.
--      Uma OC tem preco, CNPJ e dados do cliente. Bucket publico significa
--      que qualquer um com a URL le o arquivo, para sempre, sem login. O
--      acesso passa a ser por URL ASSINADA com validade curta, gerada pelo
--      app depois do RLS aprovar.
--
--   2. UMA TABELA GENERICA, nao uma por entidade.
--      `attachments(entidade, entidade_id)` aponta pra proposta, empresa ou
--      oportunidade. Fosse uma coluna `proposal_id`, anexar foto de obra numa
--      oportunidade exigiria outra tabela e outra tela. O custo e nao ter FK
--      real — resolvido pela limpeza descrita em (3).
--
--   3. O CAMINHO COMECA PELO org_id.
--      `{org_id}/{entidade}/{entidade_id}/{arquivo}` — e o que permite a
--      policy do Storage filtrar por organizacao, lendo a primeira pasta do
--      caminho. Sem isso nao ha isolamento multi-tenant no bucket, so na
--      tabela — e o arquivo e o dado que importa.
--
-- ⚠ LGPD — O PONTO QUE MAIS IMPORTA AQUI
--   Apagar a empresa CASCATEIA a linha de metadados, mas NAO apaga o arquivo
--   no Storage. Metadado some, arquivo fica, e o dado pessoal sobrevive — o
--   oposto do que a exclusao LGPD promete.
--   Por isso o app tem que remover os OBJETOS DO STORAGE ANTES de apagar a
--   empresa. A cascata aqui e rede de seguranca contra metadado orfao, nunca
--   a forma primaria de apagar. Ver executarExclusaoLgpd().
--
-- SEGURO DE RODAR: cria bucket e tabela novos. Nao toca em nada existente.
-- Idempotente.
--
-- ANTES DE RODAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
-- =========================================================================

BEGIN;

-- ── 1) O bucket ──────────────────────────────────────────────────────────
-- public=false, teto de 10 MB por arquivo e lista de tipos fechada. O teto
-- existe porque foto de celular passa de 5 MB com facilidade e o plano Free
-- tem 1 GB no total; a lista fechada evita que o bucket vire deposito.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'anexos', 'anexos', false, 10485760,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ── 2) Metadados ─────────────────────────────────────────────────────────
-- Sem FK pra entidade de proposito (ver decisao 2). `entidade` e fechado por
-- CHECK, que e o que impede erro de digitacao virar anexo invisivel.
CREATE TABLE IF NOT EXISTS public.attachments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  entidade      text NOT NULL CHECK (entidade IN ('proposal','company','opportunity')),
  entidade_id   uuid NOT NULL,
  caminho       text NOT NULL UNIQUE,   -- caminho no bucket; unico evita metadado duplicado
  nome_original text NOT NULL,          -- o nome que o usuario reconhece
  mime          text,
  tamanho       bigint,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_anexos_entidade
  ON public.attachments(org_id, entidade, entidade_id, created_at DESC);

-- org_id automatico, mesmo padrao da etapa 91d
DROP TRIGGER IF EXISTS tg_set_org_id ON public.attachments;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.attachments
  FOR EACH ROW EXECUTE FUNCTION public.set_org_id();

-- ── 3) RLS da tabela ─────────────────────────────────────────────────────
ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anexos_select" ON public.attachments;
DROP POLICY IF EXISTS "anexos_insert" ON public.attachments;
DROP POLICY IF EXISTS "anexos_delete" ON public.attachments;

CREATE POLICY "anexos_select" ON public.attachments FOR SELECT TO authenticated
  USING (org_id = public.current_org());

CREATE POLICY "anexos_insert" ON public.attachments FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

-- Apagar so quem subiu, ou o admin. Anexo costuma ser prova (OC assinada,
-- comprovante) — qualquer um poder apagar o documento do outro e risco sem
-- ganho. Sem UPDATE: anexo se troca apagando e subindo de novo, e assim o
-- created_by nunca mente sobre quem pos o arquivo ali.
CREATE POLICY "anexos_delete" ON public.attachments FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));

-- ── 4) RLS do STORAGE ────────────────────────────────────────────────────
-- Aqui esta o isolamento de verdade: sem isto, a tabela filtra por org mas o
-- ARQUIVO fica acessivel a qualquer usuario autenticado que descubra o
-- caminho. `storage.foldername(name)` devolve as pastas do caminho; a [1] e o
-- org_id, por isso ele vem primeiro.
DROP POLICY IF EXISTS "anexos_obj_select" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_insert" ON storage.objects;
DROP POLICY IF EXISTS "anexos_obj_delete" ON storage.objects;

CREATE POLICY "anexos_obj_select" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text);

CREATE POLICY "anexos_obj_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'anexos'
              AND (storage.foldername(name))[1] = public.current_org()::text
              AND NOT public.is_leitor());

CREATE POLICY "anexos_obj_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'anexos'
         AND (storage.foldername(name))[1] = public.current_org()::text);

COMMIT;

-- =========================================================================
-- CONFERENCIA
-- =========================================================================
--   SELECT id, public, file_size_limit, allowed_mime_types
--     FROM storage.buckets WHERE id = 'anexos';        -- public tem que ser false
--
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename = 'objects' AND policyname LIKE 'anexos_%';   -- 3 linhas
--
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename = 'attachments';                  -- 3 linhas
--
-- ROLLBACK (apaga os anexos junto — so use se nada foi enviado ainda):
--   BEGIN;
--   DROP POLICY IF EXISTS "anexos_obj_select" ON storage.objects;
--   DROP POLICY IF EXISTS "anexos_obj_insert" ON storage.objects;
--   DROP POLICY IF EXISTS "anexos_obj_delete" ON storage.objects;
--   DROP TABLE IF EXISTS public.attachments;
--   DELETE FROM storage.objects WHERE bucket_id = 'anexos';
--   DELETE FROM storage.buckets WHERE id = 'anexos';
--   COMMIT;
-- =========================================================================
