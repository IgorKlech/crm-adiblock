# Design — Migração Multi-Tenant (Sprint 9.0)

> **Status: PROPOSTA para revisão.** Nenhum código de aplicação ou schema foi
> alterado neste sprint. Este documento descreve *como* tornar o CRM Adiblock
> um produto multi-empresa. A execução virá em sprints próprios (9.1, 9.2…),
> cada etapa em arquivo de migração datado em `/migrations` (Regra de Ouro nº4).

---

## 0. Contexto e objetivo

Hoje o banco atende **uma** empresa (Adiblock). A `Visão de produto` do
`CLAUDE.md` define o rumo: virar **produto multi-empresa (multi-tenant)**, com
`org_id` em todas as tabelas e isolamento por RLS.

Objetivo desta migração: **isolar 100% os dados de cada organização**, de forma
que um usuário de uma org **nunca** veja dados de outra — sem reescrever o
frontend e sem downtime perceptível.

Princípio-guia: **o isolamento é responsabilidade do banco (RLS)**, não do
front. O app continua chamando `api('GET','companies',...)` e o Postgres só
devolve as linhas da org do usuário logado.

---

## 1. Modelo escolhido

**Single database, shared schema, isolamento por `org_id` via RLS.**

Todas as orgs dividem as mesmas tabelas; cada linha carrega um `org_id`; o RLS
filtra por organização. É o modelo de menor custo operacional e o mais simples
de manter no plano atual (Supabase Free → Pro), adequado à escala prevista
(dezenas a centenas de PMEs), e sem o overhead de schema-por-tenant ou
banco-por-tenant.

| Alternativa | Por que NÃO agora |
|---|---|
| Schema por tenant | Multiplica migrations e conexões; complexo no Supabase |
| Banco por tenant | Caro, provisionamento manual, backup N vezes |
| **Shared schema + RLS** | **Escolhido** — 1 migration serve todos; RLS já é a base do projeto |

### Nova tabela `organizations`

```
organizations
  id          uuid PK default gen_random_uuid()
  nome        text not null
  cnpj        text
  plano       text not null default 'free'   -- free | pro | ...
  status      text not null default 'ativo'  -- ativo | suspenso | cancelado
  created_at  timestamptz not null default now()
```

`profiles` ganha `org_id uuid` (FK → organizations). É a **âncora**: a função
`current_org()` lê a org do usuário logado a partir de `profiles.org_id`.

### Tabelas que recebem `org_id`

Tabelas de **dados de negócio** (isoladas por org):

`companies, contacts, opportunities, opportunity_products, interactions,
proposals, tasks, products, audit_log, lgpd_requests, pedido_sequences`

Tabelas/único caso especial:
- `profiles` — recebe `org_id` (cada usuário pertence a uma org).
- `organizations` — é a raiz, não tem `org_id`.
- `products` — **decisão a revisar**: catálogo é por-org (cada empresa tem o
  seu) → recebe `org_id`. (Se um dia houver catálogo global compartilhado, vira
  exceção; por ora, por-org.)
- `pedido_sequences` — a numeração de pedido é **por org**. A PK muda de `(ano)`
  para `(org_id, ano)` (ver §2d). Cada org tem sua própria sequência anual.

---

## 2. Plano de migração (idempotente e reversível, em etapas)

Cada etapa = **um arquivo** em `/migrations` (`AAAA-MM-DD-9x-descricao.sql`).
Rodar uma etapa por vez, validando antes da próxima. Todas idempotentes
(`IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `DROP POLICY IF EXISTS`).

### Etapa A — criar `organizations` + seed Adiblock

```sql
CREATE TABLE IF NOT EXISTS public.organizations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome       text NOT NULL,
  cnpj       text,
  plano      text NOT NULL DEFAULT 'free',
  status     text NOT NULL DEFAULT 'ativo',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed com id FIXO e conhecido (facilita backfill e rollback)
INSERT INTO public.organizations (id, nome, cnpj, plano, status)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'Adiblock',
        '31.458.997/0001-51', 'pro', 'ativo')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
