# 💵 Dex Heroes

Un *idle game* sur le thème de la **finance**, en **HTML / CSS / JavaScript pur**, sans aucune dépendance.

## Concept : le Cash Flow

Un **Dex** est une machine à cash composée de :

- une **source** (le billet 💵 que tu cliques pour générer du cash) ;
- un **graphe d'actifs** que tu connectes pour faire grossir le flux.

Le cash **circule** depuis la source à travers les actifs connectés. Chaque actif
connecté **ajoute du cash/sec** (+) au flux. Le graphe est **tentaculaire** : la
source est au centre et des **bras d'actifs rayonnent tout autour** (liens courbes
animés quand le flux passe). Un actif ne se connecte que s'il est en aval d'un nœud
déjà connecté.

```
        🏦──💳        📈──🪙
            \         /
     ⚡──🛢️ ── 💵 Source ── 🏠──🏗️
            /         \
        🦄──💼        🏭──🚢
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

## À venir (roadmap)

- 🦸 **Héros** obtenus via **gacha**, donnant des bonus (×cash, +clic…).
- 🔒 Déblocage du Dex suivant conditionné aux **héros** (en plus du cash).
- 🏆 Succès / objectifs, améliorations de clic.

## Structure du code

Tout tient dans `index.html`. Le graphe est décrit par le tableau `NODES`
(position `x/y`, `parent`, `baseCost`, `rate`, `growth`) — ajouter un actif ou une
branche = ajouter une ligne.

## Déploiement GitHub Pages

Workflow `.github/workflows/pages.yml` (déploie à chaque push sur `main`) + `.nojekyll`.
Source à régler une fois dans **Settings → Pages → GitHub Actions**.
