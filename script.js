const CHECKOUT_API = "https://wavelist-checkout.wavelist-mf818.workers.dev";

let allProducts = [];
let activeCategory = "All";
let activeSubgroup = "All";
const OTHER_SUBGROUP = "Everything else";
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
  buildSubgroupBar();
  renderGrid();
  initTiles();
  renderDropRows();
  focusLinkedProduct();
}

/* --- Boutique tiles + "The latest drop" rows (Matthew's pick, 2026-11-05) ---
   Everything here is built from products.json on every load, so it follows
   each 3-day refresh by itself. No ratings, stock counts or "bestseller"
   labels: only real names and real USD prices. */

// Same gift rule as make_category_pages.py (GIFT_MAX 25): skips personal-care.
const GIFT_SKIP_CATEGORIES = ["Wellness", "Beauty"];
const GIFT_SKIP_WORDS = ["diaper", "weight loss", "bandage", "toothbrush", "slimming"];
function giftItems(max) {
  return allProducts
    .filter((p) => {
      const price = Number(p.price) || 0;
      const name = (p.name || "").toLowerCase();
      return price > 0 && price < max && !GIFT_SKIP_CATEGORIES.includes(p.category)
        && !GIFT_SKIP_WORDS.some((w) => name.includes(w));
    })
    .sort((a, b) => (Number(a.price) - Number(b.price)) || (Number(b.trendScore) - Number(a.trendScore)));
}
const byTrend = (list) => list.slice().sort((a, b) => (Number(b.trendScore) || 0) - (Number(a.trendScore) || 0));
const inCategory = (cat) => byTrend(allProducts.filter((p) => (p.category || "Other") === cat));

/* Tile photo rule (automatic, text-based): a tile only uses a photo whose
   product name says it belongs to that tile (a lamp for Home, a ring for
   Jewelry...), and never one whose name suggests a face or body shot (masks,
   glasses, wigs, makeup, socks...). Each tile gets a different photo. If no
   product passes, the tile falls back to the top product of its category. */
const TILE_AVOID = /\b(mask|masks|glasses|sunglass\w*|goggle\w*|wig|wigs|makeup|lipstick|eyeshadow|eyelash\w*|lash|face|facial|tattoo|bandage|diaper\w*|sock|socks|underwear|leggings|tights|pantyhose|boxer|bra|bikini|swimsuit|shapewear|waist|slimming|mattress|air cushion)\b/i;
const TILE_FITS = {
  Gifts: /\b(mug|cup|vase|ornament\w*|lamp|light|candle|plush|necklace|bracelet|earrings?|pendant|ring|music box|keychain|figurine|planter|blanket)\b/i,
  Jewelry: /\b(necklace|bracelet|earrings?|pendant|rings?|bangle|anklet|brooch|chain)\b/i,
  Pet: /\b(dog|dogs|cat|cats|pet|pets|puppy|kitten|leash|collar|paw)\b/i,
  Home: /\b(lamp|light|lights|pillow|cushion|vase|decor\w*|blanket|throw|plant|planter|wall|curtain|rug|candle|mirror|clock|ornament\w*|shelf|basket|hanging|figurine|statue|bedding|frame)\b/i,
  Kitchen: /\b(kitchen|knife|knives|cup|mug|bowl|pan|pot|spoon|spatula|cutting|board|baking|chef|kettle|mince\w*|crusher|grater|peeler|whisk|cocktail|bottle|storage|cookware)\b/i,
  Fashion: /\b(jacket|coat|sweater|cardigan|hoodie|shirt|blouse|dress|blazer|skirt|scarf|hat|cap|vest|pants|trousers|jeans|top)\b/i,
};
function pickTilePhoto(tile, used) {
  const pool = tile === "Gifts" ? byTrend(giftItems(25)) : inCategory(tile);
  const ok = (p) => p.image && !used.has(p.image);
  const good = pool.find((p) => ok(p) && TILE_FITS[tile].test(p.name || "") && !TILE_AVOID.test(p.name || ""));
  return good || pool.find((p) => ok(p) && !TILE_AVOID.test(p.name || "")) || pool.find(ok) || null;
}
function initTiles() {
  const used = new Set();
  document.querySelectorAll(".cat-tile[data-tile]").forEach((tile) => {
    const key = tile.dataset.tile;
    const n = key === "Gifts" ? giftItems(25).length : inCategory(key).length;
    tile.hidden = n === 0;
    if (!n) return;
    tile.dataset.count = n;
    const p = pickTilePhoto(key, used);
    const img = tile.querySelector("img");
    if (p && img) { used.add(p.image); img.src = p.image; img.addEventListener("error", () => { img.remove(); }, { once: true }); }
  });
  renderTileCounts();
}
function renderTileCounts() {
  document.querySelectorAll(".cat-tile[data-count]").forEach((tile) => {
    const el = tile.querySelector(".tile-count");
    if (el) el.textContent = T("tileCount", "{n} items").replace("{n}", tile.dataset.count);
  });
}

