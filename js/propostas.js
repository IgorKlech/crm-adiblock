/* ==========================================================================
   propostas.js — a aba Propostas e o ciclo de vida de um pedido.
   Sprint 8.1e (modularizacao), 17/08/2026.

   Um dominio so, do comeco ao fim:
     lista e filtros      PR_STATUS, PR_PERIODO, renderPropostas, totalProposta
     mudanca de status    em_andamento -> pedido -> expedido | cancelada
     o pedido fechando    finalizarComoPedido, a pergunta da OC, expedicao
     revisao              o editor (EDP_*) e o historico de revisoes

   No index.html isto ja era contiguo — a extracao so tirou 640 linhas de um
   arquivo de 5.360 sem reorganizar nada. Fronteira boa vale mais que volume:
   e o mesmo motivo pelo qual documentos.js rendeu 9% num passo.

   CARREGA DEPOIS de documentos.js: usa renderCotacao(), fecharCotacao() e o
   `let PROP_ATUAL` que moram la. Como sempre, so em tempo de EXECUCAO — nada
   aqui le nada no carregamento, fora os tres addEventListener do fim, todos
   com `?.` de proposito.
   ========================================================================== */

// ── Sprint 6.5: Lista de Propostas (Em andamento / Pedidos / Canceladas) ─
let PR_STATUS = 'em_andamento';
let PR_PERIODO = 0; // 0 = todos; 30/60/90 dias; ou 'custom'

function setPrStatus(s) {
  PR_STATUS = s;
  document.querySelectorAll('#pr-tabs .td-sw').forEach(b => b.classList.toggle('ac', b.dataset.st === s));
  renderPropostas();
}

// Sprint 9.2: filtro de periodo da aba Propostas
function setPrPeriodo(v) {
  PR_PERIODO = v === 'custom' ? 'custom' : (parseInt(v, 10) || 0);
  const custom = document.getElementById('pr-custom');
  if (custom) custom.style.display = (v === 'custom') ? 'inline-flex' : 'none';
  renderPropostas();
}

// Filtra propostas pela data de geracao (created_at) conforme o periodo escolhido
function filtrarPeriodoPropostas(lst) {
  if (PR_PERIODO === 'custom') {
    const deV  = document.getElementById('pr-de')?.value;
    const ateV = document.getElementById('pr-ate')?.value;
    const de  = deV  ? new Date(deV  + 'T00:00:00').getTime() : null;
    const ate = ateV ? new Date(ateV + 'T23:59:59').getTime() : null;
    return lst.filter(p => {
      const t = new Date(p.created_at).getTime();
      if (de  && t < de)  return false;
      if (ate && t > ate) return false;
      return true;
    });
  }
  const dias = Number(PR_PERIODO) || 0;
  if (!dias) return lst;                       // "Todos"
  const corte = Date.now() - dias*86400000;
  return lst.filter(p => new Date(p.created_at).getTime() >= corte);
}

function totalProposta(p) {
  const prods = p.snapshot?.produtos || [];
  let tot = 0;
  prods.forEach(it => {
    const q = Number(it.qtd_kg)||0;
    const pr = Number(it.preco_kg)||0;
    const ipi = Number(it.ipi)||0;
    const sub = q*pr;
    tot += sub + sub*(ipi/100);
  });
  const frete = Number(p.snapshot?.condicoes?.frete_valor)||0;
  return tot + frete;
}

