# Les solutions de la chaîne v2 — ce qui a été corrigé, et pourquoi

Écrit le 2026-07-30, branche `recitation-v2`. Tout chiffre de ce document vient
d'**une seule mesure de référence** : le flux micro **brut** d'une récitation
professionnelle (379,8 s, 296 mots, capté par le téléphone qui écoutait pendant
la recette à deux téléphones de 17:30), rejoué dans la chaîne v2 avec le modèle
causal du téléphone.

| | mots non verts |
|---|---|
| v1 en production | **10,10 %** |
| **v2** | **2,03 %** |
| borne haute de preuve | 2,03 % — la décision ne perd plus rien |

Sur cette session, **aucun des mots signalés par la v1 n'était une faute de
récitation** : les 10 points d'écart sont entièrement de l'architecture.

---

## 1. « Le GOP forced condamne alors que le free est confiant »

### Le défaut

```
mot 172   gop = -11,14   free = -0,01   entendu = ""
mot 228   gop =  -8,79   free = -0,05   entendu = ""
mot 172   gop = -14,18   free = -0,34   entendu = "ٱلْبَرْء"   ← l'audio du mot 170
```

`free` proche de 0 signifie que **le modèle sait exactement ce qu'il entend**.
Si malgré ça le score forcé s'effondre, ce n'est pas que le mot est mal
prononcé : c'est qu'il **n'est pas là**. L'alignement forcé est obligé de placer
tous les mots qu'on lui donne — quand on lui demande un mot absent, il le pose
sur l'audio du voisin et rend un score catastrophique.

### La solution, en trois pièces

**a) Ne demander à la DP que ce que le décodage libre atteste.**
La bande de mots soumise à l'alignement va désormais du **premier mot attesté**
au **dernier mot attesté** — plus de marge inventée au-delà. Avant, elle partait
du point de départ du *balayage* : un bloc contenant les mots 12→25 se voyait
réclamer les mots 0→25.

```
f0 (18,00 s)   mot 2   gop =   0,00   entendu = "كَفَرُوا۟"     ← correct
f2 (13,52 s)   mot 2   gop = -21,84   entendu = ""          bande = 0..25
```

Effet : les dégâts croissaient avec la longueur du bloc — 36,6 % de non-verts en
fenêtres de 6 s, **80,0 %** en blocs de 18 s.

**b) Un mot posé sur l'audio d'un autre mot ne vote pas** (`sansCreneau`).
Si les frames attribuées à un mot **chevauchent** la plage d'un autre mot que le
décodage libre a réellement entendu, l'observation est enregistrée mais ne peut
produire aucun verdict. C'est une **géométrie**, pas un seuil : aucune durée de
référence, aucune tolérance.

**c) Aucun verdict sur `entendu` vide.**
Un `entendu` vide veut dire que les frames attribuées **n'émettent rien** : la DP
a posé le mot sur du silence ou une transition. On ne peut rien en conclure — ni
« bien », ni « mal » prononcé. C'est littéralement le contrôle bloquant du
superviseur, et **la v1 le viole 5 à 6 fois par session**.

> Ce n'est pas une tolérance : une faute de prononciation produit un **autre
> mot**, pas rien. Le cas « mot non prononcé » a son propre statut, `Omis`, qui
> repose sur une preuve **positive** (des mots postérieurs sont validés).

---

## 2. Les mots coupés à la frontière

### Le défaut

En v1, 47,4 % des coupes tombaient en plein mot. Un mot coupé n'existe entier
**nulle part** : ni dans le segment qui finit, ni dans celui qui commence. Toute
la famille de rustines de la v1 (`MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex`,
tolérance aux fragments, tolérance au bleed, filet décodage-libre, second buffer
de secours) existait pour compenser ça.

### La solution : ne plus jamais couper dans la parole

**a) Les bornes tombent là où le récitateur se tait.** C'est le point central, et
il est mesuré. Même audio, même modèle, seule la politique de découpage change —
erreur mot du décodage libre :

```
fichier entier, aucune coupe ................ 54,05 %   (202 mots lus)
clips du portier RMS recollés (44 blocs) .... 29,05 %   (269 mots lus)
regroupés ~18 s (17 blocs) .................. 39,19 %   (244 mots lus)
COUPÉ AUX SILENCES RÉELS (20 blocs) ......... 14,86 %   (307 mots lus)
                             lettres seules :  7,43 %
```

Ce n'est **pas la longueur** du bloc qui compte. Un bloc délimité par des
silences réels *est* un clip d'entraînement ; un bloc de 6 s qui commence en
plein mot est hors domaine, aussi régulier soit-il.

