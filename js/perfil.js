/* ==========================================================================
   perfil.js — a pagina de perfil da empresa e suas cinco abas.
   Sprint 8.1f (modularizacao), 19/08/2026.

   Um dominio so: abrir/fechar a pagina e renderizar Resumo, Contatos,
   Oportunidades, Interacoes e Alteracoes (o audit log da empresa).

   O QUE FICOU DE FORA, de proposito: o CRUD de contato e o de oportunidade,
   que vem logo depois no index.html. Sao modais chamados TAMBEM de outros
   lugares (lista de empresas, Kanban) — trazer junto ampliaria a fronteira
   sem que o dominio ficasse mais coeso.

   CARREGA DEPOIS de api.js/format.js. Consome CL, PF, api(), escHtml, fMoeda,
   fData, toast e os CRUDs do inline — todos em tempo de EXECUCAO. Nao ha nada
   aqui que rode no carregamento, entao a ordem so precisa colocar este arquivo
   antes do inline.
   ========================================================================== */

// ── Página de Perfil ──────────────────────────────────────────────────────
let pfClientId = null;

// ── Sprint 3.3: perfil completo da empresa com abas ─────────────────────
async function abrPerfil(id) {
  const c = CL.find(x => x.id === id);
  if (!c) { toast('Empresa não encontrada','','warning'); return; }
  pfClientId = id;
  const nome = c.razao_social || '';
  // Header
  document.getElementById('pf-topname').textContent = nome;
  document.getElementById('pf-av').textContent = ini(nome);
  document.getElementById('pf-av').style.background = cor(nome);
  document.getElementById('pf-name').textContent = nome;
  const tier = c.tier || 'lead';
  const classLbl = CLASSIF_LBL[c.classificacao];
  const badgeHtml = classLbl
    ? `<span class="classif-badge classif-${c.classificacao}" title="Tier auto: ${tier}">${classLbl}</span>`
    : `<span class="tier-badge tier-${tier}">${tier}</span>`;
  document.getElementById('pf-sub').innerHTML =
    badgeHtml
    + (c.cnpj ? ` · CNPJ: ${escHtml(c.cnpj)}` : '')
    + (c.cidade ? ` · ${escHtml(c.cidade)}${c.uf ? '/'+escHtml(c.uf) : ''}` : '');
  document.getElementById('pf-metrics').innerHTML = [
    ['Telefone', c.telefone||'—'],
    ['Email', c.email||'—'],
    ['Pipeline', fMoeda(c.valor_pipeline||0)],
    ['Opps abertas', String(c.opps_abertas||0)],
    ['Opps ganhas', String(c.opps_ganhas_total||0)],
  ].map(([l,v]) => `<div class="pf-met"><div class="pf-met-l">${l}</div><div class="pf-met-v">${v}</div></div>`).join('');
  // Renderiza todas as abas
  renderPfResumo(c);
  renderPfContatos(c);
  renderPfOportunidades(c);
  renderPfHistorico(c);
  renderPfAlteracoes(c);
  // Reset aba ativa pra Resumo
  document.querySelectorAll('#pfpage .pf-tab').forEach(t => t.classList.remove('ac'));
  document.querySelector('#pfpage .pf-tab[data-pt="resumo"]')?.classList.add('ac');
  document.querySelectorAll('#pfpage .pf-panel').forEach(p => p.classList.remove('ac'));
  document.getElementById('pf-resumo')?.classList.add('ac');
  // Mostra a página
  document.getElementById('pfpage').classList.add('op');
  document.body.style.overflow = 'hidden';
}

function fechaPerfil() {
  document.getElementById('pfpage').classList.remove('op');
  document.body.style.overflow = '';
  pfClientId = null;
}

