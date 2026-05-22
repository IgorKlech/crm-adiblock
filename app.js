// ── Config ────────────────────────────────────────────────────────────────
const SUPABASE_URL      = 'https://kgiynhrytnzfdywgjhby.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnaXluaHJ5dG56ZmR5d2dqaGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0Mzc0NzUsImV4cCI6MjA5NTAxMzQ3NX0.8cOWLAsJyXAzid5ce73FUI-HVVYJoWyfOC3pSKci6Vs';
const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── State ─────────────────────────────────────────────────────────────────
let currentUser     = null;
let currentProfile  = null;
let allClients      = [];
let allProfiles     = [];
let currentClientId = null;
let editingClientId = null;
let sortCol         = 'created_at';
let sortDir         = 'desc';
let confirmCb       = null;

// ── Palette for avatars ───────────────────────────────────────────────────
const PALETTE = ['#1F4E78','#0891b2','#7c3aed','#059669','#dc2626','#d97706','#0284c7','#c026d3'];
function avatarColor(name) {
  return PALETTE[(name || 'A').toUpperCase().charCodeAt(0) % PALETTE.length];
}
function avatarInitial(name) { return (name || '?')[0].toUpperCase(); }

// ── REST direto (bypassa o SDK p/ evitar conflito com scripts do Vercel) ──
let _authToken = SUPABASE_ANON_KEY;

async function api(method, path, body) {
  const headers = {
    'apikey':        SUPABASE_ANON_KEY,
    'Authorization': `Bearer ${_authToken}`,
    'Content-Type':  'application/json',
    'Prefer':        'return=representation',
  };
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: method || 'GET',
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    let msg = text;
    try { msg = JSON.parse(text).message || text; } catch {}
    throw new Error(msg);
  }
  try { return JSON.parse(text); } catch { return []; }
}

// ── Utils ─────────────────────────────────────────────────────────────────
function todayStr() { return new Date().toISOString().split('T')[0]; }

function isOverdue(d) { return !!d && d <= todayStr(); }

function fmtDate(d) {
  if (!d) return '—';
  const [y, m, dd] = d.split('-');
  return `${dd}/${m}/${y}`;
}

function fmtDateRelative(d) {
  if (!d) return '—';
  const today = todayStr();
  const diff  = Math.round((new Date(d) - new Date(today)) / 86400000);
  if (diff === 0)  return 'Hoje';
  if (diff === 1)  return 'Amanha';
  if (diff === -1) return 'Ontem';
  if (diff < -1)   return `${Math.abs(diff)}d atras`;
  return `em ${diff}d`;
}

function fmtDateTime(dt) {
  if (!dt) return '—';
  return new Date(dt).toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: '2-digit',
    hour: '2-digit', minute: '2-digit'
  });
}

