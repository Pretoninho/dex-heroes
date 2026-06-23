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

Construction **étape par étape** : 1) structure 3 paliers + pages module *(fait)* ·
2) économie de gemmes + **gacha** *(fait)* · 3) **placement** des héros sur les modules
(multiplicateur, par Dex) · 4) **fusion** des doublons.

## À venir (roadmap)

- 🦸 Système de héros (gacha / fusion / slots) — voir ci-dessus.
- 🔒 Déblocage du Dex suivant conditionné aux **héros** (en plus du cash).
- 🏆 Succès / objectifs, améliorations de clic.

## Structure du code

Tout tient dans `index.html`. Le graphe est décrit par le tableau `NODES`
(position `x/y`, `parent`, `baseCost`, `rate`, `growth`) — ajouter un actif ou une
branche = ajouter une ligne.

## Déploiement GitHub Pages

Workflow `.github/workflows/pages.yml` (déploie à chaque push sur `main`) + `.nojekyll`.
Source à régler une fois dans **Settings → Pages → GitHub Actions**.
