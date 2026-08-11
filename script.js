const CHECKOUT_API = "https://wavelist-checkout.wavelist-mf818.workers.dev";

let allProducts = [];
let activeCategory = "All";
let searchQuery = "";
let sortMode = "trending";
const T = (k, fb) => (window.HT_T && window.HT_T[k]) || fb;

async function loadProducts() {
  const grid = document.getElementById("product-grid");
  const countEl = document.getElementById("product-count");
  const countSuffix = document.getElementById("count-suffix");

  grid.innerHTML = "";
  renderSkeletons(grid, 8);

  try {
    const res = await fetch("products.json", { cache: "no-store" });
    if (!res.ok) throw new Error(`products.json responded with ${res.status}`);
    const data = await res.json();
    if (!Array.isArray(data)) throw new Error("products.json must be an array");
    allProducts = data;
  } catch (err) {
    console.error(err);
    grid.innerHTML = "";
    grid.appendChild(emptyState("Couldn't load the catalog. Is products.json reachable?"));
    // leave the count hidden rather than flashing a misleading "0"
    return;
  }

  countEl.textContent = allProducts.length;
  if (countSuffix) countSuffix.hidden = false;
  buildCategoryBar();
  renderGrid();
  focusLinkedProduct();
}

/* --- Deep link: /?p=<product id> ---------------------------------------
   Every post advertises ONE product but the link used to land on the full
   120-card grid, leaving the visitor to hunt for the thing that interested
   them. When ?p= names a product that's still in the catalog, scroll to its
   card and highlight it. If it has rotated out, say so plainly instead of
   dropping the visitor into the grid with no explanation. */
function focusLinkedProduct() {
  const wanted = new URLSearchParams(window.location.search).get("p");
  if (!wanted) return;

  const product = allProducts.find((p) => p.id === wanted);
  const grid = document.getElementById("product-grid");
  if (!product) {
    const note = document.createElement("div");
    note.className = "order-banner order-banner-canceled";
    note.textContent = T("linkedGone",
      "That item has rotated out of the catalog — here's what's trending right now.");
    grid.parentElement.insertBefore(note, grid);
    return;
  }

  // the linked card must be visible whatever the default filters are
  activeCategory = "All";
  searchQuery = "";
  const search = document.getElementById("product-search");
  if (search) search.value = "";
  document.querySelectorAll(".category-chip").forEach((c) =>
    c.classList.toggle("is-active", c.textContent === "All"));
  renderGrid();

  const card = grid.querySelector(`.card[data-product-id="${CSS.escape(wanted)}"]`);
  if (!card) return;

  card.classList.add("card-linked");
  card.style.animationDelay = "0s";   // no stagger on the card they came for
  requestAnimationFrame(() => card.scrollIntoView({ behavior: "smooth", block: "center" }));
}

function renderSkeletons(grid, n) {
  for (let i = 0; i < n; i++) {
    const card = document.createElement("div");
    card.className = "card skeleton";
    card.innerHTML =
      '<div class="card-thumb"></div>' +
      '<div class="card-body">' +
      '<div class="skeleton-line" style="width:40%"></div>' +
      '<div class="skeleton-line" style="width:88%"></div>' +
      '<div class="skeleton-line" style="width:62%"></div>' +
      "</div>";
    grid.appendChild(card);
  }
}

function buildCategoryBar() {
  const bar = document.getElementById("category-bar");
  if (!bar) return;
  bar.innerHTML = "";

  const counts = new Map();
  for (const p of allProducts) {
    const c = p.category || "Other";
    counts.set(c, (counts.get(c) || 0) + 1);
  }
  const categories = ["All", ...[...counts.keys()].sort((a, b) => counts.get(b) - counts.get(a))];

  for (const cat of categories) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "category-chip" + (cat === activeCategory ? " active" : "");
    if (cat !== "All") chip.style.setProperty("--cat-color", categoryColor(cat));
    chip.setAttribute("role", "tab");
    chip.setAttribute("aria-selected", cat === activeCategory ? "true" : "false");
    chip.textContent = cat === "All" ? `${T("all", "All")} (${allProducts.length})` : `${cat} (${counts.get(cat)})`;
    chip.addEventListener("click", () => {
      activeCategory = cat;
      buildCategoryBar();
      renderGrid();
    });
    bar.appendChild(chip);
  }

  // Merch lives in its own section (not the catalog), so its "category" chip
  // is a jump-link. Placed right after "All" so the new drop stays visible.
  const merchChip = document.createElement("a");
  merchChip.href = "#merch";
  merchChip.className = "category-chip category-chip-merch";
  merchChip.textContent = "Merch ✨";
  bar.insertBefore(merchChip, bar.children[1] || null);
}