-- Cada usuario so enxerga a PROPRIA org
DROP POLICY IF EXISTS "orgs_select_own" ON public.organizations;
CREATE POLICY "orgs_select_own" ON public.organizations
  FOR SELECT TO authenticated USING (id = public.current_org());
```

> O id fixo `...a1` é só uma convenção legível para o seed. Pode ser qualquer
> uuid, desde que usado consistentemente no backfill (Etapa C).

**Reversível:** `DROP TABLE public.organizations CASCADE;` (nada depende dela
ainda nesta etapa).

### Etapa B — adicionar `org_id` NULLABLE em todas as tabelas

Nullable primeiro para **não travar** nada em produção (sem backfill ainda).

```sql
ALTER TABLE public.profiles             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.companies            ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.contacts             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.opportunities        ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.opportunity_products ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.interactions         ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.proposals            ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.tasks                ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.products             ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
ALTER TABLE public.audit_log            ADD COLUMN IF NOT EXISTS org_id uuid;  -- sem FK (audit sobrevive a exclusao, padrao do projeto)
ALTER TABLE public.lgpd_requests        ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
```

`pedido_sequences` é tratada na Etapa D (muda a PK).

**Reversível:** `ALTER TABLE ... DROP COLUMN IF EXISTS org_id;` por tabela.
Como é nullable e ninguém usa ainda, dropar não afeta a operação atual.

### Etapa C — backfill com o id da Adiblock

Todos os dados existentes são da Adiblock.

```sql
DO $$
DECLARE adi uuid := '00000000-0000-0000-0000-0000000000a1';
BEGIN
  UPDATE public.profiles             SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.companies            SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.contacts             SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.opportunities        SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.opportunity_products SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.interactions         SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.proposals            SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.tasks                SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.products             SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.audit_log            SET org_id = adi WHERE org_id IS NULL;
  UPDATE public.lgpd_requests        SET org_id = adi WHERE org_id IS NULL;
END $$;
```

**Verificação obrigatória antes da Etapa D** (nenhum NULL restante):

```sql
SELECT 'companies' t, count(*) FILTER (WHERE org_id IS NULL) nulos FROM public.companies
UNION ALL SELECT 'contacts',     count(*) FILTER (WHERE org_id IS NULL) FROM public.contacts
UNION ALL SELECT 'opportunities',count(*) FILTER (WHERE org_id IS NULL) FROM public.opportunities
UNION ALL SELECT 'proposals',    count(*) FILTER (WHERE org_id IS NULL) FROM public.proposals
UNION ALL SELECT 'profiles',     count(*) FILTER (WHERE org_id IS NULL) FROM public.profiles;
-- todos os "nulos" devem ser 0
```

**Reversível:** `UPDATE ... SET org_id = NULL WHERE org_id = '<adi>';` (volta ao
estado da Etapa B). Sem perda de dados.

### Etapa D — NOT NULL + índices compostos + PK de sequências

Só depois de confirmar 0 nulos.

```sql
-- NOT NULL (trava: toda linha nova precisa de org)
ALTER TABLE public.profiles             ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.companies            ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.contacts             ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.opportunities        ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.opportunity_products ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.interactions         ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.proposals            ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.tasks                ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.products             ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.lgpd_requests        ALTER COLUMN org_id SET NOT NULL;
-- audit_log: manter NULLABLE (registros de exclusao podem nao ter org resolvida)