function renderPfResumo(c) {
  const linhas = [
    ['Razão Social', c.razao_social],
    ['Nome Fantasia', c.nome_fantasia],
    ['CNPJ', c.cnpj],
    ['Inscrição Estadual', c.ie],
    ['Indústria', c.industria],
    ['Classificação', CLASSIF_LBL[c.classificacao] || null],
    ['Vendedor responsável', c.vendedor_responsavel_nome || null],
    ['Email', c.email],
    ['Telefone', c.telefone],
    ['Website', c.website],
    ['Endereço', c.endereco],
    ['Cidade/UF', c.cidade ? (c.cidade + (c.uf ? '/'+c.uf : '')) : null],
    ['CEP', c.cep],
    ['Faturamento estimado', c.faturamento_estimado != null ? fMoeda(c.faturamento_estimado) : null],
    ['Observações', c.observacoes],
  ].filter(([_, v]) => v != null && v !== '');
  const html = linhas.length
    ? `<div style="display:grid;grid-template-columns:200px 1fr;gap:8px 16px;font-size:13px">${
        linhas.map(([k, v]) => `<div style="color:var(--mt)">${escHtml(k)}</div><div style="color:var(--tx)">${escHtml(String(v))}</div>`).join('')
      }</div>`
    : '<div class="pf-empty">Sem dados detalhados — clique em "Editar Empresa" para preencher.</div>';
  document.getElementById('pf-resumo').innerHTML = html;
}

function renderPfContatos(c) {
  const lista = c.contatos || [];
  const head = `<div class="pf-list-head">
    <h3>Contatos (${lista.length})</h3>
    <button class="btn bp sm write-only" onclick="abrContato('${c.id}')">+ Novo Contato</button>
  </div>`;
  const body = lista.length
    ? lista.sort((a,b) => (b.principal?1:0) - (a.principal?1:0)).map(ct => `
      <div class="pf-card">
        <div class="pf-card-main">
          <div class="pf-card-title">${escHtml(ct.nome)}${ct.principal?'<span class="pf-badge-princ">Principal</span>':''}</div>
          <div class="pf-card-sub">
            ${ct.cargo?`<b>${escHtml(ct.cargo)}</b>`:''}${ct.papel?` · ${escHtml(ct.papel)}`:''}
            ${(ct.email||ct.telefone)?'<br>':''}
            ${ct.email?`📧 ${escHtml(ct.email)} `:''}
            ${ct.telefone?`📞 ${escHtml(ct.telefone)}`:''}
          </div>
        </div>
        <div class="pf-card-actions">
          <button class="btn bg sm" onclick="abrContato('${c.id}','${ct.id}')">Editar</button>
          <button class="btn bod sm" onclick="delContato('${ct.id}','${escHtml(ct.nome).replace(/'/g,"\\'")}')">✕</button>
        </div>
      </div>`).join('')
    : `<div class="pf-empty">
        <span class="es-ico">👤</span>
        <div class="es-tit">Sem contatos cadastrados</div>
        <div class="es-msg">Adicione o(s) responsável(eis) da empresa para registrar com quem você fala.</div>
        <button class="es-cta write-only" onclick="abrContato('${c.id}')">+ Adicionar Contato</button>
      </div>`;
  document.getElementById('pf-contatos').innerHTML = head + body;
}

const ESTAGIO_LBL = {
  lead:'Lead', qualificado:'Qualificado', proposta_enviada:'Proposta enviada',
  em_negociacao:'Em negociação', ganha:'Ganha', perdida:'Perdida'
};

// Sprint 4.1: classificação manual da empresa (escolhida pelo vendedor no cadastro)
const CLASSIF_LBL = {
  lead_novo: 'Lead novo',
  prospect: 'Prospect',
  cliente_ativo: 'Cliente ativo',
  inativo: 'Inativo',
  indicacao: 'Indicação',
};

// Sprint 4.2: bulk de oportunidades no perfil da empresa
let pfOppSelected = new Set();

// Sprint 7.2: estagios "em aberto" (ainda em negociacao, nao fechados)
const ESTAGIOS_ABERTOS = ['lead','qualificado','proposta_enviada','em_negociacao'];

// Sprint 7.2: oportunidade ORFA = aberta e sem proximo passo agendado
// (callback nulo ou no passado). Usada no badge e no card do dashboard.
function semProximoPasso(o) {
  if (!ESTAGIOS_ABERTOS.includes(o.estagio)) return false;
  if (!o.callback_date) return true;
  return new Date(o.callback_date).getTime() < Date.now();
}

