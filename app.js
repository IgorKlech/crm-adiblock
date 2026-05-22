// ── Configuração ──────────────────────────────────────────────────────────
const URL_SB  = 'https://kgiynhrytnzfdywgjhby.supabase.co';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnaXluaHJ5dG56ZmR5d2dqaGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0Mzc0NzUsImV4cCI6MjA5NTAxMzQ3NX0.8cOWLAsJyXAzid5ce73FUI-HVVYJoWyfOC3pSKci6Vs';

// SDK apenas para autenticação
const { createClient } = supabase;
const auth = createClient(URL_SB, ANON_KEY);

// ── Token de autenticação (XHR usa este) ──────────────────────────────────
let TOKEN = ANON_KEY;

// ── XHR — não é afetado por scripts injetados ─────────────────────────────
function xhr(method, tabela, params, body) {
  return new Promise((resolve, reject) => {
    const url = `${URL_SB}/rest/v1/${tabela}${params ? '?' + params : ''}`;
    const r = new XMLHttpRequest();
    r.open(method, url, true);
    r.setRequestHeader('apikey', ANON_KEY);
    r.setRequestHeader('Authorization', 'Bearer ' + TOKEN);
    r.setRequestHeader('Content-Type', 'application/json');
    r.setRequestHeader('Prefer', 'return=representation');
    r.timeout = 12000;
    r.ontimeout = () => reject(new Error('Sem resposta do servidor. Verifique sua internet.'));
    r.onerror   = () => reject(new Error('Erro de conexão.'));
    r.onload = () => {
      if (r.status >= 200 && r.status < 300) {
        try { resolve(r.responseText ? JSON.parse(r.responseText) : []); } catch { resolve([]); }
      } else {
        let m = r.responseText;
        try { m = JSON.parse(m).message || m; } catch {}
        reject(new Error(m || 'Erro ' + r.status));
      }
    };
    r.send(body != null ? JSON.stringify(body) : null);
  });
}

// ── Estado ────────────────────────────────────────────────────────────────
let currentUser = null, currentProfile = null;
let allClients = [], allProfiles = [];
let currentClientId = null, editingClientId = null;
let sortCol = 'created_at', sortDir = 'desc', confirmCb = null;

const VENDEDORES_FIXOS = ['Igor', 'Nádia', 'Letícia', 'Gracielle'];

// ── Avatares ──────────────────────────────────────────────────────────────
const CORES = ['#1F4E78','#0891b2','#7c3aed','#059669','#dc2626','#d97706','#0284c7','#c026d3'];
const corAvatar = n => CORES[(n||'A').toUpperCase().charCodeAt(0) % CORES.length];
const iniAvatar = n => (n||'?')[0].toUpperCase();

// ── Formatação ────────────────────────────────────────────────────────────
const hoje = () => new Date().toISOString().split('T')[0];
const vencido = d => !!d && d <= hoje();

function fmtData(d) {
  if (!d) return '—';
  const [y,m,dd] = d.split('-');
  return `${dd}/${m}/${y}`;
}

function fmtRelativo(d) {
  if (!d) return '';
  const diff = Math.round((new Date(d) - new Date(hoje())) / 86400000);
  if (diff === 0) return 'Hoje';
  if (diff === 1) return 'Amanhã';
  if (diff ===-1) return 'Ontem';
  return diff < 0 ? `${Math.abs(diff)}d atrás` : `em ${diff}d`;
}

function fmtDH(dt) {
  if (!dt) return '—';
  return new Date(dt).toLocaleString('pt-BR', {
    day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit'
  });
}

function fmtMoeda(v) {
  if (v == null || v === '') return '—';
  return Number(v).toLocaleString('pt-BR', { style:'currency', currency:'BRL' });
}

function badgeStatus(s) {
  const m = { 'Pendente':'pendente','Em contato':'em-contato','Comprou':'comprou','Nao comprou':'nao-comprou','Inativo':'inativo' };
  return `<span class="badge badge-${m[s]||'pendente'}">${s}</span>`;
}

