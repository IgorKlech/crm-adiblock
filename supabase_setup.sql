-- =========================================================================
-- CRM Adiblock — Setup completo (rodar uma vez no SQL Editor do Supabase)
-- Resolve o erro: relation "public.client_products" does not exist
-- E cria o catálogo de produtos (Tabela de Preços 2025) para autocomplete
-- =========================================================================

-- -------------------------------------------------------------------------
-- 0) Garante todas as colunas que o app envia (idempotente)
--    Resolve: "Could not find the 'loss_reason' column of 'clients'..."
-- -------------------------------------------------------------------------
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS produto            text,
  ADD COLUMN IF NOT EXISTS peso               text,
  ADD COLUMN IF NOT EXISTS seller_name        text,
  ADD COLUMN IF NOT EXISTS status             text DEFAULT 'Pendente',
  ADD COLUMN IF NOT EXISTS loss_reason        text,
  ADD COLUMN IF NOT EXISTS callback_date      date,
  ADD COLUMN IF NOT EXISTS estimated_value    numeric(12,2),
  ADD COLUMN IF NOT EXISTS observation        text,
  ADD COLUMN IF NOT EXISTS internal_notes     text,
  ADD COLUMN IF NOT EXISTS status_changed_at  timestamptz,
  ADD COLUMN IF NOT EXISTS created_at         timestamptz DEFAULT now(),
  -- Fase 4: dados fiscais e da obra (usados nas cotações)
  ADD COLUMN IF NOT EXISTS endereco           text,
  ADD COLUMN IF NOT EXISTS cidade             text,
  ADD COLUMN IF NOT EXISTS uf                 text,
  ADD COLUMN IF NOT EXISTS cep                text,
  ADD COLUMN IF NOT EXISTS cnpj               text,
  ADD COLUMN IF NOT EXISTS ie                 text,
  ADD COLUMN IF NOT EXISTS obra               text,
  ADD COLUMN IF NOT EXISTS contato_outros     text, -- usado como "Solicitante" na proposta
  ADD COLUMN IF NOT EXISTS email              text;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS seller_status      text DEFAULT 'Disponível',
  -- Fase 4: dados do contato Office e Solicitação que aparecem no rodapé da cotação
  ADD COLUMN IF NOT EXISTS telefone           text,
  ADD COLUMN IF NOT EXISTS office_nome        text,
  ADD COLUMN IF NOT EXISTS office_email       text,
  ADD COLUMN IF NOT EXISTS office_telefone    text,
  ADD COLUMN IF NOT EXISTS solic_nome         text,
  ADD COLUMN IF NOT EXISTS solic_email        text,
  ADD COLUMN IF NOT EXISTS solic_telefone     text;

-- call_history (usado pelo histórico de contatos)
CREATE TABLE IF NOT EXISTS public.call_history (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  seller_id     uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  datetime      timestamptz NOT NULL DEFAULT now(),
  result        text,
  next_callback date,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.call_history
  ADD COLUMN IF NOT EXISTS next_callback date,
  ADD COLUMN IF NOT EXISTS notes         text;

CREATE INDEX IF NOT EXISTS idx_call_history_client_id ON public.call_history(client_id);

ALTER TABLE public.call_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_ch" ON public.call_history;
CREATE POLICY "auth_all_ch" ON public.call_history FOR ALL TO authenticated USING (true) WITH CHECK (true);


-- -------------------------------------------------------------------------
-- 1) client_products  (1 cliente → N produtos)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.client_products (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id   uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  produto     text NOT NULL,
  embalagem   text,
  peso        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Fase 2: garante a coluna embalagem em bancos antigos
ALTER TABLE public.client_products
  ADD COLUMN IF NOT EXISTS embalagem text;

-- Backfill: linhas legadas têm produto = "NOME (Embalagem)"
-- → separar em produto + embalagem (idempotente: só roda em linhas sem embalagem ainda)
UPDATE public.client_products
SET
  embalagem = TRIM(SUBSTRING(produto FROM '\(([^)]+)\)\s*$')),
  produto   = TRIM(REGEXP_REPLACE(produto, '\s*\([^)]+\)\s*$', ''))
WHERE embalagem IS NULL
  AND produto ~ '\([^)]+\)\s*$';

-- Fase 3: quantidade numérica (kg) e preço negociado por kg
ALTER TABLE public.client_products
  ADD COLUMN IF NOT EXISTS qtd_kg   numeric(12,2),
  ADD COLUMN IF NOT EXISTS preco_kg numeric(10,2);

-- Backfill qtd_kg: tenta extrair primeiro número de peso (ex: "60 Kg" → 60)
UPDATE public.client_products
SET qtd_kg = NULLIF(REPLACE(SUBSTRING(peso FROM '([0-9]+(?:[.,][0-9]+)?)'), ',', '.'), '')::numeric
WHERE qtd_kg IS NULL AND peso IS NOT NULL AND peso ~ '[0-9]';

CREATE INDEX IF NOT EXISTS idx_client_products_client_id
  ON public.client_products(client_id);

ALTER TABLE public.client_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_read_cp"   ON public.client_products;
DROP POLICY IF EXISTS "auth_insert_cp" ON public.client_products;
DROP POLICY IF EXISTS "auth_update_cp" ON public.client_products;
DROP POLICY IF EXISTS "auth_delete_cp" ON public.client_products;

CREATE POLICY "auth_read_cp"   ON public.client_products FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_cp" ON public.client_products FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_update_cp" ON public.client_products FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_delete_cp" ON public.client_products FOR DELETE TO authenticated USING (true);


-- -------------------------------------------------------------------------
-- 2) products  (catálogo da Tabela de Preços 2025)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                 text NOT NULL,
  embalagem            text NOT NULL,
  preco_materia_prima  numeric(10,3) NOT NULL,
  preco_office         numeric(10,2) NOT NULL,
  preco_pj             numeric(10,2) NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (nome, embalagem)
);