// Sprint 6.3: sugere o proximo passo de acao para a oportunidade baseado em estagio + datas
function proximoPasso(o) {
  if (o.estagio === 'ganha')   return { txt: 'Oportunidade ganha. Boa venda!', urg: 'done', ico: '🏆' };
  if (o.estagio === 'perdida') return { txt: `Oportunidade perdida${o.perda_motivo?' — '+escHtml(o.perda_motivo):''}.`, urg: 'done', ico: '🔒' };

  const cbMs = o.callback_date ? new Date(o.callback_date).getTime() : null;
  const agora = Date.now();
  const fimHoje = (() => { const d = new Date(); d.setHours(23,59,59,999); return d.getTime(); })();
  const estagioMs = o.estagio_changed_at ? new Date(o.estagio_changed_at).getTime() : null;
  const diasNoEstagio = estagioMs ? Math.floor((agora - estagioMs) / 86400000) : null;

  // Atrasado vale acima de tudo
  if (cbMs && cbMs < agora) {
    return { txt: `Retorno <b>atrasado</b> (${fRel(o.callback_date)}). Ligue agora.`, urg: 'high', ico: '⚠' };
  }
  if (cbMs && cbMs <= fimHoje) {
    return { txt: `Retorno hoje às <b>${fHora(o.callback_date)}</b>.`, urg: 'med', ico: '📞' };
  }

  switch (o.estagio) {
    case 'lead':
      if (!cbMs && (diasNoEstagio==null || diasNoEstagio < 2)) return { txt: 'Faça o primeiro contato e qualifique a oportunidade.', urg: 'low', ico: '👋' };
      if (!cbMs) return { txt: `Lead há <b>${diasNoEstagio} dias</b> sem contato. Ligue ou agende um retorno.`, urg: 'high', ico: '⏰' };
      return { txt: `Retorno agendado para <b>${fDataHora(o.callback_date)}</b>.`, urg: 'low', ico: '📅' };
    case 'qualificado':
      if (!cbMs) return { txt: 'Pronto pra <b>gerar e enviar a proposta</b> comercial.', urg: 'med', ico: '📝' };
      return { txt: `Retorno agendado para <b>${fDataHora(o.callback_date)}</b>. Preparar proposta?`, urg: 'low', ico: '📅' };
    case 'proposta_enviada':
      if (diasNoEstagio != null && diasNoEstagio >= 5 && !cbMs) return { txt: `Proposta enviada há <b>${diasNoEstagio} dias</b> sem retorno. Faça follow-up.`, urg: 'high', ico: '📨' };
      if (cbMs) return { txt: `Follow-up agendado para <b>${fDataHora(o.callback_date)}</b>.`, urg: 'low', ico: '📅' };
      return { txt: 'Aguardando resposta do cliente. Agende um follow-up.', urg: 'med', ico: '⏳' };
    case 'em_negociacao':
      if (!cbMs) return { txt: 'Em negociação sem próximo passo definido. Agende um retorno.', urg: 'med', ico: '🤝' };
      return { txt: `Negociando — próximo contato em <b>${fDataHora(o.callback_date)}</b>.`, urg: 'low', ico: '🤝' };
  }
  return { txt: 'Defina o próximo passo desta oportunidade.', urg: 'low', ico: 'ℹ' };
}

