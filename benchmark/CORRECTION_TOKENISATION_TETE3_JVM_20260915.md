# Tête 3 : corriger ses entrées avant de juger sa qualité

## Cause identifiée et reproduite

Le tokenizer de l'alignement (`CtcTokenizer`) utilise un dictionnaire puis un
découpage glouton. L'entraînement de la tête 3 utilise SentencePiece BPE. Ces
deux procédés ne donnent pas toujours les mêmes identifiants pour un mot
identique. Les anciennes vérifications de parité recevaient directement les
identifiants Python : elles prouvaient les calculs **après** cette étape.

Exemple réel de référence : `وَإِنْ` donne `[393, 959]` avec SentencePiece,
contre `[4, 615, 959]` avec l'ancien chemin de l'application. Cela modifie les
12 caractéristiques CTC reçues par la tête, alors que le texte paraît identique.

Les modèles SentencePiece locaux `modele_4tetes_2026-08-21/tokenizers/hafs.model`
et `warsh.model` correspondent chacun aux **1024/1024** pièces de leur
vocabulaire déployé. Leurs tables de normalisation ne sont pas identiques :
chaque riwaya doit conserver la sienne.

## Expérience causale sur les quatre faux rouges connus

`BancDiagnosticJugementJvmTest` relit les mêmes tranches PCM et les mêmes
bornes de mots que les observations Samsung archivées. Mel Kotlin, ONNX du
pack embarqué, ORT desktop 1.26.0. Pour chaque observation, les tenseurs et
bornes sont identiques entre l'ancien tokenizer et l'oracle SentencePiece.

| T805, mot sans mutation | Ancien logit JVM | Logit avec jetons SentencePiece |
|---|---|---|
| 68 `أُلْقُوا۟` | +9,64 ; +4,48 ; +8,17 | −11,88 ; −15,46 ; −12,55 |
| 131 `وَأَسِرُّوا۟` | +31,43 ; +32,56 ; +29,63 | −0,96 ; −7,31 ; −8,11 |
| 155 `مَنَاكِبِهَا` | +2,91 ; +2,71 | −1,28 ; −4,57 |
| 180 `حَاصِبًا` | +0,95 ; +1,31 ; +1,56 | −2,50 ; −3,49 ; −3,45 |

Les **11/11 observations** de ces quatre mots passent sous zéro. Leurs
anciens faux écarts sont donc expliqués par les entrées de la tête, sans
déplacer son seuil. Les scores des erreurs ciblées T023/4 et T005/27 restent
identiques ; cela ne suffit pas, à lui seul, à prouver les verdicts en flux.

Le runtime Windows n'est pas bit à bit identique au runtime Android : les
logits JVM diffèrent parfois des archives et une transcription libre peut
varier. La comparaison causale ci-dessus porte sur **deux préparations du
même tenseur JVM**, pas sur une prétendue parité numérique entre appareils.

## Correction dans le code

- `TokeniseurBpeTete3` : fusions BPE selon les scores exportés du modèle,
  normalisation par son vrai trie SentencePiece, préfixe et inconnus conservés.
- `ChaineRecitation` : tokens attendus et confusions propres à la tête 3.
  Les tokens imposés à l'aligneur ne sont pas remplacés.
- Plugin Android : charge le tokenizer correspondant à la riwaya et vérifie
  le vocabulaire et l'empreinte de la normalisation. Une incompatibilité
  désactive la participation de la tête au jugement, avec trace explicite.
- Les marqueurs d'activation du vote et de la tête restent indépendants.
  Aucun nouveau seuil ni règle de vote n'est introduit par cette correction.

