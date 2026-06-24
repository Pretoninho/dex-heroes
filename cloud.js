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

  var Cloud = { enabled: false, push: function () {}, init: function () {}, marketOpen: function () {}, marketClose: function () {} };
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
  var bridge = null, user = null, lastPush = 0, pushTimer = null, msgEl = null, pulling = false;

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
    if (!user || pulling) return;   // ne pousse pas pendant le chargement d'un compte (anti-écrasement)
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
  // Pousse le pseudo vers le cloud (table scores) pour qu'il suive le compte.
  function pushName() {
    if (!user) return;
    var score = bridge && bridge.getScore ? bridge.getScore() : 0;
    sb.from("scores").upsert({ user_id: user.id, display_name: getName(), net_worth: score, updated_at: new Date().toISOString() })
      .then(function (r) { if (r.error) console.warn("[Cloud] name:", r.error.message); });
  }
  // Charge le pseudo du compte depuis le cloud à la connexion (suit le compte, multi-appareils).
  function loadCloudName(uid) {
    sb.from("scores").select("display_name").eq("user_id", uid).maybeSingle().then(function (r) {
      var nm = r.data && r.data.display_name;
      if (nm) {
        localStorage.setItem("dexCloudName", nm);
        var inp = document.getElementById("cName");
        if (inp && document.activeElement !== inp) inp.value = nm;
      }
    });
  }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function fmtN(n) { n = Number(n) || 0; if (n < 1000) return Math.floor(n).toString(); var u = ["", "k", "M", "B", "T", "Qa"], t = Math.min(Math.floor(Math.log10(n) / 3), u.length - 1); return (n / Math.pow(1000, t)).toFixed(2) + u[t]; }

  // --- Interne -----------------------------------------------------------
  function setUser(u, doPull) {
    if (pushTimer) { clearTimeout(pushTimer); pushTimer = null; }   // annule un push en attente → n'écrit pas vers le mauvais compte
    user = u;
    renderUI();
    if (u && doPull && bridge) pullAndApply();
  }

  // Quel compte possède la partie locale actuellement en mémoire (localStorage partagé entre comptes).
  function localOwner() { return localStorage.getItem("dexCloudOwner"); }
  function setLocalOwner(uid) { localStorage.setItem("dexCloudOwner", uid); }

  function pullAndApply() {
    var uid = user.id, owner = localOwner();
    loadCloudName(uid);   // récupère le pseudo du compte (suit le compte)
    pulling = true;   // gèle les push automatiques le temps du chargement
    sb.from("saves").select("state").eq("user_id", uid).maybeSingle().then(function (r) {
      if (r.error) { pulling = false; say("Erreur de chargement : " + r.error.message); return; }
      var remote = r.data && r.data.state;
      var local = bridge.getState();
      var sameOwner = (owner === uid);

      if (remote) {
        // Compte existant. Même compte/appareil → le plus récent gagne.
        // Changement de compte (owner différent) → on charge le cloud sans discuter.
        if (sameOwner && (local.lastSeen || 0) > (remote.lastSeen || 0)) { setLocalOwner(uid); pulling = false; Cloud.push(local); }
        else { bridge.applyState(remote); setLocalOwner(uid); pulling = false; }
        return;
      }

      // Aucune sauvegarde distante pour CE compte.
      setLocalOwner(uid);
      if (owner && owner !== uid && bridge.resetState) {
        // La partie locale appartient à un AUTRE compte → on repart à neuf pour celui-ci.
        bridge.resetState();
        pulling = false;
        Cloud.push(bridge.getState());
        say("Nouveau compte : nouvelle partie.");
      } else {
        // Première sync d'un joueur jusque-là anonyme → on adopte la partie locale.
        pulling = false;
        Cloud.push(local);
        say("Première sync : ta partie locale est sauvegardée.");
      }
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
      card.querySelector("#cName").oninput = function () { setName(this.value); };
      card.querySelector("#cName").onchange = function () { setName(this.value); this.value = getName(); pushName(); this.blur(); say("Pseudo « " + getName() + " » enregistré ✔"); };
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
    fees:       function () { return sb.rpc("economy_get_fees"); },
    history:    function () { return sb.from("economy_price_history").select("price,captured_at").order("captured_at", { ascending: false }).limit(1500); },
    deposit:    function (g, c) { return sb.rpc("economy_deposit", { d_gems: g, d_cash: c }).then(function (r) { if (r && r.data && r.data.success) { if (g) bridge.addGems(-g); if (c) bridge.addCash(-c); } return r; }); },
    withdraw:   function (g, c) { return sb.rpc("economy_withdraw", { w_gems: g, w_cash: c }).then(function (r) { if (r && r.data && r.data.success) { var ng = r.data.net_gems != null ? r.data.net_gems : g, nc = r.data.net_cash != null ? r.data.net_cash : c; if (ng) bridge.addGems(ng); if (nc) bridge.addCash(nc); } return r; }); },
    place:      function (side, g, p) { return sb.rpc("economy_place_order", { p_side: side, p_gems: g, p_price: p }); },
    market:     function (side, g) { return sb.rpc("economy_market_order", { p_side: side, p_gems: g }); },
    cancel:     function (id) { return sb.rpc("economy_cancel_order", { p_order_id: id }); },
    amend:      function (id, g, p) { return sb.rpc("economy_amend_order", { p_order_id: id, p_gems: g, p_price: p }); }
  };

  // ===== EXCHANGE (Bloc 1 : en-tête ticker + carnet + buy/sell + dépôt) =====
  var XREG = {
    BULL:  ["🐂", "Haussier", "#22c197"], BEAR: ["🐻", "Baissier", "#e35d6a"],
    CRASH: ["💥", "Krach", "#e35d6a"],     CRABE:["🦀", "Plat", "#9fb0c3"],
    HYPE:  ["🚀", "Euphorie", "#22c197"]
  };
  var mkMsg = null, mkSide = "buy", mkType = "limit", mkBal = { gems: 0, cash: 0 }, mkPrice = 0;
  var mkRefresh = null, mkEditing = false, mkTF = 15;   // minutes par bougie
  function mkSay(t) { if (mkMsg) mkMsg.textContent = t || ""; }
  function fmtP(x) { x = Number(x) || 0; return x.toLocaleString("fr-FR", { maximumFractionDigits: 2 }); }
  function $id(i) { return document.getElementById(i); }

  Cloud.marketOpen = function () {
    if (!document.getElementById("xPrice")) return;   // UI pas encore montée
    renderMarket();
    Cloud.economy.fees().then(function (r) {
      var f = (r && r.data) || {}, el = document.getElementById("xFees"); if (!el) return;
      var pct = function (x) { return (Number(x) * 100).toLocaleString("fr-FR", { maximumFractionDigits: 3 }) + " %"; };
      el.textContent = "Frais : maker " + pct(f.maker || 0.001) + " · taker " + pct(f.taker || 0.002) + " · retrait " + pct(f.withdraw || 0.005);
    });
    if (mkRefresh) clearInterval(mkRefresh);
    mkRefresh = setInterval(renderMarket, 5000);
  };
  Cloud.marketClose = function () {
    if (mkRefresh) { clearInterval(mkRefresh); mkRefresh = null; }
  };

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

  // Graphique en chandeliers, 2 axes (prix à droite, temps en bas) + timeframe
  function renderChart() {
    var el = document.getElementById("xChart"); if (!el) return;
    Cloud.economy.history().then(function (r) {
      var rows = (r && r.data) || [];
      var data = rows.slice().reverse()
        .map(function (x) { return { p: Number(x.price) || 0, t: new Date(x.captured_at) }; })
        .filter(function (d) { return d.p > 0; });
      if (data.length < 2) { el.innerHTML = '<div class="xempty">Pas encore d\'historique — le marché démarre (1 point/minute).</div>'; return; }

      // Regrouper en bougies selon le timeframe (1 point ≈ 1 min)
      var per = mkTF, candles = [];
      for (var i = 0; i < data.length; i += per) {
        var seg = data.slice(i, i + per); if (!seg.length) continue;
        var pr = seg.map(function (d) { return d.p; });
        candles.push({ o: pr[0], c: pr[pr.length - 1], hi: Math.max.apply(null, pr), lo: Math.min.apply(null, pr), t: seg[0].t });
      }
      var maxC = 48; if (candles.length > maxC) candles = candles.slice(candles.length - maxC);

      var W = el.clientWidth || 320, H = 200, mT = 6, mR = 54, mB = 18, mL = 4;
      var pw = W - mL - mR, ph = H - mT - mB;
      var hi = Math.max.apply(null, candles.map(function (k) { return k.hi; }));
      var lo = Math.min.apply(null, candles.map(function (k) { return k.lo; }));
      var pad = (hi - lo) * 0.08 || hi * 0.02 || 1; hi += pad; lo -= pad;
      var py = function (p) { return mT + (1 - (p - lo) / (hi - lo)) * ph; };
      var cw = pw / candles.length;
      var tl = function (d) { var z = function (n) { return (n < 10 ? "0" : "") + n; }; return z(d.getUTCDate()) + "/" + z(d.getUTCMonth() + 1) + " " + z(d.getUTCHours()) + ":" + z(d.getUTCMinutes()); };

      var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" height="' + H + '">';
      // Axe Y : grille + prix à droite
      for (var g = 0; g <= 4; g++) {
        var pv = lo + (hi - lo) * g / 4, yy = py(pv).toFixed(1);
        svg += '<line x1="' + mL + '" x2="' + (mL + pw) + '" y1="' + yy + '" y2="' + yy + '" stroke="#1d3d2c" stroke-width="1"/>';
        svg += '<text x="' + (W - mR + 5) + '" y="' + (parseFloat(yy) + 3).toFixed(1) + '" fill="#8fb7a3" font-size="10">' + fmtP(pv) + '</text>';
      }
      // Bougies
      candles.forEach(function (k, i) {
        var cx = mL + i * cw + cw / 2, up = k.c >= k.o, col = up ? "#34d17a" : "#e06b6b", bw = Math.max(1.5, cw * 0.6);
        var yo = py(k.o), yc = py(k.c), top = Math.min(yo, yc), bh = Math.max(1, Math.abs(yc - yo));
        svg += '<line x1="' + cx.toFixed(1) + '" x2="' + cx.toFixed(1) + '" y1="' + py(k.hi).toFixed(1) + '" y2="' + py(k.lo).toFixed(1) + '" stroke="' + col + '" stroke-width="1"/>';
        svg += '<rect x="' + (cx - bw / 2).toFixed(1) + '" y="' + top.toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + bh.toFixed(1) + '" fill="' + col + '"/>';
      });
      // Axe X : quelques horodatages
      [0, Math.floor(candles.length / 2), candles.length - 1].forEach(function (idx, j) {
        if (idx < 0 || idx >= candles.length) return;
        var cx = mL + idx * cw + cw / 2, anc = j === 0 ? "start" : (j === 2 ? "end" : "middle");
        svg += '<text x="' + cx.toFixed(1) + '" y="' + (H - 5) + '" fill="#8fb7a3" font-size="10" text-anchor="' + anc + '">' + tl(candles[idx].t) + '</text>';
      });
      svg += '</svg>';
      el.innerHTML = svg;
    }).catch(function () {});
  }

  function renderMarket() {
    renderChart();
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
        if (mkEditing) return;   // ne pas écraser une édition en cours
        var rows = (r && r.data) || [], el = $id("xMyOrders"); if (!el) return;
        if (!rows.length) { el.innerHTML = '<div class="xempty">Aucun ordre ouvert</div>'; return; }
        el.innerHTML = rows.map(function (o) {
          var s = o.side === "buy" ? "Achat" : "Vente";
          return '<div class="xord" data-id="' + o.id + '">'
            + '<span class="xord-view ' + o.side + '">' + s + ' 💎' + fmtN(o.gems_remaining) + ' @ $' + fmtP(o.price) + '</span>'
            + '<span class="xord-act"><button data-edit="' + o.id + '" data-gems="' + o.gems_remaining + '" data-price="' + o.price + '">Modifier</button>'
            + '<button data-cancel="' + o.id + '">Annuler</button></span></div>';
        }).join("");
        el.querySelectorAll("[data-cancel]").forEach(function (b) {
          b.onclick = function () { Cloud.economy.cancel(b.getAttribute("data-cancel")).then(function (rr) { mkSay(rr && rr.data && rr.data.success ? "Ordre annulé." : "Erreur."); renderMarket(); }); };
        });
        el.querySelectorAll("[data-edit]").forEach(function (b) {
          b.onclick = function () { startEditOrder(b.getAttribute("data-edit"), b.getAttribute("data-gems"), b.getAttribute("data-price")); };
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
  // Type d'ordre : Limite (prix saisi) ou Market (au meilleur prix du carnet)
  function setType(t) {
    mkType = t;
    $id("xTypeLimit").classList.toggle("on", t === "limit");
    $id("xTypeMarket").classList.toggle("on", t === "market");
    var isMkt = t === "market";
    $id("xPriceIn").style.display = isMkt ? "none" : "";
    $id("xPriceLbl").style.display = isMkt ? "none" : "";
    syncSliderFromAmt();
  }

  // Édition en ligne d'un ordre (annuler + replacer atomique côté serveur)
  function startEditOrder(id, gems, price) {
    mkEditing = true;
    var row = document.querySelector('.xord[data-id="' + id + '"]'); if (!row) { mkEditing = false; return; }
    row.innerHTML = '<span class="xord-edit">$<input class="xeP" type="number" min="0" step="0.01" value="' + price + '">'
      + '💎<input class="xeG" type="number" min="0" value="' + Math.floor(gems) + '"></span>'
      + '<span class="xord-act"><button class="xeOk">✓</button><button class="xeNo">✗</button></span>';
    row.querySelector(".xeNo").onclick = function () { mkEditing = false; renderMarket(); };
    row.querySelector(".xeOk").onclick = function () {
      var p = parseFloat(row.querySelector(".xeP").value) || 0, g = Math.floor(parseFloat(row.querySelector(".xeG").value) || 0);
      if (!p || !g) { mkSay("Prix et quantité requis."); return; }
      mkEditing = false;
      Cloud.economy.amend(id, g, p).then(function (rr) {
        if (rr && rr.data && rr.data.success) mkSay("Ordre modifié ✔");
        else mkSay((rr && rr.error && rr.error.message) || (rr && rr.data && rr.data.error) || "Modification refusée.");
        renderMarket();
      });
    };
  }

  function injectMarketUI() {
    var container = document.getElementById("marketScreen");
    if (!container) return;   // index.html sans l'écran marché

    var css = ""
      + ".xch{font-size:14px;color:var(--text)}"
      + ".xch-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}"
      + ".xch-pair{font-weight:700;font-size:18px}.xch-pair span{color:var(--muted);font-weight:500;font-size:13px}"
      + ".xch-clock{font-variant-numeric:tabular-nums;color:var(--muted);font-size:12px;background:var(--panel-2);border:1px solid #2a4d3a;border-radius:8px;padding:4px 8px}"
      + ".xch-tick{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}"
      + ".xch-price{font-size:28px;font-weight:700;font-variant-numeric:tabular-nums}"
      + ".xch-chg{font-weight:600}.xch-reg{margin-left:auto;font-weight:600}"
      + ".xch-hl{color:var(--muted);font-size:12px;margin:2px 0 12px}"
      + ".xch-tf{display:flex;gap:6px;margin-bottom:6px}.xch-tf button{padding:4px 12px;border-radius:7px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--muted);font-size:12px;cursor:pointer}.xch-tf button.on{color:var(--text);border-color:var(--accent-2)}"
      + ".xch-chart{background:var(--bg);border:1px solid #1d3d2c;border-radius:12px;padding:6px;margin-bottom:12px}"
      + ".xch-chart svg{display:block;width:100%}"
      + ".xch-body{display:flex;flex-direction:column;gap:14px}"
      + "@media(min-width:640px){.xch-body{display:grid;grid-template-columns:1fr 1fr;align-items:start}}"
      + ".xch-book{background:var(--bg);border:1px solid #1d3d2c;border-radius:12px;padding:8px}"
      + ".xch-bookhead{display:flex;justify-content:space-between;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px;padding:0 4px}"
      + ".xrow{position:relative;display:flex;justify-content:space-between;padding:3px 4px;font-variant-numeric:tabular-nums;font-size:13px;overflow:hidden;border-radius:4px}"
      + ".xrow .xbar{position:absolute;top:0;bottom:0;right:0;opacity:.18}"
      + ".xrow.ask .xbar{background:#e06b6b}.xrow.bid .xbar{background:var(--accent)}"
      + ".xrow .xp{position:relative;z-index:1}.xrow.ask .xp{color:#e06b6b}.xrow.bid .xp{color:var(--accent)}"
      + ".xrow .xq{position:relative;z-index:1;color:#cfe9db}"
      + ".xch-mid{text-align:center;font-size:18px;font-weight:700;font-variant-numeric:tabular-nums;padding:6px 0;color:var(--accent-2)}"
      + ".xempty{text-align:center;color:var(--muted);padding:6px;font-size:12px;opacity:.7}"
      + ".xch-press{display:flex;height:6px;border-radius:4px;overflow:hidden;margin-top:6px;background:#1d3d2c}"
      + ".xch-press-buy{background:var(--accent)}.xch-press-sell{background:#e06b6b}"
      + ".xch-presslabel{display:flex;justify-content:space-between;font-size:11px;margin-top:3px}.xch-presslabel span:first-child{color:var(--accent)}.xch-presslabel span:last-child{color:#e06b6b}"
      + ".xch-toggle{display:flex;gap:6px;margin-bottom:8px}"
      + ".xch-toggle button{flex:1;padding:10px;border-radius:8px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--muted);font-weight:600;cursor:pointer}"
      + ".xch-toggle button.on{color:#fff}#xBuyTab.on{background:#1c7a4e;border-color:var(--accent)}#xSellTab.on{background:#7a2f37;border-color:#e06b6b}"
      + ".xch-type{display:flex;gap:6px;margin-bottom:8px}.xch-type button{flex:1;padding:7px;border-radius:8px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--muted);font-size:13px;cursor:pointer}.xch-type button.on{color:var(--text);border-color:var(--accent-2)}"
      + ".xch-l{display:block;color:var(--muted);font-size:11px;margin:6px 0 3px}"
      + ".xch input[type=number]{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #2a4d3a;background:var(--bg);color:var(--text);font-size:15px;font-variant-numeric:tabular-nums}"
      + ".xch input[type=range]{width:100%;margin:8px 0;accent-color:var(--accent)}"
      + ".xch-presets{display:flex;gap:6px;margin-bottom:6px}.xch-presets button{flex:1;padding:7px;border-radius:7px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--muted);font-size:12px;cursor:pointer}"
      + ".xch-total{font-size:13px;color:#cfe9db;margin:2px 0}.xch-total b{color:var(--accent-2)}"
      + ".xch-avbl{font-size:12px;color:var(--muted);margin-bottom:8px}.xch-avbl b{color:var(--text)}"
      + ".xch-go{width:100%;padding:13px;border-radius:10px;border:none;font-weight:700;font-size:15px;cursor:pointer}.xch-go.buy{background:var(--accent);color:#06231a}.xch-go.sell{background:#e06b6b;color:#fff}"
      + ".xch-sub{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin:14px 0 6px}"
      + ".xch-row{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.xch-row input{flex:1;min-width:70px}"
      + ".xch-row button{padding:10px 12px;border-radius:8px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--text);cursor:pointer}"
      + ".xch-orders{max-height:200px;overflow:auto}.xord{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:13px;border-bottom:1px solid #1d3d2c;padding:7px 2px}"
      + ".xord .buy{color:var(--accent)}.xord .sell{color:#e06b6b}.xord-act{display:flex;gap:4px}.xord button{padding:5px 10px;border-radius:7px;border:1px solid #2a4d3a;background:var(--panel-2);color:var(--muted);cursor:pointer;font-size:12px}"
      + ".xord-edit{display:flex;gap:4px;align-items:center}.xord-edit input{width:64px!important;padding:6px;font-size:13px}"
      + ".xch-fees{font-size:11px;color:var(--muted);margin-top:6px;text-align:center}"
      + ".xch-msg{font-size:12px;color:var(--accent-2);min-height:16px;margin-top:10px}";
    var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

    container.innerHTML = '<div class="xch">'
      + '<div class="xch-head"><div class="xch-pair">💎 GEMS <span>/ $ CASH</span></div></div>'
      + '<div class="xch-tick"><div class="xch-price" id="xPrice">—</div><div class="xch-chg" id="xChg">—</div><div class="xch-reg" id="xReg">🦀 Plat</div></div>'
      + '<div class="xch-hl" id="xHL">H — · B —</div>'
      + '<div class="xch-tf" id="xTF"><button data-tf="15" class="on">15m</button><button data-tf="60">1H</button><button data-tf="240">4H</button><button data-tf="1440">D</button></div>'
      + '<div class="xch-chart" id="xChart"><div class="xempty">Chargement du graphique…</div></div>'
      + '<div class="xch-body">'
      + '<div class="xch-col-book"><div class="xch-book"><div class="xch-bookhead"><span>Prix ($)</span><span>Qté 💎</span></div>'
      + '<div id="xAsks"></div><div class="xch-mid" id="xMid">—</div><div id="xBids"></div>'
      + '<div class="xch-press"><div class="xch-press-buy" id="xPbuy" style="width:50%"></div><div class="xch-press-sell" id="xPsell" style="width:50%"></div></div>'
      + '<div class="xch-presslabel"><span id="xPbl">—</span><span id="xPsl">—</span></div></div></div>'
      + '<div class="xch-col-trade">'
      + '<div class="xch-toggle"><button id="xBuyTab" class="on">Acheter</button><button id="xSellTab">Vendre</button></div>'
      + '<div class="xch-type"><button id="xTypeLimit" class="on">Limite</button><button id="xTypeMarket">Market</button></div>'
      + '<label class="xch-l" id="xPriceLbl">Prix ($ / 💎)</label><input id="xPriceIn" type="number" min="0" step="0.01">'
      + '<label class="xch-l">Quantité 💎</label><input id="xAmtIn" type="number" min="0" placeholder="0">'
      + '<input id="xSlider" type="range" min="0" max="100" value="0">'
      + '<div class="xch-presets"><button data-pct="25">25%</button><button data-pct="50">50%</button><button data-pct="75">75%</button><button data-pct="100">Max</button></div>'
      + '<div class="xch-total">Total : $<b id="xTotal">0</b></div>'
      + '<div class="xch-avbl" id="xAvbl">…</div>'
      + '<button class="xch-go buy" id="xGo">Acheter 💎</button>'
      + '<div class="xch-fees" id="xFees"></div>'
      + '<div class="xch-sub">Jeu ⇄ Marché</div>'
      + '<div class="xch-row">💎<input id="xMg" type="number" min="0" placeholder="gemmes"> $<input id="xMc" type="number" min="0" placeholder="cash">'
      + '<button id="xDep">Déposer</button><button id="xWit">Retirer</button></div>'
      + '<div class="xch-sub">Mes ordres</div><div class="xch-orders" id="xMyOrders">…</div>'
      + '</div></div>'
      + '<div class="xch-msg" id="xMsg"></div></div>';
    mkMsg = container.querySelector("#xMsg");

    // Handlers buy/sell
    container.querySelector("#xBuyTab").onclick = function () { setSide("buy"); };
    container.querySelector("#xSellTab").onclick = function () { setSide("sell"); };
    container.querySelector("#xTypeLimit").onclick = function () { setType("limit"); };
    container.querySelector("#xTypeMarket").onclick = function () { setType("market"); };
    container.querySelectorAll(".xch-tf button").forEach(function (b) {
      b.onclick = function () {
        mkTF = parseInt(b.getAttribute("data-tf"), 10) || 15;
        container.querySelectorAll(".xch-tf button").forEach(function (x) { x.classList.toggle("on", x === b); });
        renderChart();
      };
    });
    container.querySelector("#xSlider").oninput = function () { setAmtFromPct(parseInt(this.value, 10) || 0); };
    container.querySelector("#xAmtIn").oninput = syncSliderFromAmt;
    container.querySelector("#xPriceIn").oninput = function () { syncSliderFromAmt(); };
    container.querySelectorAll(".xch-presets button").forEach(function (b) {
      b.onclick = function () { setAmtFromPct(parseInt(b.getAttribute("data-pct"), 10)); };
    });
    container.querySelector("#xGo").onclick = function () {
      if (!user) { mkSay("Connecte-toi pour trader."); return; }
      var g = Math.floor(parseFloat($id("xAmtIn").value) || 0);
      if (!g) { mkSay("Quantité requise."); return; }
      var done = function (okMsg) {
        return function (r) {
          if (r && r.data && r.data.success) { mkSay(okMsg); $id("xAmtIn").value = ""; $id("xSlider").value = 0; syncTotal(); }
          else { mkSay((r && r.data && r.data.error) || (r && r.error && r.error.message) || "Erreur."); }
          renderMarket();
        };
      };
      if (mkType === "market") {
        Cloud.economy.market(mkSide, g).then(done(mkSide === "buy" ? "Achat Market exécuté ✔" : "Vente Market exécutée ✔"));
      } else {
        var p = parseFloat($id("xPriceIn").value) || 0;
        if (!p) { mkSay("Prix requis (ordre limite)."); return; }
        Cloud.economy.place(mkSide, g, p).then(done(mkSide === "buy" ? "Ordre d'achat placé ✔" : "Ordre de vente placé ✔"));
      }
    };
    // Dépôt / retrait (jeu <-> marché)
    container.querySelector("#xDep").onclick = function () {
      if (!user) { mkSay("Connecte-toi d'abord."); return; }
      var g = Math.floor(parseFloat($id("xMg").value) || 0), c = Math.floor(parseFloat($id("xMc").value) || 0), s = bridge.getState();
      if (!g && !c) { mkSay("Indique un montant."); return; }
      if (g > (s.gems || 0) || c > (s.cash || 0)) { mkSay("Pas assez dans le jeu."); return; }
      Cloud.economy.deposit(g, c).then(function (r) { mkSay(r && r.data && r.data.success ? "Déposé ✔" : ((r && r.data && r.data.error) || "Erreur.")); $id("xMg").value = ""; $id("xMc").value = ""; renderMarket(); });
    };
    container.querySelector("#xWit").onclick = function () {
      if (!user) { mkSay("Connecte-toi d'abord."); return; }
      var g = Math.floor(parseFloat($id("xMg").value) || 0), c = Math.floor(parseFloat($id("xMc").value) || 0);
      if (!g && !c) { mkSay("Indique un montant."); return; }
      Cloud.economy.withdraw(g, c).then(function (r) { mkSay(r && r.data && r.data.success ? "Retiré ✔" : ((r && r.data && r.data.error) || "Solde marché insuffisant.")); $id("xMg").value = ""; $id("xMc").value = ""; renderMarket(); });
    };
  }

  injectUI();
  injectMarketUI();
})();
