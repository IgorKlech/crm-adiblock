/* ==========================================================================
   anexos.js — arquivos anexados a um pedido (O4). 2026-08-17.

   Guarda no CRM o papel que hoje vive na caixa de e-mail: a OC assinada, o
   comprovante. Anexo pertence a uma PROPOSTA (foto de obra em oportunidade
   foi descartada — ver a migration 2026-08-17-anexos-storage.sql).

   COMO O ACESSO FUNCIONA, e por que nao e "so quem tem login le":
   o bucket e privado, entao nao ha URL direta e o RLS so libera pra quem esta
   autenticado na org dona. Mas o arquivo e aberto por URL ASSINADA, e URL
   assinada e um PORTADOR: quem receber o link abre ate expirar, mesmo sem
   login. Sem servidor proprio (restricao do projeto) nao da pra eliminar
   isso. A mitigacao e a validade de 60s abaixo — tempo de abrir, curto demais
   pra circular.

   CAMINHO: {org_id}/proposals/{proposal_id}/{uuid}-{nome}. O org_id vem
   PRIMEIRO porque a policy do Storage filtra lendo a primeira pasta; sem essa
   ordem nao ha isolamento multi-tenant no arquivo, so na tabela.

   CARREGA DEPOIS de config.js (usa `sb`) e api.js. Consome PROP_ATUAL
   (documentos.js), toast/conf/MEP (inline) — todos em tempo de execucao.
   ========================================================================== */

const ANEXO_MAX_BYTES = 10 * 1024 * 1024;          // igual ao teto do bucket
const ANEXO_TIPOS = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
const ANEXO_URL_SEGUNDOS = 60;                     // validade do link assinado

let ANEXOS = [];        // do pedido aberto no momento

function anexoIcone(mime) {
  return (mime || '').startsWith('image/') ? '🖼️' : '📄';
}

function anexoTamanho(bytes) {
  const b = Number(bytes) || 0;
  if (b < 1024) return b + ' B';
  if (b < 1024 * 1024) return (b / 1024).toFixed(0) + ' KB';
  return (b / (1024 * 1024)).toFixed(1) + ' MB';
}

// O nome do usuario vira chave no Storage. Acento e espaco funcionam, mas
// atrapalham na hora de depurar um caminho no painel do Supabase.
function anexoNomeSeguro(nome) {
  return String(nome || 'arquivo')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^\w.\-]+/g, '-')
    .replace(/-+/g, '-')
    .slice(-80);
}

async function abrirAnexos() {
  const p = PROP_ATUAL;
  if (!p) { toast('Sem pedido carregado', '', 'warning'); return; }
  document.getElementById('anx-m').classList.add('op');
  const inp = document.getElementById('anx-input');
  if (inp) { inp.value = ''; inp.disabled = false; }
  await carregarAnexos(p.id);
}

function fecharAnexos() {
  document.getElementById('anx-m').classList.remove('op');
}

async function carregarAnexos(proposalId) {
  const lista = document.getElementById('anx-lista');
  lista.innerHTML = '<div class="sl"><div class="sp"></div></div>';
  try {
    ANEXOS = await api('GET', 'attachments',
      `proposal_id=eq.${proposalId}&select=id,caminho,nome_original,mime,tamanho,created_at,created_by&order=created_at.desc`) || [];
    renderAnexos();
  } catch (err) {
    console.error('carregarAnexos:', err);
    lista.innerHTML = '<div class="anx-vazio" style="color:var(--er)">Não foi possível carregar: '
      + escHtml(err.message || '') + '</div>';
  }
}

function renderAnexos() {
  const lista = document.getElementById('anx-lista');
  const badge = document.getElementById('cot-anx-badge');
  if (badge) {
    badge.textContent = ANEXOS.length || '';
    badge.style.display = ANEXOS.length ? '' : 'none';
  }
  if (!ANEXOS.length) {
    lista.innerHTML = '<div class="anx-vazio">Nenhum arquivo anexado ainda.</div>';
    return;
  }
  const nome = id => (PF || []).find(x => x.id === id)?.name || '—';
  lista.innerHTML = ANEXOS.map(a => `
    <div class="anx-item">
      <span class="anx-ico">${anexoIcone(a.mime)}</span>
      <div class="anx-info">
        <button type="button" class="anx-nome" onclick="abrirAnexo('${a.id}')"
                title="Abrir ${escHtml(a.nome_original)}">${escHtml(a.nome_original)}</button>
        <div class="anx-meta">${anexoTamanho(a.tamanho)} · ${escHtml(nome(a.created_by))} · ${fDataHora(a.created_at)}</div>
      </div>
      <button type="button" class="anx-del" aria-label="Excluir ${escHtml(a.nome_original)}"
              title="Excluir" onclick="excluirAnexo('${a.id}')">✕</button>
    </div>`).join('');
}

