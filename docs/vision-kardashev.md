# Vision — Refonte Kardashev

> **Statut : design verrouillé, pas encore codé.** Ce document est l'archive de la conception
> menée en dialogue (sparring adversarial, une pierre à la fois). Il fige le **squelette** —
> le régime permanent du jeu. Il ne décrit *aucun* chiffre ni aucune ligne de code : c'est
> l'ossature à protéger, pas l'implémentation. Mise à jour à chaque décision verrouillée.
>
> **Rapport à l'existant :** ceci **remplace conceptuellement** le thème finance de Dex Heroes.
> On garde la **plomberie** (moteur énergie×temps, gains hors-ligne, sauvegarde) ; on jette
> le **thème** (gacha finance, héros, valorisation, Exchange). Voir `CLAUDE.md` pour l'état du code actuel.

---

## 0. Le pitch en une phrase

Un *idle* de **contemplation** où tu élèves des civilisations sur l'échelle de **Kardashev**,
de l'étincelle au **Type III galactique** — seul, sereinement, en bifurquant à chaque Grand Filtre,
puis en peuplant une galaxie de civs complémentaires que ta **gravité** d'Architecte finit par fédérer.

Ton de bout en bout : **sérénité, émerveillement, mélancolie.** Jamais la peur, jamais la punition,
jamais la comparaison anxieuse. Le drame vient de l'**échelle**, pas de la menace.

---

## 1. Le moteur (vérité fondatrice)

- **La vérité est une formule close : énergie × temps.** Tout le reste en est une *lecture*, un vernis.
- **Le hors-ligne n'est jamais simulé** : progression = taux × temps. Une lecture gelée qu'on fait
  courir en avant. (Ce même tour — « lecture gelée qui court en avant » — resservira deux fois :
  pour la mémoire, et pour le multijoueur.)
- Les civilisations, les PNJ, les événements ne *causent* pas la formule : ils l'**habillent**.

---

## 2. Le fantasme & la mesure

- **Fantasme :** l'ascension d'une civilisation (arbre technologique). La finance est **abandonnée**.
- **Mesure / fin :** l'échelle de **Kardashev**. La victoire = **Type III** (maîtrise galactique).
- Le **triomphe est unique et sacré** — *pas* un prestige répété. (Voir §10 : il y en a même deux.)

---

## 3. Le drame — les Grands Filtres

Cadrés comme des **seuils de transformation et d'émerveillement** (« qu'est-ce qui a grandi ? »),
**pas** comme des portes de la peur.

Mécaniquement, un filtre n'est **pas un péage** (« il te faut X énergie ») — un péage se voit et se
prépare, il ne fait pas mordre la bifurcation. À la place :

- **Chaque filtre teste une capacité *différente*.** Une civ « haut-fragile » en franchit certains
  comme du beurre et s'étouffe sur d'autres — **sans savoir lesquels d'avance**.
- **Fixes mais cachés.** La gauntlet est constante ; on ne la connaît qu'en la vivant. La **mémoire**
  l'apprend run après run.
- **La gauntlet recule.** On n'apprend les filtres que jusqu'où des civs sont mortes ; au-delà, le noir.
  Le voile ne se lève pas, il **recule vers la frontière**. Le savoir ne supprime pas la difficulté,
  il la **relocalise** au front. (Vérité de tout bon idle.)
- **Les filtres connus se contredisent.** Aucune civ ne les passe *tous* (le 7 punit la fragilité,
  le 9 la récompense). Même à information parfaite, il reste un **dilemme** : « lesquels je sacrifie ? »
- Résultat : les premiers runs sont tendus par le **pari aveugle** ; les tardifs par le **choix
  tragique lucide**. Deux saveurs de la même bifurcation.

---

## 4. Les trois verbes (un seul geste à trois tempos)

| Verbe | Tempo | Rôle |
|---|---|---|
| **Répartir** | continu | Politique *permanente* d'écoulement de l'énergie entre les fronts (haut / large…). Incline la civ vers une **identité**. Hors-ligne honore les ratios → natif au moteur. |
| **Bifurquer** | discret | Le commit tranché à un Grand Filtre. La pente continue de *répartir* **cristallise** en porte. **C'est le verbe central.** |
| **Risquer** | ponctuel | La décision de **graduation** (voir §5). Pousser un filtre de plus dans le noir, ou lâcher prise. |

**Règle de viabilité de la bifurcation** (non négociable) : une bifurcation n'est réelle que si
*les deux chemins restent vivables*. Tenue honnête par (1) des **axes orthogonaux** (haut-fragile vs
large-increvable — pas meilleur/pire), (2) le **voile** (le prochain obstacle, inconnu, décide),
(3) le « meilleur » dépend de **ta situation**, pas d'un optimum absolu.

---

## 5. Graduation = le verbe *risquer*

Le moment où une civ cesse d'être la **frontière active** et devient un **nœud passif** producteur
(formule close). C'est une **décision**, pas un seuil automatique :