// ── Toast ─────────────────────────────────────────────────────────────────
function toast(titulo, msg, tipo) {
  tipo = tipo || 'info';
  const icons = {
    success: '✓', warning: '⚠', info: 'ℹ'
  };
  const c = document.getElementById('toast-container');
  const t = document.createElement('div');
  t.className = 'toast' + (tipo==='success'?' t-success':tipo==='warning'?' t-warning':'');
  t.innerHTML = `<span style="font-size:16px">${icons[tipo]||'ℹ'}</span>
    <div class="toast-body"><div class="toast-title">${titulo}</div>${msg?`<div class="toast-msg">${msg}</div>`:''}</div>
    <button class="toast-close" onclick="this.closest('.toast').remove()">✕</button>`;
  c.appendChild(t);
  setTimeout(() => t?.parentNode && t.remove(), tipo==='warning' ? 10000 : 5000);
}

// ── Confirm ───────────────────────────────────────────────────────────────
function confirmar(titulo, msg, cb) {
  document.getElementById('confirm-title').textContent = titulo;
  document.getElementById('confirm-msg').textContent = msg;
  document.getElementById('confirm-overlay').classList.add('open');
  confirmCb = cb;
}
function fecharConfirm() {
  document.getElementById('confirm-overlay').classList.remove('open');
  confirmCb = null;
}
document.getElementById('confirm-ok').addEventListener('click', () => { fecharConfirm(); if (confirmCb) confirmCb(); });
document.getElementById('confirm-cancel').addEventListener('click', fecharConfirm);

// ── Queries XHR ───────────────────────────────────────────────────────────
async function fetchClientes() {
  return xhr('GET', 'clients', 'select=*,seller:profiles(id,name)&order=created_at.desc');
}

async function fetchPerfis() {
  return xhr('GET', 'profiles', 'select=id,name,role,email&order=name');
}

async function fetchHistorico(clienteId) {
  return xhr('GET', 'call_history',
    `client_id=eq.${clienteId}&select=*,seller:profiles(id,name)&order=datetime.desc`);
}

async function salvarCliente(dados, id) {
  if (id) {
    const rows = await xhr('PATCH', 'clients', `id=eq.${id}`, dados);
    return Array.isArray(rows) ? rows[0] : rows;
  }
  const rows = await xhr('POST', 'clients', null, dados);
  return Array.isArray(rows) ? rows[0] : rows;
}

async function excluirCliente(id) {
  const rows = await xhr('DELETE', 'clients', `id=eq.${id}`);
  if (!rows || (Array.isArray(rows) && rows.length === 0)) {
    throw new Error('Registro não encontrado ou sem permissão para excluir.');
  }
}

async function salvarContato(dados) {
  const rows = await xhr('POST', 'call_history', null, dados);
  return Array.isArray(rows) ? rows[0] : rows;
}

// ── Perfil do usuário logado ───────────────────────────────────────────────
async function fetchMeuPerfil(userId) {
  const rows = await xhr('GET', 'profiles', `id=eq.${userId}&select=*`);
  return rows[0] || null;
}

// ── Sugestões de vendedor ─────────────────────────────────────────────────
function atualizarSugestoes() {
  const dl = document.getElementById('sellers-list');
  if (!dl) return;
  const nomes = allProfiles.length > 0
    ? allProfiles.map(p => p.name)
    : VENDEDORES_FIXOS;
  dl.innerHTML = nomes.map(n => `<option value="${n}">`).join('');
}

// ── Ordenação e filtro ────────────────────────────────────────────────────
function ordenar(lista) {
  return [...lista].sort((a, b) => {
    let va = a[sortCol], vb = b[sortCol];
    if (sortCol === 'seller_name') {
      va = a.seller_name || a.seller?.name || '';
      vb = b.seller_name || b.seller?.name || '';
    }
    if (va == null && vb == null) return 0;
    if (va == null) return 1; if (vb == null) return -1;
    const c = String(va).toLowerCase() < String(vb).toLowerCase() ? -1 : 1;
    return sortDir === 'asc' ? c : -c;
  });
}

