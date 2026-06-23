# 🦸 Dex Heroes — Fiche de conception des Héros

> Document de travail. Source de vérité pour le système de héros.
> Statut : **brouillon à valider** (on itère).

Un **héros est lié à 1 module** (18 modules → 18 héros). Sa **rareté = le palier du
module** : tier 0 = **Commun**, tier 1 = **Rare**, tier 2 = **Épique**.

-----

## 1. Anatomie d'un héros

Chaque héros est décrit par les champs suivants :

| Champ | Description |
|---|---|
| **Identité** | nom, emoji, module lié, rareté |
| **Classe** | archétype (donne l'affinité de régime) — voir §5 |
| **Passif** | effet permanent quand le héros est **déployé** (familles A–D) |
| **Signature** | capacité **active** à cooldown (famille E) — unique par héros |
| **Affinité de régime** | sous quel régime le héros est fort / faible (famille G) |
| **Synergies** | sets auxquels il appartient (famille F) |
| **Niveau (fusion)** | les doublons montent le héros en niveau → renforce passif + signature |

> Un héros cumule donc : **1 passif** + **1 signature** + **1 affinité** + **des synergies**.

### Les familles d'effets (toutes exploitées)

- **A — Production / flux** : ×prod du module, du bras, des modules de même rareté, ou des modules **en aval** (cash flow), ou % de prod globale.
- **B — Clic** : +puissance de clic, auto-clic, ou clic = +N s de production.
- **C — Économie / gacha** : −coût d'amélioration, génère des gemmes, −prix des gemmes, bonus de drop / pity.
- **D — Idle / hors-ligne** : ×gains hors-ligne, +plafond idle.
- **E — Signature active** : pouvoir déclenchable à cooldown, **déclenché depuis une
  barre d'abilities globale** (liste les signatures des héros déployés, prêtes ou en
  recharge). Cooldown temps réel et persistant.
- **F — Synergies de collection** : bonus quand plusieurs héros sont déployés ensemble.
- **G — Conditionnel / régime** : la valeur du héros dépend du contexte (le pilier).

-----

## 2. Grille de raretés (identité, pas puissance brute)

Principe (GDD) : un Épique n'est pas « plus fort » dans l'absolu, il a **plus
d'identité** (signature plus spectaculaire, niche plus tranchée).

| Rareté | Multiplicateur passif de base | Signature | Régime | Fusion (max) |
|---|---|---|---|---|
| **Commun** (3★) | ×1.25 | basique | — | niv. 5 |
| **Rare** (4★) | ×1.60 | marquée + 1 synergie | — | niv. 4 |
| **Épique** (5★) | ×2.00 | spectaculaire | **affinité de régime tranchée** | niv. 3 |

-----

## 3. Catalogue des 18 héros

Légende familles entre [crochets]. Valeurs = propositions à équilibrer.

### Bras Banque 🏦 — *intérêts & trésorerie*
| Module | Héros | Rar. | Passif | Signature (active) |
|---|---|---|---|---|
| 🏦 Banque | **Jasper Norgan** | C | [A] ×1.25 prod du module | *Intérêts* : encaisse 60 s de prod du module |
| 💳 Crédit | **Jamie Damone** | R | [C] −15 % coût d'amélioration du **bras** | *Levier* : ×2 prod du bras pendant 20 s |
| 🏛️ Trésorerie | **Mayer Roschild** | E | [C/D] génère des 💎 passivement | *Planche à billets* : gros coup de cash |

### Bras Bourse 📈 — *spéculation*
| Module | Héros | Rar. | Passif | Signature |
|---|---|---|---|---|
| 📈 Bourse | **Warden Buffott** | C | [A] ×1.25 prod du module | *Volume* : ×3 prod du module 15 s |
| 🪙 Crypto | **Satoshi Nakomito** | R | [B] auto-clic (3 clics/s) | *FOMO* : pluie de clics auto 20 s |
| 🐋 Hedge Fund | **Georg Solros** | E | [A] ×prod de **tous les Rares** déployés | *Pump* : ×5 prod globale 10 s |

### Bras Immobilier 🏠 — *rente & idle*
| Module | Héros | Rar. | Passif | Signature |
|---|---|---|---|---|
| 🏠 Immobilier | **Sam Zello** | C | [D] ×1.5 gains hors-ligne | *Loyers* : encaisse une avance de loyer |
| 🏗️ Promotion | **Stephen Rolss** | R | [A] ×prod de tout le **bras** | *Chantier* : ×2 prod du bras 25 s |
| 🌆 Gratte-ciel | **Donald Trumb** | E | [A] +% prod **globale** du Dex | *Empire* : ×4 prod globale 12 s |

