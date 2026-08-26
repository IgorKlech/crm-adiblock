# Guia do Vendedor — CRM Adiblock

**Para a equipe comercial.** Como usar o CRM no dia a dia, do primeiro contato ao pedido faturado.

- **Acesso:** https://crm-adiblock.vercel.app/
- **Login:** seu e-mail corporativo
- **Perfil:** `vendedor`

> Atualizado em 26/08/2026. Novidades desta versão: **anexar a OC assinada e o
> comprovante ao pedido** (seção 6), **botões de retorno rápido** ao registrar
> interação (seção 4), **tarefas, calendário e exportar para o Google Calendar**
> (seção 2) e **verificação em duas etapas** (seção 10).

---

## 1. O vocabulário do sistema

Tudo no CRM gira em torno de 4 entidades. Entenda-as antes de começar:

| Termo | O que é | Exemplo |
|---|---|---|
| **Empresa** | O cliente B2B (CNPJ) | "Construtora XYZ Ltda" |
| **Contato** | A pessoa dentro da empresa | "João, comprador" |
| **Oportunidade** | Uma negociação de venda em andamento | "Aditivo p/ obra do viaduto" |
| **Proposta** | O documento comercial com preços | "Proposta nº 042/2026" |

> **Regra mental:** uma **empresa** tem vários **contatos** e várias **oportunidades**.
> Uma **oportunidade** gera uma ou mais **propostas**.
> Nunca crie negociação solta — sempre vinculada a uma empresa.

---

## 2. Rotina diária — comece pela aba **Hoje** (atalho `T`)

É a sua tela inicial e o coração do trabalho. Ela responde: **"o que eu preciso fazer agora?"**

O que aparece aqui:
- **Retornos agendados** (callbacks) que vencem hoje — com hora.
- **Tarefas** do dia.
- **Sininho 🔔** com alertas e pendências.

**Duas visões**, no botão no alto da tela:

- **Lista** — o que vence hoje e nos próximos 3 dias.
- **Mês** — o calendário inteiro, para enxergar a semana cheia **antes** de
  prometer visita ao cliente.

A caixa **"Só os meus"** vem marcada. Desmarque para ver a agenda da equipe.

**Tarefa não é retorno.** Retorno está preso a uma oportunidade. **Tarefa é
livre** — *"levar amostra na obra"*, *"cobrar o financeiro"*, *"mandar a ficha
técnica"*. Botão **+ Nova Tarefa**.

**📥 Exportar .ics** baixa seus compromissos num arquivo que o **Google Calendar**
e o **Outlook** importam. Serve para quem vive na agenda do celular: os retornos
passam a aparecer lá, junto do resto do dia.

**Ações rápidas** em cada item:
- 💬 **WhatsApp** — abre a conversa direto.
- 📞 **Ligar**.
- 📝 **Registrar** — lança a interação sem sair da tela.

> ✅ **Disciplina nº 1:** todo dia abre no "Hoje" e zera a lista. Se um retorno
> venceu e você não falou com o cliente, **reagende** — nunca deixe vencido e esquecido.

---

## 3. Empresas e contatos (aba **Empresas**, atalho `C`)

1. **Busque antes de criar** — evite empresa duplicada.
2. Cadastre a empresa e depois adicione os **contatos** (quem decide, quem compra).
3. Abra o **perfil da empresa** para ver tudo num lugar só: contatos,
   oportunidades, histórico e propostas.

O sistema classifica a empresa automaticamente por **tier** (você não define na mão):
- **Lead** → ainda sem compra.
- **Cliente / Conta** → conforme oportunidades ganhas.

---

## 4. Conduzindo a venda — o **Pipeline** (Kanban)

Cada oportunidade caminha por estágios. Sua missão é **mover os cards para frente**.

| Estágio | Significa | Chance ponderada |
|---|---|---|
| **Lead** | Negociação recém-aberta | 10% |
| **Qualificado** | Interesse e fit confirmados | 30% |
| **Proposta enviada** | Proposta na mão do cliente | 60% |
| **Em negociação** | Ajuste de preço/condições | 80% |
| **Ganha** | Cliente fechou | 100% |
| **Perdida** | Não fechou | 0% |

**Como mover um card:**

- **No computador:** arraste o card de uma coluna para a outra.
- **No celular:** arrastar não funciona em tela de toque. Use o botão
  **⇄ Mover** no rodapé do card e escolha o estágio na lista.

Regras que o sistema cobra de você:
- **Próximo passo é obrigatório.** Toda oportunidade ativa precisa do próximo passo
  com data/hora. Sem ele, vira **órfã** e ganha um **badge de alerta**.
- **Ao perder, informe o motivo.** Marcar como perdida exige o **motivo da perda** —
  isso alimenta as análises da equipe.

> ✅ **Disciplina nº 2:** card sem próximo passo = negociação esquecida.
> Trate o badge de órfã como prioridade.

**Registrando interações:** toda ligação, visita ou e-mail relevante vira uma
**interação** na oportunidade. É o histórico que protege você e dá memória ao
negócio. Ao registrar, já agende o **próximo retorno** (com hora).

