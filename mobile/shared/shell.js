(function installPlayloShell() {
  'use strict';
  if (!document.documentElement) { document.addEventListener('DOMContentLoaded', installPlayloShell, {once:true}); return; }
  if (window !== top || window.__playloShell) return;
  window.__playloShell = true;
  document.documentElement.dataset.playloApp = 'native';
  let frame = 0;
  const resize = () => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      const viewport = window.visualViewport;
      document.documentElement.style.setProperty('--playlo-visible-height', Math.round(viewport?.height ?? innerHeight) + 'px');
      document.documentElement.style.setProperty('--playlo-visible-top', Math.round(viewport?.offsetTop ?? 0) + 'px');
    });
  };
  addEventListener('resize', resize);
  visualViewport?.addEventListener('resize', resize);
  visualViewport?.addEventListener('scroll', resize);
  resize();
  const pendingKey = 'playlo-native-signin';
  let pending = null, polling = false, notice;
  const hex = bytes => Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
  const post = (path, body) => fetch(path, {method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(body)});
  function message(text, cancel = false) {
    notice?.remove(); notice = document.createElement('aside');
    notice.setAttribute('role', 'status');
    notice.style.cssText = 'position:fixed;inset:12px 12px auto;z-index:2147483647;background:#201c38;color:white;padding:18px;border:2px solid #ac93ff;border-radius:16px;font:16px/1.5 system-ui;box-shadow:0 12px 36px #0008';
    const label = document.createElement('p'); label.textContent = text; label.style.margin = '0'; notice.append(label);
    const button = document.createElement('button'); button.textContent = cancel ? 'Annuleren' : 'Sluiten';
    button.style.cssText = 'min-height:44px;margin-top:12px;padding:8px 16px';
    button.onclick = () => { pending = null; sessionStorage.removeItem(pendingKey); notice.remove(); };
    notice.append(button); document.body.append(notice);
  }
  async function poll() {
    if (!pending || polling) return;
    if (Date.now() >= pending.expires) { pending = null; sessionStorage.removeItem(pendingKey); message('De aanmelding is verlopen. Begin opnieuw.'); return; }
    polling = true;
    try {
      const response = await post('/api/native-auth/redeem', {id:pending.id, verifier:pending.verifier});
      if (response.status === 202) return;
      const result = await response.json();
      if (!response.ok) throw Error(result.error || 'Aanmelden is niet gelukt.');
      pending = null; sessionStorage.removeItem(pendingKey);
      localStorage.setItem('playlo-play-mode', 'account'); localStorage.setItem('playlo-onboarded', 'yes'); location.reload();
    } catch (error) {
      // A lost connection can be retried while the three-minute request is valid.
      if (error instanceof TypeError) return;
      pending = null; sessionStorage.removeItem(pendingKey); message(error.message);
    } finally { polling = false; }
  }
  async function signIn() {
    if (pending) { message('Bevestig code ' + pending.code + ' in je browser en ga terug naar Playlo.', true); return; }
    try {
      const verifier = hex(crypto.getRandomValues(new Uint8Array(32)));
      const challenge = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
      const response = await post('/api/native-auth/begin', {challenge});
      if (response.status === 404) throw Error('Aanmelden in de app komt beschikbaar na de website-update. Je kunt ondertussen als gast spelen.');
      const result = await response.json(); if (!response.ok) throw Error(result.error || 'Aanmelden is niet gelukt.');
      if (!/^[a-f0-9-]{36}$/.test(result.id) || !/^\d{6}$/.test(result.code)) throw Error('Ongeldige aanmeldreactie.');
      pending = {id:result.id, code:result.code, expires:result.expires, verifier}; sessionStorage.setItem(pendingKey, JSON.stringify(pending));
      message('Bevestig code ' + pending.code + ' in je browser en ga terug naar Playlo.', true);
      location.href = (window.__playloAuthOrigin || location.origin) + '/native-signin?request=' + pending.id;
    } catch (error) { message(error.message || 'Aanmelden is niet gelukt.'); }
  }
  try { const saved = JSON.parse(sessionStorage.getItem(pendingKey)); if (saved?.expires > Date.now()) pending = saved; } catch {}
  setInterval(poll, 2500); addEventListener('playlo:resume', poll);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) void poll(); });
  document.addEventListener('click', event => {
    const anchor = event.target.closest?.('a[href]'); if (!anchor) return;
    const url = new URL(anchor.href, location.href); if (url.origin !== location.origin) return;
    if (url.pathname === '/signin-with-chatgpt') { event.preventDefault(); event.stopImmediatePropagation(); void signIn(); }
    if (url.pathname === '/signout-with-chatgpt') {
      event.preventDefault(); event.stopImmediatePropagation(); pending = null; sessionStorage.removeItem(pendingKey);
      void post('/api/session', {mode:'guest',fresh:true}).then(response => {
        if (!response.ok) throw Error('Afmelden is niet gelukt. Probeer opnieuw.');
        localStorage.setItem('playlo-play-mode','guest'); location.href = '/';
      }).catch(error => message(error.message));
    }
  }, true);
  const send = payload => {
    const data = JSON.stringify(payload);
    if (window.PlayloNative?.postMessage) window.PlayloNative.postMessage(data);
    else window.webkit?.messageHandlers?.PlayloNative?.postMessage(data);
  };
  const originalClick = HTMLAnchorElement.prototype.click;
  // Keep the Blob itself: fetching blob: URLs is blocked by the site's connect-src policy.
  const blobs = new Map(), createURL = URL.createObjectURL.bind(URL), revokeURL = URL.revokeObjectURL.bind(URL);
  URL.createObjectURL = blob => { const url = createURL(blob); blobs.set(url, blob); return url; };
  URL.revokeObjectURL = url => { blobs.delete(url); revokeURL(url); };
  async function exportFile(anchor) {
    try {
      const url = new URL(anchor.href, location.href);
      if (url.protocol !== 'blob:' || !url.href.startsWith('blob:' + location.origin + '/')) return;
      const blob = blobs.get(url.href);
      if (!blob) throw Error('Open de export opnieuw om dit bestand in de app op te slaan.');
      if (blob.size > 4 * 1024 * 1024) throw Error('Dit bestand is te groot om in de app op te slaan.');
      const data = new Uint8Array(await blob.arrayBuffer());
      let binary = '';
      for (let index = 0; index < data.length; index += 8192) binary += String.fromCharCode(...data.subarray(index, index + 8192));
      send({type:'save', name:(anchor.download || 'Playlo-export.html').replace(/[\\/\u0000-\u001f]/g,'_').slice(0,100), mime:blob.type || 'application/octet-stream', data:btoa(binary)});
    } catch (error) { alert(error.message || 'Opslaan is niet gelukt. Probeer opnieuw.'); }
  }
  HTMLAnchorElement.prototype.click = function () {
    if (this.download && this.href.startsWith('blob:')) { void exportFile(this); return; }
    return originalClick.call(this);
  };
  document.addEventListener('click', event => {
    const anchor = event.target.closest?.('a[download]');
    if (anchor?.href.startsWith('blob:')) { event.preventDefault(); void exportFile(anchor); }
  }, true);
})();