-- Indices compostos (org_id primeiro = filtro mais seletivo do RLS)
CREATE INDEX IF NOT EXISTS idx_companies_org      ON public.companies(org_id, razao_social);
CREATE INDEX IF NOT EXISTS idx_contacts_org       ON public.contacts(org_id, company_id);
CREATE INDEX IF NOT EXISTS idx_opps_org           ON public.opportunities(org_id, estagio);
CREATE INDEX IF NOT EXISTS idx_opps_org_callback  ON public.opportunities(org_id, callback_date) WHERE estagio NOT IN ('ganha','perdida');
CREATE INDEX IF NOT EXISTS idx_oppprod_org        ON public.opportunity_products(org_id, opportunity_id);
CREATE INDEX IF NOT EXISTS idx_inter_org          ON public.interactions(org_id, datetime);
CREATE INDEX IF NOT EXISTS idx_proposals_org      ON public.proposals(org_id, ano, numero);
CREATE INDEX IF NOT EXISTS idx_tasks_org          ON public.tasks(org_id, seller_id, due_at);
CREATE INDEX IF NOT EXISTS idx_products_org       ON public.products(org_id, nome);
CREATE INDEX IF NOT EXISTS idx_audit_org          ON public.audit_log(org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lgpd_org           ON public.lgpd_requests(org_id);

-- UNIQUE constraints viram por-org:
--   proposals: (ano, numero) -> (org_id, ano, numero)
--   products:  (nome, embalagem) -> (org_id, nome, embalagem)
--   companies: (cnpj) -> (org_id, cnpj)
ALTER TABLE public.proposals DROP CONSTRAINT IF EXISTS proposals_ano_numero_key;
ALTER TABLE public.proposals ADD  CONSTRAINT proposals_org_ano_numero_key UNIQUE (org_id, ano, numero);
ALTER TABLE public.products  DROP CONSTRAINT IF EXISTS products_nome_embalagem_key;
ALTER TABLE public.products  ADD  CONSTRAINT products_org_nome_emb_key UNIQUE (org_id, nome, embalagem);
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_cnpj_key;
ALTER TABLE public.companies ADD  CONSTRAINT companies_org_cnpj_key UNIQUE (org_id, cnpj);

-- pedido_sequences: numeracao por org. PK (ano) -> (org_id, ano)
ALTER TABLE public.pedido_sequences ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.organizations(id);
UPDATE public.pedido_sequences SET org_id = '00000000-0000-0000-0000-0000000000a1' WHERE org_id IS NULL;
ALTER TABLE public.pedido_sequences ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE public.pedido_sequences DROP CONSTRAINT IF EXISTS pedido_sequences_pkey;
ALTER TABLE public.pedido_sequences ADD  PRIMARY KEY (org_id, ano);
```

> ⚠ **Nomes reais das constraints únicas** (`proposals_ano_numero_key` etc.)
> devem ser confirmados no banco antes de rodar:
> `SELECT conname FROM pg_constraint WHERE conrelid = 'public.proposals'::regclass;`
> Os nomes acima são os *defaults* do Postgres, mas valem verificação.

**Reversível:** `ALTER COLUMN org_id DROP NOT NULL`, `DROP INDEX`, e restaurar
as constraints únicas antigas. Os índices podem ser dropados sem perda.

### Etapa E — `current_org()` (SECURITY DEFINER)

```sql
CREATE OR REPLACE FUNCTION public.current_org()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.current_org() TO authenticated;
```

`SECURITY DEFINER` + `STABLE`: roda com privilégio do dono (lê `profiles` sem
recursão de RLS) e é cacheável por statement. Mesmo padrão de
`current_user_role()` já existente.

> **Trigger de auto-preenchimento (recomendado):** para o front não precisar
> mandar `org_id`, um trigger `BEFORE INSERT` em cada tabela seta
> `NEW.org_id := current_org()` quando vier NULL. Detalhe de implementação a
> definir na execução; entra como item da Etapa E.

### Etapa F — reescrever as policies RLS (org_id em TODAS)

A regra geral: **toda** policy ganha `org_id = public.current_org()`, somado às
condições atuais. Abaixo, **cada policy atual do `supabase_setup.sql` e sua
versão nova**.

#### profiles
```sql
-- ATUAL
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated USING (true);
-- NOVA  (so ve perfis da mesma org)
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated
  USING (org_id = public.current_org());

-- ATUAL
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));
-- NOVA  (idem + nao pode trocar de org)
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid() AND org_id = public.current_org())
  WITH CHECK (id = auth.uid() AND org_id = public.current_org()
              AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));