function renderPropostas() {
  const body = document.getElementById('pr-body');
  const stats = document.getElementById('pr-stats');
  if (!body) return;

  const soMeus = document.getElementById('pr-meus')?.checked;
  const meuId = ME?.id;

  const all = (PROPOSTAS||[]).filter(p => (p.status||'em_andamento') === PR_STATUS);
  let lst = soMeus && meuId ? all.filter(p => p.seller_id === meuId) : all;
  lst = filtrarPeriodoPropostas(lst); // Sprint 9.2: filtro de periodo

  const totVal = lst.reduce((s,p)=>s+totalProposta(p),0);
  stats.textContent = `${lst.length} proposta(s)${totVal>0?' · '+fMoeda(totVal):''}`;

  if (!lst.length) {
    // Sprint 9.2: se ha filtro de periodo ativo, a mensagem reflete isso
    const periodoAtivo = PR_PERIODO === 'custom' || (Number(PR_PERIODO) > 0);
    const vazio = periodoAtivo
      ? { ico:'📅', tit:'Nenhuma proposta neste período', msg:'Tente ampliar o período (ex: "Todos") ou ajustar as datas.' }
      : {
          em_andamento: { ico:'📝', tit:'Sem propostas em andamento', msg:'Gere uma proposta a partir de uma oportunidade pra ela aparecer aqui.' },
          pedido:       { ico:'📦', tit:'Sem pedidos finalizados ainda', msg:'Ao marcar uma proposta como "Pedido", ela aparece aqui pra acompanhamento.' },
          expedido:     { ico:'🚚', tit:'Nenhum pedido expedido ainda', msg:'Ao marcar um pedido como "Expedido", ele sai da fila de produção e aparece aqui.' },
          cancelada:    { ico:'🚫', tit:'Sem propostas canceladas', msg:'Propostas canceladas aparecem aqui.' },
        }[PR_STATUS];
    body.innerHTML = `<div class="pf-empty" style="margin-top:14px">
      <span class="es-ico">${vazio.ico}</span>
      <div class="es-tit">${vazio.tit}</div>
      <div class="es-msg">${vazio.msg}</div>
    </div>`;
    return;
  }

  body.innerHTML = `<div class="pr-grid">${lst.map(p => {
    const empNome = p.snapshot?.cliente?.name || (CL.find(c=>c.id===p.company_id)?.razao_social) || '—';
    const tit = p.snapshot?.oportunidade?.titulo || '';
    const vend = p.snapshot?.consultor?.nome || '';
    const dt = new Date(p.created_at).toLocaleDateString('pt-BR');
    const stLbl = { em_andamento:'Em andamento', pedido:'Pedido', expedido:'Expedido', cancelada:'Cancelada' }[p.status||'em_andamento'];
    const total = totalProposta(p);
    const pedNum = numPedido(p);
    return `<div class="pr-card" onclick="abrPropostaPorId('${p.id}')">
      <div class="pr-card-top">
        <div style="display:flex;flex-direction:column;gap:3px">
          <span class="pr-num">Proposta ${numProposta(p)}</span>
          ${pedNum ? `<span class="pr-num" style="background:var(--ok2);color:var(--ok)">Pedido ${pedNum}</span>` : ''}
          ${(p.revisao||1) > 1 ? `<span class="pr-num pr-rev">rev. ${p.revisao}</span>` : ''}
        </div>
        <span class="pr-st ${p.status||'em_andamento'}">${stLbl}</span>
      </div>
      <div class="pr-emp">${escHtml(empNome)}</div>
      ${tit?`<div class="pr-tit">${escHtml(tit)}</div>`:''}
      ${p.oc_numero?`<div class="pr-tit" style="color:var(--tx2);font-weight:600">OC do cliente: ${escHtml(p.oc_numero)}</div>`:''}
      ${p.nf_numero?`<div class="pr-tit" style="color:var(--p);font-weight:600">NF ${escHtml(p.nf_numero)}${p.transportadora?' · '+escHtml(p.transportadora):''}</div>`:''}
      <div class="pr-meta">
        <span>${escHtml(vend)} · ${dt}</span>
        <div style="display:flex;align-items:center;gap:8px">
          ${total>0?`<span class="pr-val">${fMoeda(total)}</span>`:''}
          ${MEP?.role==='admin'?`<button class="btn bd sm" style="padding:3px 8px;font-size:11px" title="Excluir proposta" onclick="event.stopPropagation();excluirPropostaById('${p.id}','${escHtml(empNome).replace(/'/g,"\\'")}')">🗑</button>`:''}
        </div>
      </div>
    </div>`;
  }).join('')}</div>`;
}

function abrPropostaPorId(id) {
  const p = (PROPOSTAS||[]).find(x => x.id === id);
  if (!p) { toast('Proposta nao encontrada','','warning'); return; }
  renderCotacao(p);
  const page = document.getElementById('cot-page');
  page.classList.add('op'); page.scrollTop = 0;
  document.body.style.overflow = 'hidden';
}

