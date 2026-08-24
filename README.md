# CRM Adiblock

A custom CRM built to manage the sales process at Adiblock, a company I work for.
It connects the sales team's activity to the client companies they handle.

**Live:** <https://crm-adiblock.vercel.app/>

## What it does

- **Agenda** — links each salesperson's actions to their client companies
- **Proposals pipeline** — tracks proposals through their stages: in progress, converted to order, shipped, cancelled
- **Radar** — flags client companies with no recent interaction, so nobody is forgotten
- **Dashboard** — overview of the operation: conversion funnel, alerts and best-selling products

It also produces **four printable documents**, which must never be mixed on the
same print job:

| Document | For whom | Shows prices? |
|---|---|---|
| **Commercial Proposal** | the client | yes — prices, tax, total |
| **Production Order** | the factory | **no** — product, packaging, quantity, weight |
| **Commercial Order** | the client | yes — confirms the closed deal, carries the client's PO number |
| **Weekly Report** | internal | — |

They are distinct stages, not versions of the same paper: the proposal offers,
the production order instructs the factory, and the commercial order formally
confirms what was agreed.

## Why it exists

Sales activity was scattered and there was no clear view of which proposals were
moving forward or which clients had gone quiet. The CRM centralises that.

## Access control

- User login required, with optional two-factor authentication (TOTP)
- Three roles: `admin` (full access, including the price catalogue and deletion),
  `vendedor` (runs their own funnel — the default), and `leitor` (read only)

Permissions are enforced **in the database**, through row-level security. What
the interface hides is convenience; anyone calling the functions from the browser
console would still hit the policy.

---

## Running locally

There is no build step, no bundler, no `package.json`, nothing to install. It is
a static site — just serve the folder:

```bash
python -m http.server 3000 --bind 127.0.0.1
# open http://127.0.0.1:3000
```

Any static server works. Opening `index.html` through `file://` does **not** —
Supabase needs an HTTP origin.

The app points at the **production** Supabase project (the `anon` key sits in
`js/config.js` and is public by design — row-level security protects the data,
not the key). So anything you change while running locally changes the real
database.

## Architecture, and what isn't up for negotiation

| Constraint | Why |
|---|---|
| **Vanilla JS, no framework** | a deliberate choice — no React, Vue or Svelte |
| **No build step** | Vercel publishes the files as they are |
| **No backend of our own** | all server-side logic is row-level security plus PostgreSQL triggers |
| **`supabase-js` served locally** | it lives in `js/vendor/`. It used to come from a CDN, and whenever that CDN was blocked the whole app went to a black screen |

Splitting `index.html` into several `<script src>` files is encouraged. What is
off the table is introducing a bundler or a framework.

### Script load order

There is no `type="module"`: **everything shares the global scope**. Each file
depends on the ones before it, so the order in `index.html` is part of the
contract:

```text
vendor/supabase-js → config.js → api.js → format.js → documentos.js
  → propostas.js → perfil.js → anexos.js → catalogo.js → agenda.js
  → inline <script>
```

A new module goes **after** whatever it consumes and **before** the inline block.

> Code that runs at module load time — a top-level `addEventListener`, say — uses
> `?.` on `getElementById`. Without it, one wrong id throws and **prevents every
> function below it from being defined**. A whole screen disappears because of a
> single line.

## Project structure

```text
index.html          markup + the JS that is not a module yet (~3,900 lines)
css/app.css         all the CSS
js/
  config.js         keys, Supabase client, load guard
  api.js            api(), apiDelete(), getToken()
  format.js         date, time and currency formatting
  documentos.js     the three printable documents
  propostas.js      proposals tab, order lifecycle, revision editor
  perfil.js         company page and its five tabs
  anexos.js         order attachments (Supabase Storage)
  catalogo.js       product and price catalogue (admin only)
  agenda.js         tasks, Today/Agenda screen, .ics export
  vendor/           supabase-js 2.39.3
migrations/         schema changes, dated (YYYY-MM-DD-*.sql)
docs/               team guides, restore instructions, database diagnostics
supabase_setup.sql  full reference schema
.github/workflows/  automated daily backup
```

Modules add up to roughly 2,900 lines; the inline block still holds about 3,900.
The split is incremental and currently **paused on purpose**: what remains are
blocks that yield little and cost a full round of manual testing, and the two
largest ones sit on the login path.

## Database

PostgreSQL on Supabase, `public` schema. The core tables:

```text
companies · contacts · opportunities · opportunity_products · interactions
proposals · proposal_revisions · tasks · products · attachments
profiles · organizations · audit_log · lgpd_requests
```

Three ideas explain most of the design decisions.

**The snapshot is immutable.** `proposals.snapshot` is a `jsonb` blob holding
everything that was agreed that day. A proposal is a legal document: if a price
changes in the catalogue later, the old proposal must still show the figure it
was issued with. **Never join to fetch current data for an old proposal.**

