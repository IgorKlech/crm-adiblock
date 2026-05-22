// ── Config ────────────────────────────────────────────────────────────────
const SUPABASE_URL      = 'https://kgiynhrytnzfdywgjhby.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnaXluaHJ5dG56ZmR5d2dqaGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0Mzc0NzUsImV4cCI6MjA5NTAxMzQ3NX0.8cOWLAsJyXAzid5ce73FUI-HVVYJoWyfOC3pSKci6Vs';

// Pega o fetch original via iframe — bypassa a interceptação do Vercel
// O iframe fica no DOM para o contexto não ser destruído
let _iframe = null;
function getCleanFetch() {
  try {
    _iframe = document.createElement('iframe');
    _iframe.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:0;height:0;border:0';
    document.body.appendChild(_iframe); // Mantém no DOM
    if (!_iframe.contentWindow?.fetch) return window.fetch.bind(window);
    return _iframe.contentWindow.fetch.bind(window); // bind ao window principal
  } catch { return window.fetch.bind(window); }
}

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { fetch: getCleanFetch() },
  auth:   { persistSession: true, autoRefreshToken: true },
});

// ── Estado ────────────────────────────────────────────────────────────────
let currentUser     = null;
let currentProfile  = null;
let allClients      = [];
let allProfiles     = [];
let currentClientId = null;
let editingClientId = null;
let sortCol         = 'created_at';
let sortDir         = 'desc';
let confirmCb       = null;

// Nomes conhecidos dos vendedores (fallback para autocomplete)
const VENDEDORES = ['Igor','Nádia','Letícia','Gracielle'];

function atualizarSugestoes() {
  const dl = document.getElementById('sellers-list');
  if (!dl) return;
  const nomes = allProfiles.length > 0
    ? allProfiles.map(p => p.name)
    : VENDEDORES;
  dl.innerHTML = nomes.map(n => `<option value="${n}">`).join('');
}

// ── Avatares ─────────────────────────────────────────────────────────────
const CORES = ['#1F4E78','#0891b2','#7c3aed','#059669','#dc2626','#d97706','#0284c7','#c026d3'];
const cor    = n => CORES[(n||'A').toUpperCase().charCodeAt(0) % CORES.length];
const ini    = n => (n||'?')[0].toUpperCase();

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
  if (diff < -1)  return `${Math.abs(diff)}d atrás`;
  return `em ${diff}d`;
}

function fmtDH(dt) {
  if (!dt) return '—';
  return new Date(dt).toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',year:'2-digit',hour:'2-digit',minute:'2-digit'});
}

function fmtMoeda(v) {
  if (v == null || v === '') return '—';
  return Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
}

function badgeStatus(s) {
  const m = {
    'Pendente':'pendente','Em contato':'em-contato',
    'Comprou':'comprou','Nao comprou':'nao-comprou','Inativo':'inativo'
  };
  return `<span class="badge badge-${m[s]||'pendente'}">${s}</span>`;
}

function dotHistorico(r) {
  const m = {'Comprou':'d-comprou','Falou':'d-falou','Nao atendeu':'d-nao-atendeu',
    'Nao tem interesse':'d-nao-int','WhatsApp enviado':'d-whatsapp','Caixa postal':'d-caixa'};
  return m[r]||'';
}

function badgeHistorico(r) {
  if (r==='Comprou') return 'r-comprou';
  if (r==='Nao tem interesse') return 'r-nao-int';
  if (r==='Nao atendeu') return 'r-nao-at';
  return '';
}

// ── Toast ─────────────────────────────────────────────────────────────────
const SVG = {
  ok:   `<svg viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>`,
  warn: `<svg viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>`,
  info: `<svg viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>`,
};

function toast(titulo, msg='', tipo='info') {
  const c = document.getElementById('toast-container');
  const t = document.createElement('div');
  t.className = `toast ${tipo==='success'?'t-success':tipo==='warning'?'t-warning':''}`;
  t.innerHTML = `${SVG[tipo==='success'?'ok':tipo==='warning'?'warn':'info']}
    <div class="toast-body"><div class="toast-title">${titulo}</div>${msg?`<div class="toast-msg">${msg}</div>`:''}</div>
    <button class="toast-close" onclick="this.closest('.toast').remove()">&#x2715;</button>`;
  c.appendChild(t);
  setTimeout(() => t?.parentNode && t.remove(), tipo==='warning'?10000:5000);
}

