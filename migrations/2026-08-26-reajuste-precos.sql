-- =========================================================================
-- 2026-08-26 — Reajuste de precos do catalogo
-- =========================================================================
-- ⚠ RODE UM BLOCO DE CADA VEZ. Nao cole o arquivo inteiro.
--   Em 24/08 um arquivo de 392 linhas colado inteiro devolveu "Success. No
--   rows returned" e nao fez nada. Cada bloco daqui devolve um NUMERO na tela;
--   "Success" sem numero nao prova coisa nenhuma.
--
-- ORIGEM: docs/catalogo-para-preencher.csv, coluna "* NOVO" preenchida a mao.
--
-- O QUE FAZ
--   BLOCO 2 atualiza preco_materia_prima, preco_office e preco_pj de 88 linhas
--   de public.products. As outras 145 linhas do CSV vieram com NOVO igual ao
--   ATUAL — nao entram no UPDATE, para a contagem na tela significar alguma
--   coisa.
--
-- O QUE **NAO** FAZ, DE PROPOSITO
--   Nao toca em `nome` nem em `embalagem`. O numero da embalagem e de onde
--   `pesoDaEmbalagem()` tira quantos volumes o Pedido de Producao pede.
--   Nao cadastra produto novo: as 19 linhas "A CADASTRAR" foram retiradas do
--   CSV nesta revisao, e nenhuma delas existe no banco.
--
-- ⚠ products NAO TEM TRIGGER DE AUDITORIA. log_audit_changes() nao roda nesta
--   tabela — um UPDATE de preco nao deixa rastro. Por isso o BLOCO 1 vem antes.
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

CREATE TABLE IF NOT EXISTS public._bkp_precos_20260826 AS
SELECT id, nome, embalagem, preco_materia_prima, preco_office, preco_pj, now() AS salvo_em
  FROM public.products;

SELECT count(*) AS linhas_guardadas FROM public._bkp_precos_20260826;
-- ESPERADO: 233


-- =========================================================================
-- BLOCO 2 de 3 — os 88 precos.  SO DEPOIS de o bloco 1 ter devolvido 233.
-- =========================================================================
-- UM COMANDO SO, de proposito: nao tem intervalo de linhas pra errar na copia
-- e o editor devolve 'UPDATE 88' — um numero, nao silencio.
-- Casa por (nome, embalagem) exatos do BANCO, que e de onde o CSV foi gerado.
-- Seguro repetir: grava valor fixo, nao incrementa.
-- =========================================================================

