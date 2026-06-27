# CLAUDE.md — Mémoire projet Dex Heroes

> Fichier de contexte persistant pour Claude. Le mettre à jour quand l'archi ou l'état évolue.

## Vue d'ensemble

**Dex Heroes** = *idle game* sur le thème de la **finance** (parodie). HTML/CSS/JS pur,
déployé en statique sur **GitHub Pages** depuis `main`. Backend optionnel **Supabase**
(comptes, cloud save, classement, et une **économie event-sourced** complète).

- **Langue de travail : français.**
- Jeu en ligne : `https://pretoninho.github.io/dex-heroes/`

## ⭐ Cap polaire (décidé le 2026-06-24) : **100 % IDLE**

Le projet **se recentre sur l'idle pur**. Tout système **actif/attentionnel/online**
est **hors périmètre** et sera **retiré des fichiers à terme** (pas tout de suite —
suppression délibérée, à confirmer avant chaque purge) :
- **✅ RETIRÉ du front (2026-06-24)** : tout le terminal **Exchange** — onglet `market`,
  écran `#marketScreen`, activité Exchange du module Bourse, mini-wallet (dépôt/retrait),
  achat de gems **au cours**/retail (→ gemmes au **prix-formule** idle pur), `TRADING_ARM`/
  venue OTC, **et tout `Cloud.economy.*` dans `cloud.js`** (663→229 lignes ; on garde auth/
  cloud-save/classement/pseudo). Le **régime** est parti avec (badge, fetch, `regimeProdMult`,
  affinité de fiche) — le champ `regime` des héros **reste en données** pour réemploi futur.
- **À retirer à terme (backend, encore en place)** : **OTC** (`economy_otc.sql`), **arbitrage**,
  **retail**, **levier** (L5), `economy_l2/l3/l3b/l4`… (le SQL n'est plus appelé par le front ;
  purge Supabase à planifier). Design **$VOLT *avec trading*** : minage passif + staking
  pourront revenir en version idle-pure.
- **On garde / on construit (idle-natif)** : cash flow, gacha, héros (passifs/synergies/
  signatures), fusion + Éclats, **gains hors-ligne**, **automatisation** (managers),
  **Valorisation** (soft-prestige), **Objectifs**, **prestige**, contenu de bras/modules.
- **Règle d'or** : chaque système a un **chemin passif par défaut** ; l'endgame
  **n'exige jamais** une action manuelle/online.