function filtrados() {
  const q  = (document.getElementById('search-input').value || '').toLowerCase();
  const sf = document.getElementById('status-filter').value;
  const vf = (document.getElementById('seller-filter').value || '').toLowerCase();
  return allClients.filter(c => {
    const nm = (c.seller_name || c.seller?.name || '').toLowerCase();
    return ((c.name||'').toLowerCase().includes(q) || (c.phone||'').includes(q)) &&
      (!sf || c.status === sf) &&
      (!vf || nm.includes(vf));
  });
}

// ── CSV ───────────────────────────────────────────────────────────────────
function exportarCSV() {
  const rows = filtrados();
  if (!rows.length) { toast('Nada para exportar', '', 'warning'); return; }
  const h = ['Nome','Telefone','Vendedor','Status','Produto','Peso','Data Retorno','Valor','Observacao'];
  const l = rows.map(c => [
    c.name, c.phone||'', c.seller_name||c.seller?.name||'', c.status,
    c.produto||'', c.peso||'', c.callback_date||'',
    c.estimated_value||'', (c.observation||'').replace(/\n/g,' ')
  ].map(v => `"${String(v).replace(/"/g,'""')}"`).join(','));
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + [h.join(','), ...l].join('\n')], {type:'text/csv;charset=utf-8'}));
  a.download = `clientes_${hoje()}.csv`;
  a.click();
  toast('Exportado!', `${rows.length} cliente(s).`, 'success');
}

// ── Render tabela ─────────────────────────────────────────────────────────
function renderClientes() {
  const lista = ordenar(filtrados());
  const total = allClients.length;
  const sub = document.getElementById('clients-subtitle');
  if (sub) sub.textContent = lista.length === total ? `${total} cliente(s)` : `${lista.length} de ${total}`;

  const tbody = document.getElementById('clients-tbody');
  if (!lista.length) {
    tbody.innerHTML = `<tr><td colspan="7"><div class="state-empty"><h3>Nenhum cliente encontrado</h3><p>Ajuste os filtros ou cadastre um novo.</p></div></td></tr>`;
    return;
  }
  tbody.innerHTML = lista.map(c => {
    const over = vencido(c.callback_date);
    const nomeVend = c.seller_name || c.seller?.name || '';
    const vendCell = nomeVend
      ? `<div class="seller-chip"><div class="seller-avatar" style="background:${corAvatar(nomeVend)}">${iniAvatar(nomeVend)}</div>${nomeVend}</div>`
      : `<span style="color:var(--muted)">—</span>`;
    const prodInfo = [c.produto, c.peso].filter(Boolean).join(' · ');
    const dataCell = c.callback_date
      ? `${fmtData(c.callback_date)} <small style="color:var(--muted)">(${fmtRelativo(c.callback_date)})</small>${over ? `<span class="overdue-badge">Vencido</span>` : ''}`
      : '—';
    return `<tr class="${over ? 'overdue' : ''}">
      <td><strong>${c.name}</strong>${prodInfo ? `<div class="prod-info">${prodInfo}</div>` : ''}</td>
      <td class="td-phone">${c.phone || '—'}</td>
      <td>${vendCell}</td>
      <td>${badgeStatus(c.status)}</td>
      <td>${dataCell}</td>
      <td>${fmtMoeda(c.estimated_value)}</td>
      <td><div class="actions-cell">
        <button class="btn btn-ghost btn-sm" onclick="abrirPainel('${c.id}')">Histórico</button>
        <button class="btn btn-primary btn-sm" onclick="abrirEdicao('${c.id}')">Editar</button>
        <button class="btn btn-outline-danger btn-sm" onclick="confirmarExclusao('${c.id}','${(c.name||'').replace(/'/g,"\\'")}')">Excluir</button>
      </div></td>
    </tr>`;
  }).join('');
}

