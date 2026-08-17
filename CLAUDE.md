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

   > ⚠ **Backup tem que trazer a tabela INTEIRA.** O PostgREST corta a resposta
   > num teto de linhas e devolve **200 OK** — um `select=*` sem paginação baixa
   > um arquivo que parece completo e não é. Isso só se descobre no dia em que o
   > backup for preciso. As duas camadas paginam:
   > o workflow (`backup.yml`) via cabeçalho `Range`, e o botão do app via
   > `apiTudo()`, que busca em páginas de 1000 até a última vir curta.
   > `order=id.asc` não é enfeite: sem ordem estável, paginar por offset pula e
   > repete linha. O `_meta.totais` do JSON lista a contagem de **todas** as
   > tabelas — é o único jeito de perceber um arquivo truncado sem abri-lo.

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
- Stack: `index.html` (em migração para módulos `<script src>`) + Supabase (`supabase-js` servido localmente de `js/vendor/`) + Vercel estático

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
| **Supabase como arquivo estático local** | `@supabase/supabase-js@2.39.3` servido de `js/vendor/` (mesma origem do Vercel). Era importado do jsDelivr, mas quando o CDN caía/era bloqueado o app inteiro ficava em tela preta (script bloqueante). Agora o local é a fonte primária e o jsDelivr é só fallback. **Não voltar a depender só do CDN.** |
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
proposals           — propostas comerciais (snapshot jsonb da revisão vigente)
proposal_revisions  — revisões anteriores de um pedido (imutável: só SELECT/INSERT)
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
- `proposals.status` — `em_andamento | pedido | cancelada | expedido` (Sprint 6.5/6.8).
- `proposals.revisao` — contador de revisões (1 = original). Ver seção 11.
- `proposals.oc_numero` — nº da ordem de compra **no sistema do cliente**. `text`,
  não `int`: vem com zeros à esquerda, letras e barras conforme o ERP dele.
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

### Escala tipográfica (2026-08-14) — não escrever `font-size` em px

Eram **18** tamanhos de fonte, incluindo `10.5`, `11.5` e `12.5px`. Nada assentava
numa grade e elementos vizinhos tinham tamanhos diferentes sem motivo — é isso que
faz uma interface parecer "não clean", mesmo quando as cores estão certas.

```css
--fs-2xs:10px   /* badge uppercase minúsculo */
--fs-xs:11px    /* label, meta densa */
--fs-sm:12px    /* secundário */
--fs-md:13px    /* corpo de tabela e card */
--fs-base:14px  /* corpo */
--fs-lg:16px    /* título de card, h3 de modal */
--fs-xl:20px    /* título de página, número destacado */
--fs-2xl:28px   /* número-herói do dashboard */
```

> **A escala vale para TEXTO. Glifo não é texto.** Avatar com iniciais, emoji de
> empty state, ✕ de fechar e ícone de botão têm tamanho por outro motivo (caber
> num círculo, ser alvo de toque). Esses continuam em px, de propósito — passar a
> régua neles é o que quebra layout em varredura mecânica. Os que estão fora:
> `.es-ico`, `.eq-av`, `.pf-av`, `.ua`, `.drill-av`, `.rel-logo`, `.prod-del`,
> `.mx`, `.coi`, `.sic`, `.bell-ic`, `.theme-toggle`, `.kb-move-btn`.

### Identidade visual — alinhada ao site adiblock.online (2026-08-14)

O CRM e o site institucional usam **o mesmo design system**. A fonte de verdade
é `../site adiblock/css/styles.css`; ao mexer em cor, fonte ou forma aqui,
confira lá primeiro. Os tokens `--blue-*` e `--ac*` carregam os nomes do site
de propósito, para a comparação ser direta.

| | Valor | Origem |
|---|---|---|
| Fonte | **Manrope** 500/600/700/800, self-hosted em `assets/fonts/` | mesmos `.woff2` do site |
| Azul | `--blue-950` a `--blue-50`; navbar e `--p` no `#0f2c54`/`#143a6e` | escala do site |
| Acento | `--ac: #ffd200` (amarelo da marca) | site |
| Forma | botão **pílula**, card `--rl` 20px | site usa 22px no card |
| Sombra | tingida de azul `rgba(9,30,66,…)` | site |
| Movimento | `--ease: cubic-bezier(.22,1,.36,1)`, lift de 2px no `:hover` | site |

