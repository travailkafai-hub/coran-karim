# Tête 3 : de 37 % à 80 % — ce qui a été tenté, mesuré, et ce que ça dit

Objectif fixé par l'utilisateur le 2026-08-05 : **80 % de détection à 2 % de
collatéral**. Point de départ mesuré : **37 %** (TTS + audio réel ré-étiqueté),
contre **28 %** pour la règle écrite à la main.

Ce document existe pour que l'objectif ne se mesure pas à l'humeur : chaque
piste y entre avec son chiffre, y compris — et surtout — celles qui échouent.

## Le point de fonctionnement, et pourquoi il est dur

« 2 % de collatéral » veut dire : pour attraper des fautes, on accepte de
signaler à tort **2 mots corrects sur 100**. Sur une récitation de 300 mots,
c'est déjà 6 accusations injustes. C'est le prix que l'app peut payer sans
devenir pénible — au-delà, le récitateur cesse de faire confiance.

Passer de 37 % à 80 % à ce point de fonctionnement, ce n'est pas « affiner un
réglage » : c'est demander au signal de séparer deux fois mieux, dans la zone
la plus difficile de la courbe (la queue).

## Ce qui a déjà été mesuré (à ne pas repayer)

| piste | résultat | date |
|---|---|---|
| règle C écrite à la main | 28 % — **plafond fixe** | 2026-07-31 |
| tête sur les 12 scores seuls | 29 % | 2026-08-04 |
| tête sur l'état d'encodeur seul | 10-20 % | 2026-08-04 |
| tête sur état + scores | 31 % puis **37 %** | 2026-08-04 |
| plus de capacité / d'epochs | **plat** (29-32 %) | 2026-08-04 |
| plus de données TTS (+7,6 %) | négligeable | 2026-08-04 |
| audio réel **seul** | **10 %** — trop « propre » | 2026-08-04 |
| audio réel **en plus** du TTS (8 k clips) | **37 %** | 2026-08-04 |
| audio réel élargi (30 k clips) | **32 %** — dégrade | 2026-08-04 |

Deux enseignements que ces lignes imposent :

1. **Le volume n'est pas le levier.** Trois tentatives d'en ajouter (TTS élargi,
   réel 8 k, réel 30 k) donnent respectivement rien, +4 points, puis −5. C'est un
   problème de **dosage et de nature** du signal, pas de quantité.
2. **La capacité n'est pas le levier non plus.** Multiplier les paramètres par 4
   ne bouge rien, et dégrade même à 5 % et 10 % de collatéral (sur-apprentissage
   sur 767 fautes).

Ce qui reste, donc : **l'information donnée à la tête**.

## Ce qui est tenté cette nuit

### 1. Variantes non scorables : exclues au lieu d'être notées −1e30

`score_force` rend une sentinelle `NEG = -1e30` quand l'audio est trop court
pour la séquence de tokens — c'est un « non mesurable », pas un « très mauvais
score ». Divisée par le nombre de frames, elle produisait des caractéristiques à
−1e29 que le filtre `|X| < 1e6` jetait ensuite : **406 exemples sur 3675, soit
11 % du jeu, perdus en silence** — dont des fautes, la donnée la plus rare.

### 2. État de l'encodeur : moyenne **et** écart-type (512 → 1024 dims)

C'est le changement le plus important, et il porte sur la **nature** du signal.
La moyenne sur les frames du mot **détruit toute la structure temporelle** avant
même d'atteindre la tête. Or une déviation est le plus souvent une
**irrégularité à l'intérieur du mot** — une lettre qui dérape, un allongement qui
s'effondre — pas un déplacement du centre de gravité du mot. L'écart-type par
dimension rend cette variabilité interne, au même coût de calcul.

### 3. Balayage systématique plutôt qu'essais au fil de l'eau

`balayage_tete3.py` compare tous les jeux de caractéristiques × capacité ×
epochs **sur le même jeu de test** (les 189 premières phrases TTS, tenues à
l'écart depuis l'origine) et la même graine. Motif : le projet a déjà annoncé un
gain qui n'existait pas faute de comparer à la bonne référence.

## Ce qu'il faudra dire si 80 % n'est pas atteint

Que ce n'est pas atteint, et à combien on s'est arrêté — pas « on s'en
approche ». Un chiffre annoncé au-dessus de la mesure coûte plus cher que
l'échec lui-même : il fait brancher sur un verdict une tête qui accuse à tort.

Rappel du garde-fou déjà inscrit dans `Tete3.kt` : tant que la parité des
caractéristiques entre Python et Kotlin n'est pas vérifiée sur device, **la
sortie de cette tête ne doit trancher aucun verdict**, quel que soit son score
hors device.
