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
| `index.html` | **Tout le jeu** (HTML/CSS/JS inline) : cash flow, modules, dexes, gacha, héros, **fusion + Éclats** (`state.shards`, `SHARD_PER_COPY`, `craftHero`), **surnoms** (`state.nicknames`, `heroName`/`heroNameFull`), **Valorisation** (`state.valoRank`, `valoMult`/`buyValo` — soft-prestige sans reset), **Objectifs** (`state.objectives`, `OBJECTIVES`, `checkObjectives`/`seedObjectives`, écran `🎯`), **gains hors-ligne + auto-amélioration**, horloge UTC, pont `window.DEX`. ⚠️ Exchange/régime **retirés** (2026-06-24). |
| `heroes.data.js` | `window.HERO_META` + `window.HERO_DATA` (18 héros : passif, signature, synergies, klass, `regime`). Le champ `regime` n'est **plus utilisé** par le front (régime retiré) mais conservé pour réemploi. |
| `cloud.js` | Intégration Supabase : auth, cloud save, classement, pseudo. **Le terminal Exchange (`Cloud.economy.*`) a été retiré** (2026-06-24, pivot 100 % Idle). |
| `backend/*.sql` | Schéma + fonctions Postgres de l'économie (voir ordre de déploiement) |
| `docs/economy.md` | Blueprint de l'économie **implémentée** (lois, couches L1–L5, décisions) |
| `docs/economy-vision.md` | **Design à venir** (validé en discussion, pas codé) : verticale Trading, Éclats, surnoms héros, jeton **$VOLT**, tiers retail/OTC, achat gems au cours |
| `docs/heroes.md` | Conception des héros |
| `backend/README.md` | Guide de mise en place Supabase |

## Conventions IMPORTANTES

- **Cache-busting** : `cloud.js` est chargé avec `?v=N` dans `index.html`.
  **Bumper N à chaque modif de `cloud.js`** (sinon le navigateur sert l'ancien).
  Version actuelle : **v=23** (retrait du terminal Exchange).
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

## Tâches en attente / roadmap

1. ~~**NPC réactif (L3b)**~~ — ✅ FAIT (`economy_l3b.sql`). Le cours bouge tout seul.
2. ~~**Régime → effet héros (famille G)**~~ — ❌ **RETIRÉ le 2026-06-24** (dépendait du cours Exchange ; pivot 100 % Idle). Le champ `regime` des héros reste en données (`heroes.data.js`) pour un éventuel réemploi **idle-natif** (ex. cycle déterministe piloté par l'horloge UTC, sans backend). Si réintroduit : repartir d'un `regimeProdMult()` local + rééquilibrer les affinités (BULL 6 / CRASH 3 / CRABE 3 / HYPE 3 / BEAR 1 / Quant 2 — BEAR trop faible).
3. **Levier (L5)** — positions, marge, moteur de liquidation au tick, funding. Attend design liquidation + « go ».
4. **Frais custody + funding** (différés).
5. **Les 17 autres activités de module**.
6. **Couche progression** — ✅ **Valorisation** (soft-prestige sans reset) + ✅ **Objectifs** (jalons one-shot) FAITS.
   Reste : **Quêtes** (tâches dirigées, **reset quotidien UTC** — horloge déjà en place ; c'est ici que vit le
   **sink récurrent** « dépense X »). Pistes : gater des déblocages sur le rang Valo ; équilibrer la liste d'objectifs.

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