> « Je laisse graduer *maintenant* (sûr, mémoire connue), ou je pousse **un filtre de plus** —
> elle pourrait casser, mais si elle survit, une civ plus grande ? »

- **Si elle casse : mémoire *moindre*.** Pas de vide, pas de punition. L'échec **enseigne**.
- **Calibrage critique :** la mémoire moindre doit valoir **moins que la graduation sûre** ne
  l'aurait donné → casser = finir **sous la ligne de base** (jamais à zéro). Sinon *risquer* meurt
  indolore (« pousser paie toujours »). Plus le **temps** englouti par la civ brisée = les dents
  du risque, sans jamais montrer le gouffre.
- **Ton :** mélancolie (« elle aurait été quelque chose, et elle n'est plus que ça »), pas frustration.

---

## 6. Le macro — la galaxie

- **Forme : un graphe organique** (nœuds / constellations), pas une grille. Une galaxie *vivante*.
- Une civ diplômée se **place** dans le graphe. **Placer** est le verbe de l'Architecte (voir §7).
- **Les arêtes se forment seules**, par **complémentarité**, dans le **rayon de gravité** (§7).
  L'Architecte ne câble pas à la main → un seul geste (placer), sérénité préservée.
- **Identité = une seule substance.** Une civ *est* la signature des bifurcations qu'elle a prises.
  L'arbre du micro **définit** l'identité horizontale au macro. (Prix accepté : nouvelle saveur de
  civ = nouvelle branche d'arbre. Couplage assumé.)
- **Le macro oriente le micro sans le déterminer :** la galaxie te donne une **intention** (« vise
  large-increvable, il me manque ça ici »), jamais une garantie. La civ qui gradue est le **résidu**
  de la façon dont elle a *réellement* survécu. L'écart intention↔résultat = le drame de la bifurcation.
- **Contrainte cardinale — le piège de la monoculture :** la complémentarité doit récompenser le
  **mélange**, jamais la répétition. Une belle constellation est **bariolée**, jamais monochrome.
  La diversité devient quelque chose qu'on **voit**. (Sinon l'optimisation pousse vers l'uniformité,
  ce qui **inverse** la condition de victoire.)

---

## 7. L'Architecte & la chaîne

L'**Architecte** = l'identité méta persistante au-dessus des civilisations. Le « toi » qui se
souvient. Archétype : l'**horloger** — il fixe les conditions de départ, puis contemple.

La **progression verticale vit dans l'Architecte** (les civs restent « à taille humaine », elles
diffèrent *horizontalement*). Les deux axes ne se concurrencent jamais.

**Chaîne d'accumulation — une seule causalité, trois rôles non substituables :**

