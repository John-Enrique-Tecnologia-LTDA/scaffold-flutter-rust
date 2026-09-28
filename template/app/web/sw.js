// Service worker do {= display_name =}: o que o PWA precisa para instalar e abrir sem rede com a última
// versão carregada.
//
// Tudo da mesma origem vai primeiro à rede (o build do Flutter não põe hash no nome dos arquivos,
// então servir do cache primeiro deixaria código velho depois de um deploy); sem rede, sai do
// cache. A API, o WebSocket e o que vem de fora (CanvasKit, fontes) não passam por aqui:
// dados são sempre ao vivo, e o resto fica no cache do próprio navegador.
const CACHE = '{= name =}-app-v1';
const SHELL = ['/', '/index.html', '/manifest.json', '/flutter_bootstrap.js', '/favicon.svg', '/icons/Icon-192.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).catch(() => {}),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('{= name =}-app-') && key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  event.respondWith((async () => {
    try {
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') {
        const copy = res.clone();
        event.waitUntil(caches.open(CACHE).then((cache) => cache.put(req, copy)));
      }
      return res;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      // rota do app (qualquer rota) sem rede: a casca do app, que mostra o erro de conexão
      if (req.mode === 'navigate') {
        const shell = (await caches.match('/index.html')) || (await caches.match('/'));
        if (shell) return shell;
      }
      throw err;
    }
  })());
});