// ── Enviar ───────────────────────────────────────────────────────────────
// Envia TODOS os arquivos escolhidos, um de cada vez.
//
// ⚠ O texto do botao vai no <span id="anx-btn-txt">, NUNCA no proprio <label>.
// O <input type=file> e filho do label, e atribuir textContent num elemento
// SUBSTITUI todos os nos filhos — era assim que o campo de arquivo sumia do
// DOM depois do primeiro envio, e por isso so dava pra anexar uma vez. O
// mesmo motivo derrubava abrirAnexos() na vez seguinte, ao procurar um
// #anx-input que nao existia mais.
//
// Sequencial, nao em paralelo: o progresso ("2 de 5") so e honesto assim, e
// evita abrir varias conexoes de upload de uma vez num projeto do plano Free.
// Um arquivo que falha NAO aborta os outros — o resumo no fim diz quais foram.
const ANEXO_MAX_LOTE = 20;

async function enviarAnexo(input) {
  const p = PROP_ATUAL;
  const escolhidos = Array.from(input.files || []);
  if (!p || !escolhidos.length) return;

  const org = MEP?.org_id;
  if (!org) { toast('Perfil sem organização', 'Recarregue a página.', 'warning'); input.value = ''; return; }

  if (escolhidos.length > ANEXO_MAX_LOTE) {
    toast('Muitos arquivos de uma vez',
          `Envie no máximo ${ANEXO_MAX_LOTE} por vez — você escolheu ${escolhidos.length}.`, 'warning');
    input.value = ''; return;
  }

  // Peneira antes de subir qualquer coisa: o bucket ja recusa tamanho e tipo
  // errados, mas o erro dele e cru. Aqui da pra dizer o que houve, e por
  // arquivo — num lote, "falhou" sem nome nao ajuda ninguem.
  const validos = [], recusados = [];
  for (const f of escolhidos) {
    if (f.size > ANEXO_MAX_BYTES) recusados.push(`${f.name} (${anexoTamanho(f.size)}, máx. 10 MB)`);
    else if (f.type && !ANEXO_TIPOS.includes(f.type)) recusados.push(`${f.name} (tipo não aceito)`);
    else validos.push(f);
  }

  const btn = document.getElementById('anx-btn');
  const txt = document.getElementById('anx-btn-txt');
  const antes = txt ? txt.textContent : '';
  // <label> nao aceita disabled — quem trava o clique e o input desabilitado
  // mais o pointer-events da classe .busy.
  btn?.classList.add('busy');
  input.disabled = true;

  const enviados = [], falhas = [];
  try {
    for (let i = 0; i < validos.length; i++) {
      const file = validos[i];
      if (txt) txt.textContent = validos.length > 1
        ? `Enviando ${i + 1} de ${validos.length}...`
        : 'Enviando...';

      const caminho = `${org}/proposals/${p.id}/${crypto.randomUUID()}-${anexoNomeSeguro(file.name)}`;
      try {
        const { error: errUp } = await sb.storage.from('anexos')
          .upload(caminho, file, { contentType: file.type || 'application/octet-stream', upsert: false });
        if (errUp) throw errUp;

        // ORDEM: arquivo primeiro, metadado depois. Se o metadado falhar, sobra
        // um arquivo sem linha — invisivel, mas recuperavel pelo painel do
        // Supabase. Na ordem inversa, a linha apontaria pra um arquivo que
        // nunca existiu.
        try {
          await api('POST', 'attachments', null, {
            proposal_id: p.id, caminho,
            nome_original: file.name, mime: file.type || null, tamanho: file.size,
            created_by: ME?.id || null,
          });
        } catch (errMeta) {
          await sb.storage.from('anexos').remove([caminho]).catch(() => {});
          throw errMeta;
        }
        enviados.push(file.name);
      } catch (err) {
        console.error('enviarAnexo:', file.name, err);
        falhas.push(`${file.name} — ` + (/row-level security|policy/i.test(err.message || '')
          ? 'sem permissão' : (err.message || 'falha no envio')));
      }
    }
  } finally {
    input.value = '';                       // permite reescolher o MESMO arquivo
    input.disabled = false;
    btn?.classList.remove('busy');
    if (txt) txt.textContent = antes;       // so o <span>: o input segue intacto
  }

  if (enviados.length) await carregarAnexos(p.id);

  const problemas = [...recusados, ...falhas];
  if (enviados.length && !problemas.length) {
    toast(enviados.length > 1 ? `${enviados.length} arquivos anexados` : 'Arquivo anexado',
          enviados.length > 1 ? '' : enviados[0], 'success');
  } else if (enviados.length && problemas.length) {
    toast(`${enviados.length} de ${enviados.length + problemas.length} anexados`,
          'Não entraram: ' + problemas.join('; '), 'warning');
  } else {
    toast('Não foi possível anexar', problemas.join('; ') || 'Nenhum arquivo válido.', 'warning');
  }
}