-- ATUAL
CREATE POLICY "profiles_update_admin" ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
-- NOVA  (admin so administra a propria org)
CREATE POLICY "profiles_update_admin" ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_admin() AND org_id = public.current_org())
  WITH CHECK (public.is_admin() AND org_id = public.current_org());

-- ATUAL
CREATE POLICY "profiles_delete_admin" ON public.profiles FOR DELETE TO authenticated
  USING (public.is_admin());
-- NOVA
CREATE POLICY "profiles_delete_admin" ON public.profiles FOR DELETE TO authenticated
  USING (public.is_admin() AND org_id = public.current_org());
```

#### companies
```sql
-- ATUAL
CREATE POLICY "companies_select" ON public.companies FOR SELECT TO authenticated USING (true);
-- NOVA
CREATE POLICY "companies_select" ON public.companies FOR SELECT TO authenticated
  USING (org_id = public.current_org());

-- ATUAL
CREATE POLICY "companies_insert" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_leitor());
-- NOVA  (garante que o insert e na propria org)
CREATE POLICY "companies_insert" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_leitor() AND org_id = public.current_org());

-- ATUAL
CREATE POLICY "companies_update_owner" ON public.companies FOR UPDATE TO authenticated
  USING (public.is_admin() OR created_by = auth.uid())
  WITH CHECK (public.is_admin() OR created_by = auth.uid());
-- NOVA
CREATE POLICY "companies_update_owner" ON public.companies FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));

-- ATUAL
CREATE POLICY "companies_delete_owner" ON public.companies FOR DELETE TO authenticated
  USING (public.is_admin() OR created_by = auth.uid());
-- NOVA
CREATE POLICY "companies_delete_owner" ON public.companies FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR created_by = auth.uid()));
```

#### contacts
```sql
-- ATUAL
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated USING (true);
CREATE POLICY "contacts_write"  ON public.contacts FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());
-- NOVA
CREATE POLICY "contacts_select" ON public.contacts FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "contacts_write"  ON public.contacts FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
```

#### opportunities
```sql
-- ATUAL
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated USING (true);
CREATE POLICY "opportunities_write"  ON public.opportunities FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());
-- NOVA
CREATE POLICY "opportunities_select" ON public.opportunities FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opportunities_write"  ON public.opportunities FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
```

#### opportunity_products
```sql
-- ATUAL
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated USING (true);
CREATE POLICY "opp_products_write"  ON public.opportunity_products FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());
-- NOVA
CREATE POLICY "opp_products_select" ON public.opportunity_products FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "opp_products_write"  ON public.opportunity_products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
```

#### interactions
```sql
-- ATUAL
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "interactions_write"  ON public.interactions FOR ALL TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());
-- NOVA
CREATE POLICY "interactions_select" ON public.interactions FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "interactions_write"  ON public.interactions FOR ALL TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
```

#### proposals
```sql
-- ATUAL
CREATE POLICY "proposals_select"        ON public.proposals FOR SELECT TO authenticated USING (true);
CREATE POLICY "proposals_insert"        ON public.proposals FOR INSERT TO authenticated WITH CHECK (NOT public.is_leitor());
CREATE POLICY "proposals_delete"        ON public.proposals FOR DELETE TO authenticated USING (public.is_admin());
CREATE POLICY "proposals_update_status" ON public.proposals FOR UPDATE TO authenticated
  USING (NOT public.is_leitor()) WITH CHECK (NOT public.is_leitor());
