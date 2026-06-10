-- =========================================================================
-- Sprint 9.1 — Etapa F (executa 3º/ultimo): LIGA O ISOLAMENTO (policies RLS)
-- =========================================================================
-- ESTE e o ponto que muda o comportamento: cada org passa a ver SO os seus
-- dados. Roda DEPOIS de 91d e 91e. Envolto em transacao (tudo ou nada).
--
-- ANTES DE RODAR:
--   1) Clique "Baixar Backup" no Dashboard.
--   2) Tenha o arquivo 91f-ROLLBACK aberto (desfaz em segundos se preciso).
--   3) Horario de baixo uso.
-- DEPOIS DE RODAR: rodar o CHECKLIST de isolamento (ver fim do arquivo).
-- Ref: docs/MULTI-TENANT.md (Etapa F).
-- =========================================================================

BEGIN;

-- organizations: endurece a policy temporaria (so a propria org)
DROP POLICY IF EXISTS "orgs_select_tmp" ON public.organizations;
DROP POLICY IF EXISTS "orgs_select_own" ON public.organizations;
CREATE POLICY "orgs_select_own" ON public.organizations FOR SELECT TO authenticated
  USING (id = public.current_org());

-- profiles  (admin tambem enxerga/edita perfis ORFAOS - sem org - p/ atribuir org
--            a um vendedor recem-criado. Onboarding/convites = fase 2.)
DROP POLICY IF EXISTS "profiles_select"       ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_self"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_admin" ON public.profiles;
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated
  USING (org_id = public.current_org() OR (org_id IS NULL AND public.is_admin()));
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "profiles_update_admin" ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_admin() AND (org_id = public.current_org() OR org_id IS NULL))
  WITH CHECK (public.is_admin() AND org_id = public.current_org());
CREATE POLICY "profiles_delete_admin" ON public.profiles FOR DELETE TO authenticated
  USING (public.is_admin() AND (org_id = public.current_org() OR org_id IS NULL));

-- companies
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

-- contacts
DROP POLICY IF EXISTS "contacts_select" ON public.contacts;
DROP POLICY IF EXISTS "contacts_write"  ON public.contacts;
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "contacts_write" ON public.contacts FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

-- opportunities
DROP POLICY IF EXISTS "opportunities_select" ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_write"  ON public.opportunities;
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opportunities_write" ON public.opportunities FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

-- opportunity_products
DROP POLICY IF EXISTS "opp_products_select" ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_write"  ON public.opportunity_products;
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opp_products_write" ON public.opportunity_products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

-- interactions
DROP POLICY IF EXISTS "interactions_select" ON public.interactions;
DROP POLICY IF EXISTS "interactions_write"  ON public.interactions;
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "interactions_write" ON public.interactions FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());

-- proposals
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

-- tasks
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

-- products
DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_write"  ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "products_write" ON public.products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND public.is_admin())
  WITH CHECK (org_id = public.current_org() AND public.is_admin());

-- audit_log  (le so a propria org; insert continua liberado p/ o trigger)
DROP POLICY IF EXISTS "audit_select" ON public.audit_log;
DROP POLICY IF EXISTS "audit_insert" ON public.audit_log;
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "audit_insert" ON public.audit_log FOR INSERT TO authenticated
  WITH CHECK (true);

-- lgpd_requests
DROP POLICY IF EXISTS "lgpd_select" ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_insert" ON public.lgpd_requests;
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org());

-- pedido_sequences
DROP POLICY IF EXISTS "pedido_seq_admin" ON public.pedido_sequences;
CREATE POLICY "pedido_seq_admin" ON public.pedido_sequences FOR ALL TO authenticated
  USING (org_id = public.current_org() AND public.is_admin())
  WITH CHECK (org_id = public.current_org() AND public.is_admin());

COMMIT;

NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- CHECKLIST DE ISOLAMENTO (rodar LOGADO no app, nao no SQL Editor):
--   1) Logado como Adiblock: aba Empresas mostra as empresas normais. OK.
--   2) Criar empresa, gerar proposta, marcar pedido -> tudo funciona.
--   3) Dashboard/Pipeline/Propostas carregam normal.
--   Se algo aparecer VAZIO pra Adiblock -> current_org() do usuario esta NULL
--   (perfil sem org). Rodar:  SELECT id, name, org_id FROM profiles;  e
--   atribuir org_id aos perfis sem org. Se nao resolver -> rodar o ROLLBACK.
--
-- Teste multi-org completo (opcional, com org fake) esta em docs/MULTI-TENANT.md (secao 4).
-- =========================================================================
