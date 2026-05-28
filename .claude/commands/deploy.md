# /deploy

Faz commit + push das mudanças do CRM Adiblock no formato padrão do projeto.

## Instruções

1. Rode `git diff --stat` e `git status` para ver o que mudou
2. Pergunte ao usuário: **"Qual foi a mudança principal? (ex: 'Sprint 6.7: descrição')"** — a não ser que $ARGUMENTS já tenha a mensagem
3. Monte o commit seguindo o formato padrão abaixo
4. Execute: `git add -- index.html supabase_setup.sql CLAUDE.md` (só adiciona arquivos relevantes do projeto — nunca `git add -A`)
5. Faça o commit e push para `origin main`
6. Informe o hash do commit e lembre o usuário de aguardar ~1 min para o deploy do Vercel + usar Ctrl+Shift+R

## Formato de commit

```
Sprint X.Y: título curto (imperativo, PT-BR)

Funcionalidade A:
- detalhe específico
- detalhe específico

Funcionalidade B:
- detalhe específico

Técnico:
- mudanças internas relevantes (RLS, triggers, CSS, etc.)
```

## Regras
- Nunca usar `--no-verify`
- Nunca fazer amend de commit já existente — sempre novo commit
- Se houver mudança no `supabase_setup.sql`, lembrar o usuário de rodar o SQL no Supabase
- O arquivo `app.js` e `style.css` são ÓRFÃOS — não os incluir no commit