-- NOVA
CREATE POLICY "proposals_select"        ON public.proposals FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "proposals_insert"        ON public.proposals FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
CREATE POLICY "proposals_delete"        ON public.proposals FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND public.is_admin());
CREATE POLICY "proposals_update_status" ON public.proposals FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND NOT public.is_leitor())
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor());
```

#### audit_log
```sql
-- ATUAL
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated USING (true);
CREATE POLICY "audit_insert" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (true);
-- NOVA  (le so a propria org; insert continua liberado p/ o trigger SECURITY DEFINER)
CREATE POLICY "audit_select" ON public.audit_log FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "audit_insert" ON public.audit_log FOR INSERT TO authenticated
  WITH CHECK (true);
-- Obs: o trigger log_audit_changes() passa a gravar NEW.org_id := current_org().
```

#### lgpd_requests
```sql
-- ATUAL
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated USING (true);
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated WITH CHECK (true);
-- NOVA
CREATE POLICY "lgpd_select" ON public.lgpd_requests FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "lgpd_insert" ON public.lgpd_requests FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org());
```

#### products
```sql
-- ATUAL
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_write"  ON public.products FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
-- NOVA
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "products_write"  ON public.products FOR ALL TO authenticated
  USING (org_id = public.current_org() AND public.is_admin())
  WITH CHECK (org_id = public.current_org() AND public.is_admin());
```

#### tasks
```sql
-- ATUAL
CREATE POLICY "tasks_select"     ON public.tasks FOR SELECT TO authenticated USING (true);
CREATE POLICY "tasks_insert"     ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_leitor() AND (seller_id = auth.uid() OR public.is_admin()));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (public.is_admin() OR seller_id = auth.uid())
  WITH CHECK (public.is_admin() OR seller_id = auth.uid());
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (public.is_admin() OR seller_id = auth.uid());
-- NOVA
CREATE POLICY "tasks_select"     ON public.tasks FOR SELECT TO authenticated
  USING (org_id = public.current_org());
CREATE POLICY "tasks_insert"     ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (org_id = public.current_org() AND NOT public.is_leitor()
              AND (seller_id = auth.uid() OR public.is_admin()));
CREATE POLICY "tasks_update_own" ON public.tasks FOR UPDATE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()))
  WITH CHECK (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));
CREATE POLICY "tasks_delete_own" ON public.tasks FOR DELETE TO authenticated
  USING (org_id = public.current_org() AND (public.is_admin() OR seller_id = auth.uid()));
```

#### pedido_sequences
```sql
-- ATUAL
CREATE POLICY "pedido_seq_admin" ON public.pedido_sequences FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
-- NOVA
CREATE POLICY "pedido_seq_admin" ON public.pedido_sequences FOR ALL TO authenticated
  USING (org_id = public.current_org() AND public.is_admin())
  WITH CHECK (org_id = public.current_org() AND public.is_admin());
-- Obs: a funcao atribui_numero_pedido() passa a filtrar por (org_id, ano).
```

#### organizations
```sql
-- (criada na Etapa A) — so le a propria org
CREATE POLICY "orgs_select_own" ON public.organizations FOR SELECT TO authenticated
  USING (id = public.current_org());