- **Focus courant** : ~~bloc **Hors-ligne + Automatisation**~~ ✅ FAIT (1ᵉʳ bloc idle-natif) :
  gains hors-ligne **plafonnés** (`OFFLINE_CAP_BASE`=4 h, héros `offlineCap` l'étendent via
  `offlineCapMult` — désormais distinct d'`offlineMult`) + **modale « Bon retour »** ;
  **auto-amélioration** (`state.autoBuy`, `autoBuyStep`, toggle 🤖, cadence `AUTO_BUY_MS`).
  Prochains idle-natifs : **prestige/ascension**, contenu de bras/modules.
- ⚠️ Les sections « économie/Exchange/$VOLT » ci-dessous décrivent l'existant **en
  sursis** : ne plus l'étendre ; le documenter sert surtout à savoir **quoi retirer**.

## Carte des fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | **Tout le jeu** (HTML/CSS/JS inline) : cash flow, modules, dexes, gacha, héros, **fusion + Éclats** (`state.shards`, `SHARD_PER_COPY`, `craftHero`), **surnoms** (`state.nicknames`, `heroName`/`heroNameFull`), **Valorisation** (`state.valoRank`, `valoMult`/`buyValo` — soft-prestige sans reset), **Objectifs** (`state.objectives`, `OBJECTIVES`, `checkObjectives`/`seedObjectives`, écran `🎯`), **gains hors-ligne + auto-amélioration**, horloge UTC, pont `window.DEX`, **🌍 `world()` (cycle de marché déterministe partagé, fonction pure UTC) + bandeau météo**, **🎰 Margin Call** (`state.mc`, `mcLaunch`/`mcAdvance`/`mcCollect`/`mcProject`, écran `#margincallScreen`). ⚠️ Exchange/régime backend **retirés** (2026-06-24) — le `world()` régime est **reconstruit en LOCAL**, sans serveur. |
| `heroes.data.js` | `window.HERO_META` + `window.HERO_DATA` (18 héros : passif, signature, synergies, klass, `regime`). Le champ `regime` n'est **plus utilisé** par le front (régime retiré) mais conservé pour réemploi. |
| `cloud.js` | Intégration Supabase : auth, cloud save, classement, pseudo. **Le terminal Exchange (`Cloud.economy.*`) a été retiré** (2026-06-24, pivot 100 % Idle). |
| `sw.js` | **Service worker « réseau d'abord »** (2026-06-27) : la PWA récupère la version fraîche en ligne à chaque ouverture (cache = hors-ligne seulement) → fini la PWA iOS figée sur le cache. Enregistré par `index.html`. |
| `manifest.webmanifest` | Manifest PWA minimal (standalone, scope, theme-color) — installable proprement. |
| `backend/*.sql` | Schéma + fonctions Postgres de l'économie (voir ordre de déploiement) |
| `docs/economy.md` | Blueprint de l'économie **implémentée** (lois, couches L1–L5, décisions) |
| `docs/economy-vision.md` | **Design à venir** (validé en discussion, pas codé) : verticale Trading, Éclats, surnoms héros, jeton **$VOLT**, tiers retail/OTC, achat gems au cours |
| `docs/heroes.md` | Conception des héros |
| `backend/README.md` | Guide de mise en place Supabase |

## Conventions IMPORTANTES

- **Cache-busting** : `cloud.js` est chargé avec `?v=N` dans `index.html`.
  **Bumper N à chaque modif de `cloud.js`** (sinon le navigateur sert l'ancien).
  Version actuelle : **v=25** (refonte UI : compte cloud re-logé dans la modale ⚙️ Réglages).
- **Workflow git** : l'utilisateur push directement sur `main` ; **le jeu se déploie depuis `main`**.
- **Déploiement (GitHub Pages via Actions `.github/workflows/pages.yml`)** : `build_type: workflow`, gardé par
  l'**environnement `github-pages`** dont la *deployment-branch-policy* liste les branches autorisées.
  ⚠️ **Gotcha (réglé le 24/06/2026)** : la policy n'autorisait que `claude/simple-idle-game-dg2zyb` → tout
  push sur `main` **échouait au déploiement en ~3 s** (rien en ligne). On a **ajouté `main`** à la policy
  (`gh api -X POST repos/:o/:r/environments/github-pages/deployment-branch-policies -f name=main -f type=branch`).
  Vérifier qu'un push s'est bien déployé : `gh run list --workflow=pages.yml --branch main -L 1`. Forcer :
  `gh workflow run pages.yml --ref main`.
- **Vérifier la syntaxe JS** : `node --check cloud.js` ; pour index.html, extraire le `<script>` inline et `node --check`.
- Ne **pas** créer de PR sans demande explicite — ici l'utilisateur veut systématiquement push sur main.

## Supabase

- URL : `https://zfimirtznyjsvukpcoec.supabase.co`
- Clé publishable (publique par design, déjà dans `cloud.js`) : `sb_publishable_j90seJWpkZU_uKWbGt9ZRg_rNfQ5ztf`
- **RLS partout.** Les fonctions sensibles sont `security definer`. Lectures publiques (ticker,
  orderbook, régime, historique, fees) accordées à `anon`. Écritures via fonctions uniquement.
- Le **tick** est planifié par `pg_cron` (`select cron.schedule('npc-tick','* * * * *', $$ select public.economy_tick_npcs(); $$);`).
  pg_cron doit être activé (Dashboard → Database → Extensions).
- Vérif via REST (lectures `anon`) :
  `curl "$URL/rest/v1/economy_regime_state?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"`

## Économie — architecture (inspirée d'AXIOM)

**Event-sourcing** : les faits sont immuables (`economy_ledger`, append-only), les soldes
sont une **projection** (`economy_balances`, cache). **Conservation** : toute `tx` somme à 0
par ressource (SYSTÈME `00000000-…-0000` inclus, seul autorisé à être négatif = robinet/puits).
Les **frais** sont la part d'un règlement qui **reste chez SYSTÈME** (sink) → conservation préservée.

Invariant santé : `select resource_id, sum(balance) from economy_balances group by resource_id;` → **0 par ressource**.

### Couches
- **L1** ledger + acteurs + `economy_post_tx` (3 tests : conservation / bornes / sanité prix).
- **L2** marché : `economy_orders`, `economy_trades`, `economy_price_index`, matching, `economy_refresh_price`.
- **L3** NPC **market-maker** (`economy_ensure_market_maker`, `economy_place_order_as`, `economy_cancel_all_orders`).
- **L3b** NPC **réactif** (`economy_ensure_reactive_npc`, `economy_market_order_as`) — fait bouger le cours (momentum + retour à la moyenne + bruit). Redéfinit `economy_tick_npcs` (MM + réactif + historique + régime).
- **L4** **régime** émergent global (`economy_classify_market`, `economy_update_regime` avec **hystérésis**, `economy_get_regime`). 5 régimes BULL/BEAR/CRASH/CRABE/HYPE. Lit la tendance du cours, déterministe, jamais aléatoire.
- **L5** contrats / **levier** — PAS encore fait.
- **OTC** (`economy_otc.sql`) — **2ᵉ venue** (`venue` ∈ retail/otc) cloisonnée du retail :
  matching/market-order/refresh-price **paramétrés par venue** (`*_v(p_venue)` + surcharges
  rétro-compat 'retail'), **2 cours** (`gems_cash` retail / `gems_cash_otc` OTC), NPC MM **mince** +
  réactif **agité** + **garde-fou d'arbitrage** (n'agit qu'au-delà de `arb_threshold`=5 %).
  Frais OTC `economy_config['fees_otc']` (taker **1,0 %**). API joueur : `economy_ticker_otc`,
  `economy_orderbook_otc`, `economy_place_order_otc`, `economy_market_order_otc` (taille mini 200 💎).
  Redéfinit `economy_tick_npcs` (corps L3b + `economy_tick_otc()`).
- Frais : `economy_fees.sql` (maker/taker + retrait), `economy_get_fees`.
- Ordres Market : `economy_market_order.sql`.
- API UI : `economy_market_api.sql` (ticker UTC, deposit/withdraw, my_balances, my_orders, amend).

### Ordre de déploiement SQL (CRITIQUE — chaque fichier redéfinit des fonctions du précédent)
```
economy.sql → economy_l2.sql → economy_l3.sql → economy_l4.sql
→ economy_market_api.sql → economy_fees.sql → economy_market_order.sql → economy_l3b.sql
→ economy_retail.sql → economy_otc.sql
```
⚠️ `economy_l3b.sql` redéfinit `economy_tick_npcs` (MM + réactif + historique + régime) et
`economy_market_order` (délègue à `economy_market_order_as`) → le passer **avant** `economy_retail.sql`
(qui dépend de `economy_market_order_as`). Si on re-passe un fichier intermédiaire, re-passer la suite.
`economy_retail.sql` = achat de gems au cours (tier retail, sous-acteur de passage).
⚠️ `economy_otc.sql` est le **DERNIER** : il redéfinit `economy_tick_npcs` (corps L3b **+** `economy_tick_otc()`),
le matching, `economy_market_order_as`, `economy_place_order_as` et `economy_refresh_price` en versions
**venue-aware** (les surcharges sans `p_venue` restent 'retail' → 0 régression). **Si on re-passe `l3b`,
RE-PASSER `economy_otc.sql` ensuite** (sinon le tick OTC est perdu). Tests : `test_economy_otc.sql`.

## Le terminal Exchange (frontend, dans `cloud.js`) — ⚠️ **RETIRÉ le 2026-06-24**

> Cette section décrit du code **supprimé** (pivot 100 % Idle). Conservée comme référence
> pour la **purge backend** restante (fonctions SQL `economy_*` encore déployées sur Supabase
> mais plus appelées). Ne rien réintroduire ici sans décision explicite.

- Onglet **🫱🏻‍🫲🏻 Exchange** (barre du haut, `data-nav="market"`) → écran plein `#marketScreen` (pas une modale).
  `index.html` appelle `Cloud.marketOpen()/marketClose()` via `showScreen("market")`.
- **Accès Exchange sur tout le bras Bourse** (`TRADING_ARM`) : chaque module du bras (Bourse / Crypto /
  Hedge Fund) a un accès Exchange + mini-wallet (dépôt/retrait). Vision : bras = verticale Trading.
- **Bascule de venue Retail ⇄ OTC** (`mkVenue`, `setVenue()`) : toggle en haut du terminal. Ouvrir
  l'Exchange depuis **Hedge Fund** force la venue **OTC** (`Cloud.marketOpen('otc')` via `pendingMarketVenue`).
  En OTC : carnet/ticker/buy/sell routés vers `*_otc` ; frais 1,0 % ; min 200 💎.
- **Widget d'arbitrage** (`#xArb`) toujours visible : `Retail $ · OTC $ · écart %`, passe **🟢 vert** quand
  |écart| > friction aller-retour (~1,2 %). L'arbitrage est une **activité joueur** (les frais sont le gate ;
  le garde-fou NPC ne borne que les écarts extrêmes). Pas de graphique OTC (l'historique reste retail = réf. régime).
- **Achat de gems au cours** : le bouton +100/+1000 fait un `economy_retail_buy_gems` (tier retail) si
  connecté ; sinon formule indexée (fallback hors-ligne). Cours lu via `Cloud.economy.ticker()`.
- Contenu : ticker (prix, **% var depuis 00:00 UTC**, régime nom+badge, H/B), **graphique chandeliers
  2 axes + timeframes 15m/1H/4H/D**, carnet (asks/bids + pression), buy/sell **Limite/Market**
  (slider + saisie), frais affichés, dépôt/retrait, mes ordres + **modification en ligne** (amend atomique).
- Pseudo : persistant (oninput + sync cloud via `scores.display_name`).

## Décisions verrouillées

- Numéraire = **cash**. Paire v1 = **gemmes ↔ cash**.
- Frais v1 = **maker 0,1 % / taker 0,2 % / retrait 0,5 %** (tunables dans `economy_config`).
  **Les héros ne réduisent PAS les frais.** **OTC** : maker 0,2 % / **taker 1,0 %** (`fees_otc`).
- **Arbitrage = activité joueur** : les **frais** sont le gate (round-trip ~1,2 % → l'écart doit le dépasser).
  Le **NPC garde-fou** ne recolle que les écarts **extrêmes** (>5 %) → la bande de profit reste au joueur.
- **Régime non aléatoire** : transcrit le marché interne (option 2). Global, recalculé au tick, **hystérésis** (ne change pas chaque minute).
- **Levier** : à construire en L5, **max-levier = f(niveau du héros Bourse)** (seule influence héros sur l'Exchange).
- Exécution **instantanée avant échéance** (ordre limite avant contrats à terme).
- **$VOLT (design v1 verrouillé, pas encore codé)** : minage = **pool global pro-rata** (émission
  globale fixe/tick répartie au prorata du hashrate = prod du bras Énergie ; **pas** de plafond par
  joueur) · **halving par seuils de supply** (épochs géométriques `E=base×2^−epoch`, convergent vers
  `C`≈21M tunable, déterministe) · v1 = **minage + trade + staking** (levier/carburant plus tard) ·
  paire **$VOLT↔cash** via module **🎲 Spéculation** (a1t1, héros Satoshi) · **staking avec lock**,
  part des frais **croissante → 100 % au plafond**, **Satoshi (Degen) booste le staking** · backend
  `economy_volt.sql` (dernier ; tables `volt_state`/`volt_miners`/`volt_stakes`, mint au tick pg_cron) ·
  moteur à rendre **pair-aware**. Tuning restant : `base`/`C`, vitesse→1er halving, durée lock, courbe frais, % Satoshi.
- **Éclats (Phase 1)** : **local** d'abord (pas de ledger) · fabrication **ciblée** (héros choisi) ·
  **un seul taux** `SHARD_PER_COPY`=8/6/4 (Commun/Rare/Épique) qui sert et à fabriquer **et** à
  couvrir une fusion (Éclats = doublons de secours) · faucet = **1 Éclat par doublon-surplus** d'un
  héros déjà maxé. **On ne trade JAMAIS les héros entiers** (anti-pay-to-win) — le trade portera sur
  les Éclats (fongibles par rareté) en Phase 2.
- **Difficulté (calibre modéré)** : `GROWTH` = **1,15** (×coût/niveau — *calibré sur le tempo Cookie Clicker*
  le 2026-06-25 : 1,28→1,15, courbe douce = goutte-à-goutte, l'arc s'allonge tout seul ; les murs de palier
  ×1,6 testés puis retirés) · gains **hors-ligne plafonnés**
  (`OFFLINE_CAP_H`=4 h, `OFFLINE_RATE`=0,5 ; les héros `offlineMult`/`offlineCap` étendent le **plafond**
  en heures, plus le taux) · **Dex 3** (puits de cash endgame, 50 M, efficience ~0,4×). Leviers tunables :
  `GROWTH`, `OFFLINE_CAP_H`/`OFFLINE_RATE`, `DEX_DEFS`.
- **Valorisation = soft-prestige SANS reset** : rang d'entreprise acheté **au cash** (`VALO_BASE`=100 k,
  `VALO_GROWTH`=×8/rang), chaque rang = **+10 %** prod globale (`VALO_STEP`, multiplicatif, permanent).
  C'est à la fois le **niveau joueur** ET le **puits de cash structurel** de fin de partie. Branché dans
  `perSecond()` (`× valoMult()`). Titres : Stagiaire→…→Légende, puis `★N`.
- **Objectifs = jalons one-shot** : conditions **dérivées de l'état courant** (prod $/s, modules connectés,
  héros possédés/maxés, rang Valo, Dex), donc **pas de compteur cumulatif**. Récompense (💎/🧩) versée
  **une fois** (latch `state.objectives`). Saves d'avant la feature **amorcées en silence** (`seedObjectives`
  marque l'acquis sans payer). C'est l'ancrage des futures **quêtes** (récurrentes, reset UTC).

## Refonte méta héros / gear / fragments — **EN CONCEPTION** (2026-06-25)

> Direction décidée en sparring, **pas encore codée**, et **assume un écart au cap 100 % idle**
> (« on laisse un peu de gestion »). Réf. d'ambiance : idle-RPG gacha façon AFK Arena (captures fournies)
> — **exemples d'ambiance, pas spec** (le jeu n'a **pas de combat** : tout effet héros/gear porte sur la **prod $/s**).

**Verrouillé :**
- **Effet héros + gear = production** (pas de combat ; ❤️/⚔️/🛡️ de la réf → buffs de prod $/s).
- **Placement par module** : 3 slots = **1 signature** (le héros propre du module → *effet spécial*) +
  **2 héros de même rareté** que le module (→ *buff*). La rareté est **équilibrée 6/6/6** (≠ les `klass`
  finance, déséquilibrées 6/3/3/3/2/1 — donc **gating par rareté, pas par classe**).
- **Inventaire à doublons** : on possède **plusieurs exemplaires** d'un même héros, **chacun équipé
  séparément** (jusqu'à 3 objets). Un exemplaire couvre **un** slot → couvrir 6 modules d'une rareté = jusqu'à
  6 exemplaires. **Tension profondeur (fusionner) vs largeur (garder pour étaler).**
- **Gacha tire des fragments** (ciblés par héros) **au lieu de héros**. Fusion **base-3** (Commun/Rare) /
  **base-4** (Épique) : niveau L = `b^L` fragments. Objets : même système (classes C/R/É, fusion).
- **Chiffrage prod — VERROUILLÉ par simulation (2026-06-25)** :
  - **Buffeur** = **+1 %/niveau, max +10 %** (niv 10 = objectif *lointain/baleine*, coût **×3 conservé** : le
    haut de courbe est **décoratif** assumé — le dernier +1 % coûte ~39 k frags). 12 slots buff/rareté →
    plafond **+120 %/rareté**, soit **+20 %/module** au max absolu et **~+10 %/module** en jeu normal ;
    **multiplicatif** avec Valo (+10 %/rang) et `moduleMult`.
  - **Signature = effet FIXE** (indépendant du niveau) : **réutilise les `passive`/`signature` existants**
    de `heroes.data.js` → accessible **tôt** (poser le héros = effet immédiat) + **pas de runaway** sur les
    effets qualitatifs (`costReduce`…). Monter un héros paie quand même via son **rôle de buffeur** sur les
    5 autres modules de sa rareté. Plafond module **+30 %** (sig +10 fixe + 2 buffeurs +10). Couche **buff =
    quantitatif grindé** / **signature = qualitatif stratégique**.

- **Gear — VERROUILLÉ (2026-06-25)** : **mix par slot** = **petit % de prod** (garniture, ~1-2 %/pièce —
  ne doit PAS écraser les héros ; sim : 9 pièces/module, à +5 %/pièce le gear dépasse les +30 % héros) **+
  1 effet qualitatif** d'un **pool capé**. **3 slots libres/héros** (non typés). **Robinet séparé** des héros
  (fragments gear distincts), même fusion **base-3 / classes C/R/É**. **Leveling** : l'effet scale
  linéairement/niveau vers son cap, coût **×3/niveau** (même auto-pacing que les héros).
  - **Pool qualitatif** : réduction de coût (verse dans le **cap 80 % global** existant de `costOf` ✅),
    gain hors-ligne (`offlineMult`, cap +100 %), plafond hors-ligne (`offlineCap`, +8 h), **trouvaille de
    fragments** (*neuf*, +50 %, **pont entre les 2 robinets** → caper serré), gemmes (`gemPriceMult`) ;
    clic/auto mineurs en option.
  - **Caps GLOBAUX par effet + rendement décroissant** → pousse à **diversifier** → c'est ce qui rend les
    **3 slots libres** intéressants (un portefeuille à composer, pas « équipe le plus gros »).

- **Robinet héros — VERROUILLÉ (2026-06-26)** : faucet **cash-gaté, pas temps-gaté** (découverte clé :
  `gemPrice()=perSecond×0,10` → 1 pull/200 gemmes coûte **toujours ~20 s de production**, à tout stade ;
  les gemmes ne sont pas rares, elles s'achètent au cash). Donc l'unité pertinente = **« heures de
  production-équivalent »**, pas « frags/jour ». **FPP=1** (1 fragment **ciblé**/pull) → **20 s de prod /
  fragment, constant pour toujours** (le self-pacing de `GROWTH`=1,15 est intégré gratis : le prix gemme
  suit la prod). Fusion **cumulée** `b^L` (coût pour ÊTRE au niveau L ; dernier palier `b^L−b^(L−1)`).
  Courbe résultante (buffeur C/R base 3) : 1er module satisfaisant (+10 %, 486 frags) ≈ **2,7 h prod-équiv**
  (~9 h @30 % du cash au gacha) · une rareté décente (2 916) ≈ 16 h · buffeur **niv10 MAX** (59 049) ≈
  **13,7 j prod-pure** (~46 j @30 %, *décoratif baleine* assumé) · 1 module MAXÉ (118 098) ≈ **27 j**. Aucun
  palier artificiel : juste `b^L × 20 s`. **Leviers de tuning** (décalent toute la courbe) : `FPP`,
  `PULL_COST`(=200), `GEM_T`(=0,10). Faucet **gear = passif/temps**, séparé (à caler en parallèle, pas
  encore chiffré).

- **Robinet gear — VERROUILLÉ (2026-06-26)** : faucet **passif/temps** (≠ héros cash-gaté), unité =
  **heures réelles**. Débit **PLAT = 80 frags/heure**, online **+ offline capé** comme le cash
  (`OFFLINE_CAP_H`=4 h base, étendable par les héros `offlineCap`). Texture voulue : héros = grind cash
  (scale avec l'engagement) / gear = « reviens chaque jour » (même débit pour tous). Pièce de gear :
  niveaux 1→8, fusion **cumulée base 3** (`3^L` frags pour ÊTRE niv L), effet prod **+1 %/pièce à max**
  (niv8 ; → **+9 %/module** = clairement **sous** les +30 % héros : garniture, le **pool qualitatif est la
  star**) + 1 effet qualitatif scalant vers son cap. Cadence calée **en parallèle** du faucet héros : 1er
  module gearé léger (9 pièces niv4, 729 frags) ≈ **9,1 h** = pile sur le « 1er module satisfaisant » héros ;
  gear MAXÉ (9 pièces niv8, 59 049) ≈ **31 j** → **le gear se complète, les héros portent la longue traîne.**
  **Séparation des 2 robinets** = monnaies distinctes (frags héros = gemmes/cash ; frags gear = temps) ;
  **seul pont** = la *trouvaille de fragments* du pool qualitatif gear (+50 %, **capé serré**, volontaire).
  Levier de tuning : `GEAR_RATE`(=80/h).

- **Migration des saves — VERROUILLÉE (2026-06-26)** : **soft-reset + crédit généreux** (philosophie A ;
  l'ancien et le nouveau modèle ont des **formes** trop différentes pour un port fidèle 1:1). Principe
  directeur : **1 ancienne copie = 1 nouveau fragment** (les deux coûtent 1 pull / 200 gemmes → conversion
  sans perte de valeur). Règles :
  1. **Héros possédés → placés au MÊME numéro de niveau** : un héros à l'ancien niv L (1→5) est re-crédité
     au nouveau niv L (`b^L` frags ciblés, b=3 C/R · 4 É), **1 copie en inventaire**. Préserve le numéro (pas
     de « j'ai chuté de 5 à 3 »), généreux (niv5 = 243 frags offerts vs ~15 copies investies), et les anciens
     maxés deviennent **mid-tier** (niv5/10) → **niv6→10 = la nouvelle traîne**.
  2. **Éclats fongibles (`state.shards`) → gemmes** : `200/SHARD_PER_COPY` gemmes/Éclat (Commun **25** ·
     Rare **~33** · Épique **50**). La fongibilité ne survit pas en ciblé → monnaie universelle.
  3. **`state.gems` conservées** telles quelles.
  4. **Gear démarre à zéro** (faucet passif se remplit dès la migration) + option petit pack « bon retour ».
  5. **Retirés** : `state.lvl` + fusion `fuseCost=niv+1`, `craftHero`, `SHARD_PER_COPY`/`state.shards` →
     remplacés par les stocks de fragments (héros ciblés + gear).

**→ Design méta COMPLET (placement, buffeur/signature, gear, les 2 robinets, migration) — prêt à coder.**

- **Démontage de l'ancien système — ✅ FAIT (a + b), 2026-06-26** (slice c restante). Slices testées
  (navigateur Chromium) + poussées une par une :
  - **(a)** Effets héros **FIXES** : passifs (`moduleMult`/`globalHeroFx`/`costOf`) + compétences actives
    (`triggerSig`) calculés à **niveau=1** (valeur de base, plus de scaling). = « signature = effet fixe ».
  - **(b1)** **Gacha RNG retiré** : onglet 🎲 + écran + `pullOnce`/`pull`/`epicProb`/`DROP`/`HEROES_BY_TIER` +
    collection. Acquisition héros = invocation ciblée de fragments. `PULL_COST` conservé. ⚠️ Champs
    `pity`/`dropBoost`/`freePullNext` vestigiaux ; **signatures `freePull`/`dropBoost` désormais inertes** (à redesigner).
  - **(b2)** **Éclats retirés** : balayage des doublons morts (les doublons = copies utiles), `craftHero` +
    bouton Fabriquer, barre d'Éclats du Codex, branches Éclats des objectifs. `SHARD_PER_COPY` conservé pour
    la migration shards→gemmes uniquement.
  - **(b3)** **Ancienne fusion + niveaux retirés** : `fuse`/`fuseCost`/`heroLvl`/`maxLvl`/`dupesOf`/`shardsOf`/
    `SHARD_LABEL` + bouton `mpFuseBtn` (page module) + affichage de l'ancien niveau. Page module : héros montre
    désormais buffeur niv + déploiement (signature). Objectif « max1 » repointé (buffeur niv 10, récompense
    gemmes). `state.lvl`/`state.shards` **conservés en données** UNIQUEMENT pour `migrateMetaV2` (vieilles saves).
  - **(c)** ✅ **FAIT (2026-06-26)** : parcours validé **intégré dans la vraie fiche Codex** + **onglet Atelier
    temporaire retiré**. La grille du Codex = le sélecteur ; cliquer un héros ouvre sa fiche (lore + surnom) avec
    le **workshop** en dessous (conteneur `#atlWorkshop`). `atelierHero` suit `ficheId` ; `renderAtelier`/
    `buildAtelierWorkshop`/`updateAtelierWorkshop` conservés (build-once + update-in-place = clics fiables).
    Retiré : `#atelierScreen`, onglet `data-nav="atelier"`, `openAtelier`/`buildAtelierPicker`/picker+chips,
    l'ancien bloc buffeur inline de la fiche (`ficheBuffBlock` et ses boutons/listeners). Testé navigateur
    (parcours complet dans la fiche + changement de héros), `node --check` OK.
  - **Signatures gacha redesignées — ✅ FAIT (2026-06-26)** : **Richard Brunson** (Épique) sig « Lancement » →
    burst **prod ×2,5 global / 20 s** (passif −prix gemmes gardé) ; **Pieter Thielo** (Rare) passif → **×1,3 prod
    de son module**, sig « Levée de fonds » → **+75 s de prod en cash**. Effets réutilisant des kinds/types déjà
    supportés (prod/cash/gemPriceReduce/mult). Kinds morts `freePull`/`dropBoost` + case `freePullChance` retirés
    du moteur. **`heroes.data.js?v=8→9`** (cache-bust). Champs `pity`/`dropBoost`/`freePullNext` restent vestigiaux.
  - **`copyCost` rééquilibré — ✅ FAIT (2026-06-26)** : remplacé le coût PLAT (`base²`, étaler = trivial → tension
    largeur cassée) par un coût **escaladant** `base^(copies+1)` : C/R = 3·9·27·81·243·729 (6 copies = 1092 ≈ niv 6-7
    de profondeur) ; Épique base 4. 1ʳᵉ copie bon marché (accessible), spread large = vrai investissement → tension
    profondeur/largeur rétablie. Vérifié navigateur (escalade 3→9→27→81). **TUNABLE** (base + exposant).
  - **Reste** : playtest d'équilibrage global (la courbe `copyCost` peut encore se régler).

#### Bloc 4 — Gear (en cours, sous-slices)
- **4a — ✅ FAIT (2026-06-26)** : **faucet gear passif**. `state.gearFrags` accrue à `GEAR_RATE`(=80)/h —
  **online** (dans `loop()`, `+GEAR_RATE/3600×dt`) **+ offline plafonné** (dans `load()`, `+GEAR_RATE/3600×eff`,
  même plafond `OFFLINE_CAP_H`=4h × `offlineCapMult` que le cash). Fondation isolée, **pas d'UI/dépense encore**
  (comme le bloc 1). Vérifié navigateur : online monte ; offline 2h=160, 6h=320 (plafonné 4h). node --check OK.
- **4b — ✅ FAIT (2026-06-26)** : **gear par-HÉROS** (décision validée : pas par-copie ; plus simple, garniture).
  `state.gearLvl`{heroId:[s0,s1,s2]} — 3 slots/héros, niv 0→8, leveled avec le faucet `gearFrags` (fusion cumulée
  base 3, `gearSlotCost(L)=3^(L+1)−3^L`). `gearBonus(id)`=`Σslots×0,01/8` (max **+3 %/héros**, +1 %/slot à niv8).
  Effet branché : `moduleBuffMult` ajoute `gearBonus` des buffeurs placés ; `moduleMult` ajoute le gear de la
  **signature** (héros-maison déployé). UI : étape **« 4️⃣ Équiper »** dans le workshop fiche (3 slots, coût/niv/
  bonus, 🛠️ dans la ligne de stats). Chiffres collent au design : 1 slot maxé ≈ 6,5k frags ≈ 82 h ; 3 slots ≈ 10 j ;
  module (9 slots) ≈ 59k ≈ 31 j. Testé navigateur (escalade 2→6→18, niveau, bonus, dépense) + `node --check` OK.
- **4c — ✅ FAIT (2026-06-26)** : **pool qualitatif** (la star du gear). `state.gearFx`{heroId:[fx0,fx1,fx2]} —
  **1 effet au choix par slot** (slots non typés). Pool `GEAR_FX` (5 effets, **TUNABLE**) : `cost` (−coût, perSlot
  2 %, cap 40 % → verse dans le cap 80 % de `costOf`), `offmult` (+gain offline, 10 %, cap 100 %), `offcap`
  (+plafond offline, 1 h, cap 8 h), `frag` (+trouvaille de frags, 5 %, cap **50 %** = pont serré entre robinets),
  `gem` (−prix gemmes, 5 %, cap 50 %). Magnitude/slot = `niveau/8 × perSlot` ; `gearQual()` = totaux globaux
  **cappés par effet** (somme tous slots tous héros) → pousse à diversifier. Branchements : `costOf` (`reduce +=
  gq.cost`), offline `load()` (`×(1+gq.offmult)` + `cap += gq.offcap`), `pullFrags` (`×(1+gq.frag)`), `gemPrice`
  (`×(1−gq.gem)`). UI : `<select>` d'effet par slot + contribution + ligne « Pool qualitatif (global, cappé) ».
  Testé : gearQual + caps (12 slots frag → 0,50), frag end-to-end (invoke ×10 → 10,5 frags bruts). node --check OK.

**→ Bloc 4 (Gear) COMPLET : faucet passif (4a) + 3 slots/effet prod (4b) + pool qualitatif capé (4c).**

### ⏳ Chantier À VENIR — réorganisation de l'affichage (UX, demandé 2026-06-26)
Le système méta est complet **fonctionnellement**, mais l'**affichage est à réorganiser** (priorité du joueur).
Pistes identifiées (à préciser avec lui avant de coder) : la **fiche Codex est devenue longue** (lore + 4 étapes
empilées : Invoquer/Renforcer/Placer/Équiper) → regrouper/replier les étapes ? · **ligne de stats `atlStat`**
très longue (💵💎🧬🛠️ + buffeur + copies) → condenser · hiérarchie visuelle générale · éventuellement l'écran
module. **Pas de cap design verrouillé encore** : partir de ce qui le gêne le plus. Rien n'est cassé, c'est
purement de la mise en forme.

### Parcours de création de héros — DANS LA FICHE CODEX (2026-06-26)
Le parcours simplifié (ex-« Atelier ») vit maintenant **dans la fiche du Codex** (`#atlWorkshop`, sous le lore
du héros) : **1️⃣ Invoquer** (acheter gemmes au cash + invoquer fragments) · **2️⃣ Renforcer** (Fusionner = +1 %/niv
*ou* Forger une copie, avec progression « X / Y · manque Z » sous chaque bouton) · **3️⃣ Placer** (modules de même
rareté, 2 slots). Fonctions `renderAtelier`/`buildAtelierWorkshop`/`updateAtelierWorkshop` ; un seul listener
délégué sur `#atlWorkshop` (boutons `data-atl`). Structure **construite une fois par héros** (anti-reconstruction
du game loop 10×/s → clics fiables), valeurs mises à jour ensuite.

### Implémentation par blocs (en cours)
Découpage livrable, pas de big-bang : (1) **Migration + stockage des fragments** → (2) **Fusion ciblée +
buffeurs** (cœur jouable) → (3) **Signatures + placement par module** → (4) **Gear + faucet passif + pool
qualitatif** (le plus lourd, en dernier).
- **Bloc 1 — ✅ FAIT (2026-06-26)** : socle **non-breaking** dans `index.html`. Constantes
  `META_VERSION`, `FUSION_BASE`(C/R=3·É=4), `BUFFER_MAX_LVL`(=10), `GEAR_RATE`(=80) ; helpers
  `fusionBase`/`fragsForLevel`(=base^L)/`rarityOf`. Stocks neufs dans `defaultState` : `state.heroFrags`{},
  `state.gearFrags`(0), `state.metaV2`(0). Migration one-shot `migrateMetaV2()` (gardée par flag `metaV2`,
  appelée dans `adopt()` après finalisation des Éclats) : héros possédés → `b^L` frags ciblés au même niveau ;
  Éclats → gemmes (`200/SHARD_PER_COPY`) puis vidés ; gear à 0. **L'ancien système (heroes/lvl/fusion/craftHero)
  reste intact et jouable**. Testé + `node --check` OK. Cloud round-trip OK (pas de bump `?v=`).
- **Bloc 2 — ✅ FAIT (2026-06-26)** : boucle **fragment ciblé → fusion → buffeur**, toujours **non-breaking**
  (source de bonus ADDITIONNELLE ; l'ancien placement/passifs/signatures reste intact — le bloc 3 réorganisera
  et retirera l'ancien). Ajouts `index.html` : champ `state.bufferLvl`{} (niveau 0→10) ; `META_VERSION`→**3** +
  migration étagée dans `adopt()` (`<2`→V2, `<3`→V3) ; `migrateMetaV3()` convertit le stock `heroFrags` du bloc 1
  en **niveaux de buffeur** (auto-fusion jusqu'au plus haut niveau finançable, reliquat gardé → un héros migré
  retrouve EXACTEMENT son ancien numéro de niveau, honore le « déjà au niveau L »). Helpers `bufferLvl`/
  `bufferStepCost`(=`b^(L+1)−b^L`)/`heroFragsOf`/`buffMult`(=`1+Σmin(lvl,10)×0,01`). Gacha **ciblé déterministe**
  `pullFrags(id,n)` (1 frag/200 💎, zéro RNG) + `fuseBuffer(id)` (dépense les frags, +1 niv). `buffMult()` branché
  dans `perSecond()` (`×valoMult×buffMult`). UI : bloc « Buffeur » dans la fiche héros (niveau, stock, ×1/×10
  invoquer, Fusionner, buff global cumulé). Testé (migration exacte+idempotente, stock partiel, fusion, cap niv10,
  pullFrags) + `node --check` OK. Cloud round-trip OK (pas de bump `?v=`). ⚠️ **Effet appliqué GLOBALEMENT** en
  interim (pas encore par-module) ; les héros migrés gagnent `+Σniveaux %` de prod globale immédiate (crédit de
  leur ancien investissement) — **le bloc 3 localisera** le buff aux slots de module + ajoutera les signatures.
  L'ancien gacha RNG (héros entiers) **coexiste encore** ; il sera retiré quand le placement V2 sera en place.
- **Bloc 3 — ✅ FAIT (2026-06-26)** : **placement par module + copies**, le buff devient **LOCALISÉ**. Décision
  prise en autonomie (« même procédure ») sur le seul point non spécifié — **d'où viennent les copies** : choix
  **A = copies forgées avec des fragments** (même monnaie que les niveaux → tension profondeur vs largeur ;
  cohérent avec « gacha = fragments »). Ajouts `index.html` : `state.bufSlots`{moduleId:[heroId,heroId]} (2 slots
  buffeurs/module, **placement GLOBAL** tous Dex) ; helpers `copyCost`(=`base²`, 9 C/R · 16 É — **TUNABLE**)/
  `copiesOwned`/`copiesUsed`/`copiesFree`/`mintCopy`/`toggleBuffer`/`moduleBuffMult`/`slotsOf`/`isPlacedOn`.
  `buffMult()` **GLOBAL retiré** de `perSecond` → remplacé par `moduleMult ×= moduleBuffMult(n.id)` (= `1 + Σniv
  buffeurs placés ×0,01`). `META_VERSION`→**4** + `migrateMetaV4()` : auto-place chaque héros niveauté sur le
  slot de **son module-maison** (continuité du buff bloc 2 → pas de chute de prod à la bascule ; consomme 1 copie ;
  idempotent). UI fiche : stock de copies + libres + « Forger une copie », et **liste de placement** (les modules
  de même rareté, toggle Placer/Retirer, garde-fous rareté/slots-pleins/copie-libre). Testé (forge, placement,
  rareté, slots, buff localisé, retrait, migration V4 + idempotence) + `node --check` OK. Cloud round-trip OK
  (pas de bump `?v=`). ⚠️ **Interim restant** (raffinements design, pas encore codés) : **signature = effet FIXE**
  (pour l'instant le héros-maison déployé garde ses **passifs niveautés** existants = la « signature » ; à figer) ;
  **retrait de l'ancien gacha RNG** + des passifs-mults niveautés ; rééquilibrage du `copyCost`.

## Tâches en attente / roadmap

1. ~~**NPC réactif (L3b)**~~ — ✅ FAIT (`economy_l3b.sql`). Le cours bouge tout seul.
2. ~~**Régime → effet héros (famille G)**~~ — ❌ **RETIRÉ le 2026-06-24** (dépendait du cours Exchange ; pivot 100 % Idle). Le champ `regime` des héros reste en données (`heroes.data.js`) pour un éventuel réemploi **idle-natif** (ex. cycle déterministe piloté par l'horloge UTC, sans backend). Si réintroduit : repartir d'un `regimeProdMult()` local + rééquilibrer les affinités (BULL 6 / CRASH 3 / CRABE 3 / HYPE 3 / BEAR 1 / Quant 2 — BEAR trop faible).
3. **Levier (L5)** — positions, marge, moteur de liquidation au tick, funding. Attend design liquidation + « go ».
4. **Frais custody + funding** (différés).
5. **Les 17 autres activités de module**.
6. **Couche progression** — ✅ **Valorisation** (soft-prestige sans reset) + ✅ **Objectifs** (jalons one-shot) FAITS.
   Reste : **Quêtes** (tâches dirigées, **reset quotidien UTC** — horloge déjà en place ; c'est ici que vit le
   **sink récurrent** « dépense X »). Pistes : gater des déblocages sur le rang Valo ; équilibrer la liste d'objectifs.

### Refonte progression — EN CONCEPTION (demandé 2026-06-26, à coder)
Direction validée en discussion (mode critique). Trois chantiers, tous **idle-natifs** :
- **A. Quêtes = milestones SIMPLES RECYCLABLES** (à faire en 1er). Remplacer les Objectifs **one-shot écrits à la
  main** (`OBJECTIVES`, hand-authored) par un système **templaté** : définir un *type* de milestone (« atteindre
  X prod/s », « connecter Y modules », « fusionner Z buffeurs », « atteindre rang Valo R »…) et le **recycler à
  seuils croissants** → progression **infinie sans hand-authoring**. Branche le **sink récurrent** (reset
  quotidien UTC, horloge déjà là). Garder le latch one-shot pour les jalons uniques ; les recyclables ont un
  compteur de palier qui monte. **Avantage** : remplace la liste figée par une courbe auto-générée + tunable.
- **B. Prestige DUR (avec reset)** — *manque vraiment*. Valo = soft-prestige **sans** reset (mid-game). Ajouter
  un **vrai prestige endgame** : reset (cash/modules/Dex ?) contre une **monnaie de multiplicateur permanente**
  → boucle idle classique. Valo reste la couche mid-game, le prestige dur la couche endgame. À spécifier (quoi
  reset, quoi garder — héros/fragments/gear probablement gardés, cash/niveaux modules reset).
- **C. Barre de progression / XP = COUCHE D'AFFICHAGE**, pas une nouvelle mécanique. ⚠️ **Anti-doublon** : la
  Valorisation EST déjà le « niveau joueur ». Une barre XP doit **visualiser** l'existant (rang Valo + objectifs
  atteints + prod), donner du *juice*/feedback — **sans** créer une 2ᵉ piste mécanique redondante.

### 🌍 SYNCHRO ENTRE JOUEURS + 🎰 MARGIN CALL — **EN COURS (2026-06-27, branche `claude/player-sync-solution-rsb0q5`)**

> **Phase 1 (`world()`) + Phase 2a/2b (Margin Call) FAITES & poussées.** Reste le **checkpoint de
> tuning** (calage des leviers feel-critiques) + polish réputation/UX. Décision : « synchroniser les
> joueurs entre eux » = **cycle déterministe sans backend** (le choix 100 % idle ; rien à stocker, rien
> à falsifier). Margin Call en est le 1ᵉʳ consommateur.

- **Phase 1 — `world(utc)` (FAIT)** : fonction **PURE** de l'horloge UTC dans `index.html` (PRNG mulberry32
  seedé par **époque** = `floor(utc/WORLD_CYCLE_MS)` + 5 régimes pondérés `REGIMES` + **hystérésis Markov
  bornée** `WORLD_LOOKBACK`). Tous les clients calculent le **même régime au même instant** → synchro
  « entre joueurs » **sans qu'aucune donnée ne circule**. Renvoie `{key,label,emoji,color,since,until,next}`.
  **Bandeau météo** `#worldBar` sous la topnav (régime · fin de run UTC · suivant), rafraîchi /s. Exposé
  `window.DEX.world`. **NON-BREAKING** : affichage seul, n'agit PAS sur la prod (l'ancien régime→prod
  reste retiré). Constantes **PROVISOIRES** (`WORLD_SEED`, `WORLD_CYCLE_MS`=20min, `WORLD_STICKY`=0,62,
  poids des régimes). Mesuré : durée moy d'un régime ~68 min, **98 % des sessions de 4 h croisent ≥2 régimes**.
- **Phase 2a — socle Margin Call (FAIT)** : `state.mc {rep, session, lastResult}` **OFF par défaut**
  (session null = idle pur intouchable). Module pilote **Bourse `a1t0`**, **moteur abstrait** (allocation ×
  durée × régime → gemmes, pas de knapsack). `mcAdvance` intègre la session **par paliers de régime**,
  online (`loop`) **et hors-ligne** (`load`, **NON capé** = responsabilité assumée) → déroulé identique
  (régime déterministe). `mcLaunch`/`mcCollect`/`mcProject`. Margin call = carburant épuisé → pause ;
  fin de durée → clôture auto (rend le carburant non brûlé). On ne perd **que le carburant misé**, jamais
  sous la base. Caps alloc/durée **indexés prod + repoussés par la réputation** (+50 %/palier) ; réputation
  = gemmes gagnées (cumul, **interne**, pas un mult global). Éco **PROVISOIRE** calibrée net-positive
  (`MC_BURN`/`MC_YIELD`/`MC_BURN_BASE`=0,8 → ~×1,16 vs achat direct sur cash consommé, ~28 % de margin call
  aux réglages max).
- **Phase 2b — UI (FAIT)** : onglet 🎰 + écran `#margincallScreen` (météo, sliders alloc×durée, **projection
  live**, panneau session actif/blown, collecte). Listeners attachés une fois ; `renderMarginCall` met à jour
  les valeurs seulement (sliders non clobberés par le game loop 10×/s).
- **RESTE** : **checkpoint de tuning** (4 leviers feel — vitesse du cycle/poids régimes, courbe entretien/régime,
  conversion alloc→gemmes/net-positif, caps réputation) à valider **avec le joueur** ; polish réputation
  (afficher le palier) + UX.

### 🎨 REFONTE UI (« app mobile ») + PUMP + simplification — **EN COURS (2026-06-27, même branche), poussé sur `main` au fil de l'eau**
Bascule d'une longue colonne vers une **app à nav du bas + page d'accueil (Lobby) = hub d'action**. Tout poussé
live sur `main` (le joueur teste en PWA « écran d'accueil »).
Tout testé navigateur (Playwright, viewport ~402×874) + `node --check`. **`cloud.js?v=25`**.

- **Shell** : **en-tête permanent 2 rangées** (`.appheader` flex column) — R1 avatar + pseudo + (rang Valo
  `×mult` · prod/s) + **☁️ compte** (injecté par `cloud.js` dans `#cloudSlot`, **logé dans la modale ⚙️**) + **⚙️
  Réglages** ; R2 chips **💵 cash** · **💎 gemmes (bouton → modale d'achat `#gemsOv`)** · **📈 Promotion** (Valo,
  sortie des réglages, pastille « abordable »). **Nav du bas flottante** `.bottomnav` (5 dest. : Cash Flow ·
  Objectifs · **Lobby 🏠** · Inventaire · Atelier ; remontée ~22px du bas). **⚙️ Réglages** = Sauver / Réinitialiser
  + **🔄 Mettre à jour** + compte. `showScreen` gère `lobby/overview/module/heroes/objectives/inventaire/margincall`
  (navKey pilote la surbrillance ; écrans internes ne la changent pas).
- **🏠 LOBBY = hub d'action** (billet + Pump + compétences + Margin Call, **uniquement ici** ; le billet
  n'apparaît plus ailleurs). Mise en page **flex robuste** : `body { min-height:100dvh; display:flex; flex-direction:column }`
  + `.appmain { flex:1 1 auto }` → l'écran remplit la hauteur, boutons poussés en bas (`margin-top:auto`) **quand ça
  tient**, et le **document scrolle nativement quand ça dépasse** (cf. correctif scroll ci-dessous).
- **PUMP (`pumpGauge`/`pumpMult`/`pumpTap`/`pumpDecay`)** : taper le billet remplit la jauge (~8 taps,
  redescend sinon) ; **multiplicateur VIVANT sur la prod** selon le palier (×2/×3/×5), **sommet → ×10 verrouillé
  30 s** (`pumpLockUntil`) puis réarmement. `perSecond ×= pumpMult()` (hors indice base du prix gemme). 100 %
  optionnel. **Effet « MAX ! »** spectaculaire au sommet (`crashEffect`) : **flash plein écran** `#crashFx` +
  **secousse** `.appmain.shake` + **gros texte « 💥 MAX ! PRODUCTION ×10 »** (anim ~2,3 s). Constantes
  `PUMP_PER_TAP`/`PUMP_DECAY`/`PUMP_LOCK_MS`/`PUMP_PALIERS` **PROVISOIRES**. (Audio à ajouter plus tard.)
- **⚡ Compétences groupées** : **un seul bouton** (Lobby) déclenche toutes les signatures prêtes des héros
  déployés (`fireAllSkills`) ; ancienne barre d'abilities retirée. **Pastilles rouges = action POSSIBLE,
  ÉTEINTES par défaut** (`updateDots`/`setDot`), calculées à la volée (jamais décoratives).
- **Simplification décidée (2026-06-27)** : héros **actifs gardés** · profondeur **+ largeur gardées** · **GEAR
  APLATI** → bonus de prod **passif auto** (`state.gearTier`/`gearMult`/`gearTierCost`/`gearAutoLevel` ; +1 %/palier,
  les `gearFrags` s'investissent seuls online+offline). **Retirés du jeu** : slots de gear, pool qualitatif,
  étape « Équiper » du workshop ; `gearBonus`/`gearQual` neutralisés. Bonus affiché dans ⚙️. **TUNABLE** (`GEAR_STEP`).
- **Split 📦 Inventaire / ⚗️ Atelier (mapping A possession/fabrication)** : Inventaire = héros **possédés**
  (`renderInventaire`, clic → fiche) ; Atelier = l'ancien écran Codex (grille 18 → fiche + workshop 3 étapes
  Invoquer/Renforcer/Placer). `openInventaire`/`#inventaireScreen`.
- **Cash Flow compacté** : les **18 modules tiennent sur un écran** (titre/hint retirés, cartes/marges serrées,
  synbar masquée si vide), écart Dex↔grille élargi, + **bouton 🤖 Auto-achat ON/OFF** placé sous la grille
  (espace au-dessus de la nav, via flex).
- **À VENIR** : **TUTO** (guidé & sautable — voir plus bas) ; le joueur retravaille **l'affichage Inventaire/
  Atelier** ; checkpoint de tuning Margin Call + Pump ; **audio** (Pump/MAX, à concevoir).

#### 🔧 PWA auto-update + scroll natif — ✅ FAIT (2026-06-27, fin de session UI)
Bloc de **correctifs mobiles/PWA** débogués avec le joueur (captures iPhone à l'appui) :
- **Auto-update de la PWA** — ✅ : la PWA « écran d'accueil » iOS restait **figée sur l'`index.html` en cache**
  (ni `location.reload()` ni cache-bust ne suffisent en standalone). Ajout d'un **service worker `sw.js`
  « réseau d'abord »** (récupère la version fraîche en ligne à chaque ouverture, cache = hors-ligne seulement,
  `skipWaiting`+`clients.claim`, purge des vieux caches) + enregistrement dans `index.html` + **`manifest.webmanifest`**
  (standalone, scope) + meta `apple-mobile-web-app-*`/`theme-color`. **Bouton 🔄 Mettre à jour** = rechargement
  **anti-cache** (sauve, purge `caches`, recharge avec `?v=Date.now()`). ⚠️ **Bootstrap** : une réinstallation
  unique de l'icône est nécessaire pour poser le SW ; ensuite les MAJ arrivent **toutes seules** (juste fermer/rouvrir).
- **⚠️ `viewport-fit=cover` RETIRÉ** : ajouté par erreur avec le SW, il étend le contenu bord-à-bord → en standalone
  iOS `100dvh` dépassait la zone visible et **poussait le bas hors écran** (bouton 🤖 Auto de Cash Flow sous la nav).
  Retour à l'inset auto du navigateur + `apple-mobile-web-app-status-bar-style: black`.
- **⚠️ SCROLL — retour au scroll NATIF du document (revert ciblé de `82de532`)** : le commit qui a créé la bascule
  Buffeur/Copies avait aussi basculé le shell en **« app figée »** (`body { height:100dvh; overflow:hidden }` +
  **scroll interne `.appmain { overflow-y:auto }`**). Ce **scroll interne clippe en PWA iOS** quand le dépassement
  est faible (liste atelier, fiche buffer = contenu coupé **et** non défilable ; copies marchait car gros dépassement).
  **Fix = restaurer l'avant-`82de532`** : `body { min-height:100dvh }` (le **document scrolle nativement**, robuste
  iOS), `.appmain`/`#screensPanel` **sans** `overflow`/`min-height:0`, atelier en **flux naturel** (`flex:0 0 auto`,
  toggle en `margin-top` normal). **Header `sticky` + nav `fixed`** restent en place. **Leçon retenue (consigne joueur)** :
  quand une modif ne règle pas le souci, **remonter au commit responsable / revert** plutôt qu'empiler des correctifs.

#### 📜 QUÊTES QUOTIDIENNES — ✅ FAIT (2026-06-27)
Branche le **sink récurrent / boucle de retour quotidienne**, **complémentaire** des Objectifs 🎯 (qui restent des
paliers d'**état** permanents recyclables). Décisions verrouillées avec le joueur :
- **« Faire X aujourd'hui »** (compteurs du jour) qui **RESETENT à 00:00 UTC** (`dailyDayKey = floor(Date.now()/86400000)`,
  donc minuit UTC pile, du jour au lendemain comme demandé). **3 quêtes/jour**, **set DÉTERMINISTE & PARTAGÉ**
  (`dailyPick(day)` via `mulberry32` seedé sur le jour → **mêmes 3 quêtes pour tous les joueurs**, prolonge le thème
  synchro `world()`, zéro backend).
- **Pool `DAILY_POOL`** (`DAILY_BY_KEY`) : `earn` (🏭 produire — **toujours incluse = garantie 100 % IDLE**), `upg`,
  `buff`, `maxp`, `frags`, `spend`, `mc`. Deux types de suivi : **`base`** = différentiel sur stat monotone
  (`cur()-baseline` figé au reset ; ex. `totalLevels`/`totalBufferLevels`/`pumpMaxCount`) · **`counter`** = compteur
  incrémenté en jeu via `dailyAdd(key,amt)` (hooks : `loop` & `load`→`earn`, `pullFrags`→`spend`+`frags`, `mcLaunch`→`mc`).
  Cibles **figées au reset** (les prod-indexées via `perSecond()` au moment du reset → pas de goalpost mobile).
- **Récompense** : 💎 par quête + **coffre bonus 3/3** (`DAILY_BONUS`=400 💎). Amorçage **silencieux** des vieilles saves
  (`rollDaily` pose baselines/compteurs à 0 → rien crédité d'office). `state.daily = {day,keys,tgt,base,prog,claimed,bonus}`.
- **UI** : petit bouton **📜** flotté en haut-droite du Lobby (`.daily-btn`, sous la météo, proche du bord, `#dotDaily`
  rouge si réclamable) → **modale `#dailyOv`** (compte à rebours reset UTC + 3 lignes `.qrow` + coffre). **Build-once +
  update-in-place** (`buildDaily`/`renderDaily`, `dailyBuiltFor`) pour clics fiables sous le game loop 10×/s.
- **TUNABLE** : `DAILY_POOL` (cibles/récompenses), `DAILY_BONUS`. **PROVISOIRE** (à playtester). ⚠️ Le joueur note que
  **les quêtes quotidiennes pourraient rendre le tuto inutile** (fil conducteur naturel) — à réévaluer à l'usage.

#### 📊 FRISE DE PRÉVISION MÉTÉO — ✅ FAIT (2026-06-27) + météo rendue NON-PERSISTANTE
- **Frise** : `forecastBlocks(horizonMs)` (blocs de régimes **contigus** de maintenant à +horizon via `world()` qui
  donne `since/until` par bloc) + `renderForecast(el, horizonH, sessionH)` (flex inline, largeur ∝ durée, couleur/emoji
  `REGIMES`, marqueur **« maintenant »**, heure UTC sur blocs larges, `title` au survol). Déterministe (mêmes régimes
  futurs pour tous) · sans lib · lecture locale.
- **Lobby** : frise 8 h read-only (`#lobbyForecast`, haut de `#lobbyScreen`, `margin-right:56px` pour dégager le 📜).
  **Margin Call** : frise (`#mcForecast`) avec **overlay vert** = fenêtre de session (`sessionH` = durée du slider, ou
  restante si en cours) → on **voit quels régimes la session traverse** ; horizon adaptatif `max(8, ceil(durée+1))`.
- **⚠️ Météo NON-persistante (demandé)** : `#worldBar` ne s'affiche **plus partout** → **uniquement Lobby + Margin Call**
  (toggle dans `showScreen`). Ligne `#mcWeather` (doublon du worldBar sur MC) **retirée**.
- **🥈 COURBE DE RISQUE Margin Call — ✅ FAIT (2026-06-27)** : `mcFuelCurve(alloc,durSec,startMs,endMs,fuel0)`
  échantillonne le carburant aux frontières de régime (mêmes formules que `mcAdvance`/`mcProject`) → série de points ;
  `renderRiskCurve(el,horizonH,curve)` trace un **SVG inline** (polyline + aire, `vector-effect:non-scaling-stroke`)
  sous la frise (`#mcRiskCurve`), **même axe de temps**. Vert « tient la durée ✓ » / rouge + marqueur + ⚠️ « Carburant
  épuisé vers HH:MM UTC » si margin call. **Décision : Margin Call reste à UNE session** (multi-session = idée bornée par
  réputation, repoussée). **Zoom MC** : frise + courbe en horizon **= durée de session ×1,15** (le Lobby garde 8 h) → les
  deux remplissent la largeur et restent alignées même pour une session courte. Insight exposé : temps avant rupture ≈
  `durée/(MC_BURN×0,8)` **indépendant de l'alloc** → le risque vient du **régime traversé**, pas de la taille du pari.
- **RESTE (dataviz, pas codé)** : décomposition de la prod · courbe de richesse · ROI du prochain achat · récap hors-ligne.

#### 📊 (archive) IDÉES DATAVIZ — discutées le 2026-06-27
Idées de **visualisations** pour le joueur (thème finance → très naturel). **100 % idle** (affichage seul, n'exige
aucune action) ; **faisable en SVG/canvas inline, sans dépendance** (jeu vanilla). À ranger dans un onglet/écran
**📊 Stats** pour ne pas alourdir le Lobby. ⚠️ **Garde-fou** : lire l'**état LOCAL** uniquement (honnête, non
comparatif) — **pas** de classement de prod temps réel (rouvrirait la boîte online/anti-triche fermée au pivot).
Par ordre de valeur estimée :
- **🥇 Frise de PRÉVISION météo de marché** — *la pépite* : `world()` est une **fonction pure du temps UTC** → le jeu
  **connaît déjà les régimes futurs**. Afficher les **6–12 prochaines heures** de régimes (frise horodatée UTC). Unique
  (aucun autre idle ne peut le faire honnêtement) + rend **Margin Call lisible** (« Krach dans 40 min → session courte »).
- **🥈 Courbe de RISQUE Margin Call** — avant lancement, tracer le **carburant dans le temps** superposé au calendrier
  des régimes → on **voit** la fenêtre où le carburant peut toucher 0. Données déjà calculées (`mcProject`).
- **🥉 Décomposition de la PRODUCTION** — camembert/barre empilée : part de Valo / buffeurs / gear / Pump / par module /
  par Dex. Répond à « d'où vient mon argent ? » et oriente les achats. (Lecture directe des facteurs de `perSecond()`.)
- **Secondaires** : courbe de **richesse** (cash cumulé / prod-s, sparkline vivante — demande un historique léger à
  bufferiser) · **ROI du prochain achat** par module (« +X $/s pour Y $ → temps de retour », visualise le mur `1,15^N`) ·
  **récap hors-ligne** en mini-graphe dans la modale « Bon retour ».
- **Repère maths** (contexte de ces graphes, cf. discussion) : deux exponentielles opposées (`GROWTH=1,15` vs empilement
  multiplicatif) · **prix indexé prod** (`gemPrice=perSecond×0,10` → coûts ≈ constants en « secondes de prod ») ·
  perception **log** (rangs Valo ×8, tiers rep `log2`) · **hasard déterministe** (`world()`/quêtes = PRNG seedé sur le
  temps + Markov à hystérésis) · Margin Call = **ruine du joueur** (EV net ~×1,16, ~28 % de margin call aux réglages max).
- **Repère implémentation** suggéré (si on code) : commencer par **frise prévision + courbe de risque Margin Call**
  (même source `world()`, fort impact gameplay, très « finance »), puis décomposition de prod.

#### Tuto — design validé (2026-06-27, à coder) — ⚠️ peut-être SUPERFLU avec les quêtes quotidiennes (à réévaluer)
**Guidé & sautable.** **Bulle à chaque étape** du cycle cœur (~8 gestes, une fois), puis **un pop contextuel**
la 1ʳᵉ fois pour les systèmes optionnels/avancés. **Cycle cœur** : 🏠 billet/Pump → 🔗 connecter+améliorer un
module → 💎 acheter gemmes → ⚗️ invoquer→fusionner→placer un héros → 📈 prendre une Valo → (clôture « les 🔴 te
guident »). **Découvertes contextuelles** (un pop) : ⚡ compétences, copies (largeur), 🎰 Margin Call, 📦 Inventaire.
Le gear n'est **plus une action** (bonus passif) → hors tuto. Technique : machine à états `state.tuto`, surbrillance
+ bulle, avance au **vrai geste**, vieilles saves `tuto.done=true` en silence (cf. `seedObjectives`).

---

### 🎰 MARGIN CALL — design verrouillé (conception d'origine, 2026-06-26) — *implémenté ci-dessus*
Réconciliation des mini-jeux avec le cap **100 % IDLE** : au lieu de cliquer (actif), on **alloue du cash** (passif).
Le skill = **dosage stratégique** d'une décision qu'on pose et qui tourne ensuite seule. (Les docs Banque=knapsack /
Bourse=assignment peuvent devenir l'**activité passive sous-jacente** du module, résolue auto, nourrie par l'allocation.)

**Boucle (le cœur) :**
- **OFF par défaut = LE coup de maître** : mini-jeu éteint ⇒ **totalement hors système** (zéro conso, zéro régime,
  zéro risque). L'idle-pur qui n'y touche jamais n'est **JAMAIS** affecté. Le risque n'existe **que** sur un
  **lancement délibéré** → *« idle pur par défaut + pari actif opt-in »*. Pilier idle intouchable.
- Le joueur **LANCE une session** : il choisit **durée × allocation (cash) × moment**, jusqu'à des **CAPS**.
- Pendant la session : le cash alloué est **consommé** pour entretenir l'activité passive du module, à un **taux
  variable piloté par le RÉGIME de marché** (réutilisé : **cycle déterministe piloté par l'horloge UTC, LOCAL, sans
  backend** ; 5 états BULL/BEAR/CRASH/CRABE/HYPE ; BULL = entretien *cheap*, CRASH = appels de marge violents).
- **Margin Call** (allocation insuffisante face au taux) ⇒ **allocation restante consumée + activité en PAUSE** jusqu'à
  relance. **Auto-désactivation** à la fin de la durée choisie (borne la fenêtre de danger).

**Non-punitif (verrouillé) :** OFF par défaut = idle-pur intouchable · le **faucet de base du module continue** quoi
qu'il arrive · on ne perd **que le carburant misé** (l'allocation), **jamais sous la base**. **Hors-ligne =
responsabilité ASSUMÉE du joueur** (« tu lances 8 h, tu dors, tu te fais sortir = le jeu, ça colle à la réalité ») —
*équitable* **parce que** le régime est **déterministe + affiché** : le joueur **lit la météo** avant de lancer
(timing stratégique). Mini-jeu non lancé = **vraiment éteint**, pas concerné par les variations.

**Anti set-and-forget (verrouillé) :** régime déterministe **mais la session traverse des transitions** (BULL→CRASH
à mi-parcours). Arbitrage **durée × taille × timing** qui ne se fige pas : longue = +rendement mais traverse plus de
météo (+risque) ; courte = sûre mais -rendement. ⚠️ Le cycle régime doit être **assez rapide** pour qu'une session en
croise plusieurs.

**Récompense (boucle complète) :**
- **GEMMES (éco-facing)** = source **alternative** de gemmes → nourrit la méta (fragments/gear). Réalise *« le manuel
  fait mieux »* : l'idle-pur achète ses gemmes au cash (sûr) ; l'actif alloue en Margin Call et sort **plus** de
  gemmes s'il joue bien. **Jamais obligatoire, récompensé.** Doit être **net-positif EN MOYENNE**, modulé par le
  régime (généreux BULL, risqué CRASH).
- **RÉPUTATION (INTERNE au mini-jeu — VERROUILLÉ : PAS un mult de prod global)** = progression/maîtrise qui débloque
  **allocation max ↑, durée max ↑, meilleur rendement gemmes, plus de modules activables, meilleures conditions de
  marge**. C'est la **barre de progression** scopée au mini-jeu → **pas de doublon avec la Valo** (= niveau joueur
  global). Répond aussi à la question « barre d'XP » (B/C de la refonte progression).

**Garde-fous / à caler (prochain chantier) :** plafond **durée + allocation max repoussés par la réputation** (= hook
de progression, protège le hors-ligne) · **lisibilité** : avant lancement, afficher la **PROJECTION** (rendement
gemmes estimé + fenêtre de risque régime sur la durée choisie) → décision transparente · **reconstruire le régime en
LOCAL** (cycle déterministe UTC, le champ `regime` des héros est gardé exprès) · **calibrer** le net-positif moyen +
la courbe taux/régime + conversion allocation→gemmes.

### Vision validée à implémenter (détails dans `docs/economy-vision.md`)
Ordre suggéré : (1) **Éclats** ~~Phase 1~~ ✅ FAIT (local : faucet surplus→Éclats, fabrication ciblée,
fusion de secours ; `state.shards`, `SHARD_PER_COPY`=8/6/4, `craftHero`, UI Codex). Reste **Phase 2** :
pont ledger + **trade** secondaire sur l'Exchange →
(2) ~~**surnoms de héros**~~ ✅ FAIT (local : `state.nicknames`, éditeur fiche Codex, perso/non-public) → (3) ~~**tiers retail/OTC**~~ ✅ FAIT (`economy_otc.sql` : achat de gems au cours + **OTC = Hedge Fund** book séparé, taille mini, taker 1 %, impact, garde-fou d'arbitrage + widget d'écart) →
(4) **$VOLT** ← **prochain bloc, design v1 verrouillé** (voir Décisions verrouillées + `economy-vision.md` §5 :
pool global pro-rata, halving par supply, minage+trade+staking, Satoshi booste le staking) →
(5) **levier (L5)** sur l'OTC → (6) **endgame** frais→stakers → (cap lointain) **DEX-shares**.
⚠️ Le **halving du $VOLT** est conçu ; reste le **tuning des nombres** (base/plafond/vitesse).

## Gotchas connus

- `node` n'a pas `Date.now()`/`Math.random()` dans les scripts Workflow (pas pertinent ici).
- Le serveur de signature git peut renvoyer 503 → réessayer le commit (backoff).
- Tests SQL : tables ledger/trades **immuables** (triggers anti-UPDATE/DELETE) → les tests vident `economy_orders` (transient) et créent des acteurs neufs.