> ⚠ **O que NÃO se copia do site: os tamanhos.** Lá o corpo é 17px com
> `line-height` 1.65 — correto para uma página lida uma vez, errado para uma
> tabela que o vendedor encara o dia inteiro (mostraria metade das linhas).
> A **identidade** é compartilhada; a **densidade** é de aplicação.

> **Amarelo é para a ação principal** (classe `.bac`). Se tudo virar amarelo,
> nada é destaque — é assim que o site usa.

**Tema escuro é derivado, não copiado**: o site não tem. O fundo é `--blue-950`
e a superfície `--blue-900`, para o escuro continuar sendo a mesma marca.

### Logos (`assets/img/`)

| Arquivo | Onde | Por quê |
|---|---|---|
| `logo-adiblock.svg` | login (tema claro), proposta, pedido de produção, pedido comercial, capa do relatório | versão escura, sobre fundo branco |
| `logo-adiblock-light.svg` | login (tema escuro) | versão reversa |
| `logo-adiblock-compact-light.svg` | navbar | **sem a tagline** |
| `favicon.svg` | aba do navegador | vetor, escala em qualquer densidade |

A variante **compacta** existe porque na navbar sobram ~38px de altura: na logo
completa, a tagline "ADITIVOS PARA CONCRETO" (11.5px no SVG) cairia para ~4px e
viraria mancha. Nos documentos impressos a logo completa é usada a **46px** — a
mesma altura que o site usa na própria navbar, o piso onde a tagline ainda lê.

No login a logo troca com o tema (`.logo-claro` / `.logo-escuro`): o cartão é
branco no claro e azul-escuro no escuro, então uma versão só sumiria numa delas.

### Breakpoints (2026-08-17)

**Aparelhos que a equipe usa de verdade** (confirmado com o Igor em 17/08/2026):
**celular Android** e **iPad/tablet** — não há iPhone em uso. As duas larguras
que mandam, portanto:

| Aparelho | Largura lógica | Por que importa |
|---|---|---|
| Galaxy S23 (e Android típico) | **360px** | é o piso real; 390px é iPhone e leva a cálculo errado |
| iPad Air / Pro 11" | **820–834px** | caem *acima* de 768, então recebem layout de mesa |

> iPad é Safari: as manhas de iOS continuam valendo (input < 16px dá zoom
> automático) mesmo sem iPhone na equipe.


Eram 7 valores sem sistema (1280, 1100, 768, 680, 640, 560, 480) e a faixa de
**769 a 1024px não tinha dono**: iPad Air (820) e iPad Pro 11" (834) caíam no
layout de mesa, com navbar de linha única cheia e alvos de toque de ~31px.

A **navbar** tem escada propria, porque com 7 abas e a identidade nova (Manrope
mais larga, aba em pílula, botão peso 700) ela passou a precisar de **~1667px** —
só cabia inteira em 1920px+. Em cada degrau sai o item menos essencial:
`1600` Controle Comercial · `1500` "ao vivo" · `1440` nome/papel · `1380` status ·
`1280` atalhos · `1200` rótulo curto nas abas · `1100` Busca só ícone.

> A guarda **estrutural** é o `overflow:hidden` na `.nbl` com `ellipsis` no `.bn2`:
> a `.nbl` encolhe, mas **texto não encolhe com a caixa** — sem isso o "Controle
> Comercial" transbordava e pintava por cima das abas. A escada evita chegar lá;
> o `overflow` garante que, se chegar, não vira sobreposição.

| Faixa | Quem | O que muda |
|---|---|---|
| ≤1024 | **tablet** e tudo abaixo | toque de 44px, rótulo curto nas abas, documentos sem largura fixa |
| ≤768 | celular | Empresas vira cards, tabela de documento rola, navbar em 2 linhas |
| ≤480 | celular estreito | modais viram bottom-sheet |

Os três blocos ficam **no fim do `app.css`**, nessa ordem: são os últimos a
casar, e 1024 → 768 → 480 garante que o mais estreito vence. Regra que serve a
tablet **e** celular mora no bloco de 1024; só o que difere é repetido no de 768.

