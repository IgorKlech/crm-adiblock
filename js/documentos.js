/* ==========================================================================
   documentos.js — os quatro papeis imprimiveis do CRM.
   Sprint 8.1d (modularizacao), 17/08/2026.

   Junta o que a secao 8 do CLAUDE.md trata como um dominio so:
     Proposta Comercial  -> cliente  · oferta        (renderCotacao)
     Pedido de Producao  -> fabrica  · instrui       (renderPedidoProducao)
     Pedido Comercial    -> cliente  · confirma      (renderPedidoComercial)

   No index.html isso vivia em dois trechos separados por 1.100 linhas de
   codigo de outro assunto. Aqui ficam lado a lado, que e como se pensa neles.

   CARREGA DEPOIS de config.js/api.js/format.js e ANTES do <script> inline.
   Tudo global, sem bundler — as funcoes daqui sao chamadas por onclick no HTML
   e por codigo do inline; as que elas usam (escHtml, fMoeda, ADIBLOCK_INFO,
   PROPOSTAS...) so sao lidas em tempo de execucao, nunca no carregamento.

   `let PROP_ATUAL` mora aqui: e o documento aberto no momento, e quem mais
   mexe nele sao estas funcoes.
   ========================================================================== */

function fecharCotacao() {
  document.getElementById('cot-page').classList.remove('op');
  document.body.style.overflow = '';
}

// ── Sprint 6.4: Pedido de Producao (para fabrica, sem valores) ────────────
let PROP_ATUAL = null;

function abrirModalPedidoProducao() {
  if (!PROP_ATUAL) { toast('Sem proposta carregada','','warning'); return; }
  // Default do solicitante: nome do contato responsavel da proposta
  const solicDefault = PROP_ATUAL.snapshot?.cliente?.contato_outros?.split('(')[0]?.trim() || '';
  document.getElementById('prod-req-solic').value = solicDefault;
  document.getElementById('prod-req-obs').value = '';
  document.getElementById('prod-req-m').classList.add('op');
  setTimeout(() => document.getElementById('prod-req-solic').focus(), 80);
}

// `?.` de proposito: este e um dos dois trechos que EXECUTAM no carregamento
// do modulo. Sem ele, um #prod-req-f ausente lanca TypeError, para o arquivo
// no meio e as funcoes declaradas ABAIXO nunca chegam a existir — inclusive
// renderCotacao. Um formulario faltando vira um botao que nao envia; nao pode
// virar "nenhum documento abre".
document.getElementById('prod-req-f')?.addEventListener('submit', e => {
  e.preventDefault();
  const solic = document.getElementById('prod-req-solic').value.trim();
  const obs   = document.getElementById('prod-req-obs').value.trim();
  if (!solic) return;
  document.getElementById('prod-req-m').classList.remove('op');
  renderPedidoProducao(PROP_ATUAL, solic, obs);
  // Esconde a cot-page por baixo (senao a impressao leva as duas paginas juntas)
  document.getElementById('cot-page').classList.remove('op');
  document.getElementById('prod-page').classList.add('op');
  document.getElementById('prod-page').scrollTop = 0;
  document.body.style.overflow = 'hidden';
});

function fecharProducao() {
  document.getElementById('prod-page').classList.remove('op');
  // Volta a mostrar a proposta original por baixo
  document.getElementById('cot-page').classList.add('op');
}

// ── Pedido Comercial (2026-08-14) ─────────────────────────────────────────
// O terceiro documento: a Proposta oferta, o Pedido de Producao instrui a
// fabrica, e este CONFIRMA pro cliente o pedido fechado — no numero de OC
// DELE, que e por onde ele cobra, confere e paga.
//
// OC, transportadora e entrega moram em COLUNA (nao no snapshot): sao dados
// de cumprimento, chegam depois, e o snapshot e o que foi negociado.

