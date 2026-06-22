# 🍪 Cookie Idle

Un petit *idle game* (jeu de type clicker) en **HTML / CSS / JavaScript pur**, sans aucune dépendance.

## Jouer

Ouvre simplement `index.html` dans ton navigateur. C'est tout.

## Fonctionnalités

- **Clic manuel** : clique sur le cookie pour en produire.
- **Générateurs automatiques** : curseur, grand-mère, ferme, usine, mine, temple… chacun produit des cookies en continu.
- **Coûts progressifs** : chaque achat augmente le prix de l'objet (×1.15, le standard du genre).
- **Sauvegarde automatique** dans le navigateur (`localStorage`), toutes les 15 s et à la fermeture.
- **Progression hors-ligne** : tu gagnes des cookies même quand le jeu est fermé.
- **Formatage des grands nombres** (k, M, B, T…).

## Structure du code

Tout tient dans `index.html` :

| Partie | Rôle |
| --- | --- |
| `GENERATORS` | Définition des générateurs (coût, production, croissance du prix). |
| `state` | État du jeu (cookies, objets possédés, dernière visite). |
| `load` / `save` | Sauvegarde et progression hors-ligne via `localStorage`. |
| `costOf` / `perSecond` | Calculs économiques. |
| `loop` | Boucle de jeu (10 ticks/sec) qui ajoute la production. |
| `render` / `buildShop` | Affichage et mise à jour de l'interface. |

## Idées d'évolution

- Améliorations de la puissance de clic.
- Système de *prestige* (reset avec bonus permanent).
- Succès / objectifs.
- Sons et animations supplémentaires.
- Adapter le thème aux « héros » (cf. nom du dépôt `dex-heroes`).