> **Tablet é touch.** Duas coisas seguem daí e são fáceis de esquecer: alvo de
> 44px vale acima de 768 também, e **arrastar não funciona** — o botão "⇄ Mover"
> do Kanban é o único caminho, então ele precisa ser clicável no tablet, não só
> visível.

> `isMobile()` no JS (`max-width:768px`) decide **cards vs. tabela** em Empresas.
> Tablet fica com a tabela de propósito: cabem ~12 empresas onde caberiam 4.
> Por isso o `.tw` tem `overflow-x:auto` **na base**, não dentro de um breakpoint.

### Rótulos em caixa alta e campos de formulário

**Tracking sai de `--ls-label` (.1em).** Eram quatro valores para o mesmo papel
(`.04em`, `.05em`, `.06em`, `0.7px`) — é o tracking que faz caixa alta pequena
parecer deliberada em vez de só pequena. O site usa `.14em`, mas lá o rótulo tem
13px numa página arejada; aqui tem 11px numa tela densa.

> O traço da `.eyebrow` do site **não** foi trazido. Os títulos de seção dos
> documentos já têm borda inferior, que cumpre o mesmo papel de separar — o traço
> seria decoração competindo com ela.

**Campo de formulário segue o padrão do site**: levemente **recuado** em repouso
(fundo `--bg`, mais suave que a superfície do card) e **branco com anel da marca**
(`--ring`, amarelo) no foco. Antes era branco sempre e a única pista de foco era
a borda fina mudar de cor — pouco num formulário de 12 campos. Funciona igual no
tema escuro, onde `--bg` é *mais escuro* que `--sur`: a lógica se inverte junto.

### Raio e sombra

Raio sai sempre de `--rs` (6px) / `--r` (10px) / `--rl` (14px) / `99px` (pílula).
Nada de valor avulso — havia 8 (`3,4,5,6,7,8,12px`).

**Sombra segue uma regra só:** card **chapado** na página usa borda **ou** sombra,
nunca as duas — as duas juntas pesam. Elemento **flutuante** (modal, popover) usa
as duas, porque precisa descolar do fundo. Cards clicáveis ganham a sombra no
`:hover`, o que torna o hover um estado de verdade em vez de um aumento sutil.

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
302  — #edp-hist-m (histórico de revisões — abre sobre o editor)
300  — #co (confirm), drill-m (dashboard drill), #edp-m (editar pedido)
297  — #pcom-page (pedido comercial)
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

### Recuperação de senha (Sprint 9.3 / B-01)

```
link do email (#type=recovery no hash)
     ↓
MODO_RECUPERACAO = true   ← lido do hash de forma SÍNCRONA, no topo do script
     ↓
boot NÃO abre o app  +  onAuthStateChange desvia pra showNovaSenha()
     ↓
updateUser({password}) → MODO_RECUPERACAO = false → replaceState → showApp()
```

**`MODO_RECUPERACAO`** é `let`, não `const`: precisa ser desligada assim que a
senha for trocada, senão o `TOKEN_REFRESHED` seguinte joga o usuário de volta na
tela de nova senha. A leitura tem que ser síncrona porque o supabase-js consome
e **apaga** o hash assim que inicializa — quem ler depois não acha nada.

> ⚠ **Depende de configuração no Supabase, não só do código.** Em
> *Authentication → URL Configuration*, a lista de **Redirect URLs** precisa
> conter `https://crm-adiblock.vercel.app/` (e `http://localhost:3000/` para
> testes locais). O `resetPasswordForEmail` manda `redirectTo: origin + pathname`;
> URL fora da lista é recusada e o link do email não funciona. O template
> *Reset Password* tem que usar `{{ .ConfirmationURL }}`.

---

## 8. Documentos imprimíveis

Quatro documentos distintos — **nunca misturar ao imprimir**:

| Documento | Página | Z-index | Para quem | Tem valores? |
|---|---|---|---|---|
| Proposta Comercial | `#cot-page` | 295 | cliente | Sim (preços, IPI, total) |
| Pedido de Produção | `#prod-page` | 296 | fábrica | Não — só produto/embalagem/qtd/peso |
| Pedido Comercial | `#pcom-page` | 297 | cliente | Sim — confirma o pedido fechado |
| Relatório Semanal | `#rel-page` | 280 | interno | — |

