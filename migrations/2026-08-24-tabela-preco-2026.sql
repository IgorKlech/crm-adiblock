-- =========================================================================
-- 2026-08-24 — Tabela de Preco 2026 nos produtos do catalogo
-- =========================================================================
-- ⚠ RODE UM BLOCO DE CADA VEZ. Nao cole o arquivo inteiro.
--
--   Na primeira tentativa o arquivo inteiro foi colado e o editor devolveu
--   "Success. No rows returned" sem ter criado a tabela de backup nem
--   aplicado um UPDATE sequer — conferido por sondagem em 13 pontos da lista.
--   Nao sei dizer o que o editor fez com as 392 linhas; sei que nao fez o que
--   estava escrito. Entao a migration passou a ser tres blocos pequenos, cada
--   um com resultado visivel na tela. Um bloco que nao roda vira erro na sua
--   frente, nao silencio.
--
-- O QUE FAZ
--   Atualiza preco_materia_prima, preco_office e preco_pj de 229 linhas de
--   public.products com os valores da Tabela de Preco 2026.
--
-- O QUE **NAO** FAZ, DE PROPOSITO
--   Nao toca em `nome` nem em `embalagem`. O catalogo do banco ja esta com as
--   embalagens REAIS (Tambor 250, CNT 1250, Bombona 24...) e a tabela impressa
--   usa as NOMINAIS (Tambor 200, CNT 1.000, Bombona 20). E do numero no nome
--   que `pesoDaEmbalagem()` tira quantos volumes o Pedido de Producao pede —
--   renomear quebraria o calculo na fabrica. 78 das 229 linhas caem nesse caso.
--
-- ⚠ products NAO TEM TRIGGER DE AUDITORIA
--   log_audit_changes() roda em companies, contacts, opportunities,
--   opportunity_products e proposals — products nao esta na lista. Um UPDATE
--   de preco nao deixa rastro nenhum. Por isso o BLOCO 1 existe e por isso ele
--   vem antes: sem ele, desfazer exigiria restaurar o banco inteiro por causa
--   de tres colunas.
--
-- ⚠ PROPOSTA JA EMITIDA NAO MUDA. `proposals.snapshot` e imutavel e guarda o
--   preco do dia da emissao. So proposta NOVA pega o preco novo.
--
-- ANTES DE COMECAR: clique "Baixar Backup" no Dashboard (Regra de Ouro nº 2).
-- =========================================================================


-- =========================================================================
-- BLOCO 1 de 3 — a rede de seguranca.  RODE SOZINHO.
-- =========================================================================
-- Guarda os precos de HOJE, direto da tabela viva. Tem que devolver uma linha
-- com a contagem; se devolver erro ou nada, PARE — nao siga para o bloco 2.
-- =========================================================================

CREATE TABLE IF NOT EXISTS public._bkp_precos_20260824 AS
SELECT id, nome, embalagem, preco_materia_prima, preco_office, preco_pj, now() AS salvo_em
  FROM public.products;

SELECT count(*) AS linhas_guardadas FROM public._bkp_precos_20260824;
-- ESPERADO: 233


-- =========================================================================
-- BLOCO 2 de 3 — os 229 precos.  SO DEPOIS de o bloco 1 ter devolvido 233.
-- =========================================================================
-- Cada UPDATE casa por (nome, embalagem) exatos do BANCO. Onde o nome da
-- embalagem difere da tabela impressa, o nome dela vai no comentario ao lado.
-- Seguro repetir: grava valor fixo, nao incrementa.
-- =========================================================================

