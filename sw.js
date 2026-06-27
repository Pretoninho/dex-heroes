// Dex Heroes — Service Worker « réseau d'abord ».
// But : en PWA (écran d'accueil iOS/Android), aller chercher la version FRAÎCHE
// en ligne à chaque ouverture (fini le cache figé), tout en gardant une copie
// pour le hors-ligne. Bump CACHE_NAME si jamais on veut purger d'autorité.
const CACHE_NAME = "dex-heroes-runtime-v1";

self.addEventListener("install", (e) => {
  self.skipWaiting();   // active la nouvelle version tout de suite
});

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    // purge les anciens caches
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // On ne gère que notre propre origine (laisse passer Supabase, CDN, etc.).
  if (url.origin !== self.location.origin) return;

  // Réseau d'abord : on tente le réseau, on met en cache, fallback cache si offline.
  e.respondWith((async () => {
    try {
      const fresh = await fetch(req, { cache: "no-store" });
      const cache = await caches.open(CACHE_NAME);
      cache.put(req, fresh.clone()).catch(() => {});
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      // dernier recours pour une navigation : l'index en cache
      if (req.mode === "navigate") {
        const idx = await caches.match("./index.html") || await caches.match("./");
        if (idx) return idx;
      }
      throw err;
    }
  })());
});
