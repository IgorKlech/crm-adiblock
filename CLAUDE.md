# CLAUDE.md — CRM Adiblock

Guia de contexto para novas sessões. Leia antes de qualquer implementação.

---

## ⚠️ REGRA DE OURO — NUNCA QUEBRAR

1. **NUNCA rodar o `supabase_setup.sql` INTEIRO no banco de produção.**
   O bloco de `DROP TABLE` do modelo antigo já está comentado, mas o hábito
   certo é: mudanças de banco vão sempre em **blocos pequenos e específicos**,
   nunca o arquivo completo. Em 01/06/2026 o arquivo inteiro foi rodado e
   apagou todas as propostas/pedidos (recuperados via `audit_log`).

2. **Plano Supabase é Free — não tem backup nativo restaurável.** A rede de
   segurança (Sprint 7.5) tem 3 camadas:
   (a) **Backup automático diário** via GitHub Actions (`.github/workflows/backup.yml`,
       03:00 BRT) que exporta todas as tabelas em JSON para a branch `backups`;
   (b) o botão **"Baixar Backup"** no app (Dashboard, admin) — backup manual,
       lembrado por toast toda sexta;
   (c) o `audit_log` (só mudanças, parcial) como último recurso.
   Restauração: ver **`docs/RESTORE.md`**.

   **Secrets do GitHub** (Settings > Secrets and variables > Actions) que o
   workflow exige — NUNCA colocar a service key em arquivo do repo:
   - `SUPABASE_URL` — ex: `https://kgiynhrytnzfdywgjhby.supabase.co`
   - `SUPABASE_SERVICE_KEY` — a `service_role` key (Supabase > Settings > API)
   - `BACKUP_REPO_TOKEN` — *(opcional)* PAT com acesso ao repo `<owner>/crm-backups`.
     Se ausente, o backup vai para a branch `backups` deste mesmo repo.

3. **Migração destrutiva, se algum dia necessária, vai em arquivo SEPARADO**
   e versionado — nunca no setup que é rodado com frequência.

4. **Toda mudança de schema vai em arquivo NOVO em `/migrations`** com data no
   nome (`AAAA-MM-DD-descricao.sql`), nunca editando migrations antigas. Uma
   migration já aplicada é histórico imutável — para corrigir algo, crie outra.

---

## 1. O que é este projeto

**CRM Adiblock** — sistema comercial interno da Adiblock (fabricante de aditivos para concreto).

- URL produção: **https://crm-adiblock.vercel.app/**
- Repo GitHub: **https://github.com/IgorKlech/crm-adiblock**
- Deploy: Vercel (auto-deploy ao push em `main`)
- Stack: `index.html` (em migração para módulos `<script src>`) + Supabase via CDN + Vercel estático

---

## Visão de produto

O CRM deixará de ser apenas interno (Adiblock) e está sendo preparado para virar
**produto multi-empresa (multi-tenant)**.

- **No futuro, todas as tabelas terão `org_id`** isolando os dados de cada empresa
  cliente; o RLS passará a filtrar por organização além de por usuário.
- **Toda feature nova deve ser escrita já sabendo disso.** Na prática:
  - **Nada de hard-codar dados Adiblock em lógica nova.** Dados específicos da
    Adiblock (CNPJ, endereço, termos comerciais, nomes de vendedores, catálogo)
    são *conteúdo*, não regra — devem vir de tabela/config, nunca embutidos em
    `if`/constante dentro de função.
  - Lógica nova não deve assumir "empresa única". Pensar sempre "de qual
    organização é este dado?".
  - O `ADIBLOCK_INFO` e afins existentes são legado tolerado; **não criar novos**
    desse tipo. Quando tocar numa área dessas, preferir mover para config.
- A migração para multi-tenant será incremental e em sprints próprios — não
  refatorar tudo de uma vez. Mas **cada linha nova nasce multi-tenant-aware**.

---

## 2. Restrições arquiteturais (não negociáveis)

| Restrição | Motivo |
|---|---|
| **Migração incremental para módulos `<script src>` sem build tool** | O single-file `index.html` cumpriu seu papel e está sendo aposentado de forma incremental. Vercel continua estático. Nenhum framework ou bundler até decisão explícita. |
| **Vanilla JS (sem framework)** | Escolha consciente — não usar React, Vue, etc. |
| **Supabase via CDN** | `@supabase/supabase-js@2.39.3` importado pelo jsDelivr |
| **Sem servidor próprio** | Toda lógica de backend é RLS + triggers PostgreSQL |
| **Vercel sem build step** | Apenas arquivos estáticos — sem `package.json`, sem bundler |

> ⚠ Nunca sugerir quebrar essas restrições. Se vier pedido de framework ou build tool, implementar dentro dos limites acima. A divisão de `index.html` em múltiplos `<script src>` é permitida e incentivada (cada arquivo carrega como `<script>` separado, sem bundler).