// Sprint 6.5: ajusta badge de status e botoes no topo da cot-page
function atualizarTopoCotacao() {
  const p = PROP_ATUAL;
  if (!p) return;
  const st = p.status || 'em_andamento';
  const badge = document.getElementById('cot-status-badge');
  // Mostra "Pedido 0336-26" quando ja tem numero de pedido, senao so o label
  const pedNum = numPedido(p);
  const lblMap = { em_andamento:'Em andamento', pedido:'Pedido', expedido:'Expedido', cancelada:'Cancelada' };
  const lbl = lblMap[st] || st;
  badge.textContent = st === 'pedido' && pedNum ? `Pedido ${pedNum}` : (st === 'expedido' && pedNum ? `Expedido ${pedNum}` : lbl);
  badge.className = 'pr-st ' + st;
  badge.style.display = '';
  // Selo "rev. N" ao lado do status — so a partir da 2a versao
  const revBadge = document.getElementById('cot-rev-badge');
  if (revBadge) {
    const rev = p.revisao || 1;
    revBadge.textContent = 'rev. ' + rev;
    revBadge.style.display = rev > 1 ? '' : 'none';
  }
  // Botoes de acao: todos os vendedores veem (qualquer proposta), leitor nao ve
  const podeAcionar = MEP?.role !== 'leitor';
  document.getElementById('cot-editar-btn').style.display = podeEditarProposta(p) ? '' : 'none';
  // Pedido Comercial so faz sentido depois que virou pedido: e a CONFIRMACAO
  // de algo fechado. Proposta em andamento ainda e oferta.
  document.getElementById('cot-pcom-btn').style.display =
    (st === 'pedido' || st === 'expedido') ? '' : 'none';
  document.getElementById('cot-finalizar-btn').style.display = (podeAcionar && st === 'em_andamento') ? '' : 'none';
  document.getElementById('cot-expedir-btn').style.display   = (podeAcionar && st === 'pedido') ? '' : 'none';
  document.getElementById('cot-cancelar-btn').style.display  = (podeAcionar && (st === 'em_andamento' || st === 'pedido')) ? '' : 'none';
  document.getElementById('cot-reabrir-btn').style.display   = (podeAcionar && (st === 'expedido' || st === 'cancelada')) ? '' : 'none';
  // Excluir: so admin ve, em qualquer status
  const exclBtn = document.getElementById('cot-excluir-btn');
  if (exclBtn) exclBtn.style.display = (MEP?.role === 'admin') ? '' : 'none';
}

async function mudarStatusProposta(novoStatus, msgSucesso) {
  if (!PROP_ATUAL) return;
  try {
    await api('PATCH','proposals',`id=eq.${PROP_ATUAL.id}`, {
      status: novoStatus,
      status_changed_at: new Date().toISOString(),
      status_changed_by: ME.id,
    });
    // Re-busca a proposta pra pegar o pedido_numero atribuido pelo trigger
    const fresh = await api('GET','proposals',
      `id=eq.${PROP_ATUAL.id}&select=id,ano,numero,revisao,pedido_numero,pedido_ano,status,status_changed_at,nf_numero,transportadora,oc_numero,entrega_local,entrega_previsao,snapshot,company_id,opportunity_id,seller_id,created_at`);
    const updated = Array.isArray(fresh) ? fresh[0] : fresh;
    if (updated) {
      PROP_ATUAL = { ...PROP_ATUAL, ...updated };
      const idx = PROPOSTAS.findIndex(x => x.id === PROP_ATUAL.id);
      if (idx >= 0) PROPOSTAS[idx] = PROP_ATUAL;
    } else {
      PROP_ATUAL.status = novoStatus;
    }
    atualizarTopoCotacao();
    const numLabel = numPedido(PROP_ATUAL) || numProposta(PROP_ATUAL);
    toast(msgSucesso, 'Nº ' + numLabel, 'success');
    // Re-renderiza a aba Propostas se estiver aberta
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
  } catch(err) {
    toast('Erro ao atualizar proposta', err.message||'', 'warning');
  }
}

async function finalizarComoPedido() {
  if (!PROP_ATUAL) return;
  await mudarStatusProposta('pedido', 'Proposta finalizada como Pedido');
  await ofereceMarcarOppGanha();
  // SEMPRE, e por ultimo. Antes, a oferta da oportunidade tinha `return` no
  // meio (opp inexistente ou ja ganha) e qualquer coisa depois dela seria
  // pulada justamente nos casos mais comuns.
  perguntarOC();
}

// Extraida de finalizarComoPedido pra que os `return` dela nao engulam o que
// vem depois.
async function ofereceMarcarOppGanha() {
  const oppId = PROP_ATUAL?.opportunity_id;
  if (!oppId) return;
  const opp = todasOpps().find(o => o.id === oppId);
  if (!opp || opp.estagio === 'ganha') return;
  if (!confirm(`Marcar tambem a oportunidade "${opp.titulo}" como GANHA?`)) return;
  try {
    await api('PATCH','opportunities',`id=eq.${oppId}`, { estagio: 'ganha' });
    CL = await fetchCl();
    toast('Oportunidade marcada como Ganha','','success');
  } catch(err) {
    toast('Erro ao atualizar oportunidade', err.message||'', 'warning');
  }
}

// ── Pergunta a OC no momento em que o pedido fecha ────────────────────────
// O campo de OC so existia dentro do modal do Pedido Comercial. Quem marcava
// como Pedido e mandava so o Pedido de Producao nunca via o campo — dai 175
// pedidos sem OC. Aqui e o momento de maior informacao: o cliente acabou de
// confirmar e tem o numero na mao.
function perguntarOC() {
  const p = PROP_ATUAL;
  if (!p) return;
  if (p.oc_numero && String(p.oc_numero).trim()) return;   // ja tem, nao incomoda
  const campo = document.getElementById('oc-input');
  if (!campo) return;
  campo.value = '';
  document.getElementById('oc-m').classList.add('op');
  setTimeout(() => campo.focus(), 80);
}

