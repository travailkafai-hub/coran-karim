# Réponse — parité Python/Kotlin tête 3 sur l'encodeur réel

Suite à `tunnel_pc_a/DEMANDE_2026-09-15_parite_tete3_encodeur.md`. Résultat :
**aucun `reference_tete3_hafs.json`/`reference_tete3_warsh.json` produit** —
deux blocages trouvés avant tout calcul, aucun des deux contourné par
improvisation (conformément à la demande).

## Ce qui a été vérifié — PASSÉ

- SHA-256 de `.../cinq-tetes-2026-09-11-madd-normal/tete3.json` (Hafs) :
  correspond exactement à `c594993a1d3687aa33ba7f521866fbeb5e2c2078c2cb7225911540fb43e0ef99`.
- SHA-256 de `.../cinq-tetes-2026-09-11-madd-normal/tete3_warsh.json` :
  correspond exactement à `f6ac3851d5ed7896ff56443d151d129669aac03f5bff0efad0387603259f625d`.
- Hash encodeur `warsh-v5-epoch6.nemo` re-vérifié à `900a142d2b585d3c`
  (méthode `hash_encodeur()`, identique à celle déjà utilisée dans le graphe
  causal). Une seule copie de ce `.nemo` existe sur ce disque — pas
  d'ambiguïté sur "lequel utiliser".

Donc : le paquet ciblé est bien le bon, et le checkpoint désigné par sa
`description` est bien le bon, sans supposition sur le nom.

## Blocage 1 — `reference_parite_tete3.py` calcule 524 dims, le pack en attend 1036

Commande lancée telle quelle (Hafs) :

```
python3 benchmark/reference_parite_tete3.py --nemo <warsh-v5-epoch6.nemo> \
  --tete3 app/android/model_pack/.../cinq-tetes-2026-09-11-madd-normal/tete3.json \
  --sortie benchmark/tunnel_pc_a/reponses/reference_tete3_hafs.json --max-cas 8
```

Échec, garde interne du script lui-même :

```
tete3.json attend 1036 caracteristiques, le vecteur en a 524 -- ce n'est pas la bonne tete
```