// ── Dashboard ─────────────────────────────────────────────────────────────
async function renderDashboard() {
  const total   = allClients.length;
  const comprou = allClients.filter(c => c.status === 'Comprou').length;
  const pend    = allClients.filter(c => c.status === 'Pendente').length;
  const venc    = allClients.filter(c => vencido(c.callback_date) && c.status !== 'Comprou' && c.status !== 'Inativo');
  const pct = v => total ? Math.round(v / total * 100) : 0;

  document.getElementById('stat-total').textContent   = total;
  document.getElementById('stat-bought').textContent  = comprou;
  document.getElementById('stat-pending').textContent = pend;
  document.getElementById('stat-overdue').textContent = venc.length;
  document.getElementById('stat-bought-bar').style.width  = pct(comprou) + '%';
  document.getElementById('stat-pending-bar').style.width = pct(pend) + '%';

  const ob = document.getElementById('overdue-badge');
  if (ob) ob.textContent = venc.length;

  const oel = document.getElementById('overdue-list');
  oel.innerHTML = venc.length
    ? venc.slice(0, 10).map(c => `
        <div class="alert-row">
          <div class="alert-dot"></div>
          <div>
            <div class="alert-name">${c.name}</div>
            <div class="alert-sub">${c.seller_name||c.seller?.name||'Sem vendedor'} — ${fmtData(c.callback_date)} (${fmtRelativo(c.callback_date)})</div>
          </div>
        </div>`).join('')
    : `<div class="state-empty" style="padding:12px 0"><p>Nenhum retorno vencido!</p></div>`;

  try {
    const hist = await xhr('GET', 'call_history', 'result=eq.Comprou&select=seller_id,seller:profiles(name)');
    const counts = {}, names = {};
    (hist || []).forEach(h => {
      counts[h.seller_id] = (counts[h.seller_id] || 0) + 1;
      if (h.seller) names[h.seller_id] = h.seller.name;
    });
    const top3  = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);
    const max   = top3[0]?.[1] || 1;
    const medal = ['p1', 'p2', 'p3'];
    document.getElementById('ranking-list').innerHTML = top3.length
      ? top3.map(([sid, n], i) => `
          <div class="rank-row">
            <div class="rank-pos ${medal[i]}">${i + 1}</div>
            <div class="rank-bar-wrap">
              <div class="rank-name">${names[sid] || 'Desconhecido'}</div>
              <div class="rank-bar"><div class="rank-bar-fill" style="width:${Math.round(n/max*100)}%"></div></div>
            </div>
            <div><div class="rank-conv">${n}</div><div class="rank-unit">vendas</div></div>
          </div>`).join('')
      : `<div class="state-empty" style="padding:12px 0"><p>Nenhuma conversão ainda.</p></div>`;
  } catch {}
}

// ── Painel histórico ──────────────────────────────────────────────────────
async function abrirPainel(id) {
  currentClientId = id;
  const c = allClients.find(x => x.id === id);
  if (!c) return;
  const nv = c.seller_name || c.seller?.name || '';
  document.getElementById('panel-avatar').textContent       = iniAvatar(c.name);
  document.getElementById('panel-avatar').style.background  = corAvatar(c.name);
  document.getElementById('panel-client-name').textContent  = c.name;
  document.getElementById('panel-client-info').textContent  = [c.phone, c.status, nv].filter(Boolean).join(' · ');
  document.getElementById('call-form').reset();
  document.getElementById('side-panel').classList.add('open');
  document.getElementById('panel-overlay').classList.add('open');
  await carregarTimeline(id);
}

async function carregarTimeline(id) {
  const el  = document.getElementById('timeline-container');
  const cnt = document.getElementById('history-count');
  el.innerHTML = `<div class="state-loading"><div class="spinner"></div></div>`;
  try {
    const hist = await fetchHistorico(id);
    if (cnt) cnt.textContent = hist.length ? `${hist.length} registro(s)` : '';
    if (!hist.length) {
      el.innerHTML = `<div class="state-empty" style="padding:12px 0"><p>Nenhum contato registrado ainda.</p></div>`;
      return;
    }
    const dotCls = r => ({
      'Comprou':'d-comprou','Falou':'d-falou','Nao atendeu':'d-nao-atendeu',
      'Nao tem interesse':'d-nao-int','WhatsApp enviado':'d-whatsapp','Caixa postal':'d-caixa'
    }[r] || '');
    const rCls = r => r==='Comprou'?'r-comprou':r==='Nao tem interesse'?'r-nao-int':r==='Nao atendeu'?'r-nao-at':'';
    el.innerHTML = `<div class="timeline">${hist.map(h => `
      <div class="tl-item">
        <div class="tl-dot ${dotCls(h.result)}"></div>
        <div class="tl-card">
          <div class="tl-meta">
            <span class="tl-date">${fmtDH(h.datetime)}</span>
            <span class="tl-seller">${h.seller?.name || '—'}</span>
          </div>
          <span class="tl-result ${rCls(h.result)}">${h.result}</span>
          ${h.notes ? `<div class="tl-notes">${h.notes}</div>` : ''}
          ${h.next_callback ? `<div class="tl-next">Próximo: <strong>${fmtData(h.next_callback)}</strong> (${fmtRelativo(h.next_callback)})</div>` : ''}
        </div>
      </div>`).join('')}</div>`;
  } catch (e) {
    el.innerHTML = `<div class="state-empty"><p style="color:var(--danger)">${e.message}</p></div>`;
  }
}

