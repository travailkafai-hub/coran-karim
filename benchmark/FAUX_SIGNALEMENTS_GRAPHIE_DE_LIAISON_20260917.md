# La graphie de liaison : une cause de faux signalements jamais vue

17 septembre 2026. Analyse **mot par mot** des 58 faux signalements du banc
d'erreurs réelles, sans hypothèse de départ : mesurer plusieurs propriétés du
mot et regarder laquelle sépare les mots faussement signalés des autres.

Le résultat n'était dans aucune des pistes explorées les deux jours précédents.

---

## 1. Ce que l'analyse a trouvé

Sur 58 faux et 659 mots corrects, sept propriétés ont été comparées (longueur,
distance à l'erreur la plus proche, position dans le verset, fréquence,
nombre d'observations…). Une seule sépare nettement :

| | faux | mots | taux |
|---|---:|---:|---:|
| mots à **shadda initiale** | 10 | 35 | **28,6 %** |
| tous les autres | 48 | 682 | **7,0 %** |

**Un mot dont la première lettre porte une shadda est faussement signalé
quatre fois plus souvent.** Les cas sont sans ambiguïté — la shadda est la
*seule* différence :

```
لَّا         lu لَا         ×2  → definitif:ROUGE
لَّكُمْ      lu لَكُمْ      ×2  → definitif:ROUGE
مُّسْتَقِيمٍ  lu مُسْتَقِيمٍ  ×2  → definitif:ROUGE
مَّا         lu مَا         ×2  → definitif:ROUGE
```

### Pourquoi c'est l'application qui a tort

En arabe coranique, une shadda sur la **première** lettre note un **idghām
avec le mot précédent** : `مِن مَّا`, `عَن رَّبِّ`. Le doublement naît de la
rencontre des deux mots ; le mot seul ne le porte pas. Le récitateur ne
prononce pas une consonne doublée sortie de nulle part — le modèle transcrit
`مَا`, et **c'est lui qui a raison phonétiquement**.

L'application comparait une **graphie de liaison** à une **transcription de
prononciation**.

---

## 2. La même règle, vue de l'autre côté

L'idghām fait disparaître le `نْ` final d'un mot **dans** la consonne initiale
du suivant — et cette consonne devient double, ce qui s'écrit par une shadda.
**Une seule règle de récitation, deux faux signalements** : le mot qui perd sa
finale, et le mot qui gagne la shadda.

| contexte | faux | mots | taux |
|---|---:|---:|---:|
| **idghām** applicable | 18 | 166 | **10,8 %** |
| **ikhfā'** applicable | 7 | 70 | **10,0 %** |
| iqlāb | 0 | 7 | 0 % |
| aucune règle | 33 | 474 | **7,0 %** |

```
ٱلرَّحْمَـٰنِ  + لَا       [idghām]  lu ٱلرَّحْمَـٰ
لِلْمُتَّقِينَ + مَفَازًا   [idghām]  lu ٱلْمُتَّقِينَ
كَبِيرٍ       + وَقَالُوا۟  [idghām]  lu كَبِيرٌ
```

Le projet possède pourtant une **tête tajwid** (`rules.json`,
`tajwid_logprobs`, `seuils_tajwid.json`) qui sait détecter ces règles. Mais le
**jugement de texte** ne s'en sert pas : il compare `entendu` à `attendu` sans
savoir qu'une règle autorise la différence.

---

## 3. Corrections appliquées

**Bilan des deux : faux signalements 8,1 % → 7,3 % sur le vote, 2,0 % → 1,8 %
sur la chaîne historique, détection inchangée à 68 %.** Cinq faux supprimés,
aucune détection perdue.

### (a) Shadda initiale — `Orthographe`, famille (11)

Une variante sans la shadda de liaison est ajoutée aux équivalences, **sur la
première lettre uniquement**.

| | avant | après |
|---|---:|---:|
| mots à shadda initiale | 10/35 — 28,6 % | **6/35 — 17,1 %** |
| **tous les autres mots** | 48/682 — 7,0 % | **48/682 — 7,0 %** |
| vote — faux signalements | 58/717 — 8,1 % | **53/717 — 7,4 %** |
| historique — faux | 14/713 — 2,0 % | **13/713 — 1,8 %** |
| **détection** | 54/80 — 68 % | **54/80 — 68 %** |

**Quatre faux supprimés, aucune détection perdue**, rappel identique famille
par famille. Le contrôle qui valide le ciblage : **les 682 autres mots sont
strictement inchangés**. Une équivalence orthographique ne doit rien changer
ailleurs — si le chiffre global avait bougé, il aurait fallu la retirer.

⚠️ **Première lettre seulement.** Les shaddas internes (`ٱلرَّحْمَـٰنِ`,
`يَتَكَلَّمُونَ`) sont des propriétés du mot ; les retirer blanchirait de vraies
fautes de gémination. La recherche s'arrête dès qu'une seconde consonne
apparaît.

Les 6 faux restants ne relèvent pas de la liaison : `رَّبِّ` lu `سَ`,
`لَّـٰبِثِينَ` sans aucune lecture exploitable — ce sont des cas de fenêtre.

### (b) Finales assimilées — `Orthographe.variantesLiaison`, branchée dans `Decideur`

Un `نْ` final ou un tanwīn devant une lettre d'idghām ou d'ikhfā' peut être
absent de la transcription.

⚠️ **Conditionné au mot suivant, et c'est tout l'intérêt** : une finale absente
**sans** règle qui l'explique reste une faute. C'est pourquoi cette fonction ne
vit pas dans `Orthographe.variantes`, qui ne voit qu'un mot isolé — elle est
appelée depuis `Decideur.statutsVote`, seul endroit qui connaît le mot suivant.

**Résultat mesuré : effet marginal — UN seul faux supprimé.**

| | départ | après (a) | après (a)+(b) |
|---|---:|---:|---:|
| vote — faux signalements | 58 — 8,1 % | 53 — 7,4 % | **52 — 7,3 %** |
| contexte idghām | 10,8 % | — | 10,2 % |
| contexte ikhfā' | 10,0 % | — | 8,6 % |
| détection | 68 % | 68 % | **68 %** |

**Pourquoi si peu, et c'est l'enseignement** : le contexte d'idghām était
**corrélé** aux faux sans en être la cause dans la majorité des cas. Relecture
des cas qui restent :

```
لِلْمُتَّقِينَ lu ٱلْمُتَّقِينَ  ← ce n'est PAS la finale, c'est le لِ INITIAL
                                   qui manque : une particule, pas un idghām
```

Les mots en contexte d'idghām sont souvent longs et précédés d'une particule —
deux propriétés qui les exposent aux causes déjà connues. La corrélation à
10,8 % était réelle ; le lien causal est beaucoup plus étroit qu'elle ne le
laissait croire.

⇒ La correction est **conservée** : elle supprime un faux, n'en ajoute aucun,
ne coûte aucune détection, et traite un cas réel (`ٱلرَّحْمَـٰنِ` lu
`ٱلرَّحْمَـٰ`). Mais elle ne doit pas être présentée comme la réponse aux 10,8 %.

**Leçon de méthode** : une corrélation forte sur une sous-population n'est pas
une cause. La shadda initiale, elle, était causale — les cas montraient la
shadda comme SEULE différence. L'idghām ne l'était qu'en partie.

---

## 3bis. Les CONDITIONS D'ECOUTE du modele — mesure forte, levier nul

Question posee : « le modele peut se comporter mieux ». Verifie, et c'est vrai
au niveau des LECTURES. Sur 2 139 observations de mots CORRECTS, taux de
lecture erronee selon le contexte audio disponible A GAUCHE du mot :

| contexte avant le mot | lectures erronees |
|---|---:|
| < 0,5 s | **69,1 %** |
| < 1,0 s | **78,4 %** |
| < 2,0 s | 26,7 % |
| < 3,0 s | **4,7 %** |
| >= 3,0 s | **3,6 %** |

| place du mot dans la fenetre | lectures erronees |
|---|---:|
| tout debut (< 20 %) | **40,8 %** |
| milieu (40-60 %) | **4,6 %** |

**Le meme encodeur, sur le meme mot, passe de 69 % a 3,6 % d'erreur selon ce
qu'il a entendu avant.** L'encodeur est CAUSAL : sans etat accumule, il devine.
Ce n'est pas le modele qui echoue, ce sont les conditions qu'on lui donne.

Et le parametre existait : `AligneurForce.margeGaucheFrames` vaut **2 frames
(160 ms)** -- en plein dans la zone a 69 %.

### Mesure a 25 frames (2 s de contexte exige)

| | marge 2 | marge 25 |
|---|---:|---:|
| detection | 54/80 - 68 % | **56/80 - 70 %** |
| faux signalements | 52 - 7,3 % | **56 - 7,8 %** |
| particule retiree | 67 % | **75 %** |

**+2 detections, +4 faux. Pas de gain net.**

POURQUOI : le vote **filtrait deja** ces lectures. Une lecture faite sans
contexte produit un mot tronque ou incomplet, donc `fragment_alignement` ou
`lecture_non_complete` -- deux exclusions deja en place. Le gain etait capte
avant d'arriver a la decision.

⇒ `margeGaucheFrames` reste a **2 (production inchangee)**, balayable par
`-DmargeGauche=N` sur le banc.

### La lecon, et c'est la deuxieme fois le meme jour

**Une correlation forte sur les OBSERVATIONS ne dit pas qu'il reste un gain a
prendre sur les VERDICTS.** L'idgham a 10,8 %, le contexte a 69 % : les deux
correlations etaient reelles, les deux etaient deja neutralisees en aval.
Seule la shadda initiale etait un vrai levier -- parce que la, rien en aval ne
la traitait, et les cas montraient la shadda comme SEULE difference.

Avant d'implementer sur la foi d'un ecart de taux, verifier ce que les couches
suivantes en font deja.

---

## 4. Pourquoi personne ne l'avait vu

Le projet normalise pour **localiser** les mots, mais compare **exactement**
pour **juger** — c'est une règle écrite (`piege_attestation_normalisee_blanchit` :
« normaliser pour TROUVER, comparer exactement pour CONFIRMER »).

Cette règle est juste pour les harakat, qui distinguent de vraies fautes. Elle
ne l'est pas pour les marques de **liaison**, qui ne sont pas des propriétés du
mot mais de sa rencontre avec le suivant.

Et ces deux corrections ne sont pas des tolérances, au sens de l'en-tête
d'`Orthographe` : **les variantes produites se prononcent exactement comme
l'original**. Aucune faute de prononciation ne peut passer par là.

---

## 5. Ce que cela ne corrige pas

Le trou principal reste entier : **particule ajoutée 52 %, particule retirée
67 %**, contre 100 % sur les flexions finales. Le modèle acoustique n'émet pas
de façon fiable `وَ`, `فَ`, `بِ` — cf.
`DIAGNOSTIC_PARTICULES_20260916.md`. Aucune équivalence orthographique ne
rattrape un son que le modèle n'a pas produit.

---

## Reproduire

```powershell
python benchmark/analyser_faux_mot_par_mot_20260917.py
cd app/android
.\gradlew.bat '-DasrBanc=true' '-DteteT3=benchmark/tetes_candidates/hafs_v2_20260917/tete3_hafs_v2.json' :app:testDebugUnitTest --tests '*BancChaineOnnxJvmTest'
```