**Ce n'est pas le mauvais fichier.** Vérifié directement dans
`tete3.json` (Hafs, celui dont le SHA-256 vient d'être confirmé) :

```
caracteristiques: ['etat_encodeur_moyen_et_ecart_type[1024]', 'forced_v', 'forced_f',
                    'free', 'alt', 'alt2', 'gopA', 'gopC', 'marge_alt', 'n_frames',
                    'n_tokens', 'entropie', 'pic_blanc']
len(normalisation.moyenne) == len(normalisation.ecart_type) == 1036
```

1024 (moyenne+écart-type de l'état encodeur) + 12 caractéristiques = 1036.
C'est la convention **mean+std**, pas mean seul.

`reference_parite_tete3.py` (lignes 140-148) fait l'inverse et le justifie
par un commentaire qui affirme l'avoir déjà vérifié compatible le
2026-08-21 :

```python
# ⚠️ MOYENNE SEULE, PAS moyenne+ecart-type. tete3.json declare
# `etat_encodeur_moyen[512]` -- 512 valeurs, pas 1024. La version
# d'origine de ce script concatenait mean+std (1024+12=1036), ce qui
# ne correspond a AUCUNE tete3 en circulation (524 attendues) : bug du
# script, pas divergence de convention (2026-08-21, meme construction
# que `tete3_tient_elle_sur_le_nouvel_encodeur.py` et
# `recalibrer_tete3.py`, verifiees compatibles avec tete3.json).
etat_moyen = seg.mean(axis=0)
vecteur = np.concatenate([etat_moyen, np.asarray(car, dtype=np.float64)])
```

Ce commentaire est **périmé**, et la preuve qu'il est faux vit dans le
fichier voisin qu'il cite lui-même comme témoin, à la même date. Dans
`recalibrer_tete3.py` (lignes 60-69), un commentaire du **même jour**
(2026-08-21) raconte l'épisode inverse :

```python
# ⚠️ E ENTIER (mean+std, 1024), PAS E[:, :512]. Erreur commise le
# 2026-08-21 matin : le tete3.json de reference utilise ce jour-la
# declarait 524 (etat_encodeur_MOYEN seul), et j'ai tronque E pour
# matcher -- en croyant corriger un bug de reference_parite_tete3.py.
# C'etait l'inverse : `tete3-v2-2026-08-05/tete3.json` (1036 dims,
# mean+std) est une variante posterieure MESUREE meilleure (37 % -> 47 %
# de detection, cf. Tete3Traits.kt), et c'est CELLE-LA que l'app Kotlin
# construit reellement (`etatMoyenEtEcartType`). Tronquer produisait un
# tete3.json incompatible avec le code deploye (« TETE INCOMPATIBLE :
# vecteur=1036, tete=524 » releve sur device le meme jour).
```

Confirmé côté Kotlin : `Tete3Traits.kt` construit bien 1024 valeurs
(`etatMoyenEtEcartType`, ligne ~291, commentaire ligne ~260 : « rend 1024
-- moyenne ET écart-type »), appelé depuis `ChaineRecitation.kt:1365`.

**Conclusion** : les deux scripts se contredisaient déjà le 2026-08-21 ;
`recalibrer_tete3.py` a été corrigé pour suivre le Kotlin réellement
déployé (mean+std, 1036), `reference_parite_tete3.py` ne l'a jamais été —
c'est exactement le "risque déjà payé deux fois" que la demande signalait.
Le pack `cinq-tetes-2026-09-11-madd-normal` a été calibré avec la
convention 1036 (comme tous les `tete3.json` produits depuis
`tete3-v2-2026-08-05`), donc `reference_parite_tete3.py` ne peut produire
de référence valide pour AUCUN pack actuellement déployé tant qu'il n'est
pas corrigé.

**Correctif possible** (pas appliqué, en attente d'accord — script hors
chaîne live mais partagé) : dans `reference_parite_tete3.py`, remplacer
`etat_moyen = seg.mean(axis=0)` par la concaténation mean+std, comme le
fait déjà `recalibrer_tete3.py` :
```python
etat_mean_std = np.concatenate([seg.mean(axis=0), seg.std(axis=0)])
vecteur = np.concatenate([etat_mean_std, np.asarray(car, dtype=np.float64)])
```
et retirer/corriger le commentaire 140-146 qui affirme le contraire (règle
projet : ne pas supprimer un commentaire qui documente une tentative
passée — le remplacer par une note qui dit qu'il s'est révélé faux, pas
l'effacer).

## Blocage 2 — le script ne sait pas produire une référence Warsh

`reference_parite_tete3.py` charge toujours `model.ctc_decoder` (tête CTC
Hafs) et `model.tokenizer.tokenizer` (SentencePiece Hafs), quel que soit le
`--tete3` passé (ligne 95 : `sp = model.tokenizer.tokenizer`, ligne 109 :
`lg = model.ctc_decoder(encoder_output=enc)`). Aucune branche vers le
`ConvLettersDecoder` Warsh ni son tokenizer séparé (`warsh_seul_v1`).

Lancer la commande Warsh telle qu'écrite dans la demande calculerait donc
un vecteur `attendu`/`logit_attendu` sur le **mauvais décodeur** — même en
corrigeant le blocage 1, le résultat serait un faux négatif ou faux positif
silencieux, exactement le risque nommé dans la demande (« un encodeur
différent invaliderait tout le résultat sans qu'aucune erreur ne le
signale »). Non lancé, pour cette raison.

Un correctif existe déjà en modèle dans le dépôt :
`tete3_audio_reel_warsh.py` construit un chemin Warsh correct (tête
`ConvLettersDecoder` + tokenizer `warsh_seul_v1`) mais ne produit pas le
format `cas[i].attendu`/`logit_attendu` attendu par le test Kotlin —
adapter `reference_parite_tete3.py` avec une branche `--warsh` reste à
faire, pas improvisé ici.

## Corpus — le `--dossier` par défaut est TTS, pas de la vraie récitation

`benchmark/data/tts_phrases_concat/manifest.jsonl` existe et est au bon
format (`manifest.jsonl` + `wav/`) — c'est le défaut utilisé si on relance
telle quelle, mais **c'est du TTS concaténé, pas de la vraie récitation**.
Le résultat qu'il produirait ne prouve la parité que sur de la voix
synthétique.

Le corpus de vraie récitation Warsh évoqué dans la demande existe :
`benchmark/data/warsh_via_hafs_montage_2026-08-31/` — mais :
- format **incompatible** avec ce que le script attend : 37 fichiers `.wav`
  à plat, aucun `manifest.jsonl`, aucun sous-dossier `wav/` ;
- c'est un corpus de **montage** (fragments assemblés), pas des prises de
  vraie récitation continue avec alignement mot par mot et fautes connues.

Non adapté ici (ni le format, ni la nature montage vs vraie récitation) —
conformément à la consigne de ne pas improviser de corpus approché.

## Ce qu'il faut pour débloquer

1. Corriger `reference_parite_tete3.py` pour la convention mean+std (1036),
   confirmée par `recalibrer_tete3.py` et par `Tete3Traits.kt` eux-mêmes —
   correctif ponctuel, localisé, déjà écrit ci-dessus, en attente
   d'validation avant application.
2. Ajouter une branche Warsh (décodeur + tokenizer) au script, ou écrire un
   script frère dédié Warsh qui produit le même format de sortie
   (`cas[i].attendu`/`logit_attendu`) — actuellement seule
   `tete3_audio_reel_warsh.py` existe et ne le produit pas tel quel.
3. Pour un résultat qui prouve quelque chose sur de la vraie récitation
   Warsh (pas du TTS) : soit reformater
   `warsh_via_hafs_montage_2026-08-31/` (37 clips, montage — nombre limité
   et nature partiellement synthétique, donc valeur de preuve limitée même
   reformaté), soit désigner un autre corpus Warsh réel avec alignement mot
   par mot déjà disponible.

Rien de tout cela n'a été fait sans accord — dites lequel prioriser (le
correctif 1 seul débloquerait déjà Hafs sur TTS ; 1+2+3 sont nécessaires
pour couvrir Warsh sur de la vraie récitation).
