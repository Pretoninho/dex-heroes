/* ============================================================================
 * Dex Heroes — Cloud (Phase A) : comptes + sauvegarde cloud via Supabase.
 * ----------------------------------------------------------------------------
 * SCAFFOLD. Tant que SUPABASE_URL / SUPABASE_ANON_KEY sont des placeholders
 * (ou si la librairie Supabase n'est pas chargée), le jeu fonctionne en LOCAL
 * (localStorage) exactement comme avant — ce fichier ne fait alors rien.
 *
 * Pour activer (voir backend/README.md) :
 *   1) crée un projet Supabase (gratuit) ;
 *   2) exécute backend/schema.sql dans son éditeur SQL ;
 *   3) colle ci-dessous l'URL du projet et la clé "anon public".
 * La clé anon est conçue pour vivre dans le client ; la Row-Level Security
 * (RLS) garantit que chaque joueur n'accède qu'à sa propre sauvegarde.
 * ==========================================================================*/
(function () {
  "use strict";

  var SUPABASE_URL = "https://zfimirtznyjsvukpcoec.supabase.co";          // URL de base (sans /rest/v1/)
  var SUPABASE_ANON_KEY = "sb_publishable_j90seJWpkZU_uKWbGt9ZRg_rNfQ5ztf";

  var Cloud = { enabled: false, push: function () {}, init: function () {} };
  window.Cloud = Cloud;

  var configured = SUPABASE_URL.indexOf("http") === 0 && SUPABASE_ANON_KEY.length > 20;
  var libOK = typeof window.supabase !== "undefined" && !!window.supabase.createClient;
  if (!configured || !libOK) {
    if (configured && !libOK) console.warn("[Cloud] Supabase non chargé (hors-ligne ?) — mode local.");
    else console.info("[Cloud] non configuré — mode local (localStorage).");
    return;
  }

  Cloud.enabled = true;
  var sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  var bridge = null, user = null, lastPush = 0, pushTimer = null, msgEl = null;

  // --- API publique ------------------------------------------------------
  Cloud.init = function (gameBridge) {
    bridge = gameBridge;
    sb.auth.getSession().then(function (r) {
      var u = r.data && r.data.session ? r.data.session.user : null;
      setUser(u, true);
    });
    sb.auth.onAuthStateChange(function (event, session) {
      setUser(session ? session.user : null, event === "SIGNED_IN");
    });
  };

  Cloud.push = function (st) {
    if (!user) return;
    clearTimeout(pushTimer);
    var delay = Math.max(0, 8000 - (Date.now() - lastPush));   // throttle ~8 s
    pushTimer = setTimeout(function () {
      lastPush = Date.now();
      sb.from("saves").upsert({ user_id: user.id, state: st, updated_at: new Date().toISOString() })
        .then(function (r) { if (r.error) console.warn("[Cloud] push:", r.error.message); });
      // Phase B : on pousse aussi le score (production /s) pour le classement
      var score = bridge && bridge.getScore ? bridge.getScore() : 0;
      sb.from("scores").upsert({ user_id: user.id, display_name: getName(), net_worth: score, updated_at: new Date().toISOString() })
        .then(function (r) { if (r.error) console.warn("[Cloud] score:", r.error.message); });
    }, delay);
  };
  Cloud.topScores = function () {
    return sb.from("scores").select("display_name,net_worth").order("net_worth", { ascending: false }).limit(20);
  };

  // Pseudo affiché au classement (modifiable ; défaut = préfixe email)
  function getName() { return localStorage.getItem("dexCloudName") || (user && user.email ? user.email.split("@")[0] : "Joueur"); }
  function setName(n) { localStorage.setItem("dexCloudName", (n || "").slice(0, 20)); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function fmtN(n) { n = Number(n) || 0; if (n < 1000) return Math.floor(n).toString(); var u = ["", "k", "M", "B", "T", "Qa"], t = Math.min(Math.floor(Math.log10(n) / 3), u.length - 1); return (n / Math.pow(1000, t)).toFixed(2) + u[t]; }

  // --- Interne -----------------------------------------------------------
  function setUser(u, doPull) {
    user = u;
    renderUI();
    if (u && doPull && bridge) pullAndApply();
  }

  function pullAndApply() {
    sb.from("saves").select("state").eq("user_id", user.id).maybeSingle().then(function (r) {
      if (r.error) { say("Erreur de chargement : " + r.error.message); return; }
      var remote = r.data && r.data.state;
      var local = bridge.getState();
      if (!remote) { Cloud.push(local); say("Première sync : ta partie locale est sauvegardée."); return; }
      if ((remote.lastSeen || 0) >= (local.lastSeen || 0)) bridge.applyState(remote);   // le plus récent gagne
      else Cloud.push(local);
    });
  }

  // --- UI : un onglet ☁️ dans le menu + une modale ----------------------
  function injectUI() {
    var css = ""
      + ".cloudtab{display:inline-flex;align-items:center;background:#18342695;color:#eafff4;border:1px solid #2a4d3a;"
      + "border-radius:999px;padding:7px 12px;font-size:14px;cursor:pointer;touch-action:manipulation}"
      + ".cloudtab.on{border-color:#34d17a;color:#34d17a}"
      + ".cloud-ov{position:fixed;inset:0;background:rgba(0,0,0,.55);display:none;align-items:center;justify-content:center;z-index:200;padding:16px}"
      + ".cloud-ov.show{display:flex}"
      + ".cloud-card{background:#12281d;border:1px solid #1d3d2c;border-radius:16px;padding:20px;width:100%;max-width:360px;color:#eafff4}"
      + ".cloud-card h3{margin:0 0 4px;font-size:18px}.cloud-card p{color:#8fb7a3;font-size:13px;margin:0 0 14px}"
      + ".cloud-card input{width:100%;box-sizing:border-box;margin:6px 0;padding:10px;border-radius:8px;border:1px solid #2a4d3a;background:#18342695;color:#eafff4}"
      + ".cloud-card .row{display:flex;gap:8px;margin-top:8px}.cloud-card button{flex:1;padding:10px;border-radius:8px;border:1px solid #2a4d3a;background:#18342695;color:#eafff4;cursor:pointer}"
      + ".cloud-card button.primary{border-color:#ffd24d;color:#ffd24d}.cloud-msg{font-size:12px;color:#ffd24d;margin-top:10px;min-height:16px}"
      + ".cloud-board{margin-top:10px;max-height:220px;overflow:auto}"
      + ".cb-row{display:flex;justify-content:space-between;gap:10px;font-size:13px;padding:5px 2px;border-bottom:1px solid #1d3d2c}"
      + ".cloud-close{margin-top:12px;width:100%;opacity:.8}";
    var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

    var tabs = document.querySelector(".navtabs");
    var tab = document.createElement("button");
    tab.className = "cloudtab"; tab.id = "cloudTab"; tab.textContent = "☁️";
    tab.title = "Compte / sauvegarde cloud";
    if (tabs) tabs.appendChild(tab);

    var ov = document.createElement("div"); ov.className = "cloud-ov"; ov.id = "cloudOv";
    ov.innerHTML = '<div class="cloud-card" id="cloudCard"></div>';
    document.body.appendChild(ov);
    ov.addEventListener("click", function (e) { if (e.target === ov) ov.classList.remove("show"); });
    tab.addEventListener("click", function () { renderUI(); document.getElementById("cloudOv").classList.add("show"); });
  }

  function say(t) { if (msgEl) msgEl.textContent = t || ""; }

  function renderUI() {
    var tab = document.getElementById("cloudTab");
    if (tab) tab.classList.toggle("on", !!user);
    var card = document.getElementById("cloudCard");
    if (!card) return;
    if (user) {
      card.innerHTML =
        '<h3>☁️ Connecté</h3><p>' + esc(user.email || "compte") + '</p>' +
        '<input id="cName" placeholder="pseudo (classement)" maxlength="20" value="' + esc(getName()) + '">' +
        '<div class="row"><button class="primary" id="cSync">Synchroniser</button>' +
        '<button id="cBoard">🏆 Classement</button></div>' +
        '<div class="row"><button id="cOut">Déconnexion</button></div>' +
        '<div class="cloud-msg" id="cMsg"></div>' +
        '<div class="cloud-board" id="cBoardList"></div>' +
        '<button class="cloud-close" id="cClose">Fermer</button>';
      msgEl = card.querySelector("#cMsg");
      card.querySelector("#cName").onchange = function () { setName(this.value); say("Pseudo enregistré."); };
      card.querySelector("#cSync").onclick = function () { lastPush = 0; Cloud.push(bridge.getState()); say("Sauvegardé ✔"); };
      card.querySelector("#cOut").onclick = function () { sb.auth.signOut().then(function () { say("Déconnecté."); }); };
      card.querySelector("#cBoard").onclick = function () {
        say("Chargement du classement…");
        Cloud.topScores().then(function (r) {
          if (r.error) { say(r.error.message); return; }
          say("");
          var rows = r.data || [], el = card.querySelector("#cBoardList");
          el.innerHTML = rows.length
            ? rows.map(function (x, i) { return '<div class="cb-row"><span>' + (i + 1) + ". " + esc(x.display_name || "—") + '</span><span>' + fmtN(x.net_worth) + ' /s</span></div>'; }).join("")
            : '<div class="cb-row"><span>Aucun score encore</span></div>';
        });
      };
    } else {
      card.innerHTML =
        '<h3>Compte (cloud)</h3><p>Connecte-toi pour jouer sur plusieurs appareils. Sans compte, ta partie reste sur cet appareil.</p>' +
        '<input id="cEmail" type="email" placeholder="email" autocomplete="email">' +
        '<input id="cPwd" type="password" placeholder="mot de passe" autocomplete="current-password">' +
        '<div class="row"><button id="cIn" class="primary">Connexion</button><button id="cUp">Créer un compte</button></div>' +
        '<div class="cloud-msg" id="cMsg"></div>' +
        '<button class="cloud-close" id="cClose">Fermer</button>';
      msgEl = card.querySelector("#cMsg");
      var email = function () { return card.querySelector("#cEmail").value.trim(); };
      var pwd = function () { return card.querySelector("#cPwd").value; };
      card.querySelector("#cIn").onclick = function () {
        say("Connexion…");
        sb.auth.signInWithPassword({ email: email(), password: pwd() })
          .then(function (r) { say(r.error ? r.error.message : "Connecté ✔"); });
      };
      card.querySelector("#cUp").onclick = function () {
        say("Création…");
        sb.auth.signUp({ email: email(), password: pwd() })
          .then(function (r) { say(r.error ? r.error.message : "Compte créé ✔ (confirme ton email si demandé)"); });
      };
    }
    var close = card.querySelector("#cClose");
    if (close) close.onclick = function () { document.getElementById("cloudOv").classList.remove("show"); };
  }

  // ===== Phase C : Marché de gemmes =====================================
  Cloud.market = {
    wallet: function () { return sb.rpc("ensure_wallet"); },
    deposit: function (g, c) { return sb.rpc("deposit", { d_gems: g, d_cash: c }).then(function (r) { if (!r.error) { if (g) bridge.addGems(-g); if (c) bridge.addCash(-c); } return r; }); },
    withdraw: function (g, c) { return sb.rpc("withdraw", { w_gems: g, w_cash: c }).then(function (r) { if (!r.error) { if (g) bridge.addGems(g); if (c) bridge.addCash(c); } return r; }); },
    listings: function () { return sb.from("listings").select("id,seller,seller_name,gems,price").order("price", { ascending: true }); },
    create: function (g, p) { return sb.rpc("create_listing", { l_gems: g, l_price: p }); },
    cancel: function (id) { return sb.rpc("cancel_listing", { l_id: id }); },
    buy: function (id) { return sb.rpc("buy_listing", { l_id: id }); }
  };

  // --- API Exchange (nouveau marché sur le ledger L2-L4) --------------------
  Cloud.economy = {
    ticker:     function () { return sb.rpc("economy_get_ticker"); },
    orderbook:  function () { return sb.rpc("economy_orderbook"); },
    myBalances: function () { return sb.rpc("economy_my_balances"); },
    myOrders:   function () { return sb.rpc("economy_my_orders"); },
    deposit:    function (g, c) { return sb.rpc("economy_deposit", { d_gems: g, d_cash: c }).then(function (r) { if (r && r.data && r.data.success) { if (g) bridge.addGems(-g); if (c) bridge.addCash(-c); } return r; }); },
    withdraw:   function (g, c) { return sb.rpc("economy_withdraw", { w_gems: g, w_cash: c }).then(function (r) { if (r && r.data && r.data.success) { if (g) bridge.addGems(g); if (c) bridge.addCash(c); } return r; }); },
    place:      function (side, g, p) { return sb.rpc("economy_place_order", { p_side: side, p_gems: g, p_price: p }); },
    cancel:     function (id) { return sb.rpc("economy_cancel_order", { p_order_id: id }); }
  };

  // ===== EXCHANGE (Bloc 1 : en-tête ticker + carnet + buy/sell + dépôt) =====
  var XREG = {
    BULL:  ["🐂", "Haussier", "#22c197"], BEAR: ["🐻", "Baissier", "#e35d6a"],
    CRASH: ["💥", "Krach", "#e35d6a"],     CRABE:["🦀", "Plat", "#9fb0c3"],
    HYPE:  ["🚀", "Euphorie", "#22c197"]
  };
  var mkMsg = null, mkSide = "buy", mkBal = { gems: 0, cash: 0 }, mkPrice = 0;
  var mkRefresh = null, mkClock = null;
  function mkSay(t) { if (mkMsg) mkMsg.textContent = t || ""; }
  function fmtP(x) { x = Number(x) || 0; return x.toLocaleString("fr-FR", { maximumFractionDigits: 2 }); }
  function $id(i) { return document.getElementById(i); }

  function openMarket() {
    $id("mkOv").classList.add("show");
    renderMarket();
    if (mkRefresh) clearInterval(mkRefresh);
    mkRefresh = setInterval(renderMarket, 5000);
    if (mkClock) clearInterval(mkClock);
    tickClock(); mkClock = setInterval(tickClock, 1000);
  }
  function closeMarket() {
    $id("mkOv").classList.remove("show");
    if (mkRefresh) { clearInterval(mkRefresh); mkRefresh = null; }
    if (mkClock) { clearInterval(mkClock); mkClock = null; }
  }
  function tickClock() {
    var d = new Date(), p = function (n) { return (n < 10 ? "0" : "") + n; };
    var el = $id("xClock");
    if (el) el.textContent = p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + ":" + p(d.getUTCSeconds()) + " UTC";
  }

  function mkAvail() {
    var p = parseFloat($id("xPriceIn").value) || mkPrice || 0;
    if (mkSide === "buy") return p > 0 ? Math.floor((mkBal.cash || 0) / p) : 0;
    return Math.floor(mkBal.gems || 0);
  }
  function syncTotal() {
    var g = parseFloat($id("xAmtIn").value) || 0, p = parseFloat($id("xPriceIn").value) || 0;
    $id("xTotal").textContent = fmtP(g * p);
  }
  function setAmtFromPct(pct) {
    var amt = Math.floor(mkAvail() * pct / 100);
    $id("xAmtIn").value = amt || 0;
    $id("xSlider").value = pct;
    syncTotal();
  }
  function syncSliderFromAmt() {
    var av = mkAvail(), g = parseFloat($id("xAmtIn").value) || 0;
    $id("xSlider").value = av > 0 ? Math.min(100, Math.round(g / av * 100)) : 0;
    syncTotal();
  }

  function renderMarket() {
    // Ticker
    Cloud.economy.ticker().then(function (r) {
      var t = (r && r.data) || {};
      mkPrice = Number(t.price) || 0;
      if ($id("xPrice")) $id("xPrice").textContent = mkPrice ? fmtP(mkPrice) : "—";
      var chg = Number(t.change_pct) || 0, up = chg >= 0;
      var ce = $id("xChg");
      if (ce) { ce.textContent = (up ? "▲ +" : "▼ ") + fmtP(chg) + " %"; ce.style.color = up ? "#22c197" : "#e35d6a"; }
      var rg = XREG[t.regime] || XREG.CRABE, re = $id("xReg");
      if (re) { re.textContent = rg[0] + " " + rg[1]; re.style.color = rg[2]; }
      if ($id("xHL")) $id("xHL").textContent = "H " + fmtP(t.high) + "  ·  B " + fmtP(t.low);
      if (!$id("xPriceIn").value && mkPrice) $id("xPriceIn").value = mkPrice;
    });
    // Carnet
    Cloud.economy.orderbook().then(function (r) {
      var ob = (r && r.data) || { bids: [], asks: [] };
      var bids = ob.bids || [], asks = ob.asks || [];
      var maxQ = 1;
      bids.concat(asks).forEach(function (o) { maxQ = Math.max(maxQ, Number(o.gems) || 0); });
      function row(o, cls) {
        var q = Number(o.gems) || 0, w = Math.round(q / maxQ * 100);
        return '<div class="xrow ' + cls + '"><span class="xbar" style="width:' + w + '%"></span>'
          + '<span class="xp">' + fmtP(o.price) + '</span><span class="xq">' + fmtN(q) + '</span></div>';
      }
      var asksHtml = asks.slice().reverse().map(function (o) { return row(o, "ask"); }).join("") || '<div class="xempty">—</div>';
      var bidsHtml = bids.map(function (o) { return row(o, "bid"); }).join("") || '<div class="xempty">—</div>';
      if ($id("xAsks")) $id("xAsks").innerHTML = asksHtml;
      if ($id("xBids")) $id("xBids").innerHTML = bidsHtml;
      if ($id("xMid")) $id("xMid").textContent = mkPrice ? fmtP(mkPrice) : "—";
      // Pression acheteurs / vendeurs
      var sb_ = 0, ss = 0;
      bids.forEach(function (o) { sb_ += Number(o.gems) || 0; });
      asks.forEach(function (o) { ss += Number(o.gems) || 0; });
      var tot = sb_ + ss, pb = tot ? Math.round(sb_ / tot * 100) : 50;
      if ($id("xPbuy")) { $id("xPbuy").style.width = pb + "%"; $id("xPsell").style.width = (100 - pb) + "%"; }
      if ($id("xPbl")) { $id("xPbl").textContent = pb + "% ach."; $id("xPsl").textContent = (100 - pb) + "% vend."; }
    });
    // Soldes + ordres (si connecté)
    if (user) {
      Cloud.economy.myBalances().then(function (r) {
        mkBal = (r && r.data) || { gems: 0, cash: 0 };
        if ($id("xAvbl")) $id("xAvbl").innerHTML = "Dispo marché : 💎<b>" + fmtN(mkBal.gems) + "</b> · $<b>" + fmtN(mkBal.cash) + "</b>";
      });
      Cloud.economy.myOrders().then(function (r) {
        var rows = (r && r.data) || [], el = $id("xMyOrders"); if (!el) return;
        if (!rows.length) { el.innerHTML = '<div class="xempty">Aucun ordre ouvert</div>'; return; }
        el.innerHTML = rows.map(function (o) {
          var s = o.side === "buy" ? "Achat" : "Vente";
          return '<div class="xord"><span class="' + o.side + '">' + s + ' 💎' + fmtN(o.gems_remaining) + ' @ $' + fmtP(o.price) + '</span>'
            + '<button data-cancel="' + o.id + '">Annuler</button></div>';
        }).join("");
        el.querySelectorAll("[data-cancel]").forEach(function (b) {
          b.onclick = function () { Cloud.economy.cancel(b.getAttribute("data-cancel")).then(function (rr) { mkSay(rr && rr.data && rr.data.success ? "Ordre annulé." : "Erreur."); renderMarket(); }); };
        });
      });
    } else {
      if ($id("xAvbl")) $id("xAvbl").textContent = "Connecte-toi pour trader.";
      if ($id("xMyOrders")) $id("xMyOrders").innerHTML = '<div class="xempty">—</div>';
    }
  }

  function setSide(side) {
    mkSide = side;
    $id("xBuyTab").classList.toggle("on", side === "buy");
    $id("xSellTab").classList.toggle("on", side === "sell");
    var go = $id("xGo");
    go.textContent = side === "buy" ? "Acheter 💎" : "Vendre 💎";
    go.className = "xch-go " + side;
    setAmtFromPct(0);
  }

  function injectMarketUI() {
    var css = ""
      + ".mk-ov{position:fixed;inset:0;background:rgba(0,0,0,.72);display:none;align-items:flex-start;justify-content:center;z-index:210;padding:10px;overflow:auto}"
      + ".mk-ov.show{display:flex}"
      + ".xch{background:#0e1722;border:1px solid #1d2a3a;border-radius:16px;padding:14px;width:100%;max-width:460px;color:#e9eef5;margin:auto;font-size:14px}"
      + ".xch-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}"
      + ".xch-pair{font-weight:700;font-size:17px}.xch-pair span{color:#7d8ba0;font-weight:500;font-size:13px}"
      + ".xch-clock{font-variant-numeric:tabular-nums;color:#9fb0c3;font-size:12px;background:#16212f;border:1px solid #243246;border-radius:8px;padding:4px 8px}"
      + ".xch-tick{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}"
      + ".xch-price{font-size:26px;font-weight:700;font-variant-numeric:tabular-nums}"
      + ".xch-chg{font-weight:600}.xch-reg{margin-left:auto;font-weight:600}"
      + ".xch-hl{color:#7d8ba0;font-size:12px;margin:2px 0 10px}"
      + ".xch-book{background:#111a26;border:1px solid #1d2a3a;border-radius:12px;padding:8px;margin-bottom:10px}"
      + ".xch-bookhead{display:flex;justify-content:space-between;color:#7d8ba0;font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px;padding:0 4px}"
      + ".xrow{position:relative;display:flex;justify-content:space-between;padding:2px 4px;font-variant-numeric:tabular-nums;font-size:13px;overflow:hidden;border-radius:4px}"
      + ".xrow .xbar{position:absolute;top:0;bottom:0;right:0;opacity:.16}"
      + ".xrow.ask .xbar{background:#e35d6a}.xrow.bid .xbar{background:#22c197}"
      + ".xrow .xp{position:relative;z-index:1}.xrow.ask .xp{color:#e35d6a}.xrow.bid .xp{color:#22c197}"
      + ".xrow .xq{position:relative;z-index:1;color:#cdd6e2}"
      + ".xch-mid{text-align:center;font-size:18px;font-weight:700;font-variant-numeric:tabular-nums;padding:5px 0;color:#e9eef5}"
      + ".xempty{text-align:center;color:#5e6b7e;padding:6px;font-size:12px}"
      + ".xch-press{display:flex;height:6px;border-radius:4px;overflow:hidden;margin-top:6px;background:#1d2a3a}"
      + ".xch-press-buy{background:#22c197}.xch-press-sell{background:#e35d6a}"
      + ".xch-presslabel{display:flex;justify-content:space-between;font-size:11px;margin-top:3px}.xch-presslabel span:first-child{color:#22c197}.xch-presslabel span:last-child{color:#e35d6a}"
      + ".xch-toggle{display:flex;gap:6px;margin-bottom:8px}"
      + ".xch-toggle button{flex:1;padding:9px;border-radius:8px;border:1px solid #243246;background:#16212f;color:#9fb0c3;font-weight:600;cursor:pointer}"
      + ".xch-toggle button.on{color:#fff}#xBuyTab.on{background:#1c7a5e;border-color:#22c197}#xSellTab.on{background:#8a3b44;border-color:#e35d6a}"
      + ".xch-l{display:block;color:#7d8ba0;font-size:11px;margin:6px 0 3px}"
      + ".xch input[type=number]{width:100%;box-sizing:border-box;padding:9px;border-radius:8px;border:1px solid #243246;background:#0b131d;color:#e9eef5;font-size:15px;font-variant-numeric:tabular-nums}"
      + ".xch input[type=range]{width:100%;margin:8px 0}"
      + ".xch-presets{display:flex;gap:6px;margin-bottom:6px}.xch-presets button{flex:1;padding:6px;border-radius:7px;border:1px solid #243246;background:#16212f;color:#9fb0c3;font-size:12px;cursor:pointer}"
      + ".xch-total{font-size:13px;color:#cdd6e2;margin:2px 0}.xch-total b{color:#ffd24d}"
      + ".xch-avbl{font-size:12px;color:#9fb0c3;margin-bottom:8px}.xch-avbl b{color:#e9eef5}"
      + ".xch-go{width:100%;padding:12px;border-radius:10px;border:none;font-weight:700;font-size:15px;cursor:pointer;color:#fff}.xch-go.buy{background:#22c197}.xch-go.sell{background:#e35d6a}"
      + ".xch-sub{color:#7d8ba0;font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin:14px 0 6px}"
      + ".xch-row{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.xch-row input{flex:1;min-width:70px}"
      + ".xch-row button{padding:9px 12px;border-radius:8px;border:1px solid #243246;background:#16212f;color:#e9eef5;cursor:pointer}"
      + ".xch-orders{max-height:140px;overflow:auto}.xord{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:13px;border-bottom:1px solid #1d2a3a;padding:6px 2px}"
      + ".xord .buy{color:#22c197}.xord .sell{color:#e35d6a}.xord button{padding:4px 9px;border-radius:7px;border:1px solid #243246;background:#16212f;color:#9fb0c3;cursor:pointer;font-size:12px}"
      + ".xch-msg{font-size:12px;color:#ffd24d;min-height:16px;margin-top:8px}.xch-close{margin-top:10px;width:100%;padding:10px;border-radius:9px;border:1px solid #243246;background:#16212f;color:#9fb0c3;cursor:pointer}";
    var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

    var ov = document.createElement("div"); ov.className = "mk-ov"; ov.id = "mkOv";
    ov.innerHTML = '<div class="xch">'
      + '<div class="xch-head"><div class="xch-pair">💎 GEMS <span>/ $ CASH</span></div><div class="xch-clock" id="xClock">--:--:-- UTC</div></div>'
      + '<div class="xch-tick"><div class="xch-price" id="xPrice">—</div><div class="xch-chg" id="xChg">—</div><div class="xch-reg" id="xReg">🦀 Plat</div></div>'
      + '<div class="xch-hl" id="xHL">H — · B —</div>'
      + '<div class="xch-book"><div class="xch-bookhead"><span>Prix ($)</span><span>Qté 💎</span></div>'
      + '<div id="xAsks"></div><div class="xch-mid" id="xMid">—</div><div id="xBids"></div>'
      + '<div class="xch-press"><div class="xch-press-buy" id="xPbuy" style="width:50%"></div><div class="xch-press-sell" id="xPsell" style="width:50%"></div></div>'
      + '<div class="xch-presslabel"><span id="xPbl">—</span><span id="xPsl">—</span></div></div>'
      + '<div class="xch-toggle"><button id="xBuyTab" class="on">Acheter</button><button id="xSellTab">Vendre</button></div>'
      + '<label class="xch-l">Prix ($ / 💎)</label><input id="xPriceIn" type="number" min="0" step="0.01">'
      + '<label class="xch-l">Quantité 💎</label><input id="xAmtIn" type="number" min="0" placeholder="0">'
      + '<input id="xSlider" type="range" min="0" max="100" value="0">'
      + '<div class="xch-presets"><button data-pct="25">25%</button><button data-pct="50">50%</button><button data-pct="75">75%</button><button data-pct="100">Max</button></div>'
      + '<div class="xch-total">Total : $<b id="xTotal">0</b></div>'
      + '<div class="xch-avbl" id="xAvbl">…</div>'
      + '<button class="xch-go buy" id="xGo">Acheter 💎</button>'
      + '<div class="xch-sub">Jeu ⇄ Marché</div>'
      + '<div class="xch-row">💎<input id="xMg" type="number" min="0" placeholder="gemmes"> $<input id="xMc" type="number" min="0" placeholder="cash">'
      + '<button id="xDep">Déposer</button><button id="xWit">Retirer</button></div>'
      + '<div class="xch-sub">Mes ordres</div><div class="xch-orders" id="xMyOrders">…</div>'
      + '<div class="xch-msg" id="xMsg"></div>'
      + '<button class="xch-close" id="xClose">Fermer</button></div>';
    document.body.appendChild(ov);
    ov.addEventListener("click", function (e) { if (e.target === ov) closeMarket(); });
    mkMsg = ov.querySelector("#xMsg");
    ov.querySelector("#xClose").onclick = closeMarket;

    // Onglet 🏦 dans le menu du haut
    var tabs = document.querySelector(".navtabs");
    if (tabs) {
      var mtab = document.createElement("button");
      mtab.className = "cloudtab"; mtab.id = "marketTab"; mtab.textContent = "🏦";
      mtab.title = "Bourse aux gemmes";
      mtab.addEventListener("click", openMarket);   // visible même déconnecté (lecture)
      var cloudTab = $id("cloudTab");
      if (cloudTab) tabs.insertBefore(mtab, cloudTab); else tabs.appendChild(mtab);
    }

    // Handlers buy/sell
    ov.querySelector("#xBuyTab").onclick = function () { setSide("buy"); };
    ov.querySelector("#xSellTab").onclick = function () { setSide("sell"); };
    ov.querySelector("#xSlider").oninput = function () { setAmtFromPct(parseInt(this.value, 10) || 0); };
    ov.querySelector("#xAmtIn").oninput = syncSliderFromAmt;
    ov.querySelector("#xPriceIn").oninput = function () { syncSliderFromAmt(); };
    ov.querySelectorAll(".xch-presets button").forEach(function (b) {
      b.onclick = function () { setAmtFromPct(parseInt(b.getAttribute("data-pct"), 10)); };
    });
    ov.querySelector("#xGo").onclick = function () {
      if (!user) { mkSay("Connecte-toi pour trader."); return; }
      var g = Math.floor(parseFloat($id("xAmtIn").value) || 0), p = parseFloat($id("xPriceIn").value) || 0;
      if (!g || !p) { mkSay("Quantité et prix requis."); return; }
      Cloud.economy.place(mkSide, g, p).then(function (r) {
        if (r && r.data && r.data.success) { mkSay(mkSide === "buy" ? "Ordre d'achat placé ✔" : "Ordre de vente placé ✔"); $id("xAmtIn").value = ""; $id("xSlider").value = 0; syncTotal(); }
        else { mkSay((r && r.data && r.data.error) || (r && r.error && r.error.message) || "Erreur."); }
        renderMarket();
      });
    };
    // Dépôt / retrait (jeu <-> marché)
    ov.querySelector("#xDep").onclick = function () {
      if (!user) { mkSay("Connecte-toi d'abord."); return; }
      var g = Math.floor(parseFloat($id("xMg").value) || 0), c = Math.floor(parseFloat($id("xMc").value) || 0), s = bridge.getState();
      if (!g && !c) { mkSay("Indique un montant."); return; }
      if (g > (s.gems || 0) || c > (s.cash || 0)) { mkSay("Pas assez dans le jeu."); return; }
      Cloud.economy.deposit(g, c).then(function (r) { mkSay(r && r.data && r.data.success ? "Déposé ✔" : ((r && r.data && r.data.error) || "Erreur.")); $id("xMg").value = ""; $id("xMc").value = ""; renderMarket(); });
    };
    ov.querySelector("#xWit").onclick = function () {
      if (!user) { mkSay("Connecte-toi d'abord."); return; }
      var g = Math.floor(parseFloat($id("xMg").value) || 0), c = Math.floor(parseFloat($id("xMc").value) || 0);
      if (!g && !c) { mkSay("Indique un montant."); return; }
      Cloud.economy.withdraw(g, c).then(function (r) { mkSay(r && r.data && r.data.success ? "Retiré ✔" : ((r && r.data && r.data.error) || "Solde marché insuffisant.")); $id("xMg").value = ""; $id("xMc").value = ""; renderMarket(); });
    };
  }

  injectUI();
  injectMarketUI();
})();