// ── Confirm ───────────────────────────────────────────────────────────────
function confirmar(titulo, msg, cb) {
  document.getElementById('confirm-title').textContent = titulo;
  document.getElementById('confirm-msg').textContent   = msg;
  document.getElementById('confirm-overlay').classList.add('open');
  confirmCb = cb;
}
function fecharConfirm() {
  document.getElementById('confirm-overlay').classList.remove('open');
  confirmCb = null;
}
document.getElementById('confirm-ok').addEventListener('click', () => { fecharConfirm(); if(confirmCb) confirmCb(); });
document.getElementById('confirm-cancel').addEventListener('click', fecharConfirm);

// ── DB via SDK ────────────────────────────────────────────────────────────
async function dbFetch(fn) {
  const { data, error } = await fn();
  if (error) throw error;
  return data || [];
}

async function fetchClientes() {
  return dbFetch(() =>
    db.from('clients').select('*, seller:profiles(id,name)').order('created_at', { ascending: false })
  );
}

async function fetchPerfis() {
  return dbFetch(() => db.from('profiles').select('id,name,role,email').order('name'));
}

async function salvarCliente(dados, id=null) {
  if (id) {
    const { data, error } = await db.from('clients').update(dados).eq('id',id).select().single();
    if (error) throw error;
    return data;
  }
  const { data, error } = await db.from('clients').insert([dados]).select().single();
  if (error) throw error;
  return data;
}

async function excluirCliente(id) {
  const { data, error } = await db.from('clients').delete().eq('id', id).select('id');
  if (error) throw error;
  if (!data || data.length === 0) throw new Error('Sem permissão para excluir. Verifique se está logado.');
}

async function fetchHistorico(clienteId) {
  return dbFetch(() =>
    db.from('call_history').select('*, seller:profiles(id,name)').eq('client_id',clienteId).order('datetime',{ascending:false})
  );
}

async function salvarContato(dados) {
  const { data, error } = await db.from('call_history').insert([dados]).select().single();
  if (error) throw error;
  return data;
}

// ── Ordenação ─────────────────────────────────────────────────────────────
function ordenar(lista) {
  return [...lista].sort((a,b) => {
    let va = a[sortCol], vb = b[sortCol];
    if (sortCol==='seller_name') { va=a.seller?.name; vb=b.seller?.name; }
    if (va==null&&vb==null) return 0;
    if (va==null) return 1; if (vb==null) return -1;
    const c = String(va).toLowerCase() < String(vb).toLowerCase() ? -1 : 1;
    return sortDir==='asc' ? c : -c;
  });
}

function atualizarCabecalhos() {
  document.querySelectorAll('thead th.sortable').forEach(th => {
    th.classList.remove('sort-asc','sort-desc');
    if (th.dataset.col===sortCol) th.classList.add(`sort-${sortDir}`);
  });
}

// ── Filtros ───────────────────────────────────────────────────────────────
function filtrados() {
  const q  = (document.getElementById('search-input').value||'').toLowerCase();
  const sf = document.getElementById('status-filter').value;
  const vf = (document.getElementById('seller-filter').value||'').toLowerCase();
  return allClients.filter(c => {
    const sellerNome = (c.seller_name || c.seller?.name || '').toLowerCase();
    return ((c.name||'').toLowerCase().includes(q)||(c.phone||'').includes(q)) &&
      (!sf||c.status===sf) &&
      (!vf||sellerNome.includes(vf));
  });
}