UPDATE public.products p
   SET preco_materia_prima = v.mp,
       preco_office        = v.of,
       preco_pj            = v.pj
  FROM (VALUES
    ('ACCELIK AS',                  'Bombona 25',       1.495,     7.53,     7.68),
    ('ACCELIK AS',                  'Bombona 6',        1.495,     8.20,     8.50),
    ('ACCELIK AS',                  'Bombona 60',       1.495,     7.20,     7.36),
    ('ACCELIK AS',                  'CNT 1250',         1.495,     6.92,     7.07),
    ('ACCELIK AS',                  'Tambor 250',       1.495,     6.73,     6.88),
    ('ACCETIVE FC POWDER',          'Saco 20',          3.240,    11.23,    11.86),
    ('ADIGROUT AR',                 'Saco 25',          0.972,     4.48,     4.63),
    ('ADIGROUT AR COMPLETE',        'Saco 25',          0.673,     3.66,     3.82),
    ('ADIGROUT AR PLUS',            'Saco 25',          1.350,     5.20,     5.65),
    ('ADIGROUT MC',                 'Saco 25',          1.778,     6.68,     6.83),
    ('ADIGROUT TIX',                'Saco 25',          0.923,     4.38,     4.53),
    ('ADIGROUT UFR',                'Saco 25',          1.977,     7.22,     7.37),
    ('ADIGROUT WHITE',              'Saco 25',          2.511,     8.68,     8.83),
    ('ARGAPOL RE 642',              'Saco 25',          1.191,     5.11,     5.26),
    ('CURE CA',                     'Bombona 20',       2.678,    10.75,    10.91),
    ('CURE CA',                     'Bombona 50',       2.678,    10.43,    10.58),
    ('CURE CA',                     'CNT 1000',         2.678,    10.15,    10.30),
    ('CURE CA',                     'Tambor 200',       2.678,     9.95,    10.11),
    ('HYDROFLEX SEL',               'Bombona 20',       6.151,    20.23,    20.31),
    ('KOLA',                        'Bombona 20',       1.744,     8.21,     8.36),
    ('KOLA',                        'Bombona 5',        1.744,     8.10,     8.25),
    ('KOLA',                        'Bombona 50',       1.744,     7.88,     8.04),
    ('KOLA',                        'CNT 1000',         1.744,     7.60,     7.75),
    ('KOLA',                        'Tambor 200',       1.744,     7.41,     7.56),
    ('KOLA PLUS TIX',               'Bombona 20',       7.115,    22.86,    23.02),
    ('KOLA PLUS TIX',               'Bombona 50',       7.115,    22.54,    22.69),
    ('KOLA PLUS TIX',               'CNT 1000',         7.115,    22.25,    22.41),
    ('KOLA PLUS TIX',               'Tambor 200',       7.115,    22.06,    22.22),
    ('KOLA SBR',                    'Bombona 20',       3.580,    13.24,    13.39),
    ('KOLA SBR',                    'Bombona 50',       3.580,    12.92,    13.07),
    ('KOLA SBR',                    'CNT 1000',         3.580,    12.63,    12.78),
    ('KOLA SBR',                    'Tambor 200',       3.580,    12.44,    12.59),
    ('KOLA SUPER',                  'Bombona 20',       7.115,    22.86,    23.02),
    ('KOLA SUPER',                  'Bombona 50',       7.115,    22.54,    22.69),
    ('KOLA SUPER',                  'CNT 1000',         7.115,    22.25,    22.41),
    ('KOLA SUPER',                  'Tambor 200',       7.115,    22.06,    22.22),
    ('LIKTIVE ACEP UF',             'Bombona 25',       2.454,    10.30,    10.91),
    ('MINERAL REPAIR 132 Conjunto', 'Conjunto 40',      2.346,     8.00,     8.80),
    ('MINERAL REPAIR 333 Conjunto', 'Conjunto 40',      2.032,     8.40,     9.24),
    ('MINERAL REPAIR 499 Conjunto', 'Conjunto 40',      2.708,     8.00,     8.80),
    ('PLASTICIZER BINDER',          'Bombona 20',       1.722,     8.15,     8.30),
    ('PLASTICIZER BINDER',          'Bombona 50',       1.722,     7.82,     7.98),
    ('PLASTICIZER BINDER',          'CNT 1000',         1.722,     7.54,     7.69),
    ('PLASTICIZER CW',              'Bombona 20',       4.382,    15.41,    15.56),
    ('PLASTICIZER CW',              'Bombona 50',       4.382,    15.08,    15.23),
    ('PLASTICIZER CW',              'CNT 1000',         4.382,    14.80,    14.95),
    ('PLASTICIZER CW',              'Tambor 200',       4.382,    14.61,    14.76),
    ('PLASTICIZER HC',              'Bombona 20',       3.427,    12.80,    12.96),
    ('PLASTICIZER HC',              'Bombona 50',       3.427,    12.48,    12.63),
    ('PLASTICIZER HC',              'CNT 1000',         3.427,    12.19,    12.35),
    ('PLASTICIZER HC',              'Tambor 200',       3.427,    12.34,    12.50),
    ('PLASTICIZER PREMIUM',         'Bombona 20',       2.040,     9.01,     9.17),
    ('PLASTICIZER PREMIUM',         'Bombona 50',       2.040,     8.69,     8.84),
    ('PLASTICIZER PREMIUM',         'CNT 1000',         2.040,     8.40,     8.56),
    ('PLASTICIZER PREMIUM',         'Tambor 200',       2.040,     8.21,     8.37),
    ('POLYPLAST 167',               'Bombona 24',       2.803,    11.10,    11.25),
    ('POLYPLAST 167',               'Bombona 60',       2.803,    10.77,    10.93),
    ('POLYPLAST 167',               'CNT 1200',         2.803,    10.49,    10.64),
    ('POLYPLAST 167',               'Tambor 240',       2.803,    10.30,    10.45),
    ('Prime JD Conjunto',           'Conjunto 1',      54.368,   172.26,   172.41),
    ('RELENT',                      'Bombona 20',       6.423,    20.97,    21.13),
    ('RELENT',                      'Bombona 50',       6.423,    20.65,    20.80),
    ('RELENT',                      'CNT 1000',         6.423,    20.36,    20.52),
    ('RELENT',                      'Tambor 200',       6.423,    20.17,    20.33),
    ('RELENT AD',                   'Bombona 20',      23.060,    67.25,    67.65),
    ('RELENT AD',                   'Tambor 200',      23.060,    65.05,    65.25),
    ('RELENT BIO-VO',               'Bombona 20',       7.588,    24.16,    24.31),
    ('RELENT BIO-VO',               'Bombona 50',       7.588,    23.83,    23.98),
    ('RELENT BIO-VO',               'CNT 1000',         7.588,    23.55,    23.70),
    ('RELENT BIO-VO',               'Tambor 200',       7.588,    23.35,    23.51),
    ('RELENT SUPER',                'Bombona 20',      11.605,    35.12,    35.27),
    ('RELENT SUPER',                'Bombona 50',      11.605,    34.79,    34.95),
    ('RELENT SUPER',                'Tambor 200',      11.605,    34.32,    34.47),
    ('SUFLEX GREY RA',              'Balde 18',         8.094,    25.48,    25.63),
    ('SUFLEXIBLE RA',               'Balde 18',         8.094,    25.48,    25.63),
    ('SUPROFLEX CONJUNTO',          'Conjunto 20',      1.056,     7.32,     7.47),
    ('WP ARCON',                    'Bombona 20',       0.528,     4.89,     5.04),
    ('WP ARCON',                    'Bombona 50',       0.528,     4.56,     4.72),
    ('WP ARCON',                    'Tambor 200',       0.528,     4.09,     4.24),
    ('WP ARPOMON',                  'Saco 20',          1.300,     5.37,     5.53),
    ('WP CRYSTAL',                  'Saco 20',          3.034,    10.10,    10.26),
    ('WP FLEXIBLE',                 'Bombona 18',       6.511,    21.22,    21.37),
    ('WP FLEXIBLE',                 'Bombona 42',       6.511,    20.74,    20.90),
    ('WP FLEXIBLE',                 'Tambor 180',       6.511,    20.41,    20.57),
    ('WP HYDRACEM UF',              'Saco 20',          4.283,    13.51,    13.67),
    ('WP TILE PRO',                 'Bombona 20',       2.043,     9.02,     9.18),
    ('WP TILE PRO',                 'Bombona 50',       2.043,     8.70,     8.85),
    ('WP TILE PRO',                 'Tambor 200',       2.043,     8.22,     8.38)
  ) AS v(nome, embalagem, mp, of, pj)
 WHERE p.nome = v.nome AND p.embalagem = v.embalagem;