function renderGrid() {
  const grid = document.getElementById("product-grid");
  grid.innerHTML = "";

  const q = searchQuery.trim().toLowerCase();
  const visible = allProducts
    .filter((p) => activeCategory === "All" || (p.category || "Other") === activeCategory)
    .filter((p) => !q || `${p.name || ""} ${p.fullName || ""} ${p.description || ""} ${p.category || ""}`.toLowerCase().includes(q))
    .sort((a, b) => {
      if (sortMode === "price-asc") return (Number(a.price) || 0) - (Number(b.price) || 0);
      if (sortMode === "price-desc") return (Number(b.price) || 0) - (Number(a.price) || 0);
      return (Number(b.trendScore) || 0) - (Number(a.trendScore) || 0);
    });

  if (visible.length === 0) {
    grid.appendChild(emptyState(q
      ? T("noMatches", "No matches — try fewer or different words.")
      : "No trending products right now — check back soon."));
    return;
  }
  visible.forEach((product, i) => {
    const card = buildCard(product);
    // gentle staggered fade-in as the grid renders
    card.style.animationDelay = (i * 0.04) + "s";
    grid.appendChild(card);
  });
}

function emptyState(message) {
  const div = document.createElement("div");
  div.className = "empty-state";
  div.textContent = message;
  return div;
}

// Category border colors: known categories get brand-tuned hues; anything new
// falls back to a stable pick from the palette (hash of the name), so colors
// never change between visits or cycles.
const CATEGORY_COLORS = {
  "Fashion": "#fb5d7d",
  "Beauty": "#f472b6",
  "Jewelry": "#fbbf24",
  "Footwear": "#fb923c",
  "Kitchen": "#f97352",
  "Home": "#a78bfa",
  "Electronics": "#38bdf8",
  "Gadgets": "#38bdf8",
  "Pet": "#a3e635",
  "Fitness": "#2dd4bf",
  "Sports": "#4ade80",
  "Outdoor": "#34d399",
  "Auto": "#94a3b8",
  "Bags": "#e879f9",
  "Trending Finds": "#f59e0b",
};
const CATEGORY_FALLBACK = ["#fb5d7d", "#fb923c", "#a78bfa", "#2dd4bf", "#38bdf8", "#4ade80", "#e879f9", "#94a3b8"];

function categoryColor(cat) {
  if (CATEGORY_COLORS[cat]) return CATEGORY_COLORS[cat];
  let h = 0;
  for (let i = 0; i < cat.length; i++) h = (h * 31 + cat.charCodeAt(i)) >>> 0;
  return CATEGORY_FALLBACK[h % CATEGORY_FALLBACK.length];
}

