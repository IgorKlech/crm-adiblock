# Guia de Restauração — CRM Adiblock

Como restaurar os dados a partir dos JSONs de backup (do backup automático
diário em `backups/AAAA-MM-DD/` ou do arquivo manual baixado pelo Dashboard).

> ⚠ **Antes de tudo, leia a Regra de Ouro do `CLAUDE.md`.** Restaurar é uma
> operação delicada. Faça com calma, fora de horário de uso, e tenha certeza
> de qual backup vai usar.

---

## Quando usar

- Perda/corrupção de dados (como o incidente de 01/06/2026).
- Migração para um novo projeto Supabase.
- Recuperar uma tabela específica que foi apagada.

Se o problema for só **algumas linhas** (ex: propostas apagadas), prefira
recuperar do `audit_log` (veja a seção final) antes de uma restauração completa.

---

## Pré-requisitos

- A `service_role key` do Supabase (Settings > API). **Nunca** commitar.
- As tabelas precisam **existir** no banco (schema criado). Se for um banco
  novo, rode antes o `supabase_setup.sql` **em blocos** (nunca inteiro de uma vez
  — ver Regra de Ouro), ou as migrations em `/migrations`.
- `curl` e `jq` instalados (ou use o próprio SQL Editor do Supabase).

Defina as variáveis (no terminal):

```bash
export SB_URL="https://SEU_PROJ.supabase.co"
export SB_KEY="SUA_SERVICE_ROLE_KEY"
```

---

## Ordem de restauração (respeita as FKs)

As tabelas têm dependências (chaves estrangeiras). **Restaure nesta ordem**
para nenhum INSERT falhar por referência inexistente:

| # | Tabela | Depende de |
|---|---|---|
| 1 | `profiles` | (nenhuma — espelha auth.users) |
| 2 | `products` | (nenhuma) |
| 3 | `companies` | profiles (created_by) |
| 4 | `contacts` | companies |
| 5 | `opportunities` | companies, contacts, profiles |
| 6 | `opportunity_products` | opportunities |
| 7 | `interactions` | opportunities, contacts, profiles |
| 8 | `proposals` | opportunities, companies, profiles |
| 9 | `tasks` | profiles, companies |
| 10 | `lgpd_requests` | companies, profiles |
| 11 | `audit_log` | (sem FK — pode ir por último, ou nem restaurar) |

> `profiles` espelha `auth.users`. Se os usuários do Auth não existirem mais
> (projeto novo), recrie-os primeiro no Supabase Auth com os **mesmos `id`**,
> senão os `created_by`/`seller_id` ficarão órfãos (são `ON DELETE SET NULL`,
> então não quebram — só perdem o vínculo).

---

## Método A — `curl` com upsert (recomendado)

Para cada tabela, na ordem acima, faça um **upsert** (insere ou atualiza se o
`id` já existir). O header `Prefer: resolution=merge-duplicates` faz o upsert
por chave primária.

```bash
restore_table () {
  local tabela="$1"
  local arquivo="$2"   # caminho do .json daquela tabela
  echo "Restaurando $tabela ..."
  curl -s -X POST "$SB_URL/rest/v1/$tabela" \
    -H "apikey: $SB_KEY" \
    -H "Authorization: Bearer $SB_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=minimal" \
    --data-binary "@$arquivo"
  echo " ok"
}

PASTA="backups/2026-06-10"   # ajuste para a data do backup desejado

restore_table profiles             "$PASTA/profiles.json"
restore_table products             "$PASTA/products.json"
restore_table companies            "$PASTA/companies.json"
restore_table contacts             "$PASTA/contacts.json"
restore_table opportunities        "$PASTA/opportunities.json"
restore_table opportunity_products "$PASTA/opportunity_products.json"
restore_table interactions         "$PASTA/interactions.json"
restore_table proposals            "$PASTA/proposals.json"
restore_table tasks                "$PASTA/tasks.json"
restore_table lgpd_requests        "$PASTA/lgpd_requests.json"
restore_table audit_log            "$PASTA/audit_log.json"
```

**Se vier do backup manual** (um único `backup-adiblock-*.json` com tudo
dentro), extraia cada tabela antes:

```bash
for t in profiles products companies contacts opportunities \
         opportunity_products interactions proposals tasks \
         lgpd_requests audit_log; do
  jq ".$t // []" backup-adiblock-XXXX.json > "/tmp/$t.json"
done
# depois rode restore_table apontando para /tmp/$t.json
```

### Sobre conflito de chave única

- `proposals` tem `UNIQUE (ano, numero)`. Se restaurar por cima de dados
  existentes com mesmos números, o merge por `id` resolve — mas se os `id`
  forem diferentes e o `(ano,numero)` colidir, vai dar erro 409. Nesse caso,
  restaure numa tabela limpa.
- `products` tem `UNIQUE (nome, embalagem)`. Mesmo raciocínio.

Para uma restauração **limpa** (banco vazio), não há conflito — é o cenário
mais simples.

---

## Método B — SQL Editor do Supabase

Se preferir não usar `curl`, dá para carregar via SQL com `jsonb`:

1. Abra o conteúdo do `.json` da tabela.
2. No SQL Editor:

```sql
-- Exemplo para companies (repita por tabela, na ordem das FKs)
insert into public.companies
select * from jsonb_populate_recordset(null::public.companies, '<COLE_O_ARRAY_JSON_AQUI>'::jsonb)
on conflict (id) do update set
  razao_social = excluded.razao_social,
  -- ... demais colunas ...
  updated_at = excluded.updated_at;
```

Para arrays grandes, prefira o Método A (curl), que não tem limite de tamanho
de query.

---

## Verificação pós-restauração

```sql
select 'companies' t, count(*) from public.companies
union all select 'contacts', count(*) from public.contacts
union all select 'opportunities', count(*) from public.opportunities
union all select 'proposals', count(*) from public.proposals
union all select 'products', count(*) from public.products
order by 1;
```

Compare com os totais no `_meta.json` da pasta de backup.

Depois, recarregue o app (Ctrl+Shift+R) e confira as abas Empresas, Pipeline e
Propostas.

```sql
NOTIFY pgrst, 'reload schema';
```

---

## Recuperação parcial via `audit_log` (sem backup)

Se só algumas linhas sumiram e o `audit_log` estava ativo, dá para reconstruir
a partir dele (foi assim que as 23 propostas foram recuperadas em 01/06/2026):

```sql
-- Estado final de cada registro vivo de uma tabela (ex: proposals)
with ultimo as (
  select distinct on (row_id) row_id, action, new_data
  from public.audit_log
  where table_name = 'proposals'
  order by row_id, created_at desc
)
select new_data->>'numero' as numero,
       new_data->'snapshot'->'cliente'->>'name' as cliente
from ultimo
where action <> 'DELETE'
order by 1;
```

Depois, reinsira o `new_data` de cada `row_id` na tabela
(ver histórico do projeto / sessão de recuperação para o script completo).