**Editing an order versions it, it does not overwrite.** When a revision is
saved, the old snapshot is **archived first** into `proposal_revisions`, and only
then is the new one written. In that order, a failure halfway through leaves one
spare archived revision — harmless. In the reverse order, the same failure would
destroy the original forever. `proposal_revisions` accepts only `SELECT` and
`INSERT` — not even an admin can delete from it.

**Multi-tenant.** Every table carries an `org_id`, filled in by a trigger, and
row-level security filters by organisation. The system is being prepared to serve
more than one company, so **new logic must not assume a single company** or
hard-code Adiblock's own data into an `if` or a constant — that is content, and
it belongs in a table or a config.

## Backups — read this before touching the database

> **The Supabase plan is Free and has no restorable native backup.**

The safety net has three layers:

1. **Automated daily backup** — GitHub Actions (`.github/workflows/backup.yml`) at 03:00 BRT, exporting every table as JSON to the `backups` branch
2. **A "Download Backup" button** in the Dashboard — manual, on demand
3. **`audit_log`** — changes only, partial, a last resort

Restoring: **[`docs/RESTORE.md`](docs/RESTORE.md)**.

Two traps that have already cost us:

**A backup must bring the whole table.** PostgREST truncates the response at a
row ceiling and still returns **200 OK** — a `select=*` without pagination
downloads a file that looks complete and isn't, and you only find out on the day
you need it. Both layers paginate. The `_meta.totais` block in the JSON lists the
row count of every table: it is the only way to spot a truncated file without
opening it.

**`audit_log` has a blind spot.** The trigger ignores `updated_at`,
`estagio_changed_at` and `closed_at`; when the resulting diff is empty it returns
**before the INSERT** and writes nothing at all. An UPDATE touching only those
columns is invisible in the audit trail. A migration of that kind has to build
its own safety net.

## Migrations

- **Never run the whole `supabase_setup.sql` against production.** It is a schema
  reference. On 2026-06-01 someone ran the entire file and wiped every proposal.
- Each schema change goes into a **new file** under `migrations/`, dated:
  `YYYY-MM-DD-description.sql`.
- **An applied migration is immutable history.** To correct something, write
  another one.
- Run small, specific blocks in the Supabase SQL editor, with a backup taken
  first.

> The Supabase SQL editor only displays the result of the **last** statement. A
> migration with separate "before" and "after" checks hides the first one — fold
> both into a single result.

## Deploy

Push to `main` and Vercel publishes automatically. There is no build stage.

> **A push is not a deploy.** An accepted `git push` only proves GitHub received
> it. Vercel always builds the commit at the tip; if that build fails, production
> freezes at the last good deploy and *every* commit since then is left out.
> After shipping something visible, confirm it by fetching a string from
> production that exists only in the new version:
>
> ```bash
> curl -s https://crm-adiblock.vercel.app/css/app.css | grep <marker>
> ```

## Conventions

**Data access always goes through `api()`** — never call the Supabase endpoint
directly. It uses `XMLHttpRequest` rather than `fetch`, because Vercel injects
instrumentation scripts that interfere with `fetch`.

```js
api('GET',   'companies',    'select=*&order=razao_social.asc')
api('POST',  'opportunities', null, { titulo: '...' })
api('PATCH', 'opportunities', `id=eq.${id}`, { estagio: 'ganha' })
apiDelete('contacts', `id=eq.${id}`)          // DELETE has its own function
```

**CSS values come from `:root` variables** — colour, radius, shadow, spacing and
font size. No loose values.

**Media queries do not add specificity.** On a tie, whichever rule comes **later**
in the file wins, so the responsive blocks live at the **end** of `app.css`. A
mobile rule written before the base rule it is meant to override is silently
annulled — no error, no warning.

**Stacking (`z-index`)** follows two rules: a modal sits above the surface that
opened it, and a global responder (confirmation dialog, toast) never competes for
a layer with whatever invoked it — which is why those live in the 900+ band.

## Documentation

The documents below are in Portuguese — they are written for the team that uses
the system day to day.

| File | Audience |
|---|---|
| **[CLAUDE.md](CLAUDE.md)** | deep project context: technical decisions, history, pitfalls. **Read it before implementing anything.** |
| [docs/rotina.html](docs/rotina.html) | the salesperson's routine in four moments of the day — what you send to someone who just joined |
| [docs/GUIA-VENDEDOR.md](docs/GUIA-VENDEDOR.md) | long-form reference, 12 sections |
| [docs/RESTORE.md](docs/RESTORE.md) | how to restore a backup |
| [docs/MULTI-TENANT.md](docs/MULTI-TENANT.md) | design of the multi-tenant migration |
| [docs/diagnostico-banco.sql](docs/diagnostico-banco.sql) | six read-only blocks for checking the database |

## Status

In production, used daily.