const DROP_ROWS = [
  { key: "rowGifts15", en: "Gifts under $15", items: () => giftItems(15), link: "gifts/?ref=row" },
  { key: "rowPet", en: "For pet people", items: () => inCategory("Pet"), link: "c/pet/?ref=row" },
  { key: "rowHome", en: "Home finds", items: () => inCategory("Home"), link: "c/home/?ref=row" },
  { key: "rowJewelry", en: "Jewelry picks", items: () => inCategory("Jewelry"), link: "c/jewelry/?ref=row" },
  { key: "rowKitchen", en: "Kitchen helpers", items: () => inCategory("Kitchen"), link: "c/kitchen/?ref=row" },
  // true trend order, whole catalogue, nothing filtered out
  { key: "rowTrending", en: "Trending right now", items: () => byTrend(allProducts), link: null },
];
const ROW_MAX = 12;
function buildDropCard(p) {
  const card = document.createElement("button");
  card.type = "button";
  card.className = "drop-card";
  card.dataset.productId = p.id || "";
  card.setAttribute("aria-label", `${p.name || ""}, $${(Number(p.price) || 0).toFixed(2)} USD`);
  const ph = document.createElement("span");
  ph.className = "drop-ph";
  if (!p.image && typeof p.gradient === "string") ph.style.background = p.gradient;
  if (p.image) {
    const img = document.createElement("img");
    img.src = p.image; img.alt = ""; img.loading = "lazy"; img.referrerPolicy = "no-referrer";
    img.addEventListener("error", () => { img.remove(); ph.textContent = p.emoji || ""; }, { once: true });
    ph.appendChild(img);
  } else {
    ph.textContent = p.emoji || "";
  }
  const name = document.createElement("span");
  name.className = "drop-name";
  name.textContent = p.name || T("untitled", "Untitled product");
  const price = document.createElement("span");
  price.className = "drop-price";
  price.textContent = `$${(Number(p.price) || 0).toFixed(2)}`;
  const cur = document.createElement("small");
  cur.textContent = " USD";
  price.appendChild(cur);
  card.append(ph, name, price);
  card.addEventListener("click", () => openProductSheet(p));
  return card;
}
function renderDropRows() {
  const wrap = document.getElementById("drop-rows");
  if (!wrap || !allProducts.length) return;
  wrap.innerHTML = "";
  DROP_ROWS.forEach((row) => {
    const items = row.items();
    if (!items.length) return;
    const sec = document.createElement("div");
    sec.className = "drop-row";
    const head = document.createElement("div");
    head.className = "drop-row-head";
    const h = document.createElement("h3");
    h.textContent = T(row.key, row.en);
    head.appendChild(h);
    const more = document.createElement(row.link ? "a" : "button");
    more.className = "drop-more";
    if (row.link) {
      more.href = row.link;
      more.textContent = T("seeAll", "See all {n} →").replace("{n}", items.length);
    } else {
      more.type = "button";
      more.textContent = T("searchAll", "Search all {n} →").replace("{n}", allProducts.length);
      more.addEventListener("click", () => openBrowse(false));
    }
    head.appendChild(more);
    const rail = document.createElement("div");
    rail.className = "drop-rail";
    items.slice(0, ROW_MAX).forEach((p) => rail.appendChild(buildDropCard(p)));
    sec.append(head, rail);
    wrap.appendChild(sec);
  });
}
window.HT_RENDER_DROP = () => { renderDropRows(); renderTileCounts(); };

