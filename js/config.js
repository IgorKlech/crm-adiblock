/* ==========================================================================
   config.js — chaves, cliente Supabase e a guarda de carregamento.
   Sprint 8.1 (modularizacao), retomado em 17/08/2026.

   CARREGA ANTES de api.js e do <script> inline: define SB_URL, SB_KEY e `sb`,
   que os dois usam. Sem bundler e sem type=module — tudo aqui e global,
   igual a quando morava no inline.

   ⚠ MUDANCA DE COMPORTAMENTO ao sair do inline: o `throw` da guarda abaixo
   agora para SO este arquivo; antes parava o script inteiro. Os arquivos
   seguintes continuam executando e vao dar erro de referencia no console.
   O que o usuario VE nao muda — a tela de erro ja substituiu o body.
   ========================================================================== */
// ── Config ────────────────────────────────────────────────────────────────
const SB_URL = 'https://kgiynhrytnzfdywgjhby.supabase.co';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnaXluaHJ5dG56ZmR5d2dqaGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0Mzc0NzUsImV4cCI6MjA5NTAxMzQ3NX0.8cOWLAsJyXAzid5ce73FUI-HVVYJoWyfOC3pSKci6Vs';
// Guarda: se nem o arquivo local nem o CDN definiram `supabase`, mostra um
// aviso visivel em vez de TELA PRETA muda (o que travava o app antes).
if (typeof supabase === 'undefined' || !supabase.createClient) {
  document.body.innerHTML =
    '<div style="max-width:440px;margin:80px auto;padding:24px;font-family:Inter,system-ui,sans-serif;'
    // Sprint 9.3 (B-02): var(--tx)/var(--mt) e nao hex fixo — esta tela herda o
    // fundo do tema salvo, e texto escuro fixo sumia no modo escuro.
    + 'text-align:center;color:var(--tx)">'
    + '<div style="font-size:40px">⚠️</div>'
    + '<h2 style="margin:8px 0">Nao foi possivel carregar o sistema</h2>'
    + '<p style="color:var(--mt);line-height:1.5">Uma biblioteca essencial nao carregou '
    + '(possivel queda de rede ou bloqueio por extensao/firewall). '
    + 'Verifique a conexao e tente recarregar.</p>'
    + '<button onclick="location.reload()" style="margin-top:12px;padding:10px 20px;'
    + 'border:0;border-radius:8px;background:var(--p);color:#fff;font-weight:600;cursor:pointer">'
    + 'Recarregar</button></div>';
  throw new Error('supabase-js nao carregou (local + CDN falharam)');
}
const { createClient } = supabase;
const sb = createClient(SB_URL, SB_KEY);

// Sprint 9.3 (B-01): o link de "redefinir senha" chega como #type=recovery na URL.
// O supabase-js consome e APAGA esse hash assim que inicializa, e o evento
// PASSWORD_RECOVERY corre junto com o boot — quem chegar primeiro ganha. Ler o
// hash aqui, de forma sincrona, e a unica leitura confiavel: a partir dela o
// boot e o onAuthStateChange sabem que nao devem abrir o app.
// `let` e nao `const`: precisa ser desligada assim que a senha for trocada, se
// nao o TOKEN_REFRESHED seguinte joga o usuario de volta na tela de nova senha.
let MODO_RECUPERACAO = /[#&]type=recovery/.test(window.location.hash || '');

