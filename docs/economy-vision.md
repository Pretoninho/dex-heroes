# 🔭 Dex Heroes — Vision économique & gameplay (design)

> Document de **conception** : décisions prises en discussion, **pas encore
> implémentées**. Source de vérité pour les évolutions à venir de l'économie,
> des actifs, des héros et de l'Exchange. (L'architecture **déjà en place** est
> dans [`economy.md`](./economy.md) et [`../CLAUDE.md`](../CLAUDE.md).)
>
> Statut : **design validé en discussion**, à implémenter au « go » bloc par bloc.

---

## 0. Boucle de jeu (état actuel) — pourquoi le $VOLT

> Section **descriptive** : le cycle du joueur tel qu'il tourne **aujourd'hui**
> (implémenté), ses trous, et où les blocs à venir se branchent. Sert de
> motivation au reste du document.

### Le cycle

```
  ① IDLE / CASH FLOW ──$──► acheter des 💎 (cours retail, ou formule de repli)
     (connecter/améliorer modules → $/sec)            │
        ▲                                             ▼
        │                                   ② GACHA (200💎, pity 80) → héros
        │                                             │
        │                          doublon d'un héros maxé ─► 🧩 Éclats ─┐
   ④ +PRODUCTION                                      ▼                  │
   (passifs + synergies + signatures)      ③ HÉROS : fusion (doublons → │
        ▲                                   niveau) · Éclats → héros     │
        │                                   ciblé ◄──────────────────────┘
        └───────────── déployer dans le Dex ─────────┘

  ⑤ MÉTA  ⟳ Régime de marché → +prod des héros déployés alignés (adapter sa compo)
  ⑥ EXCHANGE (cloud) : déposer 💎/$ ⇄ trader · Retail⇄OTC arbitrage → multiplier
     💎/$ → retirer → relance le gacha
```

- **Boucle primaire (idle, solide)** : `$ → 💎 → gacha → héros → +prod → $`. Tourne
  hors-ligne, sans cloud. ✅
- **Boucle de collection (solide)** : doublons → fusion ; surplus → Éclats →
  fabrication ciblée (ferme la malchance gacha). ✅
- **Boucle de marché (optionnelle, cloud)** : déposer → trader/arbitrer retail⇄OTC →
  multiplier 💎/$ → re-tirer. Seul espace **actif/compétitif**. ✅
- **Méta ambiante** : le régime (global, piloté par le marché interne) module la prod
  des héros alignés → plus **subi** qu'agi pour le joueur lambda. ⚠️

### Les trous (état actuel)

1. **Pas de vrai endgame** : héros maxés + Dex achetés → ne reste que « +$/sec » → plafonne.
2. **Le bras Énergie n'a aucun rôle propre** : il ne fait que du cash, comme les autres.
3. **Les frais du marché sont un puits pur** (restent chez SYSTÈME) → valeur dormante.
4. **L'Exchange est cloisonné** : trader multiplie 💎/$ mais ne crée pas d'actif nouveau.

### Où ça se branche

Le **$VOLT** (§5) vise exactement ces 4 trous : Énergie **mine** (#2) → le jeton se
**trade** (#4) → le **staking** transforme les frais dormants en **rendement** (#1, #3),
le **halving** entretient la tension d'offre. Le **levier** (L5) puis l'**endgame
frais→stakers** referment la boucle économique de fin de partie.

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
> **Phase 2 à venir** : pont vers le ledger + marché secondaire sur l'Exchange.

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

1. ~~**Éclats** (faucet fusion + sink fabrication)~~ — ✅ **Phase 1 FAITE** (local). Reste : trade (Phase 2, pont ledger).
2. ~~**Surnoms de héros**~~ — ✅ FAIT (local, `state.nicknames`, éditeur fiche Codex).
3. ~~**Tiers retail/OTC** + **achat de gems au cours**~~ — ✅ FAIT (`economy_retail.sql` + `economy_otc.sql`).
4. **$VOLT** (design verrouillé, voir §5) : minage **pool global pro-rata** (Énergie, halving
   par supply) + trade **$VOLT↔cash** (module Spéculation) + **staking** (lock, part frais
   croissante, Satoshi booste). `economy_volt.sql`. ← **prochain bloc**.
5. **Levier (L5)** sur l'OTC, gated par le niveau du héros Bourse.
6. **Endgame** : bascule frais → stakers (quand $VOLT plafonné).
7. *(cap lointain)* **DEX-shares** : bourse d'actions entre joueurs.
