# Demande — parité Python/Kotlin de la tête 3 sur l'encodeur réel

Origine : `benchmark/TACHE_CLAUDE_CALIBRATION_TETE3_ET_REPETITIONS.md` (Codex),
section 1. Ce que j'ai pu faire depuis le PC portable est dans
`app/android/app/src/test/kotlin/.../Tete3ParitePaqueDeployeTest.kt` et
`benchmark/reference_parite_tete3_deployee.py` : ça vérifie la couche MLP
seule (poids, normalisation, ReLU) sans encodeur, avec un vecteur synthétique.
**Ça ne vérifie PAS l'extraction des 12 caractéristiques depuis un vrai
audio** — c'est ce que cette demande couvre.

## Ce qui manque ici pour le faire

Aucun `torch`, aucun `nemo` installés sur ce PC, aucun fichier `.nemo` trouvé
en local. `benchmark/reference_parite_tete3.py` (déjà dans le dépôt, écrit
pour un autre paquet) a besoin de ça pour tourner.

## Le paquet à couvrir — vérifier l'empreinte AVANT de calculer quoi que ce soit

`app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/`

| fichier | SHA-256 attendu |
|---|---|
| `tete3.json` (Hafs) | `c594993a1d3687aa33ba7f521866fbeb5e2c2078c2cb7225911540fb43e0ef99` |
| `tete3_warsh.json` | `f6ac3851d5ed7896ff56443d151d129669aac03f5bff0efad0387603259f625d` |

Si un des deux ne correspond pas sur PC A : **arrêter**, le dire dans la
réponse, ne rien calculer sur un fichier différent de celui déployé.

## Le checkpoint

Le champ `description` de chaque `tete3.json` le nomme : `warsh-v5-epoch6.nemo`,
hash encodeur `900a142d2b585d3c` — déjà vérifié dans le graphe causal
(`step10_priere_et_tajwid.py`) comme identique à l'encodeur qui a produit ce
pack, par deux méthodes indépendantes. Cette demande ne redemande pas cette
vérification-là ; elle demande la suivante, qui n'a jamais été faite : le
Kotlin calcule-t-il les mêmes 12 caractéristiques que ce checkpoint sur un
audio réel ?

Si plusieurs fichiers portent ce nom sur PC A, vérifier lequel a réellement le
hash encodeur `900a142d2b585d3c` avant de l'utiliser — ne pas supposer que le
nom suffit (c'est écrit noir sur blanc dans `Tete3PariteTest` : « Le LISEZ_MOI
du transfert l'exigeait explicitement... ne pas supposer »).

## Ce qui est demandé

Lancer, pour Hafs et pour Warsh séparément (le script prend un seul `--tete3` à
la fois) :

```bash
python3 benchmark/reference_parite_tete3.py \
  --nemo <chemin vers warsh-v5-epoch6.nemo, hash verifie> \
  --tete3 app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/tete3.json \
  --sortie benchmark/tunnel_pc_a/reponses/reference_tete3_hafs.json \
  --max-cas 8

python3 benchmark/reference_parite_tete3.py \
  --nemo <meme checkpoint> \
  --tete3 app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/tete3_warsh.json \
  --sortie benchmark/tunnel_pc_a/reponses/reference_tete3_warsh.json \
  --max-cas 8 \
  --dossier <corpus audio Warsh reel si different du defaut>
```

Le `--dossier` par défaut (`data/tts_phrases_concat`) est un corpus de phrases
concaténées TTS — s'il existe un corpus de VRAIE récitation avec alignement
mot par mot et fautes connues pour Warsh, le préférer et le dire dans la
réponse. Sinon, dire explicitement que c'est du TTS et pas de la vraie
récitation — la nuance compte pour ce que le résultat prouve.

`--max-cas 8` plutôt que le défaut (5) : plus de mots jugeables dans le
fichier de sortie, pour couvrir plus de longueurs de mot (le risque nommé par
le script lui-même : un mot court a peu de frames, son Viterbi remonte peu, un
backtrack faux y passerait inaperçu).

## Ce que je ferai du résultat

Avec `reference_tete3_hafs.json`/`reference_tete3_warsh.json` dans
`reponses/`, j'écrirai un test Kotlin qui rejoue chaque `cas[i].attendu` (les
12 caractéristiques nommées) et `cas[i].logit_attendu` contre
`Tete3Traits.caracteristiques()` et `Tete3.logit()`, sur le paquet réellement
déployé — exactement le même principe que `Tete3TraitsTest`, mais sur le bon
fichier cette fois. Je committerai ce test avec le résultat, pas l'inverse.

## S'il manque autre chose pour lancer ça

Le dire dans `reponses/` plutôt que d'improviser un corpus ou un checkpoint
approché — un encodeur différent invaliderait tout le résultat sans qu'aucune
erreur ne le signale (c'est exactement le risque que `Tete3.kt` documente).