function renderPfOportunidades(c) {
  const lista = c.oportunidades || [];
  const head = `<div class="pf-list-head">
    <h3>Oportunidades (${lista.length})</h3>
    <button class="btn bp sm write-only" onclick="abrOpp('${c.id}')">+ Nova Oportunidade</button>
  </div>`;
  // Ordena: abertas primeiro, depois ganhas, depois perdidas, e por data
  const ord = [...lista].sort((a,b) => {
    const aClosed = a.estagio === 'ganha' || a.estagio === 'perdida';
    const bClosed = b.estagio === 'ganha' || b.estagio === 'perdida';
    if (aClosed !== bClosed) return aClosed ? 1 : -1;
    return (b.callback_date||'').localeCompare(a.callback_date||'');
  });
  // Limpa seleções de opps que sumiram
  pfOppSelected = new Set([...pfOppSelected].filter(id => ord.some(o => o.id === id)));
  const bulkBar = pfOppSelected.size
    ? `<div id="pf-bulk-bar">
        <span><b>${pfOppSelected.size}</b> selecionada(s):</span>
        <select onchange="if(this.value){bulkOppEstagio(this.value);this.value='';}">
          <option value="">Mudar estágio para...</option>
          <option value="lead">Lead</option>
          <option value="qualificado">Qualificado</option>
          <option value="proposta_enviada">Proposta enviada</option>
          <option value="em_negociacao">Em negociação</option>
          <option value="ganha">Ganha</option>
          <option value="perdida">Perdida</option>
        </select>
        <button class="btn bod sm" onclick="bulkOppExcluir()">🗑 Excluir</button>
        <button class="btn bg sm" onclick="bulkOppLimpar()">Cancelar</button>
      </div>`
    : '';
  const body = ord.length
    ? ord.map(o => {
        const sel = pfOppSelected.has(o.id);
        return `<div class="pf-card pf-opp-card ${sel?'pf-opp-selected':''}">
        <input type="checkbox" class="pf-opp-cb" ${sel?'checked':''} onclick="toggleOppSel('${o.id}',this.checked)" title="Selecionar pra ação em massa">
        <div class="pf-card-main">
          <div class="pf-card-title">${escHtml(o.titulo)} <span class="estagio-badge est-${o.estagio}">${ESTAGIO_LBL[o.estagio]||o.estagio}</span>${semProximoPasso(o)?' <span class="badge-orfa">⚠ sem próximo passo</span>':''}</div>
          <div class="pf-card-sub">
            ${o.obra?`Obra: <b>${escHtml(o.obra)}</b> · `:''}
            ${o.seller_name?`Vendedor: ${escHtml(o.seller_name)} · `:''}
            ${o.valor_estimado!=null?`Valor: <b>${fMoeda(o.valor_estimado)}</b>`:''}
            ${o.callback_date?` · Retorno: <b>${fDataHora(o.callback_date)}</b>`:''}
          </div>
          ${(() => { const p = proximoPasso(o); return `<div class="pp pp-${p.urg}"><span class="pp-ico">${p.ico}</span><span class="pp-txt"><b>Próximo passo:</b> ${p.txt}</span></div>`; })()}
          <div class="pf-opp-actions">
            <button class="btn bg sm" onclick="abrInteracao('${o.id}','${c.id}')">Registrar interação</button>
            <button class="btn bac sm" onclick="abrCotacaoFromOpp('${o.id}','${c.id}')">Gerar proposta</button>
            <button class="btn bp sm" onclick="abrOpp('${c.id}','${o.id}')">Editar</button>
            <button class="btn bod sm" onclick="delOpp('${o.id}','${escHtml(o.titulo).replace(/'/g,"\\'")}')">✕</button>
          </div>
        </div>
      </div>`;
      }).join('')
    : `<div class="pf-empty">
        <span class="es-ico">🎯</span>
        <div class="es-tit">Sem oportunidades em aberto</div>
        <div class="es-msg">Crie uma oportunidade pra registrar produtos, agendar retornos e gerar propostas.</div>
        <button class="es-cta write-only" onclick="abrOpp('${c.id}')">+ Criar Oportunidade</button>
      </div>`;
  document.getElementById('pf-oportunidades').innerHTML = head + bulkBar + body;
}

function toggleOppSel(id, on) {
  if (on) pfOppSelected.add(id); else pfOppSelected.delete(id);
  const c = CL.find(x => x.id === pfClientId);
  if (c) renderPfOportunidades(c);
}

function bulkOppLimpar() {
  pfOppSelected.clear();
  const c = CL.find(x => x.id === pfClientId);
  if (c) renderPfOportunidades(c);
}

async function bulkOppEstagio(novoEstagio) {
  if (!pfOppSelected.size) return;
  const ids = [...pfOppSelected];
  conf('Mudar estágio', `Alterar ${ids.length} oportunidade(s) para "${ESTAGIO_LBL[novoEstagio]}"?`, async () => {
    try {
      const idsList = ids.map(i => `"${i}"`).join(',');
      await api('PATCH', 'opportunities', `id=in.(${idsList})`, { estagio: novoEstagio });
      toast('Estágio atualizado', `${ids.length} oportunidade(s) movida(s)`, 'success');
      pfOppSelected.clear();
      CL = await fetchCl();
      const c = CL.find(x => x.id === pfClientId);
      if (c) { renderPfOportunidades(c); renderPfResumo(c); }
      renderCl();
    } catch(err) {
      console.error('bulkOppEstagio:', err);
      toast('Erro', err.message||'', 'warning');
    }
  });
}

