/* ==========================================================================
   externo.js — o vendedor externo e o que o escritório faz por ele.
   2026-10-05. Migration: migrations/2026-10-05-vendedor-externo.sql

   A TRAVA ESTÁ NO BANCO. Tudo aqui é conveniência e mensagem clara: quem
   chamasse a API pelo console esbarraria no RLS e nas guardas
   (proposals_guarda_externo, companies_guarda_externo). Nada neste arquivo
   decide o que o externo pode VER — o banco já devolve só o que é dele.

     papel                ehExterno, ehEscritorio
     CNPJ já existente    externoChecaCnpj -> pedido de acesso pro escritório
     pedidos de acesso    ACESSO_PEDIDOS, renderPedidosAcesso, decidirAcesso
     acesso manual        carregarAcessoExternos / salvarAcessoExternos (modal de empresa)
     aceite de pedido     aceitarPedido, abrirDevolverPedido, confirmarDevolverPedido
     sininho              pendenciasDoSininho

   CARREGA DEPOIS de propostas.js (usa mudarStatusProposta, PROP_ATUAL) e
   antes do inline (que usa ehExterno). Nada executa no carregamento.
   ========================================================================== */

function ehExterno()   { return myRole() === 'externo'; }
// "Escritório" = quem aceita pedido e libera acesso: interno que escreve.
function ehEscritorio() { const r = myRole(); return r === 'admin' || r === 'vendedor'; }

// ── CNPJ que já existe ───────────────────────────────────────────────────
// O externo não enxerga a empresa de outro vendedor, então o UNIQUE do CNPJ
// devolveria um erro sem sentido para ele. A RPC compara só os dígitos e,
// se a empresa existir, abre um pedido de acesso — sem dizer de quem é.
async function externoChecaCnpj(cnpj, razao) {
  if (!ehExterno() || !cnpj) return 'livre';
  return await api('POST', 'rpc/externo_checa_cnpj', null, { p_cnpj: cnpj, p_razao: razao || null });
}

// Devolve true se o cadastro deve parar (a mensagem já foi dada).
function avisoCnpjExterno(res) {
  if (res === 'solicitado') {
    toast('Este CNPJ já está cadastrado',
      'Pedimos ao escritório para liberar esta empresa para você. Quando aprovarem, ela aparece na sua lista.', 'info');
    return true;
  }
  if (res === 'ja_solicitado') {
    toast('Pedido de acesso já enviado', 'O escritório ainda não respondeu sobre este CNPJ.', 'info');
    return true;
  }
  if (res === 'ja_tem_acesso') {
    toast('Você já tem esta empresa', 'Procure pelo nome ou CNPJ na aba Empresas.', 'info');
    return true;
  }
  return false;
}

// ── Pedidos de acesso ────────────────────────────────────────────────────
let ACESSO_PEDIDOS = [];

async function fetchPedidosAcesso() {
  try {
    if (ehExterno()) {
      ACESSO_PEDIDOS = await api('GET', 'company_access_requests',
        'select=id,status,cnpj_digitado,razao_digitada,created_at&order=created_at.desc&limit=50') || [];
    } else if (ehEscritorio()) {
      // `!requester_id`: a tabela tem duas FKs para profiles (pedinte e quem decidiu)
      ACESSO_PEDIDOS = await api('GET', 'company_access_requests',
        'select=id,status,cnpj_digitado,razao_digitada,created_at,' +
        'empresa:companies(id,razao_social,vendedor_responsavel_nome),' +
        'pedinte:profiles!requester_id(id,name)' +
        '&status=eq.pendente&order=created_at.asc') || [];
    } else {
      ACESSO_PEDIDOS = [];
    }
  } catch (err) {
    // Tabela ainda não existe (migration não aplicada): não é erro do usuário.
    console.warn('fetchPedidosAcesso:', err.message);
    ACESSO_PEDIDOS = [];
  }
  return ACESSO_PEDIDOS;
}

