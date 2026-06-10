-- =========================================================================
-- Sprint 9.1 — Etapa E (executa 1º de E/D/F): fundação do isolamento
--   current_org() + auto-preenchimento de org_id + audit com org_id
-- =========================================================================
-- SEGURA: NAO muda comportamento visivel (policies ainda permissivas). Apenas
-- garante que TODO novo registro nasce com org_id = a org do usuario logado.
-- Isso e pre-requisito do NOT NULL (proxima etapa). Idempotente.
--
-- ATENCAO ordem: roda DEPOIS de 91a/91b/91c e ANTES do NOT NULL (91e).
-- NAO mexe em pedido_sequences/atribui_numero_pedido (isso fica na 91e, junto
-- com a troca da PK pra (org_id, ano)).
-- Ref: docs/MULTI-TENANT.md (Etapa E).
-- =========================================================================

-- 1) current_org(): a org do usuario logado (lida de profiles.org_id)
CREATE OR REPLACE FUNCTION public.current_org()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.current_org() TO authenticated;

-- 2) set_org_id(): preenche org_id no INSERT quando vier nulo (o front nao manda)
CREATE OR REPLACE FUNCTION public.set_org_id()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.org_id IS NULL THEN
    NEW.org_id := public.current_org();
  END IF;
  RETURN NEW;
END $$;

-- Aplica BEFORE INSERT nas tabelas de dados (NAO em profiles/organizations/audit_log)
DROP TRIGGER IF EXISTS tg_set_org_id ON public.companies;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.companies            FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.contacts;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.contacts             FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.opportunities;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.opportunities        FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.opportunity_products;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.opportunity_products FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.interactions;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.interactions         FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.proposals;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.proposals            FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.tasks;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.tasks                FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.products;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.products             FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.lgpd_requests;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.lgpd_requests        FOR EACH ROW EXECUTE FUNCTION public.set_org_id();
DROP TRIGGER IF EXISTS tg_set_org_id ON public.pedido_sequences;
CREATE TRIGGER tg_set_org_id BEFORE INSERT ON public.pedido_sequences     FOR EACH ROW EXECUTE FUNCTION public.set_org_id();

-- 3) log_audit_changes(): agora grava org_id (resto IDENTICO ao original).
--    set_org_id (BEFORE) ja preencheu NEW.org_id antes deste AFTER rodar.
CREATE OR REPLACE FUNCTION public.log_audit_changes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id    uuid;
  v_user_name  text;
  v_user_role  text;
  v_row_id     uuid;
  v_company_id uuid;
  v_org_id     uuid;
  v_old_jsonb  jsonb;
  v_new_jsonb  jsonb;
  v_changes    jsonb;
  k            text;
BEGIN
  v_user_id := auth.uid();
  SELECT name, role INTO v_user_name, v_user_role FROM public.profiles WHERE id = v_user_id;

  IF TG_OP = 'DELETE' THEN
    v_old_jsonb := to_jsonb(OLD);
    v_row_id := (v_old_jsonb->>'id')::uuid;
    v_company_id := COALESCE(
      NULLIF(v_old_jsonb->>'company_id','')::uuid,
      CASE WHEN TG_TABLE_NAME = 'companies' THEN v_row_id ELSE NULL END
    );
  ELSE
    v_new_jsonb := to_jsonb(NEW);
    v_row_id := (v_new_jsonb->>'id')::uuid;
    v_company_id := COALESCE(
      NULLIF(v_new_jsonb->>'company_id','')::uuid,
      CASE WHEN TG_TABLE_NAME = 'companies' THEN v_row_id ELSE NULL END
    );
    IF TG_OP = 'UPDATE' THEN
      v_old_jsonb := to_jsonb(OLD);
      v_changes := '[]'::jsonb;
      FOR k IN SELECT jsonb_object_keys(v_new_jsonb) LOOP
        IF k IN ('updated_at','estagio_changed_at','closed_at') THEN CONTINUE; END IF;
        IF (v_new_jsonb->k) IS DISTINCT FROM (v_old_jsonb->k) THEN
          v_changes := v_changes || jsonb_build_array(jsonb_build_object('field', k, 'from', v_old_jsonb->k, 'to', v_new_jsonb->k));
        END IF;
      END LOOP;
      IF jsonb_array_length(v_changes) = 0 THEN RETURN NEW; END IF;
    END IF;
  END IF;

  -- org_id: do registro auditado (ja preenchido pelo set_org_id) ou da sessao
  v_org_id := COALESCE(
    NULLIF(COALESCE(v_new_jsonb, v_old_jsonb)->>'org_id','')::uuid,
    public.current_org()
  );

  INSERT INTO public.audit_log (table_name, row_id, action, user_id, user_name, user_role, old_data, new_data, changes, company_id, org_id)
  VALUES (TG_TABLE_NAME, v_row_id, TG_OP, v_user_id, v_user_name, v_user_role, v_old_jsonb, v_new_jsonb, v_changes, v_company_id, v_org_id);

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- TESTE OBRIGATORIO antes da proxima etapa (91e):
--   1) Pelo APP (logado), crie uma empresa de teste.
--   2) Rode e confirme que ela nasceu com org_id preenchido:
--        SELECT razao_social, org_id FROM public.companies
--         ORDER BY created_at DESC LIMIT 1;
--      -> org_id deve ser o da Adiblock (00000000-0000-0000-0000-0000000000a1)
--   3) Confirme current_org():  SELECT public.current_org();  -> nao pode ser NULL
--   (Pode apagar a empresa de teste depois.)
-- =========================================================================

-- =========================================================================
-- ROLLBACK (Etapa E):
--   DROP TRIGGER IF EXISTS tg_set_org_id ON public.companies;  (idem demais tabelas)
--   DROP FUNCTION IF EXISTS public.set_org_id();
--   DROP FUNCTION IF EXISTS public.current_org();
--   -- restaurar log_audit_changes da versao sem org_id (supabase_setup.sql)
-- =========================================================================
