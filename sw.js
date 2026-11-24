// Offline-first cache for Flow of Ace. Bump VERSION when files change.
const VERSION = 'flowoface-v15';
const CORE = ['./', 'index.html', 'manifest.webmanifest', 'icon.svg', 'config.js', 'lib/supabase.js'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const FONT_HOSTS = ['fonts.googleapis.com', 'fonts.gstatic.com'];
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  // Account and sync traffic (Supabase, Google sign-in) always goes to the network, never the cache.
  if (!sameOrigin && !FONT_HOSTS.includes(url.hostname)) return;
  // Config and the page itself: network first, so updates arrive; cache as the offline fallback.
  if (sameOrigin && (req.mode === 'navigate' || url.pathname.endsWith('/config.js') || url.pathname.endsWith('/audio/manifest.json'))) {
    e.respondWith(fetch(req).then(res => { const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); return res; })
      .catch(() => caches.match(req, { ignoreSearch: true }).then(hit => hit || caches.match('index.html'))));
    return;
  }
  // Everything else (library, icon, fonts): cache first.
  e.respondWith(caches.match(req, { ignoreSearch: true }).then(hit => hit || fetch(req).then(res => {
    if (res && (res.ok || res.type === 'opaque')) { const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
    return res;
  })));
});
