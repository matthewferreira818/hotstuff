/*
 * HotsTuff service worker — makes the site installable and fast on repeat
 * visits, with a best-effort offline mode.
 *
 * Strategy:
 *   - navigations + products.json: network first (never a stale catalog while
 *     online), cached copy only as the offline fallback
 *   - same-origin static files: stale-while-revalidate
 *   - CJ product photos: stale-while-revalidate, capped so quota can't balloon
 *   - checkout API calls are never intercepted
 *
 * Bump VERSION whenever index.html / styles.css / script.js change, so
 * installed apps pick the new shell up on their next visit.
 */

const VERSION = "v17";
const SHELL_CACHE = `hotstuff-shell-${VERSION}`;
const RUNTIME_CACHE = `hotstuff-runtime-${VERSION}`;
const IMAGE_CACHE = `hotstuff-images-${VERSION}`;
const IMAGE_CACHE_MAX = 120;

const CHECKOUT_HOST = "wavelist-checkout.wavelist-mf818.workers.dev";

const SHELL = [
  "index.html",
  "styles.css",
  "script.js",
  "i18n.js",
  "manifest.webmanifest",
  "assets/icons/icon-192.png",
  "assets/icons/icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k.startsWith("hotstuff-") && ![SHELL_CACHE, RUNTIME_CACHE, IMAGE_CACHE].includes(k))
          .map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

async function trimCache(name, max) {
  const cache = await caches.open(name);
  const keys = await cache.keys();
  for (let i = 0; i < keys.length - max; i++) await cache.delete(keys[i]);
}

/* Network first; drop a copy in `cacheName` and fall back to it offline.
 * Cache keys are plain URLs so request flags like no-store don't interfere. */
async function networkFirst(request, cacheName, fallbackUrl) {
  const url = request.url;
  try {
    const fresh = await fetch(request);
    if (fresh.ok) {
      const cache = await caches.open(cacheName);
      cache.put(url, fresh.clone());
    }
    return fresh;
  } catch (err) {
    const cached = (await caches.match(url)) || (fallbackUrl && (await caches.match(fallbackUrl)));
    if (cached) return cached;
    throw err;
  }
}

async function staleWhileRevalidate(request, cacheName, maxEntries) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request.url);
  const refresh = fetch(request)
    .then((fresh) => {
      // opaque cross-origin responses (status 0) are fine for images
      if (fresh.ok || fresh.type === "opaque") {
        cache.put(request.url, fresh.clone());
        if (maxEntries) trimCache(cacheName, maxEntries);
      }
      return fresh;
    })
    .catch(() => cached);
  return cached || refresh;
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // never get between the customer and Stripe
  if (url.hostname === CHECKOUT_HOST) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirst(request, SHELL_CACHE, "index.html"));
    return;
  }

  if (url.origin === self.location.origin) {
    if (url.pathname.endsWith("/products.json")) {
      event.respondWith(networkFirst(request, RUNTIME_CACHE));
    } else {
      event.respondWith(staleWhileRevalidate(request, SHELL_CACHE));
    }
    return;
  }

  if (url.hostname.endsWith("cjdropshipping.com")) {
    event.respondWith(staleWhileRevalidate(request, IMAGE_CACHE, IMAGE_CACHE_MAX));
  }
});