CREATE INDEX IF NOT EXISTS idx_products_nome ON public.products(nome);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_read_products" ON public.products;
CREATE POLICY "auth_read_products" ON public.products FOR SELECT TO authenticated USING (true);


-- -------------------------------------------------------------------------
-- 3) Seed dos produtos (re-runnable via ON CONFLICT)
-- -------------------------------------------------------------------------
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES
('ACCELIK AS','Bombona 20',1.492,6.98,7.12),
('ACCELIK AS','Bombona 50',1.492,6.68,6.82),
('ACCELIK AS','Tambor',1.492,6.24,6.38),
('ACCELIK AS','CNT',1.492,6.42,6.56),
('ACCELIK SF','Bombona 20',2.923,10.61,10.75),
('ACCELIK SF','Bombona 50',2.923,10.31,10.45),
('ACCELIK SF','Tambor',2.923,9.87,10.01),
('ACCELIK SF','CNT',2.923,10.04,10.19),
('ACCETIVE FC POWDER','Saco 20',3.708,11.09,11.23),
('ACEPESS FAST','Bombona 20',2.923,10.61,10.75),
('ACEPESS FAST','Bombona 50',2.923,10.31,10.45),
('ACEPESS FAST','Tambor',2.923,9.87,10.01),
('ACEPESS FAST','CNT',2.923,10.04,10.19),
('ACS 800','Bombona 20',1.250,6.37,6.51),
('ACS 800','Bombona 50',1.250,6.07,6.21),
('ACS 800','Tambor',1.250,5.63,5.77),
('ACS 800','CNT',1.250,5.80,5.95),
('ADIGROUT AR','Saco 25',0.840,3.82,3.97),
('ADIGROUT AR COMPLETE','Saco 25',0.585,3.18,3.32),
('ADIGROUT MC','Saco 25',1.688,5.97,6.12),
('ADIGROUT MIX','Saco 10',8.000,21.97,22.11),
('ADIGROUT MIX CONCRETE','Saco 10',8.400,22.98,23.12),
('ADIGROUT TIX','Saco 25',0.787,3.72,3.86),
('ADIGROUT UFR','Saco 25',1.992,6.74,6.89),
('ADIGROUT WHITE','Saco 25',2.511,8.06,8.20),
('ADIPOX','Conjunto',3.500,20.38,20.52),
('AGRECON POWDER','Saco 8',50.000,128.39,128.53),
('ARGAPOL 592 IC Conjunto','Conjunto',0.950,6.00,6.14),
('ARGAPOL 992 Conjunto','Conjunto',2.750,10.56,10.70),
('ARGAPOL BC Conjunto','Conjunto',1.200,6.63,6.77),
('ARGAPOL MRI','Saco 20',1.200,4.74,4.88),
('ARGAPOL RE 642','Saco 25',0.631,3.32,3.47),
('CEPAS INJECT','Saco 20',2.500,8.03,8.17),
('CEPAS INJECT BC','Saco 30',3.500,10.56,10.71),
('CI 900','Bombona 20',2.456,9.43,9.57),
('CI 900','Bombona 50',2.456,9.12,9.27),
('CI 900','Tambor',2.456,8.68,8.82),
('CI 900','CNT',2.456,8.86,9.00),
('CURE CA','Bombona 20',2.761,10.20,10.34),
('CURE CA','Bombona 50',2.761,9.90,10.04),
('CURE CA','Tambor',2.761,9.45,9.60),
('CURE CA','CNT',2.761,9.63,9.77),
('DRAMOR POWDER','Saco 20',5.702,16.14,16.29),
('EDIMPER M','Bombona 20',5.753,17.78,17.92),
('EDIMPER M','Bombona 50',5.753,17.48,17.62),
('EDIMPER M','Tambor',5.753,17.04,17.18),
('EDIMPER M','CNT',5.753,17.21,17.36),
('EDIMPER PLUS','Bombona 20',9.092,26.24,26.38),
('EDIMPER PLUS','Bombona 50',9.092,25.94,26.08),
('EDIMPER PLUS','Tambor',9.092,25.50,25.64),
('EDIMPER PLUS','CNT',9.092,25.67,25.82),
('EXPANDER 2019','Saco 10',2.350,7.77,7.92),
('EXPANFLUID IC','Saco 10',5.670,16.19,16.33),
('FASTER','Bombona 20',1.190,6.22,6.36),
('FASTER','Bombona 50',1.190,5.91,6.06),
('FASTER','Tambor',1.190,5.47,5.62),
('FASTER','CNT',1.190,5.65,5.79),
('FLUXYGROUT HMR CONJUNTO','Conjunto',22.000,65.95,66.09),
('FLUXYGROUT SOFT CONJUNTO','Conjunto',17.000,53.28,53.42),
('HYDROFLEX S A','Bombona 20',3.381,11.77,11.91),
('HYDROFLEX S A','Bombona 50',3.381,11.47,11.61),
('HYDROFLEX S A','Tambor',3.381,11.02,11.17),
('HYDROFLEX S A','CNT',3.381,11.20,11.35),
('HYDROFLEX SEL','Bombona 20',6.260,19.06,19.21),
('HYDROFLEX SEL','Bombona 50',6.260,18.76,18.90),
('HYDROFLEX RR','Bombona 20',30.000,79.22,79.36),
('HYDROFLEX RR','Bombona 50',30.000,78.92,79.06),
('HYDROFLEX RR','Tambor',30.000,78.48,78.62),
('HYDROFLEX RR','CNT',30.000,78.65,78.80),
('HYDROFLEX RS','Bombona 20',4.427,14.42,14.56),
('HYDROFLEX RS','Bombona 50',4.427,14.12,14.26),
('HYDROFLEX RS','Tambor',4.427,13.68,13.82),
('HYDROFLEX RS','CNT',4.427,13.85,14.00),
('HYDROFLEX S','Bombona 20',19.799,53.37,53.51),
('HYDROFLEX S','Bombona 50',19.799,53.07,53.21),
('HYDROFLEX S','Tambor',19.799,52.63,52.77),
('HYDROFLEX S','CNT',19.799,52.80,52.95),
('HYDROFLEX V2','Bombona 20',5.817,17.94,18.08),
('HYDROFLEX V2','Bombona 50',5.817,17.64,17.78),
('INCORPOR BS PLUS','Bombona 20',3.189,11.28,11.43),
('INCORPOR BS PLUS','Bombona 50',3.189,10.98,11.12),
('INCORPOR BS PLUS','Tambor',3.189,10.54,10.68),
('INCORPOR BS PLUS','CNT',3.189,10.72,10.86),
('INCORPOR BS-D','Bombona 20',1.602,7.26,7.41),
('INCORPOR BS-D','Bombona 50',1.602,6.96,7.10),
('INCORPOR BS-D','Tambor',1.602,6.52,6.66),
('INCORPOR BS-D','CNT',1.602,6.70,6.84),
('KOLA','Bombona 20',2.015,8.31,8.45),
('KOLA','Bombona 50',2.015,8.00,8.15),
('KOLA','Tambor',2.015,7.56,7.71),
('KOLA','CNT',2.015,7.74,7.88),
('KOLA PLUS TIX','Bombona 20',8.218,24.02,24.17),
('KOLA PLUS TIX','Bombona 50',8.218,23.72,23.87),
('KOLA PLUS TIX','Tambor',8.218,23.28,23.42),
('KOLA PLUS TIX','CNT',8.218,23.46,23.60),
('KOLA PVA','Bombona 20',1.087,5.96,6.10),
('KOLA PVA','Bombona 50',1.087,5.65,5.80),
('KOLA PVA','Tambor',1.087,5.21,5.35),
('KOLA SBR','Bombona 20',4.145,13.70,13.85),
('KOLA SBR','Bombona 50',4.145,13.40,13.54),
('KOLA SBR','Tambor',4.145,12.96,13.10),
('KOLA SBR','CNT',4.145,13.14,13.28),
('KOLA SUPER','Bombona 20',8.218,24.02,24.17),
('KOLA SUPER','Bombona 50',8.218,23.72,23.87),
('KOLA SUPER','Tambor',8.218,23.28,23.42),
('KOLA SUPER','CNT',8.218,23.46,23.60),
('LIKTIVE ACEP UF','Bombona 25',2.725,10.88,10.25),
('LIKTIVE ACEP UF','Bombona 60',2.725,9.81,9.95),
('LIKTIVE ACEP UF','Tambor',2.725,9.36,9.51),
('MINERAL REPAIR 132 Conjunto','Conjunto',2.205,8.00,8.80),
('MINERAL REPAIR 333 Conjunto','Conjunto',2.232,8.40,9.24),
('MINERAL REPAIR 499 Conjunto','Conjunto',3.086,8.00,8.80),
('MORFLOOR HR','Saco',0.749,3.72,3.86),
('PLASTICIZER BINDER','Bombona 20',2.419,9.33,9.47),
('PLASTICIZER BINDER','Bombona 50',2.419,9.03,9.17),
('PLASTICIZER BINDER','Tambor',2.419,8.59,8.73),
('PLASTICIZER BINDER','CNT',2.419,8.76,8.91),
('PLASTICIZER CW','Bombona 20',5.040,15.97,16.12),
('PLASTICIZER CW','Bombona 50',5.040,15.67,15.81),
('PLASTICIZER CW','Tambor',5.040,15.23,15.37),
('PLASTICIZER CW','CNT',5.040,15.41,15.55),
('PLASTICIZER HC','Bombona 20',4.822,15.42,15.56),
('PLASTICIZER HC','Bombona 50',4.822,15.12,15.26),
('PLASTICIZER HC','Tambor',4.822,14.99,15.14),
('PLASTICIZER HC','CNT',4.822,14.85,15.00),
('PLASTICIZER PREMIUM','Bombona 20',1.609,7.28,7.42),
('PLASTICIZER PREMIUM','Bombona 50',1.609,6.98,7.12),
('PLASTICIZER PREMIUM','Tambor',1.609,6.54,6.68),
('PLASTICIZER PREMIUM','CNT',1.609,6.71,6.86),
('PLASTICIZER SAD','Bombona 20',1.770,7.69,7.83),
('PLASTICIZER SAD','Bombona 50',1.770,7.38,7.53),
('PLASTICIZER SAD','Tambor',1.770,6.94,7.09),
('PLASTICIZER SAD','CNT',1.770,7.12,7.26),
('PLASTICIZER SAD 20','Bombona 20',1.270,6.42,6.56),
('PLASTICIZER SAD 20','Bombona 50',1.270,6.12,6.26),
('PLASTICIZER SAD 20','Tambor',1.270,5.68,5.82),
('PLASTICIZER SAD 20','CNT',1.270,5.85,6.00),
('POLYPLAST 146','Bombona 24',3.878,13.03,13.17),
('POLYPLAST 146','Bombona 60',3.878,12.73,12.87),
('POLYPLAST 146','Tambor',3.878,12.29,12.43),
('POLYPLAST 146','CNT',3.878,12.46,12.61),
('POLYPLAST 151','Bombona 24',3.900,13.08,13.23),
('POLYPLAST 151','Bombona 60',3.900,12.78,12.92),
('POLYPLAST 151','Tambor',3.900,12.34,12.48),
('POLYPLAST 151','CNT',3.900,12.52,12.66),
('POLYPLAST 167','Bombona 24',3.761,12.73,12.88),
('POLYPLAST 167','Bombona 60',3.761,12.43,12.57),
('POLYPLAST 167','Tambor',3.761,11.99,12.13),
('POLYPLAST 167','CNT',3.761,12.17,12.31),
('POLYPLAST 170 D','Bombona 24',2.672,9.97,10.12),
('POLYPLAST 170 D','Bombona 60',2.672,9.67,9.81),
('POLYPLAST 170 D','Tambor',2.672,9.23,9.37),
('POLYPLAST 170 D','CNT',2.672,9.41,9.55),
('POLYPLAST 170 PLUS','Bombona 24',2.834,10.38,10.53),
('POLYPLAST 170 PLUS','Bombona 60',2.834,10.08,10.22),
('POLYPLAST 170 PLUS','Tambor',2.834,9.64,9.78),
('POLYPLAST 170 PLUS','CNT',2.834,9.82,9.96),
('POLYPLAST 4300','Bombona 24',3.857,12.97,13.12),
('POLYPLAST 4300','Bombona 60',3.857,12.67,12.82),
('POLYPLAST 4300','Tambor',3.857,12.23,12.37),
('POLYPLAST 4300','CNT',3.857,12.41,12.55),
('POLYSEL CONJUNTO','Conjunto',85.000,224.38,224.52),
('PRIME JD CONJUNTO 1KG','Conjunto',100.353,267.57,267.71),
('RELEASE WAX','Balde',8.349,24.98,25.12),
('RELENT','Bombona 20',8.089,23.70,23.84),
('RELENT','Bombona 50',8.089,23.40,23.54),
('RELENT','Tambor',8.089,22.96,23.10),
('RELENT','CNT',8.089,23.13,23.28),
('RELENT AD','Bombona 20',23.998,86.90,87.15),
('RELENT AD','Bombona 50',23.060,86.30,86.80),
('RELENT AD','Tambor',23.998,83.00,83.30),
('RELENT AD','CNT',23.060,61.07,61.21),
('RELENT BASE','Tambor',17.000,45.35,45.49),
('RELENT BIO-VO','Bombona 20',11.896,33.34,33.49),
('RELENT BIO-VO','Bombona 50',11.896,33.04,33.19),
('RELENT BIO-VO','Tambor',11.896,32.60,32.74),
('RELENT BIO-VO','CNT',11.896,32.78,32.92),
('RELENT CONCENTRATE','Bombona 20',18.000,48.81,48.96),
('RELENT CONCENTRATE','Bombona 50',18.000,48.51,48.65),
('RELENT CONCENTRATE','Tambor',18.000,48.07,48.21),
('RELENT CONCENTRATE','CNT',18.000,48.25,48.39),
('RELENT RTU','Bombona 20',1.287,6.46,6.61),
('RELENT RTU','Bombona 50',1.287,6.16,6.30),
('RELENT RTU','Tambor',1.287,5.72,5.86),
('RELENT RTU','CNT',1.287,5.90,6.04),
('RELENT S','Bombona 20',2.149,8.65,8.79),
('RELENT S','Bombona 50',2.149,8.35,8.49),
('RELENT S','Tambor',2.149,7.72,7.86),
('RELENT SMO','Bombona 20',7.656,22.60,22.74),
('RELENT SMO','Bombona 50',7.656,22.30,22.44),
('RELENT SMO','Tambor',7.656,21.86,22.00),
('RELENT SUPER','Bombona 20',10.516,29.85,29.99),
('RELENT SUPER','Bombona 50',10.516,29.55,29.69),
('RELENT SUPER','Tambor',10.516,29.11,29.25),
('RELENT W','Bombona 20',8.176,23.92,24.06),
('RELENT W','Bombona 50',8.176,23.62,23.76),
('RELENT W','Tambor',8.176,23.18,23.32),
('RETARPEG S','Bombona 20',5.140,16.23,16.37),
('RETARPEG S','Bombona 50',5.140,15.93,16.07),
('RETARPEG S','Tambor',5.140,15.48,15.63),
('RETARTIVE WR 2010','Bombona 20',2.916,10.59,10.73),
('RETARTIVE WR 2010','Bombona 50',2.916,10.29,10.43),
('RETARTIVE WR 2010','Tambor',2.916,9.85,9.99),
('RETARTIVE WR 2010','CNT',2.916,10.03,10.17),
('RETARTIVE WR 2048','Bombona 20',2.410,9.31,9.45),
('RETARTIVE WR 2048','Bombona 50',2.410,9.01,9.15),
('RETARTIVE WR 2048','Tambor',2.410,8.56,8.71),
('RETARTIVE WR 2048','CNT',2.410,8.74,8.88),
('RUST CONVERTER','Bombona 25',11.284,31.79,31.94),
('RUST CONVERTER','Bombona 60',11.284,31.49,31.64),
('STRUCTURAL AD CONJUNTO','Conjunto',29.716,84.19,84.34),
('STRUCTURAL TF CONJUNTO','Conjunto',72.477,192.55,192.69),
('SUPERFLUID AC','Bombona 24',4.370,14.27,14.42),
('SUPERFLUID AC','Bombona 60',4.370,13.97,14.12),
('SUPERFLUID AC','Tambor',4.370,13.53,13.67),
('SUPERFLUID AC','CNT',4.370,13.71,13.85),
('VERTICAL CURE','Bombona 20',3.089,11.03,11.17),
('VERTICAL CURE','Bombona 50',3.089,10.73,10.87),
('VERTICAL CURE','Tambor',3.089,10.29,10.43),
('WHITE MINERAL REPAIR CONJUNTO','Conjunto',5.500,17.26,17.41),
('WP ARCON','Bombona 20',0.567,4.64,4.78),
('WP ARCON','Bombona 50',0.567,4.34,4.48),
('WP ARCON','Tambor',0.567,3.90,4.04),
('WP ARPOMON','Saco 20',0.933,4.06,4.20),
('WP CRYSTAL','Saco 25',1.957,6.65,6.80),
('WP FLEXIBLE','Bombona 18',4.125,13.65,13.80),
('WP FLEXIBLE','Bombona 42',3.102,10.76,10.90),
('WP FLEXIBLE','Tambor',4.125,12.91,13.05),
('WP HYDRACEM UF','Saco 25',5.075,14.55,14.70),
('SUFLEX GREY RA','Balde 18',8.193,24.44,24.59),
('SUFLEXIBLE RA','Balde 18',8.193,24.44,24.59),
('SUPROFLEX CONJUNTO','Conjunto',0.769,6.07,6.21),
('WP TILE PRO','Bombona 20',3.255,11.45,11.59),
('WP TILE PRO','Bombona 50',3.255,11.15,11.29),
('WP TILE PRO','Tambor',3.255,10.71,10.85)
ON CONFLICT (nome, embalagem) DO UPDATE SET
  preco_materia_prima = EXCLUDED.preco_materia_prima,
  preco_office        = EXCLUDED.preco_office,
  preco_pj            = EXCLUDED.preco_pj;


