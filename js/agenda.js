/* ==========================================================================
   agenda.js - a agenda e o que ela mostra. Sprint 8.1g, 2026-08-19.

   Reune tres coisas que sempre foram o mesmo assunto e estavam separadas no
   inline: as TAREFAS livres (Sprint 6.2), a tela HOJE/AGENDA em lista ou
   calendario mensal (6.1+6.2) e a EXPORTACAO .ics. `eventosAgenda()` e a
   juncao que justifica o modulo - ela unifica callback de oportunidade e
   tarefa livre num formato so, e as tres telas leem dela.

   O backup manual (`apiTudo`/`baixarBackup`) ficou no inline de proposito:
   estava escrito debaixo do cabecalho do .ics, mas e outro assunto e vive
   com o Dashboard, que e onde fica o botao.

   CARREGA DEPOIS de format.js (dtToInput, inputToISO, fRel, fMoeda, escHtml)
   e api.js. Consome do inline, sempre em tempo de execucao: CL, TASKS, ME,
   MEP, ESTAGIO_LBL, fetchTasks, updateBell, todasOpps, toast, deferComUndo,
   abrPerfil, abrInteracao.

   ⚠ UNICA LINHA QUE EXECUTA NA CARGA: o addEventListener do form de tarefa.
   Usa `?.` porque em modulo um erro ali impede TODAS as funcoes abaixo de
   existirem - a tela Hoje sumiria inteira por causa de um id trocado.
   ========================================================================== */

// ── Sprint 6.2: CRUD de Tarefas livres ────────────────────────────────────
let TASK_EID = null;

function popularTaskEmpresas() {
  const sel = document.getElementById('task-emp');
  if (!sel) return;
  const cur = sel.value;
  sel.innerHTML = '<option value="">— Sem empresa —</option>' +
    CL.map(c => `<option value="${c.id}">${escHtml(c.razao_social)}</option>`).join('');
  sel.value = cur || '';
}

function abrTaskNova(preDate) {
  TASK_EID = null;
  document.getElementById('task-m-titulo').textContent = 'Nova Tarefa';
  document.getElementById('task-del-btn').style.display = 'none';
  document.getElementById('task-tit').value = '';
  document.getElementById('task-desc').value = '';
  document.getElementById('task-emp').value = '';
  // default: hoje 17:00 (ou data sugerida 09:00)
  const d = preDate ? new Date(preDate) : new Date();
  if (!preDate) d.setHours(17,0,0,0); else d.setHours(9,0,0,0);
  document.getElementById('task-due').value = dtToInput(d.toISOString());
  popularTaskEmpresas();
  document.getElementById('task-m').classList.add('op');
  setTimeout(()=>document.getElementById('task-tit').focus(), 100);
}

function abrTaskEdit(id) {
  const t = TASKS.find(x => x.id === id);
  if (!t) return;
  TASK_EID = id;
  document.getElementById('task-m-titulo').textContent = 'Editar Tarefa';
  document.getElementById('task-del-btn').style.display = (t.seller_id === ME?.id || ME?.role === 'admin') ? '' : 'none';
  document.getElementById('task-tit').value = t.titulo || '';
  document.getElementById('task-desc').value = t.descricao || '';
  popularTaskEmpresas();
  document.getElementById('task-emp').value = t.company_id || '';
  document.getElementById('task-due').value = dtToInput(t.due_at);
  document.getElementById('task-m').classList.add('op');
}

function fechaTask() {
  document.getElementById('task-m').classList.remove('op');
  TASK_EID = null;
}

document.getElementById('task-f')?.addEventListener('submit', async e => {
  e.preventDefault();
  const btn = document.getElementById('task-sub');
  btn.disabled = true; btn.textContent = 'Salvando...';
  const payload = {
    titulo:     document.getElementById('task-tit').value.trim(),
    descricao:  document.getElementById('task-desc').value.trim() || null,
    due_at:     inputToISO(document.getElementById('task-due').value),
    company_id: document.getElementById('task-emp').value || null,
  };
  try {
    if (TASK_EID) {
      await api('PATCH','tasks',`id=eq.${TASK_EID}`, payload);
    } else {
      await api('POST','tasks',null, { ...payload, seller_id: ME.id });
    }
    TASKS = await fetchTasks();
    fechaTask();
    renderToday();
    updateBell();
    toast(TASK_EID ? 'Tarefa atualizada' : 'Tarefa criada', '', 'success');
  } catch(err) {
    toast('Erro ao salvar tarefa', err.message||'', 'warning');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar';
  }
});