function buildCard(p) {
  const price = (Number(p.price) || 0).toFixed(2);
  const trendScore = Number.isFinite(Number(p.trendScore)) ? p.trendScore : "—";

  const card = document.createElement("article");
  card.className = "card";
  card.dataset.productId = p.id || "";   // lets /?p=<id> find its card
  card.style.setProperty("--cat-color", categoryColor(p.category || "Other"));

  const thumb = document.createElement("div");
  thumb.className = "card-thumb";
  if (typeof p.gradient === "string") {
    thumb.style.background = p.gradient;
  }

  if (typeof p.image === "string" && p.image) {
    const img = document.createElement("img");
    img.className = "card-thumb-img";
    img.src = p.image;
    img.alt = p.name || "";
    img.loading = "lazy";
    img.referrerPolicy = "no-referrer";
    img.addEventListener("error", () => {
      // photo failed to load (CDN hiccup): show the emoji tile instead of
      // leaving a blank gradient
      img.remove();
      const fallback = document.createElement("span");
      fallback.textContent = p.emoji || "";
      fallback.setAttribute("aria-hidden", "true");
      thumb.prepend(fallback);
    }, { once: true });
    thumb.appendChild(img);
  } else {
    const emojiSpan = document.createElement("span");
    emojiSpan.textContent = p.emoji || "";
    emojiSpan.setAttribute("aria-hidden", "true");
    thumb.appendChild(emojiSpan);
  }

  const badge = document.createElement("span");
  badge.className = "card-badge";
  badge.textContent = p.badge || "";
  thumb.appendChild(badge);

  // tap the photo -> detail sheet with the full listing name + description
  thumb.classList.add("thumb-tappable");
  thumb.setAttribute("role", "button");
  thumb.tabIndex = 0;
  thumb.setAttribute("aria-label", p.name || T("untitled", "Untitled product"));
  thumb.addEventListener("click", () => openProductSheet(p));
  thumb.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openProductSheet(p); }
  });

  const body = document.createElement("div");
  body.className = "card-body";

  const category = document.createElement("div");
  category.className = "card-category";
  category.textContent = p.category || "";

  const name = document.createElement("h3");
  name.className = "card-name";
  name.textContent = p.name || T("untitled", "Untitled product");
  // hover shows the supplier's full title; the card itself stays punchy
  name.title = p.fullName || p.name || "";

  const desc = document.createElement("p");
  desc.className = "card-desc";
  desc.textContent = p.description || "";

  const footer = document.createElement("div");
  footer.className = "card-footer";

  const priceEl = document.createElement("span");
  priceEl.className = "card-price";
  priceEl.textContent = `$${price}`;

  const trendEl = document.createElement("span");
  trendEl.className = "card-trend";
  trendEl.textContent = `Trend score ${trendScore}`;

  footer.append(priceEl, trendEl);

  const buyButton = document.createElement("button");
  buyButton.className = "btn btn-primary card-buy";
  buyButton.type = "button";
  buyButton.textContent = T("buyNow", "Buy now");
  buyButton.addEventListener("click", () => startCheckout(p.id, buyButton));

  body.append(category, name, desc, footer, buyButton);
  card.append(thumb, body);

  return card;
}

/* --- Product detail sheet: tap a product photo and it opens large, with the
   full supplier listing name, the description, and a Buy button. Bottom sheet
   on phones, centered dialog on desktop. Closes on X, backdrop, Escape, or
   the phone's back button (via a history entry). --- */
let sheetEls = null;

function ensureSheet() {
  if (sheetEls) return sheetEls;

  const backdrop = document.createElement("div");
  backdrop.className = "sheet-backdrop";
  backdrop.hidden = true;

  const sheet = document.createElement("article");
  sheet.className = "product-sheet";
  sheet.setAttribute("role", "dialog");
  sheet.setAttribute("aria-modal", "true");

  const closeBtn = document.createElement("button");
  closeBtn.className = "sheet-close";
  closeBtn.type = "button";
  closeBtn.setAttribute("aria-label", T("sheetClose", "Close"));
  closeBtn.innerHTML = "&times;";

  const media = document.createElement("div");
  media.className = "sheet-media";
  const body = document.createElement("div");
  body.className = "sheet-body";

  sheet.append(closeBtn, media, body);
  backdrop.appendChild(sheet);
  document.body.appendChild(backdrop);

  closeBtn.addEventListener("click", () => closeProductSheet(true));
  backdrop.addEventListener("click", (e) => { if (e.target === backdrop) closeProductSheet(true); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !backdrop.hidden) closeProductSheet(true);
  });
  window.addEventListener("popstate", () => { if (!backdrop.hidden) closeProductSheet(false); });

  sheetEls = { backdrop, sheet, media, body, closeBtn };
  return sheetEls;
}

