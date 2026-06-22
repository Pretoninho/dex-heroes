# 💵 Dex Heroes

Un *idle game* sur le thème de la **finance**, en **HTML / CSS / JavaScript pur**, sans aucune dépendance.

> **Dex Heroes = un « Dex » (une collection) qui produit de l'argent.**
> Tu cliques sur le billet pour faire du cash, tu recrutes des **Héros** et tu fais progresser ton Dex petit à petit.

## Jouer

- **En ligne** : via GitHub Pages → `https://pretoninho.github.io/dex-heroes/` (voir activation ci-dessous).
- **En local** : ouvre simplement `index.html` dans ton navigateur.

## Fonctionnalités

- **Clic manuel** sur le billet 💵 → +$ à chaque clic.
- **Héros (générateurs)** : chaque Héros recruté produit du cash en continu. V1 = 3 Héros :
  - 🧑‍💼 **Le Trader** (+$0.1/s)
  - 🏦 **Le Banquier** (+$1/s)
  - 📈 **L'Investisseur** (+$8/s)
- **Le Dex se remplit** : une barre de progression montre les Héros recrutés (X/N).
- **Coûts progressifs** : chaque recrutement augmente le prix du Héros (×1.15).
- **Sauvegarde automatique** (`localStorage`), toutes les 15 s et à la fermeture.
- **Progression hors-ligne** : tu gagnes du cash même jeu fermé.

## À venir (idées)

- 💰 Montée en niveau dédiée des Héros.
- ✨ **Investir dans un 2ᵉ Dex** (mécanique de *prestige* avec bonus permanent).
- 🏆 Succès / objectifs, améliorations de clic, sons.

## Structure du code

Tout tient dans `index.html`. La liste `HEROES` en haut du script définit les Héros
(coût, production, croissance du prix) — il suffit d'ajouter/modifier une ligne pour
changer le contenu du jeu.

## Déploiement GitHub Pages

Le dépôt contient un workflow (`.github/workflows/pages.yml`) qui publie le site
automatiquement à chaque push.

**Activation (une seule fois)** : dans GitHub → **Settings → Pages → Build and
deployment → Source : GitHub Actions**. Le site sera ensuite disponible à l'URL
indiquée par l'action de déploiement.