function fmtCurrency(v) {
  if (v == null || v === '') return '—';
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function statusBadge(s) {
  const cls = {
    'Pendente':'pendente', 'Em contato':'em-contato',
    'Comprou':'comprou', 'Nao comprou':'nao-comprou', 'Inativo':'inativo'
  };
  return `<span class="badge badge-${cls[s] || 'pendente'}">${s}</span>`;
}

function dotClass(r) {
  const m = {
    'Comprou':'d-comprou','Falou':'d-falou','Nao atendeu':'d-nao-atendeu',
    'Nao tem interesse':'d-nao-int','WhatsApp enviado':'d-whatsapp','Caixa postal':'d-caixa'
  };
  return m[r] || '';
}

function resultClass(r) {
  if (r === 'Comprou')           return 'r-comprou';
  if (r === 'Nao tem interesse') return 'r-nao-int';
  if (r === 'Nao atendeu')       return 'r-nao-at';
  return '';
}

// ── Toast ─────────────────────────────────────────────────────────────────
const ICONS = {
  info:    `<svg class="toast-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>`,
  success: `<svg class="toast-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>`,
  warning: `<svg class="toast-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>`,
};

function toast(title, msg = '', type = 'info') {
  const c = document.getElementById('toast-container');
  const t = document.createElement('div');
  const cls = type === 'success' ? 't-success' : type === 'warning' ? 't-warning' : '';
  t.className = `toast ${cls}`;
  t.innerHTML = `
    ${ICONS[type] || ICONS.info}
    <div class="toast-body">
      <div class="toast-title">${title}</div>
      ${msg ? `<div class="toast-msg">${msg}</div>` : ''}
    </div>
    <button class="toast-close" onclick="this.closest('.toast').remove()">&#x2715;</button>`;
  c.appendChild(t);
  const delay = type === 'warning' ? 12000 : 5000;
  setTimeout(() => t && t.parentNode && t.remove(), delay);
}

// ── Confirm Dialog ────────────────────────────────────────────────────────
function showConfirm(title, msg, cb) {
  document.getElementById('confirm-title').textContent = title;
  document.getElementById('confirm-msg').textContent   = msg;
  document.getElementById('confirm-overlay').classList.add('open');
  confirmCb = cb;
}
function closeConfirm() {
  document.getElementById('confirm-overlay').classList.remove('open');
  confirmCb = null;
}
document.getElementById('confirm-ok').addEventListener('click', () => {
  closeConfirm();
  if (confirmCb) confirmCb();
});
document.getElementById('confirm-cancel').addEventListener('click', closeConfirm);

// ── Supabase DB via REST direto ────────────────────────────────────────────
async function fetchClients() {
  return api('GET', 'clients?select=*,seller:profiles(id,name)&order=created_at.desc');
}

async function fetchProfiles() {
  return api('GET', 'profiles?select=*&order=name');
}

async function saveClient(payload, id = null) {
  if (id) {
    const rows = await api('PATCH', `clients?id=eq.${id}&select=*`, payload);
    return Array.isArray(rows) ? rows[0] : rows;
  }
  const rows = await api('POST', 'clients?select=*', payload);
  return Array.isArray(rows) ? rows[0] : rows;
}

async function deleteClientById(id) {
  await api('DELETE', `clients?id=eq.${id}`);
}

async function fetchHistory(clientId) {
  return api('GET', `call_history?client_id=eq.${clientId}&select=*,seller:profiles(id,name)&order=datetime.desc`);
}

async function insertHistory(payload) {
  const rows = await api('POST', 'call_history?select=*', payload);
  return Array.isArray(rows) ? rows[0] : rows;
}

// ── Sort ──────────────────────────────────────────────────────────────────
function applySort(list) {
  return [...list].sort((a, b) => {
    let va = a[sortCol];
    let vb = b[sortCol];
    if (sortCol === 'seller_name') { va = a.seller?.name; vb = b.seller?.name; }
    if (va == null && vb == null) return 0;
    if (va == null) return 1;
    if (vb == null) return -1;
    const cmp = String(va).toLowerCase() < String(vb).toLowerCase() ? -1 : 1;
    return sortDir === 'asc' ? cmp : -cmp;
  });
}

function updateSortHeaders() {
  document.querySelectorAll('thead th.sortable').forEach(th => {
    th.classList.remove('sort-asc', 'sort-desc');
    if (th.dataset.col === sortCol) th.classList.add(`sort-${sortDir}`);
  });
}

// ── Filter ────────────────────────────────────────────────────────────────
function getFiltered() {
  const q  = (document.getElementById('search-input').value || '').toLowerCase();
  const sf = document.getElementById('status-filter').value;
  const vf = document.getElementById('seller-filter').value;
  return allClients.filter(c =>
    ((c.name || '').toLowerCase().includes(q) || (c.phone || '').includes(q)) &&
    (!sf || c.status === sf) &&
    (!vf || (c.seller && c.seller.id === vf))
  );
}

// ── CSV Export ────────────────────────────────────────────────────────────
function exportCSV() {
  const rows = getFiltered();
  if (!rows.length) { toast('Nada para exportar', 'Sem clientes com os filtros atuais.', 'warning'); return; }
  const headers = ['Nome','Telefone','Vendedor','Status','Produto','Peso','Data Retorno','Valor Estimado','Observacao'];
  const lines = rows.map(c => [
    c.name, c.phone||'', c.seller?.name||'', c.status,
    c.produto||'', c.peso||'', c.callback_date||'',
    c.estimated_value||'', (c.observation||'').replace(/\n/g,' ')
  ].map(v => `"${String(v).replace(/"/g,'""')}"`).join(','));
  const csv  = [headers.join(','), ...lines].join('\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url;
  a.download = `clientes_adiblock_${todayStr()}.csv`;
  a.click();
  URL.revokeObjectURL(url);
  toast('Exportado!', `${rows.length} cliente(s) exportados.`, 'success');
}

// ── Render Clients ────────────────────────────────────────────────────────
function renderClients() {
  const filtered = applySort(getFiltered());
  const total    = allClients.length;
  const shown    = filtered.length;

  document.getElementById('clients-subtitle').textContent =
    shown === total ? `${total} cliente(s) cadastrado(s)` : `Mostrando ${shown} de ${total}`;

  const tbody = document.getElementById('clients-tbody');
  if (!filtered.length) {
    tbody.innerHTML = `<tr><td colspan="7"><div class="state-empty"><h3>Nenhum cliente encontrado</h3><p>Tente ajustar a busca ou os filtros.</p></div></td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(c => {
    const over = isOverdue(c.callback_date);
    const relDate = c.callback_date
      ? `${fmtDate(c.callback_date)} <span style="color:var(--muted);font-size:11px">(${fmtDateRelative(c.callback_date)})</span>${over ? `<span class="overdue-badge">Vencido</span>` : ''}`
      : '—';

    const sellerCell = c.seller
      ? `<div class="seller-chip"><div class="seller-avatar" style="background:${avatarColor(c.seller.name)}">${avatarInitial(c.seller.name)}</div>${c.seller.name}</div>`
      : `<span style="color:var(--muted)">—</span>`;

    const prodLine = [c.produto, c.peso ? c.peso + ' kg' : ''].filter(Boolean).join(' · ');
    return `<tr class="${over ? 'overdue' : ''}" data-id="${c.id}">
      <td>
        <strong>${c.name}</strong>
        ${prodLine ? `<div style="font-size:11px;color:var(--muted);margin-top:2px">${prodLine}</div>` : ''}
      </td>
      <td class="td-phone">${c.phone || '—'}</td>
      <td>${sellerCell}</td>
      <td>${statusBadge(c.status)}</td>
      <td>${relDate}</td>
      <td>${fmtCurrency(c.estimated_value)}</td>
      <td><div class="actions-cell">
        <button class="btn btn-ghost btn-sm" onclick="openPanel('${c.id}')">Historico</button>
        <button class="btn btn-primary btn-sm" onclick="openEditModal('${c.id}')">Editar</button>
        <button class="btn btn-ghost btn-sm" style="color:var(--danger);border-color:var(--danger-mid)" onclick="doDelete('${c.id}','${(c.name||'').replace(/'/g,"\\'")}')">Excluir</button>
      </div></td>
    </tr>`;
  }).join('');
}

// ── Render Dashboard ──────────────────────────────────────────────────────
async function renderDashboard() {
  const total    = allClients.length;
  const bought   = allClients.filter(c => c.status === 'Comprou').length;
  const pending  = allClients.filter(c => c.status === 'Pendente').length;
  const overList = allClients.filter(c =>
    isOverdue(c.callback_date) && c.status !== 'Comprou' && c.status !== 'Inativo'
  );

  document.getElementById('stat-total').textContent   = total;
  document.getElementById('stat-bought').textContent  = bought;
  document.getElementById('stat-pending').textContent = pending;
  document.getElementById('stat-overdue').textContent = overList.length;

  const pct = v => total ? Math.round((v / total) * 100) : 0;
  document.getElementById('stat-bought-bar').style.width  = pct(bought)  + '%';
  document.getElementById('stat-pending-bar').style.width = pct(pending) + '%';

  document.getElementById('overdue-badge').textContent = overList.length;

  // Overdue list
  const oel = document.getElementById('overdue-list');
  oel.innerHTML = overList.length
    ? overList.slice(0, 10).map(c => `
        <div class="alert-row">
          <div class="alert-dot"></div>
          <div>
            <div class="alert-name">${c.name}</div>
            <div class="alert-sub">${c.seller ? c.seller.name : 'Sem vendedor'} &mdash; Retorno: ${fmtDate(c.callback_date)} (${fmtDateRelative(c.callback_date)})</div>
          </div>
        </div>`).join('')
    : `<div class="state-empty" style="padding:20px 0"><p>Sem retornos vencidos. Tudo em dia!</p></div>`;

  // Ranking
  const { data: hist } = await db
    .from('call_history')
    .select('seller_id, seller:profiles(name)')
    .eq('result', 'Comprou');

  const counts = {}, names = {};
  (hist || []).forEach(h => {
    counts[h.seller_id] = (counts[h.seller_id] || 0) + 1;
    if (h.seller) names[h.seller_id] = h.seller.name;
  });

  const top3   = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);
  const max    = top3[0]?.[1] || 1;
  const posClass = ['p1', 'p2', 'p3'];

  const rel = document.getElementById('ranking-list');
  rel.innerHTML = top3.length
    ? top3.map(([sid, n], i) => `
        <div class="rank-row">
          <div class="rank-pos ${posClass[i]}">${i + 1}</div>
          <div class="rank-bar-wrap">
            <div class="rank-name">${names[sid] || 'Desconhecido'}</div>
            <div class="rank-bar"><div class="rank-bar-fill" style="width:${Math.round((n/max)*100)}%"></div></div>
          </div>
          <div>
            <div class="rank-conv">${n}</div>
            <div class="rank-unit">vendas</div>
          </div>
        </div>`).join('')
    : `<div class="state-empty" style="padding:20px 0"><p>Nenhuma conversao registrada ainda.</p></div>`;
}

// ── Side Panel ────────────────────────────────────────────────────────────
async function openPanel(clientId) {
  currentClientId = clientId;
  const c = allClients.find(x => x.id === clientId);
  if (!c) return;

  const initial = avatarInitial(c.name);
  const color   = avatarColor(c.name);
  document.getElementById('panel-avatar').textContent            = initial;
  document.getElementById('panel-avatar').style.background       = color;
  document.getElementById('panel-client-name').textContent       = c.name;
  document.getElementById('panel-client-info').textContent =
    [c.phone, c.status, c.seller?.name].filter(Boolean).join(' · ');

  document.getElementById('call-form').reset();
  document.getElementById('side-panel').classList.add('open');
  document.getElementById('panel-overlay').classList.add('open');
  await loadTimeline(clientId);
}

async function loadTimeline(clientId) {
  const el   = document.getElementById('timeline-container');
  const cntEl = document.getElementById('history-count');
  el.innerHTML = `<div class="state-loading"><div class="spinner"></div></div>`;

  const hist = await fetchHistory(clientId);
  cntEl.textContent = hist.length ? `${hist.length} registro(s)` : '';

  if (!hist.length) {
    el.innerHTML = `<div class="state-empty" style="padding:16px 0"><p>Nenhum contato registrado ainda.</p></div>`;
    return;
  }

  el.innerHTML = `<div class="timeline">${hist.map(h => `
    <div class="tl-item">
      <div class="tl-dot ${dotClass(h.result)}"></div>
      <div class="tl-card">
        <div class="tl-meta">
          <span class="tl-date">${fmtDateTime(h.datetime)}</span>
          <span class="tl-seller">${h.seller ? h.seller.name : 'Desconhecido'}</span>
        </div>
        <span class="tl-result ${resultClass(h.result)}">${h.result}</span>
        ${h.notes ? `<div class="tl-notes">${h.notes}</div>` : ''}
        ${h.next_callback ? `<div class="tl-next">Proximo retorno: <strong>${fmtDate(h.next_callback)}</strong> (${fmtDateRelative(h.next_callback)})</div>` : ''}
      </div>
    </div>`).join('')}</div>`;
}

function closePanel() {
  document.getElementById('side-panel').classList.remove('open');
  document.getElementById('panel-overlay').classList.remove('open');
  currentClientId = null;
}

// ── Client Modal ──────────────────────────────────────────────────────────
function populateSellers(ids) {
  ids.forEach(id => {
    const el  = document.getElementById(id);
    if (!el) return;
    const cur = el.value;
    const def = id === 'field-seller' ? '<option value="">Sem vendedor</option>' : '<option value="">Todos os vendedores</option>';
    el.innerHTML = def + allProfiles.map(p => `<option value="${p.id}">${p.name}</option>`).join('');
    if (cur) el.value = cur;
  });
}

function openAddModal() {
  editingClientId = null;
  document.getElementById('modal-title').textContent    = 'Novo Cliente';
  document.getElementById('modal-save-btn').textContent = 'Criar Cliente';
  document.getElementById('client-form').reset();
  document.getElementById('field-status').value = 'Pendente';
  const errEl = document.getElementById('modal-save-error');
  if (errEl) errEl.textContent = '';
  populateSellers(['field-seller']);
  document.getElementById('client-modal-overlay').classList.add('open');
  setTimeout(() => document.getElementById('field-name').focus(), 80);
}

function openEditModal(clientId) {
  const c = allClients.find(x => x.id === clientId);
  if (!c) return;
  editingClientId = clientId;
  document.getElementById('modal-title').textContent    = 'Editar Cliente';
  document.getElementById('modal-save-btn').textContent = 'Salvar Alteracoes';
  const errEl = document.getElementById('modal-save-error');
  if (errEl) errEl.textContent = '';
  populateSellers(['field-seller']);
  document.getElementById('field-name').value          = c.name || '';
  document.getElementById('field-phone').value         = c.phone || '';
  document.getElementById('field-seller').value        = c.seller_id || '';
  document.getElementById('field-status').value        = c.status || 'Pendente';
  document.getElementById('field-callback-date').value = c.callback_date || '';
  document.getElementById('field-value').value         = c.estimated_value || '';
  document.getElementById('field-produto').value       = c.produto || '';
  document.getElementById('field-peso').value          = c.peso || '';
  document.getElementById('field-observation').value   = c.observation || '';
  document.getElementById('client-modal-overlay').classList.add('open');
}

function closeModal() {
  document.getElementById('client-modal-overlay').classList.remove('open');
  editingClientId = null;
}

async function doDelete(id, name) {
  showConfirm(
    'Excluir cliente',
    `Tem certeza que deseja excluir "${name}"? Esta acao nao pode ser desfeita e o historico de contatos tambem sera removido.`,
    async () => {
      try {
        await deleteClientById(id);
        allClients = allClients.filter(c => c.id !== id);
        renderClients();
        toast('Cliente excluido', `"${name}" foi removido com sucesso.`);
      } catch (err) {
        toast('Erro ao excluir', err.message, 'warning');
      }
    }
  );
}

// ── Debug badge ───────────────────────────────────────────────────────────
function updateDebugBadge(msg) {
  const el = document.getElementById('debug-badge');
  if (!el) return;
  el.textContent = msg || `${allProfiles.length} vendedor(es) | ${allClients.length} cliente(s)`;
  el.style.display = 'block';
}

// ── Overdue notification on login ─────────────────────────────────────────
function checkOverdueNotification() {
  const n = allClients.filter(c =>
    isOverdue(c.callback_date) && c.status !== 'Comprou' && c.status !== 'Inativo'
  ).length;
  if (n > 0)
    toast(
      `${n} retorno(s) vencido(s)`,
      `Voce tem ${n} cliente(s) com data de retorno vencida ou para hoje.`,
      'warning'
    );
}

// ── Teste direto de conexao ───────────────────────────────────────────────
async function testeConexao(token) {
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/profiles?select=id,name&limit=10`, {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${token}`,
      }
    });
    const json = await res.json();
    updateDebugBadge(`Fetch direto: ${res.status} | ${JSON.stringify(json).slice(0,80)}`);
  } catch(e) {
    updateDebugBadge(`Fetch direto ERRO: ${e.message}`);
  }
}

// ── Init App ──────────────────────────────────────────────────────────────
async function initApp(user) {
  currentUser = user;

  // Salva o token para uso nas queries diretas
  const { data: sessionData } = await db.auth.getSession();
  _authToken = sessionData?.session?.access_token || SUPABASE_ANON_KEY;
  testeConexao(_authToken);

  // Load profile
  try {
    const { data } = await db.from('profiles').select('*').eq('id', user.id).single();
    currentProfile = data;
  } catch {
    currentProfile = { name: user.email.split('@')[0], role: 'vendedor' };
  }

  const name = currentProfile?.name || user.email;
  document.getElementById('user-name-display').textContent = name;
  document.getElementById('user-role-display').textContent = currentProfile?.role === 'admin' ? 'Admin' : 'Vendedor';
  document.getElementById('user-avatar').textContent        = avatarInitial(name);
  document.getElementById('user-avatar').style.background   = avatarColor(name);

  // Carrega perfis e clientes em paralelo
  const [profResult, cliResult] = await Promise.allSettled([fetchProfiles(), fetchClients()]);

  if (profResult.status === 'fulfilled') {
    allProfiles = profResult.value;
    populateSellers(['seller-filter', 'field-seller']);
    updateDebugBadge();
  } else {
    console.error('fetchProfiles:', profResult.reason?.message);
    toast('Erro ao carregar vendedores', profResult.reason?.message, 'warning');
  }

  if (cliResult.status === 'fulfilled') {
    allClients = cliResult.value;
    renderClients();
    checkOverdueNotification();
    updateDebugBadge();
  } else {
    console.error('fetchClients:', cliResult.reason?.message);
    document.getElementById('clients-tbody').innerHTML =
      `<tr><td colspan="7"><div class="state-empty"><h3>Erro ao carregar clientes</h3><p style="color:var(--danger)">${cliResult.reason?.message}</p></div></td></tr>`;
    toast('Erro de banco de dados', cliResult.reason?.message, 'warning');
  }
}

// ── Events ────────────────────────────────────────────────────────────────

// Login
document.getElementById('login-form').addEventListener('submit', async e => {
  e.preventDefault();
  const btn = document.getElementById('login-btn');
  const err = document.getElementById('login-error');
  btn.disabled = true; btn.textContent = 'Entrando...'; err.textContent = '';
  try {
    const { error } = await db.auth.signInWithPassword({
      email:    document.getElementById('login-email').value.trim(),
      password: document.getElementById('login-password').value,
    });
    if (error) throw error;
  } catch (e) {
    err.textContent = e.message || 'Erro ao fazer login.';
    btn.disabled = false; btn.textContent = 'Entrar';
  }
});

// Logout
document.getElementById('logout-btn').addEventListener('click', async () => {
  try { await Promise.race([db.auth.signOut(), new Promise(r => setTimeout(r, 3000))]); } catch {}
  _authToken = SUPABASE_ANON_KEY;
  window.location.reload();
});

// Tabs
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

// Sort columns
document.querySelectorAll('thead th.sortable').forEach(th => {
  th.addEventListener('click', () => {
    const col = th.dataset.col;
    if (sortCol === col) {
      sortDir = sortDir === 'asc' ? 'desc' : 'asc';
    } else {
      sortCol = col; sortDir = 'asc';
    }
    updateSortHeaders();
    renderClients();
  });
});

// Search & filters
document.getElementById('search-input').addEventListener('input', renderClients);
document.getElementById('status-filter').addEventListener('change', renderClients);
document.getElementById('seller-filter').addEventListener('change', renderClients);

// Add client
document.getElementById('add-client-btn').addEventListener('click', openAddModal);
document.getElementById('modal-close-btn').addEventListener('click', closeModal);
document.getElementById('modal-cancel-btn').addEventListener('click', closeModal);
document.getElementById('client-modal-overlay').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeModal();
});

// Client form submit
document.getElementById('client-form').addEventListener('submit', async e => {
  e.preventDefault();
  const btn      = document.getElementById('modal-save-btn');
  const errorEl  = document.getElementById('modal-save-error');
  btn.disabled = true; btn.textContent = 'Salvando...'; errorEl.textContent = '';

  try {
    const payload = {
      name:            document.getElementById('field-name').value.trim(),
      phone:           document.getElementById('field-phone').value.trim() || null,
      seller_id:       document.getElementById('field-seller').value || null,
      status:          document.getElementById('field-status').value,
      callback_date:   document.getElementById('field-callback-date').value || null,
      estimated_value: document.getElementById('field-value').value ? parseFloat(document.getElementById('field-value').value) : null,
      produto:         document.getElementById('field-produto').value.trim() || null,
      peso:            document.getElementById('field-peso').value.trim() || null,
      observation:     document.getElementById('field-observation').value.trim() || null,
    };

    await saveClient(payload, editingClientId);
    allClients = await fetchClients();
    renderClients();
    closeModal();
    toast(
      editingClientId ? 'Cliente atualizado' : 'Cliente criado',
      `"${payload.name}" foi ${editingClientId ? 'atualizado' : 'adicionado'} com sucesso.`,
      'success'
    );
  } catch (err) {
    console.error('saveClient:', err);
    const msg = err.message || 'Erro desconhecido. Tente novamente.';
    errorEl.textContent = msg;
    toast('Erro ao salvar', msg, 'warning');
  } finally {
    btn.disabled = false;
    btn.textContent = editingClientId ? 'Salvar Alteracoes' : 'Criar Cliente';
  }
});

// Panel
document.getElementById('panel-close-btn').addEventListener('click', closePanel);
document.getElementById('panel-overlay').addEventListener('click', closePanel);

// Call form
document.getElementById('call-form').addEventListener('submit', async e => {
  e.preventDefault();
  if (!currentClientId) return;

  const result = document.getElementById('call-result').value;
  if (!result) { toast('Campo obrigatorio', 'Selecione o resultado do contato.', 'warning'); return; }

  const btn  = document.getElementById('call-submit-btn');
  const nextCb = document.getElementById('call-next-callback').value || null;
  btn.disabled = true; btn.textContent = 'Registrando...';

  try {
    await insertHistory({
      client_id:     currentClientId,
      seller_id:     currentUser.id,
      datetime:      new Date().toISOString(),
      result,
      next_callback: nextCb,
      notes:         document.getElementById('call-notes').value.trim() || null,
    });

    // Auto-update client status
    const updates = {};
    if (result === 'Comprou') {
      updates.status = 'Comprou';
    } else if (result === 'Nao tem interesse') {
      updates.status = 'Nao comprou';
    } else if (result === 'Ligar de volta') {
      updates.status = 'Em contato';
      if (nextCb) updates.callback_date = nextCb;
    } else {
      const cl = allClients.find(c => c.id === currentClientId);
      if (cl && cl.status === 'Pendente') updates.status = 'Em contato';
      if (nextCb) updates.callback_date = nextCb;
    }

    if (Object.keys(updates).length) await saveClient(updates, currentClientId);

    allClients = await fetchClients();
    renderClients();
    document.getElementById('call-form').reset();
    await loadTimeline(currentClientId);
    toast('Contato registrado', 'Historico atualizado com sucesso.', 'success');
  } catch (err) {
    console.error('insertHistory:', err);
    toast('Erro ao registrar', err.message, 'warning');
  } finally {
    btn.disabled = false; btn.textContent = 'Registrar Contato';
  }
});

// Export
document.getElementById('export-btn').addEventListener('click', exportCSV);

// Dashboard refresh
document.getElementById('dash-refresh-btn').addEventListener('click', async () => {
  allClients = await fetchClients();
  renderDashboard();
  toast('Dashboard atualizado', '', 'success');
});

// ESC key closes modals and panel
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  if (document.getElementById('client-modal-overlay').classList.contains('open')) { closeModal(); return; }
  if (document.getElementById('confirm-overlay').classList.contains('open')) { closeConfirm(); return; }
  if (document.getElementById('side-panel').classList.contains('open')) { closePanel(); return; }
});

// ── Auth state ────────────────────────────────────────────────────────────
db.auth.onAuthStateChange(async (_event, session) => {
  if (session?.user) {
    _authToken = session.access_token || SUPABASE_ANON_KEY;
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
    await initApp(session.user);
  } else {
    _authToken = SUPABASE_ANON_KEY;
    document.getElementById('login-screen').style.display = 'flex';
    document.getElementById('app').style.display = 'none';
    currentUser = null; currentProfile = null;
    allClients = []; allProfiles = [];
  }
});

(async () => {
  const { data: { session } } = await db.auth.getSession();
  if (session?.user) {
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
    await initApp(session.user);
  }
})();