/* Search icon (from mockup B): opens the full searchable list, with the
   category filters, sort and the regular cards (Buy now on each). */
function openBrowse(focus = true) {
  const browse = document.getElementById("browse");
  if (!browse) return;
  browse.hidden = false;
  browse.scrollIntoView({ behavior: "smooth", block: "start" });
  const input = document.getElementById("product-search");
  if (focus && input) setTimeout(() => input.focus({ preventScroll: true }), 350);
}
(function initSearchToggle() {
  const btn = document.getElementById("search-toggle");
  if (btn) btn.addEventListener("click", () => openBrowse(true));
})();

/* --- "New lineup in X days" (council 2026-11-05) ---------------------------
   Read from catalog-meta.json, which the 3-day refresh writes from the real
   cron. Shown only when we can trust it: the file exists, this lineup is at
   most 4 days old, and the next refresh is still in the future. Otherwise
   the line stays hidden: never a wrong number. */
let catalogMeta = null;
function renderNextLineup() {
  const el = document.getElementById("next-lineup");
  if (!el) return;
  el.hidden = true;
  if (!catalogMeta) return;
  const now = new Date();
  const last = new Date(catalogMeta.refreshed_at);
  const next = new Date(catalogMeta.next_refresh);
  if (isNaN(last) || isNaN(next)) return;
  if (now - last > 4 * 86400000 || next <= now) return;
  const day = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const days = Math.round((day(next) - day(now)) / 86400000);
  let text;
  if (days <= 0) text = T("nextToday", "New lineup later today");
  else if (days === 1) text = T("nextTomorrow", "New lineup tomorrow");
  else text = T("nextIn", "New lineup in {n} days").replace("{n}", days);
  el.textContent = " · " + text;
  el.hidden = false;
}
window.HT_RENDER_NEXT = renderNextLineup;
(async function loadCatalogMeta() {
  try {
    const res = await fetch("catalog-meta.json", { cache: "no-store" });
    if (!res.ok) return;
    catalogMeta = await res.json();
    renderNextLineup();
  } catch (e) { /* stays hidden */ }
})();

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
    const rows = document.getElementById("drop-rows");
    (rows || grid).parentElement.insertBefore(note, rows || grid);
    return;
  }

  // the linked card must be visible whatever the default filters are
  const browse = document.getElementById("browse");
  if (browse) browse.hidden = false;
  activeCategory = "All";
  activeSubgroup = "All";
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
      activeSubgroup = "All";
      buildCategoryBar();
      buildSubgroupBar();
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

// Second-level filter. Only appears when the active category actually has
// more than one subgroup in the current rotation -- a bar with one chip in it
// is noise, and the catalogue is rebuilt every three days, so which categories
// deserve one changes on its own.
function buildSubgroupBar() {
  const bar = document.getElementById("subgroup-bar");
  if (!bar) return;
  bar.innerHTML = "";

  const counts = new Map();
  let unlabelled = 0;
  if (activeCategory !== "All") {
    for (const p of allProducts) {
      if ((p.category || "Other") !== activeCategory) continue;
      const g = p.subgroup || "";
      if (!g) unlabelled += 1;
      else counts.set(g, (counts.get(g) || 0) + 1);
    }
  }

  if (counts.size < 2) {
    bar.hidden = true;
    return;
  }
  bar.hidden = false;

  const total = [...counts.values()].reduce((a, b) => a + b, 0) + unlabelled;
  const groups = ["All", ...[...counts.keys()].sort((a, b) => counts.get(b) - counts.get(a))];
  if (unlabelled) groups.push(OTHER_SUBGROUP);

  for (const g of groups) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "subgroup-chip" + (g === activeSubgroup ? " active" : "");
    chip.setAttribute("role", "tab");
    chip.setAttribute("aria-selected", g === activeSubgroup ? "true" : "false");
    const n = g === "All" ? total : (g === OTHER_SUBGROUP ? unlabelled : counts.get(g));
    chip.textContent = `${g === "All" ? T("all", "All") : g} (${n})`;
    chip.addEventListener("click", () => {
      activeSubgroup = g;
      buildSubgroupBar();
      renderGrid();
    });
    bar.appendChild(chip);
  }
}

