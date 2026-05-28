# /sql-pending

Mostra os blocos SQL que ainda precisam ser rodados no Supabase SQL Editor para a sessão atual.

## Instruções

Leia o `supabase_setup.sql` e o `CLAUDE.md` do projeto e mostre de forma clara:

1. **Quais migrações existem** (por sprint) e uma forma de checar se já foram aplicadas
2. **O SQL exato** para rodar — bloco copiável, pronto para colar no Supabase
3. **Como verificar** se já foi aplicado (ex: checar `information_schema.columns` para a coluna)

## Como checar cada migração

### Sprint 6.1 — callback_date como timestamptz
Verifique com:
```sql
SELECT data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='opportunities' AND column_name='callback_date';
-- Se retornar 'timestamp with time zone', já foi feito. Se 'date', precisa rodar.
```

### Sprint 6.2 — tabela tasks
Verifique com:
```sql
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema='public' AND table_name='tasks'
);
-- Se false, precisa criar a tabela.
```

### Sprint 6.5 — coluna status em proposals
Verifique com:
```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='proposals' AND column_name='status';
-- Se não retornar linha, precisa rodar o ALTER.
```

## Formato de saída esperado

Para cada migração, mostre:
- ✅ Já aplicada — ou — ⚠ Pendente
- O SQL completo pronto para copiar (se pendente)
- Link para o Supabase SQL Editor: https://supabase.com/dashboard/project/[PROJECT_ID]/sql

## Nota
Os SQLs no `supabase_setup.sql` são **idempotentes** — podem ser rodados mais de uma vez sem quebrar nada.
Sempre termine com: `NOTIFY pgrst, 'reload schema';`