Os três primeiros são etapas distintas, não versões do mesmo papel: a **Proposta**
oferta, o **Pedido de Produção** instrui a fábrica, e o **Pedido Comercial**
confirma formalmente o que foi fechado — carregando o **nº da OC do cliente**,
que é o número pelo qual *ele* cobra, confere e paga. O botão só aparece quando
o status já é `pedido` ou `expedido`: confirmar exige algo fechado.

**Regra de print**: ao abrir `#prod-page` ou `#pcom-page`, a `#cot-page` tem `.op`
removido. Ao fechar, restaura. Sem isso o PDF sai com dois documentos colados —
já aconteceu no Sprint 6.4. O `@media print` tem uma regra `body:has(...)` para
cada combinação possível.

**Campos de cumprimento ficam em coluna, não no snapshot**: `oc_numero`,
`entrega_local`, `entrega_previsao`, `transportadora` e `nf_numero` chegam depois
da negociação, às vezes dias depois. O snapshot é o que foi *negociado* e é
imutável — enfiar dado de entrega nele obrigaria a reescrever documento fechado.

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
| 6.7 | Numeração de pedido independente da proposta (`pedido_numero`/`pedido_ano`, `pedido_sequences`) + excluir proposta (admin) | 55eea96 |
| 6.8 | Status `expedido` + modal de expedição (NF + transportadora) | 10c2310 |
| 7.0 | Contrato do projeto atualizado: fim do single-file, visão multi-tenant | 7ce7e19 |
| 7.1 | Ações rápidas na tela Hoje (WhatsApp/Ligar/Registrar) | bd101ce |
| 7.2 | Próximo passo obrigatório + motivo de perda (`perda_motivo`) + badge de órfãs | b5ac3f1 |
| 7.3 | Mobile real: cards em listas, tabs com label curto, bottom-sheets | f415f1f |
| 7.4 | Painel de adoção por vendedor (admin) na aba Equipe | d5a6013 |
| 7.5 | Backup diário automático (GitHub Actions) + `docs/RESTORE.md` | f65bbc6 |
| 8.1a/b | Modularização: extrai `css/app.css` e `js/format.js` (EM ANDAMENTO) | d126950 + 529c7c9 |
| 8.2 | Radar de Reativação (clientes dormentes priorizados, atalho R) | 86a0064 |
| 9.0 | Design doc multi-tenant (`docs/MULTI-TENANT.md`) — só documento | 8fc80dd |
| 9.1 | Multi-tenant etapas D/F: NOT NULL + índices compostos + numeração por org, policies RLS por org | 404eb33 + 7b83512 |
| 9.3 | Auditoria de UX: logo/favicon, recuperação de senha, cores do tema escuro, mover estágio sem arrastar, navbar mobile | 0e0d841 |

---

### Em andamento / não concluídos

- **Sprint 8.1 (modularização) — em andamento.** Já extraídos: `css/app.css`,
  `js/format.js`, `js/config.js`, `js/api.js`. Os órfãos `app.js`/`style.css`
  foram apagados em 17/08/2026. Faltam `state.js`, `js/views/*`, `modals.js` e
  `main.js` — o `<script>` inline ainda tem **5.781 linhas**, e é aí que está o
  ganho de verdade; config e api somaram só ~100 linhas.
  As views são o pedaço difícil: dependem de tudo e não dá pra verificar sem
  **abrir o app entre cada extração**. Análise estática pega sintaxe e ordem de
  carga, não pega "a tela não renderiza mais".

> **O que checar depois de extrair um módulo** (a análise estática cobre isto,
> e só isto): sintaxe de cada arquivo; **colisão de declaração no escopo global**
> — só coluna zero conta, `const` dentro de função é local e repetir é normal;
> toda função movida ainda tem chamador (`onclick` do HTML, inline ou outro
> módulo); e **quais linhas do módulo executam no carregamento** — essas são as
> perigosas, porque um erro ali impede as funções abaixo de existirem. Por isso
> `document.getElementById(...)` de nível superior em módulo usa `?.`.
- **Sprint 9.1 (multi-tenant) saiu do papel**: as etapas D e F já foram aplicadas
  (NOT NULL + índices compostos + numeração por org; policies RLS por org, com
  ROLLBACK). O design segue em [docs/MULTI-TENANT.md](docs/MULTI-TENANT.md).

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

