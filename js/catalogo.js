/* ==========================================================================
   catalogo.js — cadastro de produtos, embalagens e precos. SO ADMIN.
   2026-08-17.

   A trava de verdade esta no BANCO: a policy `products_write` exige
   `is_admin()` e `org_id = current_org()`. Tudo aqui e conveniencia — um
   vendedor que chamasse estas funcoes pelo console esbarraria no RLS e
   receberia erro do PostgREST. Mesmo assim as funcoes checam o papel antes,
   pra dar mensagem clara em vez de erro cru.

   MODELO: cada linha de `products` e um par PRODUTO + EMBALAGEM (chave unica
   `(nome, embalagem)` no banco). "Cadastrar uma embalagem nova" e criar outra
   linha com o mesmo `nome`. Por isso a tela agrupa por produto e lista as
   embalagens dentro — e como se pensa no catalogo.

   CARREGA DEPOIS de api.js/format.js e ANTES do <script> inline. Consome
   api() e apiDelete() (api.js), escHtml (format.js), e toast(), conf(), PRODS
   e MEP (inline) — todos lidos so em tempo de EXECUCAO, nunca no
   carregamento, que e o que torna a ordem segura.
   ========================================================================== */

// Produto cujo formulario esta aberto. null = produto novo; string = nova
// embalagem daquele produto (o nome ja vem travado).
let CAT_NOME_FIXO = null;

function catEhAdmin() {
  if (MEP?.role === 'admin') return true;
  toast('Só o administrador altera o catálogo', 'Fale com o Igor.', 'warning');
  return false;
}

async function abrirCatalogo() {
  if (!catEhAdmin()) return;
  const page = document.getElementById('cat-page');
  page.classList.add('op'); page.scrollTop = 0;
  document.body.style.overflow = 'hidden';
  document.getElementById('cat-busca').value = '';
  await recarregarCatalogo();
}

function fecharCatalogo() {
  document.getElementById('cat-page').classList.remove('op');
  document.body.style.overflow = '';
}

// Rebusca do banco. Traz o `id`, que o fetchProds do inline nao trazia — sem
// ele nao da pra alterar nem excluir linha.
async function recarregarCatalogo() {
  const lista = document.getElementById('cat-lista');
  lista.innerHTML = '<div class="sl"><div class="sp"></div></div>';
  try {
    PRODS = await api('GET', 'products',
      'select=id,nome,embalagem,preco_materia_prima,preco_office,preco_pj&order=nome,embalagem') || [];
    renderCatalogo();
  } catch (err) {
    console.error('recarregarCatalogo:', err);
    lista.innerHTML = '<div class="pf-empty" style="color:var(--er)">Não foi possível carregar: '
      + escHtml(err.message || '') + '</div>';
  }
}

function renderCatalogo() {
  const lista = document.getElementById('cat-lista');
  if (!lista) return;
  const termo = (document.getElementById('cat-busca')?.value || '').trim().toLowerCase();

  // agrupa por nome: uma "ficha" por produto, com suas embalagens dentro
  const grupos = new Map();
  for (const p of (PRODS || [])) {
    const alvo = ((p.nome || '') + ' ' + (p.embalagem || '')).toLowerCase();
    if (termo && !alvo.includes(termo)) continue;
    if (!grupos.has(p.nome)) grupos.set(p.nome, []);
    grupos.get(p.nome).push(p);
  }

  const conta = document.getElementById('cat-conta');
  if (conta) conta.textContent = grupos.size
    ? `${grupos.size} produto(s) · ${[...grupos.values()].reduce((s, g) => s + g.length, 0)} embalagem(ns)`
    : '';

  if (!grupos.size) {
    lista.innerHTML = `<div class="pf-empty">${termo
      ? 'Nenhum produto encontrado para "' + escHtml(termo) + '".'
      : 'Catálogo vazio. Use "+ Novo produto" para começar.'}</div>`;
    return;
  }

  lista.innerHTML = [...grupos.entries()].map(([nome, embs]) => `
    <div class="cat-prod">
      <div class="cat-prod-head">
        <h3>${escHtml(nome)}</h3>
        <button type="button" class="btn bg sm" onclick="abrirNovaEmbalagem('${escAttr(nome)}')">+ Embalagem</button>
      </div>
      <div class="cat-embs">
        ${embs.map(p => `
          <div class="cat-emb" data-id="${p.id}">
            <div class="cat-emb-nome">${escHtml(p.embalagem || '—')}</div>
            ${campoPreco(p.id, 'pj',     'Base PJ',       p.preco_pj)}
            ${campoPreco(p.id, 'office', 'Base OFFICE',   p.preco_office)}
            ${campoPreco(p.id, 'mp',     'Matéria-prima', p.preco_materia_prima)}
            <div class="cat-emb-acoes">
              <button type="button" class="btn bp sm" onclick="salvarPrecos('${p.id}')">Salvar</button>
              <button type="button" class="cat-del" title="Excluir esta embalagem"
                      aria-label="Excluir embalagem ${escAttr(p.embalagem || '')} de ${escAttr(nome)}"
                      onclick="excluirEmbalagem('${p.id}','${escAttr(nome)}','${escAttr(p.embalagem || '')}')">✕</button>
            </div>
          </div>`).join('')}
      </div>
    </div>`).join('');
}

