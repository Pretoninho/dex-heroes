# 💱 Dex Heroes — Architecture de l'économie

> Inspiré des principes d'**AXIOM** : coder des **primitives minimales**, laisser
> les phénomènes **émerger**. Le marché, le prix, le régime, les contrats sont des
> **couches émergentes** au-dessus d'un seul primitif fondateur : le **grand livre
> de faits**.

## Les lois (adaptées à Dex Heroes)
- **I — Conservation** : aucune ressource n'apparaît/disparaît sans contrepartie tracée. Les « robinets » (gacha, production) et les « puits » (frais) passent par un acteur **SYSTÈME** (≈ NATURE d'AXIOM).
- **II — Coût** : toute action a un coût explicite (frais de marché, etc.).
- **III — Opacité** : un joueur ne voit que **ses propres** faits/soldes. Seules les **projections agrégées** (prix, volume) sont publiques.
- *(Localité : non utilisée pour l'instant — pas de géographie.)*

## Le primitif fondateur : le **grand livre (ledger)**
- Tout mouvement est une **entrée de ledger immuable** (`economy_ledger`), append-only, séquencée.
- Une **opération** = un **`tx`** : un ensemble d'entrées **équilibrées** (somme des deltas = 0 **par ressource**) → conservation garantie, comptabilité en partie double.
- **Le solde n'est pas stocké comme vérité — c'est une PROJECTION** : `solde(acteur, ressource) = Σ deltas`. On garde un **cache** (`economy_balances`) mis à jour dans la même transaction (perf), mais le ledger reste la **source de vérité**.
- **Atomicité** : `economy_post_tx(...)` écrit toutes les entrées en une transaction ; si une échoue, rien ne se produit.

## Les acteurs (primitif unifié)
`economy_actors` : `player` (lié à un compte), `npc` (autonome), `system` (NATURE — source/puits, peut être négatif). Joueurs, NPC et système partagent **le même primitif** ; leurs rôles sont **dérivés**.

## Les couches émergentes (roadmap par niveaux)
| Niveau | Couche | Émergence |
|---|---|---|
| **L1** | **Ledger + acteurs** *(cette étape)* | la richesse devient traçable, conservée, projetée |
| **L2** | **Marché sur ledger** : ordres + **faits de trade** | **prix implicite** (ratio cash/gemme) ; index de prix = moyenne pondérée des trades récents |
| **L3** | **NPC teneurs de marché** (tick `pg_cron`) | **le cours bouge tout seul** → l'économie vit même sans joueurs |
| **L4** | **Régime** dérivé du cours/volume du marché interne | l'« option 2 » que tu veux : régime **non aléatoire**, émergent |
| **L5** | **Contrats** (`economy_contract` + faits de terme) | ordres à cours limité, ventes récurrentes, **prêts/intérêts**, institutions |

## Pourquoi c'est flexible (accueillir de nouvelles features)
- **Ajouter une feature = ajouter un `kind` d'entrée + (option) une table de faits + un *wrapper* qui appelle `post_tx`.** Le cœur (ledger, conservation, projection) ne change jamais.
- Nouvelles **ressources** : juste une nouvelle valeur de `resource` (pas de schéma à changer).
- Nouveaux **acteurs/NPC** : une ligne dans `economy_actors` + une `policy` (jsonb) décrivant leur comportement.
- **Contrats** = des faits qui, quand leurs **termes** sont remplis (au tick), émettent des `tx` → tout réutilise le primitif.

## Principe de travail
- **Incrémental** : une couche à la fois, livrée + **testée** (cohérence, conservation, sécurité) avant la suivante.
- **NPC testés en priorité** : on vérifie qu'ils ne **créent/détruisent** rien hors SYSTÈME et que les prix qu'ils produisent restent sains.

## Cohabitation avec l'existant
Le marché actuel (`wallets`/`listings`) **continue de tourner** pendant qu'on bâtit le ledger en parallèle. On **migrera** le marché sur le ledger en L2, puis on retirera l'ancien `wallets`. Rien n'est cassé entre-temps.