async function toggleTaskDone(id, done) {
  try {
    await api('PATCH','tasks',`id=eq.${id}`, { done });
    TASKS = await fetchTasks();
    renderToday();
    updateBell();
  } catch(err) {
    toast('Erro ao atualizar tarefa', err.message||'', 'warning');
  }
}

function deletarTask() {
  if (!TASK_EID) return;
  const id = TASK_EID;
  const t  = TASKS.find(x => x.id === id);
  const tit = t?.titulo || 'tarefa';
  // Esconde da UI imediatamente; deleta no DB so apos 7s se nao desfizer
  TASKS = TASKS.filter(x => x.id !== id);
  fechaTask();
  renderToday(); updateBell();
  deferComUndo('Tarefa excluída', tit, async () => {
    await api('DELETE','tasks',`id=eq.${id}`);
    TASKS = await fetchTasks();
    renderToday(); updateBell();
  }, 'Exclusão cancelada');
}

// ── Sprint 6.1+6.2: Tela "Hoje/Agenda" — Lista ou Calendario Mensal ───────
let TD_VIEW = 'lista';
let CAL_REF = null; // 1o dia do mes que esta sendo exibido no calendario

function setTodayView(v) {
  TD_VIEW = v;
  document.querySelectorAll('.td-sw').forEach(b => b.classList.toggle('ac', b.dataset.view === v));
  renderToday();
}

// Unifica callbacks de oportunidades + tarefas livres num formato comum,
// ja filtrado pelo "so meus" se aplicavel.
function eventosAgenda() {
  const soMeus = document.getElementById('td-meus')?.checked;
  const meuId = ME?.id;
  const meuNome = MEP?.name;
  const mineSeller = o => !soMeus || (meuId && o.seller_id === meuId) || (meuNome && o.seller_name === meuNome);

  const opps = todasOpps()
    .filter(o => o.estagio !== 'ganha' && o.estagio !== 'perdida')
    .filter(o => o.callback_date)
    .filter(mineSeller)
    .map(o => ({
      tipo:        'cb',
      id:          'o:'+o.id,
      raw_id:      o.id,
      at:          new Date(o.callback_date).getTime(),
      atISO:       o.callback_date,
      titulo:      o.titulo || '—',
      empresa:     o.company_nome || '—',
      company_id:  o.company_id,
      seller_name: o.seller_name,
      estagio:     o.estagio,
      obra:        o.obra,
      valor:       o.valor_estimado,
      done:        false,
    }));

  const tks = (TASKS||[])
    .filter(t => !soMeus || (meuId && t.seller_id === meuId))
    .map(t => ({
      tipo:        'task',
      id:          't:'+t.id,
      raw_id:      t.id,
      at:          new Date(t.due_at).getTime(),
      atISO:       t.due_at,
      titulo:      t.titulo,
      descricao:   t.descricao,
      empresa:     t.company?.razao_social || null,
      company_id:  t.company_id,
      seller_name: t.seller?.name,
      seller_id:   t.seller_id,
      done:        !!t.done,
    }));

  return [...opps, ...tks];
}

function renderToday() {
  const saud = document.getElementById('td-saud');
  const dataEl = document.getElementById('td-data');
  const body = document.getElementById('td-body');
  if (!body) return;

  // Saudacao por hora do dia
  const agora = new Date();
  const h = agora.getHours();
  const eu  = (MEP?.name || ME?.email || '').split(/[\s@]/)[0];
  const cum = h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
  saud.textContent = `${cum}${eu?', '+eu:''}!`;
  dataEl.textContent = agora.toLocaleDateString('pt-BR', { weekday:'long', day:'2-digit', month:'long', year:'numeric' });

  if (TD_VIEW === 'mes') renderCalendarioMes(body);
  else renderListaHoje(body);
}

// Sprint 7.1: normaliza telefone pra link do WhatsApp.
// Prefixa 55 (Brasil) por COMPRIMENTO, nao por prefixo — evita confundir o
// codigo do pais 55 com o DDD 55 (RS). 10/11 digitos = falta cod. pais.
function foneParaWa(fone) {
  if (!fone) return null;
  const d = String(fone).replace(/\D/g, '');
  if (d.length < 10) return null;          // incompleto
  return d.length <= 11 ? '55' + d : d;    // 10/11 = DDD+numero; 12/13 = ja tem 55
}

// Sprint 7.1: telefone do contato principal de uma empresa (ou 1o com telefone)
function contatoPrincipalFone(companyId) {
  const c = CL.find(x => x.id === companyId);
  if (!c) return null;
  const cts = c.contatos || [];
  const ct = cts.find(x => x.principal && x.telefone) || cts.find(x => x.telefone);
  return ct?.telefone || null;
}