**Os botões de retorno rápido.** No celular, escolher data e hora à mão custa 4
a 6 toques — o Android abre um seletor para a data e outro para a hora. Por isso
a tela de interação tem uma linha de botões:

`Amanhã` · `3 dias` · `1 semana` · `15 dias` · `1 mês`

Um toque preenche a data às **09:00**. O campo de data continua logo abaixo, para
quando você precisar de hora exata.

> **Eles pulam o fim de semana.** Retorno marcado para sábado não é retorno — é
> algo que aparece atrasado na segunda. Consequência: numa sexta-feira, "Amanhã"
> e "3 dias" caem na mesma segunda. A data escolhida aparece no campo, então não
> tem como se enganar.

---

## 5. Gerando a **Proposta Comercial** (aba **Propostas**, atalho `P`)

A proposta é um **documento legal**. Pontos críticos:

- Preços, produtos e valores ficam **congelados** no momento da geração. Se o
  catálogo mudar depois, a proposta antiga **mantém os valores originais** —
  isso é proteção, não erro. Para mudar o que foi combinado existe um caminho
  próprio, que **guarda a versão anterior** (seção 7).
- A numeração é **automática e sequencial por ano** — não invente número.
- Estados da proposta:
  - `em andamento` → enviada, em negociação.
  - `pedido` → cliente fechou.
  - `expedido` → saiu com NF e transportadora.
  - `cancelada` → caiu.

> ⚠️ **Não confunda os documentos imprimíveis.** São etapas diferentes, não
> versões do mesmo papel:
>
> | Documento | Para quem | Serve para | Tem preço? |
> |---|---|---|---|
> | **Proposta Comercial** | Cliente | **Ofertar** | **Sim** |
> | **Pedido de Produção** | Fábrica | **Instruir** a produção | **Não** (só produto/qtd/peso) |
> | **Pedido Comercial** | Cliente | **Confirmar** o pedido fechado | **Sim** |
> | **Relatório Semanal** | Interno | Acompanhar | — |
>
> O **Pedido de Produção** vai para a fábrica e **nunca mostra valores**.

---

## 6. Quando o cliente fecha — virando **Pedido**

1. Mude a proposta para o status **`pedido`**. O sistema atribui um **número de
   pedido próprio**, diferente do número da proposta.
2. Gere o **📋 Pedido de Produção** para a fábrica (sem preços).
3. Gere o **📄 Pedido Comercial** para o cliente — é a confirmação formal.
4. Conforme avança, registre **`expedido`** com **NF + transportadora**.

A oportunidade correspondente vai para **Ganha** — e aí conta para o seu
ranking e para o tier do cliente.

### O nº da OC do cliente

Ao gerar o Pedido Comercial o sistema pede o **número da ordem de compra do
cliente** — o número que **ele** gerou no sistema **dele**.

**Por que isso importa:** é por esse número que o cliente cobra, confere e paga.
Quando ele liga dizendo *"estou falando do pedido 4500123789"*, esse é o número
que ele tem na mão — o nosso ele não sabe de cor.

Com a OC preenchida, ela aparece no card da aba Propostas e **você acha o pedido
pela busca digitando o número do cliente** (`Ctrl+K`).

> ✅ **Disciplina nº 3:** pediu a OC ao cliente, lançou na hora. Depois ninguém
> lembra, e a cobrança trava.

Também são registrados aqui o **local de entrega** (já vem preenchido com a obra
da oportunidade, mas você pode trocar), a **transportadora** e a **previsão de
entrega**.

### Anexos do pedido — 📎

A **OC assinada** e o **comprovante de pagamento** ficam junto do pedido, e não
na caixa de e-mail de quem recebeu. Com o pedido aberto, clique em **📎 Anexos**.

- **PDF, JPG, PNG ou WebP**, até **10 MB** cada, no máximo **20 por vez**.
- Cada arquivo mostra **quem enviou**, com data e hora.
- **Apagar: só quem enviou, ou o admin.** É prova — a OC assinada é o documento
  que sustenta a cobrança.
- Não existe "substituir". Para trocar, apague e suba de novo — assim o nome de
  quem enviou nunca fica mentindo.

> ⚠️ **O link do anexo funciona para quem o tiver.** Ao abrir um arquivo, o
> sistema gera um link que **vale 60 segundos** e não pede login. É tempo de
> abrir, não de repassar. **Não cole esse link em WhatsApp nem em e-mail** — se
> o cliente precisa do arquivo, mande o arquivo.

> ✅ **Disciplina nº 4:** chegou a OC assinada, anexou no pedido. Em seis meses,
> quando o financeiro perguntar, o documento está onde qualquer um acha.

---

## 7. Quando o cliente muda de ideia — **revisão do pedido**

Cliente pede desconto ao trocar a forma de pagamento. Cliente pede para
acrescentar mais um material no pedido que já está fechado. Isso é rotina.

**Antes** a saída era cancelar e refazer com outro número — e o cliente ficava
com um número na mão enquanto o CRM tinha outro. **Agora não.**

