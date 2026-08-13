/*
 * HotsTuff storefront i18n — EN (default, in the markup) + FR overlay.
 *
 * How it works: elements carry data-i18n="key". On switch to FR, each
 * element's English innerHTML is remembered and replaced with the FR
 * dictionary entry; switching back restores the originals. Runtime strings
 * (Buy buttons, banners, chips) are exposed to script.js via window.HT_T.
 *
 * Language choice: ?lang=fr|en param > saved choice > browser language.
 */

(function () {
  const FR = {
    "announce": "🚚 <b>Livraison gratuite</b><span class=\"announce-detail\"> sur chaque commande</span><span class=\"announce-extra\"> · 🔒 Paiement sécurisé Stripe</span> · ↩️ Garantie 30 jours ou argent remis",
    "nav-trending": "Tendances",
    "nav-how": "Comment ça marche",
    "nav-merch": "Merch <span class=\"nav-new\">Nouveau</span>",
    "nav-shipping": "Livraison",
    "nav-automation": "Automatisation",
    "nav-shop": "Magasinez les tendances",
    "eyebrow-main": "Réapprovisionné chaque jour",
    "eyebrow-products": "produits en ligne",
    "hero-title": "Bienvenue chez <span class=\"brand-accent\">HotsTuff!</span><br>Des produits tendance que les gens aiment vraiment.",
    "hero-sub": "HotsTuff suit ce qui est tendance sur les réseaux et dans les recherches, puis compose une nouvelle sélection de produits aux quelques jours. Pas de catalogue figé, pas d'inventaire mort — juste ce qui est hot en ce moment.",
    "hero-cta-shop": "Voir les tendances",
    "hero-cta-how": "Comment ça fonctionne",
    "hero-cta-automation": "✨ Automatisation pour votre entreprise",
    "trust-1": "<b>Paiement sécurisé</b><small>Transactions traitées par Stripe</small>",
    "trust-2": "<b>Livraison suivie gratuite</b><small>Sur chaque commande — 24 pays</small>",
    "trust-3": "<b>Garantie 30 jours</b><small>Remboursement complet ou remplacement gratuit</small>",
    "trust-4": "<b>Un vrai humain au soutien</b><small>Réponse en 1 à 2 jours ouvrables</small>",
    "trending-title": "Tendances de la semaine",
    "trending-sub": "Classé par score de tendance — un mélange en direct du volume de recherche et du taux de vente.",
    "merch-eyebrow": "✨ Fraîchement arrivé",
    "merch-sub": "Affichez la flamme — la gamme complète est <b>en ligne</b> : t-shirt, coton ouaté, casquette brodée, tasse et autocollant. Ou téléversez votre propre design et on le met sur un t-shirt.",
    "merch-sticker-price": "À partir de 3,49 $",
    "merch-custom-title": "T-shirt à votre design — 32,99 $",
    "merch-note": "T-shirts personnalisés : choisissez taille et couleur au paiement — on imprime votre visuel et on le livre à votre porte. Téléversez seulement des visuels que vous avez le droit d'imprimer.<br>\n      Le merch à logo part de notre partenaire d'impression — livraison calculée à leur paiement. Voyez la <a href=\"https://hotstuff-store.printify.me\" target=\"_blank\" rel=\"noopener\">boutique merch HotsTuff</a> complète.",
    "how-title": "Comment le catalogue reste frais",
    "how-sub": "Chaque fiche ici, c'est des données, pas du code — c'est ça qui rend la rotation facile.",
    "how-1-title": "Un signal de tendance entre",
    "how-1-body": "Les recherches montantes et la vitesse sur les réseaux font ressortir un produit candidat.",
    "how-2-title": "Ajouté au catalogue",
    "how-2-body": "Une seule entrée s'ajoute à la liste de produits — aucune refonte requise.",
    "how-3-title": "Retiré quand ça refroidit",
    "how-3-body": "Quand le score de tendance baisse, l'entrée est retirée et la place se libère pour la suite.",
    "ship-title": "Livraison et retours",
    "ship-sub": "Des réponses franches avant d'acheter — pas de surprises à la porte.",
    "ship-1-title": "Livraison",
    "ship-1-body": "On livre dans 24 pays — Canada, États-Unis, Royaume-Uni, Australie et la majeure partie de l'Europe. Les commandes sont traitées en 1 à 3 jours ouvrables, et comme les articles partent directement de nos fournisseurs, la livraison prend habituellement <strong>1 à 3 semaines</strong> selon votre région. Vous recevrez un numéro de suivi par courriel dès qu'il est disponible.",
    "ship-2-title": "Retours et remboursements",
    "ship-2-body": "Si votre article arrive endommagé, défectueux, erroné, ou n'arrive jamais, on arrange ça avec un <strong>remplacement gratuit ou un remboursement complet</strong> — écrivez-nous dans les <strong>30 jours</strong> suivant la livraison. Pour un retour par changement d'idée, contactez-nous dans les 14 jours (des frais de retour peuvent s'appliquer).",
    "ship-3-title": "Service à la clientèle",
    "ship-3-body": "HotsTuff est tenu par une vraie personne — Matthew, au Nouveau-Brunswick, Canada. Les articles partent directement de nos fournisseurs : c'est pourquoi la livraison prend 1 à 3 semaines et que les prix restent aussi bas. Un pépin? Textez-moi et je m'en occupe.<br>\n            📞 <a href=\"tel:+15068899737\">(506) 889-9737</a><br>\n            ✉️ <a href=\"mailto:ceohotstuff@yahoo.com\">ceohotstuff@yahoo.com</a>",
    "faq-1-q": "À quelle fréquence le catalogue change-t-il?",
    "faq-1-a": "Assez souvent — de nouveaux produits s'ajoutent et d'autres sortent au rythme des tendances, pas sur un horaire fixe.",
    "faq-2-q": "Est-ce une boutique à produit unique?",
    "faq-2-a": "Non. HotsTuff est volontairement multi-produits et fait tourner sa sélection selon ce qui est tendance et ce qui se vend.",
    "faq-3-q": "En combien de temps une nouvelle tendance apparaît-elle?",
    "faq-3-a": "On surveille les données de tendance et de vente chaque jour : un produit qui monte peut être en ligne en quelques heures — et quand la demande refroidit, il est retiré pour faire place à la suite.",
    "faq-4-q": "Et si je veux un article déjà épuisé ou retiré?",
    "faq-4-a": "Les articles tendance bougent vite, c'est voulu — la disponibilité n'est pas garantie. Chaque fiche est vérifiée avant sa mise en ligne, et si un produit que vous avez acheté sort du catalogue, votre commande, votre garantie et votre soutien restent intacts.",
    "faq-5-q": "Combien de temps prend la livraison?",
    "faq-5-a": "Les commandes sont traitées en 1 à 3 jours ouvrables et arrivent généralement en 1 à 3 semaines, puisque les articles partent directement de nos fournisseurs. Vous recevrez le suivi par courriel. Voir <a href=\"#shipping\">Livraison et retours</a> pour tous les détails.",
    "faq-6-q": "Quelle est votre politique de retour?",
    "faq-6-a": "Article endommagé, défectueux, erroné ou jamais livré : remplacement gratuit ou remboursement complet dans les 30 jours suivant la livraison. Retours par changement d'idée acceptés dans les 14 jours (frais de retour possibles). Contactez le soutien pour commencer un retour.",
    "footer-stripe": "· Paiement sécurisé par Stripe · Tous les prix en USD",
    "sort-trending": "🔥 Tendances d'abord",
    "sort-price-asc": "Prix : du moins cher au plus cher",
    "sort-price-desc": "Prix : du plus cher au moins cher",
    "footer-note": "Soutien : <a href=\"mailto:ceohotstuff@yahoo.com\">ceohotstuff@yahoo.com</a>\n        · <a href=\"tel:+15068899737\">(506) 889-9737</a>\n        · <a href=\"automation/fr/\">Automatisation sociale pour votre entreprise</a>\n        · <a href=\"privacy/\">Confidentialité</a>\n        · <a href=\"terms/\">Conditions</a>",
  };

  // Runtime strings used by script.js
  const T_EN = {
    buyNow: "Buy now", buy: "Buy", redirecting: "Redirecting…", uploading: "Uploading…",
    all: "All", untitled: "Untitled product",
    checkoutFail: "Couldn't start checkout. Please try again in a moment.",
    paidBanner: "Payment received — thank you! Your order is being placed for fulfillment.",
    canceledBanner: "Checkout canceled — no charge was made.",
    over8mb: "<b>That file is over 8 MB</b><br><small>Try a smaller image</small>",
    uploadFailPrefix: "<b>Upload failed</b><br><small>", uploadFailSuffix: " — tap to retry</small>",
    getApp: "📲 Get the app",
    iosHint: "Tap <b>Share</b> ▸ <b>Add to Home Screen</b> to install HotsTuff.",
    title: "HotsTuff — Shop what's trending right now",
    searchPlaceholder: "Search products…",
    noMatches: "No matches — try fewer or different words.",
    sheetClose: "Close", sheetTrend: "Trend score",
    sheetListed: "Listed as:",
  };
  const T_FR = {
    buyNow: "Acheter", buy: "Acheter", redirecting: "Redirection…", uploading: "Téléversement…",
    all: "Tout", untitled: "Produit sans nom",
    checkoutFail: "Impossible de démarrer le paiement. Réessayez dans un instant.",
    paidBanner: "Paiement reçu — merci! Votre commande est en cours de traitement.",
    canceledBanner: "Paiement annulé — aucun montant n'a été facturé.",
    over8mb: "<b>Ce fichier dépasse 8 Mo</b><br><small>Essayez une image plus petite</small>",
    uploadFailPrefix: "<b>Échec du téléversement</b><br><small>", uploadFailSuffix: " — touchez pour réessayer</small>",
    getApp: "📲 Obtenez l'app",
    iosHint: "Touchez <b>Partager</b> ▸ <b>Ajouter à l'écran d'accueil</b> pour installer HotsTuff.",
    title: "HotsTuff — Magasinez ce qui est tendance",
    searchPlaceholder: "Chercher un produit…",
    noMatches: "Aucun résultat — essayez d'autres mots.",
    sheetClose: "Fermer", sheetTrend: "Indice de tendance",
    sheetListed: "Nom complet :",
  };

  const saved = new Map(); // element -> original EN innerHTML

  function currentLang() {
    const q = new URLSearchParams(location.search).get("lang");
    if (q === "fr" || q === "en") return q;
    const stored = localStorage.getItem("hotstuff-lang");
    if (stored) return stored;
    return (navigator.language || "").toLowerCase().startsWith("fr") ? "fr" : "en";
  }

  function applyLang(lang) {
    document.documentElement.lang = lang;
    window.HT_LANG = lang;
    window.HT_T = lang === "fr" ? T_FR : T_EN;
    document.title = window.HT_T.title;

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (lang === "fr") {
        if (!saved.has(el)) saved.set(el, el.innerHTML);
        if (FR[key]) el.innerHTML = FR[key];
      } else if (saved.has(el)) {
        el.innerHTML = saved.get(el);
      }
    });

    // refresh strings that script.js rendered dynamically
    document.querySelectorAll(".card-buy").forEach((b) => {
      if (!b.disabled) b.textContent = window.HT_T.buyNow;
    });
    document.querySelectorAll(".chip").forEach((c) => {
      const m = c.textContent.match(/^(All|Tout) \((\d+)\)$/);
      if (m) c.textContent = `${window.HT_T.all} (${m[2]})`;
    });

    const searchBox = document.getElementById("product-search");
    if (searchBox) searchBox.placeholder = window.HT_T.searchPlaceholder;

    const btn = document.getElementById("lang-toggle");
    if (btn) {
      btn.textContent = lang === "fr" ? "EN" : "FR";
      btn.setAttribute("aria-label", lang === "fr" ? "Switch to English" : "Passer au français");
    }
  }

  window.HT_APPLY_LANG = applyLang;

  document.addEventListener("DOMContentLoaded", () => {
    const btn = document.getElementById("lang-toggle");
    if (btn) {
      btn.addEventListener("click", () => {
        const next = window.HT_LANG === "fr" ? "en" : "fr";
        localStorage.setItem("hotstuff-lang", next);
        applyLang(next);
      });
    }
    applyLang(currentLang());
  });
})();