function fecharPainel() {
  document.getElementById('side-panel').classList.remove('open');
  document.getElementById('panel-overlay').classList.remove('open');
  currentClientId = null;
}

// ── Modal cliente ─────────────────────────────────────────────────────────
function abrirNovoCliente() {
  editingClientId = null;
  document.getElementById('modal-title').textContent    = 'Novo Cliente';
  document.getElementById('modal-save-btn').textContent = 'Criar Cliente';
  document.getElementById('client-form').reset();
  document.getElementById('field-status').value = 'Pendente';
  const errEl = document.getElementById('modal-save-error');
  if (errEl) errEl.textContent = '';
  atualizarSugestoes();
  document.getElementById('client-modal-overlay').classList.add('open');
  setTimeout(() => document.getElementById('field-name').focus(), 80);
}

function abrirEdicao(id) {
  const c = allClients.find(x => x.id === id);
  if (!c) return;
  editingClientId = id;
  document.getElementById('modal-title').textContent    = 'Editar Cliente';
  document.getElementById('modal-save-btn').textContent = 'Salvar Alterações';
  const errEl = document.getElementById('modal-save-error');
  if (errEl) errEl.textContent = '';
  atualizarSugestoes();
  document.getElementById('field-name').value          = c.name || '';
  document.getElementById('field-phone').value         = c.phone || '';
  document.getElementById('field-seller-name').value   = c.seller_name || c.seller?.name || '';
  document.getElementById('field-status').value        = c.status || 'Pendente';
  document.getElementById('field-callback-date').value = c.callback_date || '';
  document.getElementById('field-value').value         = c.estimated_value || '';
  document.getElementById('field-produto').value       = c.produto || '';
  document.getElementById('field-peso').value          = c.peso || '';
  document.getElementById('field-observation').value   = c.observation || '';
  document.getElementById('client-modal-overlay').classList.add('open');
}

function fecharModal() {
  document.getElementById('client-modal-overlay').classList.remove('open');
  editingClientId = null;
}

async function confirmarExclusao(id, nome) {
  confirmar(
    'Excluir cliente',
    `Tem certeza que deseja excluir "${nome}"? O histórico de contatos também será removido.`,
    async () => {
      try {
        await excluirCliente(id);
        allClients = allClients.filter(c => c.id !== id);
        try { localStorage.setItem('crm_clients', JSON.stringify(allClients)); } catch {}
        renderClientes();
        toast('Cliente excluído', `"${nome}" removido.`, 'success');
      } catch (e) {
        toast('Erro ao excluir', e.message, 'warning');
      }
    }
  );
}