### "Produtos Vendidos" conta PEDIDO, não oportunidade (2026-08-17)

O painel do Dashboard somava `opportunity_products` — os produtos de **toda**
oportunidade, em qualquer estágio. Lead que nunca fechou entrava como venda.

E errava no sentido oposto também: `opportunity_products` guarda a lista de
produtos **uma vez por oportunidade**, mas o banco tem **176 pedidos fechados
para 110 oportunidades ganhas** — muita recompra do mesmo cliente na mesma
oportunidade. Essas ~66 vendas a mais eram colapsadas numa só.

A fonte é `proposals` com status `pedido`/`expedido`, lendo o **snapshot**:

- captura recompra (cada pedido conta uma vez);
- usa o valor **realmente negociado**, já com as revisões — `opportunity_products`
  é a estimativa da abertura;
- pega os 8 pedidos cuja oportunidade não foi marcada como ganha.

Custo aceito: perde 3 oportunidades ganhas sem pedido gerado (2,7%) — e essas
não têm venda confirmada mesmo.

> **O filtro de período usa `status_changed_at` da proposta**, não o `created_at`
> da empresa. Antes, "últimos 30 dias" queria dizer *empresas cadastradas nos
> últimos 30 dias* — mesmo defeito do filtro da aba Empresas.

> **Valor é qtd × preço, sem IPI** (imposto não é receita de produto), e o
> painel declara isso no título. Número de faturamento tem que dizer de onde vem.

### Por que snapshot jsonb imutável nas proposals?

Proposta comercial é documento legal. Se o preço ou nome do produto mudar no catálogo depois, a proposta original deve preservar os valores exatos do momento da geração. Nunca fazer JOIN para buscar dados atuais de uma proposta antiga.

### Como editar um pedido sem quebrar a imutabilidade (2026-08-14)

Cliente pedir desconto ao trocar a forma de pagamento, ou pedir pra acrescentar
outro material num pedido já fechado, é rotina. Editar o `snapshot` no lugar
resolveria — e apagaria a prova do que valia antes. O `audit_log` **não** cobre
esse buraco: `snapshot` está na lista de campos que ele ignora.

Então editar **versiona**, não sobrescreve:

```
proposals.snapshot   → sempre a revisão VIGENTE
proposals.revisao    → contador (1 = original)
proposal_revisions   → o passado, uma linha por revisão anterior + motivo + autor
```

Ao salvar: **arquiva primeiro** (`POST proposal_revisions` com o snapshot antigo),
**sobrescreve depois** (`PATCH proposals`). Nessa ordem, um erro no meio deixa
uma revisão arquivada sobrando — inofensivo. Na ordem inversa, o mesmo erro
perderia o snapshot antigo para sempre.

`proposal_revisions` tem policy de `SELECT` e `INSERT` apenas — sem `UPDATE`,
sem `DELETE`, nem para admin. Histórico que pode ser reescrito não é histórico.

Só `em_andamento` e `pedido` aceitam edição. `expedido` fica travado porque a NF
já foi emitida — mudar o pedido depois disso descasa do fiscal.

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

> ⚠ **Push não é deploy.** Um `git push` aceito só garante que o GitHub recebeu.
> A Vercel constrói **sempre o commit do topo** — se esse build falhar, a produção
> congela no último deploy bom e *todos* os commits desde então ficam de fora,
> mesmo os que não têm nada a ver com a falha. Depois de subir mudança visível,
> confirme buscando na produção uma string que **só exista na versão nova**
> (`curl https://crm-adiblock.vercel.app/css/app.css | grep <marcador>`).

