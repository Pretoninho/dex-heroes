/* ============================================================================
 * Dex Heroes — Données des héros (source d'affichage des fiches)
 * ----------------------------------------------------------------------------
 * Fichier de DONNÉES (pas de logique de jeu). Chargé via <script src> pour
 * rester compatible local (file://) ET en ligne (GitHub Pages).
 * Expose : window.HERO_META et window.HERO_DATA.
 *
 * id : DOIT correspondre à l'id du module dans index.html (a{bras}t{palier}).
 * rarity : 0 = Commun (3★), 1 = Rare (4★), 2 = Épique (5★) = palier du module.
 * effect : description structurée du passif (pour la future logique de jeu).
 *   family : A production/flux · B clic · C éco/gacha · D idle
 *   type   : mult | costReduce | autoClick | clickMult | gemGen | freePull |
 *            offlineMult | offlineCap | globalMult | synergyMult ...
 *   scope  : module | arm | rarity | downstream | global
 * Voir docs/heroes.md pour la conception complète.
 * ==========================================================================*/

(function (root) {
  "use strict";

  var HERO_META = {
    rarities: [
      { key: 0, name: "Commun", stars: 3, baseMult: 1.25, color: "#8fb7a3", fusionMax: 5 },
      { key: 1, name: "Rare",   stars: 4, baseMult: 1.60, color: "#7ab8ff", fusionMax: 4 },
      { key: 2, name: "Épique", stars: 5, baseMult: 2.00, color: "#ffd24d", fusionMax: 3 }
    ],
    regimes: ["BULL", "BEAR", "CRASH", "CRABE", "HYPE"],
    families: {
      A: "Production / flux", B: "Clic", C: "Économie / gacha", D: "Idle / hors-ligne"
    },
    // Synergies de collection (héros déployés ensemble) — voir docs/heroes.md §4
    synergies: [
      { key: "arm_banque",  name: "Banque",          members: ["a0t0", "a0t1", "a0t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "arm_bourse",  name: "Bourse",          members: ["a1t0", "a1t1", "a1t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "arm_immo",    name: "Immobilier",      members: ["a2t0", "a2t1", "a2t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "arm_indus",   name: "Industrie",       members: ["a3t0", "a3t1", "a3t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "arm_startup", name: "Startup",         members: ["a4t0", "a4t1", "a4t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "arm_energie", name: "Énergie",         members: ["a5t0", "a5t1", "a5t2"], mult: 1.25, bonus: "+25 % prod du bras" },
      { key: "speculation", name: "Spéculation",     members: ["a1t0", "a1t1", "a1t2", "a4t1"], mult: 1.30, bonus: "+risque / +gain" },
      { key: "briques",     name: "Briques & mortier", members: ["a2t0", "a2t1", "a2t2", "a3t0"], mult: 1.30, bonus: "+rente" },
      { key: "deeptech",    name: "Deep tech",       members: ["a3t2", "a5t2", "a5t1"], mult: 1.30, bonus: "+prod & −coûts" }
    ]
  };

  // --- Les 18 héros (1 par module) -----------------------------------------
  var HERO_DATA = [
    // Bras Banque 🏦 — intérêts & trésorerie
    { id: "a0t0", arm: "Banque", module: "Banque", emoji: "🏦", name: "Jasper Norgan", rarity: 0, klass: "Market Maker", regime: "CRABE",
      passive: { family: "A", text: "×1.25 production du module", effect: { type: "mult", value: 1.25, scope: "module" } },
      signature: { name: "Intérêts", text: "Encaisse l'équivalent de 60 s de prod du module", cooldown: 120 },
      synergies: ["arm_banque"] },
    { id: "a0t1", arm: "Banque", module: "Crédit", emoji: "💳", name: "Jamie Damone", rarity: 1, klass: "Momentum", regime: "BULL",
      passive: { family: "C", text: "−15 % coût d'amélioration du bras Banque", effect: { type: "costReduce", value: 0.15, scope: "arm" } },
      signature: { name: "Levier", text: "×2 production du bras pendant 20 s", cooldown: 180 },
      synergies: ["arm_banque"] },
    { id: "a0t2", arm: "Banque", module: "Trésorerie", emoji: "🏛️", name: "Mayer Roschild", rarity: 2, klass: "Diamond Hands", regime: "CRASH",
      passive: { family: "C", text: "Génère des gemmes 💎 passivement", effect: { type: "gemGen", value: 1, scope: "global" } },
      signature: { name: "Planche à billets", text: "Gros coup de cash instantané", cooldown: 300 },
      synergies: ["arm_banque"] },

    // Bras Bourse 📈 — spéculation
    { id: "a1t0", arm: "Bourse", module: "Bourse", emoji: "📈", name: "Warden Buffott", rarity: 0, klass: "Momentum", regime: "BULL",
      passive: { family: "A", text: "×1.25 production du module", effect: { type: "mult", value: 1.25, scope: "module" } },
      signature: { name: "Volume", text: "×3 production du module pendant 15 s", cooldown: 120 },
      synergies: ["arm_bourse", "speculation"] },
    { id: "a1t1", arm: "Bourse", module: "Crypto", emoji: "🪙", name: "Satoshi Nakomito", rarity: 1, klass: "Degen", regime: "HYPE",
      passive: { family: "B", text: "Auto-clic : 3 clics/s automatiques", effect: { type: "autoClick", value: 3, scope: "global" } },
      signature: { name: "FOMO", text: "Pluie de clics auto pendant 20 s", cooldown: 180 },
      synergies: ["arm_bourse", "speculation"] },
    { id: "a1t2", arm: "Bourse", module: "Hedge Fund", emoji: "🐋", name: "Georg Solros", rarity: 2, klass: "Short Seller", regime: "BEAR",
      passive: { family: "A", text: "×prod de tous les Rares déployés", effect: { type: "rarityMult", value: 1.15, scope: "rarity", rarity: 1 } },
      signature: { name: "Pump", text: "×5 production globale pendant 10 s", cooldown: 300 },
      synergies: ["arm_bourse", "speculation"] },

    // Bras Immobilier 🏠 — rente & idle
    { id: "a2t0", arm: "Immobilier", module: "Immobilier", emoji: "🏠", name: "Sam Zello", rarity: 0, klass: "Market Maker", regime: "CRABE",
      passive: { family: "D", text: "×1.5 gains hors-ligne", effect: { type: "offlineMult", value: 1.5, scope: "global" } },
      signature: { name: "Loyers", text: "Encaisse une avance de loyer", cooldown: 150 },
      synergies: ["arm_immo", "briques"] },
    { id: "a2t1", arm: "Immobilier", module: "Promotion", emoji: "🏗️", name: "Stephen Rolss", rarity: 1, klass: "Momentum", regime: "BULL",
      passive: { family: "A", text: "×prod de tout le bras Immobilier", effect: { type: "mult", value: 1.3, scope: "arm" } },
      signature: { name: "Chantier", text: "×2 production du bras pendant 25 s", cooldown: 180 },
      synergies: ["arm_immo", "briques"] },
    { id: "a2t2", arm: "Immobilier", module: "Gratte-ciel", emoji: "🌆", name: "Donald Trumb", rarity: 2, klass: "Momentum", regime: "BULL",
      passive: { family: "A", text: "+% production globale du Dex", effect: { type: "globalMult", value: 1.1, scope: "global" } },
      signature: { name: "Empire", text: "×4 production globale pendant 12 s", cooldown: 300 },
      synergies: ["arm_immo", "briques"] },

    // Bras Industrie 🏭 — production lourde
    { id: "a3t0", arm: "Industrie", module: "Industrie", emoji: "🏭", name: "Henry Frod", rarity: 0, klass: "Quant", regime: null,
      passive: { family: "A", text: "×1.25 production du module", effect: { type: "mult", value: 1.25, scope: "module" } },
      signature: { name: "Cadence", text: "×3 production du module pendant 15 s", cooldown: 120 },
      synergies: ["arm_indus", "briques"] },
    { id: "a3t1", arm: "Industrie", module: "Commerce", emoji: "🚢", name: "Aristote Onissas", rarity: 1, klass: "Market Maker", regime: "CRABE",
      passive: { family: "A", text: "Booste les modules en aval (flux)", effect: { type: "downstreamMult", value: 1.2, scope: "downstream" } },
      signature: { name: "Convoi", text: "×2 production en aval pendant 25 s", cooldown: 180 },
      synergies: ["arm_indus"] },
    { id: "a3t2", arm: "Industrie", module: "Aérospatial", emoji: "🛰️", name: "Richard Brunson", rarity: 2, klass: "Diamond Hands", regime: "CRASH",
      passive: { family: "C", text: "−prix des gemmes", effect: { type: "gemPriceReduce", value: 0.2, scope: "global" } },
      signature: { name: "Lancement", text: "Le prochain tirage est gratuit", cooldown: 240 },
      synergies: ["arm_indus", "deeptech"] },

    // Bras Startup 💼 — clic & croissance
    { id: "a4t0", arm: "Startup", module: "Startup", emoji: "💼", name: "Steve Jorbs", rarity: 0, klass: "Degen", regime: "HYPE",
      passive: { family: "B", text: "+100 % puissance de clic", effect: { type: "clickMult", value: 2, scope: "global" } },
      signature: { name: "Pitch", text: "Clics ×10 pendant 15 s", cooldown: 150 },
      synergies: ["arm_startup"] },
    { id: "a4t1", arm: "Startup", module: "Licorne", emoji: "🦄", name: "Pieter Thielo", rarity: 1, klass: "Momentum", regime: "BULL",
      passive: { family: "C", text: "+chance de tirage gratuit au gacha", effect: { type: "freePullChance", value: 0.05, scope: "global" } },
      signature: { name: "Levée", text: "+20 % de drop pendant 5 tirages", cooldown: 300 },
      synergies: ["arm_startup", "speculation"] },
    { id: "a4t2", arm: "Startup", module: "Conglomérat", emoji: "🌍", name: "Geoff Bezus", rarity: 2, klass: "Quant", regime: null,
      passive: { family: "F", text: "×prod par synergie active", effect: { type: "synergyMult", value: 1.1, scope: "global" } },
      signature: { name: "Fusion-acquisition", text: "Active toutes les synergies pendant 15 s", cooldown: 300 },
      synergies: ["arm_startup"] },

    // Bras Énergie 🛢️ — puissance brute
    { id: "a5t0", arm: "Énergie", module: "Énergie", emoji: "🛢️", name: "John Lockefeller", rarity: 0, klass: "Diamond Hands", regime: "CRASH",
      passive: { family: "D", text: "+plafond de production hors-ligne", effect: { type: "offlineCap", value: 1.5, scope: "global" } },
      signature: { name: "Gisement", text: "Double le stock idle accumulé", cooldown: 240 },
      synergies: ["arm_energie"] },
    { id: "a5t1", arm: "Énergie", module: "Renouvelable", emoji: "⚡", name: "Elron Tusk", rarity: 1, klass: "Momentum", regime: "BULL",
      passive: { family: "A", text: "×prod des modules de même rareté", effect: { type: "rarityMult", value: 1.15, scope: "rarity", rarity: 1 } },
      signature: { name: "Réseau", text: "×2 production des Rares pendant 20 s", cooldown: 180 },
      synergies: ["arm_energie", "deeptech"] },
    { id: "a5t2", arm: "Énergie", module: "Fusion", emoji: "☢️", name: "Bill Gatts", rarity: 2, klass: "Degen", regime: "HYPE",
      passive: { family: "A", text: "×prod globale (le plus fort)", effect: { type: "globalMult", value: 1.2, scope: "global" } },
      signature: { name: "Réaction en chaîne", text: "×8 production pendant 8 s", cooldown: 360 },
      synergies: ["arm_energie", "deeptech"] }
  ];

  root.HERO_META = HERO_META;
  root.HERO_DATA = HERO_DATA;
  if (typeof module !== "undefined" && module.exports) module.exports = { HERO_META: HERO_META, HERO_DATA: HERO_DATA };
})(typeof window !== "undefined" ? window : this);