// ── Inicialização ─────────────────────────────────────────────────────────
async function iniciar(user) {
  currentUser = user;

  // Carrega dados em cache imediatamente (instantâneo)
  try {
    const cached = localStorage.getItem('crm_clients');
    if (cached) {
      allClients = JSON.parse(cached);
      renderClientes();
    }
  } catch {}

  // Perfil do usuário
  try {
    currentProfile = await fetchMeuPerfil(user.id);
  } catch {
    currentProfile = { name: user.email.split('@')[0], role: 'vendedor' };
  }
  const nome = currentProfile?.name || user.email;
  document.getElementById('user-name-display').textContent = nome;
  document.getElementById('user-role-display').textContent = currentProfile?.role === 'admin' ? 'Admin' : 'Vendedor';
  document.getElementById('user-avatar').textContent       = iniAvatar(nome);
  document.getElementById('user-avatar').style.background  = corAvatar(nome);

  // Carrega perfis e clientes em paralelo
  const [rProf, rCli] = await Promise.allSettled([fetchPerfis(), fetchClientes()]);

  if (rCli.status === 'fulfilled') {
    allClients = rCli.value;
    try { localStorage.setItem('crm_clients', JSON.stringify(allClients)); } catch {}
  } else if (!allClients.length) {
    toast('Erro ao carregar clientes', rCli.reason?.message, 'warning');
  }

  if (rProf.status === 'fulfilled' && rProf.value.length > 0) {
    allProfiles = rProf.value;
  }

  atualizarSugestoes();
  renderClientes();

  // Alerta de vencidos
  const n = allClients.filter(c => vencido(c.callback_date) && c.status !== 'Comprou' && c.status !== 'Inativo').length;
  if (n > 0) toast(`${n} retorno(s) vencido(s)`, `${n} cliente(s) com data vencida ou para hoje.`, 'warning');
}

// ── Eventos ───────────────────────────────────────────────────────────────

// Login
document.getElementById('login-form').addEventListener('submit', async e => {
  e.preventDefault();
  const btn = document.getElementById('login-btn');
  const err = document.getElementById('login-error');
  btn.disabled = true; btn.textContent = 'Entrando...'; err.textContent = '';
  try {
    const { error } = await auth.auth.signInWithPassword({
      email:    document.getElementById('login-email').value.trim(),
      password: document.getElementById('login-password').value,
    });
    if (error) throw error;
  } catch (e) {
    err.textContent = e.message || 'Email ou senha incorretos.';
    btn.disabled = false; btn.textContent = 'Entrar';
  }
});

// Logout
document.getElementById('logout-btn').addEventListener('click', async () => {
  localStorage.removeItem('crm_clients');
  try { await Promise.race([auth.auth.signOut(), new Promise(r => setTimeout(r, 2000))]); } catch {}
  window.location.reload();
});

// Abas
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    document.getElementById(`${tab}-view`).classList.add('active');
    if (tab === 'dashboard') renderDashboard();
  });
});

// Ordenar
document.querySelectorAll('thead th.sortable').forEach(th => {
  th.addEventListener('click', () => {
    sortDir = sortCol === th.dataset.col && sortDir === 'asc' ? 'desc' : 'asc';
    sortCol = th.dataset.col;
    document.querySelectorAll('thead th.sortable').forEach(t => t.classList.remove('sort-asc','sort-desc'));
    th.classList.add('sort-' + sortDir);
    renderClientes();
  });
});

// Filtros
document.getElementById('search-input').addEventListener('input', renderClientes);
document.getElementById('status-filter').addEventListener('change', renderClientes);
document.getElementById('seller-filter').addEventListener('input', renderClientes);

// Botões principais
document.getElementById('add-client-btn').addEventListener('click', abrirNovoCliente);
document.getElementById('export-btn').addEventListener('click', exportarCSV);
document.getElementById('dash-refresh-btn').addEventListener('click', async () => {
  try { allClients = await fetchClientes(); renderDashboard(); toast('Atualizado', '', 'success'); } catch {}
});

// Modal
document.getElementById('modal-close-btn').addEventListener('click', fecharModal);
document.getElementById('modal-cancel-btn').addEventListener('click', fecharModal);
document.getElementById('client-modal-overlay').addEventListener('click', e => {
  if (e.target === e.currentTarget) fecharModal();
});