function abrirModalPedidoComercial() {
  const p = PROP_ATUAL;
  if (!p) { toast('Sem proposta carregada','','warning'); return; }
  const snap = p.snapshot || {};
  const c = snap.cliente || {};
  document.getElementById('pcom-oc').value     = p.oc_numero || '';
  // Transportadora e a mesma coluna que a expedicao usa — nao duplicar
  document.getElementById('pcom-transp').value = p.transportadora || '';
  document.getElementById('pcom-prev').value   = p.entrega_previsao || '';
  // Default do local: a obra da oportunidade, senao o endereco do cliente
  document.getElementById('pcom-local').value  = p.entrega_local
    || c.obra
    || [c.endereco, c.cidade && c.uf ? c.cidade+'/'+c.uf : (c.cidade||c.uf||'')].filter(Boolean).join(' — ')
    || '';
  document.getElementById('pcom-erro').textContent = '';
  document.getElementById('pcom-m').classList.add('op');
  setTimeout(() => document.getElementById('pcom-oc')?.focus(), 80);
}

document.getElementById('pcom-f')?.addEventListener('submit', async e => {
  e.preventDefault();
  const p = PROP_ATUAL;
  const err = document.getElementById('pcom-erro');
  err.textContent = '';
  if (!p) return;
  const dados = {
    oc_numero:        document.getElementById('pcom-oc').value.trim() || null,
    transportadora:   document.getElementById('pcom-transp').value.trim() || null,
    entrega_previsao: document.getElementById('pcom-prev').value || null,
    entrega_local:    document.getElementById('pcom-local').value.trim() || null,
  };
  const btn = document.getElementById('pcom-sub');
  btn.disabled = true; btn.textContent = 'Salvando...';
  try {
    await api('PATCH', 'proposals', `id=eq.${p.id}`, dados);
    PROP_ATUAL = { ...p, ...dados };
    const idx = PROPOSTAS.findIndex(x => x.id === p.id);
    if (idx >= 0) PROPOSTAS[idx] = PROP_ATUAL;

    document.getElementById('pcom-m').classList.remove('op');
    renderPedidoComercial(PROP_ATUAL);
    // Esconde a cot-page por baixo, senao a impressao leva as duas paginas
    // juntas (mesmo motivo do fix do Sprint 6.4 no Pedido de Producao).
    document.getElementById('cot-page').classList.remove('op');
    const page = document.getElementById('pcom-page');
    page.classList.add('op'); page.scrollTop = 0;
    document.body.style.overflow = 'hidden';
    if (document.getElementById('pr-view')?.classList.contains('ac')) renderPropostas();
  } catch(ex) {
    console.error('pedido comercial:', ex);
    err.textContent = /oc_numero|entrega_/i.test(ex.message||'')
      ? 'O banco ainda não tem as colunas do Pedido Comercial. Rode migrations/2026-08-14-pedido-comercial.sql.'
      : (ex.message || 'Não foi possível salvar.');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar e gerar';
  }
});

function fecharPedidoComercial() {
  document.getElementById('pcom-page').classList.remove('op');
  document.getElementById('cot-page').classList.add('op');
}

