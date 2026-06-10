// js/format.js — Helpers de formatação (Sprint 8.1b)
// Extraído mecanicamente do index.html, SEM mudança de lógica.
// Carregado ANTES do <script> principal. fRel() usa hj() (global, no main).
// TODO: migrar para ES modules (import/export) no futuro — ver CLAUDE.md.

function fData(d) {
  if (!d) return '—';
  // Tolerante: aceita 'YYYY-MM-DD' (date puro) ou 'YYYY-MM-DDTHH...' (timestamptz)
  const dateOnly = String(d).slice(0,10);
  const [y,m,dd] = dateOnly.split('-');
  return dd+'/'+m+'/'+y;
}
// Sprint 6.1: data + hora local pra exibir callbacks
function fDataHora(d) {
  if (!d) return '—';
  const dt = new Date(d);
  if (isNaN(dt)) return '—';
  return dt.toLocaleString('pt-BR', { day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit' });
}
// Sprint 6.1: somente a hora "14:30"
function fHora(d) {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt)) return '';
  return dt.toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' });
}
// Sprint 6.1: timestamptz do DB -> formato do <input type="datetime-local"> em horario LOCAL
function dtToInput(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  if (isNaN(d)) return '';
  const pad = n => String(n).padStart(2,'0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
// Sprint 6.1: valor de <input type="datetime-local"> -> ISO UTC pro DB
function inputToISO(v) {
  if (!v) return null;
  const d = new Date(v);
  return isNaN(d) ? null : d.toISOString();
}
function fRel(d) {
  if (!d) return '';
  const df = Math.round((new Date(d) - new Date(hj())) / 86400000);
  if (df===0) return 'Hoje';
  if (df===1) return 'Amanhã';
  if (df===-1) return 'Ontem';
  return df < 0 ? Math.abs(df)+'d atrás' : 'em '+df+'d';
}
function fMoeda(v) {
  if (v==null||v==='') return '—';
  return Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
}
const escHtml = s => String(s==null?'':s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