function openProductSheet(p) {
  const els = ensureSheet();
  els.sheet.style.setProperty("--cat-color", categoryColor(p.category || "Other"));
  els.media.innerHTML = "";
  els.body.innerHTML = "";
  els.media.style.background = typeof p.gradient === "string" ? p.gradient : "";

  const showEmoji = () => {
    const span = document.createElement("span");
    span.textContent = p.emoji || "";
    span.setAttribute("aria-hidden", "true");
    els.media.prepend(span);
  };
  if (typeof p.image === "string" && p.image) {
    const img = document.createElement("img");
    img.src = p.image;
    img.alt = p.name || "";
    img.referrerPolicy = "no-referrer";
    img.addEventListener("error", () => { img.remove(); showEmoji(); }, { once: true });
    els.media.appendChild(img);
  } else {
    showEmoji();
  }

  const category = document.createElement("div");
  category.className = "sheet-category";
  category.textContent = p.category || "";

  const name = document.createElement("h3");
  name.className = "sheet-name";
  name.textContent = p.name || T("untitled", "Untitled product");

  const desc = document.createElement("p");
  desc.className = "sheet-desc";
  desc.textContent = p.description || "";

  const meta = document.createElement("div");
  meta.className = "sheet-meta";
  const price = document.createElement("span");
  price.className = "sheet-price";
  price.textContent = `$${(Number(p.price) || 0).toFixed(2)}`;
  const trend = document.createElement("span");
  trend.className = "sheet-trend";
  trend.textContent = `${T("sheetTrend", "Trend score")} ${Number.isFinite(Number(p.trendScore)) ? p.trendScore : "—"}`;
  meta.append(price, trend);

  const buyButton = document.createElement("button");
  buyButton.className = "btn btn-primary card-buy";
  buyButton.type = "button";
  buyButton.textContent = T("buyNow", "Buy now");
  buyButton.addEventListener("click", () => startCheckout(p.id, buyButton));

  els.body.append(category, name, desc);
  // the supplier's full listing title often carries extra spec words the short
  // name drops — show it when it genuinely adds something
  if (p.fullName && p.fullName !== p.name) {
    const listed = document.createElement("p");
    listed.className = "sheet-fullname";
    listed.textContent = `${T("sheetListed", "Listed as:")} ${p.fullName}`;
    els.body.appendChild(listed);
  }
  els.body.append(meta, buyButton);

  els.backdrop.hidden = false;
  requestAnimationFrame(() => els.backdrop.classList.add("open"));
  document.body.style.overflow = "hidden";
  try { history.pushState({ sheet: p.id || 1 }, ""); } catch (e) { /* sandboxed iframes */ }
}

function closeProductSheet(viaUi) {
  const els = sheetEls;
  if (!els || els.backdrop.hidden) return;
  els.backdrop.classList.remove("open");
  els.backdrop.hidden = true;
  document.body.style.overflow = "";
  // pop the history entry we pushed on open, so Back doesn't need two taps
  if (viaUi && history.state && history.state.sheet) history.back();
}