-- -------------------------------------------------------------------------
-- 4) proposals — propostas comerciais com numeração sequencial por ano
--    Numero formato: NNNN-AA (ex: 0142-26 = proposta 142 de 2026)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.proposals (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ano         int  NOT NULL DEFAULT EXTRACT(YEAR FROM now())::int,
  numero      int  NOT NULL,
  client_id   uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  seller_id   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  snapshot    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ano, numero)
);

CREATE INDEX IF NOT EXISTS idx_proposals_client_id ON public.proposals(client_id);
CREATE INDEX IF NOT EXISTS idx_proposals_ano_numero ON public.proposals(ano, numero DESC);

-- Trigger: atribui o próximo numero sequencial para o ano, atomicamente
-- (advisory lock evita race condition entre vendedores criando ao mesmo tempo)
CREATE OR REPLACE FUNCTION public.atribui_numero_proposta()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.numero IS NULL OR NEW.numero = 0 THEN
    PERFORM pg_advisory_xact_lock(hashtext('proposta_ano_' || NEW.ano));
    SELECT COALESCE(MAX(numero), 0) + 1 INTO NEW.numero
      FROM public.proposals WHERE ano = NEW.ano;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_atribui_numero_proposta ON public.proposals;
CREATE TRIGGER tg_atribui_numero_proposta
  BEFORE INSERT ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.atribui_numero_proposta();

ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_proposals" ON public.proposals;
CREATE POLICY "auth_all_proposals" ON public.proposals
  FOR ALL TO authenticated USING (true) WITH CHECK (true);


-- -------------------------------------------------------------------------
-- 5) Recarrega o schema do PostgREST (necessário para o embed funcionar já)
-- -------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