**b) Le bloc contient le silence ENTIER, pas la moitié.** La première version
coupait au milieu du silence : chaque bloc ne gardait que ~0,15 s de pause à
droite, alors que le modèle causal exige **1,04 s d'audio postérieur**. Le
dernier mot de chaque énoncé était donc toujours « au bord », jamais votant, et
déclaré *omis* — **alors qu'il était lu parfaitement** :

```
mot  67  أَلَآ         gop = 0,00   entendu = "أَلَآ"        → Omis
mot 287  مُتَشَـٰبِهًا  gop = 0,00   entendu = "مُتَشَـٰبِهًا"  → Omis
```

La fermeture du bloc est maintenant **retardée** jusqu'à avoir capté un
lookahead complet après la dernière parole. Les blocs **se recouvrent sur les
silences** : aucun mot n'est au bord de quoi que ce soit, ce sont les silences
qui le sont.

**c) Le silence n'est plus jeté.** Le portier de la v1 supprimait le silence
au-delà de 0,3 s. Preuve directe qu'il détruisait l'information : rejouée sur le
flux **brut** au lieu des clips recollés, la première v2 rendait **exactement le
même taux** (36,61 %) — son propre portier reconstruisait le flux mutilé. Le
silence n'est pas du bruit : c'est le **séparateur** et le **contexte droit**.

---

## 3. L'alignement et l'ancre

### Le défaut

La v1 portait une **ancre mutable** : une position incrémentée d'une passe à
l'autre. Une erreur s'y installait et ne se corrigeait plus — mesuré, l'ancre
prenait **57 mots de retard** avant le décrochage, et `findResyncOffset` ne
cherchait **qu'en avant** (un récitateur qui répète ne pouvait structurellement
pas être suivi). Les tentatives de rattrapage jetaient des mots corrects
(8,16 % → 13,40 %).

### La solution : il n'y a plus d'ancre

**a) La position est ré-estimée à chaque bloc**, depuis l'acoustique, jamais
incrémentée depuis l'historique. Une erreur ne dure donc qu'un bloc.

**b) La recherche est bornée des deux côtés.** Un récitateur qui répète est
suivi — le recul est journalisé, jamais silencieux.

**c) Déplacer la position n'abandonne aucun mot.** C'est le couplage qui avait
tué la v22 : « déplacer l'ancre » ⇒ « les mots derrière sont perdus ». Ici les
deux opérations sont décorrélées : les mots dépassés restent dans le registre de
preuves, éligibles à n'importe quel bloc ultérieur, et leur audio est toujours
dans le flux brut.

**d) L'appariement est un vrai alignement (LCS), sans aucun seuil.** L'ancienne
version avançait mot par mot et abandonnait après **3 mots non reconnus** — un
seuil que rien ne justifiait. Sur des blocs longs, trois substitutions groupées
suffisaient : l'ancre restait bloquée au mot 82 sur 295. Une LCS traite les
insertions et suppressions comme des trous du chemin, pas comme des motifs
d'abandon.

**e) Deux mesures indépendantes valent deux fenêtres.** Le décodage libre ignore
le texte attendu, l'alignement forcé le connaît : quand les deux concordent sur
le même audio, on tient deux preuves indépendantes. Exiger deux *fenêtres* était
une approximation de « exiger deux *preuves* » — et la deuxième fenêtre
apportait une preuve systématiquement **dégradée** (`ٱلْبَرْ` pour `ٱلْبَرْقُ`).

---

## 4. « Faut-il que le récitateur fasse des pauses ? »

**Non. Il récite normalement.**

La « pause » de 0,40 s n'est pas un arrêt demandé au récitateur. C'est un moment
où l'**énergie du signal descend** sous 3 % pendant 400 ms — ce qui arrive
naturellement et constamment en murattal : reprises de souffle, fins de groupe
de souffle, marques de waqf, fins de verset.

Sur la récitation de référence, sans aucune consigne particulière, le détecteur a
trouvé **102 de ces moments en 380 s — un toutes les 3,7 s en moyenne**. Le
récitateur n'a rien fait de spécial ; il a respiré.

**Et s'il ne s'arrête jamais ?** Un garde-fou coupe à 30 s, au point le moins
énergique disponible. C'est dégradé mais pas cassé — et avec le réglage retenu il
ne se déclenche jamais. S'il se déclenche, c'est un symptôme à instruire, pas un
réglage à baisser (mesuré : à 18 s, il coupait en pleine parole et faisait passer
le taux de 11,86 % à **51,53 %**).