function fecharPerguntaOC() {
  document.getElementById('oc-m').classList.remove('op');
}

async function salvarPerguntaOC() {
  const p = PROP_ATUAL;
  const campo = document.getElementById('oc-input');
  const btn = document.getElementById('oc-salvar');
  if (!p || !campo) return;
  const oc = campo.value.trim();
  if (!oc) { fecharPerguntaOC(); return; }   // vazio = mesma coisa que "Depois"
  btn.disabled = true; btn.textContent = 'Salvando...';
  try {
    await api('PATCH','proposals',`id=eq.${p.id}`, { oc_numero: oc });
    PROP_ATUAL = { ...p, oc_numero: oc };
    const i = PROPOSTAS.findIndex(x => x.id === p.id);
    if (i >= 0) PROPOSTAS[i] = PROP_ATUAL;
    fecharPerguntaOC();
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
    toast('OC registrada', 'Agora dá pra achar este pedido pelo número do cliente.', 'success');
  } catch(err) {
    toast('Erro ao salvar a OC', err.message||'', 'warning');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar OC';
  }
}

// Sprint 6.8: abre modal pedindo NF + transportadora antes de marcar como expedido
function expedicaoProposta() {
  if (!PROP_ATUAL) return;
  document.getElementById('exp-nf').value = PROP_ATUAL.nf_numero || '';
  document.getElementById('exp-transp').value = PROP_ATUAL.transportadora || '';
  document.getElementById('expedicao-m').classList.add('op');
  setTimeout(() => document.getElementById('exp-nf').focus(), 80);
}

// `?.`: este trecho executa no CARREGAMENTO. Num modulo, um elemento ausente
// lanca TypeError, para o arquivo no meio e as funcoes declaradas abaixo
// nunca chegam a existir. Um formulario faltando vira um botao que nao
// envia; nao pode virar "a aba Propostas nao abre".
document.getElementById('expedicao-f')?.addEventListener('submit', async e => {
  e.preventDefault();
  const nf     = document.getElementById('exp-nf').value.trim();
  const transp = document.getElementById('exp-transp').value.trim();
  if (!nf) return;
  const btn = document.getElementById('exp-sub');
  btn.disabled = true; btn.textContent = 'Salvando...';
  document.getElementById('expedicao-m').classList.remove('op');
  try {
    await api('PATCH','proposals',`id=eq.${PROP_ATUAL.id}`, {
      status:           'expedido',
      nf_numero:        nf,
      transportadora:   transp || null,
      status_changed_at: new Date().toISOString(),
      status_changed_by: ME.id,
    });
    // Re-busca pra sincronizar estado local
    const fresh = await api('GET','proposals',
      `id=eq.${PROP_ATUAL.id}&select=id,ano,numero,revisao,pedido_numero,pedido_ano,status,status_changed_at,nf_numero,transportadora,oc_numero,entrega_local,entrega_previsao,snapshot,company_id,opportunity_id,seller_id,created_at`);
    const updated = Array.isArray(fresh) ? fresh[0] : fresh;
    if (updated) {
      PROP_ATUAL = { ...PROP_ATUAL, ...updated };
      const idx = PROPOSTAS.findIndex(x => x.id === PROP_ATUAL.id);
      if (idx >= 0) PROPOSTAS[idx] = PROP_ATUAL;
    }
    atualizarTopoCotacao();
    toast('Expedição registrada', `NF ${nf}${transp?' · '+transp:''}`, 'success');
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
  } catch(err) {
    toast('Erro ao registrar expedição', err.message||'', 'warning');
  } finally {
    btn.disabled = false; btn.textContent = '🚚 Confirmar Expedição';
  }
});

function cancelarProposta() {
  if (!PROP_ATUAL) return;
  if (!confirm('Cancelar esta proposta? Ela vai pra aba "Canceladas" e pode ser reaberta depois.')) return;
  mudarStatusProposta('cancelada', 'Proposta cancelada');
}

function reabrirProposta() {
  if (!PROP_ATUAL) return;
  mudarStatusProposta('em_andamento', 'Proposta reaberta');
}

// Sprint 6.7: excluir proposta (definitivo — só admin)
function excluirProposta() {
  if (!PROP_ATUAL) return;
  excluirPropostaById(PROP_ATUAL.id, PROP_ATUAL.snapshot?.cliente?.name || numProposta(PROP_ATUAL));
}