-- ESPERADO na tela: UPDATE 88
-- Se vier menos que 88, alguma linha do CSV nao casou com (nome, embalagem)
-- do banco — o BLOCO 3 mostra quais.


-- =========================================================================
-- BLOCO 3 de 3 — conferencia.  RODE SOZINHO, depois do bloco 2.
-- =========================================================================
SELECT (SELECT count(*) FROM public._bkp_precos_20260826)                    AS linhas_guardadas,
       (SELECT count(*) FROM public.products p
          JOIN public._bkp_precos_20260826 b ON b.id = p.id
         WHERE p.preco_office        IS DISTINCT FROM b.preco_office
            OR p.preco_pj            IS DISTINCT FROM b.preco_pj
            OR p.preco_materia_prima IS DISTINCT FROM b.preco_materia_prima) AS linhas_alteradas,
       (SELECT count(*) FROM public.products)                                AS total_no_catalogo,
       (SELECT count(*) FROM public.products WHERE preco_pj < preco_office)  AS margem_invertida;

-- ESPERADO: 233 · 88 · 233 · 0
--   margem_invertida tem que ser 0: o LIKTIVE ACEP UF, unico invertido desde
--   agosto, foi desinvertido nesta rodada (OFFICE 10,30 / PJ 10,91).
--   Se vier 1 ou mais, rode a sondagem abaixo pra ver quem e.

-- SONDAGEM (so-leitura, roda quando quiser):
--   SELECT nome, embalagem, preco_office, preco_pj
--     FROM public.products WHERE preco_pj < preco_office ORDER BY nome;


