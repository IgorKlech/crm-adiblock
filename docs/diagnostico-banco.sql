-- =========================================================================
-- DIAGNOSTICO DO BANCO — CRM Adiblock
-- =========================================================================
-- SO LEITURA. Nao ha INSERT, UPDATE, DELETE, ALTER nem DROP em lugar nenhum
-- deste arquivo — pode rodar em producao sem medo, a qualquer hora.
--
-- COMO USAR: abra o SQL Editor do Supabase e rode um BLOCO por vez (cada um
-- devolve uma tabela). Cole a saida de volta pro Claude interpretar.
--
-- Por que isto existe: a varredura de 17/08/2026 cobriu o codigo do CRM e
-- parou na borda do Supabase. Indices, integridade e o isolamento por
-- organizacao nunca foram verificados no banco vivo — so no SQL declarado.
-- Declarar indice em migration nao garante que ele existe: garante que
-- alguem escreveu.
-- =========================================================================


-- =========================================================================
-- BLOCO 1 — Tamanho de cada tabela
-- =========================================================================
-- Serve pra duas coisas: dimensionar o sistema, e CONFERIR O BACKUP. Os
-- numeros daqui tem que bater com o `_meta.totais` do JSON que o botao
-- "Baixar Backup" gera. Se o backup vier menor, ele esta truncado.
select
  relname                                as tabela,
  n_live_tup                             as linhas,
  pg_size_pretty(pg_total_relation_size(relid)) as tamanho
from pg_stat_user_tables
where schemaname = 'public'
order by n_live_tup desc;


-- =========================================================================
-- BLOCO 2 — Indices: existem, e alguem usa?
-- =========================================================================
-- `usos` = quantas vezes o Postgres escolheu aquele indice desde o ultimo
-- restart das estatisticas. Indice com 0 uso e peso morto: ocupa disco e
-- deixa todo INSERT/UPDATE mais lento sem devolver nada. Mas cuidado ao ler:
-- 0 tambem aparece em indice recem-criado ou em tabela pequena demais pro
-- planner se dar ao trabalho.
select
  relname       as tabela,
  indexrelname  as indice,
  idx_scan      as usos,
  pg_size_pretty(pg_relation_size(indexrelid)) as tamanho
from pg_stat_user_indexes
where schemaname = 'public'
order by idx_scan asc, relname;


-- =========================================================================
-- BLOCO 3 — Integridade e dados que sujam relatorio
-- =========================================================================
-- Cada linha e uma pergunta. `qtd` = 0 significa "esta limpo".
select 'opps ganhas SEM closed_at' as checagem, count(*) as qtd,
       'usam created_at como aproximacao — deixam o Radar de Reativacao impreciso' as impacto
  from public.opportunities where estagio = 'ganha' and closed_at is null
union all
select 'opps perdidas SEM motivo', count(*),
       'o motivo da perda e obrigatorio no front desde o Sprint 7.2; estas sao anteriores'
  from public.opportunities where estagio = 'perdida'
   and (perda_motivo is null or btrim(perda_motivo) = '')
union all
select 'opps abertas SEM proximo passo', count(*),
       'sao as "orfas" — badge de alerta no Pipeline'
  from public.opportunities
 where estagio not in ('ganha','perdida') and callback_date is null
union all
select 'contatos apontando pra empresa que nao existe', count(*),
       'lixo referencial'
  from public.contacts c
 where c.company_id is not null
   and not exists (select 1 from public.companies e where e.id = c.company_id)
union all
select 'interacoes apontando pra oportunidade que nao existe', count(*),
       'lixo referencial — some do historico do perfil'
  from public.interactions i
 where i.opportunity_id is not null
   and not exists (select 1 from public.opportunities o where o.id = i.opportunity_id)
union all
select 'propostas sem empresa', count(*),
       'aparecem na aba Propostas sem nome de cliente'
  from public.proposals p
 where p.company_id is null
    or not exists (select 1 from public.companies e where e.id = p.company_id)
union all
select 'empresas duplicadas por CNPJ', count(*),
       'mesmo CNPJ cadastrado mais de uma vez'
  from (select cnpj from public.companies
         where cnpj is not null and btrim(cnpj) <> ''
         group by cnpj having count(*) > 1) d
union all
select 'pedidos com revisao > 1', count(*),
       'so pra saber se a feature de revisao esta sendo usada'
  from public.proposals where coalesce(revisao,1) > 1
union all
select 'pedidos SEM numero de OC do cliente', count(*),
       'status pedido/expedido sem oc_numero — a cobranca do cliente nao acha'
  from public.proposals
 where status in ('pedido','expedido') and (oc_numero is null or btrim(oc_numero) = '');


-- =========================================================================
-- BLOCO 4 — Multi-tenant: o org_id esta preenchido em tudo?
-- =========================================================================
-- A etapa 91e pos NOT NULL nessas colunas. Se algum numero vier > 0, alguma
-- linha escapou — e com RLS por org, linha sem org_id fica INVISIVEL pra
-- todo mundo, inclusive pro dono.
select 'companies' as tabela, count(*) filter (where org_id is null) as sem_org, count(*) as total from public.companies
union all select 'contacts',             count(*) filter (where org_id is null), count(*) from public.contacts
union all select 'opportunities',        count(*) filter (where org_id is null), count(*) from public.opportunities
union all select 'opportunity_products', count(*) filter (where org_id is null), count(*) from public.opportunity_products
union all select 'interactions',         count(*) filter (where org_id is null), count(*) from public.interactions
union all select 'proposals',            count(*) filter (where org_id is null), count(*) from public.proposals
union all select 'proposal_revisions',   count(*) filter (where org_id is null), count(*) from public.proposal_revisions
union all select 'tasks',                count(*) filter (where org_id is null), count(*) from public.tasks
union all select 'products',             count(*) filter (where org_id is null), count(*) from public.products
union all select 'profiles',             count(*) filter (where org_id is null), count(*) from public.profiles;


-- =========================================================================
-- BLOCO 5 — RLS: esta ligado, e com quais politicas?
-- =========================================================================
-- `rls_ligado = false` numa tabela de dados e furo de isolamento: qualquer
-- usuario autenticado le tudo, de todas as organizacoes.
select
  t.relname                                   as tabela,
  t.relrowsecurity                            as rls_ligado,
  count(p.policyname)                         as politicas,
  string_agg(p.policyname || ' [' || p.cmd || ']', ', ' order by p.policyname) as quais
from pg_class t
join pg_namespace n on n.oid = t.relnamespace
left join pg_policies p on p.schemaname = 'public' and p.tablename = t.relname
where n.nspname = 'public' and t.relkind = 'r'
group by t.relname, t.relrowsecurity
order by t.relrowsecurity asc, t.relname;


-- =========================================================================
-- BLOCO 6 — Numeracao de propostas e pedidos
-- =========================================================================
-- A numeracao e sequencial por (org, ano). Buraco na sequencia costuma ser
-- proposta excluida — normal. Duplicata seria grave: dois documentos com o
-- mesmo numero circulando.
select ano,
       count(*)                    as propostas,
       min(numero)                 as menor,
       max(numero)                 as maior,
       max(numero) - count(*)      as buracos_na_sequencia,
       count(*) - count(distinct numero) as numeros_repetidos
  from public.proposals
 group by ano
 order by ano desc;