---

## 3. Equipe e usuários

| Usuário | Email | Role |
|---|---|---|
| Igor Klech | pcp@adiblock.online | `admin` |
| Nádia | comercial@adiblock.online | `vendedor` |
| Letícia | vendas@adiblock.online | `vendedor` |
| Gracielle | laboratorio@adiblock.online | `vendedor` |

Roles: `admin`, `vendedor`, `leitor`. Default: `vendedor`.

---

## 4. Banco de dados (Supabase — schema `public`)

### Tabelas principais

```
profiles            — vendedores e admin (espelha auth.users)
companies           — empresas B2B (substitui "clients" do modelo antigo)
contacts            — contatos dentro de uma empresa (N por empresa)
opportunities       — oportunidades de venda (N por empresa)
opportunity_products— produtos de uma oportunidade
interactions        — histórico de contatos por oportunidade
proposals           — propostas comerciais (snapshot jsonb imutável)
tasks               — tarefas livres (Sprint 6.2, sem oportunidade)
audit_log           — log imutável de INSERT/UPDATE/DELETE
lgpd_requests       — ações LGPD
products            — catálogo de preços (tabela 2025)
```

### View

```
companies_with_tier — calcula tier automático (lead/cliente/conta) baseado em opps ganhas
```

### Campos críticos

- `opportunities.callback_date` — **timestamptz** (não `date`). Migrado em Sprint 6.1.
- `interactions.next_callback` — **timestamptz** (idem).
- `proposals.status` — `em_andamento | pedido | cancelada` (Sprint 6.5).
- `audit_log.company_id` — **sem FK** (audit log sobrevive à exclusão LGPD).

### Funções e triggers

- `current_user_role()` — retorna role do usuário logado (SECURITY DEFINER)
- `is_admin()` / `is_leitor()` — helpers de permissão
- `log_audit_changes()` — trigger em companies/contacts/opportunities/opportunity_products/proposals
- `opportunity_estagio_changed()` — seta `closed_at` e `estagio_changed_at`
- `atribui_numero_proposta()` — numeração sequencial atômica por ano
- `tasks_set_updated()` — seta `done_at` quando `done` muda

---

## 5. Padrões de código

### JavaScript

**Todos os globals são top-level** (sem módulos). 163+ funções no mesmo escopo. Risco de colisão — use nomes descritivos.

```js
// Estado global principal
let CL = [];        // empresas (companies) com embeds
let PF = [];        // profiles (vendedores)
let PRODS = [];     // catálogo de produtos
let TASKS = [];     // tarefas livres
let PROPOSTAS = []; // propostas (cache local)
let ME = null;      // usuário logado (auth)
let MEP = null;     // perfil do usuário logado (profiles)
```

**Data access** — sempre via função `api()`:
```js
// GET
api('GET', 'companies', 'select=*&order=razao_social.asc')
// POST
api('POST', 'opportunities', null, { titulo: '...', ... })
// PATCH
api('PATCH', 'opportunities', `id=eq.${id}`, { estagio: 'ganha' })
// DELETE — usar apiDelete(), não api('DELETE'...)
apiDelete('contacts', `id=eq.${id}`)
```

**Nunca** chamar o endpoint do Supabase diretamente — sempre via `api()`.

### Helpers de data (Sprint 6.1+)

```js
fData(d)          // 'YYYY-MM-DD' ou timestamptz → 'DD/MM/YYYY'
fDataHora(d)      // timestamptz → 'DD/MM/YY HH:MM'
fHora(d)          // timestamptz → 'HH:MM'
dtToInput(ts)     // timestamptz → valor de <input type="datetime-local">
inputToISO(v)     // valor de datetime-local → ISO UTC pra salvar no DB
fRel(d)           // 'Hoje' / 'Amanhã' / '3d atrás' / 'em 5d'
```

**Sempre usar `dtToInput`/`inputToISO`** ao ler/escrever `callback_date` e `next_callback`.

### CSS

Variáveis em `:root` — nunca usar cores hardcoded fora delas:
```css
--p, --ph, --ps   /* primary (azul) */
--ok, --ok2       /* verde */
--er, --er2       /* vermelho */
--wr, --wr2       /* amarelo/warning */
--tx, --tx2       /* texto */
--mt, --mt2       /* muted */
--sur, --bg       /* superfície e fundo */
--bdr, --bdr2     /* bordas */
```

Tema dark: `[data-theme="dark"]` com override de todas as variáveis.

---

## 6. Estrutura de navegação

### Abas (navbar)

