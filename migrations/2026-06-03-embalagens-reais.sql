-- =========================================================================
-- Migracao 2026-06-03 — Embalagens reais (com peso/volume no nome)
-- =========================================================================
-- Corrige as embalagens do catalogo para o formato real com peso embutido
-- (ex: "Tambor" -> "Tambor 250", "CNT" -> "CNT 1250", "Bombona 20" ->
-- "Bombona 25"). Isso faz o calculo de "Qtd de embalagens" no Pedido de
-- Producao funcionar para todos os produtos (pesoDaEmbalagem le o numero
-- do nome da embalagem).
--
-- SEGURANCA:
-- - So altera a coluna `embalagem` (e o nome do PRIME JD) — PRECOS preservados.
-- - Idempotente: rodar 2x nao causa dano (a 2a vez nao encontra os antigos).
-- - Pareamento feito linha a linha contra o catalogo real do banco em 03/06/2026.
--
-- Produtos fora da lista nova:
--   ADIGROUT AR PLUS -> MANTIDO (continua ativo)
--   ADIPOX, MORFLOOR HR, VERTICAL CURE -> EXCLUIDOS (sairam de linha)
-- =========================================================================

-- ── Bombonas ──
UPDATE public.products SET embalagem='Bombona 25' WHERE embalagem='Bombona 20' AND nome IN ('ACCELIK AS','ACCELIK SF','EDIMPER PLUS');
UPDATE public.products SET embalagem='Bombona 24' WHERE embalagem='Bombona 20' AND nome IN ('ACEPESS FAST','FASTER','RETARTIVE WR 2010','RETARPEG S');
UPDATE public.products SET embalagem='Bombona 22' WHERE embalagem='Bombona 20' AND nome='RETARTIVE WR 2048';
UPDATE public.products SET embalagem='Bombona 60' WHERE embalagem='Bombona 50' AND nome IN ('ACCELIK AS','ACCELIK SF','EDIMPER PLUS','ACEPESS FAST','FASTER','RETARTIVE WR 2010','RETARPEG S');
UPDATE public.products SET embalagem='Bombona 55' WHERE embalagem='Bombona 50' AND nome='RETARTIVE WR 2048';

-- ── Tambores ──
UPDATE public.products SET embalagem='Tambor 200' WHERE embalagem='Tambor' AND nome IN ('ACS 800','CI 900','CURE CA','EDIMPER M','HYDROFLEX RR','HYDROFLEX RS','HYDROFLEX S','HYDROFLEX S A','INCORPOR BS PLUS','INCORPOR BS-D','KOLA','KOLA PLUS TIX','KOLA PVA','KOLA SBR','KOLA SUPER','PLASTICIZER BINDER','PLASTICIZER CW','PLASTICIZER HC','PLASTICIZER PREMIUM','PLASTICIZER SAD','PLASTICIZER SAD 20','RELENT','RELENT AD','RELENT BASE','RELENT BIO-VO','RELENT CONCENTRATE','RELENT RTU','RELENT S','RELENT SMO','RELENT SUPER','RELENT W','WP ARCON','WP TILE PRO');
UPDATE public.products SET embalagem='Tambor 240' WHERE embalagem='Tambor' AND nome IN ('POLYPLAST 146','POLYPLAST 151','POLYPLAST 167','POLYPLAST 170 D','POLYPLAST 170 PLUS','POLYPLAST 4300','ACEPESS FAST','FASTER','RETARPEG S','RETARTIVE WR 2010','SUPERFLUID AC');
UPDATE public.products SET embalagem='Tambor 250' WHERE embalagem='Tambor' AND nome IN ('ACCELIK AS','ACCELIK SF','EDIMPER PLUS','LIKTIVE ACEP UF');
UPDATE public.products SET embalagem='Tambor 220' WHERE embalagem='Tambor' AND nome='RETARTIVE WR 2048';
UPDATE public.products SET embalagem='Tambor 180' WHERE embalagem='Tambor' AND nome='WP FLEXIBLE';