```

**Reversível (todas as policies):** como cada `CREATE POLICY` é precedido de
`DROP POLICY IF EXISTS`, o rollback é reaplicar o `supabase_setup.sql` na
versão pré-9.x (as policies "ATUAL" acima). Guardar a versão antiga em
`/migrations` como `rollback`.

---

## 3. Mudanças no front

**Em lugar nenhum.** O isolamento é 100% no banco:

- O front continua chamando `api('GET','companies',...)` etc. O RLS devolve só
  as linhas da org do usuário. **Nenhuma query do front muda.**
- Os INSERTs **não** precisam mandar `org_id`: o trigger `BEFORE INSERT`
  (Etapa E) preenche `NEW.org_id := current_org()`. Assim o front nem sabe que
  `org_id` existe.

### Exceções (os únicos pontos a tocar no front, em sprint futuro)

1. **Numeração por org** — `numProposta()`/`numPedido()` já leem do registro;
   nada muda. A função SQL de numeração de pedido passa a filtrar por
   `(org_id, ano)` — mudança no banco, não no front.
2. **Backup — decisão aprovada: global (dono) + por-org (cada empresa).**
   Sai quase de graça da própria arquitetura RLS, sem código novo:
   - **Global do dono**: o `.github/workflows/backup.yml` usa a `service_role`
     key, que **ignora o RLS** → continua exportando **todas as orgs**. É o seu
     backup-mãe. Sem mudança.
   - **Por-org**: o botão "Baixar Backup" no app usa o **token do usuário
     logado**, então o RLS **filtra automaticamente** só os dados da org dele.
     Quando houver multi-tenant, cada admin de empresa baixa só o que é seu —
     sem nenhuma alteração no `baixarBackup()`.
   Único ajuste futuro (cosmético): o `_meta` do backup global poderia separar
   os totais por org. Não-bloqueante.
3. **Tela de cadastro de org / troca de org**: só existe quando entrarmos em
   onboarding (fora desta fase — §6).

---

## 4. Plano de teste (provar que NADA vaza)

Criar uma **org fake** com usuário próprio e verificar isolamento total.

### Setup do teste
```sql
-- 1) Org de teste
INSERT INTO public.organizations (id, nome, plano, status)
VALUES ('00000000-0000-0000-0000-0000000000b2', 'Empresa Teste', 'free', 'ativo');

-- 2) Criar um usuario no Supabase Auth (painel) e pegar o id; entao:
UPDATE public.profiles SET org_id = '00000000-0000-0000-0000-0000000000b2', role = 'admin'
WHERE id = '<uuid-do-usuario-teste>';