// Aspas em nome de produto quebrariam o onclick inline. escHtml nao basta:
// ele nao escapa a aspa simples que delimita o argumento.
function escAttr(s) {
  return String(s == null ? '' : s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/"/g, '&quot;');
}

function campoPreco(id, chave, rotulo, valor) {
  return `<label class="cat-preco">
    <span>${rotulo}</span>
    <input type="number" step="0.01" min="0" data-p="${chave}" data-id="${id}"
           value="${valor != null ? Number(valor).toFixed(2) : ''}" placeholder="—">
  </label>`;
}

async function salvarPrecos(id) {
  if (!catEhAdmin()) return;
  const campos = document.querySelectorAll(`.cat-preco input[data-id="${id}"]`);
  const dados = {};
  campos.forEach(c => {
    const v = c.value.trim();
    const n = v === '' ? null : Number(v);
    if (v !== '' && (!isFinite(n) || n < 0)) return;   // ignora lixo
    if (c.dataset.p === 'pj')     dados.preco_pj = n;
    if (c.dataset.p === 'office') dados.preco_office = n;
    if (c.dataset.p === 'mp')     dados.preco_materia_prima = n;
  });
  if (dados.preco_pj == null) {
    toast('Base PJ é obrigatório', 'É o preço sugerido ao montar proposta.', 'warning');
    return;
  }
  try {
    await api('PATCH', 'products', `id=eq.${id}`, dados);
    const i = (PRODS || []).findIndex(p => p.id === id);
    if (i >= 0) PRODS[i] = { ...PRODS[i], ...dados };
    toast('Preços atualizados', 'Vale para as próximas propostas.', 'success');
  } catch (err) {
    console.error('salvarPrecos:', err);
    toast('Não foi possível salvar', err.message || '', 'warning');
  }
}

function excluirEmbalagem(id, nome, emb) {
  if (!catEhAdmin()) return;
  conf('Excluir embalagem',
    `Remover "${emb}" do produto "${nome}"? Propostas já geradas não são afetadas — elas guardam os próprios valores.`,
    async () => {
      try {
        await apiDelete('products', `id=eq.${id}`);
        PRODS = (PRODS || []).filter(p => p.id !== id);
        renderCatalogo();
        toast('Embalagem removida', '', 'success');
      } catch (err) {
        console.error('excluirEmbalagem:', err);
        toast('Não foi possível excluir', err.message || '', 'warning');
      }
    });
}

// ── Formulário: produto novo ou embalagem nova ───────────────────────────
function abrirNovoProduto() {
  if (!catEhAdmin()) return;
  CAT_NOME_FIXO = null;
  document.getElementById('cat-m-tit').textContent = 'Novo produto';
  document.getElementById('cat-f').reset();
  document.getElementById('cat-nome').readOnly = false;
  document.getElementById('cat-erro').textContent = '';
  document.getElementById('cat-m').classList.add('op');
  setTimeout(() => document.getElementById('cat-nome')?.focus(), 80);
}

function abrirNovaEmbalagem(nome) {
  if (!catEhAdmin()) return;
  CAT_NOME_FIXO = nome;
  document.getElementById('cat-m-tit').textContent = 'Nova embalagem';
  document.getElementById('cat-f').reset();
  const campoNome = document.getElementById('cat-nome');
  campoNome.value = nome;
  // Travado: aqui o nome identifica o produto que ja existe. Deixar editavel
  // faria "nova embalagem" virar "produto novo" sem querer.
  campoNome.readOnly = true;
  document.getElementById('cat-erro').textContent = '';
  document.getElementById('cat-m').classList.add('op');
  setTimeout(() => document.getElementById('cat-emb')?.focus(), 80);
}

function fecharNovoProduto() {
  document.getElementById('cat-m').classList.remove('op');
  CAT_NOME_FIXO = null;
}

document.getElementById('cat-f')?.addEventListener('submit', async e => {
  e.preventDefault();
  if (!catEhAdmin()) return;
  const erro = document.getElementById('cat-erro');
  erro.textContent = '';
  const nome = (CAT_NOME_FIXO || document.getElementById('cat-nome').value).trim();
  const emb  = document.getElementById('cat-emb').value.trim();
  const pj   = document.getElementById('cat-pj').value.trim();
  if (!nome || !emb) { erro.textContent = 'Produto e embalagem são obrigatórios.'; return; }
  if (!pj)           { erro.textContent = 'Base PJ é obrigatório — é o preço sugerido na proposta.'; return; }

  // O banco tem UNIQUE (nome, embalagem); checar aqui da mensagem melhor que
  // o erro cru do PostgREST.
  const jaExiste = (PRODS || []).some(p =>
    (p.nome || '').toLowerCase() === nome.toLowerCase() &&
    (p.embalagem || '').toLowerCase() === emb.toLowerCase());
  if (jaExiste) { erro.textContent = `"${nome}" já tem a embalagem "${emb}".`; return; }

  const num = v => { const t = String(v).trim(); return t === '' ? null : Number(t); };
  const btn = document.getElementById('cat-sub');
  btn.disabled = true; btn.textContent = 'Salvando...';
  try {
    // org_id nao vai aqui: o trigger set_org_id preenche no INSERT.
    await api('POST', 'products', null, {
      nome, embalagem: emb,
      preco_pj: num(pj),
      preco_office: num(document.getElementById('cat-office').value),
      preco_materia_prima: num(document.getElementById('cat-mp').value),
    });
    fecharNovoProduto();
    await recarregarCatalogo();
    toast(CAT_NOME_FIXO ? 'Embalagem adicionada' : 'Produto cadastrado', `${nome} — ${emb}`, 'success');
  } catch (err) {
    console.error('salvar produto:', err);
    erro.textContent = /duplicate|unique/i.test(err.message || '')
      ? 'Já existe esse produto com essa embalagem.'
      : (err.message || 'Não foi possível salvar.');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar';
  }
});
