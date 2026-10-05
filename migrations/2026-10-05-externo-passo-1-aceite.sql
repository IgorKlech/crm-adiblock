-- =========================================================================
-- VENDEDOR EXTERNO — PASSO 1 de 5: status "aguardando aceite" + guarda das propostas
-- =========================================================================
-- Não muda nada para quem já usa o CRM.
-- Como rodar: SQL Editor > New query > cole o ARQUIVO INTEIRO > Run.
-- A última linha do resultado diz OK ou ERRO. Só siga para o próximo passo com OK.
-- Origem: 2026-10-05-vendedor-externo.sql (o mesmo SQL, fatiado).
-- =========================================================================
-- BLOCO 2 — aceite de pedido (status novo + guarda do externo em proposals)
-- =========================================================================
BEGIN;

-- 2a) status 'aguardando_aceite'. Troca o CHECK antigo (achado pela definição,
--     não pelo nome, pra não depender de como o Postgres o batizou).
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.proposals'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%em_andamento%'
  LOOP
    EXECUTE format('ALTER TABLE public.proposals DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
ALTER TABLE public.proposals ADD CONSTRAINT proposals_status_check
  CHECK (status IN ('em_andamento','aguardando_aceite','pedido','expedido','cancelada'));

-- 2b) rastro do aceite. Em coluna (não no snapshot): é cumprimento, não negociação.
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS aceite_solicitado_em  timestamptz,
  ADD COLUMN IF NOT EXISTS aceite_solicitado_por uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aceite_em             timestamptz,
  ADD COLUMN IF NOT EXISTS aceite_por            uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aceite_recusa_motivo  text;

-- 2c) guarda. A trava de "externo não fecha pedido sozinho" mora AQUI, não
--     no botão: quem chamar a API pelo console esbarra na exceção.
CREATE OR REPLACE FUNCTION public.proposals_guarda_externo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_externo() THEN
    -- escritório aceitando: registra quem e quando
    IF TG_OP = 'UPDATE' AND OLD.status = 'aguardando_aceite' AND NEW.status = 'pedido' THEN
      NEW.aceite_em  := now();
      NEW.aceite_por := auth.uid();
      NEW.aceite_recusa_motivo := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.seller_id := auth.uid();
    IF coalesce(NEW.status, 'em_andamento') <> 'em_andamento' THEN
      RAISE EXCEPTION 'Proposta nova começa em andamento.';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status NOT IN ('em_andamento','aguardando_aceite') THEN
    RAISE EXCEPTION 'Este pedido já foi aceito pelo escritório — alterações passam pelo escritório.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'em_andamento'      AND NEW.status IN ('aguardando_aceite','cancelada'))
    OR (OLD.status = 'aguardando_aceite' AND NEW.status IN ('em_andamento','cancelada'))
  ) THEN
    RAISE EXCEPTION 'Vendedor externo não pode passar para "%": o pedido precisa do aceite do escritório.', NEW.status;
  END IF;
  IF NEW.status = 'aguardando_aceite' AND OLD.status <> 'aguardando_aceite' THEN
    NEW.aceite_solicitado_em  := now();
    NEW.aceite_solicitado_por := auth.uid();
    NEW.aceite_recusa_motivo  := NULL;
  END IF;
  -- campos que só o escritório escreve
  NEW.seller_id      := OLD.seller_id;
  NEW.pedido_numero  := OLD.pedido_numero;
  NEW.pedido_ano     := OLD.pedido_ano;
  NEW.nf_numero      := OLD.nf_numero;
  NEW.transportadora := OLD.transportadora;
  NEW.aceite_em      := OLD.aceite_em;
  NEW.aceite_por     := OLD.aceite_por;
  RETURN NEW;
END $$;

-- "tg_aa_" ordena antes de "tg_atribui_numero_pedido": a guarda roda primeiro.
DROP TRIGGER IF EXISTS tg_aa_guarda_externo ON public.proposals;
CREATE TRIGGER tg_aa_guarda_externo BEFORE INSERT OR UPDATE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.proposals_guarda_externo();

COMMIT;

-- CONFERÊNCIA (é o resultado que aparece na tela)
SELECT CASE WHEN n = 2 THEN 'OK — pode seguir'
            ELSE 'ERRO: esperado 2, veio ' || n || ' — NÃO siga, mande o print' END AS passo_1
  FROM (SELECT (SELECT count(*) FROM pg_trigger WHERE tgname='tg_aa_guarda_externo' AND tgrelid='public.proposals'::regclass) + (SELECT count(*) FROM pg_constraint WHERE conname='proposals_status_check' AND pg_get_constraintdef(oid) LIKE '%aguardando_aceite%')) t(n);