// ── CSV ───────────────────────────────────────────────────────────────────
function exportarCSV() {
  const rows = filtrados();
  if (!rows.length) { toast('Nada para exportar','Sem clientes com os filtros atuais.','warning'); return; }
  const h = ['Nome','Telefone','Vendedor','Status','Produto','Peso','Data Retorno','Valor','Observacao'];
  const l = rows.map(c => [
    c.name, c.phone||'', c.seller?.name||'', c.status,
    c.produto||'', c.peso||'', c.callback_date||'',
    c.estimated_value||'', (c.observation||'').replace(/\n/g,' ')
  ].map(v => `"${String(v).replace(/"/g,'""')}"`).join(','));
  const csv = [h.join(','),...l].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿'+csv],{type:'text/csv;charset=utf-8'}));
  a.download = `clientes_${hoje()}.csv`;
  a.click();
  toast('Exportado!',`${rows.length} cliente(s).`,'success');
}

// ── Render clientes ───────────────────────────────────────────────────────
function renderClientes() {
  const lista = ordenar(filtrados());
  const total = allClients.length;
  document.getElementById('clients-subtitle').textContent =
    lista.length===total ? `${total} cliente(s)` : `${lista.length} de ${total}`;

  const tbody = document.getElementById('clients-tbody');
  if (!lista.length) {
    tbody.innerHTML = `<tr><td colspan="7"><div class="state-empty"><h3>Nenhum cliente encontrado</h3><p>Ajuste os filtros ou cadastre um novo.</p></div></td></tr>`;
    return;
  }

  tbody.innerHTML = lista.map(c => {
    const over = vencido(c.callback_date);
    const dataCell = c.callback_date
      ? `${fmtData(c.callback_date)} <small style="color:var(--muted)">(${fmtRelativo(c.callback_date)})</small>${over?`<span class="overdue-badge">Vencido</span>`:''}`
      : '—';
    const nomeVendedor = c.seller_name || c.seller?.name || '';
    const vendedor = nomeVendedor
      ? `<div class="seller-chip"><div class="seller-avatar" style="background:${cor(nomeVendedor)}">${ini(nomeVendedor)}</div>${nomeVendedor}</div>`
      : `<span style="color:var(--muted)">—</span>`;
    const prodInfo = [c.produto, c.peso].filter(Boolean).join(' · ');
    return `<tr class="${over?'overdue':''}" data-id="${c.id}">
      <td><strong>${c.name}</strong>${prodInfo?`<div class="prod-info">${prodInfo}</div>`:''}</td>
      <td class="td-phone">${c.phone||'—'}</td>
      <td>${vendedor}</td>
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
  const comprou = allClients.filter(c=>c.status==='Comprou').length;
  const pend    = allClients.filter(c=>c.status==='Pendente').length;
  const vencidos = allClients.filter(c=>vencido(c.callback_date)&&c.status!=='Comprou'&&c.status!=='Inativo');

  const pct = v => total ? Math.round(v/total*100) : 0;

  document.getElementById('stat-total').textContent   = total;
  document.getElementById('stat-bought').textContent  = comprou;
  document.getElementById('stat-pending').textContent = pend;
  document.getElementById('stat-overdue').textContent = vencidos.length;
  document.getElementById('stat-bought-bar').style.width  = pct(comprou)+'%';
  document.getElementById('stat-pending-bar').style.width = pct(pend)+'%';
  document.getElementById('overdue-badge').textContent = vencidos.length;

  const oel = document.getElementById('overdue-list');
  oel.innerHTML = vencidos.length
    ? vencidos.slice(0,10).map(c=>`
        <div class="alert-row">
          <div class="alert-dot"></div>
          <div>
            <div class="alert-name">${c.name}</div>
            <div class="alert-sub">${c.seller?.name||'Sem vendedor'} — ${fmtData(c.callback_date)} (${fmtRelativo(c.callback_date)})</div>
          </div>
        </div>`).join('')
    : `<div class="state-empty" style="padding:16px 0"><p>Nenhum retorno vencido!</p></div>`;

  try {
    const { data: hist } = await db.from('call_history').select('seller_id, seller:profiles(name)').eq('result','Comprou');
    const counts={}, names={};
    (hist||[]).forEach(h=>{
      counts[h.seller_id]=(counts[h.seller_id]||0)+1;
      if(h.seller) names[h.seller_id]=h.seller.name;
    });
    const top3  = Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,3);
    const max   = top3[0]?.[1]||1;
    const medal = ['p1','p2','p3'];
    document.getElementById('ranking-list').innerHTML = top3.length
      ? top3.map(([sid,n],i)=>`
          <div class="rank-row">
            <div class="rank-pos ${medal[i]}">${i+1}</div>
            <div class="rank-bar-wrap">
              <div class="rank-name">${names[sid]||'Desconhecido'}</div>
              <div class="rank-bar"><div class="rank-bar-fill" style="width:${Math.round(n/max*100)}%"></div></div>
            </div>
            <div><div class="rank-conv">${n}</div><div class="rank-unit">vendas</div></div>
          </div>`).join('')
      : `<div class="state-empty" style="padding:16px 0"><p>Nenhuma conversão registrada.</p></div>`;
  } catch {}
}

// ── Painel lateral ────────────────────────────────────────────────────────
async function abrirPainel(id) {
  currentClientId = id;
  const c = allClients.find(x=>x.id===id);
  if (!c) return;
  document.getElementById('panel-avatar').textContent        = ini(c.name);
  document.getElementById('panel-avatar').style.background  = cor(c.name);
  document.getElementById('panel-client-name').textContent   = c.name;
  document.getElementById('panel-client-info').textContent   =
    [c.phone, c.status, c.seller?.name].filter(Boolean).join(' · ');
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
    cnt.textContent = hist.length ? `${hist.length} registro(s)` : '';
    if (!hist.length) {
      el.innerHTML = `<div class="state-empty" style="padding:12px 0"><p>Nenhum contato registrado ainda.</p></div>`;
      return;
    }
    el.innerHTML = `<div class="timeline">${hist.map(h=>`
      <div class="tl-item">
        <div class="tl-dot ${dotHistorico(h.result)}"></div>
        <div class="tl-card">
          <div class="tl-meta">
            <span class="tl-date">${fmtDH(h.datetime)}</span>
            <span class="tl-seller">${h.seller?.name||'—'}</span>
          </div>
          <span class="tl-result ${badgeHistorico(h.result)}">${h.result}</span>
          ${h.notes?`<div class="tl-notes">${h.notes}</div>`:''}
          ${h.next_callback?`<div class="tl-next">Próximo: <strong>${fmtData(h.next_callback)}</strong> (${fmtRelativo(h.next_callback)})</div>`:''}
        </div>
      </div>`).join('')}</div>`;
  } catch(e) {
    el.innerHTML = `<div class="state-empty"><p style="color:var(--danger)">${e.message}</p></div>`;
  }
}

function fecharPainel() {
  document.getElementById('side-panel').classList.remove('open');
  document.getElementById('panel-overlay').classList.remove('open');
  currentClientId = null;
}

// ── Modal cliente ─────────────────────────────────────────────────────────
function preencherVendedores(ids) {
  ids.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    const cur = el.value;
    const def = id==='field-seller'?'<option value="">Sem vendedor</option>':'<option value="">Todos os vendedores</option>';
    el.innerHTML = def + allProfiles.map(p=>`<option value="${p.id}">${p.name}</option>`).join('');
    if (cur) el.value = cur;
  });
}

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
  const c = allClients.find(x=>x.id===id);
  if (!c) return;
  editingClientId = id;
  document.getElementById('modal-title').textContent    = 'Editar Cliente';
  document.getElementById('modal-save-btn').textContent = 'Salvar Alterações';
  const errEl = document.getElementById('modal-save-error');
  if (errEl) errEl.textContent = '';
  atualizarSugestoes();
  document.getElementById('field-name').value          = c.name||'';
  document.getElementById('field-phone').value         = c.phone||'';
  document.getElementById('field-seller-name').value   = c.seller_name || c.seller?.name || '';
  document.getElementById('field-status').value        = c.status||'Pendente';
  document.getElementById('field-callback-date').value = c.callback_date||'';
  document.getElementById('field-value').value         = c.estimated_value||'';
  document.getElementById('field-produto').value       = c.produto||'';
  document.getElementById('field-peso').value          = c.peso||'';
  document.getElementById('field-observation').value   = c.observation||'';
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
        allClients = allClients.filter(c=>c.id!==id);
        renderClientes();
        toast('Cliente excluído',`"${nome}" foi removido.`,'success');
      } catch(e) {
        toast('Erro ao excluir', e.message, 'warning');
      }
    }
  );
}

// ── Notificação vencidos ───────────────────────────────────────────────────
function notificarVencidos() {
  const n = allClients.filter(c=>vencido(c.callback_date)&&c.status!=='Comprou'&&c.status!=='Inativo').length;
  if (n>0) toast(`${n} retorno(s) vencido(s)`,`Você tem ${n} cliente(s) com data vencida ou para hoje.`,'warning');
}

// ── Init ──────────────────────────────────────────────────────────────────
async function iniciar(user, token) {
  currentUser = user;

  // Carrega perfil do usuário logado
  try {
    const { data } = await db.from('profiles').select('*').eq('id',user.id).single();
    currentProfile = data;
  } catch {
    currentProfile = { name: user.email.split('@')[0], role: 'vendedor' };
  }

  const nome = currentProfile?.name || user.email;
  document.getElementById('user-name-display').textContent = nome;
  document.getElementById('user-role-display').textContent = currentProfile?.role==='admin'?'Admin':'Vendedor';
  document.getElementById('user-avatar').textContent       = ini(nome);
  document.getElementById('user-avatar').style.background  = cor(nome);

  // Mostra dados em cache instantaneamente enquanto carrega do banco
  try {
    const cached = localStorage.getItem('crm_clients');
    if (cached) {
      allClients = JSON.parse(cached);
      renderClientes();
    }
  } catch {}

  // Carrega perfis e clientes em paralelo
  const [rProf, rCli] = await Promise.allSettled([fetchPerfis(), fetchClientes()]);

  if (rCli.status==='fulfilled') {
    allClients = rCli.value;
    try { localStorage.setItem('crm_clients', JSON.stringify(allClients)); } catch {}
  } else {
    console.error('fetchClientes:', rCli.reason?.message);
    if (!allClients.length) toast('Erro ao carregar clientes', rCli.reason?.message, 'warning');
  }

  if (rProf.status==='fulfilled' && rProf.value.length>0) {
    allProfiles = rProf.value;
  } else {
    const vistos = new Set();
    allProfiles = [];
    allClients.forEach(c => {
      const nm = c.seller_name || c.seller?.name;
      const id = c.seller?.id || nm;
      if (nm && id && !vistos.has(id)) {
        vistos.add(id);
        allProfiles.push({ id, name: nm, role:'vendedor' });
      }
    });
    allProfiles.sort((a,b)=>a.name.localeCompare(b.name));
  }

  atualizarSugestoes();
  renderClientes();
  notificarVencidos();
}

// ── Eventos ───────────────────────────────────────────────────────────────

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
  } catch(e) {
    err.textContent = e.message || 'Erro ao fazer login.';
    btn.disabled = false; btn.textContent = 'Entrar';
  }
});

// Logout
document.getElementById('logout-btn').addEventListener('click', async () => {
  try { await Promise.race([db.auth.signOut(), new Promise(r=>setTimeout(r,3000))]); } catch {}
  window.location.reload();
});

// Abas
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
    document.querySelectorAll('.view').forEach(v=>v.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    document.getElementById(`${tab}-view`).classList.add('active');
    if (tab==='dashboard') renderDashboard();
  });
});

// Ordenar colunas
document.querySelectorAll('thead th.sortable').forEach(th => {
  th.addEventListener('click', () => {
    const col = th.dataset.col;
    sortDir = sortCol===col && sortDir==='asc' ? 'desc' : 'asc';
    sortCol = col;
    atualizarCabecalhos();
    renderClientes();
  });
});

// Busca e filtros
document.getElementById('search-input').addEventListener('input', renderClientes);
document.getElementById('status-filter').addEventListener('change', renderClientes);
document.getElementById('seller-filter').addEventListener('change', renderClientes);

// Botões da tabela
document.getElementById('add-client-btn').addEventListener('click', abrirNovoCliente);
document.getElementById('export-btn').addEventListener('click', exportarCSV);
document.getElementById('dash-refresh-btn').addEventListener('click', async () => {
  allClients = await fetchClientes().catch(()=>allClients);
  renderDashboard();
  toast('Dashboard atualizado','','success');
});

// Modal cliente
document.getElementById('modal-close-btn').addEventListener('click', fecharModal);
document.getElementById('modal-cancel-btn').addEventListener('click', fecharModal);
document.getElementById('client-modal-overlay').addEventListener('click', e => {
  if (e.target===e.currentTarget) fecharModal();
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
      phone:           document.getElementById('field-phone').value.trim()||null,
      seller_name:     document.getElementById('field-seller-name').value.trim()||null,
      status:          document.getElementById('field-status').value,
      callback_date:   document.getElementById('field-callback-date').value||null,
      estimated_value: document.getElementById('field-value').value ? parseFloat(document.getElementById('field-value').value) : null,
      produto:         document.getElementById('field-produto').value.trim()||null,
      peso:            document.getElementById('field-peso').value.trim()||null,
      observation:     document.getElementById('field-observation').value.trim()||null,
    };
    await salvarCliente(dados, editingClientId);
    allClients = await fetchClientes();
    renderClientes();
    fecharModal();
    toast(editingClientId?'Cliente atualizado':'Cliente criado',`"${dados.name}" salvo com sucesso.`,'success');
  } catch(e) {
    const msg = e.message||'Erro ao salvar. Tente novamente.';
    if (errEl) errEl.textContent = msg;
    toast('Erro ao salvar', msg, 'warning');
  } finally {
    btn.disabled = false;
    btn.textContent = editingClientId?'Salvar Alterações':'Criar Cliente';
  }
});

// Painel lateral
document.getElementById('panel-close-btn').addEventListener('click', fecharPainel);
document.getElementById('panel-overlay').addEventListener('click', fecharPainel);

// Formulário de contato
document.getElementById('call-form').addEventListener('submit', async e => {
  e.preventDefault();
  if (!currentClientId) return;
  const resultado = document.getElementById('call-result').value;
  if (!resultado) { toast('Campo obrigatório','Selecione o resultado do contato.','warning'); return; }
  const btn  = document.getElementById('call-submit-btn');
  const prox = document.getElementById('call-next-callback').value||null;
  btn.disabled = true; btn.textContent = 'Registrando...';
  try {
    await salvarContato({
      client_id:     currentClientId,
      seller_id:     currentUser.id,
      datetime:      new Date().toISOString(),
      result:        resultado,
      next_callback: prox,
      notes:         document.getElementById('call-notes').value.trim()||null,
    });
    // Atualiza status do cliente automaticamente
    const upd = {};
    if (resultado==='Comprou')          upd.status='Comprou';
    else if (resultado==='Nao tem interesse') upd.status='Nao comprou';
    else if (resultado==='Ligar de volta') {
      upd.status='Em contato';
      if (prox) upd.callback_date=prox;
    } else {
      const cl = allClients.find(c=>c.id===currentClientId);
      if (cl?.status==='Pendente') upd.status='Em contato';
      if (prox) upd.callback_date=prox;
    }
    if (Object.keys(upd).length) await salvarCliente(upd, currentClientId);
    allClients = await fetchClientes();
    renderClientes();
    document.getElementById('call-form').reset();
    await carregarTimeline(currentClientId);
    toast('Contato registrado','Histórico atualizado.','success');
  } catch(e) {
    toast('Erro ao registrar', e.message, 'warning');
  } finally {
    btn.disabled = false; btn.textContent = 'Registrar Contato';
  }
});

// ESC fecha modais
document.addEventListener('keydown', e => {
  if (e.key!=='Escape') return;
  if (document.getElementById('client-modal-overlay').classList.contains('open')) { fecharModal(); return; }
  if (document.getElementById('confirm-overlay').classList.contains('open'))      { fecharConfirm(); return; }
  if (document.getElementById('side-panel').classList.contains('open'))           { fecharPainel(); return; }
});

// ── Auth ──────────────────────────────────────────────────────────────────
db.auth.onAuthStateChange(async (_event, session) => {
  if (session?.user) {
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
    await iniciar(session.user, session.access_token);
  } else {
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
    await iniciar(session.user, session.access_token);
  }
})();
