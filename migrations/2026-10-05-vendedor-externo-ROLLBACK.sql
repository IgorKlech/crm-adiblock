-- #########################################################################
-- ##  SÓ RODE SE DER ERRADO — e só se alguém pedir.                       ##
-- ##  Este arquivo DESFAZ o vendedor externo. Rodá-lo logo depois da      ##
-- ##  migration anula a migration (foi o que aconteceu em 05/10/2026).    ##
-- #########################################################################
-- =========================================================================
-- ROLLBACK de 2026-10-05-vendedor-externo.sql
-- =========================================================================
-- Devolve as policies EXATAMENTE como estavam (91f + revisão de pedidos +
-- anexos) e desliga as guardas. NÃO apaga company_access nem
-- company_access_requests: tabela sem policy que a use é inofensiva, e
-- apagar perderia quem tinha acesso a quê. O DROP delas está no fim,
-- comentado, para quando houver certeza.
--
-- Rode em BLOCOS, como a migration. Antes do Bloco R2, nenhum usuário deve
-- estar com role 'externo' — o R1 cuida disso.
-- =========================================================================


-- BLOCO R1 — tira o papel externo de quem o tem e devolve propostas
--            aguardando aceite para "em andamento" (o CHECK antigo não as aceita)
BEGIN;
UPDATE public.profiles  SET role = 'leitor'        WHERE role = 'externo';
UPDATE public.proposals SET status = 'em_andamento' WHERE status = 'aguardando_aceite';
COMMIT;
-- conferência (deve dar 0 e 0):
-- SELECT (SELECT count(*) FROM public.profiles WHERE role='externo') AS externos,
--        (SELECT count(*) FROM public.proposals WHERE status='aguardando_aceite') AS aguardando;


-- BLOCO R2 — policies de volta ao estado anterior
BEGIN;

DROP POLICY IF EXISTS "companies_select"       ON public.companies;
DROP POLICY IF EXISTS "companies_insert"       ON public.companies;
DROP POLICY IF EXISTS "companies_update_owner" ON public.companies;
DROP POLICY IF EXISTS "companies_delete_owner" ON public.companies;
CREATE POLICY "companies_select" ON public.companies FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "companies_insert" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
CREATE POLICY "companies_update_owner" ON public.companies FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));
CREATE POLICY "companies_delete_owner" ON public.companies FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));

DROP POLICY IF EXISTS "contacts_select" ON public.contacts;
DROP POLICY IF EXISTS "contacts_write"  ON public.contacts;
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "contacts_write" ON public.contacts FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "opportunities_select" ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_write"  ON public.opportunities;
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opportunities_write" ON public.opportunities FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "opp_products_select" ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_write"  ON public.opportunity_products;
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opp_products_write" ON public.opportunity_products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "interactions_select" ON public.interactions;
DROP POLICY IF EXISTS "interactions_write"  ON public.interactions;
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "interactions_write" ON public.interactions FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "proposals_select"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_insert"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_delete"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_update_status" ON public.proposals;
CREATE POLICY "proposals_select" ON public.proposals FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "proposals_insert" ON public.proposals FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
CREATE POLICY "proposals_delete" ON public.proposals FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND public.is_admin());
CREATE POLICY "proposals_update_status" ON public.proposals FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "prop_rev_select" ON public.proposal_revisions;
DROP POLICY IF EXISTS "prop_rev_insert" ON public.proposal_revisions;
CREATE POLICY "prop_rev_select" ON public.proposal_revisions FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "prop_rev_insert" ON public.proposal_revisions FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

DROP POLICY IF EXISTS "anexos_select" ON public.attachments;
DROP POLICY IF EXISTS "anexos_insert" ON public.attachments;
DROP POLICY IF EXISTS "anexos_delete" ON public.attachments;
CREATE POLICY "anexos_select" ON public.attachments FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "anexos_insert" ON public.attachments FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
CREATE POLICY "anexos_delete" ON public.attachments FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));

DROP POLICY IF EXISTS "tasks_select"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_own" ON public.tasks;
DROP POLICY IF EXISTS "tasks_delete_own" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "tasks_insert" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (seller_id = auth.uid() OR public.is_admin()));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));

DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated
  USING (org_id = public.current_org());

DROP POLICY IF EXISTS "audit_select" ON public.audit_log;
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated
  USING (org_id = public.current_org());

DROP POLICY IF EXISTS "lgpd_select" ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_insert" ON public.lgpd_requests;
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org());

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

NOTIFY pgrst, 'reload schema';

-- conferência (deve dar 0 — nenhuma policy citando externo):
-- SELECT count(*) FROM pg_policies
--  WHERE coalesce(qual,'') || coalesce(with_check,'') ILIKE '%externo%'
--    AND tablename NOT IN ('company_access','company_access_requests');


-- BLOCO R3 — guardas e status
-- A view NÃO volta a ignorar o RLS: aquilo era brecha, não comportamento.
BEGIN;
DROP TRIGGER IF EXISTS tg_aa_guarda_externo ON public.proposals;
DROP TRIGGER IF EXISTS tg_aa_guarda_externo ON public.companies;
ALTER TABLE public.proposals DROP CONSTRAINT IF EXISTS proposals_status_check;
ALTER TABLE public.proposals ADD CONSTRAINT proposals_status_check
  CHECK (status IN ('em_andamento','pedido','expedido','cancelada'));
COMMIT;
-- conferência (deve dar 0):
-- SELECT count(*) FROM pg_trigger WHERE tgname = 'tg_aa_guarda_externo';


-- OPCIONAL, só com certeza de que não volta — perde quem tinha acesso a quê:
--   DROP TABLE IF EXISTS public.company_access_requests;
--   DROP TABLE IF EXISTS public.company_access;
--   ALTER TABLE public.proposals DROP COLUMN IF EXISTS aceite_solicitado_em,
--     DROP COLUMN IF EXISTS aceite_solicitado_por, DROP COLUMN IF EXISTS aceite_em,
--     DROP COLUMN IF EXISTS aceite_por, DROP COLUMN IF EXISTS aceite_recusa_motivo;
-- =========================================================================