| Atalho | Tab | `data-tab` | Render function |
|---|---|---|---|
| T | Hoje/Agenda | `td` | `renderToday()` |
| C | Empresas | `cl` | `renderCl()` |
| — | Pipeline | `kb` | `renderKanban()` |
| P | Propostas | `pr` | `renderPropostas()` |
| D | Dashboard | `db` | `renderDb()` |
| — | Equipe | `eq` | `renderEquipe()` |

### Pages sobrepostas (position:fixed, z-index)

```
600  — kbd-help, gs-overlay
500  — gs-overlay
450  — bell-pop
400  — #tc (toasts), schema-banner
310  — prod-req-m (modal pedido produção)
300  — #co (confirm), drill-m (dashboard drill)
296  — #prod-page (pedido produção)
295  — #cot-page (proposta)
293  — task-m
292  — gcm (modal gerar cotação)
290  — #cont-m, #opp-m, #int-m, #gcm
280  — #pfpage (perfil empresa), #rel-page
200  — .mo (modais genéricos)
150  — #sp (side panel)
100  — #nb (navbar)
```

> Regra: modais que abrem por cima do perfil (`#pfpage` z-index 280) precisam de z-index ≥ 290.

---

## 7. Fluxo de autenticação

```
boot → getSession()
     ↓
     session.user existe?
     ├── sim → checkMfaChallenge() → showApp() → iniciar(user)
     └── não → showLogin()

onAuthStateChange:
  SIGNED_IN     → (só se !APP_INICIADO) → checkMfaChallenge() → iniciar()
  TOKEN_REFRESHED → IGNORAR (não re-inicializa)
  SIGNED_OUT    → showLogin(), reseta APP_INICIADO
```

**`APP_INICIADO`** — flag global que impede `iniciar()` de rodar 2x (evita o bug do alert falso ao ficar idle).

**`limparSessao()`** — limpa todas as chaves `sb-*` do localStorage/sessionStorage. Não toca em `crm_theme`, `crm_metas`, `crm_visoes`.

---

## 8. Documentos imprimíveis

Três documentos distintos — **nunca misturar ao imprimir**:

| Documento | Página | Z-index | Tem valores? |
|---|---|---|---|
| Proposta Comercial | `#cot-page` | 295 | Sim (preços, IPI, total) |
| Pedido de Produção | `#prod-page` | 296 | Não — só produto/embalagem/qtd/peso |
| Relatório Semanal | `#rel-page` | 280 | — |

**Regra de print**: ao abrir `#prod-page`, a `#cot-page` tem `.op` removido. Ao fechar, restaura. Impede que ambos apareçam no PDF.

**`pesoDaEmbalagem(emb)`** — extrai peso por embalagem:
- Regex: `"Bombona 20"` → 20, `"Saco 25"` → 25
- Defaults: `"Tambor"` → 200, `"CNT"` → 1000

---

## 9. Sprints implementados

| Sprint | O que fez | Commit |
|---|---|---|
| 1–3 (legacy) | Modelo B2B (companies/contacts/opportunities), LGPD, roles, audit log, propostas | — |
| 4.1–5.3 | Classificação, kanban, MFA/TOTP, dashboard, ranking, importar CSV | — |
| 6.0 (fix) | Modal proposta abre sobre pfpage (z-index fix) + campo Frete na proposta | 76dfb5b |
| 6.1 | callback com hora (timestamptz), sininho 🔔, aba "Hoje" como inicial | 92423b6 |
| 6.2 | Calendário mensal, tarefas livres (`tasks`), export `.ics` | fd1b933 |
| 6.3 | Busca global (contatos + propostas), toastUndo, empty states, próximo passo | d91eeaf |
| 6.4 | Pedido de Produção (sem valores, para a fábrica) | c3c7e95 + 96845a9 |
| 6.5 | Aba Propostas (em andamento / pedido / cancelada), status na cot-page | 20f82d0 |
| 6.6 | Cards do Dashboard interativos (drill-down por card) | 6f0146c |

---

## 10. SQL de migração pendente (rodar no Supabase)

Sempre verificar se o usuário já rodou antes de pedir de novo.

### Sprint 6.1 — callback_date timestamptz
```sql
DO $$ DECLARE v_type text; BEGIN
  SELECT data_type INTO v_type FROM information_schema.columns
   WHERE table_schema='public' AND table_name='opportunities' AND column_name='callback_date';
  IF v_type = 'date' THEN
    ALTER TABLE public.opportunities ALTER COLUMN callback_date TYPE timestamptz
    USING (callback_date::text || ' 09:00:00-03')::timestamptz;
  END IF;
END $$;
-- (idem para interactions.next_callback)
```

### Sprint 6.2 — tabela tasks
```sql
CREATE TABLE IF NOT EXISTS public.tasks ( ... );
-- Ver supabase_setup.sql bloco Sprint 6.2
```