function renderPedidoComercial(prop) {
  const snap  = prop.snapshot || {};
  const c     = snap.cliente || {};
  const cond  = snap.condicoes || {};
  const consultor = snap.consultor || {};
  const prods = snap.produtos || [];

  const pedLabel = numPedido(prop) || numProposta(prop);
  const dataStr  = new Date().toLocaleDateString('pt-BR');
  const frete    = Number(cond.frete_valor) || 0;

  let subtotal = 0, ipiTotal = 0;
  const linhas = prods.map((p, i) => {
    const q  = Number(p.qtd_kg)  || 0;
    const pr = Number(p.preco_kg)|| 0;
    const sub = q * pr;
    const ipi = sub * ((Number(p.ipi)||0)/100);
    subtotal += sub; ipiTotal += ipi;
    return `<tr>
      <td class="num">${p.item || i+1}</td>
      <td><b>${escHtml(p.produto||'—')}</b>${p.embalagem?`<div class="pcom-emb">${escHtml(p.embalagem)}</div>`:''}</td>
      <td class="num">${q.toLocaleString('pt-BR')}</td>
      <td class="num">${fmtBRL(pr)}</td>
      <td class="num">${fmtBRL(sub + ipi)}</td>
    </tr>`;
  }).join('');
  const total = subtotal + ipiTotal + frete;

  const entregaPrev = prop.entrega_previsao ? fData(prop.entrega_previsao) : null;

  document.getElementById('pcom-body').innerHTML = `<div class="cot-body">
    <div class="cot-header">
      <div class="cot-logo-wrap">
        <img src="assets/img/logo-adiblock.svg" alt="Adiblock">
        <div>
          <div class="cot-title">Adiblock — Aditivos para Concretos</div>
          <div class="cot-h1">Pedido Comercial</div>
        </div>
      </div>
      <div class="cot-meta">
        <div>Pedido: <b>${escHtml(pedLabel)}</b></div>
        ${(prop.revisao||1) > 1 ? `<div>Revisão: <b>${prop.revisao}</b></div>` : ''}
        <div>Emissão: <b>${dataStr}</b></div>
      </div>
    </div>

    <!-- A OC do cliente e o dado mais importante da folha: e o numero pelo
         qual ELE se refere ao pedido. Por isso vem em destaque, no topo. -->
    ${prop.oc_numero ? `<div class="pcom-oc-box">
      <span>Ordem de compra do cliente</span>
      <b>${escHtml(prop.oc_numero)}</b>
    </div>` : `<div class="pcom-oc-box pcom-oc-vazia">
      <span>Ordem de compra do cliente</span>
      <b>não informada</b>
    </div>`}

    <div class="cot-2col">
      <div>
        <div class="cot-sect-title">Cliente</div>
        <div class="cot-info-list">
          <div><span>Nome:</span> <b>${escHtml(c.name||'—')}</b></div>
          ${c.cnpj?`<div><span>CNPJ/CPF:</span> <b>${escHtml(c.cnpj)}</b></div>`:''}
          ${c.ie?`<div><span>I.E.:</span> ${escHtml(c.ie)}</div>`:''}
          ${c.contato_outros?`<div><span>Solicitante:</span> <b>${escHtml(c.contato_outros)}</b></div>`:''}
          ${c.phone?`<div><span>Telefone:</span> ${escHtml(c.phone)}</div>`:''}
        </div>
      </div>
      <div>
        <div class="cot-sect-title">Entrega</div>
        <div class="cot-info-list">
          <div><span>Local:</span> <b>${escHtml(prop.entrega_local || c.obra || '—')}</b></div>
          <div><span>Frete:</span> ${escHtml(cond.frete||'—')}${frete>0?' · '+fmtBRL(frete):''}</div>
          <div><span>Transportadora:</span> ${escHtml(prop.transportadora||'a definir')}</div>
          ${entregaPrev?`<div><span>Previsão:</span> <b>${escHtml(entregaPrev)}</b></div>`:''}
          ${prop.nf_numero?`<div><span>Nota fiscal:</span> <b>${escHtml(prop.nf_numero)}</b></div>`:''}
        </div>
      </div>
    </div>

    <div class="cot-sect-title" style="margin-top:18px">Itens do pedido</div>
    <table class="cot-tab pcom-tab">
      <thead><tr>
        <th class="num" style="width:38px">Item</th>
        <th>Produto</th>
        <th class="num" style="width:90px">Qtd (kg)</th>
        <th class="num" style="width:90px">R$/kg</th>
        <th class="num" style="width:110px">Total</th>
      </tr></thead>
      <tbody>${linhas || '<tr><td colspan="5" style="text-align:center;color:var(--mt)">— sem itens —</td></tr>'}</tbody>
      <tfoot>
        <tr><td colspan="4" class="cot-total-lbl">Subtotal</td><td class="num cot-total-val">${fmtBRL(subtotal)}</td></tr>
        ${ipiTotal>0?`<tr><td colspan="4" class="cot-total-lbl">IPI</td><td class="num cot-total-val">${fmtBRL(ipiTotal)}</td></tr>`:''}
        ${frete>0?`<tr><td colspan="4" class="cot-total-lbl">Frete</td><td class="num cot-total-val">${fmtBRL(frete)}</td></tr>`:''}
        <tr><td colspan="4" class="cot-total-lbl">Total do pedido</td><td class="num cot-total-val">${fmtBRL(total)}</td></tr>
      </tfoot>
    </table>

    <div class="cot-2col" style="margin-top:18px">
      <div>
        <div class="cot-sect-title">Condições</div>
        <div class="cot-info-list">
          <div><span>Pagamento:</span> <b>${escHtml(cond.prazo_pagamento||'—')}</b></div>
          <div><span>Consultor:</span> ${escHtml(consultor.nome||'—')}</div>
          ${consultor.telefone?`<div><span>Telefone:</span> ${escHtml(consultor.telefone)}</div>`:''}
        </div>
      </div>
      <div>
        <div class="cot-sect-title">Fornecedor</div>
        <div class="cot-info-list">
          <div>${escHtml(ADIBLOCK_INFO.razao)}</div>
          <div>CNPJ: ${escHtml(ADIBLOCK_INFO.cnpj)}</div>
          <div>${escHtml(ADIBLOCK_INFO.telefone)}</div>
        </div>
      </div>
    </div>

    ${cond.obs?`<div class="cot-obs" style="margin-top:16px">${escHtml(cond.obs)}</div>`:''}

    <div class="cot-footer">
      Documento de confirmação de pedido. Valores e condições conforme a proposta
      ${escHtml(numProposta(prop))}${(prop.revisao||1)>1?` (revisão ${prop.revisao})`:''}.
    </div>
  </div>`;
}