-- 3) Inserir 1 empresa de teste nessa org
INSERT INTO public.companies (razao_social, org_id, created_by)
VALUES ('Cliente da Empresa Teste', '00000000-0000-0000-0000-0000000000b2', '<uuid-do-usuario-teste>');
```

### Checklist de verificação (logado como cada usuário)

Rodar as queries **autenticado** (via app ou REST com o JWT do usuário), não
como `service_role` (que ignora RLS).

| # | Logado como | Query | Resultado esperado |
|---|---|---|---|
| 1 | user Adiblock | `GET /companies` | só empresas da Adiblock; **não** aparece "Cliente da Empresa Teste" |
| 2 | user Teste | `GET /companies` | só "Cliente da Empresa Teste"; **nenhuma** empresa Adiblock |
| 3 | user Teste | `GET /proposals` | vazio (org nova, sem propostas) |
| 4 | user Teste | `GET /opportunities` | vazio |
| 5 | user Teste | tentar `PATCH /companies?id=eq.<id_de_empresa_Adiblock>` | 0 linhas afetadas (RLS bloqueia) |
| 6 | user Teste | tentar `GET /profiles` | só o próprio perfil (mesma org) |
| 7 | user Adiblock | `GET /audit_log` | só eventos da Adiblock |
| 8 | qualquer | `SELECT current_org()` | retorna o org_id correto do usuário |

### Teste de contagem cruzada (como service_role, só para conferência)
```sql
SELECT org_id, count(*) FROM public.companies GROUP BY org_id;
-- deve mostrar as 2 orgs com contagens separadas e coerentes
```

**Critério de aprovação:** itens 1–8 todos OK. Qualquer vazamento (ver dado de
outra org) = **falha**, reverter Etapa F e investigar a policy.

---

## 5. Riscos e rollback por etapa

| Etapa | Risco | Mitigação / Rollback |
|---|---|---|
| A (organizations) | Baixo. Tabela nova, nada depende. | `DROP TABLE organizations CASCADE`. |
| B (org_id nullable) | Baixo. Coluna nullable não afeta nada. | `DROP COLUMN org_id` por tabela. |
| C (backfill) | Médio. UPDATE em massa. Se id errado, dados ficam órfãos. | Idempotente (`WHERE org_id IS NULL`). Rollback: `SET org_id = NULL`. Verificação de 0 nulos antes de seguir. |
| D (NOT NULL + índices + PK) | **Alto.** NOT NULL trava se sobrou nulo; mudar PK de `pedido_sequences` e UNIQUEs pode falhar se houver duplicidade cross-org (não há ainda). | Só rodar após verificação da Etapa C. Rollback: `DROP NOT NULL`, `DROP INDEX`, restaurar constraints antigas. Rodar em janela de baixo uso. |
| E (current_org + trigger) | Médio. Se `current_org()` retorna NULL (perfil sem org), policies barram tudo → app "vazio". | Garantir backfill de `profiles.org_id` (Etapa C) **antes**. Teste: `SELECT current_org()` ≠ NULL para todos os usuários. |
| F (policies RLS) | **Alto.** Policy errada = vazamento entre orgs **ou** app inteiro bloqueado. | Aplicar tudo numa transação; rodar o checklist §4 imediatamente. Rollback: reaplicar policies "ATUAL". Testar em staging/projeto-cópia antes de produção. |

### Ordem segura de execução
A → B → C → **(verificar 0 nulos)** → E → D → F → **(rodar checklist §4)**.

> `current_org()` (E) antes de F porque as policies novas dependem dela.
> NOT NULL (D) depois do backfill (C). Idealmente ensaiar tudo num **projeto
> Supabase de cópia** antes da produção.

### Salvaguardas gerais
- **Backup antes de tudo** (workflow do Sprint 7.5 + "Baixar Backup" manual).
- Cada etapa é um arquivo datado em `/migrations` (Regra de Ouro nº4).
- Nunca rodar o `supabase_setup.sql` inteiro (Regra de Ouro nº1).
- Ter o `rollback.sql` de cada etapa escrito **antes** de aplicar.

---

## 6. Fora do escopo desta fase (fase seguinte)

Esta migração entrega **apenas o isolamento de dados**. Ficam para depois:

- **Billing / planos**: cobrança, limites por plano (`organizations.plano` já
  existe como campo, mas sem enforcement).
- **Onboarding self-service**: criar org + primeiro admin sozinho (signup).
- **Convites de usuário**: hoje o admin cria usuário pelo Supabase Auth; um
  fluxo de convite por e-mail (com org_id pré-atribuído) vem depois.
- **Troca de org / multi-org por usuário**: um usuário pertence a **uma** org
  nesta fase. Suporte a usuário em várias orgs é fase futura.
- **Admin do produto (super-admin)**: papel que enxerga todas as orgs (para
  suporte). Hoje, só via `service_role` no painel.
- ~~Backup por-org~~ **RESOLVIDO no design** (item 3, exceção 2): global do dono
  via service_role + por-org via RLS no botão "Baixar Backup". Sem código novo.
- **Branding por org**: logo/cores/termos por organização (o `ADIBLOCK_INFO`
  hoje é fixo; vira config por org).

---

## 7. Resumo para decisão

- **Modelo:** shared schema + RLS por `org_id`. Menor custo, alinhado ao que já
  existe.
- **Migração:** 6 etapas idempotentes e reversíveis, cada uma num arquivo
  datado, ensaiáveis em cópia antes da produção.
- **Front:** zero mudança (o RLS resolve); trigger preenche `org_id`.
- **Prova de isolamento:** checklist de 8 verificações com org fake.
- **Maior risco:** Etapa F (policies). Mitigado por teste em cópia + checklist
  + rollback pronto.

**Aguardando sua revisão antes de escrever qualquer migração (9.1+).**