function renderListaHoje(body) {
  const evs = eventosAgenda();
  const agoraMs = Date.now();
  const fimHoje = new Date(); fimHoje.setHours(23,59,59,999);
  const fimHojeMs = fimHoje.getTime();
  const fim3d = new Date(fimHojeMs + 3*86400000).getTime();

  const atrasados = evs.filter(e => !e.done && e.at < agoraMs).sort((a,b)=>b.at-a.at);
  const hoje      = evs.filter(e => !e.done && e.at >= agoraMs && e.at <= fimHojeMs).sort((a,b)=>a.at-b.at);
  const proximos  = evs.filter(e => !e.done && e.at > fimHojeMs && e.at <= fim3d).sort((a,b)=>a.at-b.at);

  const linha = (e, late=false) => {
    const dt = new Date(e.at);
    const horaTxt = dt.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
    const diaTxt = dt.toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit'});
    const mostraDia = late || (e.at > fimHojeMs);
    if (e.tipo === 'task') {
      return `<div class="td-row td-task ${e.done?'done':''}">
        <input type="checkbox" class="td-task-check" ${e.done?'checked':''} onclick="event.stopPropagation();toggleTaskDone('${e.raw_id}',this.checked)" title="Marcar como concluida">
        <div class="td-time ${late?'td-late-time':''}">${horaTxt}<small>${mostraDia?diaTxt:'hoje'}</small></div>
        <div class="td-info" onclick="abrTaskEdit('${e.raw_id}')" style="cursor:pointer">
          <div class="td-emp"><span class="td-tipo">Tarefa</span>${escHtml(e.titulo)}</div>
          ${e.empresa?`<div class="td-tit">${escHtml(e.empresa)}</div>`:''}
          <div class="td-meta">
            <span>${escHtml(e.seller_name||'—')}</span>
            ${e.descricao?`<span>${escHtml(e.descricao.slice(0,60))}${e.descricao.length>60?'...':''}</span>`:''}
            ${late?`<span style="color:var(--er);font-weight:600">${fRel(e.atISO)}</span>`:''}
          </div>
        </div>
        <button class="td-task-edit" onclick="event.stopPropagation();abrTaskEdit('${e.raw_id}')">Editar</button>
      </div>`;
    }
    // callback de oportunidade — Sprint 7.1: acoes rapidas que nao disparam o onclick da linha
    const fone = contatoPrincipalFone(e.company_id);
    const wa = foneParaWa(fone);
    const waSvg = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M.057 24l1.687-6.163c-1.041-1.804-1.588-3.849-1.587-5.946.003-6.556 5.338-11.891 11.893-11.891 3.181.001 6.167 1.24 8.413 3.488 2.245 2.248 3.481 5.236 3.48 8.414-.003 6.557-5.338 11.892-11.893 11.892-1.99-.001-3.951-.5-5.688-1.448l-6.305 1.654zm6.597-3.807c1.676.995 3.276 1.591 5.392 1.592 5.448 0 9.886-4.434 9.889-9.885.002-5.462-4.415-9.89-9.881-9.892-5.452 0-9.887 4.434-9.889 9.884-.001 2.225.651 3.891 1.746 5.634l-.999 3.648 3.742-.981zm11.387-5.464c-.074-.124-.272-.198-.57-.347-.297-.149-1.758-.868-2.031-.967-.272-.099-.47-.149-.669.149-.198.297-.768.967-.941 1.165-.173.198-.347.223-.644.074-.297-.149-1.255-.462-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.297-.347.446-.521.151-.172.2-.296.3-.495.099-.198.05-.372-.025-.521-.075-.148-.669-1.611-.916-2.206-.242-.579-.487-.501-.669-.51l-.57-.01c-.198 0-.52.074-.792.372s-1.04 1.016-1.04 2.479 1.065 2.876 1.213 3.074c.149.198 2.096 3.2 5.077 4.487.709.306 1.263.489 1.694.626.712.226 1.36.194 1.872.118.571-.085 1.758-.719 2.006-1.413.248-.695.248-1.29.173-1.414z"/></svg>';
    const acoes = `<div class="td-acoes">
      ${wa?`<a class="td-act td-act-wa" href="https://wa.me/${wa}" target="_blank" rel="noopener" onclick="event.stopPropagation()" title="WhatsApp ${escHtml(fone)}">${waSvg}</a>`:''}
      ${wa?`<a class="td-act" href="tel:+${wa}" onclick="event.stopPropagation()" title="Ligar ${escHtml(fone)}">📞</a>`:''}
      <button class="td-act td-act-reg" onclick="event.stopPropagation();abrInteracao('${e.raw_id}','${e.company_id}','hoje')" title="Registrar interação">✓</button>
    </div>`;
    return `<div class="td-row" onclick="abrPerfil('${e.company_id}')">
      <div class="td-time ${late?'td-late-time':''}">${horaTxt}<small>${mostraDia?diaTxt:'hoje'}</small></div>
      <div class="td-info">
        <div class="td-emp"><span class="td-tipo cb">Retorno</span>${escHtml(e.empresa)} <span class="td-est">${ESTAGIO_LBL?.[e.estagio]||e.estagio}</span></div>
        <div class="td-tit">${escHtml(e.titulo)}</div>
        <div class="td-meta">
          <span>${escHtml(e.seller_name||'Sem vendedor')}</span>
          ${e.obra?`<span>Obra: ${escHtml(e.obra)}</span>`:''}
          ${e.valor!=null?`<span>${fMoeda(e.valor)}</span>`:''}
          ${late?`<span style="color:var(--er);font-weight:600">${fRel(e.atISO)}</span>`:''}
        </div>
      </div>
      ${acoes}
    </div>`;
  };

  // Secao vazia fica COMPACTA: titulo e mensagem na mesma linha. Do jeito
  // antigo cada bloco vazio comia ~116px de altura pra dizer que nao havia
  // nada, e num dia calmo os dois somavam ~230px da primeira tela — a tela
  // que a equipe abre primeiro todo dia. A informacao continua ali; o que sai
  // e o espaco em branco.
  const sec = (titulo, lista, badgeCls, vazia) => `
    <div class="td-sec${lista.length ? '' : ' td-sec-vazia'}">
      <div class="td-sec-h">
        <h3>${titulo} <span class="td-badge ${badgeCls}">${lista.length}</span></h3>
        ${lista.length ? '' : `<span class="td-vazia-msg">${vazia}</span>`}
      </div>
      ${lista.length ? lista.map(e=>linha(e, badgeCls==='td-late')).join('') : ''}
    </div>`;

  body.innerHTML =
    sec('⚠ Atrasados', atrasados, 'td-late', 'Nenhum retorno atrasado. ') +
    sec('Hoje', hoje, 'td-now', 'Nenhum retorno agendado pra hoje.') +
    sec('Próximos 3 dias', proximos, 'td-soon', 'Agenda livre nos próximos 3 dias.');
}

