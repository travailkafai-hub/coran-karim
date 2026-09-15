# Suite — blocage 2 (Warsh) débloqué, référence produite sur audio réel

## Pourquoi pas le raccourci 1-à-1 Hafs→Warsh

L'utilisateur avait proposé de réutiliser le décodeur Hafs avec une
correspondance mot à mot (même texte coranique, écrit différemment) pour
trouver les frontières côté Warsh. Vérifié dans le dépôt avant de faire quoi
que ce soit : cette méthode a déjà été **envisagée puis explicitement
écartée** le 2026-08-31 (commentaire en tête de
`benchmark/tete3_audio_reel_warsh.py`), au profit de la tête Warsh réelle sur
audio Warsh réel — précisément parce que l'utilisateur avait lui-même douté
de l'équivalence des SONS (pas seulement du texte) entre Hafs et Warsh sur la
hamza et le madd ce soir-là. Le raccourci n'a donc pas été retenté : le risque
identifié alors (erreur concentrée sur les mots qui se prononcent
différemment, justement ceux qui comptent pour la tête 3) reste valable.

## Ce qui a été fait à la place

Nouveau script `benchmark/reference_parite_tete3_warsh.py`, même contrat de
sortie que `reference_parite_tete3.py` (mêmes clés `cas[i].attendu`/
`logit_attendu`, même arrondi avant calcul, même format `NOMS`), mais reprend
le chargement de la **vraie** tête Warsh (`ConvLettersDecoder` + tokenizer
`warsh_seul_v1`) exactement comme `tete3_audio_reel_warsh.py`, celui qui a
servi à calibrer `tete3_warsh.json`.

Checkpoints utilisés — vérifiés co-localisés et cohérents avec la
description de `tete3_warsh.json` (`warsh-v5-epoch6`, hash encodeur déjà
revérifié `900a142d2b585d3c`) :
- `transfert_2026-08-31/modele/warsh-v5-epoch6.nemo`
- `transfert_2026-08-31/modele/warsh-v5-epoch6-tete-warsh.pt` (seule
  correspondance exacte du nom sur le disque ; d'autres `*-tete-warsh.pt`
  existent mais appartiennent à des runs clairement différents par leur nom
  — H3_poids_hafs_50, warsh-v3-corrige, warsh-v4-*, non utilisés)

Corpus : `benchmark/nemo_manifests_mixte_hw/train_warsh_final_2026-08-22.jsonl`
— **vraie récitation Warsh, contenu vérifié**, pas du TTS ni du montage
(contrairement au corpus par défaut utilisé côté Hafs).

## Résultat

```
python3 benchmark/reference_parite_tete3_warsh.py \
  --nemo transfert_2026-08-31/modele/warsh-v5-epoch6.nemo \
  --tete_warsh transfert_2026-08-31/modele/warsh-v5-epoch6-tete-warsh.pt \
  --tete3 transfert_2026-09-11_production_v2/tete3_warsh.json \
  --sortie reference_tete3_warsh.json \
  --max-cas 8
```

A tourné sans erreur. `taille_vecteur` = **1036** pour les 3 cas produits
(pas 8 : la ligne choisie n'a que 4 mots, dont 3 jugeables — comportement
normal, pas une anomalie).

- Audio réel : `AbdelKabirHadidi_assajda/100_10.wav`
- Phrase : `وَحُصِّلَ مَا فِے اِ۬لصُّدُورِ`

Fichiers joints : `reference_parite_tete3_warsh.py` (le script) et
`reference_tete3_warsh.json` (le résultat).

## État final des deux blocages de la demande initiale

| | Hafs | Warsh |
|---|---|---|
| calcul (poids, arithmétique) | déjà vérifié par toi | déjà vérifié par toi |
| extraction depuis audio réel | ✅ référence produite (TTS) | ✅ référence produite (**vraie récitation**) |

Les deux références sont maintenant disponibles pour le test Kotlin
(`cas[i].attendu`/`logit_attendu` contre `Tete3Traits.caracteristiques()`/
`Tete3.logit()`), sur le paquet réellement déployé des deux côtés.