function excluirPropostaById(id, label) {
  const p = PROPOSTAS.find(x => x.id === id);
  if (!p) { toast('Proposta não encontrada','','warning'); return; }
  const num = numPedido(p) ? `Pedido ${numPedido(p)}` : `Proposta ${numProposta(p)}`;

  // Remove imediatamente do cache e da UI
  PROPOSTAS = PROPOSTAS.filter(x => x.id !== id);
  if (PROP_ATUAL?.id === id) fecharCotacao();
  if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();

  deferComUndo(`${num} excluída`, escHtml(label||''), async () => {
    await api('DELETE', 'proposals', `id=eq.${id}`);
    PROPOSTAS = await fetchPropostas();
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
  }, `${num} restaurada`);
}

// ── Revisao de pedido (2026-08-14) ────────────────────────────────────────
// Cliente pede desconto ao trocar a forma de pagamento, ou pede pra
// acrescentar outro material num pedido ja fechado. Editar o snapshot no
// lugar apagaria a prova do que foi combinado antes (proposta e documento
// legal — CLAUDE.md secao 11), e o audit_log nao cobre: ele ignora o campo
// snapshot. Entao editar VERSIONA: o snapshot vigente e arquivado em
// proposal_revisions e a proposta passa pra revisao seguinte.
//
// Rascunho das linhas em edicao. Nao e o snapshot — vira snapshot no submit.
let EDP_LINHAS = [];

// Status que aceitam edicao. `expedido` fica de fora de proposito: a NF ja
// foi emitida, e mudar o pedido depois disso descasa do fiscal.
const EDP_STATUS_EDITAVEIS = new Set(['em_andamento', 'pedido']);

function podeEditarProposta(p) {
  if (!p || MEP?.role === 'leitor') return false;
  return EDP_STATUS_EDITAVEIS.has(p.status || 'em_andamento');
}

function abrirEditarPedido() {
  const p = PROP_ATUAL;
  if (!p) { toast('Sem proposta carregada','','warning'); return; }
  if (!podeEditarProposta(p)) {
    toast('Não dá pra editar', 'Pedido expedido ou cancelado não aceita alteração.', 'warning');
    return;
  }
  const snap = p.snapshot || {};
  const cond = snap.condicoes || {};

  // Copia profunda: mexer no rascunho nao pode respingar no snapshot vigente
  // enquanto o usuario ainda nao salvou (ou se ele cancelar).
  EDP_LINHAS = (snap.produtos || []).map(it => ({ ...it }));

  document.getElementById('edp-titulo').textContent =
    (numPedido(p) ? 'Editar pedido ' + numPedido(p) : 'Editar proposta ' + numProposta(p));
  document.getElementById('edp-prox-rev').textContent = 'revisão ' + ((p.revisao || 1) + 1);
  document.getElementById('edp-pgto').value      = cond.prazo_pagamento || '';
  document.getElementById('edp-frete').value     = cond.frete || 'FOB';
  document.getElementById('edp-frete-val').value = cond.frete_valor != null ? cond.frete_valor : '';
  document.getElementById('edp-val').value       = cond.validade_dias || 30;
  document.getElementById('edp-obs').value       = cond.obs || '';
  document.getElementById('edp-motivo').value    = '';
  document.getElementById('edp-erro').textContent = '';

  edpRenderLinhas();
  document.getElementById('edp-m').classList.add('op');
  setTimeout(() => document.getElementById('edp-motivo')?.focus(), 80);
}

function fecharEditarPedido() {
  document.getElementById('edp-m').classList.remove('op');
  EDP_LINHAS = [];
}

// Catalogo (PRODS) pro <select> de "acrescentar produto". Cada opcao carrega
// o preco sugerido no dataset pra preencher o campo sem uma segunda busca.
// "PRODUTO — Embalagem", o rotulo que o <select> usa como value. Uma funcao
// so pra montar e pra comparar: era aqui que estava o bug — a lista era
// preenchida com `it.produto` (so o nome) e comparada com opcoes que valem
// "nome — embalagem", entao NADA casava e o select voltava pra "escolha".
function edpRotulo(it) {
  if (!it || !String(it.produto || '').trim()) return '';
  return it.produto + (it.embalagem ? ' — ' + it.embalagem : '');
}

// Recebe o ROTULO COMPLETO da linha (nao so o nome).
// `nome` e `embalagem` vao no dataset porque separar por " — " quebraria em
// produto cujo proprio nome tenha esse tracinho.
function edpOpcoesCatalogo(sel) {
  const rotulos = [];
  const opts = (PRODS || []).map(pr => {
    const rot = pr.nome + (pr.embalagem ? ' — ' + pr.embalagem : '');
    rotulos.push(rot);
    return `<option value="${escHtml(rot)}" ${rot === sel ? 'selected' : ''}
             data-nome="${escHtml(pr.nome)}" data-emb="${escHtml(pr.embalagem || '')}"
             data-preco="${pr.preco_pj != null ? pr.preco_pj : ''}">${escHtml(rot)}</option>`;
  }).join('');
  // Produto que esta no pedido mas saiu do catalogo (ou foi digitado a mao)
  // ganha a propria opcao. Sem isto ele sumiria da tela e o vendedor acharia
  // que o item foi apagado — quando na verdade o dado continua no snapshot.
  const forfe = (sel && !rotulos.includes(sel))
    ? `<option value="${escHtml(sel)}" selected data-fora="1">${escHtml(sel)} (fora do catálogo)</option>`
    : '';
  // "Outro" cobre o produto que ainda nao esta no catalogo — o vendedor nao
  // pode ficar travado esperando o cadastro pra fechar o pedido.
  return `<option value="" ${sel ? '' : 'selected'}>— escolha —</option>`
       + forfe + opts + `<option value="__outro__">Outro (digitar)</option>`;
}

