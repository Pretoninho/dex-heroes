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
        '<div class="row"><button id="cMarket">🏦 Marché</button>' +
        '<button id="cOut">Déconnexion</button></div>' +
        '<div class="cloud-msg" id="cMsg"></div>' +
        '<div class="cloud-board" id="cBoardList"></div>' +
        '<button class="cloud-close" id="cClose">Fermer</button>';
      msgEl = card.querySelector("#cMsg");
      card.querySelector("#cName").onchange = function () { setName(this.value); say("Pseudo enregistré."); };
      card.querySelector("#cSync").onclick = function () { lastPush = 0; Cloud.push(bridge.getState()); say("Sauvegardé ✔"); };
      card.querySelector("#cMarket").onclick = function () { document.getElementById("cloudOv").classList.remove("show"); openMarket(); };
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

  var mkMsg = null;
  function mkSay(t) { if (mkMsg) mkMsg.textContent = t || ""; }
  function mkAfter(ok) { return function (r) { mkSay(r && r.error ? (r.error.message || "Erreur") : ok); renderMarket(); }; }
  function mkNum(id) { var v = parseFloat(document.getElementById(id).value); return isFinite(v) && v > 0 ? Math.floor(v) : 0; }
  function openMarket() { document.getElementById("mkOv").classList.add("show"); renderMarket(); }

  function renderMarket() {
    Cloud.market.wallet().then(function (r) {
      var w = (r && r.data) || { gems: 0, cash: 0 };
      var el = document.getElementById("mkWallet");
      if (el) el.innerHTML = "Porte-monnaie : 💎 <b>" + fmtN(w.gems) + "</b> &middot; $<b>" + fmtN(w.cash) + "</b>";
    });
    Cloud.market.listings().then(function (r) {
      var el = document.getElementById("mkList"); if (!el) return;
      if (r.error) { el.textContent = r.error.message; return; }
      var rows = r.data || [];
      if (!rows.length) { el.innerHTML = '<div class="mk-li">Aucune annonce</div>'; return; }
      el.innerHTML = rows.map(function (x) {
        var mine = user && x.seller === user.id;
        var btn = mine ? '<button data-cancel="' + x.id + '">Annuler</button>'
                       : '<button class="primary" data-buy="' + x.id + '">Acheter</button>';
        return '<div class="mk-li"><span>' + esc(x.seller_name || "anonyme") + ' — 💎' + fmtN(x.gems) + ' pour $' + fmtN(x.price) + '</span>' + btn + '</div>';
      }).join("");
      el.querySelectorAll("[data-buy]").forEach(function (b) { b.onclick = function () { Cloud.market.buy(b.getAttribute("data-buy")).then(mkAfter("Acheté !")); }; });
      el.querySelectorAll("[data-cancel]").forEach(function (b) { b.onclick = function () { Cloud.market.cancel(b.getAttribute("data-cancel")).then(mkAfter("Annulé.")); }; });
    });
  }

  function injectMarketUI() {
    var css = ""
      + ".mk-ov{position:fixed;inset:0;background:rgba(0,0,0,.6);display:none;align-items:flex-start;justify-content:center;z-index:210;padding:16px;overflow:auto}"
      + ".mk-ov.show{display:flex}"
      + ".mk-card{background:#12281d;border:1px solid #1d3d2c;border-radius:16px;padding:18px;width:100%;max-width:440px;color:#eafff4;margin:auto}"
      + ".mk-card h3{margin:0 0 10px}.mk-wallet{background:#18342695;border:1px solid #2a4d3a;border-radius:10px;padding:10px;font-size:15px;margin-bottom:12px}"
      + ".mk-wallet b{color:#ffd24d}.mk-sub{color:#8fb7a3;font-size:12px;margin:12px 0 6px;text-transform:uppercase;letter-spacing:.5px}"
      + ".mk-card input{width:78px;box-sizing:border-box;padding:8px;border-radius:8px;border:1px solid #2a4d3a;background:#0d1f17;color:#eafff4}"
      + ".mk-row{display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:6px}"
      + ".mk-card button{padding:8px 12px;border-radius:8px;border:1px solid #2a4d3a;background:#18342695;color:#eafff4;cursor:pointer}"
      + ".mk-card button.primary{border-color:#ffd24d;color:#ffd24d}.mk-list{max-height:240px;overflow:auto}"
      + ".mk-li{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:13px;border-bottom:1px solid #1d3d2c;padding:7px 2px}"
      + ".mk-msg{font-size:12px;color:#ffd24d;min-height:16px;margin-top:8px}.mk-close{margin-top:12px;width:100%;opacity:.85}";
    var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

    var ov = document.createElement("div"); ov.className = "mk-ov"; ov.id = "mkOv";
    ov.innerHTML = '<div class="mk-card">'
      + '<h3>🏦 Marché des gemmes</h3>'
      + '<div class="mk-wallet" id="mkWallet">Porte-monnaie : …</div>'
      + '<div class="mk-sub">Déposer / retirer (jeu &harr; marché)</div>'
      + '<div class="mk-row">💎<input id="mkDg" type="number" min="0" placeholder="gemmes"> $<input id="mkDc" type="number" min="0" placeholder="cash">'
      + '<button id="mkDep">Déposer</button><button id="mkWit">Retirer</button></div>'
      + '<div class="mk-sub">Vendre des gemmes</div>'
      + '<div class="mk-row">💎<input id="mkSg" type="number" min="1" placeholder="gemmes"> $<input id="mkSp" type="number" min="1" placeholder="prix">'
      + '<button class="primary" id="mkSell">Mettre en vente</button></div>'
      + '<div class="mk-sub">Annonces</div>'
      + '<div class="mk-list" id="mkList">…</div>'
      + '<div class="mk-msg" id="mkMsg"></div>'
      + '<button class="mk-close" id="mkClose">Fermer</button></div>';
    document.body.appendChild(ov);
    ov.addEventListener("click", function (e) { if (e.target === ov) ov.classList.remove("show"); });
    mkMsg = ov.querySelector("#mkMsg");
    ov.querySelector("#mkClose").onclick = function () { ov.classList.remove("show"); };
    ov.querySelector("#mkDep").onclick = function () {
      var g = mkNum("mkDg"), c = mkNum("mkDc"), s = bridge.getState();
      if (g > (s.gems || 0) || c > (s.cash || 0)) { mkSay("Pas assez dans le jeu."); return; }
      if (!g && !c) { mkSay("Indique un montant."); return; }
      Cloud.market.deposit(g, c).then(mkAfter("Déposé."));
    };
    ov.querySelector("#mkWit").onclick = function () { var g = mkNum("mkDg"), c = mkNum("mkDc"); if (!g && !c) { mkSay("Indique un montant."); return; } Cloud.market.withdraw(g, c).then(mkAfter("Retiré.")); };
    ov.querySelector("#mkSell").onclick = function () { var g = mkNum("mkSg"), p = mkNum("mkSp"); if (!g || !p) { mkSay("Gemmes et prix requis."); return; } Cloud.market.create(g, p).then(mkAfter("En vente !")); };
  }

  injectUI();
  injectMarketUI();
})();