| Couche | Nature | Rôle |
|---|---|---|
| **Mémoire** | substrat passif, *ressenti* | Chaque civ diplômée laisse une trace. Cœur émotionnel. Jamais dépensée, jamais vraiment vide (l'échec laisse une mémoire moindre). |
| **Savoir** | couche *jouée* | Se lit dans la mémoire → éclaire la carte des filtres (§3), ouvre de nouvelles branches, traversées plus sûres. |
| **Gravité** | ce que le savoir *gagne* | = **la portée du champ** de l'Architecte. Décide jusqu'où une civ placée se câble. Faible au début (voisines proches) → forte (constellations entières). **Lier les civs = le mécanisme littéral du Type III.** |

> Mémoire → Savoir → Gravité. *Ressenti → joué → gagné.*

---

## 8. Le multijoueur — une fédération de *traces*

Galaxie partagée, **asynchrone**, **coopérative**, **zéro PvP**.

- **Vecteur choisi : la portée.** La gravité d'un autre Architecte atteint *faiblement* ta galaxie ;
  vous fédérez vers un **Type III partagé**. **Prix payé et assumé :** c'est de l'amplification
  **verticale** partagée (la gravité *est* verticale, par construction). « Horizontal uniquement »
  est **dépensé**. Mais elle **amplifie**, n'**active** jamais (voir §10).
- **La liveness est tuée par le modèle de *trace*** (= le tour du hors-ligne, une 3ᵉ fois) :
  - Un voisin est un **instantané gelé** d'une galaxie, puisé dans un bassin de **sauvegardes figées**.
    Personne n'a jamais besoin d'être en ligne. (Modèle « fantôme asynchrone ».)
  - Apparié à un moment **ponctuel** (quand tu gradues / gagnes de la gravité), au **ton tempo** —
    jamais au rythme d'un serveur. **Zéro re-brassage subi.**
  - **Don involontaire :** la gravité **rayonne** juste parce que ta galaxie existe et est grande
    (comme une étoile chauffe ses planètes). On ne peut ni la **retenir**, ni la **marchander**, ni
    la **retirer par dépit**. → zéro transaction, zéro otage, zéro trahison.
  - **Pas de scoreboard.** Tu *sens* la chaleur des Architectes proches ; tu ne vois jamais « le sien
    est plus gros ». Vertical dans le mécanisme, **horizontal dans la présentation**.
  - S'il s'efface, sa gravité **refroidit** comme une étoile mourante (mélancolie, pas punition).
- **Voisinage complémentaire :** les Architectes qui se réchauffent le mieux se **manquent**
  mutuellement. La complémentarité qui câblait les civs *dans* une galaxie recâble les galaxies
  *dans* une fédération. **Le même geste, une résolution de plus.**
- **Le cadeau caché :** la couche sociale **est** la couche mémoire. Les civs laissent des mémoires ;
  les Architectes laissent des traces de galaxie — *la même chose*. **Les autres Architectes sont
  des mémoires que tu n'as pas faites.** Le multi n'est pas un greffon : c'est la Mémoire étendue au ciel.

**Coûts résiduels à surveiller :**
1. **Première vraie dépendance backend** (bassin d'instantanés + appariement). Exigence : **dégradation
   gracieuse** — pas de réseau → pas de voisins → **solo intact** (la chaleur est amplification, jamais activation).
2. **Farming de galaxie bancale :** si une galaxie déséquilibrée attire de meilleurs voisins, les
   joueurs déséquilibreront *exprès* → inversion de la valeur cardinale (§6). Garde-fou nécessaire :
   récompenser ce qui *complète un bel ensemble*, pas ce qui *exhibe un trou*.

---

## 9. Le motif esthétique (la signature)

Tout le design est **le même geste vu à une autre résolution** :

- micro ↔ macro : élever une civ ↔ peupler une galaxie ;
- répartir ↔ bifurquer : la pente continue ↔ le commit discret ;
- civ ↔ galaxie : complémentarité *dans* la galaxie ↔ complémentarité *entre* galaxies ;
- mémoire ↔ fédération : tes traces ↔ les traces des autres.

C'est rare et c'est précieux. Toute extension future devrait **prolonger ce motif**, pas le contredire.

---

## 10. Les deux triomphes

- **Type III solo** — toujours atteignable **seul**. Sacré, unique. La règle « 100 % solo » tient
  **pour ta porte à toi**. La gravité d'autrui *amplifie* la route, ne la **débloque** jamais.
- **Type III partagé** — un *second* triomphe, **au-dessus**. Quand les gravités de plusieurs
  Architectes se chevauchent assez, la région qu'ils éclairent *ensemble* atteint une grandeur
  qu'aucun n'atteint seul. C'est du **rab**, pas la grille. Ne peut pas s'obtenir seul, et c'est
  très bien : ce n'est pas la condition de la victoire, c'est une victoire **en plus**.

---

## 11. La première heure (cold start) — *à concevoir*

⚠️ Tout ce qui précède décrit le **régime permanent**. Un nouvel Architecte a **une** civ, **zéro**
mémoire/savoir/gravité/voisin, une galaxie **vide**. La plupart des verbes **n'existent pas encore**
pour lui (rien à placer, rien à fédérer). Minute un = **répartir** vers un premier filtre.

**Question ouverte (la prochaine pierre) :** dans quel **ordre** la machine se révèle-t-elle ?
Qu'est-ce qui doit accrocher dès la minute un, *avant* toute couche méta ? C'est là que meurent la
plupart des beaux idle. À résoudre avant de construire.

---

## 12. Plan de construction (pour ne rien gâcher)

L'ordre est sacré — **jamais tout d'un coup**, sous peine de se noyer dans la méta avant d'avoir une
seconde de jeu amusant.

1. ✅ **Mettre le squelette à l'abri** — ce document.
2. **Le noyau seul, jetable** — *une* civ : répartir → filtre caché → bifurquer → risquer/graduer.
   Cent lignes, moche. **Seule question : est-ce amusant 20 minutes ?** Si non, aucune méta-couche
   ne le sauve (et on l'aura appris à bas coût).
3. **Ordre de révélation** — graduation → placement → galaxie → mémoire → savoir → gravité →
   fédération. **Chaque couche seulement quand celle d'en dessous a prouvé qu'elle méritait sa place.**

Plomberie réutilisable de Dex Heroes : moteur énergie×temps, hors-ligne, sauvegarde. Thème : jeté.

---

## 13. Fils ouverts (non tranchés)

- **§11 — la première heure / ordre de révélation** (prochaine décision de design).
- **Qu'y a-t-il *après* le triomphe solo**, si ce n'est pas un prestige répété ?
- Tout le **chiffrage** (taux, coûts, courbes, calibrage du « sous la ligne de base », % de chaleur,
  taille du bassin d'appariement, bandes d'échelle). Aucun nombre n'est verrouillé.
- Garde-fous d'implémentation : monoculture (§6), farming de galaxie bancale (§8), dégradation
  gracieuse du backend (§8).