-- =========================================================================
-- BLOCO A (opcional) — as 5 linhas que parecem erro de digitacao no CSV
-- =========================================================================
-- Ficaram FORA do bloco 2. Cada uma quebra um padrao que as ~230 outras linhas
-- respeitam, entao aplicar o CSV literal aqui seria gravar o erro no banco.
-- Confira os cinco antes de descomentar.
--
--  1. INCORPOR BS PLUS / Tambor 200 — CSV traz PJ = 673, com OFFICE 6,57.
--     Falta a virgula. Nao ha duvida real: nenhum produto do catalogo passa de
--     R$ 140/kg, e o proprio OFFICE da linha continua 6,57.
--       CSV: 6,57 / 673        ->  correcao: 6,57 / 6,73  (= preco atual)
--
--  2. EDIMPER M / Bombona 50 — PJ 16,59 contra OFFICE 13,44. O gap PJ-OFFICE
--     e 0,15 em praticamente todo o catalogo; aqui daria 3,15. O 3 virou 6.
--       CSV: 13,44 / 16,59     ->  correcao: 13,44 / 13,59 (= preco atual)
--
--  3. HYDROFLEX SEL / Bombona 50 — PJ 19,17 ABAIXO do OFFICE 19,91. Margem
--     invertida, o mesmo defeito que o LIKTIVE ACEP UF teve o ano passado.
--       CSV: 19,91 / 19,17     ->  correcao: 19,91 / 20,06 (= preco atual)
--
--  4. ACS 800 / CNT 1000 — CSV sobe o OFFICE pra 6,52 e deixa o PJ em 6,40,
--     invertendo a margem. As outras tres embalagens do ACS 800 vieram sem
--     nenhuma alteracao, entao o mais provavel e que o OFFICE nao devia mudar.
--       CSV: 6,52 / 6,40       ->  correcao: 6,25 / 6,40  (= preco atual)
--
--  5. PLASTICIZER BINDER / Tambor 200 — CSV repete 7,82 / 7,98, que sao os
--     valores da Bombona 50 logo acima; deixa o Tambor mais caro que o CNT,
--     coisa que nao acontece em nenhum outro produto. A materia-prima subiu
--     pra 1,722 nas quatro embalagens e o OFFICE subiu +0,06 nas outras tres
--     (8,09->8,15 · 7,76->7,82 · 7,48->7,54), entao o Tambor acompanha:
--       CSV: 7,82 / 7,98       ->  correcao: 7,35 / 7,50  (+0,06, como as tres)
--
--     Esta e a UNICA das cinco que muda preco de verdade — nas outras quatro
--     a correcao coincide com o que ja esta no banco, entao deixar de rodar
--     este bloco nao deixa nenhuma delas errada.
-- =========================================================================
/*
UPDATE public.products p
   SET preco_materia_prima = v.mp,
       preco_office        = v.of,
       preco_pj            = v.pj
  FROM (VALUES
    ('INCORPOR BS PLUS',   'Tambor 200',    1.438,  6.57,  6.73),
    ('EDIMPER M',          'Bombona 50',    3.781, 13.44, 13.59),
    ('HYDROFLEX SEL',      'Bombona 50',    6.151, 19.91, 20.06),
    ('ACS 800',            'CNT 1000',      1.250,  6.25,  6.40),
    ('PLASTICIZER BINDER', 'Tambor 200',    1.722,  7.35,  7.50)
  ) AS v(nome, embalagem, mp, of, pj)
 WHERE p.nome = v.nome AND p.embalagem = v.embalagem;
-- ESPERADO na tela: UPDATE 5
*/
-- ⚠ Corrigir aqui e nao corrigir no CSV faz o erro voltar no proximo reajuste.


-- =========================================================================
-- ROLLBACK EXATO (enquanto _bkp_precos_20260826 existir)
-- =========================================================================
--   UPDATE public.products p
--      SET preco_materia_prima = b.preco_materia_prima,
--          preco_office        = b.preco_office,
--          preco_pj            = b.preco_pj
--     FROM public._bkp_precos_20260826 b
--    WHERE p.id = b.id;
--
-- LIMPEZA (so depois de a equipe usar os precos novos por uma semana):
--   DROP TABLE public._bkp_precos_20260826;
-- =========================================================================
