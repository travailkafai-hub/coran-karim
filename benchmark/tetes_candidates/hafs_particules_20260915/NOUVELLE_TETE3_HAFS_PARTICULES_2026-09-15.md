# Nouvelle tête 3 Hafs candidate — confusions de particule de liaison (2026-09-15)

## Ce que c'est

`tete3_hafs_particules.json` (joint) — candidate pour remplacer
`tete3_hafs.json` du pack `transfert_2026-09-11_production_v2/`. **Pas
déployée, pas encore testée sur device.** Même format exact que l'actuelle
(1036 dims, mean+std de `encoder_state` + 12 caractéristiques,
`Tete3Traits.etatMoyenEtEcartType` compatible sans changement côté Kotlin).

## Pourquoi

Audit du dataset d'entraînement existant : `variantes()`/`variante_large()`
ne généraient que des substitutions phonémiques (même point d'articulation,
ex. ط↔ت) et des harakat — jamais de confusion de **particule de liaison**
initiale (وَ/فَ, بِ/لِ), pourtant une confusion réelle et fréquente en
récitation. Ajout d'une nouvelle catégorie `substitution_particule` dans
`benchmark/tete3_audio_reel.py` (poids ×6, volontairement concentré sur ce
type d'erreur), puis régénération à plus grande échelle (40 000 clips réels
au lieu de 4 000) sur le même encodeur que la tête déployée
(`warsh-v5-epoch6.nemo`, hash `900a142d2b585d3c`).

## Mesure — comparaison PAR CATÉGORIE, mêmes clips de test, seuil brut

Script : `benchmark/comparer_tete3_particules_2026-09-15.py` (joint). Compare
l'ancienne et la nouvelle tête sur exactement les mêmes 3000 clips (même
seed, même préfixe) — pas une comparaison entre deux caches différents.

| catégorie | n | ancienne | nouvelle |
|---|---|---|---|
| substitution_particule | 174 | 75,3 % | **96,0 %** |
| harakat | 263 | 90,5 % | 97,7 % |
| insertion | 128 | 96,1 % | 100,0 % |
| omission | 140 | 82,1 % | 95,0 % |
| substitution | 421 | 92,6 % | 99,0 % |
| correct (faux positifs) | 1219 | 0,5 % | 0,4 % |

Gain net sur la catégorie ciblée (+20,7 pts), pas de régression sur aucune
autre catégorie, faux positifs stables/en légère baisse. Le gain vient à la
fois de la nouvelle catégorie ET du volume d'entraînement bien plus grand
(31 571 exemples/15 078 fautes contre 3 174 pour la tête actuelle) — les
deux facteurs ne sont pas isolés l'un de l'autre par cette mesure.

## Ce qui reste à faire avant tout déploiement

- Export dans le pack 5 têtes (remplacer `tete3_hafs.json`, reste inchangé),
  parité PyTorch/ONNX, quantification — pas encore fait.
- Test réel device avant tout remplacement du pack déployé (règle projet).
- Côté Warsh : même méthode tentée, **résultat négatif** (régression sur
  4/5 catégories, gain quasi nul sur la catégorie ciblée) — rejetée, pas
  incluse ici. Diagnostic en cours (piste actuelle : reconstruire un
  entraînement Warsh depuis l'audio Hafs BRUT CONTINU + timestamps réels
  + décodeur Warsh, par analogie avec `reconstruire_clips_warsh_depuis_sourates_brutes.py` —
  pas encore de résultat).

## Fichiers joints

- `tete3_hafs_particules.json` — la tête candidate
- `benchmark/tete3_audio_reel.py` — script de génération modifié (catégorie
  `substitution_particule` ajoutée, additif, compatible arrière)
- `benchmark/comparer_tete3_particules_2026-09-15.py` — script de
  comparaison par catégorie utilisé pour produire le tableau ci-dessus
