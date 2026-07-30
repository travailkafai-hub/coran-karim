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

---

# Partie II — Le biais canonique : pourquoi une vraie faute passe au vert

*Ajouté le 2026-07-30 au soir, après que l'utilisateur a récité `زَزَقْنَـٰهُمْ`
au lieu de `رَزَقْنَـٰهُمْ` et que l'app l'a colorié **vert**.*

## 9. Le fait, mesuré sur sa voix

| fenêtre donnée au modèle | ce qu'il écrit |
|---|---|
| **étroite** (le mot seul, 2 s) | **`زَ`** — le ز réellement prononcé |
| **large** (la phrase, 7,5 s) | `رَزَقْنَـٰهُمْ` — la forme **canonique** |

Le modèle **entend** la faute et la **corrige** dès qu'il a le contexte de la
phrase. Vérifié ensuite sur **12 modèles sur 12** : en fenêtre large, *tous*
écrivent la forme canonique, sans exception. Ce n'est donc pas un défaut du
modèle déployé — c'est une propriété de la façon dont ils ont tous été
entraînés.

## 10. La cause racine, trouvée dans les données

Le manifeste d'entraînement (`nemo_manifests_dual`, 156 892 exemples) contient
bien des contre-exemples : 81 380 clips à fautes délibérées, et ils sont
**correctement étiquetés** — le texte est celui **réellement prononcé**, jamais
le canonique (vérifié : 81 380 sur 81 380).

Le problème est ailleurs :