UPDATE public.products SET preco_materia_prima=1.486, preco_office=7.18, preco_pj=7.33 WHERE nome='ACCELIK AS' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=1.486, preco_office=7.50, preco_pj=7.66 WHERE nome='ACCELIK AS' AND embalagem='Bombona 25';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=1.486, preco_office=6.89, preco_pj=7.05 WHERE nome='ACCELIK AS' AND embalagem='CNT 1250';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=1.486, preco_office=6.70, preco_pj=6.86 WHERE nome='ACCELIK AS' AND embalagem='Tambor 250';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.62, preco_pj=10.77 WHERE nome='ACCELIK SF' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.94, preco_pj=11.10 WHERE nome='ACCELIK SF' AND embalagem='Bombona 25';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.33, preco_pj=10.49 WHERE nome='ACCELIK SF' AND embalagem='CNT 1250';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.14, preco_pj=10.29 WHERE nome='ACCELIK SF' AND embalagem='Tambor 250';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=3.084, preco_office=10.24, preco_pj=10.40 WHERE nome='ACCETIVE FC POWDER' AND embalagem='Saco 20';
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.62, preco_pj=10.77 WHERE nome='ACEPESS FAST' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.94, preco_pj=11.10 WHERE nome='ACEPESS FAST' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.33, preco_pj=10.49 WHERE nome='ACEPESS FAST' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.746, preco_office=10.14, preco_pj=10.29 WHERE nome='ACEPESS FAST' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=1.250, preco_office=6.53, preco_pj=6.69 WHERE nome='ACS 800' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.250, preco_office=6.86, preco_pj=7.01 WHERE nome='ACS 800' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.250, preco_office=6.25, preco_pj=6.40 WHERE nome='ACS 800' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.250, preco_office=6.06, preco_pj=6.21 WHERE nome='ACS 800' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=0.989, preco_office=4.52, preco_pj=4.68 WHERE nome='ADIGROUT AR' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=0.684, preco_office=3.69, preco_pj=3.85 WHERE nome='ADIGROUT AR COMPLETE' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=1.780, preco_office=6.68, preco_pj=6.84 WHERE nome='ADIGROUT MC' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=8.000, preco_office=23.66, preco_pj=23.81 WHERE nome='ADIGROUT MIX' AND embalagem='Saco 10';
UPDATE public.products SET preco_materia_prima=8.400, preco_office=24.75, preco_pj=24.90 WHERE nome='ADIGROUT MIX CONCRETE' AND embalagem='Saco 10';
UPDATE public.products SET preco_materia_prima=0.942, preco_office=4.43, preco_pj=4.58 WHERE nome='ADIGROUT TIX' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=1.987, preco_office=7.25, preco_pj=7.40 WHERE nome='ADIGROUT UFR' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=2.514, preco_office=8.69, preco_pj=8.84 WHERE nome='ADIGROUT WHITE' AND embalagem='Saco 25';
UPDATE public.products SET preco_materia_prima=50.000, preco_office=138.27, preco_pj=138.42 WHERE nome='AGRECON POWDER' AND embalagem='Saco 8';
UPDATE public.products SET preco_materia_prima=0.950, preco_office=6.46, preco_pj=6.61 WHERE nome='ARGAPOL 592 IC Conjunto' AND embalagem='Conjunto 35,4';   -- tabela: Conjunto 35
UPDATE public.products SET preco_materia_prima=2.750, preco_office=11.37, preco_pj=11.53 WHERE nome='ARGAPOL 992 Conjunto' AND embalagem='Conjunto 6';
UPDATE public.products SET preco_materia_prima=1.200, preco_office=7.14, preco_pj=7.30 WHERE nome='ARGAPOL BC Conjunto' AND embalagem='Conjunto 35';
UPDATE public.products SET preco_materia_prima=1.200, preco_office=5.10, preco_pj=5.25 WHERE nome='ARGAPOL MRI' AND embalagem='Saco 20';
UPDATE public.products SET preco_materia_prima=1.198, preco_office=5.13, preco_pj=5.28 WHERE nome='ARGAPOL RE 642' AND embalagem='Saco 25';   -- tabela: Saco 20
UPDATE public.products SET preco_materia_prima=2.500, preco_office=8.65, preco_pj=8.80 WHERE nome='CEPAS INJECT' AND embalagem='Saco 20';
UPDATE public.products SET preco_materia_prima=3.500, preco_office=11.38, preco_pj=11.53 WHERE nome='CEPAS INJECT BC' AND embalagem='Saco 20';   -- tabela: Saco 30
UPDATE public.products SET preco_materia_prima=1.390, preco_office=6.92, preco_pj=7.07 WHERE nome='CI 900' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.390, preco_office=7.24, preco_pj=7.39 WHERE nome='CI 900' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.390, preco_office=6.63, preco_pj=6.79 WHERE nome='CI 900' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.390, preco_office=6.44, preco_pj=6.59 WHERE nome='CI 900' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=2.412, preco_office=9.71, preco_pj=9.86 WHERE nome='CURE CA' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=2.412, preco_office=10.03, preco_pj=10.18 WHERE nome='CURE CA' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=2.412, preco_office=9.42, preco_pj=9.58 WHERE nome='CURE CA' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=2.412, preco_office=9.23, preco_pj=9.38 WHERE nome='CURE CA' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=4.796, preco_office=14.91, preco_pj=15.07 WHERE nome='DRAMOR POWDER' AND embalagem='Saco 20';
UPDATE public.products SET preco_materia_prima=3.781, preco_office=13.44, preco_pj=13.59 WHERE nome='EDIMPER M' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=3.781, preco_office=13.77, preco_pj=13.92 WHERE nome='EDIMPER M' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=3.781, preco_office=13.16, preco_pj=13.31 WHERE nome='EDIMPER M' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=3.781, preco_office=12.97, preco_pj=13.12 WHERE nome='EDIMPER M' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=4.462, preco_office=15.30, preco_pj=15.45 WHERE nome='EDIMPER PLUS' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=4.462, preco_office=15.62, preco_pj=15.78 WHERE nome='EDIMPER PLUS' AND embalagem='Bombona 25';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=4.462, preco_office=15.01, preco_pj=15.17 WHERE nome='EDIMPER PLUS' AND embalagem='CNT 1250';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=4.462, preco_office=14.82, preco_pj=14.98 WHERE nome='EDIMPER PLUS' AND embalagem='Tambor 250';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.350, preco_office=8.37, preco_pj=8.53 WHERE nome='EXPANDER 2019' AND embalagem='Saco 10';
UPDATE public.products SET preco_materia_prima=5.022, preco_office=15.66, preco_pj=15.82 WHERE nome='EXPANFLUID IC' AND embalagem='Saco 10';
UPDATE public.products SET preco_materia_prima=1.134, preco_office=6.22, preco_pj=6.37 WHERE nome='FASTER' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=1.134, preco_office=6.54, preco_pj=6.70 WHERE nome='FASTER' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=1.134, preco_office=5.93, preco_pj=6.09 WHERE nome='FASTER' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=1.134, preco_office=5.74, preco_pj=5.90 WHERE nome='FASTER' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=22.000, preco_office=71.02, preco_pj=71.18 WHERE nome='FLUXYGROUT HMR CONJUNTO' AND embalagem='Conjunto 22';   -- tabela: Conjunto 20
UPDATE public.products SET preco_materia_prima=17.000, preco_office=57.38, preco_pj=57.53 WHERE nome='FLUXYGROUT SOFT CONJUNTO' AND embalagem='Conjunto 28';   -- tabela: Conjunto 20
UPDATE public.products SET preco_materia_prima=30.000, preco_office=84.99, preco_pj=85.14 WHERE nome='HYDROFLEX RR' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=30.000, preco_office=85.31, preco_pj=85.47 WHERE nome='HYDROFLEX RR' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=30.000, preco_office=84.70, preco_pj=84.86 WHERE nome='HYDROFLEX RR' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=30.000, preco_office=84.51, preco_pj=84.67 WHERE nome='HYDROFLEX RR' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=4.032, preco_office=14.13, preco_pj=14.28 WHERE nome='HYDROFLEX RS' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=4.032, preco_office=14.45, preco_pj=14.61 WHERE nome='HYDROFLEX RS' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=4.032, preco_office=13.84, preco_pj=14.00 WHERE nome='HYDROFLEX RS' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=4.032, preco_office=13.65, preco_pj=13.80 WHERE nome='HYDROFLEX RS' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=19.799, preco_office=57.15, preco_pj=57.31 WHERE nome='HYDROFLEX S' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=19.799, preco_office=57.48, preco_pj=57.63 WHERE nome='HYDROFLEX S' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=19.799, preco_office=56.87, preco_pj=57.02 WHERE nome='HYDROFLEX S' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=19.799, preco_office=56.68, preco_pj=56.83 WHERE nome='HYDROFLEX S' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=0.850, preco_office=5.44, preco_pj=5.60 WHERE nome='HYDROFLEX S A' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=0.850, preco_office=5.77, preco_pj=5.92 WHERE nome='HYDROFLEX S A' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=0.850, preco_office=5.16, preco_pj=5.31 WHERE nome='HYDROFLEX S A' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=0.850, preco_office=4.97, preco_pj=5.12 WHERE nome='HYDROFLEX S A' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=6.151, preco_office=19.91, preco_pj=20.06 WHERE nome='HYDROFLEX SEL' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.151, preco_office=20.23, preco_pj=20.39 WHERE nome='HYDROFLEX SEL' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=5.707, preco_office=18.70, preco_pj=18.85 WHERE nome='HYDROFLEX V2' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=5.707, preco_office=19.02, preco_pj=19.17 WHERE nome='HYDROFLEX V2' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.438, preco_office=7.05, preco_pj=7.20 WHERE nome='INCORPOR BS PLUS' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.438, preco_office=7.37, preco_pj=7.53 WHERE nome='INCORPOR BS PLUS' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.438, preco_office=6.76, preco_pj=6.92 WHERE nome='INCORPOR BS PLUS' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.438, preco_office=6.57, preco_pj=6.73 WHERE nome='INCORPOR BS PLUS' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=0.727, preco_office=5.11, preco_pj=5.26 WHERE nome='INCORPOR BS-D' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=0.727, preco_office=5.43, preco_pj=5.59 WHERE nome='INCORPOR BS-D' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=0.727, preco_office=4.82, preco_pj=4.98 WHERE nome='INCORPOR BS-D' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=0.727, preco_office=4.63, preco_pj=4.79 WHERE nome='INCORPOR BS-D' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.708, preco_office=7.79, preco_pj=7.94 WHERE nome='KOLA' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.708, preco_office=8.11, preco_pj=8.26 WHERE nome='KOLA' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.708, preco_office=7.50, preco_pj=7.65 WHERE nome='KOLA' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.708, preco_office=7.31, preco_pj=7.46 WHERE nome='KOLA' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=22.13, preco_pj=22.28 WHERE nome='KOLA PLUS TIX' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=22.46, preco_pj=22.61 WHERE nome='KOLA PLUS TIX' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=21.85, preco_pj=22.00 WHERE nome='KOLA PLUS TIX' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=21.65, preco_pj=21.81 WHERE nome='KOLA PLUS TIX' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=0.630, preco_office=4.84, preco_pj=5.00 WHERE nome='KOLA PVA' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=0.630, preco_office=5.17, preco_pj=5.32 WHERE nome='KOLA PVA' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=0.630, preco_office=4.37, preco_pj=4.52 WHERE nome='KOLA PVA' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=3.513, preco_office=12.71, preco_pj=12.86 WHERE nome='KOLA SBR' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=3.513, preco_office=13.04, preco_pj=13.19 WHERE nome='KOLA SBR' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=3.513, preco_office=12.43, preco_pj=12.58 WHERE nome='KOLA SBR' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=3.513, preco_office=12.23, preco_pj=12.39 WHERE nome='KOLA SBR' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=22.13, preco_pj=22.28 WHERE nome='KOLA SUPER' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=22.46, preco_pj=22.61 WHERE nome='KOLA SUPER' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=21.85, preco_pj=22.00 WHERE nome='KOLA SUPER' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=6.965, preco_office=21.65, preco_pj=21.81 WHERE nome='KOLA SUPER' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=2.454, preco_office=9.82, preco_pj=9.97 WHERE nome='LIKTIVE ACEP UF' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.454, preco_office=10.91, preco_pj=10.30 WHERE nome='LIKTIVE ACEP UF' AND embalagem='Bombona 25';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.454, preco_office=9.34, preco_pj=9.50 WHERE nome='LIKTIVE ACEP UF' AND embalagem='Tambor 250';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.035, preco_office=8.00, preco_pj=8.80 WHERE nome='MINERAL REPAIR 132 Conjunto' AND embalagem='Conjunto 40';
UPDATE public.products SET preco_materia_prima=2.014, preco_office=8.40, preco_pj=9.24 WHERE nome='MINERAL REPAIR 333 Conjunto' AND embalagem='Conjunto 40';
UPDATE public.products SET preco_materia_prima=2.690, preco_office=8.00, preco_pj=8.80 WHERE nome='MINERAL REPAIR 499 Conjunto' AND embalagem='Conjunto 40';
UPDATE public.products SET preco_materia_prima=1.701, preco_office=7.76, preco_pj=7.92 WHERE nome='PLASTICIZER BINDER' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.701, preco_office=8.09, preco_pj=8.24 WHERE nome='PLASTICIZER BINDER' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.701, preco_office=7.48, preco_pj=7.63 WHERE nome='PLASTICIZER BINDER' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.701, preco_office=7.29, preco_pj=7.44 WHERE nome='PLASTICIZER BINDER' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=4.334, preco_office=14.95, preco_pj=15.10 WHERE nome='PLASTICIZER CW' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=4.334, preco_office=15.27, preco_pj=15.43 WHERE nome='PLASTICIZER CW' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=4.334, preco_office=14.66, preco_pj=14.82 WHERE nome='PLASTICIZER CW' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=4.334, preco_office=14.47, preco_pj=14.63 WHERE nome='PLASTICIZER CW' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=3.386, preco_office=12.36, preco_pj=12.52 WHERE nome='PLASTICIZER HC' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=3.386, preco_office=12.69, preco_pj=12.84 WHERE nome='PLASTICIZER HC' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=3.386, preco_office=12.08, preco_pj=12.23 WHERE nome='PLASTICIZER HC' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=3.386, preco_office=12.23, preco_pj=12.38 WHERE nome='PLASTICIZER HC' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.843, preco_office=8.15, preco_pj=8.31 WHERE nome='PLASTICIZER PREMIUM' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.843, preco_office=8.48, preco_pj=8.63 WHERE nome='PLASTICIZER PREMIUM' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.843, preco_office=7.87, preco_pj=8.02 WHERE nome='PLASTICIZER PREMIUM' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.843, preco_office=7.68, preco_pj=7.83 WHERE nome='PLASTICIZER PREMIUM' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.810, preco_office=8.06, preco_pj=8.22 WHERE nome='PLASTICIZER SAD' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.810, preco_office=8.39, preco_pj=8.54 WHERE nome='PLASTICIZER SAD' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.810, preco_office=7.78, preco_pj=7.93 WHERE nome='PLASTICIZER SAD' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.810, preco_office=7.59, preco_pj=7.74 WHERE nome='PLASTICIZER SAD' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.270, preco_office=6.59, preco_pj=6.74 WHERE nome='PLASTICIZER SAD 20' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.270, preco_office=6.91, preco_pj=7.07 WHERE nome='PLASTICIZER SAD 20' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.270, preco_office=6.30, preco_pj=6.46 WHERE nome='PLASTICIZER SAD 20' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.270, preco_office=6.11, preco_pj=6.27 WHERE nome='PLASTICIZER SAD 20' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=3.543, preco_office=12.79, preco_pj=12.94 WHERE nome='POLYPLAST 146' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=3.543, preco_office=13.12, preco_pj=13.27 WHERE nome='POLYPLAST 146' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=3.543, preco_office=12.51, preco_pj=12.66 WHERE nome='POLYPLAST 146' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=3.543, preco_office=12.32, preco_pj=12.47 WHERE nome='POLYPLAST 146' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=3.576, preco_office=12.88, preco_pj=13.03 WHERE nome='POLYPLAST 151' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=3.576, preco_office=13.21, preco_pj=13.36 WHERE nome='POLYPLAST 151' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=3.576, preco_office=12.60, preco_pj=12.75 WHERE nome='POLYPLAST 151' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=3.576, preco_office=12.41, preco_pj=12.56 WHERE nome='POLYPLAST 151' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.745, preco_office=10.61, preco_pj=10.77 WHERE nome='POLYPLAST 167' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.745, preco_office=10.94, preco_pj=11.09 WHERE nome='POLYPLAST 167' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.745, preco_office=10.33, preco_pj=10.48 WHERE nome='POLYPLAST 167' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.745, preco_office=10.14, preco_pj=10.29 WHERE nome='POLYPLAST 167' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.400, preco_office=9.67, preco_pj=9.82 WHERE nome='POLYPLAST 170 D' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.400, preco_office=10.00, preco_pj=10.15 WHERE nome='POLYPLAST 170 D' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.400, preco_office=9.39, preco_pj=9.54 WHERE nome='POLYPLAST 170 D' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.400, preco_office=9.20, preco_pj=9.35 WHERE nome='POLYPLAST 170 D' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.550, preco_office=10.08, preco_pj=10.24 WHERE nome='POLYPLAST 170 PLUS' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.550, preco_office=10.41, preco_pj=10.56 WHERE nome='POLYPLAST 170 PLUS' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.550, preco_office=9.80, preco_pj=9.95 WHERE nome='POLYPLAST 170 PLUS' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.550, preco_office=9.61, preco_pj=9.76 WHERE nome='POLYPLAST 170 PLUS' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=3.589, preco_office=12.92, preco_pj=13.07 WHERE nome='POLYPLAST 4300' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=3.589, preco_office=13.24, preco_pj=13.40 WHERE nome='POLYPLAST 4300' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=3.589, preco_office=12.63, preco_pj=12.79 WHERE nome='POLYPLAST 4300' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=3.589, preco_office=12.44, preco_pj=12.59 WHERE nome='POLYPLAST 4300' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=85.000, preco_office=241.64, preco_pj=241.79 WHERE nome='POLYSEL CONJUNTO' AND embalagem='Conjunto 5';
UPDATE public.products SET preco_materia_prima=7.812, preco_office=25.44, preco_pj=25.59 WHERE nome='RELEASE WAX' AND embalagem='Balde 18';   -- tabela: Balde 14
UPDATE public.products SET preco_materia_prima=6.400, preco_office=20.59, preco_pj=20.74 WHERE nome='RELENT' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.400, preco_office=20.91, preco_pj=21.07 WHERE nome='RELENT' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=6.400, preco_office=20.30, preco_pj=20.46 WHERE nome='RELENT' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=6.400, preco_office=20.11, preco_pj=20.27 WHERE nome='RELENT' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=23.060, preco_office=66.05, preco_pj=66.20 WHERE nome='RELENT AD' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=14.870, preco_office=44.03, preco_pj=44.18 WHERE nome='RELENT AD' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=23.060, preco_office=65.77, preco_pj=65.92 WHERE nome='RELENT AD' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=14.870, preco_office=43.23, preco_pj=43.38 WHERE nome='RELENT AD' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=17.000, preco_office=48.84, preco_pj=48.99 WHERE nome='RELENT BASE' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=7.535, preco_office=23.69, preco_pj=23.84 WHERE nome='RELENT BIO-VO' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=7.535, preco_office=24.01, preco_pj=24.16 WHERE nome='RELENT BIO-VO' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=7.535, preco_office=23.40, preco_pj=23.56 WHERE nome='RELENT BIO-VO' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=7.535, preco_office=23.21, preco_pj=23.36 WHERE nome='RELENT BIO-VO' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=18.000, preco_office=52.24, preco_pj=52.40 WHERE nome='RELENT CONCENTRATE' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=18.000, preco_office=52.57, preco_pj=52.72 WHERE nome='RELENT CONCENTRATE' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=18.000, preco_office=51.96, preco_pj=52.11 WHERE nome='RELENT CONCENTRATE' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=18.000, preco_office=51.77, preco_pj=51.92 WHERE nome='RELENT CONCENTRATE' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.011, preco_office=5.88, preco_pj=6.04 WHERE nome='RELENT RTU' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=1.011, preco_office=6.21, preco_pj=6.36 WHERE nome='RELENT RTU' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=1.011, preco_office=5.60, preco_pj=5.75 WHERE nome='RELENT RTU' AND embalagem='CNT 1000';
UPDATE public.products SET preco_materia_prima=1.011, preco_office=5.41, preco_pj=5.56 WHERE nome='RELENT RTU' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=2.202, preco_office=9.13, preco_pj=9.28 WHERE nome='RELENT S' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=2.202, preco_office=9.46, preco_pj=9.61 WHERE nome='RELENT S' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=2.202, preco_office=8.46, preco_pj=8.61 WHERE nome='RELENT S' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=6.378, preco_office=20.53, preco_pj=20.68 WHERE nome='RELENT SMO' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.378, preco_office=20.85, preco_pj=21.01 WHERE nome='RELENT SMO' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=6.378, preco_office=20.05, preco_pj=20.21 WHERE nome='RELENT SMO' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=10.842, preco_office=32.71, preco_pj=32.86 WHERE nome='RELENT SUPER' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=10.842, preco_office=33.03, preco_pj=33.19 WHERE nome='RELENT SUPER' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=10.842, preco_office=32.23, preco_pj=32.39 WHERE nome='RELENT SUPER' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=6.401, preco_office=20.59, preco_pj=20.75 WHERE nome='RELENT W' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=6.401, preco_office=20.92, preco_pj=21.07 WHERE nome='RELENT W' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=6.401, preco_office=20.12, preco_pj=20.27 WHERE nome='RELENT W' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=4.741, preco_office=16.06, preco_pj=16.21 WHERE nome='RETARPEG S' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=4.741, preco_office=16.38, preco_pj=16.54 WHERE nome='RETARPEG S' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=4.741, preco_office=15.58, preco_pj=15.74 WHERE nome='RETARPEG S' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.744, preco_office=10.61, preco_pj=10.76 WHERE nome='RETARTIVE WR 2010' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.744, preco_office=10.93, preco_pj=11.09 WHERE nome='RETARTIVE WR 2010' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.744, preco_office=10.33, preco_pj=10.48 WHERE nome='RETARTIVE WR 2010' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.744, preco_office=10.13, preco_pj=10.29 WHERE nome='RETARTIVE WR 2010' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=2.873, preco_office=10.96, preco_pj=11.12 WHERE nome='RETARTIVE WR 2048' AND embalagem='Bombona 55';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=2.873, preco_office=11.29, preco_pj=11.44 WHERE nome='RETARTIVE WR 2048' AND embalagem='Bombona 22';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=2.873, preco_office=10.68, preco_pj=10.83 WHERE nome='RETARTIVE WR 2048' AND embalagem='CNT 1100';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=2.873, preco_office=10.49, preco_pj=10.64 WHERE nome='RETARTIVE WR 2048' AND embalagem='Tambor 220';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=8.655, preco_office=26.74, preco_pj=26.89 WHERE nome='RUST CONVERTER' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=8.655, preco_office=27.07, preco_pj=27.22 WHERE nome='RUST CONVERTER' AND embalagem='Bombona 25';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=17.070, preco_office=56.16, preco_pj=56.31 WHERE nome='STRUCTURAL AD CONJUNTO' AND embalagem='Conjunto 1';
UPDATE public.products SET preco_materia_prima=43.492, preco_office=128.26, preco_pj=128.42 WHERE nome='STRUCTURAL TF CONJUNTO' AND embalagem='Conjunto 1';
UPDATE public.products SET preco_materia_prima=7.018, preco_office=22.54, preco_pj=22.70 WHERE nome='SUFLEX GREY RA' AND embalagem='Balde 18';   -- tabela: Balde 20
UPDATE public.products SET preco_materia_prima=7.018, preco_office=22.54, preco_pj=22.70 WHERE nome='SUFLEXIBLE RA' AND embalagem='Balde 18';   -- tabela: Balde 20
UPDATE public.products SET preco_materia_prima=3.802, preco_office=13.50, preco_pj=13.65 WHERE nome='SUPERFLUID AC' AND embalagem='Bombona 60';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=3.802, preco_office=13.82, preco_pj=13.98 WHERE nome='SUPERFLUID AC' AND embalagem='Bombona 24';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=3.802, preco_office=13.21, preco_pj=13.37 WHERE nome='SUPERFLUID AC' AND embalagem='CNT 1200';   -- tabela: CNT 1000
UPDATE public.products SET preco_materia_prima=3.802, preco_office=13.02, preco_pj=13.18 WHERE nome='SUPERFLUID AC' AND embalagem='Tambor 240';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=1.071, preco_office=7.36, preco_pj=7.51 WHERE nome='SUPROFLEX CONJUNTO' AND embalagem='Conjunto 20';   -- tabela: Conjunto 18
UPDATE public.products SET preco_materia_prima=5.500, preco_office=18.59, preco_pj=18.74 WHERE nome='WHITE MINERAL REPAIR CONJUNTO' AND embalagem='Conjunto 40';
UPDATE public.products SET preco_materia_prima=0.493, preco_office=4.47, preco_pj=4.62 WHERE nome='WP ARCON' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=0.493, preco_office=4.79, preco_pj=4.95 WHERE nome='WP ARCON' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=0.493, preco_office=3.99, preco_pj=4.15 WHERE nome='WP ARCON' AND embalagem='Tambor 200';
UPDATE public.products SET preco_materia_prima=1.320, preco_office=5.43, preco_pj=5.58 WHERE nome='WP ARPOMON' AND embalagem='Saco 20';
UPDATE public.products SET preco_materia_prima=3.053, preco_office=10.16, preco_pj=10.31 WHERE nome='WP CRYSTAL' AND embalagem='Saco 20';   -- tabela: Saco 25
UPDATE public.products SET preco_materia_prima=6.457, preco_office=20.74, preco_pj=20.90 WHERE nome='WP FLEXIBLE' AND embalagem='Bombona 42';   -- tabela: Bombona 50
UPDATE public.products SET preco_materia_prima=6.457, preco_office=21.07, preco_pj=21.22 WHERE nome='WP FLEXIBLE' AND embalagem='Bombona 18';   -- tabela: Bombona 20
UPDATE public.products SET preco_materia_prima=6.457, preco_office=20.27, preco_pj=20.42 WHERE nome='WP FLEXIBLE' AND embalagem='Tambor 180';   -- tabela: Tambor 200
UPDATE public.products SET preco_materia_prima=4.298, preco_office=13.55, preco_pj=13.71 WHERE nome='WP HYDRACEM UF' AND embalagem='Saco 20';   -- tabela: Saco 25
UPDATE public.products SET preco_materia_prima=2.026, preco_office=8.65, preco_pj=8.81 WHERE nome='WP TILE PRO' AND embalagem='Bombona 50';
UPDATE public.products SET preco_materia_prima=2.026, preco_office=8.98, preco_pj=9.13 WHERE nome='WP TILE PRO' AND embalagem='Bombona 20';
UPDATE public.products SET preco_materia_prima=2.026, preco_office=8.18, preco_pj=8.33 WHERE nome='WP TILE PRO' AND embalagem='Tambor 200';