function renderCalendarioMes(body) {
  if (!CAL_REF) {
    CAL_REF = new Date();
    CAL_REF.setDate(1); CAL_REF.setHours(0,0,0,0);
  }
  const ano = CAL_REF.getFullYear();
  const mes = CAL_REF.getMonth();
  const primDia = new Date(ano, mes, 1);
  const ultDia  = new Date(ano, mes+1, 0);
  // Comeca no domingo da semana do dia 1
  const inicio = new Date(primDia);
  inicio.setDate(inicio.getDate() - inicio.getDay());
  // Termina no sabado da semana do ultimo dia
  const fim = new Date(ultDia);
  fim.setDate(fim.getDate() + (6 - fim.getDay()));

  // Agrupa eventos por dia YYYY-MM-DD
  const evs = eventosAgenda();
  const porDia = new Map();
  evs.forEach(e => {
    const d = new Date(e.at);
    const k = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    if (!porDia.has(k)) porDia.set(k, []);
    porDia.get(k).push(e);
  });

  const hojeKey = (()=>{ const t=new Date(); return `${t.getFullYear()}-${String(t.getMonth()+1).padStart(2,'0')}-${String(t.getDate()).padStart(2,'0')}`;})();
  const agoraMs = Date.now();

  const dows = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'];
  let html = `<div class="cal-wrap">
    <div class="cal-nav">
      <h3>${primDia.toLocaleDateString('pt-BR',{month:'long',year:'numeric'})}</h3>
      <div class="cal-nav-btns">
        <button class="cal-nav-btn" onclick="calNav(-1)" title="Mês anterior">‹</button>
        <button class="cal-nav-btn cal-nav-today" onclick="calNav(0)" title="Hoje">Hoje</button>
        <button class="cal-nav-btn" onclick="calNav(1)" title="Próximo mês">›</button>
      </div>
    </div>
    <div class="cal-grid">
      ${dows.map(d=>`<div class="cal-dow">${d}</div>`).join('')}`;

  const cur = new Date(inicio);
  while (cur <= fim) {
    const k = `${cur.getFullYear()}-${String(cur.getMonth()+1).padStart(2,'0')}-${String(cur.getDate()).padStart(2,'0')}`;
    const outroMes = cur.getMonth() !== mes;
    const eHoje = k === hojeKey;
    const eventosDia = (porDia.get(k) || []).sort((a,b)=>a.at-b.at);
    const top3 = eventosDia.slice(0,3);
    const extra = eventosDia.length - top3.length;
    const evHtml = top3.map(e => {
      const cls = e.done ? 'ev-done' : (e.tipo==='task' ? 'ev-task' : (e.at < agoraMs ? 'ev-late' : ''));
      const tipoCls = e.tipo === 'task' ? 'ev-task' : '';
      const t = new Date(e.at).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
      const click = e.tipo==='task' ? `abrTaskEdit('${e.raw_id}')` : `abrPerfil('${e.company_id}')`;
      return `<div class="cal-ev ${cls||tipoCls}" onclick="event.stopPropagation();${click}" title="${escHtml(e.empresa||e.titulo)}">${t} ${escHtml(e.tipo==='task'?e.titulo:(e.empresa||e.titulo))}</div>`;
    }).join('');
    const moreLink = extra > 0 ? `<div class="cal-ev-more">+${extra}</div>` : '';
    const cellCls = ['cal-cell', outroMes?'cal-other':'', eHoje?'cal-today':''].filter(Boolean).join(' ');
    html += `<div class="${cellCls}" onclick="abrTaskNova('${cur.toISOString()}')" title="Clique pra criar tarefa">
      <div class="cal-day">${cur.getDate()}</div>
      ${evHtml}${moreLink}
    </div>`;
    cur.setDate(cur.getDate()+1);
  }

  html += `</div></div>`;
  body.innerHTML = html;
}