async function bulkOppExcluir() {
  if (!pfOppSelected.size) return;
  const ids = [...pfOppSelected];
  conf('⚠ Excluir oportunidades',
    `Remover ${ids.length} oportunidade(s) com produtos e interações relacionados? Não há volta.`,
    async () => {
      try {
        const idsList = ids.map(i => `"${i}"`).join(',');
        await apiDelete('opportunities', `id=in.(${idsList})`);
        toast('Excluídas', `${ids.length} oportunidade(s) removida(s)`, 'success');
        pfOppSelected.clear();
        CL = await fetchCl();
        const c = CL.find(x => x.id === pfClientId);
        if (c) { renderPfOportunidades(c); renderPfResumo(c); renderPfHistorico(c); }
        renderCl();
      } catch(err) {
        console.error('bulkOppExcluir:', err);
        toast('Erro', err.message||'', 'warning');
      }
    });
}

async function renderPfHistorico(c) {
  const el = document.getElementById('pf-historico');
  const opps = c.oportunidades || [];
  if (!opps.length) {
    el.innerHTML = '<div class="pf-empty">Sem oportunidades — sem histórico ainda. Crie uma oportunidade primeiro.</div>';
    return;
  }
  el.innerHTML = '<div class="sl"><div class="sp"></div></div>';
  try {
    const oppIds = opps.map(o => `"${o.id}"`).join(',');
    // Teto de 300. Esta era a unica consulta de TELA sem limite: um cliente
    // antigo, com varias oportunidades e anos de ligacoes registradas, traria
    // tudo de uma vez. E a disciplina nº 2 do guia e "toda conversa vira
    // interacao", entao isto cresce por design.
    // 300 e generoso pra rolar e ainda assim um teto: quem precisa do que ficou
    // antes disso usa a aba Alterações ou o backup.
    const LIM_INT = 300;
    const ints = await api('GET','interactions',`opportunity_id=in.(${oppIds})&select=*,seller:profiles(name)&order=datetime.desc&limit=${LIM_INT}`);
    if (!ints || !ints.length) {
      el.innerHTML = '<div class="pf-empty">Nenhuma interação registrada ainda.</div>';
      return;
    }
    // Agrupa por oportunidade
    const byOpp = new Map();
    ints.forEach(i => {
      if (!byOpp.has(i.opportunity_id)) byOpp.set(i.opportunity_id, []);
      byOpp.get(i.opportunity_id).push(i);
    });
    el.innerHTML = opps.filter(o => byOpp.has(o.id)).map(o => {
      const rows = byOpp.get(o.id).map(i => `
        <div class="pf-int-row">
          <div class="pf-int-meta">
            <span>${fDH(i.datetime)} · ${escHtml(i.seller?.name||'—')}</span>
            <span class="pf-int-result">${escHtml(i.result||'—')}</span>
          </div>
          ${i.notes?`<div class="pf-int-notes">${escHtml(i.notes)}</div>`:''}
          ${i.next_callback?`<div class="pf-int-cb">Próximo retorno: <b>${fDataHora(i.next_callback)}</b></div>`:''}
        </div>`).join('');
      return `<div style="margin-bottom:18px">
        <div style="font-size:13px;font-weight:600;color:var(--p);margin-bottom:8px">📋 ${escHtml(o.titulo)} <span class="estagio-badge est-${o.estagio}">${ESTAGIO_LBL[o.estagio]||o.estagio}</span></div>
        <div style="background:var(--sur);border:1px solid var(--bdr);border-radius:var(--rs)">${rows}</div>
      </div>`;
    }).join('')
    // Bateu no teto: diz que cortou. Truncar sem avisar faz o vendedor achar
    // que aquilo e o historico inteiro — e ele decide em cima disso.
    + (ints.length >= LIM_INT
        ? `<div class="pf-empty" style="margin-top:4px">Mostrando as <b>${LIM_INT}</b> interações mais recentes.
             As anteriores continuam no banco e saem no backup.</div>`
        : '');
  } catch(err) {
    console.error('renderPfHistorico:', err);
    el.innerHTML = '<div class="pf-empty" style="color:var(--er)">Erro ao carregar histórico: '+escHtml(err.message||'')+'</div>';
  }
}