document.getElementById('client-form').addEventListener('submit', async e => {
  e.preventDefault();
  const btn   = document.getElementById('modal-save-btn');
  const errEl = document.getElementById('modal-save-error');
  btn.disabled = true; btn.textContent = 'Salvando...';
  if (errEl) errEl.textContent = '';
  try {
    const dados = {
      name:            document.getElementById('field-name').value.trim(),
      phone:           document.getElementById('field-phone').value.trim() || null,
      seller_name:     document.getElementById('field-seller-name').value.trim() || null,
      status:          document.getElementById('field-status').value,
      callback_date:   document.getElementById('field-callback-date').value || null,
      estimated_value: document.getElementById('field-value').value ? parseFloat(document.getElementById('field-value').value) : null,
      produto:         document.getElementById('field-produto').value.trim() || null,
      peso:            document.getElementById('field-peso').value.trim() || null,
      observation:     document.getElementById('field-observation').value.trim() || null,
    };
    await salvarCliente(dados, editingClientId);
    allClients = await fetchClientes();
    try { localStorage.setItem('crm_clients', JSON.stringify(allClients)); } catch {}
    renderClientes();
    fecharModal();
    toast(editingClientId ? 'Cliente atualizado' : 'Cliente criado', `"${dados.name}" salvo.`, 'success');
  } catch (e) {
    const msg = e.message || 'Erro ao salvar.';
    if (errEl) errEl.textContent = msg;
    toast('Erro ao salvar', msg, 'warning');
  } finally {
    btn.disabled = false;
    btn.textContent = editingClientId ? 'Salvar Alterações' : 'Criar Cliente';
  }
});

// Painel
document.getElementById('panel-close-btn').addEventListener('click', fecharPainel);
document.getElementById('panel-overlay').addEventListener('click', fecharPainel);

// Contato
document.getElementById('call-form').addEventListener('submit', async e => {
  e.preventDefault();
  if (!currentClientId) return;
  const resultado = document.getElementById('call-result').value;
  if (!resultado) { toast('Campo obrigatório', 'Selecione o resultado.', 'warning'); return; }
  const btn  = document.getElementById('call-submit-btn');
  const prox = document.getElementById('call-next-callback').value || null;
  btn.disabled = true; btn.textContent = 'Registrando...';
  try {
    await salvarContato({
      client_id:     currentClientId,
      seller_id:     currentUser.id,
      datetime:      new Date().toISOString(),
      result:        resultado,
      next_callback: prox,
      notes:         document.getElementById('call-notes').value.trim() || null,
    });
    const upd = {};
    if (resultado === 'Comprou')             upd.status = 'Comprou';
    else if (resultado === 'Nao tem interesse') upd.status = 'Nao comprou';
    else if (resultado === 'Ligar de volta') { upd.status = 'Em contato'; if (prox) upd.callback_date = prox; }
    else {
      const cl = allClients.find(c => c.id === currentClientId);
      if (cl?.status === 'Pendente') upd.status = 'Em contato';
      if (prox) upd.callback_date = prox;
    }
    if (Object.keys(upd).length) await salvarCliente(upd, currentClientId);
    allClients = await fetchClientes();
    try { localStorage.setItem('crm_clients', JSON.stringify(allClients)); } catch {}
    renderClientes();
    document.getElementById('call-form').reset();
    await carregarTimeline(currentClientId);
    toast('Contato registrado', '', 'success');
  } catch (e) {
    toast('Erro', e.message, 'warning');
  } finally {
    btn.disabled = false; btn.textContent = 'Registrar Contato';
  }
});

// ESC
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  if (document.getElementById('client-modal-overlay').classList.contains('open')) { fecharModal(); return; }
  if (document.getElementById('confirm-overlay').classList.contains('open'))      { fecharConfirm(); return; }
  if (document.getElementById('side-panel').classList.contains('open'))           { fecharPainel(); return; }
});

// ── Autenticação ──────────────────────────────────────────────────────────
function mostrarApp(session) {
  TOKEN = session.access_token;
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('app').style.display = 'flex';
}
function mostrarLogin() {
  TOKEN = ANON_KEY;
  document.getElementById('login-screen').style.display = 'flex';
  document.getElementById('app').style.display = 'none';
  currentUser = null; currentProfile = null;
  allClients = []; allProfiles = [];
}

auth.auth.onAuthStateChange(async (_event, session) => {
  if (session?.user) {
    mostrarApp(session);
    await iniciar(session.user);
  } else {
    mostrarLogin();
  }
});

(async () => {
  const { data: { session } } = await auth.auth.getSession();
  if (session?.user) {
    mostrarApp(session);
    await iniciar(session.user);
  }
})();