// Sprint 6.4: extrai peso/volume por embalagem.
// 1o: regex pega numero no nome ("Bombona 20" -> 20, "Saco 25" -> 25)
// 2o: tabela de defaults pra nomes padrao do setor quimico sem numero
const PESO_EMBALAGEM_DEFAULT = {
  'tambor':  200,   // tambor padrao de 200L
  'cnt':     1000,  // container/IBC, padrao 1000L
  // 'conjunto' fica fora porque varia muito (kit de componentes)
};
function pesoDaEmbalagem(emb) {
  if (!emb) return null;
  const s = String(emb).trim();
  // 1) Tem numero explicito? "Bombona 20", "Saco 25", "Balde 18"
  const m = s.match(/(\d+(?:[.,]\d+)?)/);
  if (m) return parseFloat(m[1].replace(',','.'));
  // 2) Default por nome (Tambor, CNT)
  const k = s.toLowerCase();
  for (const key of Object.keys(PESO_EMBALAGEM_DEFAULT)) {
    if (k.includes(key)) return PESO_EMBALAGEM_DEFAULT[key];
  }
  return null;
}

function renderPedidoProducao(prop, solicitante, obsProd) {
  const snap = prop.snapshot || {};
  const c    = snap.cliente || {};
  const prods= snap.produtos || [];

  const dataStr = new Date(prop.created_at || Date.now()).toLocaleDateString('pt-BR');
  // Sprint 6.7: Pedido de Producao usa o numero de PEDIDO se disponivel,
  // senao cai no numero da proposta (compatibilidade com propostas antigas)
  const propLabel = numPedido(prop) || numProposta(prop);

  // Calcula totais e linhas (so o que a fabrica precisa)
  let pesoTotalGeral = 0;
  let qtdEmbTotal = 0;
  const rowsHtml = prods.map((p, i) => {
    const pesoTotal = p.qtd_kg != null ? Number(p.qtd_kg) : 0;
    pesoTotalGeral += pesoTotal;
    const pesoPorEmb = pesoDaEmbalagem(p.embalagem);
    const qtdEmb = pesoPorEmb && pesoTotal ? (pesoTotal / pesoPorEmb) : null;
    if (qtdEmb) qtdEmbTotal += qtdEmb;
    // Mostra inteiro se for inteiro; caso contrario uma casa decimal
    const qtdEmbTxt = qtdEmb == null ? '—' : (Number.isInteger(qtdEmb) ? qtdEmb : qtdEmb.toFixed(1));
    return `<tr>
      <td class="num">${i+1}</td>
      <td><b>${escHtml(p.produto||'—')}</b></td>
      <td>${escHtml(p.embalagem||'—')}</td>
      <td class="num">${qtdEmbTxt}</td>
      <td class="num">${pesoPorEmb!=null ? pesoPorEmb.toLocaleString('pt-BR') : '—'}</td>
      <td class="num">${pesoTotal.toLocaleString('pt-BR')}</td>
    </tr>`;
  }).join('');

  // Linhas em branco pra preencher a mao se imprimir
  const blanks = Math.max(0, 5 - prods.length);
  const blankRows = Array.from({length: blanks}).map(() => `<tr class="prod-empty"><td></td><td></td><td></td><td></td><td></td><td></td></tr>`).join('');

  document.getElementById('prod-body').innerHTML = `<div class="cot-body">
    <div class="cot-header">
      <div class="cot-logo-wrap">
        <img src="assets/img/logo-adiblock.svg" alt="Adiblock">
        <div>
          <div class="cot-title">Adiblock — Aditivos para Concretos</div>
          <div class="cot-h1">Pedido de Produção</div>
        </div>
      </div>
      <div class="cot-meta">
        <div>Pedido: <b>${escHtml(propLabel)}${(prop.revisao||1) > 1 ? ` — rev. ${prop.revisao}` : ''}</b></div>
        <div>Data: <b>${dataStr}</b></div>
      </div>
    </div>

    <div style="background:var(--bg);border:1px solid var(--bdr);border-radius:8px;padding:12px 16px;margin-bottom:18px;display:grid;grid-template-columns:1fr 1fr;gap:6px 24px;font-size:12.5px">
      <div style="grid-column:1/-1;display:flex;justify-content:space-between;align-items:baseline;padding-bottom:8px;border-bottom:1px solid var(--bdr);margin-bottom:4px">
        <div><span style="color:var(--mt);font-weight:600;margin-right:8px">Cliente:</span><b style="font-size:14px">${escHtml(c.name||'—')}</b></div>
        <div><span style="color:var(--mt);font-weight:600;margin-right:8px">Solicitação:</span><b>${escHtml(solicitante)}</b></div>
      </div>
      ${c.endereco||c.cidade||c.uf ? `<div style="grid-column:1/-1"><span style="color:var(--mt);font-weight:600;margin-right:8px">Endereço:</span>${escHtml([c.endereco, c.cidade&&c.uf?c.cidade+'/'+c.uf:(c.cidade||c.uf||''), c.cep?'CEP '+c.cep:''].filter(Boolean).join(' — '))}</div>` : ''}
      ${c.cnpj ? `<div><span style="color:var(--mt);font-weight:600;margin-right:8px">CNPJ:</span>${escHtml(c.cnpj)}</div>` : ''}
      ${c.phone ? `<div><span style="color:var(--mt);font-weight:600;margin-right:8px">Telefone:</span>${escHtml(c.phone)}</div>` : ''}
      ${c.obra ? `<div style="grid-column:1/-1"><span style="color:var(--mt);font-weight:600;margin-right:8px">Obra:</span><b>${escHtml(c.obra)}</b></div>` : ''}
    </div>

    <table class="prod-tab">
      <colgroup>
        <col style="width:36px">
        <col style="width:auto">
        <col style="width:120px">
        <col style="width:80px">
        <col style="width:90px">
        <col style="width:90px">
      </colgroup>
      <thead><tr>
        <th class="num">Item</th>
        <th>Produto</th>
        <th>Embalagem</th>
        <th class="num">Qtd<br><span style="font-weight:400;text-transform:none;font-size:9px;color:var(--mt)">embalagens</span></th>
        <th class="num">Peso por<br><span style="font-weight:400;text-transform:none;font-size:9px;color:var(--mt)">embalagem (kg)</span></th>
        <th class="num">Peso total<br><span style="font-weight:400;text-transform:none;font-size:9px;color:var(--mt)">(kg)</span></th>
      </tr></thead>
      <tbody>${rowsHtml||''}${blankRows}</tbody>
      ${pesoTotalGeral > 0 ? `<tfoot><tr>
        <td colspan="3" style="text-align:right;font-weight:700;color:var(--mt);text-transform:uppercase;font-size:10px;padding:10px 8px;background:var(--bg);border-top:2px solid var(--p)">Totais</td>
        <td class="num" style="font-weight:700;font-size:13px;color:var(--p);padding:10px 8px;background:var(--bg);border-top:2px solid var(--p)">${Number.isInteger(qtdEmbTotal) ? qtdEmbTotal : qtdEmbTotal.toFixed(1)}</td>
        <td style="background:var(--bg);border-top:2px solid var(--p)"></td>
        <td class="num" style="font-weight:700;font-size:13px;color:var(--p);padding:10px 8px;background:var(--bg);border-top:2px solid var(--p)">${pesoTotalGeral.toLocaleString('pt-BR')}</td>
      </tr></tfoot>` : ''}
    </table>

    ${obsProd ? `<div class="prod-obs-box"><b>Observações</b>${escHtml(obsProd)}</div>` : ''}

    <div class="cot-footer">
      ADIBLOCK FABRICAÇÃO COMERCIALIZAÇÃO E REPRESENTAÇÃO DE PRODUTOS QUÍMICOS LTDA &middot; CNPJ ${escHtml(ADIBLOCK_INFO?.cnpj||'')}
    </div>
  </div>`;
}

