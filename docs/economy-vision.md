# 🔭 Dex Heroes — Vision économique & gameplay (design)

> Document de **conception** : décisions prises en discussion, **pas encore
> implémentées**. Source de vérité pour les évolutions à venir de l'économie,
> des actifs, des héros et de l'Exchange. (L'architecture **déjà en place** est
> dans [`economy.md`](./economy.md) et [`../CLAUDE.md`](../CLAUDE.md).)
>
> Statut : **design validé en discussion**, à implémenter au « go » bloc par bloc.

---

## 0. Boucle de jeu (état actuel, **100 % Idle**)

> Section **descriptive** : le cycle du joueur tel qu'il tourne **aujourd'hui**, après
> le pivot 100 % Idle (Exchange + régime retirés le 2026-06-24). Sert de cadre au reste
> du document — les blocs « trading » ci-dessous sont **en sursis** (cf. `CLAUDE.md`).

### Boucle cœur (minute par minute)

```
   ┌────────────────────────────────────────────────────────┐
   │                                                        │
   ▼                                                        │
① PRODUCTION (cash/s)  ──passive, tourne même hors-ligne     │
   │                                                        │
   ▼                                                        │
② CASH ──► améliore/connecte les MODULES (graphe Dex)        │
   │        → ↑ production    (🤖 auto-amélioration le fait) │
   │                                                        │
   ├──► achète des GEMMES (prix-formule indexé sur la prod)  │
   │                                                        │
   ▼                                                        │
③ GACHA (200 💎/tirage, pity Épique) ──► HÉROS              │
   │                                                        │
   ▼                                                        │
④ HÉROS déployés sur modules (passifs · synergies ·         │
   │   signatures) ──► ↑ production ─────────────────────────┘
   │
   └─► doublons ─► FUSION (niveau du héros)
       doublon d'un héros maxé ─► 🧩 ÉCLAT
       Éclats ─► craft ciblé / fusion de secours
```

Moteur : **+ production → + cash → + modules & + gemmes → + héros → + production**.

- **Boucle primaire (idle, solide)** : `$ → 💎 → gacha → héros → +prod → $`. Tourne
  hors-ligne, sans cloud. ✅
- **Boucle de collection (solide)** : doublons → fusion ; doublon maxé → Éclats →
  fabrication ciblée (ferme la malchance gacha). ✅

### Boucle méta (par session / long terme)

Quand la boucle cœur sature, le cash et les gains se convertissent en **progression permanente** :

| Levier | Rôle | Effet |
|---|---|---|
| 🏛️ **Valorisation** | Soft-prestige **sans reset** (rangs au cash, ×8/rang) | **+10 % prod globale/rang**, permanent → puits de cash **et** niveau joueur |
| 🎯 **Objectifs** | Jalons one-shot franchis **passivement** | Récompense 💎/🧩 → réinjectée dans le gacha |
| 🗃️ **Dex 2 / 3** | Paliers d'échelle (gros achats cash) | Multiplient coûts **et** gains → relancent la boucle cœur plus haut |
| 💤 **Hors-ligne** | Récompense de retour (plafond 4 h, taux 0,5 ; héros étendent le plafond) | Démarrage de session boosté → modale « Bon retour » |

### Garantie idle