function edpRenderLinhas() {
  const box = document.getElementById('edp-prod-lista');
  if (!EDP_LINHAS.length) {
    box.innerHTML = '<div class="edp-vazio">Nenhum produto. Use “Acrescentar produto” abaixo.</div>';
    return;
  }
  box.innerHTML = `<div class="edp-phead">
      <div>Produto</div><div class="num">Qtd (kg)</div><div class="num">R$/kg</div>
      <div class="num">IPI %</div><div class="num">Total</div><div></div>
    </div>` + EDP_LINHAS.map((it, i) => {
    // TODA linha e editavel, inclusive as que vieram do pedido original. Antes
    // so as novas tinham <select> e as antigas eram texto fixo — nao havia
    // como trocar a EMBALAGEM de um item ja fechado, que e justamente o que o
    // cliente pede ("manda em bombona em vez de tambor"). O jeito de contornar
    // seria apagar e reincluir, e isso perde o historico da linha.
    const novo = !!it._novo;
    const nomeCel = `<div class="edp-novo-wrap">
           <select class="edp-prod-sel" aria-label="Produto e embalagem da linha ${i + 1}"
                   onchange="edpTrocaProduto(${i}, this)">${edpOpcoesCatalogo(edpRotulo(it))}</select>
           ${it._livre ? `<input class="edp-prod-livre" placeholder="Nome do produto"
                                 value="${escHtml(it.produto||'')}" oninput="EDP_LINHAS[${i}].produto=this.value">` : ''}
           ${novo ? '<span class="edp-tag-novo">novo</span>' : ''}
         </div>`;
    // Cada campo carrega o proprio rotulo num <label>. No desktop ele fica
    // escondido (o cabecalho da tabela ja diz), no celular o cabecalho some e
    // o rotulo aparece — senao vira uma fileira de caixas sem identificacao.
    const campo = (lbl, val, expr) => `<label class="edp-fld">
        <span>${lbl}</span>
        <input class="num" type="number" step="0.01" min="0" value="${val}"
               oninput="EDP_LINHAS[${i}].${expr};edpAtualizaTotais()">
      </label>`;
    return `<div class="edp-prow">
      ${nomeCel}
      ${campo('Qtd (kg)', it.qtd_kg != null ? it.qtd_kg : '', 'qtd_kg=parseNum(this.value)')}
      ${campo('R$/kg', it.preco_kg != null ? it.preco_kg : '', 'preco_kg=parseNum(this.value)')}
      ${campo('IPI %', it.ipi != null ? it.ipi : 0, 'ipi=parseNum(this.value)??0')}
      <div class="num edp-lin-tot" data-i="${i}"><span class="edp-lin-tot-lbl">Total</span><b>—</b></div>
      <button type="button" class="edp-del" title="Remover do pedido"
              onclick="edpRemoveLinha(${i})" aria-label="Remover produto">✕</button>
    </div>`;
  }).join('') + `<div class="edp-tot-bar">
      Total do pedido: <b id="edp-total">—</b>
      <span id="edp-delta" class="edp-delta"></span>
    </div>`;
  edpAtualizaTotais();
}

function edpTrocaProduto(i, sel) {
  const v = sel.value;
  if (v === '__outro__') {
    EDP_LINHAS[i]._livre = true;
    EDP_LINHAS[i].produto = '';
    EDP_LINHAS[i].embalagem = null;
  } else if (v === '') {
    // Voltou pra "— escolha —": limpa, senao a linha ficaria com o produto
    // antigo no dado e vazia na tela.
    EDP_LINHAS[i]._livre = false;
    EDP_LINHAS[i].produto = '';
    EDP_LINHAS[i].embalagem = null;
  } else {
    const opt = sel.selectedOptions[0];
    EDP_LINHAS[i]._livre = false;
    // Nome e embalagem saem do DATASET da opcao, nao de split(' — '): produto
    // cujo nome contenha o tracinho quebraria a divisao. A opcao "fora do
    // catalogo" nao tem dataset — nela o rotulo inteiro e o nome.
    if (opt?.dataset.fora) {
      EDP_LINHAS[i].produto   = v;
      EDP_LINHAS[i].embalagem = null;
    } else {
      EDP_LINHAS[i].produto   = opt?.dataset.nome || v;
      EDP_LINHAS[i].embalagem = opt?.dataset.emb || null;
    }
    // So sugere preco se a linha ainda nao tem um. Preco negociado nao pode
    // ser sobrescrito por troca de embalagem.
    const preco = opt?.dataset.preco;
    if (preco && EDP_LINHAS[i].preco_kg == null) EDP_LINHAS[i].preco_kg = Number(preco);
  }
  edpRenderLinhas();
}