**Como fazer:** abra o pedido e clique em **✏ Editar**. Você pode:

- alterar **quantidade, preço e IPI** de cada item;
- **remover** um produto do pedido;
- **acrescentar** produto (escolhendo do catálogo, ou digitando o nome se ainda
  não estiver cadastrado);
- mudar **prazo de pagamento, frete, validade e observações**.

Enquanto você mexe, o **total recalcula na hora** e aparece quanto mudou em
relação à versão atual — dá para ver o efeito do desconto **antes de salvar**,
com o cliente ainda no telefone.

### O que acontece ao salvar

O pedido **não é sobrescrito**: nasce a **revisão 2**. O `0336-26` continua sendo
`0336-26`, e passa a se chamar `0336-26 rev. 2`. A revisão 1 fica guardada
inteira e você consulta quando quiser, clicando no selo **rev. 2** no topo.

A revisão sai impressa nos documentos. Sem isso, duas versões diferentes do
mesmo pedido circulariam com o mesmo número e ninguém saberia qual o cliente tem.

### O motivo é obrigatório

O sistema exige que você escreva **por que** o pedido mudou. Escreva de verdade:

- ✅ *"cliente trocou 30DD por 45DD e pediu 5% de desconto"*
- ❌ *"ajuste"*

É esse campo que responde *"por que este pedido saiu mais barato?"* daqui a seis
meses, quando ninguém lembrar da conversa.

### Duas regras

- **Pedido já expedido não pode ser editado.** A NF foi emitida; mudar o pedido
  depois disso descasa do fiscal. Se precisar, fale com o Igor.
- **Revisou um pedido que já foi para a fábrica? Reenvie o Pedido de Produção.**
  O sistema avisa na hora, mas quem reenvia é você — a fábrica está com a versão
  antiga e vai produzir errado.

---

## 8. Não deixar cliente esfriar — **Radar de Reativação** (atalho `R`)

O sistema lista automaticamente os **clientes dormentes** priorizados — quem
comprou e sumiu. Use o Radar **semanalmente** para retomar contato antes que o
cliente vá para o concorrente.

A mensagem de WhatsApp do Radar aceita os marcadores **`{nome_contato}`** e
**`{empresa}`**, que são preenchidos automaticamente para cada cliente.

---

## 9. Acompanhando seus números — **Dashboard** (atalho `D`)

- Cards **interativos**: clique em qualquer número para ver os detalhes (drill-down).
- Acompanhe seu funil, conversão e ranking na aba **Equipe**.
- O admin acompanha a **adoção por vendedor** — usar o sistema corretamente faz
  parte do trabalho, não é opcional.

---

## 10. Acesso, senha e celular

**Esqueceu a senha?** Na tela de login, clique em **"Esqueci minha senha"**,
informe seu e-mail corporativo e o link de redefinição chega em alguns minutos.
Não precisa pedir para ninguém.

- O link **vale uma vez só**. Se não chegar, confira o **spam**.
- Ao abrir o link você escolhe a nova senha (mínimo 8 caracteres) e já entra.

**Travou em "Entrando..."?** Use o link **"Limpar sessão e tentar de novo"**,
logo abaixo do formulário.

**Verificação em duas etapas (2FA).** Em **Minhas Configurações** você pode
ativar o 2FA. O sistema mostra um QR para escanear num app autenticador (Google
Authenticator, Authy, 1Password) e, dali em diante, o login pede também o código
de 6 dígitos que o app gera.

É opcional, e vale a pena: sua conta enxerga carteira de clientes, preço e
margem. **Vai trocar de celular? Desative o 2FA antes.** Sem o app antigo, quem
destrava é o Igor, pelo painel do Supabase.

**No celular:** o sistema funciona no telefone. As abas ficam numa faixa própria
que **desliza para o lado** quando não cabem todas na tela.

---

## 11. Os 9 hábitos de quem usa bem o CRM

1. **Comece pelo "Hoje"** e zere os retornos do dia.
2. **Toda conversa vira interação** registrada.
3. **Toda oportunidade tem próximo passo** com data.
4. **Busque antes de cadastrar** (sem duplicatas).
5. **Documento certo para cada público** (proposta ≠ pedido de produção).
6. **Peça e lance a OC do cliente** assim que o pedido fechar.
7. **Mudou o pedido? Revise no sistema** e escreva o motivo de verdade.
8. **Radar semanal** para reativar clientes parados.
9. **Chegou OC assinada ou comprovante? Anexe no pedido.**

---

## 12. Atalhos de teclado

| Tecla | Vai para |
|---|---|
| `T` | Hoje / Agenda |
| `C` | Empresas |
| `P` | Propostas |
| `R` | Radar de Reativação |
| `D` | Dashboard |
| `Ctrl+K` | Busca (empresa, contato, proposta, nº de pedido, nº de OC) |

> Dica: pressione `?` dentro do app para abrir a tabela de atalhos.

---

*CRM Adiblock — guia interno da equipe comercial.*
