-- =========================================================================
-- VENDEDOR EXTERNO — PASSO 4 de 5: regras de acesso — propostas, anexos, tarefas, produtos, histórico
-- =========================================================================
-- DEPOIS DESTE: abra o CRM como admin e confira Propostas, Hoje e Dashboard.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- A última linha do resultado diz OK ou ERRO. Só siga para o próximo passo com OK.
-- Origem: 2026-10-05-vendedor-externo.sql (o mesmo SQL, fatiado).
-- =========================================================================
BEGIN;

-- proposals — inline pelo mesmo motivo de companies (INSERT ... RETURNING)
DROP POLICY IF EXISTS "proposals_select"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_insert"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_delete"        ON public.proposals;
DROP POLICY IF EXISTS "proposals_update_status" ON public.proposals;
CREATE POLICY "proposals_select" ON public.proposals FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND (
    NOT (SELECT public.is_externo())
    OR ((SELECT public.sessao_com_2fa()) AND CASE
          WHEN company_id IS NULL THEN seller_id = auth.uid()
          ELSE public.alcanca_empresa(company_id) END)));
CREATE POLICY "proposals_insert" ON public.proposals FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "proposals_delete" ON public.proposals FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND public.is_admin());
CREATE POLICY "proposals_update_status" ON public.proposals FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)))
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

-- proposal_revisions (continua só SELECT + INSERT — histórico não se reescreve)
DROP POLICY IF EXISTS "prop_rev_select" ON public.proposal_revisions;
DROP POLICY IF EXISTS "prop_rev_insert" ON public.proposal_revisions;
CREATE POLICY "prop_rev_select" ON public.proposal_revisions FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "prop_rev_insert" ON public.proposal_revisions FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));

-- attachments (metadado)
DROP POLICY IF EXISTS "anexos_select" ON public.attachments;
DROP POLICY IF EXISTS "anexos_insert" ON public.attachments;
DROP POLICY IF EXISTS "anexos_delete" ON public.attachments;
CREATE POLICY "anexos_select" ON public.attachments FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "anexos_insert" ON public.attachments FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));
CREATE POLICY "anexos_delete" ON public.attachments FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid())
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_proposta(proposal_id)));

-- tasks — externo vê só as próprias (interno continua vendo as da org)
DROP POLICY IF EXISTS "tasks_select"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_own" ON public.tasks;
DROP POLICY IF EXISTS "tasks_delete_own" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo())
              OR ((SELECT public.sessao_com_2fa()) AND seller_id = auth.uid())));
CREATE POLICY "tasks_insert" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (seller_id = auth.uid() OR public.is_admin())
              AND (NOT (SELECT public.is_externo())
                   OR company_id IS NULL OR public.alcanca_empresa(company_id)));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid())
              AND (NOT (SELECT public.is_externo())
                   OR company_id IS NULL OR public.alcanca_empresa(company_id)));
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));

-- products — externo NÃO lê a tabela (tem o custo); lê produtos_venda()
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated
  USING (org_id = public.current_org() AND NOT (SELECT public.is_externo()));

-- audit_log — guarda old_data/new_data de TUDO: externo só das empresas dele
DROP POLICY IF EXISTS "audit_select" ON public.audit_log;
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo())
              OR (company_id IS NOT NULL AND public.alcanca_empresa(company_id))));

-- lgpd_requests
DROP POLICY IF EXISTS "lgpd_select" ON public.lgpd_requests;
DROP POLICY IF EXISTS "lgpd_insert" ON public.lgpd_requests;
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org()
         AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org()
              AND (NOT (SELECT public.is_externo()) OR public.alcanca_empresa(company_id)));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN n = 15 THEN 'OK — pode seguir'
            ELSE 'ERRO: esperado 15, veio ' || n || ' — NÃO siga, mande o print' END AS passo_4
  FROM (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename IN ('proposals','proposal_revisions','attachments','tasks','products','audit_log','lgpd_requests') AND (coalesce(qual,'')||coalesce(with_check,'')) ~* '(externo|alcanca)') t(n);