function edpAddLinha() {
  EDP_LINHAS.push({
    produto: '', embalagem: null, qtd_kg: null, preco_kg: null,
    ipi: 0, classificacao_risco: 'NÃO CLASSIFICADO',
    _novo: true, _livre: false,
  });
  edpRenderLinhas();
  setTimeout(() => document.querySelector('#edp-prod-lista .edp-prow:last-child .edp-prod-sel')?.focus(), 60);
}

function edpRemoveLinha(i) {
  EDP_LINHAS.splice(i, 1);
  edpRenderLinhas();
}

// Total ao vivo + quanto mudou em relacao a revisao vigente. O vendedor
// costuma estar com o cliente no telefone — ele precisa ver o efeito do
// desconto na hora, nao depois de salvar.
function edpAtualizaTotais() {
  const frete = parseNum(document.getElementById('edp-frete-val').value) || 0;
  let tot = 0;
  EDP_LINHAS.forEach((it, i) => {
    const sub = (Number(it.qtd_kg)||0) * (Number(it.preco_kg)||0);
    const comIpi = sub + sub * ((Number(it.ipi)||0)/100);
    tot += comIpi;
    const cel = document.querySelector(`.edp-lin-tot[data-i="${i}"] b`);
    if (cel) cel.textContent = comIpi > 0 ? fMoeda(comIpi) : '—';
  });
  tot += frete;
  const elTot = document.getElementById('edp-total');
  if (elTot) elTot.textContent = fMoeda(tot);

  const antes = totalProposta(PROP_ATUAL);
  const el = document.getElementById('edp-delta');
  if (!el) return;
  const dif = tot - antes;
  if (!antes || Math.abs(dif) < 0.005) { el.textContent = ''; return; }
  const pct = (dif / antes) * 100;
  el.textContent = `${dif > 0 ? '▲' : '▼'} ${fMoeda(Math.abs(dif))} (${pct > 0 ? '+' : ''}${pct.toFixed(1)}%) vs. revisão atual`;
  el.className = 'edp-delta ' + (dif > 0 ? 'up' : 'down');
}

document.getElementById('edp-frete-val')?.addEventListener('input', edpAtualizaTotais);

