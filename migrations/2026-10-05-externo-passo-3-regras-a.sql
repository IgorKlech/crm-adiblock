-- =========================================================================
-- VENDEDOR EXTERNO — PASSO 3 de 5: regras de acesso — empresas, contatos, oportunidades
-- =========================================================================
-- DEPOIS DESTE: abra o CRM como admin e confira Empresas e Pipeline.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- A última linha do resultado diz OK ou ERRO. Só siga para o próximo passo com OK.
-- Origem: 2026-10-05-vendedor-externo.sql (o mesmo SQL, fatiado).
-- =========================================================================
-- BLOCO 4 — POLICIES. É ESTE que muda comportamento.
-- Para quem não é externo, cada policy fica EQUIVALENTE à da 91f: o termo
-- novo é `NOT (SELECT is_externo()) OR ...`, verdadeiro para todo interno.
-- `(SELECT ...)` vira initplan: avaliado uma vez por consulta, não por linha.
-- =========================================================================
BEGIN;

-- companies — inline (não via alcanca_empresa) para o INSERT ... RETURNING
-- do próprio cadastro enxergar a linha recém-criada.
DROP POLICY IF EXISTS "companies_select"       ON public.companies;
DROP POLICY IF EXISTS "companies_insert"       ON public.companies;
DROP POLICY IF EXISTS "companies_update_owner" ON public.companies;
DROP POLICY IF EXISTS "companies_delete_owner" ON public.companies;
CREATE POLICY "companies_select" ON public.companies FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND (
    NOT (SELECT public.is_externo())
    OR ((SELECT public.sessao_com_2fa()) AND (
         vendedor_responsavel_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.company_access a
                     WHERE a.company_id = companies.id AND a.profile_id = auth.uid())))));
CREATE POLICY "companies_insert" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo())
                   OR ((SELECT public.sessao_com_2fa()) AND vendedor_responsavel_id = auth.uid())));
CREATE POLICY "companies_update_owner" ON public.companies FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND public.alcanca_empresa(id))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
              AND public.alcanca_empresa(id));
-- excluir empresa (e o fluxo LGPD) fica com o escritório
CREATE POLICY "companies_delete_owner" ON public.companies FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND NOT (SELECT public.is_externo()));

-- contacts
DROP POLICY IF EXISTS "contacts_select" ON public.contacts;
DROP POLICY IF EXISTS "contacts_write"  ON public.contacts;
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "contacts_write" ON public.contacts FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- opportunities
DROP POLICY IF EXISTS "opportunities_select" ON public.opportunities;
DROP POLICY IF EXISTS "opportunities_write"  ON public.opportunities;
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "opportunities_write" ON public.opportunities FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- opportunity_products
DROP POLICY IF EXISTS "opp_products_select" ON public.opportunity_products;
DROP POLICY IF EXISTS "opp_products_write"  ON public.opportunity_products;
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));
CREATE POLICY "opp_products_write" ON public.opportunity_products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));

-- interactions
DROP POLICY IF EXISTS "interactions_select" ON public.interactions;
DROP POLICY IF EXISTS "interactions_write"  ON public.interactions;
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));
CREATE POLICY "interactions_write" ON public.interactions FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_opp(opportunity_id)));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN n = 12 THEN 'OK — pode seguir'
            ELSE 'ERRO: esperado 12, veio ' || n || ' — NÃO siga, mande o print' END AS passo_3
  FROM (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename IN ('companies','contacts','opportunities','opportunity_products','interactions') AND (coalesce(qual,'')||coalesce(with_check,'')) ~* '(externo|alcanca)') t(n);