async function renderPedidosAcesso() {
  const box = document.getElementById('eq-acessos-body');
  const wrap = document.getElementById('eq-acessos');
  if (!box || !wrap) return;
  if (!ehEscritorio()) { wrap.hidden = true; return; }
  await fetchPedidosAcesso();
  wrap.hidden = !ACESSO_PEDIDOS.length;
  box.innerHTML = ACESSO_PEDIDOS.map(r => `
    <div class="eq-card">
      <div class="eq-info-main">
        <div class="eq-nome">${escHtml(r.pedinte?.name || '?')} quer acesso a <b>${escHtml(r.empresa?.razao_social || r.razao_digitada || '—')}</b></div>
        <div class="eq-meta">CNPJ ${escHtml(r.cnpj_digitado || '—')} · responsável hoje: ${escHtml(r.empresa?.vendedor_responsavel_nome || 'ninguém')} · pedido em ${fData(r.created_at)}</div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:wrap">
        <button class="btn bg sm" onclick="decidirAcesso('${r.id}', false)">Recusar</button>
        <button class="btn bp sm" onclick="decidirAcesso('${r.id}', true)">Liberar</button>
      </div>
    </div>`).join('');
}

async function decidirAcesso(id, aprovar) {
  try {
    await api('POST', 'rpc/decidir_acesso', null, { p_req: id, p_aprovar: !!aprovar });
    toast(aprovar ? 'Acesso liberado' : 'Pedido recusado',
      aprovar ? 'A empresa já aparece para o vendedor externo.' : '', 'success');
    await renderPedidosAcesso();
    updateBell();
  } catch (err) {
    toast('Erro ao decidir o pedido', err.message || '', 'warning');
  }
}

// ── Acesso manual (modal de empresa, só escritório) ──────────────────────
// O responsável continua sendo UM só (vendedor_responsavel_id). Isto é o
// acesso ADICIONAL: o escritório põe um externo numa empresa que não é dele.
let ACESSO_EXT_ORIGINAL = new Set();

function externosDaEquipe() {
  return (PF || []).filter(p => p.role === 'externo');
}

async function carregarAcessoExternos(companyId) {
  const wrap = document.getElementById('f-ext-wrap');
  const lista = document.getElementById('f-ext-lista');
  if (!wrap || !lista) return;
  ACESSO_EXT_ORIGINAL = new Set();
  const externos = externosDaEquipe();
  wrap.hidden = !companyId || !ehEscritorio() || !externos.length;
  if (wrap.hidden) { lista.innerHTML = ''; return; }
  try {
    const rows = await api('GET', 'company_access', `company_id=eq.${companyId}&select=profile_id`) || [];
    ACESSO_EXT_ORIGINAL = new Set(rows.map(r => r.profile_id));
  } catch (err) { console.warn('carregarAcessoExternos:', err.message); }
  const resp = CL.find(c => c.id === companyId)?.vendedor_responsavel_id;
  lista.innerHTML = externos.map(p => {
    const ehResp = p.id === resp;
    return `<label>
      <input type="checkbox" value="${escHtml(p.id)}"${ACESSO_EXT_ORIGINAL.has(p.id) || ehResp ? ' checked' : ''}${ehResp ? ' disabled' : ''}>
      ${escHtml(p.name || p.email || '?')}${ehResp ? ' <span class="f-ext-resp">responsável</span>' : ''}
    </label>`;
  }).join('');
}

// Grava só a diferença. Chamada DEPOIS do save da empresa.
async function salvarAcessoExternos(companyId) {
  const wrap = document.getElementById('f-ext-wrap');
  if (!wrap || wrap.hidden || !companyId) return;
  const marcados = new Set([...wrap.querySelectorAll('input[type=checkbox]:checked:not(:disabled)')].map(i => i.value));
  const novos    = [...marcados].filter(id => !ACESSO_EXT_ORIGINAL.has(id));
  const tirados  = [...ACESSO_EXT_ORIGINAL].filter(id => !marcados.has(id));
  if (novos.length) {
    await api('POST', 'company_access', null,
      novos.map(id => ({ company_id: companyId, profile_id: id, granted_by: ME?.id || null })));
  }
  for (const id of tirados) {
    await apiDelete('company_access', `company_id=eq.${companyId}&profile_id=eq.${id}`);
  }
}

// ── Aceite de pedido ─────────────────────────────────────────────────────
// Externo fecha -> 'aguardando_aceite'. O nº do pedido só nasce quando o
// escritório aceita (o trigger de numeração dispara na entrada em 'pedido').
async function aceitarPedido() {
  if (!PROP_ATUAL) return;
  await mudarStatusProposta('pedido', 'Pedido aceito');
  updateBell();
  await ofereceMarcarOppGanha();
  perguntarOC();
}