-- ── CNTs ──
UPDATE public.products SET embalagem='CNT 1000' WHERE embalagem='CNT' AND nome IN ('ACS 800','CI 900','CURE CA','EDIMPER M','HYDROFLEX RR','HYDROFLEX RS','HYDROFLEX S','HYDROFLEX S A','INCORPOR BS PLUS','INCORPOR BS-D','KOLA','KOLA PLUS TIX','KOLA SBR','KOLA SUPER','PLASTICIZER BINDER','PLASTICIZER CW','PLASTICIZER HC','PLASTICIZER PREMIUM','PLASTICIZER SAD','PLASTICIZER SAD 20','RELENT','RELENT AD','RELENT BIO-VO','RELENT CONCENTRATE','RELENT RTU');
UPDATE public.products SET embalagem='CNT 1200' WHERE embalagem='CNT' AND nome IN ('POLYPLAST 146','POLYPLAST 151','POLYPLAST 167','POLYPLAST 170 D','POLYPLAST 170 PLUS','POLYPLAST 4300','ACEPESS FAST','FASTER','RETARTIVE WR 2010','SUPERFLUID AC');
UPDATE public.products SET embalagem='CNT 1250' WHERE embalagem='CNT' AND nome IN ('ACCELIK AS','ACCELIK SF','EDIMPER PLUS');
UPDATE public.products SET embalagem='CNT 1100' WHERE embalagem='CNT' AND nome='RETARTIVE WR 2048';

-- ── Sacos e Balde ──
UPDATE public.products SET embalagem='Saco 20'  WHERE embalagem='Saco 30' AND nome='CEPAS INJECT BC';
UPDATE public.products SET embalagem='Saco 20'  WHERE embalagem='Saco 25' AND nome IN ('WP CRYSTAL','WP HYDRACEM UF');
UPDATE public.products SET embalagem='Balde 18' WHERE embalagem='Balde'   AND nome='RELEASE WAX';

-- ── Conjuntos (cada um com seu peso) ──
UPDATE public.products SET embalagem='Conjunto 35,4' WHERE embalagem='Conjunto' AND nome='ARGAPOL 592 IC Conjunto';
UPDATE public.products SET embalagem='Conjunto 6'    WHERE embalagem='Conjunto' AND nome='ARGAPOL 992 Conjunto';
UPDATE public.products SET embalagem='Conjunto 35'   WHERE embalagem='Conjunto' AND nome='ARGAPOL BC Conjunto';
UPDATE public.products SET embalagem='Conjunto 22'   WHERE embalagem='Conjunto' AND nome='FLUXYGROUT HMR CONJUNTO';
UPDATE public.products SET embalagem='Conjunto 28'   WHERE embalagem='Conjunto' AND nome='FLUXYGROUT SOFT CONJUNTO';
UPDATE public.products SET embalagem='Conjunto 40'   WHERE embalagem='Conjunto' AND nome IN ('MINERAL REPAIR 132 Conjunto','MINERAL REPAIR 333 Conjunto','MINERAL REPAIR 499 Conjunto','WHITE MINERAL REPAIR CONJUNTO');
UPDATE public.products SET embalagem='Conjunto 5'    WHERE embalagem='Conjunto' AND nome='POLYSEL CONJUNTO';
UPDATE public.products SET embalagem='Conjunto 1'    WHERE embalagem='Conjunto' AND nome IN ('STRUCTURAL AD CONJUNTO','STRUCTURAL TF CONJUNTO');
UPDATE public.products SET embalagem='Conjunto 20'   WHERE embalagem='Conjunto' AND nome='SUPROFLEX CONJUNTO';

-- ── PRIME JD: nome + embalagem mudam ──
UPDATE public.products SET nome='Prime JD Conjunto', embalagem='Conjunto 1'
  WHERE nome IN ('PRIME JD CONJUNTO 1KG','PRIME JD CONJUNTO');

-- ── Produtos que sairam de linha (ADIGROUT AR PLUS fica) ──
DELETE FROM public.products WHERE nome IN ('ADIPOX','MORFLOOR HR','VERTICAL CURE');

NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- Conferencia (deve voltar so os 4 produtos fora da lista, ou vazio):
--   SELECT nome, embalagem FROM public.products
--   WHERE embalagem IN ('Tambor','CNT','Conjunto','Balde') ORDER BY nome;
-- =========================================================================