// ── Proposta Comercial (a oferta — tem precos, vai pro cliente) ───────────

function renderCotacao(prop) {
  PROP_ATUAL = prop; // Sprint 6.4: guarda pra o botao Pedido de Producao
  try { atualizarTopoCotacao(); } catch {} // Sprint 6.5: atualiza badge + botoes
  const snap = prop.snapshot || {};
  const c    = snap.cliente || {};
  const consultor = snap.consultor || {};
  const office    = snap.office || {};
  const cond      = snap.condicoes || {};
  const prods     = snap.produtos || [];

  const dataProp = new Date(prop.created_at || Date.now());
  const dataStr  = dataProp.toLocaleDateString('pt-BR');
  const validade = new Date(dataProp.getTime() + (cond.validade_dias||30) * 86400000).toLocaleDateString('pt-BR');
  const propLabel = numProposta(prop);
  const pedLabel  = numPedido(prop); // Sprint 6.7: numero do pedido (so existe apos "Marcar como Pedido")

  let totalGeral = 0;
  const rowsHtml = prods.map(p => {
    const q  = p.qtd_kg   != null ? Number(p.qtd_kg)   : null;
    const pr = p.preco_kg != null ? Number(p.preco_kg) : null;
    const ipiPct = p.ipi != null ? Number(p.ipi) : 0;
    const valorSemIpi = (q != null && pr != null) ? q * pr : null;
    const ipiVal      = valorSemIpi != null ? valorSemIpi * (ipiPct/100) : 0;
    const valorTotal  = valorSemIpi != null ? valorSemIpi + ipiVal : null;
    if (valorTotal != null) totalGeral += valorTotal;
    return `<tr>
      <td class="num">${p.item||''}</td>
      <td><b>${escHtml(p.produto)}</b>${p.embalagem?` <span style="color:var(--mt)">(${escHtml(p.embalagem)})</span>`:''}</td>
      <td class="num">${q!=null?q.toLocaleString('pt-BR'):'—'}</td>
      <td class="num">${pr!=null?fmtBRL(pr):'—'}</td>
      <td class="num">${valorSemIpi!=null?fmtBRL(valorSemIpi):'—'}</td>
      <td class="num">${ipiPct}%</td>
      <td class="num">${valorTotal!=null?fmtBRL(valorTotal):'—'}</td>
      <td style="font-size:11px;color:var(--er);font-weight:600">${escHtml(p.classificacao_risco||'—')}</td>
    </tr>`;
  }).join('');

  const enderecoFull = [c.endereco, c.cidade && c.uf ? c.cidade+'/'+c.uf : (c.cidade||c.uf||''), c.cep ? 'CEP '+c.cep : null].filter(Boolean).join(' — ');

  // ─── Página 1: Proposta ───
  const pagina1 = `<div class="cot-body cot-page-break">
    <div class="cot-header">
      <div class="cot-logo-wrap">
        <img src="assets/img/logo-adiblock.svg" alt="Adiblock">
        <div>
          <div class="cot-title">Adiblock — Aditivos para Concretos</div>
          <div class="cot-h1">Proposta Comercial</div>
        </div>
      </div>
      <div class="cot-meta">
        <div>Proposta: <b>${escHtml(propLabel)}</b></div>
        ${pedLabel ? `<div>Pedido: <b style="color:var(--ok)">${escHtml(pedLabel)}</b></div>` : ''}
        <!-- A revisao PRECISA sair no documento impresso: sem ela, duas versoes
             diferentes do mesmo pedido circulam com o mesmo numero e ninguem
             sabe qual das duas o cliente tem na mao. -->
        ${(prop.revisao||1) > 1 ? `<div>Revisão: <b>${prop.revisao}</b></div>` : ''}
        <div>Data: <b>${dataStr}</b></div>
        <div>Validade: <b>${validade}</b></div>
      </div>
    </div>

    <div class="cot-2col">
      <div>
        <div class="cot-sect-title">Cliente</div>
        <div class="cot-info-list">
          <div><span>Nome:</span> <b>${escHtml(c.name||'—')}</b></div>
          ${c.email?`<div><span>Email:</span> ${escHtml(c.email)}</div>`:''}
          ${c.cnpj?`<div><span>CNPJ/CPF:</span> <b>${escHtml(c.cnpj)}</b></div>`:''}
          ${c.ie?`<div><span>I.E.:</span> ${escHtml(c.ie)}</div>`:''}
          ${c.contato_outros?`<div><span>Solicitante:</span> <b>${escHtml(c.contato_outros)}</b></div>`:''}
          ${c.phone?`<div><span>Telefone:</span> ${escHtml(c.phone)}</div>`:''}
          ${enderecoFull?`<div><span>Endereço:</span> ${escHtml(enderecoFull)}</div>`:''}
          ${c.obra?`<div><span>Obra:</span> ${escHtml(c.obra)}</div>`:''}
        </div>
      </div>
      <div>
        <div class="cot-sect-title">Contatos Adiblock</div>
        <div class="cot-info-list">
          <div><span>Consultor:</span> <b>${escHtml(consultor.nome||'—')}</b></div>
          ${consultor.email?`<div><span>email:</span> ${escHtml(consultor.email)}</div>`:''}
          ${consultor.telefone?`<div><span>Telefone:</span> ${escHtml(consultor.telefone)}</div>`:''}
          ${office.nome?`<div style="margin-top:8px"><span>Office:</span> <b>${escHtml(office.nome)}</b></div>`:''}
          ${office.email?`<div><span>email:</span> ${escHtml(office.email)}</div>`:''}
          ${office.telefone?`<div><span>Telefone:</span> ${escHtml(office.telefone)}</div>`:''}
        </div>
      </div>
    </div>

    <div class="cot-sect">
      <div class="cot-sect-title">Produtos</div>
      <table class="cot-tab">
        <colgroup>
          <col style="width:32px">
          <col style="width:auto">
          <col style="width:54px">
          <col style="width:64px">
          <col style="width:74px">
          <col style="width:38px">
          <col style="width:80px">
          <col style="width:110px">
        </colgroup>
        <thead><tr>
          <th class="num">Item</th>
          <th>Produto (embalagem)</th>
          <th class="num">Qtd (kg)</th>
          <th class="num">Preço unit.</th>
          <th class="num">Valor s/ IPI</th>
          <th class="num">IPI</th>
          <th class="num">Valor Total</th>
          <th>Class. risco</th>
        </tr></thead>
        <tbody>${rowsHtml||'<tr><td colspan="8" style="text-align:center;color:var(--mt);padding:20px">Sem produtos.</td></tr>'}${(Number(cond.frete_valor)||0) > 0 ? `<tr>
          <td class="num"></td>
          <td><b>Frete</b> <span style="color:var(--mt)">(${escHtml(cond.frete||'FOB')})</span></td>
          <td class="num">—</td>
          <td class="num">—</td>
          <td class="num">${fmtBRL(Number(cond.frete_valor))}</td>
          <td class="num">—</td>
          <td class="num">${fmtBRL(Number(cond.frete_valor))}</td>
          <td>—</td>
        </tr>`:''}</tbody>
        ${(totalGeral + (Number(cond.frete_valor)||0)) > 0 ? `<tfoot><tr>
          <td colspan="6" class="cot-total-lbl">Valor Total</td>
          <td colspan="2" class="cot-total-val">${fmtBRL(totalGeral + (Number(cond.frete_valor)||0))}</td>
        </tr></tfoot>` : ''}
      </table>
    </div>

    ${cond.obs ? `<div class="cot-sect">
      <div class="cot-sect-title">OBS</div>
      <div class="cot-obs">${escHtml(cond.obs)}</div>
    </div>`:''}

    <div style="font-size:13px;margin-top:14px"><b>Prazo de pagamento:</b> ${escHtml(cond.prazo_pagamento||'30DD')}</div>
  </div>`;

  // ─── Página 2: Condições Comerciais ───
  const pagina2 = `<div class="cot-body cot-page-break">
    <div class="cot-h1" style="margin-bottom:18px">Condições Comerciais</div>
    <table class="cot-condicoes">
      <tr><td>Prazo de pagamento</td><td><b>${escHtml(cond.prazo_pagamento||'30DD')}</b></td></tr>
      <tr><td>Frete</td><td><b>${escHtml(cond.frete||'FOB')}</b>${(Number(cond.frete_valor)||0)>0?` — <b>${fmtBRL(Number(cond.frete_valor))}</b> <span style="color:var(--mt);font-size:11px">(incluso no Valor Total)</span>`:''}</td></tr>
      <tr><td>Condições sobre o transporte</td><td>Quando a carga conter produtos classificados como perigosos para efeito de transporte terrestre, em atenção à legislação da ANTT, o veículo deverá possuir as placas adequadas, bem como o motorista deverá possuir MOPP válido.</td></tr>
      <tr><td>Prazo de entrega</td><td>Até 10 dias úteis após confirmação da proposta por e-mail.</td></tr>
      <tr><td>Impostos inclusos sobre a fatura</td><td><b>ICMS incluso</b> — Optante pelo Simples Nacional.</td></tr>
      <tr><td>Demais impostos</td><td>IPI isento. Demais impostos inclusos.</td></tr>
      <tr><td>Prazo de validade da proposta</td><td><b>${cond.validade_dias||30} dias</b></td></tr>
      <tr><td>Observações adicionais</td><td>Esta proposta é complementada pelos <b>TERMOS COMERCIAIS GERAIS</b> em anexo.</td></tr>
    </table>

    <div class="cot-corresp">
      <div>
        <div style="font-weight:600;margin-bottom:4px">Correspondência:</div>
        <div>${escHtml(ADIBLOCK_INFO.razao)}</div>
        <div>CNPJ: ${escHtml(ADIBLOCK_INFO.cnpj)}</div>
        <div>${escHtml(ADIBLOCK_INFO.endereco)}</div>
        <div>${escHtml(ADIBLOCK_INFO.cidade)}</div>
        <div>CEP: ${escHtml(ADIBLOCK_INFO.cep)}</div>
      </div>
      <div>
        <div style="font-weight:600;margin-bottom:4px">Comunicação:</div>
        <div>Fone: ${escHtml(ADIBLOCK_INFO.telefone)}</div>
        <div>Mail: ${escHtml(ADIBLOCK_INFO.email)}</div>
        <div>Web: ${escHtml(ADIBLOCK_INFO.web)}</div>
      </div>
    </div>
  </div>`;

  // ─── Página 3: Termos Comerciais Gerais ───
  const pagina3 = `<div class="cot-body">
    <div class="cot-h1" style="margin-bottom:14px">Termos Comerciais Gerais</div>
    <div style="font-size:12px;line-height:1.55;color:var(--tx);margin-bottom:14px">
      As vendas efetuadas pela <b>ADIBLOCK FABRICAÇÃO COMERCIALIZAÇÃO E REPRESENTAÇÃO DE PRODUTOS QUIMICOS LTDA</b>, doravante denominada ADIBLOCK, são realizadas sob as seguintes condições:
    </div>
    <ol class="cot-termos">
      ${TERMOS_COMERCIAIS.map(t => `<li>${escHtml(t)}</li>`).join('')}
    </ol>
  </div>`;

  document.getElementById('cot-body').innerHTML = pagina1 + pagina2 + pagina3;
}
