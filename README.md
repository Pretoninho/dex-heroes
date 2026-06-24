# 💵 Dex Heroes

Un *idle game* sur le thème de la **finance**, en **HTML / CSS / JavaScript pur**, sans aucune dépendance.

## Concept : le Cash Flow

Un **Dex** est une machine à cash composée de :

- une **source** (le billet 💵 que tu cliques pour générer du cash) ;
- un **graphe d'actifs** que tu connectes pour faire grossir le flux.

Le cash **circule** depuis la source à travers les actifs connectés. Chaque actif
connecté **ajoute du cash/sec** (+) au flux. Un actif ne se connecte que s'il est en
aval d'un module déjà connecté.

L'affichage est en **maître-détail** :
- **Vue d'ensemble** : la Source en haut, puis chaque **bras** sur une ligne, lu de
  gauche à droite sur **3 paliers** (Commun ▸ Rare ▸ Épique).
- **Page module** : taper un module ouvre sa page dédiée (niveau, production,
  connecter / améliorer, et bientôt un **slot héros**).

```
                 💵 Source
   │
   ├─ 🏦 ▸ 💳 ▸ 🏛️
   ├─ 📈 ▸ 🪙 ▸ 🐋
   ├─ 🏠 ▸ 🏗️ ▸ 🌆
   ├─ 🏭 ▸ 🚢 ▸ 🛰️
   ├─ 💼 ▸ 🦄 ▸ 🌍
   └─ 🛢️ ▸ ⚡ ▸ ☢️
      Commun  Rare  Épique
```

## Jouer

- **En ligne** : `https://pretoninho.github.io/dex-heroes/`
- **En local** : ouvre `index.html` dans ton navigateur.

## Fonctionnalités

- **Clic manuel** sur le billet → +$ par clic.
- **Connecter un actif** (coûte du cash) → il ajoute +$/s au flux.
- **Améliorer un actif** déjà connecté → niveau supérieur, encore plus de +$/s.
- **Graphe à branches** avec liens animés quand le flux passe.
- **Sauvegarde auto** (`localStorage`) + **progression hors-ligne**.
- **Double-tap zoom désactivé** sur mobile (`touch-action: manipulation`).

## Dex multiples

Un **Dex** est une machine à cash complète (source + graphe). On peut en **acheter
plusieurs** : un sélecteur d'onglets (`Dex 1`, `Dex 2`, `＋ Acheter`) en haut du
panneau permet d'en construire un nouveau. Chaque Dex possède sa **propre
progression** de graphe et tous **cumulent** leur production dans le même cash.

Les Dex sont définis par `DEX_DEFS` (`costMult`, `rateMult`, `buyCost`). Le Dex 2
réutilise le même graphe avec des chiffres à l'échelle (coûts ×50, prod ×25).
Le déblocage passe par `canBuyDex()` — pour l'instant uniquement le cash ; à terme,
il exigera aussi d'avoir tous les héros.

## Héros & Gacha

Chaque module a un héros associé (1 héros = 1 module, même rareté = palier).
Boucle d'acquisition : **cash → gemmes → tirages**.

- **Gemmes** : achetées avec du cash, **prix indexé sur la production** (un 10-pull ≈ 100 s de prod).
- **Gacha** (réglages du GDD *Desk Heroes*) : taux **79 % Commun / 18 % Rare / 3 % Épique**,
  **pity** (Épique garanti au 80ᵉ tirage, soft pity dès le 74ᵉ). Tirage = **200 💎**.
- **Collection** des 18 héros + compteur de copies.

**Placement** : sur la page d'un module, si tu possèdes son héros tu peux le
**déployer** → multiplicateur de production du module (**Commun ×1.25 · Rare ×1.6 ·
Épique ×2**), indépendant **par Dex**. Un badge 🦸 apparaît sur les modules avec un
héros déployé.

Construction **étape par étape** : 1) structure 3 paliers + pages module *(fait)* ·
2) économie de gemmes + **gacha** *(fait)* · 3) **placement** des héros *(fait)* ·
4) **fusion** des doublons (les copies renforceront le multiplicateur).

## Multijoueur & économie (Supabase)

Le jeu peut se synchroniser entre appareils et faire tourner une **économie de
marché complète** via **Supabase**. Désactivé par défaut : sans clés dans
`cloud.js`, tout reste local (`localStorage`). Mise en place dans
[`backend/README.md`](./backend/README.md).

- **Comptes + cloud save** : synchro multi-appareils, suivi du propriétaire de la
  partie (un compte ≠ un autre sur le même navigateur), pseudo persistant.
- **Classement** : production /s, lu depuis la table `scores`.
- **Bourse aux gemmes (Exchange)** : un vrai **terminal de trading** in-game,
  100 % monnaie de jeu (gemmes ↔ cash).

### L'Exchange 🫱🏻‍🫲🏻

Onglet **Exchange** (et accès depuis la page du module 📈 **Bourse** — *1 module =
1 activité, 18 à terme*). Terminal façon plateforme d'échange :

- **Ticker** : prix, **variation depuis 00:00 UTC**, **régime de marché** (nom + badge).
- **Graphique en chandeliers** (2 axes) avec **timeframes 15m / 1H / 4H / D**.
- **Carnet d'ordres** (achats/ventes + barre de pression).
- **Achat/Vente** en ordre **Limite** ou **Market**, avec slider + saisie, et
  **modification d'ordre** en ligne.
- **Frais** maker / taker / retrait (configurables).
- **Dépôt / retrait** entre le jeu et le marché.

### Économie event-sourced (inspirée d'AXIOM)

Sous le capot, une architecture en couches sur un **grand livre immuable** :

| Couche | Contenu |
|---|---|
| **L1** | Ledger append-only + soldes (projection) + conservation (toute opération somme à 0) |
| **L2** | Marché : carnet, matching, faits de trade, index de prix |
| **L3** | **NPC teneur de marché** (liquidité permanente, tick `pg_cron`) |
| **L4** | **Régime de marché émergent** (BULL/BEAR/CRASH/CRABE/HYPE), lu du cours, non aléatoire, avec hystérésis |
| **L5** | *(à venir)* contrats & **levier** (gated par le niveau du héros Bourse) |

Détails : [`docs/economy.md`](./docs/economy.md). Ordre de déploiement SQL et
notes d'architecture dans [`CLAUDE.md`](./CLAUDE.md).

## À venir (roadmap)

- 🤖 **NPC réactif** — fait *bouger* le cours tout seul (marché vivant sans joueurs).
- 🦸 **Régime → héros** : le régime du jour modifiera la production selon la classe du héros.
- 📈 **Levier** (L5) : trading à effet de levier, débloqué par le niveau du héros Bourse.
- 🔒 Déblocage du Dex suivant conditionné aux **héros**.
- 🏆 Succès / objectifs.

## Structure du code

L'essentiel tient dans `index.html`. Données des héros dans `heroes.data.js`,
intégration cloud + terminal Exchange dans `cloud.js`, économie SQL dans
`backend/`. Mémoire technique du projet : [`CLAUDE.md`](./CLAUDE.md).

## Déploiement GitHub Pages

Workflow `.github/workflows/pages.yml` (déploie à chaque push sur `main`) + `.nojekyll`.
Source à régler une fois dans **Settings → Pages → GitHub Actions**.