| | n | durée médiane | **mots par clip** |
|---|---|---|---|
| contre-exemples à fautes (TTS) | 81 380 | 1,71 s | **1 — toujours 1, maximum 1** |
| Coran récité (sans faute) | 75 512 | 10,40 s | 9 (jusqu'à 98) |

**Tous les contre-exemples sont des mots isolés.** Le modèle n'a jamais vu une
*phrase* contenant une faute. Il a donc appris deux régimes disjoints :

- **fenêtre courte** → régime « mot isolé », où il a vu des fautes → il
  transcrit fidèlement ;
- **fenêtre longue** → régime « phrase coranique », où **tout ce qu'il a vu
  était parfait** → il applique son a priori de séquence et corrige.

C'est exactement le comportement observé. Et c'est structurel pour la chaîne
v2, qui juge sur des blocs de 5 à 15 s — en plein dans le régime biaisé.

## 11. Ce qui a été essayé et qui ne marche pas : le montage audio

`benchmark/build_confusable_splice_augmentation.py` (écrit le 2026-07-14,
jamais utilisé) fabrique une faute **en vraie voix** : il repère par alignement
forcé les frontières d'une lettre dans un clip réel et y greffe un segment réel
contenant la lettre confusable, prélevé ailleurs dans le corpus.

Exécuté pour la première fois le 2026-07-30 (après réparation du symlink
`benchmark/data/train_wav`, cassé par un reparse tag Windows) :

```
original : ... أَكْثَرَ ٱلنَّاسِ لَا يَعْلَمُونَ
monté    : ... أَكْثَرَ ٱلنَّاصِ لَا يَعْلَمُونَ    (س → ص, segment réel de 80 ms)
```

**Vérification, et elle est négative** : sur le fichier monté, le modèle lit
`ٱلنَّاسِ` — la lettre **d'origine** — en fenêtre étroite comme en fenêtre large.

Cause : le segment remplacé fait **une seule frame (80 ms)**, parce que
l'alignement CTC est *peaky* — il marque la frame où la lettre culmine, pas
l'**étendue acoustique** du phonème. L'outil étiquetterait donc `ص` un son qui
reste `س`. **Entraîner là-dessus apprendrait l'inverse de ce qu'on veut.**

⇒ Le montage n'est pas utilisable tant qu'il ne remplace pas l'étendue réelle
du phonème. C'est précisément le risque que son auteur avait signalé en tête de
fichier (« écouter plusieurs exemples avant une augmentation à grande échelle »).

## 12. Comparaison des modèles — sur les DEUX axes

Mesure à découpage identique, flux brut de référence. **Détection** = fautes
injectées dans la cible (1 mot sur 5) et signalées ; **collatéral** = mots
intacts devenus non verts.

| modèle | faux positifs | détection | collatéral |
|---|---|---|---|
| **causal-v1 (déployé)** | **2,03 %** | **100 %** | **2,44 %** |
| tajweed-v2_059 | 12,93 % | 100 % | 12,65 % |
| pcd_ACTUEL_v1 | 12,59 % | 95,9 % | 11,43 % |
| mixed-e02 | 9,18 % | 100 % | 13,06 % |

Les concurrents transcrivent mieux (4,05 % d'erreur mot contre 7,77 %) mais
**jugent bien plus mal** : ils signalent 12 à 13 % de mots corrects. Le modèle
déployé reste le bon choix pour juger — c'est la mesure, pas une préférence.

## 13. Les trois familles d'architecture, vérifiées dans les POIDS

Le nom d'un modèle ne dit pas son architecture. Vérifié en listant les
paramètres des checkpoints, pas en lisant les exports :

| forme | où ça se voit | modèles |
|---|---|---|
| tête tajwid séparée (19 classes) | 2ᵉ sortie ONNX + `rules.json` | les 5 `deploy/*dual-head*`, et `causal-stageb` |
| règles en **symboles dans le vocabulaire** | 40 pièces en zone privée Unicode | `rules-260h_stage1b`, `rules-260h_piste3` |
| aucune | — | `pcd`, `mixed-e02`, `tajweed-augmented`, `tajweed-epoch09`, `tajweed-v2`, `causal-v1` |

`tajweed-epoch09` et `tajweed-v2` s'appellent ainsi parce qu'ils ont été
entraînés sur du texte **annoté** tajwid, pas parce qu'ils ont une tête dédiée :
leur `ctc_decoder` sort 1025 classes (1024 lettres + blank), et aucun paramètre
ne contient `tajwid`. Les deux `rules-260h`, qui mélangent règles et lettres
dans un seul softmax, sont les **pires de tous** (67 % d'erreur mot) — ce que la
mesure d'origine annonçait déjà (« les règles volaient ~20 % de masse de
probabilité aux lettres »).

## 14. Historique des entraînements

| date | run | résultat | statut |
|---|---|---|---|
| 25/07 23:38 | `streaming-causal-v1` | val_wer_ctc 0,492 | abandonné |
| **26/07 07:17** | **`streaming-causal-v1-lr3e4`** | **0,183** (epoch 18) → `causal-final.nemo` | **déployé** |
| 26/07 08:08 | `causal-v2-cycle2-BUGGY-wrong-init` | — | jeté (init fausse) |
| 26/07 08:26 | `causal-v2-cycle2` | 0,195 (epoch 0) | pas mieux |
| 26/07 11:16 | `dual-head-v1/stageb-causal-v1` | val_tajwid 0,190 (epoch 4) | **jamais déployé** |
| 26/07 16:16 | `causal-v3` | **0,180** (epoch 0) | abandonné — « silence hors distribution » |
| 27/07 00:09 | `nemotron-ctc-v1` | val_wer 0,628 | jamais exporté |

À noter : **`causal-v3` était meilleur dès l'epoch 0** (0,180 contre 0,183 après
18 epochs) et a été abandonné pour un problème de silence hors distribution,
pas de qualité. À rouvrir si l'on relance un cycle.

## 15. Le cahier des charges, et ce qu'il reste à faire

Fixé par l'utilisateur le 2026-07-30 :

> « le modèle doit être juste pour transcrire et valider **sans être biaisé** ;
> quand il y a une faute il la fait savoir, sinon pas d'utilité. Et la tête
> tajwid c'est optionnel, quand c'est activé, juste pour préciser les mots où le
> tajwid est absent. »

**Tête 1 — juger sans biais.** Il faut des contre-exemples **au niveau de la
phrase** : des versets entiers dont **un mot** est fauté, étiquetés avec le texte
prononcé. Les 18 195 fautes existent déjà (9 723 harakat, 8 472 lettres, avec
`kind` et `detail` du type `ه->ح`) ; ce qui manque, c'est leur **contexte**.
La voie praticable est celle qui a produit ces fautes : **XTTS-v2 avec clonage
vocal sur de vrais récitateurs du corpus** (`generate_tts_augmentation.py`),
appliqué à des versets entiers au lieu de mots isolés. Le montage audio, lui,
est écarté par la mesure (§11).

**Tête 2 — tajwid, optionnelle.** Déjà entraînée (`causal-stageb`, val_tajwid
0,190), déjà fonctionnelle — 9 règles distinctes détectées sur un seul bloc de
l'audio utilisateur. Tout est prêt côté app : `expectedRules` est peuplé depuis
`text_uthmani_tajweed`, `decodeTajwid` rend la frame de chaque règle (donc
l'attribution au mot se fait par recouvrement), et `RecitationErrorKind.tajwid`
existe. Deux verrous seulement : le modèle à deux têtes n'est pas déployé, et
`FrontAcoustique` ne lit que `logprobs`. Un troisième garde-fou est explicite
dans le code et devra être levé sciemment :

```kotlin
require(!hasTajwidHead) { "ce deploiement causal doit rester sans tete tajweed" }
```

**Ce que la tête tajwid ne fera jamais** : voir un `ز` à la place d'un `ر`.
C'est une lettre, pas une règle. Trois erreurs, trois mécanismes :

| erreur | exemple | ce qui la détecte |
|---|---|---|
| lettre | `ز` pour `ر` | fenêtre **étroite** — et, à terme, un modèle non biaisé |
| harakat | `رَ` pour `رُ` | GOP, faiblement (−0,16 à −0,90 mesuré) |
| règle | madd raccourci, ghunnah oubliée | **tête tajwid** |