function renderGrid() {
  const grid = document.getElementById("product-grid");
  grid.innerHTML = "";

  const q = searchQuery.trim().toLowerCase();
  const visible = allProducts
    .filter((p) => activeCategory === "All" || (p.category || "Other") === activeCategory)
    .filter((p) => activeSubgroup === "All"
      || (activeSubgroup === OTHER_SUBGROUP ? !p.subgroup : p.subgroup === activeSubgroup))
    .filter((p) => !q || `${p.name || ""} ${p.fullName || ""} ${p.description || ""} ${p.category || ""} ${p.subgroup || ""}`.toLowerCase().includes(q))
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
  // "JEWELRY · NECKLACES" -- the subgroup is the useful half once a shopper
  // is scanning a filtered grid, so show it where the category already is.
  category.textContent = [p.category, p.subgroup].filter(Boolean).join(" · ");

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
  const cardCur = document.createElement("small");
  cardCur.className = "price-cur";
  cardCur.textContent = " USD";
  priceEl.appendChild(cardCur);

  // The trend score used to sit here beside the price. "95" out of what? It
  // meant nothing to a shopper and took the second-most valuable spot on the
  // card to say it. The score still decides which products get picked and
  // drives the "Trending first" sort -- it just isn't shown as a bare number.
  // It stays on the detail sheet, where someone who opened a product has room
  // for it and the "Trending" badge above already sets the context.
  footer.append(priceEl);

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
  category.textContent = [p.category, p.subgroup].filter(Boolean).join(" · ");

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
  const sheetCur = document.createElement("small");
  sheetCur.className = "price-cur";
  sheetCur.textContent = " USD";
  price.appendChild(sheetCur);
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
  // what to expect, right under Buy now; same facts as the terms page
  const expect = document.createElement("p");
  expect.className = "sheet-expect";
  const expectText = document.createElement("span");
  expectText.className = "sheet-expect-text";
  expectText.textContent = T("expectSheet",
    "Ships from our supplier. Processed in 1–3 business days, usually 1–3 weeks to arrive. Prices in USD. 30-day guarantee.");
  const termsLink = document.createElement("a");
  termsLink.href = "terms/";
  termsLink.textContent = T("terms", "Terms");
  expect.append(expectText, " ", termsLink);
  els.body.appendChild(expect);

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

  // Phones (11-05): the bubble waits until the visitor has scrolled past the
  // first products, so it never covers the first screen. Desktop: unchanged.
  const isPhone = window.matchMedia("(max-width: 640px)").matches;
  let scrolledPast = !isPhone || !document.getElementById("drop-rows");
  let wanted = false;
  function pastFirstProducts() {
    const first = document.querySelector("#drop-rows .drop-row");
    if (!first) return false;
    return first.getBoundingClientRect().bottom < 0;
  }
  function onScroll() {
    if (scrolledPast || !pastFirstProducts()) return;
    scrolledPast = true;
    window.removeEventListener("scroll", onScroll);
    if (wanted) makePill();
  }
  if (!scrolledPast) window.addEventListener("scroll", onScroll, { passive: true });
  function offerPill() {
    wanted = true;
    if (scrolledPast) makePill();
  }

  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredPrompt = e;
    offerPill();
  });

  // iOS Safari never fires beforeinstallprompt — offer the hint instead
  if (isIOS) offerPill();

  window.addEventListener("appinstalled", () => {
    localStorage.setItem(DISMISS_KEY, "1");
    if (pill) pill.remove();
  });
})();