Référence technique des formats : [BPE SentencePiece](https://github.com/google/sentencepiece/blob/master/src/bpe_model.cc),
[normalisation](https://github.com/google/sentencepiece/blob/master/src/normalizer.cc),
[format du trie Darts](https://github.com/google/sentencepiece/blob/master/third_party/darts_clone/darts.h).

## Vérifications

- Parité intégrale normalisation + identifiants : **277 016/277 016** textes
  Hafs et **329 326/329 326** Warsh, lexique et confusions générées compris.
- Test permanent supplémentaire : les références audio Hafs/Warsh passent
  maintenant aussi par les véritables tokenizers Kotlin, cible et confusions.
- `BancChaineOnnxJvmTest` : replay PCM → mel Kotlin → ONNX → chaîne Kotlin
  entière, avec décisions pendant le flux et arrêt au premier décrochage.
  Quatre configurations : historique, vote, vote+tête avec anciennes entrées,
  vote+tête avec BPE. Cas T805, témoins T807/T808 et erreurs T023/T005.

Les résultats du replay complet et leur comparaison sont écrits dans
`replay_chaine_jvm_20260915/resultats.json` et `analyse.json`. Le script
d'analyse compare uniquement les statuts Kotlin, distingue rouges définitifs
et signalements, exclut les insertions proxy et donne la couverture commune.
Il ne compare pas manuellement deux vocabulaires pour inventer un verdict.

### Résultat mesuré de la correction BPE seule

Archive immuable de cette étape : `replay_chaine_jvm_20260915_avant_kashida/`.
Le test natif complet a exécuté 383 inférences en 134 secondes, puis les tests
de parité et de flux : 18 tests, aucun échec et aucun saut.

Sur T805, mêmes 222 indices et mêmes **1 152 observations hors tête 3** entre
anciennes et nouvelles entrées de tête :

| Configuration JVM | Mutations signalées / 20 | Corrects signalés / 200 | Corrects rouges définitifs / 200 |
|---|---:|---:|---:|
| Historique | 8/20 = 40 % | 7/200 = 3,5 % | 3/200 = 1,5 % |
| Vote seul | 11/20 = 55 % | 14/200 = 7 % | 6/200 = 3 % |
| Vote + tête, anciennes entrées | 11/20 = 55 % | 18/200 = 9 % | 10/200 = 5 % |
| Vote + tête, BPE | 11/20 = 55 % | 14/200 = 7 % | 6/200 = 3 % |

Les quatre mots du diagnostic passent bien **rouge définitif → vert
définitif pendant le flux**, sans perte des erreurs signalées. Le compte
diffère légèrement du Samsung (11 puis 7 faux rouges), ce qui confirme la
limite de comparaison entre runtimes déjà annoncée.

Sur T023 et T005, les erreurs ciblées restent rouges définitives. Sur le
témoin T808, la tête BPE retire un doute (mot 13), mais laisse quatre faux
rouges sur 73 mots, contre trois pour le vote seul : **elle reste donc
expérimentale**. Sur T807, arrêt à 18,16 s, seulement 7/105 mots jugés pour
le vote : aucune conclusion sur les 98 autres. Ne pas présenter le dénominateur
commun avec l'historique (6 mots T807, 5 mots T808) comme un test des témoins
entiers. L'analyse expose aussi toute la population jugée par configuration.

### Seconde correction : comparaison de la kashida

Le mot T805/0 `تَبَـٰرَكَ` était lu `تَبَارَكَ` dans trois fenêtres, mais
la variante autorisée `تَبَـارَكَ` conservait son trait typographique U+0640.
`VoteFenetres.cle` retire maintenant uniquement ce trait avant NFC. Aucune
haraka, consonne, hamza ou voyelle longue n'est supprimée. Un test négatif
vérifie que voyelle brève, haraka changée et consonne ajoutée restent distinctes.
Les anciennes sorties sont conservées avant le second replay, pour isoler
ce changement de la correction des entrées de la tête.

Résultat du second replay : seul T805/0 change, rouge définitif → vert
définitif. Aucun autre statut ne change sur les cinq cas pour la configuration
avec BPE. Bilan des **deux corrections** sur T805 : faux rouges **10/200
(5 %) → 5/200 (2,5 %)** ; signalements de mots non modifiés **18/200 (9 %)
→ 13/200 (6,5 %)**. Mutations signalées **11/20 (55 %) → 11/20 (55 %)**,
dont **5/20 (25 %) rouges définitifs**. C'est un gain de précision mesuré,
pas encore une hausse du rappel. Le témoin historique reste à 7/200 mots
non modifiés signalés ; le vote expérimental n'est donc pas validé globalement.

Graphe relu pour cette étape : `mesure_ecritures_equivalentes`,
`piege_attestation_normalisee_blanchit`,
`piege_comparer_de_l_arabe_sans_normalisation_unicode`. La clé reste distincte
du normaliseur utilisé pour localiser les mots.

Le premier essai complet a subi un crash du compilateur C2 de Microsoft JDK
21.0.10, dans `Localisateur.localiser` (`hs_err_pid29428.log`). Le banc
`-DasrBanc=true` exclut cette méthode de l'optimisation JIT sur le PC.
Ce contournement ne concerne pas le runtime Android.

Validation finale : **46 tests, 0 échec, 0 erreur, 0 saut**, dont le replay
complet (383 inférences, 135 s) et les 606 342 comparaisons de tokenisation.
APK debug compilée et ses quatre assets de tokenisation vérifiés octet par
octet contre les sources. La dépendance ORT Windows reste réservée aux tests.
APK : `app/build/app/outputs/apk/debug/app-debug.apk`, SHA-256
`5161daf3f9fd8a94da845876865fae0f05855f380e64037517b5fc759303bc62`.
Empreintes du code, du modèle, des assets et paramètres du banc dans
`replay_chaine_jvm_20260915/provenance.json`. APK non installée sur Samsung.

## Reproduire / relais Claude

Pour choisir le prochain entrainement sur Ubuntu :
[diagnostic tete seule / encodeur et protocole de comparaison](CLAUDE_UBUNTU_DIAGNOSTIC_REENTRAINEMENT_TETE3_20260915.md).
Ce document distingue les copies locales des scripts de l'etat distant a
verifier, et explique l'ecart entre bornes du mot en generation et en app.

Depuis la racine du dépôt, PowerShell :

```powershell
.\benchmark\lancer_replay_chaine_jvm_20260915.ps1
```

L'export exige le paquet Python `sentencepiece`, déjà présent sur ce PC.
Les gros oracles JSONL sont générés, pas versionnés. Un oracle absent fait
échouer le banc explicitement activé ; les tests audio ne se lancent pas
par défaut dans la suite ordinaire. Aucun téléphone n'est requis.

Pour la comparaison de scores sur fenêtres archivées seulement :

```powershell
python benchmark/preparer_oracle_tokenizer_tete3.py
cd app/android
.\gradlew.bat '-DasrBanc=true' :app:testDebugUnitTest --tests '*BancDiagnosticJugementJvmTest'
```

Sur Samsung, le contrôle restant sera la reproduction des mêmes passages
avec le nouveau tokenizer et les marqueurs documentés. Ne pas relancer les
100 sessions. Ne pas appliquer le seuil Hafs −2,222 ni Warsh +3,099 sans
mesurer les entrées et le coût sur les mots corrects en flux.

La correction du tokenizer ne calibre pas les poids du vote : deux lectures
CTC erronées presque certaines peuvent encore dominer une lecture correcte.
Les décrochages sur fragments restent également un problème distinct. Les
mesures négatives du graphe sont conservées ; cette nouvelle cause explique
une partie des faux rouges, elle n'annule pas toute la campagne de Claude.

Prochaine investigation concrète, pour Claude : T805/94 (perte de `وَ`),
211 (perte de `ن`), 202 (double émission), 216 (fragment). Sur /94 les
fenêtres 80 et 84 partagent le début 2 026 240 ; la 81 démarre à 1 900 800.
Sur /211 les deux fausses lectures commencent à 4 463 360 ; la correcte
à 4 395 520. Hypothèse à tester : une coupe à gauche commune corrèle les
erreurs, et la somme des pics CTC les compte comme deux confirmations.
Rejouer les mêmes WAV avec une variation contrôlée du contexte et comparer
les fautes réelles voisines. Ne pas dédupliquer toutes les fenêtres partageant
un bord sans mesure : des contextes différents peuvent apporter une vraie
confirmation. Ne pas blanchir tous les fragments du mot attendu.
