# 🔭 Dex Heroes — Vision économique & gameplay (design)

> Document de **conception** : décisions prises en discussion, **pas encore
> implémentées**. Source de vérité pour les évolutions à venir de l'économie,
> des actifs, des héros et de l'Exchange. (L'architecture **déjà en place** est
> dans [`economy.md`](./economy.md) et [`../CLAUDE.md`](../CLAUDE.md).)
>
> Statut : **design validé en discussion**, à implémenter au « go » bloc par bloc.

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
| 🧩 **Éclats** (fragments) | surplus de fusion | fabriquer un héros choisi | compléter SON héros vs vendre | **prochain** |
| ⚡ **$VOLT** | minage par le bras Énergie | carburant (levier/signatures) + staking | miner / trader / staker | **conçu** |
| 📜 DEX-shares | « introduire » son DEX | dividende = part de prod | bourse d'actions entre joueurs | **cap lointain** |

**Règle verrouillée : on ne trade JAMAIS les héros entiers** (risque pay-to-win).
On trade des **Éclats** (fongibles) — voir §3.

---

## 3. Éclats (fragments de héros) — *premier nouvel actif*

- **Mutualisés par rareté** : 3 types — Éclats **Commun / Rare / Épique** (pas 18
  marchés illiquides).
- **Production (faucet)** : un doublon **au-delà du niveau max** du héros se
  convertit en Éclats de sa rareté. *(La fusion sert d'abord à monter le niveau ;
  le surplus devient Éclats.)*
- **Sink** : dépenser des Éclats pour **fabriquer un héros choisi** de cette rareté
  (ou booster une fusion).
- **Trade** : marché secondaire des héros **sans vendre les héros** eux-mêmes.
- **Démantèlement** (héros non désiré → Éclats) : **prévu plus tard**, pas en v1.

---

## 4. Héros nommables (surnom)

- Le joueur peut donner un **surnom optionnel** à ses héros.
- Affichage **« Surnom (Nom canonique) »** — le **nom canonique reste la source de
  vérité** (identité parodique + docs préservées).
- **Filtre anti-grossièretés** seulement si le surnom devient public (classement…).
- Aucun conflit avec les marchés (on trade des Éclats par rareté, pas par héros).
- Coût technique faible (un champ `nickname` dans la save). **En test.**

---

## 5. $VOLT — l'actif volatil (module 🎲 Spéculation)

Jeton **volatil, à offre plafonnée**, **carburant de la verticale Trading**.
(Nom du jeton **découplé** du module, comme les surnoms de héros.)

### 5.1 Production : minage par le bras Énergie (modèle Bitcoin)
- Le bras **Énergie** (🛢️ · ⚡ · ☢️) **mine** le $VOLT : la production d'énergie
  frappe du $VOLT (faucet SYSTÈME → joueur) jusqu'à un **plafond GLOBAL fixe**.
- **Émission décroissante (halvings)** : ⚠️ **protocole à concevoir** (cadence,
  taille des paliers, plafond exact). À détailler avant implémentation.
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

## 6. Tiers d'Exchange : Retail vs OTC

Pour gérer la **manipulation** sans casser l'onboarding : deux tiers, mappés sur
les modules.

| Tier | Module | Caractéristiques | Effet |
|---|---|---|---|
| **Retail** | 📈 Bourse | ordres **plafonnés**, liquidité profonde (MM), **frais bas**, faible impact | **protège** les petits ; prix stable |
| **OTC** | 🐋 Hedge Fund | **gros** ordres, carnet **mince**, **frais élevés**, **impact de prix** réel | les whales jouent là, paient & subissent l'impact ; **isolés** du retail |

- La **manipulation est confinée à l'OTC** (jeu entre gros) ; le **retail reste
  stable** pour les nouveaux.
- **Écart de prix** retail/OTC → **arbitrage** (rôle possible d'un NPC arbitragiste).
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

- **Protocole de halving du $VOLT** : cadence, paliers, plafond exact, vitesse de
  minage vs production d'énergie. *(à concevoir)*
- **Levier** : design détaillé de la liquidation, marge en $VOLT, funding (L5).
- **Mécanique de staking** : durée de blocage, calcul du rendement (part des frais),
  effet de Satoshi.
- **Fabrication de héros via Éclats** : coûts par rareté, héros ciblable ou aléatoire.
- **NPC arbitragiste** retail↔OTC : utile dès le départ ou plus tard ?

---

## 10. Ordre de construction suggéré (au « go »)

1. **Éclats** (faucet fusion + sink fabrication + trade) — premier nouvel actif, sûr.
2. **Surnoms de héros** — petit, isolé, sympa.
3. **Tiers retail/OTC** + **achat de gems au cours** — restructure l'Exchange existant.
4. **$VOLT** : minage (Énergie) + module Spéculation + actif volatil + staking.
5. **Levier (L5)** sur l'OTC, gated par le niveau du héros Bourse.
6. **Endgame** : bascule frais → stakers (quand $VOLT plafonné).
7. *(cap lointain)* **DEX-shares** : bourse d'actions entre joueurs.