Chaque étape a un **chemin passif par défaut** : la production tourne seule, l'**auto-amélioration
(🤖)** dépense le cash sans clic, les **objectifs** se valident en jouant, les **gains hors-ligne**
récompensent l'absence. **Aucune étape de l'endgame n'exige une action manuelle ou d'être en ligne**
(règle d'or du cap polaire).

### Les trous (état actuel)

1. **Pas de vrai endgame / prestige dur** : héros maxés + Dex achetés → ne reste que
   « +$/sec ». La Valorisation joue ce rôle en plus doux (sans reset) → **prochain bloc logique**.
2. **Les 17 autres activités de module ne sont pas codées** : tous les modules ne font que
   du cash, aucun n'a d'identité propre (le seul qui en avait une, la Bourse/Exchange, a été retiré).
3. **Le bras Énergie n'a aucun rôle propre** (héritage : il devait miner le $VOLT).

### Où ça se branche

Les prochains blocs idle-natifs visent ces trous : une **couche prestige/ascension** (#1),
puis des **identités de module** (#2) — passifs spécifiques, mini-systèmes idle par bras.
Le **$VOLT** (§5) et les sections trading ci-dessous ne reviendront **que** sous une forme
**idle-pure** (minage passif + staking, sans terminal à surveiller), ou pas du tout.

---

## 1. Principe directeur : le bras = une *verticale*, le module = une *facette*

On abandonne « 1 module = 1 activité isolée » au profit de **« 1 bras = 1
verticale, chaque module en est une facette »**. Le bras **Bourse** est la
**verticale Trading** :

| Module | Facette | Héros (en place) |
|---|---|---|
| 📈 **Bourse** | **Marché retail** : paire de base 💎/$, petits ordres, liquidité garantie | Warden Buffott (Momentum) |
| 🎲 **Spéculation** *(ex-Crypto)* | **Actif volatil** : le jeton **$VOLT** | Satoshi Nakomito (**Degen**) |
| 🐋 **Hedge Fund** | **OTC / gros ordres** : venue institutionnelle, peu liquide, frais élevés, **levier** | Georg Solros (**levier**) |

À terme : **chaque module du jeu = une activité**, et **chaque bras = une
verticale** (18 activités, 6 verticales).

---

## 2. Multi-actifs

Le **ledger event-sourced accepte n'importe quelle ressource** sans changement de
schéma (`resource_id`). Donc ajouter des actifs est **trivial côté moteur** ; le
travail est la **sémantique gameplay** : pour chaque actif, définir **faucet /
sink / décision créée**.

| Actif | Faucet | Sink | Décision | Statut |
|---|---|---|---|---|
| 💎 Gems | exchange / passifs héros | gacha | spéculer vs tirer | en place |
| $ Cash | production (cash flow) | achats / frais | — | en place |
| 🧩 **Éclats** (fragments) | surplus de fusion | fabriquer un héros choisi | compléter SON héros vs vendre | **Phase 1 ✅** (trade = Phase 2) |
| ⚡ **$VOLT** | minage par le bras Énergie | carburant (levier/signatures) + staking | miner / trader / staker | **conçu** |
| 📜 DEX-shares | « introduire » son DEX | dividende = part de prod | bourse d'actions entre joueurs | **cap lointain** |

**Règle verrouillée : on ne trade JAMAIS les héros entiers** (risque pay-to-win).
On trade des **Éclats** (fongibles) — voir §3.

---

## 3. Éclats (fragments de héros) — *premier nouvel actif*

> Statut : **Phase 1 codée** (faucet + sink + fusion de secours, 100 % côté save).
> **Phase 2 : design verrouillé** (juin 2026, voir §3 bis), pas encore codé.

- **Mutualisés par rareté** : 3 types — Éclats **Commun / Rare / Épique** (pas 18
  marchés illiquides). Stockés dans `state.shards = {0,1,2}` (clé = rareté).
- **Production (faucet)** ✅ : un doublon tiré sur un héros **déjà au niveau max** se
  convertit en **1 Éclat** de sa rareté (au lieu d'un doublon mort). *(La fusion sert
  d'abord à monter le niveau ; le surplus devient Éclats.)* Migration au chargement :
  les doublons morts des héros déjà maxés sont balayés en Éclats.
- **Sink — fabrication ciblée** ✅ : dépenser des Éclats pour **fabriquer 1 copie d'un
  héros choisi** de cette rareté (`SHARD_PER_COPY` : Commun **8** · Rare **6** · Épique
  **4**, tunables). La copie débloque le héros **ou** sert de doublon.
- **Fusion de secours** ✅ : si les doublons manquent pour fusionner, les Éclats
  **couvrent le déficit** (manque × coût d'1 copie). Deux chemins, un seul taux.
- **Trade** (Phase 2) : marché secondaire des héros **sans vendre les héros** eux-mêmes
  (nécessite de ponter `state` ↔ ledger event-sourced).
- **Démantèlement** (héros non désiré → Éclats) : **prévu plus tard**, pas en v1.

**UI** : barre d'Éclats + bouton « Fabriquer » sur la fiche (Codex 📖) ; le bouton
Fusionner du module bascule sur le coût en Éclats quand les doublons manquent.

---

## 3 bis. Éclats — Phase 2 : trade & raffinage (design verrouillé, juin 2026)

> Statut : **design validé en discussion, pas encore codé.** Reste **1 décision d'archi**
> (couture client↔ledger, voir fin de section) avant le build. Issu d'une analyse
> multi-perspectives (5 lentilles de design + critique adverse).

**Le pari.** Rendre les Éclats échangeables **sans** que le cash achète la puissance ni la
collection. Principe directeur : **le gacha possède la DÉCOUVERTE, le marché possède la
PROFONDEUR — gatée.**

**Décisions verrouillées :**

1. Éclats ↔ **cash** ; **tout sur le ledger** (plus de faucet/sink offline).
2. **Collection = gacha-souverain** : les Éclats (faucet ou achetés) ne **débloquent
   jamais** un héros jamais tiré ; ils ne servent qu'à **leveler/fusionner un héros déjà
   possédé**. Protège le « NEW ! » (cœur émotionnel du gacha).
3. **Un seul Éclat *tradable* par rareté** (jeton spéculatif, liquide) **+ Éclat *lié***
   (soulbound, matière à puissance). Le **raffinage** est le goulot à sens unique entre les
   deux — il porte tous les gates.
4. **Épique non-tradable en v1** (l'inversion de coût le rend le plus dangereux *et* le plus
   désirable). Ouvrir **Commun/Rare** d'abord ; Épique réévalué sous télémétrie.

**Le flux (4 étapes) :**

```text
1. FAUCET      doublon-surplus sur héros maxé → +1 Éclat TRADABLE   (ledger : SYSTÈME −1 = l'offre)
2. MARCHÉ      achat/vente Éclat tradable ↔ cash                    (MM = backstop plancher, jamais de mint)
3. RAFFINAGE   Éclat tradable → Éclat LIÉ                           ← GATES : ratio + horloge
4. FABRICATION Éclats liés → copie/level d'un héros DÉJÀ possédé    ← GATES : sink cash + verrou collection
```

**Les gates (rôles distincts, complémentaires) :**

| Gate | Étape | Rôle | Valeur v1 |
|---|---|---|---|
| **Ratio** | Raffinage | friction de valeur *en Éclats* ; les pertes → SYSTÈME = sink déflationniste (contre le faucet) | **1,2:1** |
| **Horloge** | Raffinage | gate de **vitesse** : découple richesse ↔ rythme de puissance | **hard-cap ~10 tradables/j**, reset 00:00 UTC, global/compte |
| **Sink cash** | Fabrication | gate de **valeur** : le knob de calibration anti-P2W | ≈ coût gacha (voir calibration) |
| **Verrou collection** | Fabrication | leveling-only, jamais débloquer | protège la découverte gacha |

Ratio + cash = *combien ça coûte* ; horloge = *à quelle vitesse*. **Les deux nécessaires** :
sans horloge un riche convertit tout d'un coup ; sans gate de valeur l'horloge ne fait que
retarder un power-grab pas cher.

**Calibration (l'invariant chiffré).** Anchor : *fabriquer 1 copie par le marché doit coûter
≥ tirer cette copie au gacha.* Gacha (taux 79/18/3 %, 6 héros/rareté, tirage 200 💎 ≈
20 000 cash à l'ancre 100) → coût d'une copie d'un **héros précis** (donc leveling) :

| Rareté | Tirages/copie | Coût gacha/copie | Sink cash/copie (strawman) | Plancher MM/Éclat |
|---|---|---|---|---|
| **Commun** | 7,6 | ~152 000 cash | ~150 000 | ~3 000 |
| **Rare** | 33,3 | ~667 000 cash | ~650 000 | ~12 000 |

Split retenu : **plancher bas + gros sink cash** → marché d'Éclats **liquide** (bon pour le
méta-jeu Bourse), puissance payée à la **fabrication**. Total Commun ≈ **1,18× le gacha** →
acheter+raffiner reste *un peu plus cher* que tirer, mais déterministe : c'est la **prime de
déterminisme**, jamais un raccourci. ⚠️ Chiffres à **caler sur la vraie courbe de cash-flow**.

**Market-maker des Éclats** (≠ MM des gems, voir Gotchas) :

- **Acheteur de dernier recours** à un **plancher cash fixe par rareté** (`economy_config`,
  comme les fees). N'agit **qu'au plancher** ; au-dessus → price discovery pure.
- **Budget cash borné/période** (anti-inflation, anti-hoard). Asks **depuis inventaire de
  consignation** uniquement — **jamais de mint d'Éclats**.
- **Pas de NPC momentum** : le prix doit rester un **signal propre de rareté** (overflow whale
  vs demande raffineur), pas un cours piloté.

**Conservation inversée (la digue).** Contrairement à gems/cash, **SYSTÈME ne peut être négatif
sur les Éclats QUE via le faucet** (doublon-surplus mérité). Le MM ne mint jamais (solde Éclats
≥ 0). Invariant **vérifiable**, pas une règle molle.

**Conséquences assumées :**

- **`fuse()` ET `craftHero()` passent par le même goulot** (ne consomment que des Éclats *liés*
  + sink cash). Sinon la fusion-de-secours est un **backdoor** qui contourne tous les gates.
- **La Phase 2 re-gate rétroactivement la Phase 1** : la fabrication ciblée *gratuite* du surplus
  disparaît (le ledger est **fongible** → impossible de distinguer Éclat mérité vs acheté ; le
  tracking de provenance a été écarté). C'est le prix de « aucun chemin de puissance non-gaté ».

**La couture client↔ledger — TRANCHÉE (client-trusted borné).** Le faucet (mint Éclat) et le
verrou collection vivent **à cheval** entre la save **client-authoritative** et l'économie
**server-authoritative**. Constats d'archi (vérifiés) :

- L'**état du jeu = un blob client**, upsert verbatim dans `saves` ([`cloud.js`]) — **zéro
  validation serveur**.
- **Gems + gacha = 100 % client** : `pull()` fait `state.gems -= cost` et roule en
  `Math.random()`, **sans appel serveur**. Le **seul** morceau server-authoritative = le ledger
  (trades/settlement/conservation).
- 🔑 Le **pont game→ledger est DÉJÀ client-trusted** : `economy_deposit` crédite le ledger avec
  ce que le client demande (garde-fou unique : `d_gems > 1e9`), **sans vérifier la possession**.
  Un save-editor peut déjà **injecter des gems fantômes** dans l'économie multijoueur.

**Décision : (a) client-trusted, cohérent avec l'existant.** Sécuriser le faucet d'Éclats pendant
que le dépôt de gems est grand ouvert serait *verrouiller la fenêtre à côté d'une porte ouverte*
(gain marginal ~nul, incohérent). L'anti-P2W vise les **incitations du joueur honnête**, pas
l'anti-triche (un save-editor s'octroie déjà n'importe quoi — hors modèle de menace). L'option
« mirror du roster serveur » est **circulaire** (relire le blob = relire la triche) ; une vraie
sécurité exigerait un **gacha server-authoritative** = hors scope.

**Triptyque retenu :**

1. **Faucet via RPC capé serveur** (montant/appel + cap/jour, façon garde-fou `1e9`) → **plafonne
   le rayon de nuisance** d'un tricheur sur le marché multijoueur, sans prétendre l'empêcher.
2. **Coût serveur / octroi-lock client** : la fabrication est un **RPC qui brûle cash ledger +
   Éclats liés** (coût 100 % réel → l'économie anti-P2W tient) ; le **verrou collection** reste
   **client-side** (best-effort). Même un tricheur qui le contourne **paie le plein coût ledger**
   — pas de puissance *bon marché*, juste du ciblage qu'il avait déjà en éditant le blob. Le lock
   client coûte donc ~zéro en sécurité.
3. **Gates server-enforced** : horloge de raffinage, sink cash, calibration — tous applicables
   côté ledger (qui détient cash et Éclats). Ils font le travail réel.

→ **Coût = serveur (réel) · octroi/lock = client (best-effort) · gates = serveur** — exactement le
partage déjà en place pour gems/gacha.

**À durcir plus tard (pas Phase 2) :** le dépôt client-trusted est un trou latent de l'économie
multijoueur ; si la triche devient un vrai problème, durcir **holistiquement** (gacha + pont
server-authoritative), pas spécifiquement les Éclats.

**Démantèlement** (héros non désiré → Éclats) : toujours **plus tard**, pas en v1.

**Build (engineering, au « go ») :** généraliser le matching à la paire (`base_resource` ↔ cash)
· nouvelles ressources ledger (`shard_c/r` tradables, `shard_c/r_bound` liés) · fonctions
faucet/refine/fabricate/MM · invariant de conservation Éclats · migration des `state.shards`
Phase 1 → ledger · tests + ordre de déploiement · frontend (sélecteur de paire, UI
raffinage/fabrication) · bump `?v=`.

---

## 4. Héros nommables (surnom) — ✅ IMPLÉMENTÉ

> Statut : **codé** (`state.nicknames = {heroId: surnom}`, helpers `heroName` /
> `heroNameFull`, éditeur sur la fiche du Codex). Cosmétique et **personnel** (pas
> public) → pas de filtre pour l'instant. Voyage au cloud via `Cloud.push(state)`.

- Le joueur donne un **surnom optionnel** à ses héros (éditeur dans la fiche 📖,
  max 20 car., caractères de contrôle filtrés).
- Affichage : le **surnom** prime dans le Codex (en vert), le module et les toasts ;
  la fiche montre « *alias de « Nom canonique »* ». Le **nom canonique reste la
  source de vérité** (identité parodique + docs préservées).
- **Filtre anti-grossièretés** : seulement si le surnom devient public (classement…) —
  **pas nécessaire aujourd'hui** (surnoms personnels, le pseudo public est séparé).
- Aucun conflit avec les marchés (on trade des Éclats par rareté, pas par héros).

---

## 5. $VOLT — l'actif volatil (module 🎲 Spéculation)

Jeton **volatil, à offre plafonnée**, **carburant de la verticale Trading**.
(Nom du jeton **découplé** du module, comme les surnoms de héros.)

> **Décisions verrouillées (v1)** — *design validé, pas encore codé* :
> - **Minage = pool global pro-rata** : émission globale fixe/tick **répartie au prorata
>   du hashrate** (= prod du bras Énergie déclarée par chaque joueur). Plus de mineurs =
>   part plus fine (analogue à la difficulté Bitcoin). Mineurs inactifs (hashrate périmé)
>   exclus. **Pas** de plafond par joueur.
> - **Halving par seuils de supply** (pas par le temps) : émission `E = base × 2^(−epoch)` ;
>   `epoch++` quand `cumulative_minted` franchit `C·(1−2⁻ᵏ)` → **épochs géométriques** qui
>   convergent vers le plafond `C` (parodie **21 000 000**, tunable). Déterministe, équitable.
> - **Périmètre v1 = minage + trade + staking.** Levier (L5) et carburant des signatures = plus tard.
> - **Paire = $VOLT ↔ cash**, ouverte depuis le module **🎲 Spéculation** (Crypto, a1t1).
>   Moteur à rendre **pair-aware** (2ᵉ paire après la base venue-aware d'OTC).
> - **Staking avec période de lock** (durée exacte à caler), part des frais **croissante
>   → 100 % au plafond** (raconte l'endgame). **Satoshi (Degen)** déployé → **+rendement de
>   staking** (seule influence héros sur le $VOLT au v1).
> - **Backend** : nouveau `economy_volt.sql`, **dernier** de la chaîne ; tables `volt_state`
>   (cumulative/epoch/cap), `volt_miners` (hashrate), `volt_stakes` ; mint au tick pg_cron.
> - **Reste à caler (tuning, à l'implémentation)** : `base`/`C` exacts, vitesse → 1er halving,
>   durée du lock, forme de la courbe part-de-frais, % du boost Satoshi.

### 5.1 Production : minage par le bras Énergie (modèle Bitcoin)
- Le bras **Énergie** (🛢️ · ⚡ · ☢️) **mine** le $VOLT : la production d'énergie
  frappe du $VOLT (faucet SYSTÈME → joueur) jusqu'à un **plafond GLOBAL fixe**.
- **Émission décroissante (halvings)** ✅ **protocole décidé** : épochs géométriques
  par seuils de supply (voir Décisions verrouillées ci-dessus). Reste à **caler les
  nombres** (`base`, `C`, vitesse → 1er halving).
- Cross-arm : **Énergie** (mine) → **Bourse/Spéculation** (trade) → **utilité**.
  Donne enfin un rôle au bras Énergie au-delà du cash.

### 5.2 Plafond GLOBAL (pas par joueur)
- **Vraie rareté** → volatilité (un soft-cap par joueur gonflerait l'offre avec le
  nombre de joueurs → thèse cassée).
- **Équité par le rendement, pas la dilution** : un retardataire mine peu mais peut
  **acheter du $VOLT et le staker** pour toucher les frais (revenu ouvert à tous).

### 5.3 Volatilité (leviers cumulés)
- **Offre plafonnée** (rareté).
- **Ancre faible / absente** (le jeton flotte librement, contrairement aux gems ~100).
- **NPC réactif plus agité** sur cet actif (plus de `noise`/`w_mom`, moins de
  `w_rev`, carnet MM mince).

### 5.4 Utilités (simplifiées)
1. **Marge / collatéral du levier** (Hedge Fund / OTC) — demande des traders.
2. **Carburant des signatures** (capacités actives des héros) — demande idle.
3. **Staking → rendement** : bloquer du $VOLT pour toucher une part des **frais**
   de l'économie. **Possible dès le début** (coexiste avec le minage).
   *(Le burn → stimulus de prod est retiré pour simplifier.)*
- Héros **Satoshi (Degen)** : réduit le coût carburant / améliore le rendement de
  staking (seule influence héros sur cet actif).

### 5.5 Endgame : émission finie → partage des frais
- Aujourd'hui les **frais** (maker/taker/retrait) sont un **puits pur** (restent
  chez SYSTÈME).
- Quand le plafond de $VOLT est atteint, l'émission s'arrête et la récompense
  **bascule vers le partage des frais** : les **stakers de $VOLT touchent les
  frais** de toute l'économie (modèle Bitcoin : subvention → frais).
- Le $VOLT **mûrit** : matière première minée → **actif productif à rendement**.
- **Boucle vertueuse** : plus de trading → plus de frais → plus de rendement → plus
  de demande de $VOLT. Le jeton reflète le **débit de frais** de l'économie.
- Le bras Énergie **garde sa production de cash** ; seule la prime $VOLT bascule du
  minage vers le staking.

> Chaîne complète : **frais (puits) → rendement de staking (utilité) → endgame du
> minage** — un seul système cohérent.

---

## 6. Tiers d'Exchange : Retail vs OTC — ✅ IMPLÉMENTÉ (`economy_otc.sql`)

> Statut : **codé** (venue `otc` cloisonnée, 2 cours, MM mince, taker 1 %, taille
> mini 200 💎, impact réel, NPC garde-fou d'arbitrage >5 %, widget d'écart côté UI).
> L'**arbitragiste joueur** est l'activité visée ; les frais (round-trip ~1,2 %) sont
> le gate, le garde-fou ne borne que les écarts extrêmes. **Reste** : outils
> d'arbitrage avancés (raccourci 1-clic achète-retail→vends-OTC), graphique OTC dédié.

Pour gérer la **manipulation** sans casser l'onboarding : deux tiers, mappés sur
les modules.

| Tier | Module | Caractéristiques | Effet |
|---|---|---|---|
| **Retail** | 📈 Bourse | ordres **plafonnés**, liquidité profonde (MM), **frais bas**, faible impact | **protège** les petits ; prix stable |
| **OTC** | 🐋 Hedge Fund | **gros** ordres, carnet **mince**, **frais élevés**, **impact de prix** réel | les whales jouent là, paient & subissent l'impact ; **isolés** du retail |

- La **manipulation est confinée à l'OTC** (jeu entre gros) ; le **retail reste
  stable** pour les nouveaux.
- **Écart de prix** retail/OTC → **arbitrage** : activité **joueur** (gate = frais
  ~1,2 % aller-retour) ; un **NPC garde-fou** ne recolle que les écarts > 5 %.
- C'est la base du design du **levier** (sur l'OTC).

---

## 7. Achat de gems : au cours du marché

- On **ne retire pas** le bouton « acheter des gems » ; il devient un **ordre Market
  plafonné** sur le tier **retail**.
- **Prix = le cours du marché** (meilleur ask ≈ cours × (1 + spread du MM)).
- Le prix des gems **flotte** (émergent) ; fini la formule indexée sur la production.
- **L'ancienne formule** (`gemPrice` indexée prod) devient le **fallback hors-ligne**.
- Le plafond par ordre empêche un achat de bouger le cours → retail stable.

---

## 8. Manipulation : un mal *encadré* qui nourrit le jeu

- **Mauvaise** si elle gâte la progression de base (gacha) des petits → confinée au
  retail stable (§6).
- **Bonne** côté OTC : crée un **méta-jeu** (pumps/dumps entre gros) et **nourrit le
  régime** (un pump = HYPE, un dump = CRASH → stratégie héros). Contenu émergent.

---

## 9. Questions ouvertes (à trancher avant implémentation)

- ~~**Protocole de halving du $VOLT**~~ ✅ **décidé** (épochs géométriques par supply,
  pool global pro-rata — voir §5). Reste du **tuning** : `base`, `C`, vitesse → 1er halving.
- ~~**Mécanique de staking**~~ ✅ **décidé** (lock + part des frais croissante → 100 %,
  Satoshi booste le rendement — voir §5). Reste du **tuning** : durée du lock, courbe, % Satoshi.
- **Levier** : design détaillé de la liquidation, marge en $VOLT, funding (L5).
- ~~**Fabrication de héros via Éclats**~~ ✅ FAIT (ciblé, 8/6/4 — voir §3).
- ~~**NPC arbitragiste** retail↔OTC~~ ✅ FAIT (garde-fou >5 %, arbitrage = activité joueur — §6).

---

## 10. Ordre de construction suggéré (au « go »)

1. ~~**Éclats** (faucet fusion + sink fabrication)~~ — ✅ **Phase 1 FAITE** (local). Reste : **trade (Phase 2)** — design verrouillé (**§3 bis**), reste 1 décision d'archi (couture client↔ledger) puis le build.
2. ~~**Surnoms de héros**~~ — ✅ FAIT (local, `state.nicknames`, éditeur fiche Codex).
3. ~~**Tiers retail/OTC** + **achat de gems au cours**~~ — ✅ FAIT (`economy_retail.sql` + `economy_otc.sql`).
4. **$VOLT** (design verrouillé, voir §5) : minage **pool global pro-rata** (Énergie, halving
   par supply) + trade **$VOLT↔cash** (module Spéculation) + **staking** (lock, part frais
   croissante, Satoshi booste). `economy_volt.sql`. ← **prochain bloc**.
5. **Levier (L5)** sur l'OTC, gated par le niveau du héros Bourse.
6. **Endgame** : bascule frais → stakers (quand $VOLT plafonné).
7. *(cap lointain)* **DEX-shares** : bourse d'actions entre joueurs.