// ── Render aba "Alterações" (Sprint 5.2 — audit log) ───────────────────
const AUDIT_TABLE_LBL = {
  companies: 'empresa', contacts: 'contato', opportunities: 'oportunidade',
  opportunity_products: 'produto', proposals: 'proposta'
};
const AUDIT_ACTION_LBL = { INSERT: 'criou', UPDATE: 'alterou', DELETE: 'excluiu' };
// Campos que não precisam aparecer na timeline (ruído)
const AUDIT_SKIP_FIELDS = new Set(['created_at','created_by','id','snapshot','company_id']);
// Labels mais amigáveis pros campos
const AUDIT_FIELD_LBL = {
  razao_social: 'Razão Social', nome_fantasia: 'Nome Fantasia', cnpj: 'CNPJ', ie: 'I.E.',
  email: 'Email', telefone: 'Telefone', website: 'Site', industria: 'Indústria',
  faturamento_estimado: 'Faturamento', endereco: 'Endereço', cidade: 'Cidade', uf: 'UF', cep: 'CEP',
  observacoes: 'Observações', internal_notes: 'Notas internas',
  classificacao: 'Classificação', lgpd_consent_at: 'LGPD consentimento',
  lgpd_delete_requested_at: 'LGPD exclusão solicitada',
  nome: 'Nome', cargo: 'Cargo', papel: 'Papel', principal: 'Principal',
  titulo: 'Título', obra: 'Obra', estagio: 'Estágio', valor_estimado: 'Valor',
  callback_date: 'Próximo retorno', perda_motivo: 'Motivo da perda', observation: 'Observação',
  seller_name: 'Vendedor', seller_id: 'Vendedor (ID)', contact_id: 'Contato',
  produto: 'Produto', embalagem: 'Embalagem', qtd_kg: 'Qtd (kg)', preco_kg: 'Preço (R$/kg)',
  ano: 'Ano', numero: 'Número', opportunity_id: 'Oportunidade (ID)',
};

function fmtAuditVal(v) {
  if (v === null || v === undefined) return '<em style="color:var(--mt2)">(vazio)</em>';
  if (typeof v === 'boolean') return v ? 'sim' : 'não';
  const s = String(v);
  if (s.length > 60) return escHtml(s.slice(0,60)) + '…';
  return escHtml(s);
}

async function renderPfAlteracoes(c) {
  const el = document.getElementById('pf-alteracoes');
  if (!el) return;
  el.innerHTML = '<div class="sl"><div class="sp"></div></div>';
  try {
    // Busca audit do company_id (inclui filhas via company_id que o trigger preenche)
    const rows = await api('GET','audit_log', `company_id=eq.${c.id}&select=*&order=created_at.desc&limit=200`);
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="pf-empty">Sem registros de alteração ainda. Cada criação, edição ou exclusão será registrada aqui automaticamente.</div>';
      return;
    }
    el.innerHTML = rows.map(r => {
      const tableLbl = AUDIT_TABLE_LBL[r.table_name] || r.table_name;
      const actionLbl = AUDIT_ACTION_LBL[r.action] || r.action;
      const who = r.user_name || '(sistema)';
      let body = '';
      if (r.action === 'UPDATE' && Array.isArray(r.changes) && r.changes.length) {
        body = '<div class="al-changes">' + r.changes
          .filter(ch => !AUDIT_SKIP_FIELDS.has(ch.field))
          .map(ch => `<div><b>${escHtml(AUDIT_FIELD_LBL[ch.field] || ch.field)}:</b> <span class="al-from">${fmtAuditVal(ch.from)}</span> → <span class="al-to">${fmtAuditVal(ch.to)}</span></div>`)
          .join('') + '</div>';
      } else if (r.action === 'INSERT') {
        const d = r.new_data || {};
        const titulo = d.razao_social || d.titulo || d.nome || d.produto || '';
        body = titulo ? `<div class="al-changes">"${escHtml(titulo)}"</div>` : '';
      } else if (r.action === 'DELETE') {
        const d = r.old_data || {};
        const titulo = d.razao_social || d.titulo || d.nome || d.produto || '';
        body = titulo ? `<div class="al-changes">"${escHtml(titulo)}"</div>` : '';
      }
      return `<div class="al-item">
        <div class="al-dot al-${r.action}"></div>
        <div class="al-main">
          <div class="al-head"><b>${escHtml(who)}</b> ${actionLbl} ${tableLbl} — ${fDH(r.created_at)}</div>
          ${body}
        </div>
      </div>`;
    }).join('');
  } catch(err) {
    console.error('renderPfAlteracoes:', err);
    el.innerHTML = '<div class="pf-empty" style="color:var(--er)">Erro ao carregar histórico: '+escHtml(err.message||'')+'</div>';
  }
}