-- =========================================================================
-- BLOCO 3 de 3 — conferencia.  RODE SOZINHO, depois do bloco 2.
-- =========================================================================
SELECT (SELECT count(*) FROM public._bkp_precos_20260824)                    AS linhas_guardadas,
       (SELECT count(*) FROM public.products p
          JOIN public._bkp_precos_20260824 b ON b.id = p.id
         WHERE p.preco_office        IS DISTINCT FROM b.preco_office
            OR p.preco_pj            IS DISTINCT FROM b.preco_pj
            OR p.preco_materia_prima IS DISTINCT FROM b.preco_materia_prima) AS linhas_alteradas,
       (SELECT count(*) FROM public.products)                                AS total_no_catalogo,
       (SELECT count(*) FROM public.products WHERE preco_pj < preco_office)  AS margem_invertida;

-- ESPERADO: 233 · 228 · 233 · 1
--   228 e nao 229 porque o ACCELIK AS Bombona 25 ja estava com o preco de 2026
--   antes deste bloco (alterado a mao apos o export). O UPDATE dele grava o
--   mesmo valor, entao ele nao conta como alterado em relacao ao backup.
--   margem_invertida 1 = LIKTIVE ACEP UF, ver BLOCO B.


-- =========================================================================
-- BLOCO A (opcional) — as 19 linhas da tabela 2026 que NAO existem no catalogo
-- =========================================================================
-- MORFLOOR HR e VERTICAL CURE: apagados pela migration de 03/06/2026 ("sairam
--   de linha") e de volta na tabela 2026, com preco. Sem eles, o vendedor nao
--   acha o produto se o cliente pedir. Recomendo cadastrar.
--
-- MINERAL REPAIR / WHITE MINERAL REPAIR Comp.A e Comp.B: hoje so existe o
--   CONJUNTO. Decisao COMERCIAL: so cadastre se a equipe pode vender avulso.
--
-- PRIME JD: o banco tem `Prime JD Conjunto`. A tabela 2026 tem 1KG e 5KG. Se
--   for renomear em vez de criar, veja o BLOCO C.
--
-- ⚠ org_id: se products tem o trigger set_org_id, ele preenche sozinho. Se nao
--   tiver, o INSERT falha — acrescente a coluna org_id com o id da Adiblock.
-- =========================================================================
/*
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('ADIGROUT MIX CRYSTAL', 'Saco 10', 9.000, 26.39, 26.54) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('CONCREMOVER SUPER', 'Bombona 50', 1.761, 7.93, 8.08) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 132 Comp.A', 'Saco 20', 2.362, 8.87, 9.02) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 132 Comp.B', 'Balde 20', 1.708, 8.63, 8.79) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 333 Comp.A', 'Saco 20', 2.319, 8.74, 8.90) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 333 Comp.B', 'Balde 20', 1.708, 8.63, 8.79) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 499 Comp.A', 'Saco 20', 3.672, 12.77, 12.92) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MINERAL REPAIR 499 Comp.B', 'Balde 20', 1.708, 8.63, 8.79) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('MORFLOOR HR', 'Saco 25', 0.889, 4.39, 4.54) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('PRIME JD CONJUNTO 1KG', 'Conjunto 1', 54.368, 162.67, 162.82) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('PRIME JD CONJUNTO 5KG', 'Conjunto 6', 54.368, 172.26, 172.41) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('SUFLEX GREY RA', 'Balde 5', 8.094, 27.04, 27.20) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('SUFLEX GREY RA', 'Balde 3.6', 7.018, 23.12, 23.27) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('SUFLEXIBLE RA', 'Balde 5', 7.018, 24.11, 24.26) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('VERTICAL CURE', 'Bombona 50', 2.430, 9.75, 9.91) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('VERTICAL CURE', 'Bombona 20', 2.430, 10.08, 10.23) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('VERTICAL CURE', 'Tambor 200', 2.430, 9.28, 9.43) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('WHITE MINERAL REPAIR COMP.A', 'Saco 20', 3.672, 12.77, 12.92) ON CONFLICT (nome, embalagem) DO NOTHING;
INSERT INTO public.products (nome, embalagem, preco_materia_prima, preco_office, preco_pj) VALUES ('WHITE MINERAL REPAIR COMP.B', 'Bombona 20', 1.708, 8.69, 8.85) ON CONFLICT (nome, embalagem) DO NOTHING;
*/


-- =========================================================================
-- BLOCO B (opcional) — a margem invertida do LIKTIVE ACEP UF
-- =========================================================================
-- A tabela 2026 traz preco_pj MENOR que preco_office nessa linha (10,30 contra
-- 10,91): a venda com 10% de comissao sairia mais barata que a sem comissao.
-- O bloco 2 aplica a tabela COMO ELA E — nao inventei preco. Se voce confirmar
-- que e erro da planilha, este UPDATE corrige seguindo o mesmo espacamento das
-- outras linhas do produto (office + 0,15).
--
-- ⚠ Corrigir aqui e nao corrigir na planilha faz o erro voltar no ano que vem.
-- =========================================================================
/*
UPDATE public.products SET preco_pj = 11.03
 WHERE nome = 'LIKTIVE ACEP UF' AND embalagem = 'Bombona 25';
*/


-- =========================================================================
-- BLOCO C (opcional) — as 4 linhas do banco que a tabela 2026 nao lista
-- =========================================================================
--   ACCELIK AS               Bombona 6      office     6.98   (mantem o preco atual)
--   ADIGROUT AR PLUS         Saco 25        office     3.95   (mantem o preco atual)
--   KOLA                     Bombona 5      office     8.31   (mantem o preco atual)
--   Prime JD Conjunto        Conjunto 1     office   267.57   (mantem o preco atual)
--
-- Nenhuma precisa ser apagada:
--   ADIGROUT AR PLUS — a migration de junho ja mandava manter ("continua ativo")
--   ACCELIK AS Bombona 6 / KOLA Bombona 5 — embalagens pequenas fora da tabela.
--     Hoje custam o mesmo que a bombona seguinte. Pra manter essa relacao:
--       UPDATE public.products SET preco_materia_prima=1.486, preco_office=7.50, preco_pj=7.66
--        WHERE nome='ACCELIK AS' AND embalagem='Bombona 6';
--       UPDATE public.products SET preco_materia_prima=1.708, preco_office=8.11, preco_pj=8.26
--        WHERE nome='KOLA' AND embalagem='Bombona 5';
--   Prime JD Conjunto — virou 1KG e 5KG na tabela 2026. Renomear em vez de criar:
--       UPDATE public.products SET nome='PRIME JD CONJUNTO 1KG',
--              preco_materia_prima=54.368, preco_office=162.67, preco_pj=162.82
--        WHERE nome='Prime JD Conjunto' AND embalagem='Conjunto 1';
--     (e entao tire a linha do 1KG do BLOCO A antes de rodar)


-- =========================================================================
-- ROLLBACK EXATO (enquanto _bkp_precos_20260824 existir)
-- =========================================================================
--   UPDATE public.products p
--      SET preco_materia_prima = b.preco_materia_prima,
--          preco_office        = b.preco_office,
--          preco_pj            = b.preco_pj
--     FROM public._bkp_precos_20260824 b
--    WHERE p.id = b.id;
--
-- LIMPEZA (so depois de a equipe usar os precos novos por uma semana):
--   DROP TABLE public._bkp_precos_20260824;
-- =========================================================================