### Sprint 6.5 — status em proposals
```sql
ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'em_andamento'
  CHECK (status IN ('em_andamento','pedido','cancelada')), ...;
```

> Todos os SQLs estão no `supabase_setup.sql` e são **idempotentes** (podem ser rodados mais de uma vez).

---

## 11. Decisões técnicas importantes

### Por que XHR em vez de fetch nativo?

Vercel injeta scripts de instrumentação que interferem com `fetch`. A função `api()` usa `XMLHttpRequest` diretamente com headers de autenticação manuais (`Authorization: Bearer <token>` + `apikey`). Não trocar para `fetch` sem testar em produção.

### Por que `APP_INICIADO` flag?

O evento `TOKEN_REFRESHED` do Supabase Auth dispara ~a cada hora e era tratado como `SIGNED_IN`, re-rodando `iniciar()` inteiro. Isso causava: refetch de todos os dados, múltiplos `setInterval` empilhados, e o watchdog disparando um `confirm()` nativo enquanto o usuário estava idle. Resolvido com `APP_INICIADO`.

### Por que audit_log.company_id sem FK?

Requisito LGPD: o log de auditoria deve sobreviver à exclusão da empresa. Com FK normal (`ON DELETE SET NULL` já está no código), o `DELETE` em `companies` disparava violação de constraint. Removida a FK; o `company_id` é apenas um atalho de filtro, não integridade referencial.

### Por que snapshot jsonb imutável nas proposals?

Proposta comercial é documento legal. Se o preço ou nome do produto mudar no catálogo depois, a proposta original deve preservar os valores exatos do momento da geração. Nunca fazer JOIN para buscar dados atuais de uma proposta antiga.

### Por que `toastUndo` em vez de `confirm()` nativo?

`confirm()` bloqueia o thread JS, é feio, e não funciona em iframes (Vercel preview). `toastUndo` é otimista: esconde o item imediatamente na UI, executa o DELETE no DB após 7s se não houver clique em "Desfazer".

---

## 12. Padrões de commit

Formato usado na sessão anterior:
```
Sprint X.Y: descrição curta do que foi adicionado

Feature 1:
- detalhe
- detalhe

Feature 2:
- detalhe

Técnico:
- detalhe interno
```

---

## 13. Problemas conhecidos e soluções

| Problema | Causa | Solução aplicada |
|---|---|---|
| Alert "login demorando" ao ficar idle | TOKEN_REFRESHED tratado como SIGNED_IN | Flag APP_INICIADO + ignorar TOKEN_REFRESHED |
| Modal proposta ficava atrás do perfil | Z-index 200 < pfpage 280 | gcm agora tem z-index 290 |
| Pedido imprimia junto com proposta | cot-page continuava com .op atrás | Ao abrir prod-page, remove .op da cot-page |
| audit_log bloqueava DELETE de empresa | FK constraint com ON DELETE RESTRICT implícito | ALTER TABLE DROP CONSTRAINT audit_log_company_id_fkey |
| TOKEN_REFRESHED empilhava setInterval | setInterval sem clearInterval prévio | window._bellTimer com clear antes de recriar |
| Migration falhou "invalid syntax for timestamptz" | coluna já era timestamptz, USING tentava concatenar de novo | DO $$ com check de data_type antes do ALTER |

---

## 14. Arquivos do projeto

```
crm-adiblock/
├── index.html          ← arquivo principal (5500+ linhas, tudo aqui)
├── supabase_setup.sql  ← schema completo + migrations (idempotente)
├── vercel.json         ← headers Cache-Control: no-store
├── logo.png            ← logo Adiblock (usada nas propostas)
├── app.js              ← ÓRFÃO (não referenciado, pode ignorar)
├── style.css           ← ÓRFÃO (não referenciado, pode ignorar)
└── .claude/
    ├── settings.json
    ├── thinking-logs/  ← blocos de thinking exportados da sessão anterior
    └── memory/         ← memórias persistentes do Claude
```

---

## 15. Próximos itens em aberto (não implementados)

Da lista de sprints sugeridos, ainda faltam:

- **U1**: Documentar atalhos no cheat-sheet (botão ⌨ já existe)
- **U4**: Confirmação inline (toggles sem modal)
- **U5**: Mobile-friendly real (testar em celular, ajustar tabelas)
- **U7**: Avatar/iniciais coloridas consistente em todas as telas
- **O1**: Quebrar index.html em `<script src>` modulares (cache por arquivo)
- **O2**: Drag-and-drop no Kanban do Pipeline
- **O3**: Timeline unificada no perfil (interações + alterações + propostas)
- **O4**: Anexos via Supabase Storage (PDF, foto da obra)
- **Pedido Comercial**: documento com nº OC do cliente, transportadora (distinto de Proposta e Pedido de Produção)
