-- =========================================================================
-- 2026-08-17 — Anexos do pedido (O4): bucket privado + metadados
-- =========================================================================
-- POR QUE
--   A OC assinada e o comprovante vivem na caixa de e-mail de quem recebeu.
--   Quem precisa depois nao acha, e quando a pessoa esta de folga ninguem
--   acha. O CRM ja guarda o pedido; falta guardar o papel que veio junto.
--
-- ESCOPO: anexo pertence a uma PROPOSTA/PEDIDO. Foto de obra em oportunidade
--   foi descartada pelo Igor em 17/08, entao nao ha tabela generica: o anexo
--   tem `proposal_id` com FK de verdade e ON DELETE CASCADE. Integridade
--   referencial de graca, em vez de um par (entidade, entidade_id) sem FK.
--
-- ⚠ SOBRE "so le quem tem login"
--   O bucket e privado, entao o arquivo nao e alcancavel por URL direta e o
--   RLS so libera pra quem esta autenticado na organizacao dona. Mas o app
--   acessa por URL ASSINADA, e uma URL assinada e um portador: quem receber o
--   link abre o arquivo ate ele expirar, mesmo sem login. Nao da pra eliminar
--   isso sem servidor proprio (restricao do projeto). A mitigacao e VALIDADE
--   CURTA — o app vai gerar links de 60 segundos, o suficiente pra abrir e
--   curto demais pra circular. Fica dito porque a diferenca importa: nao e
--   "so quem tem login le", e "so quem tem login CONSEGUE O LINK, e o link
--   morre em 1 minuto".
--
-- ⚠ LGPD
--   Apagar a empresa NAO apaga estes anexos: `proposals.company_id` e
--   ON DELETE SET NULL, ou seja, a proposta sobrevive a exclusao da empresa —
--   e o anexo com ela. E uma OC tem CNPJ, endereco e nome de pessoa.
--   Por isso a exclusao LGPD no app tera de, nesta ordem:
--     1) apagar os OBJETOS no Storage das propostas daquela empresa
--     2) apagar as linhas de attachments
--     3) so entao apagar a empresa
--   Cascata de banco nunca alcanca arquivo no Storage. A CASCADE abaixo cobre
--   o caso de a PROPOSTA ser excluida, e ainda assim so o metadado.
--
-- SEGURO DE RODAR: cria bucket e tabela novos, nao toca em nada existente.
-- Idempotente.
--
-- ANTES DE RODAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
-- =========================================================================

BEGIN;

-- ── 1) O bucket ──────────────────────────────────────────────────────────
-- public=false: sem isso, qualquer um com a URL le o arquivo pra sempre.
-- Teto de 10 MB e tipos fechados — foto de celular passa de 5 MB com
-- facilidade e o plano Free tem 1 GB no total.
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
CREATE TABLE IF NOT EXISTS public.attachments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  proposal_id   uuid NOT NULL REFERENCES public.proposals(id) ON DELETE CASCADE,
  caminho       text NOT NULL UNIQUE,   -- caminho no bucket; unico evita metadado duplicado
  nome_original text NOT NULL,          -- o nome que o usuario reconhece
  mime          text,
  tamanho       bigint,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_anexos_proposta
  ON public.attachments(org_id, proposal_id, created_at DESC);

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
-- ganho. Sem UPDATE: troca-se apagando e subindo de novo, e assim created_by
-- nunca mente sobre quem pos o arquivo ali.
CREATE POLICY "anexos_delete" ON public.attachments FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));

-- ── 4) RLS do STORAGE ────────────────────────────────────────────────────
-- O isolamento de verdade. Sem isto a tabela filtra por org mas o ARQUIVO
-- fica alcancavel por qualquer usuario autenticado que descubra o caminho.
-- `storage.foldername(name)` devolve as pastas; a [1] e o org_id — por isso
-- o caminho e {org_id}/proposals/{proposal_id}/{arquivo}.
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
-- CONFERENCIA — rode e mande a saida
-- =========================================================================
--   SELECT id, public, file_size_limit, allowed_mime_types
--     FROM storage.buckets WHERE id = 'anexos';        -- public TEM QUE SER false
--
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename = 'objects' AND policyname LIKE 'anexos_%'
--    ORDER BY policyname;                              -- 3 linhas
--
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename = 'attachments' ORDER BY policyname;   -- 3 linhas
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
