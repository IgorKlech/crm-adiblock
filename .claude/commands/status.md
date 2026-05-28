# /status

Mostra um resumo rápido do estado atual do projeto CRM Adiblock.
Use no início de cada sessão nova para retomar o contexto sem precisar ler tudo.

## Instruções

Execute os seguintes comandos e organize a saída no formato abaixo:

1. `git log --oneline -10` — últimos 10 commits
2. `git status` — mudanças não commitadas
3. Leia o `CLAUDE.md` seção 15 (Próximos itens em aberto)
4. Leia o `CLAUDE.md` seção 10 (SQL de migração pendente)

## Formato de saída

```
## Estado do CRM Adiblock — [data de hoje]

### Últimos commits
[lista dos últimos 5 commits com hash curto e mensagem]

### Mudanças locais não commitadas
[arquivos modificados — ou "Nenhuma" se limpo]

### Próximos itens em aberto
[lista dos itens da seção 15 do CLAUDE.md]

### SQL pendente (rodar no Supabase)
[migrações que ainda podem não ter sido aplicadas]

### Deploy
- Repositório: https://github.com/IgorKlech/crm-adiblock
- Produção: https://crm-adiblock.vercel.app/
- Último commit no ar: [hash do último commit]
```

## Após mostrar o status

Pergunte: **"Por onde quer começar hoje?"** e sugira 1-2 itens da lista de pendentes baseado no que parece mais prioritário.