### Le couple pause / seuil RMS

Les deux paramètres ne se lisent **pas séparément** :

```
pause   rms     blocs   non verts
0,30    0,01      39     73,56 %
0,35    0,01      39     73,56 %
0,30    0,02      60      3,39 %
0,35    0,02      53     65,76 %
0,30    0,03     127      4,41 %
0,35    0,03     104      2,71 %
0,35    0,035    112      4,41 %
0,40    0,03     102      2,03 %   ← retenu
0,45    0,03     102      2,03 %   ← même chiffre : vrai PLATEAU
```

Ce qui pilote le taux, c'est le **nombre de blocs** que le couple produit : trop
peu (39) et les blocs sortent du domaine du modèle ; trop (127) et chaque
frontière est une occasion de se tromper. L'optimum est un **plateau**, pas un
pic — 0,40 et 0,45 donnent le même résultat. C'est la seule forme de réglage
acceptable : un pic isolé aurait été un accident, pas une propriété.

---

## 5. Ce que le modèle a à voir là-dedans : rien, ou presque

Contre-intuitif et mesuré. À découpage identique, sur le même flux brut :

| modèle | erreur mot (transcription) | mots non verts (jugement) |
|---|---|---|
| tajweed-v2_059 | **4,05 %** (le meilleur) | **10,88 %** (le pire) |
| tajweed-epoch09 | 4,39 % | — |
| mixed-e02 | 5,74 % | 11,90 % |
| **causal-v1 (déployé)** | 7,77 % | **2,03 %** |

Le décodage libre et l'alignement forcé **ne mesurent pas la même chose**. Un bon
transcripteur n'est pas automatiquement un bon juge. Changer de modèle n'est donc
pas le levier — l'architecture l'est.

---

## 6. Ce qui reste : 6 mots sur 295

La borne haute de preuve vaut aussi 2,03 % : **la décision ne perd plus rien**,
chaque mot restant est un mot qu'aucun bloc ne lit correctement.

| mot | ce que c'est |
|---|---|
| 67 `أَلَآ`, 228 `وَإِن` | lus parfaitement (`gop = 0,00`, texte exact) mais toujours au **bord** d'un bloc → jamais votants |
| 172 `أَبْصَـٰرَهُمْ` | entendu `أَبْصَـٰرُهُمْ` — vraie divergence de **harakat** (َ vs ُ) |
| 181 `قَامُوا۟` | le modèle hésite (`free = -1,71`), confusion م/ل |
| 2 autres | artefacts d'allongement (token doublé) |

---

## 7. Ce que cette version PERD, et qu'il faut savoir

- **Le délai de verrouillage n'est plus constant.** Un mot est jugé quand son
  énoncé se termine, donc le délai suit la longueur de l'énoncé — comme en v1.
  La grille régulière promettait un délai constant ; elle valait **32 points de
  taux**, l'échange a été fait sciemment.
- **La v2 n'est branchée sur rien.** Elle ne tourne que dans le banc. Une recette
  à deux téléphones mesure aujourd'hui la v1.
- **Le chiffre vient d'UNE session.** Une récitation, un récitateur, un
  téléphone. La prochaine étape est la recette à deux téléphones.

---

## 8. Comment refaire la mesure

```bash
# 1) la couche B décide les blocs (vrai code de l'app, en JVM)
cd app/android && ./gradlew --offline :app:testDebugUnitTest \
    --tests "*BancFluxBrut.blocs*" --rerun-tasks \
    -DpauseMin=0.40 -DseuilRms=0.03 -DmaxBloc=40

# 2) le modèle calcule les logprobs de CES blocs-là, et rien d'autre
PYTHONPATH="benchmark/.venv_nemo/lib/python3.14/site-packages:benchmark" \
    python3.14 benchmark/logprobs_blocs.py

# 3) les couches D/E/F/G rendent le verdict
cd app/android && ./gradlew --offline :app:testDebugUnitTest \
    --tests "*BancFluxBrut.juger*" --rerun-tasks
```

~30 s par itération, sans téléphone. Les couches B/D/E/F/G n'ont **aucune
dépendance Android ni ONNX** : le banc **appelle le code de l'app** au lieu de
l'imiter — c'est ce qui évite le piège payé deux jours de suite sur ce projet
(« le banc mesurait mon découpage, pas l'app »).

Plancher du modèle : `benchmark/plafond_modele.py` et
`benchmark/comparer_modeles_flux_brut.py`.