// ── Abrir ────────────────────────────────────────────────────────────────
async function abrirAnexo(id) {
  const a = ANEXOS.find(x => x.id === id);
  if (!a) return;
  try {
    const { data, error } = await sb.storage.from('anexos')
      .createSignedUrl(a.caminho, ANEXO_URL_SEGUNDOS);
    if (error) throw error;
    // noopener: sem isso a aba aberta ganha referencia a esta pela window.opener
    window.open(data.signedUrl, '_blank', 'noopener');
  } catch (err) {
    console.error('abrirAnexo:', err);
    toast('Não foi possível abrir', err.message || '', 'warning');
  }
}

// ── Excluir ──────────────────────────────────────────────────────────────
function excluirAnexo(id) {
  const a = ANEXOS.find(x => x.id === id);
  if (!a) return;
  conf('Excluir anexo', `Remover "${a.nome_original}"? Não dá para desfazer.`, async () => {
    try {
      // Arquivo primeiro. Se falhar, o metadado fica e da pra tentar de novo.
      // Na ordem inversa, o arquivo viraria orfao invisivel — que e exatamente
      // o problema de LGPD que a migration descreve.
      const { error } = await sb.storage.from('anexos').remove([a.caminho]);
      if (error) throw error;
      await apiDelete('attachments', `id=eq.${id}`);
      ANEXOS = ANEXOS.filter(x => x.id !== id);
      renderAnexos();
      toast('Anexo removido', '', 'success');
    } catch (err) {
      console.error('excluirAnexo:', err);
      const msg = /row-level security|policy/i.test(err.message || '')
        ? 'Só quem enviou o arquivo, ou o admin, pode excluir.'
        : (err.message || '');
      toast('Não foi possível excluir', msg, 'warning');
    }
  });
}

// ── LGPD: apaga os arquivos de TODAS as propostas de uma empresa ─────────
// Chamado ANTES de excluir a empresa, nos TRES caminhos que apagam empresa:
// abrDel (exclusao comum), bulkExcluir (em massa) e executarExclusaoLgpd.
// Aceita um id ou uma lista. Cascata de banco nunca alcanca objeto no
// Storage: sem isto, o metadado sumiria e a OC — com CNPJ, endereco e nome de
// pessoa — continuaria no bucket. E `proposals.company_id` e ON DELETE SET
// NULL, entao a proposta nem chega a ser apagada junto.
// Devolve quantos arquivos removeu; erro aqui ABORTA a exclusao, de proposito:
// e melhor a exclusao falhar visivelmente do que dizer que apagou sem apagar.
async function apagarAnexosDaEmpresa(companyIds) {
  const ids = (Array.isArray(companyIds) ? companyIds : [companyIds]).filter(Boolean);
  if (!ids.length) return 0;
  const filtro = ids.length === 1
    ? `company_id=eq.${ids[0]}`
    : `company_id=in.(${ids.map(i => `"${i}"`).join(',')})`;
  const props = await api('GET', 'proposals', `${filtro}&select=id`) || [];
  if (!props.length) return 0;
  const propIds = props.map(p => `"${p.id}"`).join(',');
  const anexos = await api('GET', 'attachments', `proposal_id=in.(${propIds})&select=id,caminho`) || [];
  if (!anexos.length) return 0;

  const { error } = await sb.storage.from('anexos').remove(anexos.map(a => a.caminho));
  if (error) throw new Error('Falha ao apagar arquivos do armazenamento: ' + error.message);
  await apiDelete('attachments', `proposal_id=in.(${propIds})`);
  return anexos.length;
}
