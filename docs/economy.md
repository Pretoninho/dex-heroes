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

## Décisions verrouillées (juin 2026)

| Choix | Décision |
|---|---|
| **Numéraire** | Cash (unité de compte) — prix d'une gemme = ratio cash/gemme. |
| **v1 : paire d'échange** | Gemmes ↔ Cash seulement. Le ledger accepte d'autres ressources ; on les exerce plus tard. |
| **Modèle NPC** | **Market-maker d'abord** (stabilise le prix, se teste isolé), **réactif ensuite** (crée l'ondulation que le régime lira). |
| **Ordre des contrats** | **Exécution instantanée avant terme/échéance** → ordre à cours limité avant ventes récurrentes / prêts / intérêts. |
| **Tick `pg_cron`** | À la minute. Le projet se met en pause après 7 j d'inactivité (free tier) ; acceptable (pas de joueurs = pas besoin que l'économie respire). |
| **Free tier Supabase** | **Tient** sans refactoring. Trois garde-fous : (1) un tick ne poste que des ordres (pas d'écritures ledger) ; seuls les trades exécutés écrivent ; (2) solde = projection en cache (perf invariante) ; (3) compaction prévue au schéma (non implémentée, juste réservée — on la grave dès L1). À 3 joueurs + 1 MM, quelques entrées/min au pire. |

## Trois tests de cohérence (à passer à chaque tick, surtout NPC)

Vérifiables automatiquement ; gardent le système sain :

1. **Conservation** : après un batch de ticks NPC, `Σ deltas == 0 par ressource` (hors SYSTÈME). Sinon annuler le tick.
2. **Bornes** : aucun solde < 0 (sauf SYSTÈME), prix > 0, volume sain. Un NPC qui refuse est traité comme un joueur en manque de solde → `post_tx` le refuse.
3. **Sanité du prix** : l'index ne peut ±X % par tick (coupe-circuit). Si un NPC mal réglé veut ×10 le cours, on le borne.

## Principe de travail
- **Incrémental** : une couche à la fois, livrée + **testée** (cohérence, conservation, sécurité) avant la suivante.
- **NPC testés en priorité** : vérifier qu'ils ne créent/détruisent rien hors SYSTÈME et que les prix restent sains.
- **Exécution avant terme** : toujours câbler le cas instantané (ordre à cours limité) avant l'échéance (contrat récurrent). C'est une règle générale : l'instantané dépend que de l'état présent ; l'échéance demande un tick fiable.

## Cohabitation avec l'existant
Le marché actuel (`wallets`/`listings`) **continue de tourner** pendant qu'on bâtit le ledger en parallèle. On **migrera** le marché sur le ledger en L2, puis on retirera l'ancien `wallets`. Rien n'est cassé entre-temps.

## Détail des couches (ordre exact d'implémentation)

**L1** : Schéma `economy_ledger` + `economy_balances` (cache) + `economy_actors` ; fonction `economy_post_tx` ; 3 tests (conservation/bornes/sanité).

**L2** : Migration des trades joueur↔joueur vers `post_tx` ; table `economy_trades` (faits) ; calcul de l'**index de prix** = moyenne pondérée des N derniers trades.

**L3** : Tick `pg_cron` ; NPC market-maker seul (une policy : spread, depth, ref) ; test isolation : cours stable, conservation = 0.

**L3b** : NPC réactif (regarde index N ticks, tendance → achète/vend) ; cours commence à onduler.

**L4** : Régime = f(dérivée de l'index) → 🐂 BULL / 🐻 BEAR / 💥 CRASH / 🦀 CRABE / 🚀 HYPE. Affinité héros (famille G) appliquée au score.

**L5** : Contrats. Ordre 1 = ordre à cours limité (l'exécution dès que prix la croise) ; ordre 2+ = DCA / prêt / intérêt (s'exécute au tick).