function abrirDevolverPedido() {
  if (!PROP_ATUAL) return;
  document.getElementById('dev-motivo').value = '';
  document.getElementById('dev-err').textContent = '';
  document.getElementById('dev-m').classList.add('op');
  setTimeout(() => document.getElementById('dev-motivo').focus(), 80);
}

function fecharDevolverPedido() {
  document.getElementById('dev-m').classList.remove('op');
}

async function confirmarDevolverPedido() {
  const p = PROP_ATUAL;
  const motivo = document.getElementById('dev-motivo').value.trim();
  const btn = document.getElementById('dev-ok');
  // Devolver sem dizer o porquê deixa o vendedor adivinhando o que corrigir.
  if (!motivo) { document.getElementById('dev-err').textContent = 'Diga o que precisa ser corrigido.'; return; }
  if (!p) return;
  btn.disabled = true;
  try {
    await api('PATCH', 'proposals', `id=eq.${p.id}`, {
      status: 'em_andamento',
      aceite_recusa_motivo: motivo,
      status_changed_at: new Date().toISOString(),
      status_changed_by: ME.id,
    });
    PROP_ATUAL = { ...p, status: 'em_andamento', aceite_recusa_motivo: motivo };
    const i = PROPOSTAS.findIndex(x => x.id === p.id);
    if (i >= 0) PROPOSTAS[i] = PROP_ATUAL;
    fecharDevolverPedido();
    atualizarTopoCotacao();
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
    updateBell();
    toast('Pedido devolvido', 'Voltou para "Em andamento" com o seu motivo.', 'success');
  } catch (err) {
    document.getElementById('dev-err').textContent = err.message || 'Erro ao devolver.';
  } finally {
    btn.disabled = false;
  }
}

// ── Sininho ──────────────────────────────────────────────────────────────
// Escritório: pedidos esperando aceite + pedidos de acesso.
// Externo: propostas que o escritório devolveu.
function pendenciasDoSininho() {
  const linha = (ico, tit, sub, onclick) => `<div class="bell-row" onclick="${onclick};fecharBell()">
      <div class="bell-t">${ico}</div>
      <div class="bell-bd"><div class="bell-emp">${escHtml(tit)}</div><div class="bell-sub">${escHtml(sub)}</div></div>
    </div>`;
  const nomeEmp = p => p.snapshot?.cliente?.name || CL.find(c => c.id === p.company_id)?.razao_social || '—';
  let n = 0, html = '';

  if (ehEscritorio()) {
    const aguard = (PROPOSTAS || []).filter(p => p.status === 'aguardando_aceite');
    if (aguard.length) {
      n += aguard.length;
      html += `<div class="bell-h">Pedidos para aceitar <span>${aguard.length}</span></div>` +
        aguard.slice(0, 8).map(p => linha('📦', nomeEmp(p), 'Proposta ' + numProposta(p) + ' · ' + (p.snapshot?.consultor?.nome || ''),
          `abrPropostaPorId('${p.id}')`)).join('');
    }
    if (ACESSO_PEDIDOS.length) {
      n += ACESSO_PEDIDOS.length;
      html += `<div class="bell-h">Pedidos de acesso <span>${ACESSO_PEDIDOS.length}</span></div>` +
        ACESSO_PEDIDOS.slice(0, 8).map(r => linha('🔑', r.empresa?.razao_social || r.razao_digitada || '—', 'pedido por ' + (r.pedinte?.name || '?'),
          `document.querySelector('.tb[data-tab=&quot;eq&quot;]').click()`)).join('');
    }
  } else if (ehExterno()) {
    const devolvidas = (PROPOSTAS || []).filter(p => p.status === 'em_andamento' && p.aceite_recusa_motivo && p.seller_id === ME?.id);
    if (devolvidas.length) {
      n += devolvidas.length;
      html += `<div class="bell-h">Devolvidos pelo escritório <span>${devolvidas.length}</span></div>` +
        devolvidas.slice(0, 8).map(p => linha('↩', nomeEmp(p), p.aceite_recusa_motivo, `abrPropostaPorId('${p.id}')`)).join('');
    }
  }
  return { n, html };
}
