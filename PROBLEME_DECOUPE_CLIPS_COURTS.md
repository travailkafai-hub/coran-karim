# Le problème du corpus 3-8 s — les clips longs sont bons, la découpe ne l'est pas

## En une phrase

**L'audio de départ (versets entiers) est bien aligné avec son texte. Le
problème apparaît uniquement quand on essaie de savoir OÙ, À L'INTÉRIEUR de
ce clip, chaque mot commence et finit — pour pouvoir en extraire un fragment
de 3 à 8 secondes.**

---

## 1. Les clips longs sont vérifiés bons

`train_wav_local/` contient ~59 000 clips : un fichier audio par verset
récité, avec le texte du verset entier dans le manifeste
(`nemo_manifests_dual/train_manifest.jsonl`).

Test fait cette nuit : décoder ces clips **tels quels, sans y toucher**, et
comparer au texte attendu. Résultat sur 54 récitateurs (8 clips chacun,
~100-150 mots) :

- la quasi-totalité tombe entre **5 % et 25 %** de WER — le bruit normal du
  modèle, pas un défaut de données ;
- **9 récitateurs** (surtout ceux au suffixe `_assajda`) ressortent à
  **30-104 %** — pour eux, le texte du manifeste ne correspond vraiment pas à
  l'audio. Documentés et exclus (`benchmark/recitateurs_exclus.py`).

**Conclusion de cette étape : le couple (audio, texte) du clip ENTIER est
fiable**, sauf pour ces 9 cas à part.

## 2. Le besoin : des fragments courts (3-8 s), pas des versets entiers

Le modèle voit très peu de très courts fragments à l'entraînement (moins de
3 % des clips durent moins de 3 s), alors que c'est exactement ce que produit
la segmentation en direct sur le téléphone (un mot coupé en bord de fenêtre).
Objectif : fabriquer ce genre de fragments à partir des clips longs déjà
vérifiés, **sans capturer de nouvel audio**.

Pour ça il faut savoir, à l'intérieur d'un clip de 8-15 mots, où se trouve
la frontière entre le mot 3 et le mot 4 par exemple — c'est cette frontière
qui a posé problème toute la soirée.

## 3. Trois méthodes essayées pour trouver cette frontière

| # | méthode | idée | WER mesuré sur les fragments produits |
|---|---|---|---|
| v1 | proportions externes | `word_timings_ref.json` donne la durée MÉDIANE de chaque mot chez d'AUTRES récitateurs (quran.com), mise à l'échelle de la durée du clip | **37,2 %** (propres) / 61,3 % (tronqués) |
| v2 | alignement Viterbi CTC brut | le modèle lui-même aligne le texte sur l'audio, on prend directement les bornes qu'il donne par mot | **43,3 %** / 64,2 % — pire |
| v3 | frontière par probabilité de blanc | le modèle place un REPÈRE au centre de chaque mot (comme v2), mais la COUPURE elle-même est cherchée là où la probabilité de silence est maximale entre deux repères | **33,9 %** / 48,5 % — mieux, toujours insuffisant |

Les trois échouent à produire un texte fiable pour le fragment découpé, à des
degrés différents.

## 4. Pourquoi v2 (l'alignement du modèle) a raté

C'est le résultat le plus contre-intuitif : demander au modèle d'aligner
lui-même son propre texte devrait être la méthode la plus fiable. Elle a
pourtant fait **pire** que v1.

Cause vérifiée par inspection directe (verset 44:15, Yasser Ad-Dussary) :

```
mots   :  إِنَّا  كَاشِفُوا۟  ٱلْعَذَابِ  قَلِيلًا  إِنَّكُمْ  عَآئِدُونَ
largeur:    1        9           5          3         4         31   (frames de 80 ms)
```

Le premier mot n'obtient qu'**une seule frame** (80 ms), le dernier en obtient
**31** (2,48 s) — pour des mots de longueur comparable. L'alignement CTC est
« pointu » par nature : il marque l'instant où le modèle est le plus confiant
d'avoir entendu le mot, pas la durée réelle qu'il occupe dans l'audio. Ce
piège était déjà documenté dans ce projet depuis le 14 juillet
(`ETAT_CTC_NEMO.md`, commit `2ae8dc7`), et n'a pas été relu avant d'écrire v2.

## 5. Pourquoi v3 (probabilité de blanc) est meilleur mais pas suffisant

v3 corrige une partie du défaut : au lieu d'utiliser la largeur peu fiable
des spans, elle ne s'en sert que comme repère de POSITION, et cherche la
vraie coupure ailleurs (où le modèle est confiant qu'il ne se passe rien).
Résultat sur le même exemple : les 6 mots obtiennent des durées de 0,96 à
1,52 s — bien plus plausible que 1 à 31 frames.

Mais le test à l'échelle (189 fragments, 35 récitateurs) montre que
l'amélioration ne suffit pas :

- **le problème touche presque tous les récitateurs**, pas seulement
  quelques-uns — Yasser Ad-Dussary, qui tenait à 3-12 % sur les clips longs
  et sur v1, tombe à 35 % ici ;
- ça confirme que le défaut restant est dans la MÉTHODE (la précision de la
  recherche de frontière elle-même), pas dans des données mal étiquetées —
  contrairement aux 9 récitateurs exclus au point 1, qui eux avaient un vrai
  problème à la source.

## 6. État actuel

**Rien de fiable à date pour ce sous-problème précis.** Les clips longs
restent utilisables tels quels (c'est ce qui a servi à tous les entraînements
de cette nuit, tajwid et CTC — le CTC n'a d'ailleurs pas besoin de frontières
de mots précalculées, il apprend l'alignement tout seul pendant
l'entraînement, donc n'est pas concerné par ce problème). Seule la
DÉCOUPE en fragments courts reste bloquée.

Piste non essayée : ne pas chercher UNE frontière ponctuelle, mais un modèle
de durée par mot (longueur phonétique attendue), pour contraindre la
recherche plutôt que de se fier à un seul maximum local de probabilité de
blanc — qui peut lui-même tomber au mauvais endroit sur un récitateur qui
enchaîne les mots sans coupure nette.
