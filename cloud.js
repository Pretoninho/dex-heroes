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
  var SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmaW1pcnR6bnlqc3Z1a3Bjb2VjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODYzNDcsImV4cCI6MjA5Nzc2MjM0N30.EoMjtkxK4v4XGTLer8BmzVyIJzoAVqezMpVaykD0Fz8";

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

  injectUI();
})();
