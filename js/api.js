/* ==========================================================================
   api.js — todo acesso a dados passa por aqui.
   Sprint 8.1 (modularizacao), retomado em 17/08/2026.

   DEPENDE de config.js (SB_URL, SB_KEY) — carregar depois dele.
   Ver CLAUDE.md secao 11 sobre por que XHR e nao fetch.
   ========================================================================== */
// Le sempre do localStorage — mais confiavel que guardar em variavel.
function getToken() {
  try {
    const k = Object.keys(localStorage).find(x => x.startsWith('sb-') && x.endsWith('-auth-token'));
    if (k) {
      const d = JSON.parse(localStorage.getItem(k));
      return d?.access_token || SB_KEY;
    }
  } catch {}
  return SB_KEY;
}

// ── XHR — não sofre interferência de scripts do Vercel ───────────────────
function api(method, table, qs, body) {
  return new Promise((resolve, reject) => {
    const url = SB_URL + '/rest/v1/' + table + (qs ? '?' + qs : '');
    const r = new XMLHttpRequest();
    r.open(method, url, true);
    r.setRequestHeader('apikey', SB_KEY);
    r.setRequestHeader('Authorization', 'Bearer ' + getToken());
    r.setRequestHeader('Content-Type', 'application/json');
    r.setRequestHeader('Prefer', 'return=representation');
    r.timeout = 15000;
    r.ontimeout = () => reject(new Error('Sem resposta do servidor. Verifique sua internet.'));
    r.onerror   = () => reject(new Error('Erro de conexão.'));
    r.onload    = () => {
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

// Delete com verificação de count
function apiDelete(table, qs) {
  return new Promise((resolve, reject) => {
    const url = SB_URL + '/rest/v1/' + table + (qs ? '?' + qs : '');
    const r = new XMLHttpRequest();
    r.open('DELETE', url, true);
    r.setRequestHeader('apikey', SB_KEY);
    r.setRequestHeader('Authorization', 'Bearer ' + getToken());
    r.setRequestHeader('Prefer', 'count=exact');
    r.timeout = 15000;
    r.ontimeout = () => reject(new Error('Timeout ao excluir.'));
    r.onerror   = () => reject(new Error('Erro de rede.'));
    r.onload    = () => {
      if (r.status === 204 || r.status === 200) {
        const cr = r.getResponseHeader('Content-Range') || '';
        const m  = cr.match(/\/(\d+)$/);
        const n  = m ? parseInt(m[1]) : 1; // se sem header, assume ok
        if (n === 0) reject(new Error('Sem permissão para excluir. Verifique se você está logado.'));
        else resolve(n);
      } else {
        let msg = r.responseText;
        try { msg = JSON.parse(msg).message || msg; } catch {}
        reject(new Error(msg || 'Erro ' + r.status));
      }
    };
    r.send(null);
  });
}