function calNav(dir) {
  if (!CAL_REF) { CAL_REF = new Date(); CAL_REF.setDate(1); CAL_REF.setHours(0,0,0,0); }
  if (dir === 0) {
    CAL_REF = new Date(); CAL_REF.setDate(1); CAL_REF.setHours(0,0,0,0);
  } else {
    CAL_REF.setMonth(CAL_REF.getMonth() + dir);
  }
  renderToday();
}

function exportarICS() {
  const evs = eventosAgenda().filter(e => !e.done);
  if (!evs.length) {
    toast('Nada pra exportar', 'Sem retornos nem tarefas pendentes', 'warning');
    return;
  }
  // ICS exige UTC no formato YYYYMMDDTHHMMSSZ
  const toICS = ts => {
    const d = new Date(ts);
    const pad = n => String(n).padStart(2,'0');
    return `${d.getUTCFullYear()}${pad(d.getUTCMonth()+1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
  };
  // Escapa caracteres especiais segundo RFC 5545
  const esc = s => String(s||'').replace(/\\/g,'\\\\').replace(/;/g,'\\;').replace(/,/g,'\\,').replace(/\n/g,'\\n');

  const now = toICS(Date.now());
  const ev = evs.map(e => {
    const start = e.at;
    const end   = start + 30*60*1000; // 30 min default
    const titulo = e.tipo === 'task'
      ? `[Tarefa] ${e.titulo}`
      : `[Retorno] ${e.empresa} — ${e.titulo}`;
    const desc = e.tipo === 'task'
      ? (e.descricao || '') + (e.empresa ? `\\nEmpresa: ${e.empresa}` : '')
      : `Oportunidade: ${e.titulo}\\nVendedor: ${e.seller_name||'—'}${e.obra?`\\nObra: ${e.obra}`:''}`;
    return `BEGIN:VEVENT
UID:${e.id}@adiblock-crm
DTSTAMP:${now}
DTSTART:${toICS(start)}
DTEND:${toICS(end)}
SUMMARY:${esc(titulo)}
DESCRIPTION:${esc(desc)}
${e.empresa ? 'LOCATION:'+esc(e.empresa) : ''}
END:VEVENT`;
  }).join('\n');

  const ics = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Adiblock//CRM Comercial//PT-BR
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-CALNAME:Agenda Adiblock${MEP?.name?' — '+MEP.name:''}
X-WR-TIMEZONE:America/Sao_Paulo
${ev}
END:VCALENDAR`;

  const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  const stamp = new Date().toISOString().slice(0,10);
  a.download = `agenda-adiblock-${stamp}.ics`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  toast('Agenda exportada', `${evs.length} evento(s) no .ics`, 'success');
}