> ⚠ **Media query NÃO aumenta especificidade.** No empate, vence quem vem
> **depois** no arquivo. Regra de celular escrita ANTES da regra-base que ela
> deveria sobrescrever é silenciosamente anulada — não há erro, não há aviso, o
> app só se comporta como se a regra não existisse. Em 17/08/2026 três regras do
> Sprint 7.3/9.3 estavam nesse estado, e uma delas (`.cl-cards{display:flex}`)
> deixava a aba Empresas **em branco no celular** desde então. Por isso os blocos
> responsivos ficam no **fim** do `app.css`. Para checar:
> comparar cada regra dentro de `@media` com regras-base de mesmo seletor e
> linha maior.

> ⚠ **Seletor que não casa com nada é pior que seletor ausente** — parece que
> resolveu. Já apareceu duas vezes: `.filtro-clear` (o botão "Limpar filtros" da
> aba Empresas limpava só a busca, deixando período/classificação/vendedor
> ligados) e um `span.lbl` que eu mesmo inventei. Ao escrever CSS ou
> `querySelectorAll` mirando uma classe, confirmar que ela existe no HTML.

> ⚠ **Verificar CSS também, não só JS e HTML.** Um comentário mal fechado no
> `app.css` não gera erro em lugar nenhum: apaga silenciosamente a regra
> seguinte. Em 14/08/2026 isso derrubou a navbar em produção e passou por duas
> rodadas de verificação que só olhavam sintaxe de JS e balanceamento de tags.
> Checar: `/*` e `*/` em número igual, chaves balanceadas, nenhum texto solto
> fora de regra.

| Problema | Causa | Solução aplicada |
|---|---|---|
| Alert "login demorando" ao ficar idle | TOKEN_REFRESHED tratado como SIGNED_IN | Flag APP_INICIADO + ignorar TOKEN_REFRESHED |
| Modal proposta ficava atrás do perfil | Z-index 200 < pfpage 280 | gcm agora tem z-index 290 |
| Pedido imprimia junto com proposta | cot-page continuava com .op atrás | Ao abrir prod-page, remove .op da cot-page |
| audit_log bloqueava DELETE de empresa | FK constraint com ON DELETE RESTRICT implícito | ALTER TABLE DROP CONSTRAINT audit_log_company_id_fkey |
| TOKEN_REFRESHED empilhava setInterval | setInterval sem clearInterval prévio | window._bellTimer com clear antes de recriar |
| Migration falhou "invalid syntax for timestamptz" | coluna já era timestamptz, USING tentava concatenar de novo | DO $$ com check de data_type antes do ALTER |
| Deploy parou de sair sem erro visível no app; produção congelada em um commit antigo | `vercel.json` com uma chave `"//"` de comentário — JSON válido, mas o schema da Vercel só aceita `source`/`headers`/`has`/`missing` em cada regra, e propriedade extra **rejeita o deploy inteiro** | tirar a chave; **JSON não tem comentário** — a explicação vai no CLAUDE.md ou no commit |
| Aba Empresas em branco no celular; barras de ação de Hoje/Propostas vazando pra fora da tela | 3 regras de `@media(max-width:768px)` escritas ANTES das regras-base de mesmo seletor — media query não soma especificidade, então a base posterior vencia. Com o seletor de status visível, a `.nbr` (`flex-shrink:0`) passava de 360px e forçava a **página** a ficar mais larga; com a página larga, nada mais precisava quebrar | mover as 3 pro bloco do fim do arquivo + `min-width:0` e `flex-wrap` na `.nbr`, pra ela nunca empurrar o documento |
| Abas da navbar empilhadas em coluna, vazando sobre a página | comentário CSS fechado cedo demais (`*/` no meio), o parser descartou até a próxima chave e levou junto `#tabs{display:flex}` | frase movida para dentro do comentário — e passou a haver checagem de CSS, não só de JS/HTML |

---

## 14. Arquivos do projeto