async function startCheckout(productId, button, designId) {
  // count the Buy click as a `buy-<id>` event — this is the "interacted with"
  // signal the catalog rotation uses to decide which items stay
  if (window.goatcounter && typeof window.goatcounter.count === "function") {
    try {
      window.goatcounter.count({ path: "buy-" + productId, title: "Buy click", event: true });
    } catch (e) { /* analytics must never block a sale */ }
  }
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = T("redirecting", "Redirecting…");

  try {
    const res = await fetch(`${CHECKOUT_API}/create-checkout-session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(designId ? { productId, designId } : { productId }),
    });
    const data = await res.json();
    if (!res.ok || !data.url) {
      throw new Error(data.error || `Checkout request failed (${res.status})`);
    }
    window.location.href = data.url;
  } catch (err) {
    console.error(err);
    button.disabled = false;
    button.textContent = originalText;
    alert(T("checkoutFail", "Couldn't start checkout. Please try again in a moment."));
  }
}

function showOrderStatusBanner() {
  const params = new URLSearchParams(window.location.search);
  const main = document.querySelector("main");
  if (params.get("success") === "1") {
    const banner = document.createElement("div");
    banner.className = "order-banner order-banner-success";
    banner.textContent = T("paidBanner", "Payment received — thank you! Your order is being placed for fulfillment.");
    main.prepend(banner);
  } else if (params.get("canceled") === "1") {
    const banner = document.createElement("div");
    banner.className = "order-banner order-banner-canceled";
    banner.textContent = T("canceledBanner", "Checkout canceled — no charge was made.");
    main.prepend(banner);
  }
}

(function initCatalogControls() {
  const search = document.getElementById("product-search");
  const sort = document.getElementById("product-sort");
  if (search) {
    let t = null;
    search.addEventListener("input", () => {
      clearTimeout(t);
      t = setTimeout(() => { searchQuery = search.value; renderGrid(); }, 120);
    });
  }
  if (sort) {
    sort.addEventListener("change", () => { sortMode = sort.value; renderGrid(); });
  }
})();

document.getElementById("year").textContent = new Date().getFullYear();
showOrderStatusBanner();
loadProducts();

/* --- Custom-design merch: upload art, then buy (middleman flow) --- */
(function initCustomMerch() {
  const fileInput = document.getElementById("design-file");
  const preview = document.getElementById("design-preview");
  const hint = document.getElementById("design-hint");
  const buyBtn = document.getElementById("design-buy");
  if (!fileInput || !buyBtn) return;

  let designId = null;

  fileInput.addEventListener("change", async () => {
    const file = fileInput.files && fileInput.files[0];
    if (!file) return;
    if (file.size > 8 * 1024 * 1024) {
      hint.innerHTML = T("over8mb", "<b>That file is over 8 MB</b><br><small>Try a smaller image</small>");
      return;
    }
    const dataUrl = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
    preview.src = dataUrl;
    preview.hidden = false;
    hint.hidden = true;
    buyBtn.disabled = true;
    buyBtn.textContent = T("uploading", "Uploading…");
    try {
      const res = await fetch(`${CHECKOUT_API}/upload-design`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: file.name, dataUrl }),
      });
      const data = await res.json();
      if (!res.ok || !data.designId) throw new Error(data.error || "upload failed");
      designId = data.designId;
      buyBtn.disabled = false;
      buyBtn.textContent = T("buy", "Buy");
    } catch (err) {
      designId = null;
      buyBtn.textContent = T("buy", "Buy");
      preview.hidden = true;
      hint.hidden = false;
      hint.innerHTML = T("uploadFailPrefix", "<b>Upload failed</b><br><small>") + String(err.message || err) + T("uploadFailSuffix", " — tap to retry</small>");
    }
  });

  buyBtn.addEventListener("click", () => {
    if (designId) startCheckout("custom-tee", buyBtn, designId);
  });
})();

/* --- Merch card clicks: merch-<slug> events, the pop-up store's only
       funnel signal — GoatCounter can't see printify.me itself --------- */
(function trackMerchClicks() {
  const SLUGS = {
    "30344866": "merch-tee",
    "30344867": "merch-crewneck",
    "30344868": "merch-cap",
    "30345175": "merch-mug",
    "30345176": "merch-sticker",
  };
  document.querySelectorAll('#merch a[href*="printify.me"]').forEach((link) => {
    link.addEventListener("click", () => {
      if (window.goatcounter && typeof window.goatcounter.count === "function") {
        try {
          const id = (link.href.match(/product\/(\d+)/) || [])[1];
          window.goatcounter.count({ path: SLUGS[id] || "merch-store", title: "Merch click", event: true });
        } catch (e) { /* analytics must never block the hop to the store */ }
      }
    });
  });
})();

/* ---- app install (PWA) ---------------------------------------------- */
(() => {
  if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("sw.js").catch((err) => console.warn("sw registration failed", err));
    });
  }

  const DISMISS_KEY = "hotstuff-install-dismissed";
  const isStandalone =
    window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
  if (isStandalone || localStorage.getItem(DISMISS_KEY)) return;

  const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
  let deferredPrompt = null;
  let pill = null;

  function makePill() {
    if (pill) return pill;
    pill = document.createElement("div");
    pill.className = "install-pill";
    pill.innerHTML =
      '<button type="button" class="install-pill-btn">' + T("getApp", "📲 Get the app") + "</button>" +
      '<button type="button" class="install-pill-close" aria-label="Dismiss">×</button>';
    document.body.appendChild(pill);
    pill.querySelector(".install-pill-close").addEventListener("click", () => {
      localStorage.setItem(DISMISS_KEY, "1");
      pill.remove();
    });
    pill.querySelector(".install-pill-btn").addEventListener("click", async () => {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        const choice = await deferredPrompt.userChoice;
        deferredPrompt = null;
        if (choice.outcome === "accepted") {
          localStorage.setItem(DISMISS_KEY, "1");
          pill.remove();
        }
      } else if (isIOS) {
        showIOSHint();
      }
    });
    return pill;
  }

  function showIOSHint() {
    let hint = pill.querySelector(".install-hint");
    if (hint) { hint.remove(); return; }
    hint = document.createElement("div");
    hint.className = "install-hint";
    hint.innerHTML = T("iosHint", "Tap <b>Share</b> ▸ <b>Add to Home Screen</b> to install HotsTuff.");
    pill.appendChild(hint);
  }

  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredPrompt = e;
    makePill();
  });

  // iOS Safari never fires beforeinstallprompt — offer the hint instead
  if (isIOS) makePill();

  window.addEventListener("appinstalled", () => {
    localStorage.setItem(DISMISS_KEY, "1");
    if (pill) pill.remove();
  });
})();
