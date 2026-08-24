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
-- UM COMANDO SO, de proposito. Antes eram 229 UPDATE separados e a copia
-- por intervalo de linhas se mostrou fragil. Aqui basta selecionar deste
-- cabecalho ate o ponto-e-virgula final: comentario colado junto e inofensivo,
-- e o editor devolve 'UPDATE 229' — um numero, nao silencio.
--
-- Casa por (nome, embalagem) exatos do BANCO. Onde o nome da embalagem difere
-- da tabela impressa, o nome dela vai no comentario ao lado da linha.
-- Seguro repetir: grava valor fixo, nao incrementa.
-- =========================================================================

UPDATE public.products p
   SET preco_materia_prima = v.mp,
       preco_office        = v.of,
       preco_pj            = v.pj
  FROM (VALUES
    ('ACCELIK AS', 'Bombona 60', 1.486, 7.18, 7.33),   -- tabela: Bombona 50
    ('ACCELIK AS', 'Bombona 25', 1.486, 7.50, 7.66),   -- tabela: Bombona 20
    ('ACCELIK AS', 'CNT 1250', 1.486, 6.89, 7.05),   -- tabela: CNT 1000
    ('ACCELIK AS', 'Tambor 250', 1.486, 6.70, 6.86),   -- tabela: Tambor 200
    ('ACCELIK SF', 'Bombona 60', 2.746, 10.62, 10.77),   -- tabela: Bombona 50
    ('ACCELIK SF', 'Bombona 25', 2.746, 10.94, 11.10),   -- tabela: Bombona 20
    ('ACCELIK SF', 'CNT 1250', 2.746, 10.33, 10.49),   -- tabela: CNT 1000
    ('ACCELIK SF', 'Tambor 250', 2.746, 10.14, 10.29),   -- tabela: Tambor 200
    ('ACCETIVE FC POWDER', 'Saco 20', 3.084, 10.24, 10.40),
    ('ACEPESS FAST', 'Bombona 60', 2.746, 10.62, 10.77),   -- tabela: Bombona 50
    ('ACEPESS FAST', 'Bombona 24', 2.746, 10.94, 11.10),   -- tabela: Bombona 20
    ('ACEPESS FAST', 'CNT 1200', 2.746, 10.33, 10.49),   -- tabela: CNT 1000
    ('ACEPESS FAST', 'Tambor 240', 2.746, 10.14, 10.29),   -- tabela: Tambor 200
    ('ACS 800', 'Bombona 50', 1.250, 6.53, 6.69),
    ('ACS 800', 'Bombona 20', 1.250, 6.86, 7.01),
    ('ACS 800', 'CNT 1000', 1.250, 6.25, 6.40),
    ('ACS 800', 'Tambor 200', 1.250, 6.06, 6.21),
    ('ADIGROUT AR', 'Saco 25', 0.989, 4.52, 4.68),
    ('ADIGROUT AR COMPLETE', 'Saco 25', 0.684, 3.69, 3.85),
    ('ADIGROUT MC', 'Saco 25', 1.780, 6.68, 6.84),
    ('ADIGROUT MIX', 'Saco 10', 8.000, 23.66, 23.81),
    ('ADIGROUT MIX CONCRETE', 'Saco 10', 8.400, 24.75, 24.90),
    ('ADIGROUT TIX', 'Saco 25', 0.942, 4.43, 4.58),
    ('ADIGROUT UFR', 'Saco 25', 1.987, 7.25, 7.40),
    ('ADIGROUT WHITE', 'Saco 25', 2.514, 8.69, 8.84),
    ('AGRECON POWDER', 'Saco 8', 50.000, 138.27, 138.42),
    ('ARGAPOL 592 IC Conjunto', 'Conjunto 35,4', 0.950, 6.46, 6.61),   -- tabela: Conjunto 35
    ('ARGAPOL 992 Conjunto', 'Conjunto 6', 2.750, 11.37, 11.53),
    ('ARGAPOL BC Conjunto', 'Conjunto 35', 1.200, 7.14, 7.30),
    ('ARGAPOL MRI', 'Saco 20', 1.200, 5.10, 5.25),
    ('ARGAPOL RE 642', 'Saco 25', 1.198, 5.13, 5.28),   -- tabela: Saco 20
    ('CEPAS INJECT', 'Saco 20', 2.500, 8.65, 8.80),
    ('CEPAS INJECT BC', 'Saco 20', 3.500, 11.38, 11.53),   -- tabela: Saco 30
    ('CI 900', 'Bombona 50', 1.390, 6.92, 7.07),
    ('CI 900', 'Bombona 20', 1.390, 7.24, 7.39),
    ('CI 900', 'CNT 1000', 1.390, 6.63, 6.79),
    ('CI 900', 'Tambor 200', 1.390, 6.44, 6.59),
    ('CURE CA', 'Bombona 50', 2.412, 9.71, 9.86),
    ('CURE CA', 'Bombona 20', 2.412, 10.03, 10.18),
    ('CURE CA', 'CNT 1000', 2.412, 9.42, 9.58),
    ('CURE CA', 'Tambor 200', 2.412, 9.23, 9.38),
    ('DRAMOR POWDER', 'Saco 20', 4.796, 14.91, 15.07),
    ('EDIMPER M', 'Bombona 50', 3.781, 13.44, 13.59),
    ('EDIMPER M', 'Bombona 20', 3.781, 13.77, 13.92),
    ('EDIMPER M', 'CNT 1000', 3.781, 13.16, 13.31),
    ('EDIMPER M', 'Tambor 200', 3.781, 12.97, 13.12),
    ('EDIMPER PLUS', 'Bombona 60', 4.462, 15.30, 15.45),   -- tabela: Bombona 50
    ('EDIMPER PLUS', 'Bombona 25', 4.462, 15.62, 15.78),   -- tabela: Bombona 20
    ('EDIMPER PLUS', 'CNT 1250', 4.462, 15.01, 15.17),   -- tabela: CNT 1000
    ('EDIMPER PLUS', 'Tambor 250', 4.462, 14.82, 14.98),   -- tabela: Tambor 200
    ('EXPANDER 2019', 'Saco 10', 2.350, 8.37, 8.53),
    ('EXPANFLUID IC', 'Saco 10', 5.022, 15.66, 15.82),
    ('FASTER', 'Bombona 60', 1.134, 6.22, 6.37),   -- tabela: Bombona 50
    ('FASTER', 'Bombona 24', 1.134, 6.54, 6.70),   -- tabela: Bombona 20
    ('FASTER', 'CNT 1200', 1.134, 5.93, 6.09),   -- tabela: CNT 1000
    ('FASTER', 'Tambor 240', 1.134, 5.74, 5.90),   -- tabela: Tambor 200
    ('FLUXYGROUT HMR CONJUNTO', 'Conjunto 22', 22.000, 71.02, 71.18),   -- tabela: Conjunto 20
    ('FLUXYGROUT SOFT CONJUNTO', 'Conjunto 28', 17.000, 57.38, 57.53),   -- tabela: Conjunto 20
    ('HYDROFLEX RR', 'Bombona 50', 30.000, 84.99, 85.14),
    ('HYDROFLEX RR', 'Bombona 20', 30.000, 85.31, 85.47),
    ('HYDROFLEX RR', 'CNT 1000', 30.000, 84.70, 84.86),
    ('HYDROFLEX RR', 'Tambor 200', 30.000, 84.51, 84.67),
    ('HYDROFLEX RS', 'Bombona 50', 4.032, 14.13, 14.28),
    ('HYDROFLEX RS', 'Bombona 20', 4.032, 14.45, 14.61),
    ('HYDROFLEX RS', 'CNT 1000', 4.032, 13.84, 14.00),
    ('HYDROFLEX RS', 'Tambor 200', 4.032, 13.65, 13.80),
    ('HYDROFLEX S', 'Bombona 50', 19.799, 57.15, 57.31),
    ('HYDROFLEX S', 'Bombona 20', 19.799, 57.48, 57.63),
    ('HYDROFLEX S', 'CNT 1000', 19.799, 56.87, 57.02),
    ('HYDROFLEX S', 'Tambor 200', 19.799, 56.68, 56.83),
    ('HYDROFLEX S A', 'Bombona 50', 0.850, 5.44, 5.60),
    ('HYDROFLEX S A', 'Bombona 20', 0.850, 5.77, 5.92),
    ('HYDROFLEX S A', 'CNT 1000', 0.850, 5.16, 5.31),
    ('HYDROFLEX S A', 'Tambor 200', 0.850, 4.97, 5.12),
    ('HYDROFLEX SEL', 'Bombona 50', 6.151, 19.91, 20.06),
    ('HYDROFLEX SEL', 'Bombona 20', 6.151, 20.23, 20.39),
    ('HYDROFLEX V2', 'Bombona 50', 5.707, 18.70, 18.85),
    ('HYDROFLEX V2', 'Bombona 20', 5.707, 19.02, 19.17),
    ('INCORPOR BS PLUS', 'Bombona 50', 1.438, 7.05, 7.20),
    ('INCORPOR BS PLUS', 'Bombona 20', 1.438, 7.37, 7.53),
    ('INCORPOR BS PLUS', 'CNT 1000', 1.438, 6.76, 6.92),
    ('INCORPOR BS PLUS', 'Tambor 200', 1.438, 6.57, 6.73),
    ('INCORPOR BS-D', 'Bombona 50', 0.727, 5.11, 5.26),
    ('INCORPOR BS-D', 'Bombona 20', 0.727, 5.43, 5.59),
    ('INCORPOR BS-D', 'CNT 1000', 0.727, 4.82, 4.98),
    ('INCORPOR BS-D', 'Tambor 200', 0.727, 4.63, 4.79),
    ('KOLA', 'Bombona 50', 1.708, 7.79, 7.94),
    ('KOLA', 'Bombona 20', 1.708, 8.11, 8.26),
    ('KOLA', 'CNT 1000', 1.708, 7.50, 7.65),
    ('KOLA', 'Tambor 200', 1.708, 7.31, 7.46),
    ('KOLA PLUS TIX', 'Bombona 50', 6.965, 22.13, 22.28),
    ('KOLA PLUS TIX', 'Bombona 20', 6.965, 22.46, 22.61),
    ('KOLA PLUS TIX', 'CNT 1000', 6.965, 21.85, 22.00),
    ('KOLA PLUS TIX', 'Tambor 200', 6.965, 21.65, 21.81),
    ('KOLA PVA', 'Bombona 50', 0.630, 4.84, 5.00),
    ('KOLA PVA', 'Bombona 20', 0.630, 5.17, 5.32),
    ('KOLA PVA', 'Tambor 200', 0.630, 4.37, 4.52),
    ('KOLA SBR', 'Bombona 50', 3.513, 12.71, 12.86),
    ('KOLA SBR', 'Bombona 20', 3.513, 13.04, 13.19),
    ('KOLA SBR', 'CNT 1000', 3.513, 12.43, 12.58),
    ('KOLA SBR', 'Tambor 200', 3.513, 12.23, 12.39),
    ('KOLA SUPER', 'Bombona 50', 6.965, 22.13, 22.28),
    ('KOLA SUPER', 'Bombona 20', 6.965, 22.46, 22.61),
    ('KOLA SUPER', 'CNT 1000', 6.965, 21.85, 22.00),
    ('KOLA SUPER', 'Tambor 200', 6.965, 21.65, 21.81),
    ('LIKTIVE ACEP UF', 'Bombona 60', 2.454, 9.82, 9.97),   -- tabela: Bombona 50
    ('LIKTIVE ACEP UF', 'Bombona 25', 2.454, 10.91, 10.30),   -- tabela: Bombona 20
    ('LIKTIVE ACEP UF', 'Tambor 250', 2.454, 9.34, 9.50),   -- tabela: Tambor 200
    ('MINERAL REPAIR 132 Conjunto', 'Conjunto 40', 2.035, 8.00, 8.80),
    ('MINERAL REPAIR 333 Conjunto', 'Conjunto 40', 2.014, 8.40, 9.24),
    ('MINERAL REPAIR 499 Conjunto', 'Conjunto 40', 2.690, 8.00, 8.80),
    ('PLASTICIZER BINDER', 'Bombona 50', 1.701, 7.76, 7.92),
    ('PLASTICIZER BINDER', 'Bombona 20', 1.701, 8.09, 8.24),
    ('PLASTICIZER BINDER', 'CNT 1000', 1.701, 7.48, 7.63),
    ('PLASTICIZER BINDER', 'Tambor 200', 1.701, 7.29, 7.44),
    ('PLASTICIZER CW', 'Bombona 50', 4.334, 14.95, 15.10),
    ('PLASTICIZER CW', 'Bombona 20', 4.334, 15.27, 15.43),
    ('PLASTICIZER CW', 'CNT 1000', 4.334, 14.66, 14.82),
    ('PLASTICIZER CW', 'Tambor 200', 4.334, 14.47, 14.63),
    ('PLASTICIZER HC', 'Bombona 50', 3.386, 12.36, 12.52),
    ('PLASTICIZER HC', 'Bombona 20', 3.386, 12.69, 12.84),
    ('PLASTICIZER HC', 'CNT 1000', 3.386, 12.08, 12.23),
    ('PLASTICIZER HC', 'Tambor 200', 3.386, 12.23, 12.38),
    ('PLASTICIZER PREMIUM', 'Bombona 50', 1.843, 8.15, 8.31),
    ('PLASTICIZER PREMIUM', 'Bombona 20', 1.843, 8.48, 8.63),
    ('PLASTICIZER PREMIUM', 'CNT 1000', 1.843, 7.87, 8.02),
    ('PLASTICIZER PREMIUM', 'Tambor 200', 1.843, 7.68, 7.83),
    ('PLASTICIZER SAD', 'Bombona 50', 1.810, 8.06, 8.22),
    ('PLASTICIZER SAD', 'Bombona 20', 1.810, 8.39, 8.54),
    ('PLASTICIZER SAD', 'CNT 1000', 1.810, 7.78, 7.93),
    ('PLASTICIZER SAD', 'Tambor 200', 1.810, 7.59, 7.74),
    ('PLASTICIZER SAD 20', 'Bombona 50', 1.270, 6.59, 6.74),
    ('PLASTICIZER SAD 20', 'Bombona 20', 1.270, 6.91, 7.07),
    ('PLASTICIZER SAD 20', 'CNT 1000', 1.270, 6.30, 6.46),
    ('PLASTICIZER SAD 20', 'Tambor 200', 1.270, 6.11, 6.27),
    ('POLYPLAST 146', 'Bombona 60', 3.543, 12.79, 12.94),   -- tabela: Bombona 50
    ('POLYPLAST 146', 'Bombona 24', 3.543, 13.12, 13.27),   -- tabela: Bombona 20
    ('POLYPLAST 146', 'CNT 1200', 3.543, 12.51, 12.66),   -- tabela: CNT 1000
    ('POLYPLAST 146', 'Tambor 240', 3.543, 12.32, 12.47),   -- tabela: Tambor 200
    ('POLYPLAST 151', 'Bombona 60', 3.576, 12.88, 13.03),   -- tabela: Bombona 50
    ('POLYPLAST 151', 'Bombona 24', 3.576, 13.21, 13.36),   -- tabela: Bombona 20
    ('POLYPLAST 151', 'CNT 1200', 3.576, 12.60, 12.75),   -- tabela: CNT 1000
    ('POLYPLAST 151', 'Tambor 240', 3.576, 12.41, 12.56),   -- tabela: Tambor 200
    ('POLYPLAST 167', 'Bombona 60', 2.745, 10.61, 10.77),   -- tabela: Bombona 50
    ('POLYPLAST 167', 'Bombona 24', 2.745, 10.94, 11.09),   -- tabela: Bombona 20
    ('POLYPLAST 167', 'CNT 1200', 2.745, 10.33, 10.48),   -- tabela: CNT 1000
    ('POLYPLAST 167', 'Tambor 240', 2.745, 10.14, 10.29),   -- tabela: Tambor 200
    ('POLYPLAST 170 D', 'Bombona 60', 2.400, 9.67, 9.82),   -- tabela: Bombona 50
    ('POLYPLAST 170 D', 'Bombona 24', 2.400, 10.00, 10.15),   -- tabela: Bombona 20
    ('POLYPLAST 170 D', 'CNT 1200', 2.400, 9.39, 9.54),   -- tabela: CNT 1000
    ('POLYPLAST 170 D', 'Tambor 240', 2.400, 9.20, 9.35),   -- tabela: Tambor 200
    ('POLYPLAST 170 PLUS', 'Bombona 60', 2.550, 10.08, 10.24),   -- tabela: Bombona 50
    ('POLYPLAST 170 PLUS', 'Bombona 24', 2.550, 10.41, 10.56),   -- tabela: Bombona 20
    ('POLYPLAST 170 PLUS', 'CNT 1200', 2.550, 9.80, 9.95),   -- tabela: CNT 1000
    ('POLYPLAST 170 PLUS', 'Tambor 240', 2.550, 9.61, 9.76),   -- tabela: Tambor 200
    ('POLYPLAST 4300', 'Bombona 60', 3.589, 12.92, 13.07),   -- tabela: Bombona 50
    ('POLYPLAST 4300', 'Bombona 24', 3.589, 13.24, 13.40),   -- tabela: Bombona 20
    ('POLYPLAST 4300', 'CNT 1200', 3.589, 12.63, 12.79),   -- tabela: CNT 1000
    ('POLYPLAST 4300', 'Tambor 240', 3.589, 12.44, 12.59),   -- tabela: Tambor 200
    ('POLYSEL CONJUNTO', 'Conjunto 5', 85.000, 241.64, 241.79),
    ('RELEASE WAX', 'Balde 18', 7.812, 25.44, 25.59),   -- tabela: Balde 14
    ('RELENT', 'Bombona 50', 6.400, 20.59, 20.74),
    ('RELENT', 'Bombona 20', 6.400, 20.91, 21.07),
    ('RELENT', 'CNT 1000', 6.400, 20.30, 20.46),
    ('RELENT', 'Tambor 200', 6.400, 20.11, 20.27),
    ('RELENT AD', 'Bombona 50', 23.060, 66.05, 66.20),
    ('RELENT AD', 'Bombona 20', 14.870, 44.03, 44.18),
    ('RELENT AD', 'CNT 1000', 23.060, 65.77, 65.92),
    ('RELENT AD', 'Tambor 200', 14.870, 43.23, 43.38),
    ('RELENT BASE', 'Tambor 200', 17.000, 48.84, 48.99),
    ('RELENT BIO-VO', 'Bombona 50', 7.535, 23.69, 23.84),
    ('RELENT BIO-VO', 'Bombona 20', 7.535, 24.01, 24.16),
    ('RELENT BIO-VO', 'CNT 1000', 7.535, 23.40, 23.56),
    ('RELENT BIO-VO', 'Tambor 200', 7.535, 23.21, 23.36),
    ('RELENT CONCENTRATE', 'Bombona 50', 18.000, 52.24, 52.40),
    ('RELENT CONCENTRATE', 'Bombona 20', 18.000, 52.57, 52.72),
    ('RELENT CONCENTRATE', 'CNT 1000', 18.000, 51.96, 52.11),
    ('RELENT CONCENTRATE', 'Tambor 200', 18.000, 51.77, 51.92),
    ('RELENT RTU', 'Bombona 50', 1.011, 5.88, 6.04),
    ('RELENT RTU', 'Bombona 20', 1.011, 6.21, 6.36),
    ('RELENT RTU', 'CNT 1000', 1.011, 5.60, 5.75),
    ('RELENT RTU', 'Tambor 200', 1.011, 5.41, 5.56),
    ('RELENT S', 'Bombona 50', 2.202, 9.13, 9.28),
    ('RELENT S', 'Bombona 20', 2.202, 9.46, 9.61),
    ('RELENT S', 'Tambor 200', 2.202, 8.46, 8.61),
    ('RELENT SMO', 'Bombona 50', 6.378, 20.53, 20.68),
    ('RELENT SMO', 'Bombona 20', 6.378, 20.85, 21.01),
    ('RELENT SMO', 'Tambor 200', 6.378, 20.05, 20.21),
    ('RELENT SUPER', 'Bombona 50', 10.842, 32.71, 32.86),
    ('RELENT SUPER', 'Bombona 20', 10.842, 33.03, 33.19),
    ('RELENT SUPER', 'Tambor 200', 10.842, 32.23, 32.39),
    ('RELENT W', 'Bombona 50', 6.401, 20.59, 20.75),
    ('RELENT W', 'Bombona 20', 6.401, 20.92, 21.07),
    ('RELENT W', 'Tambor 200', 6.401, 20.12, 20.27),
    ('RETARPEG S', 'Bombona 60', 4.741, 16.06, 16.21),   -- tabela: Bombona 50
    ('RETARPEG S', 'Bombona 24', 4.741, 16.38, 16.54),   -- tabela: Bombona 20
    ('RETARPEG S', 'Tambor 240', 4.741, 15.58, 15.74),   -- tabela: Tambor 200
    ('RETARTIVE WR 2010', 'Bombona 60', 2.744, 10.61, 10.76),   -- tabela: Bombona 50
    ('RETARTIVE WR 2010', 'Bombona 24', 2.744, 10.93, 11.09),   -- tabela: Bombona 20
    ('RETARTIVE WR 2010', 'CNT 1200', 2.744, 10.33, 10.48),   -- tabela: CNT 1000
    ('RETARTIVE WR 2010', 'Tambor 240', 2.744, 10.13, 10.29),   -- tabela: Tambor 200
    ('RETARTIVE WR 2048', 'Bombona 55', 2.873, 10.96, 11.12),   -- tabela: Bombona 50
    ('RETARTIVE WR 2048', 'Bombona 22', 2.873, 11.29, 11.44),   -- tabela: Bombona 20
    ('RETARTIVE WR 2048', 'CNT 1100', 2.873, 10.68, 10.83),   -- tabela: CNT 1000
    ('RETARTIVE WR 2048', 'Tambor 220', 2.873, 10.49, 10.64),   -- tabela: Tambor 200
    ('RUST CONVERTER', 'Bombona 60', 8.655, 26.74, 26.89),   -- tabela: Bombona 50
    ('RUST CONVERTER', 'Bombona 25', 8.655, 27.07, 27.22),   -- tabela: Bombona 20
    ('STRUCTURAL AD CONJUNTO', 'Conjunto 1', 17.070, 56.16, 56.31),
    ('STRUCTURAL TF CONJUNTO', 'Conjunto 1', 43.492, 128.26, 128.42),
    ('SUFLEX GREY RA', 'Balde 18', 7.018, 22.54, 22.70),   -- tabela: Balde 20
    ('SUFLEXIBLE RA', 'Balde 18', 7.018, 22.54, 22.70),   -- tabela: Balde 20
    ('SUPERFLUID AC', 'Bombona 60', 3.802, 13.50, 13.65),   -- tabela: Bombona 50
    ('SUPERFLUID AC', 'Bombona 24', 3.802, 13.82, 13.98),   -- tabela: Bombona 20
    ('SUPERFLUID AC', 'CNT 1200', 3.802, 13.21, 13.37),   -- tabela: CNT 1000
    ('SUPERFLUID AC', 'Tambor 240', 3.802, 13.02, 13.18),   -- tabela: Tambor 200
    ('SUPROFLEX CONJUNTO', 'Conjunto 20', 1.071, 7.36, 7.51),   -- tabela: Conjunto 18
    ('WHITE MINERAL REPAIR CONJUNTO', 'Conjunto 40', 5.500, 18.59, 18.74),
    ('WP ARCON', 'Bombona 50', 0.493, 4.47, 4.62),
    ('WP ARCON', 'Bombona 20', 0.493, 4.79, 4.95),
    ('WP ARCON', 'Tambor 200', 0.493, 3.99, 4.15),
    ('WP ARPOMON', 'Saco 20', 1.320, 5.43, 5.58),
    ('WP CRYSTAL', 'Saco 20', 3.053, 10.16, 10.31),   -- tabela: Saco 25
    ('WP FLEXIBLE', 'Bombona 42', 6.457, 20.74, 20.90),   -- tabela: Bombona 50
    ('WP FLEXIBLE', 'Bombona 18', 6.457, 21.07, 21.22),   -- tabela: Bombona 20
    ('WP FLEXIBLE', 'Tambor 180', 6.457, 20.27, 20.42),   -- tabela: Tambor 200
    ('WP HYDRACEM UF', 'Saco 20', 4.298, 13.55, 13.71),   -- tabela: Saco 25
    ('WP TILE PRO', 'Bombona 50', 2.026, 8.65, 8.81),
    ('WP TILE PRO', 'Bombona 20', 2.026, 8.98, 9.13),
    ('WP TILE PRO', 'Tambor 200', 2.026, 8.18, 8.33)
  ) AS v(nome, embalagem, mp, of, pj)
 WHERE p.nome = v.nome AND p.embalagem = v.embalagem;

-- ESPERADO na tela: UPDATE 229


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
