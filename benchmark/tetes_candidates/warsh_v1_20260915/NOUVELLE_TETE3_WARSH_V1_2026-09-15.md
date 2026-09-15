# Nouvelle tête 3 Warsh candidate — audio natif reconstruit (2026-09-15)

## Ce que c'est

`tete3_warsh_v1.json` (joint) — candidate pour remplacer `tete3_warsh.json`
du pack `transfert_2026-09-11_production_v2/`. **Pas déployée, pas encore
testée sur device.** Même format exact que l'actuelle (1036 dims, mean+std
de `encoder_state` + 12 caractéristiques).

## Pourquoi

Diagnostic : le manifeste Warsh existant (`train_warsh_final_2026-08-22.jsonl`,
463 647 lignes) est à **99,8 % des clips d'un seul mot**
(`mots_hafs_complet_mots1/`, texte vérifié conforme Warsh — pas de
contamination Hafs, juste un nom de dossier trompeur). Le script
d'entraînement tête 3 (`tete3_audio_reel_warsh.py`) ignore tout clip de
moins de 2 mots (contexte nécessaire) — donc sur 40 000 clips tirés,
quasiment tous étaient rejetés, ne laissant que ~13 877 exemples
exploitables. C'est mécanique, pas un signal Warsh intrinsèquement faible.

**Fix** : reconstruction complète depuis l'audio brut continu (sourates
entières, pas des clips pré-découpés), méthode déjà éprouvée du projet
(`reconstruire_clips_warsh_depuis_sourates_brutes.py`, alignement
séquentiel via le vrai décodeur Warsh). 9 récitateurs Warsh vérifiés
(way2quran_warsh + mp3quran_warsh), 114 sourates chacun → **155 529 clips
multi-mots**, dont 50 479 exemples d'entraînement exploitables (0 perte),
contre 13 877 avant.

## Mesure — comparaison PAR CATÉGORIE, mêmes clips de test, seuil brut

Script : `benchmark/comparer_tete3_particules_warsh_2026-09-15.py` (déjà
envoyé). Compare l'ancienne et la nouvelle tête sur les mêmes 3000 clips.

| catégorie | n | ancienne | nouvelle (V1) |
|---|---|---|---|
| substitution_particule | 252 | 67,1 % | **81,3 %** |
| insertion | 208 | 86,1 % | 97,1 % |
| omission | 245 | 77,1 % | 83,3 % |
| substitution | 688 | 89,8 % | 95,2 % |
| harakat | 403 | 92,1 % | 91,1 % |
| correct (faux positifs) | 1971 | 6,4 % | 7,4 % |

Amélioration sur 4/5 catégories, cible (+14,2 pts), coût faible en faux
positifs (+1 pt). Cette fois le gain vient principalement du VOLUME et de
la QUALITÉ des clips (multi-mots, pas de la nouvelle catégorie particule
seule) — contrairement à Hafs, l'ancien manifeste Warsh était structurellement
sous-exploité.

## Piste alternative testée et écartée

Idée testée en parallèle (utilisateur) : audio HAFS réel (timestamps
fiables) + texte WARSH (via une table de correspondance mot-à-mot
construite pour l'occasion, `correspondance_hafs_warsh_mots.json`, 91,3 %
de couverture sur tout le Coran, alignement de séquence complète par
sourate — PAS par numéro de verset, qui diverge sur 75/114 sourates).
Fonctionne mécaniquement mais reste **non compétitif** : 38 538 exemples
construits (variantes de fautes multipliées ×6 sur le même audio, gratuit
en calcul), recalibré à seulement 21,0 %/34,5 % (seuils calibrés) contre
74,5 %/94,5 % pour V1 sur son propre test. Le volume n'était pas le facteur
limitant — probablement un signal intrinsèquement plus faible (audio Hafs
lu par le décodeur Warsh) et/ou un déséquilibre correct/faute non résolu.
Piste documentée dans le skill `warsh-corpus-audio`, close pour l'instant.

## Ce qui reste à faire avant tout déploiement

- Export dans le pack 5 têtes (remplacer `tete3_warsh.json`, reste
  inchangé), parité PyTorch/ONNX, quantification — pas encore fait.
- Test réel device avant tout remplacement du pack déployé.

## Fichiers joints

- `tete3_warsh_v1.json` — la tête candidate
- `reconstruire_clips_warsh_depuis_sourates_brutes.py` — script de
  reconstruction (déjà dans le dépôt, pas modifié)
- `comparer_tete3_particules_warsh_2026-09-15.py` — script de comparaison