### Bras Industrie 🏭 — *production lourde*
| Module | Héros | Rar. | Passif | Signature |
|---|---|---|---|---|
| 🏭 Industrie | **Henry Frod** | C | [A] ×1.25 prod du module | *Cadence* : ×3 prod du module 15 s |
| 🚢 Commerce | **Aristote Onissas** | R | [A] booste les modules **en aval** (flux) | *Convoi* : ×2 prod en aval 25 s |
| 🛰️ Aérospatial | **Richard Brunson** | E | [C] −prix des gemmes | *Lancement* : prochain tirage gratuit |

### Bras Startup 💼 — *clic & croissance*
| Module | Héros | Rar. | Passif | Signature |
|---|---|---|---|---|
| 💼 Startup | **Steve Jorbs** | C | [B] +100 % puissance de clic | *Pitch* : clics ×10 pendant 15 s |
| 🦄 Licorne | **Pieter Thielo** | R | [C] +chance de tirage gratuit au gacha | *Levée* : +20 % drop pendant 5 tirages |
| 🌍 Conglomérat | **Geoff Bezus** | E | [F] ×prod par **synergie active** | *Fusion-acquisition* : active toutes les synergies 15 s |

### Bras Énergie 🛢️ — *puissance brute*
| Module | Héros | Rar. | Passif | Signature |
|---|---|---|---|---|
| 🛢️ Énergie | **John Lockefeller** | C | [D] +plafond de production hors-ligne | *Gisement* : double le stock idle |
| ⚡ Renouvelable | **Elron Tusk** | R | [A] ×prod des modules de **même rareté** | *Réseau* : ×2 prod des Rares 20 s |
| ☢️ Fusion | **Bill Gatts** | E | [A] ×prod **globale** (le plus fort) | *Réaction en chaîne* : ×8 prod 8 s |

-----

## 4. Synergies (famille F)

Bonus quand plusieurs héros sont **déployés en même temps** (sur un Dex) :

- **Synergie de bras** : les 3 héros d'un même bras (C+R+E) → **+25 % prod du bras**.
- **Synergie de rareté** : déployer 6 héros d'une rareté → bonus croissant (6 Épiques = effet ultime).
- **Synergies thématiques** (exemples) :
  - *Spéculation* : Bourse + Crypto + Hedge Fund + Licorne → +risque/+gain.
  - *Briques & mortier* : Immobilier + Promotion + Gratte-ciel + Industrie → +rente.
  - *Deep tech* : Aérospatial + Fusion + Renouvelable → +prod & −coûts.

-----

## 5. Régime de marché (famille G — le pilier, couche avancée)

Un **régime du jour** (🐂 BULL · 🐻 BEAR · 💥 CRASH · 🦀 CRABE · 🚀 HYPE) modifie
l'efficacité des héros selon leur **classe**. Un héros n'est jamais « plus fort »,
il est **adapté à autre chose** → on recompose ses déploiements selon le régime.

Classes (du GDD) et affinité forte :
- 🐂 Momentum → BULL · 🐻 Short Seller → BEAR/CRASH · 🦀 Market Maker → CRABE
- 💎 Diamond Hands → CRASH · 🚀 Degen → HYPE · 🛡️ Quant → polyvalent

> Couche **optionnelle / phase ultérieure** : on peut livrer le système héros sans
> les régimes d'abord, puis ajouter cette couche pour la rétention long terme.

-----

## 6. Fusion (famille — montée en puissance)

Les **doublons** montent le héros en niveau :
- chaque niveau **renforce le passif** (ex. +10 % de l'effet) et **améliore la
  signature** (cooldown −, durée/puissance +) ;
- surplus de doublons → **fragments** échangeables contre un héros choisi.

Détail chiffré : à définir à l'étape « Fusion ».

-----

## 7. Ordre de construction proposé

1. **Passifs** (familles A–D) : un effet par héros, déployable. *(socle)*
2. **Synergies** (F) : sets de bras / rareté / thème.
3. **Signatures** (E) : capacités actives à cooldown, déclenchées depuis une **barre
   d'abilities globale**.
4. **Fusion** : doublons → niveaux.
5. **Régimes** (G) : couche avancée (rétention long terme).