```
crm-adiblock/
├── index.html          ← HTML + <script> inline (a maior parte do JS ainda aqui)
├── css/
│   └── app.css         ← todo o CSS (extraído do <style> no Sprint 8.1a)
├── js/
│   ├── config.js       ← chaves, cliente Supabase, guarda de carregamento (8.1c)
│   ├── api.js          ← api(), apiDelete(), getToken() (8.1c)
│   ├── format.js       ← helpers de formatação (8.1b)
│   ├── documentos.js   ← os 3 papéis imprimíveis + PROP_ATUAL (8.1d)
│   └── vendor/         ← supabase-js 2.39.3 (arquivo local, ver seção 2)
├── supabase_setup.sql  ← schema completo (DROP destrutivo COMENTADO — Regra de Ouro)
├── migrations/         ← mudanças de schema datadas (AAAA-MM-DD-*.sql)
│   ├── 2026-06-03-embalagens-reais.sql
│   ├── 2026-08-14-revisao-pedidos.sql
│   ├── 2026-08-14-pedido-comercial.sql
│   └── 2026-08-17-closed-at-retroativo.sql
├── docs/
│   ├── RESTORE.md      ← guia de restauração de backup
│   ├── diagnostico-banco.sql ← 6 blocos SÓ-LEITURA de checagem do banco
│   └── MULTI-TENANT.md ← design da migração multi-tenant (Sprint 9.0)
├── .github/workflows/
│   └── backup.yml      ← backup diário automático (Sprint 7.5)
├── vercel.json         ← headers Cache-Control: no-store
├── assets/
│   ├── fonts/          ← Manrope self-hosted (woff2 500/600/700/800)
│   └── img/            ← logos SVG e favicon (vindos do site adiblock.online)
├── logo.png            ← ÓRFÃO desde 14/08/2026 (substituída pelas SVG).
│                         Mantida a pedido: pode estar em uso FORA do app
│                         (assinatura de e-mail, papel timbrado).
└── .claude/
    ├── settings.json
    ├── commands/       ← skills: /deploy, /sql-pending, /status
    ├── thinking-logs/  ← blocos de thinking exportados
    └── memory/         ← memórias persistentes do Claude
```

> **Ordem de carga** (crítica — tudo compartilha escopo global, sem `type=module`):
> `vendor/supabase-js` → `config.js` → `api.js` → `format.js` → `documentos.js` → `<script>` inline.
> `api.js` usa `SB_URL`/`SB_KEY` de `config.js`; o inline usa `sb`, `api()`,
> `apiDelete()` e `MODO_RECUPERACAO` dos dois. Módulo novo entra **antes** do
> inline e **depois** de quem ele consome. CSS via `<link href="css/app.css">`.
>
> ⚠ **O `throw` da guarda de carregamento agora para só o `config.js`** — antes,
> morando no inline, parava tudo. Se o supabase-js não carregar, os arquivos
> seguintes ainda executam e enchem o console de erro de referência. O que o
> usuário vê não muda: a tela de erro já substituiu o `body`.

---

## 15. Próximos itens em aberto (não implementados)

> **Painel "Clientes sem contato há 7+ dias" foi REMOVIDO em 17/08/2026.** Estava
> desligado desde o Sprint 3 (um `return;` na quinta linha da função) enquanto o
> HTML, o CSS e o ícone de alerta da navbar seguiam no sistema, inertes. O Radar
> de Reativação (Sprint 8.2) faz o mesmo trabalho melhor — prioriza dormentes em
> vez de só listar. Se um dia voltar, precisa ser reescrito sobre `interactions`;
> a versão antiga consultava `call_history`, tabela que não existe mais.


Da lista de sprints sugeridos, ainda faltam:

- **Sprint 8.1 (resto)**: concluir modularização (config/state/api/views/modals/main) e apagar `app.js`/`style.css`
- **U4**: Confirmação inline (toggles sem modal)
- **U7**: Avatar/iniciais coloridas consistente em todas as telas
- **O3**: Timeline unificada no perfil (interações + alterações + propostas + revisões de pedido)
- **O4**: Anexos via Supabase Storage (PDF, foto da obra)
- **Guia do vendedor desatualizado**: `docs/GUIA-VENDEDOR.*` está untracked e não cobre editar pedido (revisões), Pedido Comercial nem recuperação de senha

> Já feitos: U1 (cheat-sheet), U5 (mobile Sprint 7.3), O1 (modularização em
> andamento), **O2** (drag-and-drop do Kanban — já existia em `renderKanban()`;
> a lista dizia o contrário), **Pedido Comercial** (2026-08-14), **Sprint 9.1**
> (etapas D e F aplicadas).