document.getElementById('edp-f')?.addEventListener('submit', async e => {
  e.preventDefault();
  const p = PROP_ATUAL;
  const err = document.getElementById('edp-erro');
  err.textContent = '';
  if (!p) return;

  // Revalida o status aqui tambem: o modal pode ter ficado aberto enquanto
  // outra pessoa expediu o pedido na outra ponta.
  if (!podeEditarProposta(p)) {
    err.textContent = 'Este pedido mudou de status e não aceita mais alteração. Feche e abra de novo.';
    return;
  }
  const motivo = document.getElementById('edp-motivo').value.trim();
  if (!motivo) { err.textContent = 'Descreva o motivo da alteração.'; return; }
  if (!EDP_LINHAS.length) { err.textContent = 'O pedido precisa de pelo menos um produto.'; return; }
  const semNome = EDP_LINHAS.findIndex(it => !String(it.produto||'').trim());
  if (semNome >= 0) { err.textContent = `Escolha o produto da linha ${semNome+1}.`; return; }
  const semQtd = EDP_LINHAS.findIndex(it => !(Number(it.qtd_kg) > 0));
  if (semQtd >= 0) { err.textContent = `Informe a quantidade da linha ${semQtd+1}.`; return; }

  // Snapshot novo: parte do vigente e troca so produtos e condicoes. Cliente,
  // consultor, office e oportunidade seguem como estavam — a revisao muda o
  // que foi negociado, nao de quem e o pedido.
  const snapAntigo = p.snapshot || {};
  const snapshotNovo = {
    ...snapAntigo,
    produtos: EDP_LINHAS.map((it, idx) => ({
      item: idx + 1,
      produto:   String(it.produto || '').trim(),
      embalagem: it.embalagem || null,
      qtd_kg:    it.qtd_kg,
      preco_kg:  it.preco_kg,
      ipi:       it.ipi ?? 0,
      classificacao_risco: it.classificacao_risco || 'NÃO CLASSIFICADO',
    })),
    condicoes: {
      ...(snapAntigo.condicoes || {}),
      prazo_pagamento: document.getElementById('edp-pgto').value.trim() || '30DD',
      frete:           document.getElementById('edp-frete').value,
      frete_valor:     parseNum(document.getElementById('edp-frete-val').value) || 0,
      validade_dias:   parseInt(document.getElementById('edp-val').value, 10) || 30,
      obs:             document.getElementById('edp-obs').value.trim() || null,
    },
  };

  const btn = document.getElementById('edp-sub');
  btn.disabled = true; btn.textContent = 'Salvando...';
  try {
    // ORDEM IMPORTA: arquiva primeiro, sobrescreve depois. Se o PATCH falhar,
    // sobra uma revisao arquivada a mais (inofensivo). Na ordem inversa, uma
    // falha aqui perderia o snapshot antigo pra sempre.
    await api('POST', 'proposal_revisions', null, {
      proposal_id: p.id,
      revisao:     p.revisao || 1,
      snapshot:    snapAntigo,
      motivo,
      created_by:  ME.id,
    });
    await api('PATCH', 'proposals', `id=eq.${p.id}`, {
      snapshot: snapshotNovo,
      revisao:  (p.revisao || 1) + 1,
    });

    PROP_ATUAL = { ...p, snapshot: snapshotNovo, revisao: (p.revisao || 1) + 1 };
    const idx = PROPOSTAS.findIndex(x => x.id === p.id);
    if (idx >= 0) PROPOSTAS[idx] = PROP_ATUAL;

    fecharEditarPedido();
    renderCotacao(PROP_ATUAL);
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
    // Se ja era pedido, a fabrica provavelmente recebeu o Pedido de Producao
    // da revisao anterior — mandar de novo e responsabilidade do vendedor.
    toast('Revisão ' + PROP_ATUAL.revisao + ' salva',
          (p.status === 'pedido')
            ? 'Reenvie o Pedido de Produção — a fábrica está com a versão antiga.'
            : 'A versão anterior continua guardada no histórico.',
          'success');
  } catch(ex) {
    console.error('salvar revisao:', ex);
    // Erro tipico se a migration ainda nao foi rodada no banco
    err.textContent = /proposal_revisions|revisao/i.test(ex.message||'')
      ? 'O banco ainda não tem a tabela de revisões. Rode migrations/2026-08-14-revisao-pedidos.sql.'
      : (ex.message || 'Não foi possível salvar a revisão.');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar revisão';
  }
});

async function abrirHistoricoRevisoes() {
  const p = PROP_ATUAL;
  if (!p) return;
  const box = document.getElementById('edp-hist-body');
  box.innerHTML = '<div class="edp-vazio">Carregando...</div>';
  document.getElementById('edp-hist-m').classList.add('op');
  try {
    const revs = await api('GET','proposal_revisions',
      `proposal_id=eq.${p.id}&select=revisao,snapshot,motivo,created_at,created_by&order=revisao.desc`) || [];
    const nome = id => (PF||[]).find(x => x.id === id)?.name || '—';
    // A revisao vigente nao esta na tabela de historico (ela vive na proposta),
    // entao entra aqui na mao, no topo.
    const atual = {
      revisao: p.revisao || 1, snapshot: p.snapshot, motivo: null,
      created_at: p.status_changed_at || p.created_at, created_by: p.seller_id, _atual: true,
    };
    box.innerHTML = [atual, ...revs].map(r => {
      const prods = r.snapshot?.produtos || [];
      const cond = r.snapshot?.condicoes || {};
      const tot = totalProposta({ snapshot: r.snapshot });
      return `<div class="edp-rev ${r._atual?'atual':''}">
        <div class="edp-rev-head">
          <span class="edp-rev-num">rev. ${r.revisao}${r._atual?' · vigente':''}</span>
          <span class="edp-rev-meta">${escHtml(nome(r.created_by))} · ${fDataHora(r.created_at)}</span>
        </div>
        ${r.motivo?`<div class="edp-rev-motivo">“${escHtml(r.motivo)}”</div>`:''}
        <div class="edp-rev-prods">${prods.map(it =>
          `<div>${escHtml(it.produto||'—')} · ${Number(it.qtd_kg||0).toLocaleString('pt-BR')}kg · ${fMoeda(Number(it.preco_kg)||0)}/kg</div>`
        ).join('')}</div>
        <div class="edp-rev-cond">${escHtml(cond.prazo_pagamento||'—')} · ${escHtml(cond.frete||'—')} · <b>${fMoeda(tot)}</b></div>
      </div>`;
    }).join('');
  } catch(ex) {
    console.error('historico revisoes:', ex);
    box.innerHTML = `<div class="edp-vazio">Não foi possível carregar o histórico. ${escHtml(ex.message||'')}</div>`;
  }
}
