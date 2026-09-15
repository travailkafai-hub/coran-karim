# Vote entre fenêtres et nouvelle tête 3 Hafs — état vérifié le 15/09/2026

## Demande à préserver

Comparer les lectures de plusieurs fenêtres du **même mot, sur la même
occurrence audio**. Ce ne sont pas des répétitions du récitateur.

| Observations | Résultat demandé |
|---|---|
| A:0,8 + A:0,8 contre B:0,8 | A gagne, même si B est l'attendu |
| A:0,2 ; B:0,9 ; C:0,1 | B gagne |
| A:0,8 contre B:0,8 | doute, attendre une confirmation |

Le poids mesure la fiabilité d'une lecture, jamais son accord avec l'attendu.
Les fenêtres sont corrélées : une somme de poids n'est pas une probabilité.
La tête 3 mesure un écart à une **cible** ; son logit ne remplace pas la
confiance de transcription A/B/C.

## Code réellement ajouté

Dans `app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/` :

- `VoteFenetres.kt` : agrégation native A/B/C, NFC sans retirer les harakat,
  exclusion des bords, créneaux inexistants, lectures vides et fragments de
  l'alignement ; déduplication par fenêtre et par contexte audio identique.
- `ConfianceLectureCtc` (même fichier) : candidat de poids = moyenne
  géométrique des pics des runs CTC non blancs. Le nombre de frames blanches
  et la tenue d'un token n'augmentent pas son poids. Minimum des pics et
  confiance par entropie conservés pour comparer les estimateurs.
- `JournalVoteFenetres.kt` : JSON `[vote-observation]` pour **chaque**
  observation, puis `[vote-resultat]`, y compris après verrouillage et sans
  changement de couleur. Version `schema=1`, `mode=observation`.
- `ChaineRecitation` remplit ces données dans le vrai registre ; le plugin
  active la mesure pour Hafs dans les APK debug. `Decideur` ne lit pas encore
  le vote. Aucun nouveau statut ne vient de cette instrumentation.

Les poids portent explicitement `NON_CALIBRE`. Les plages qui ne partagent
aucune frame donnent `OCCURRENCE_AMBIGUE` ; ce garde conservateur reste à
évaluer, il ne prétend pas résoudre toute l'attribution temporelle.
`couvert` n'est pas un filtre : sa longueur dépend du mot attendu, donc le
filtrer effacerait des troncatures réellement prononcées.

Les changements antérieurs liés aux reprises après décrochage restent
distincts. Le `Decideur.kt` du point de sauvegarde et celui de cette mesure
sont identiques. Ne pas présenter ces changements antérieurs comme le vote.

## Résultat Samsung : une cause plus précise que l'hypothèse initiale

Appareil : `R3CY20XW7TD`, Samsung SM-S931B. Cas T023, erreur au verset 36:3,
ancien index 5, index 4 dans l'extrait. Attendu : `ٱلْمُرْسَلِينَ`.
Injecté par le manifest : `ٱلْمُرْسَلُونَ`, donneur 36:13.

Extrait de **18,4054375 s**, versets 36:2 à 36:4 : seul le contexte immédiat
de l'erreur est conservé. Ce contexte diffère de celui du WAV 20 versets ;
l'A/B compare donc deux nouvelles passes sur **ce même extrait**.

| fenêtre | entendu | poids brut | GOP | admissibilité |
|---:|---|---:|---:|---|
| 4 | ٱلْمُرْسَلُونَ | 0,803968 | −0,021622 | admissible |
| 5 | ٱلْمُرْسَلُونَ | 0,940463 | −0,672748 | admissible |
| 6 | إِلَىٰ | 0,760266 | −3,759357 | exclue : bord de fenêtre |
| 7 | ٱلْمُرْسَلُونَ | 0,797560 | −0,004960 | admissible |

Les trois lectures admissibles s'accordent sur l'injecté, poids total
**2,541991**. Aucune ne porte l'attestation exacte de l'attendu.
L'application passe pourtant de `provisoire:orange` à `provisoire:vert`.
Sur **cet extrait**, ce n'est donc pas un vote B isolé ni le raccourci
`nette` : les seuils GOP permettent déjà le vert sur une lecture différente,
puis `meilleurProvisoire` le conserve. Ne pas généraliser cette cause à
tous les mots de l'ancienne campagne.

**Conséquence pour l'implémentation : choisir l'hypothèse et juger sa
conformité sont deux étapes nécessaires.** Réutiliser uniquement la couleur
GOP de la dernière observation gagnante laisserait passer ce cas.

Autre point de code à instruire, sans prétendre en avoir mesuré l'effet :
dans `AligneurForce`, le rattrapage `forwardMoyenGraphe` peut agrandir les
bornes et remplacer `f`, alors que `fr` et le `n` utilisé dans le résultat
proviennent encore de l'alignement initial. Examiner cette incohérence de
portée avant d'interpréter `forced/free/frames` comme un même intervalle.
Ne pas modifier ses seuils pour compenser.

## Contrôles de la mesure, pas une annonce de gain

| contrôle | témoin | instrumentation |
|---|---:|---:|
| mots attendus | 8 | 8 |
| définitifs verts | 6/8 | 6/8 |
| provisoires verts en fin de session | 1/8 | 1/8 |
| non jugés | 1/8 | 1/8 |
| suites de statuts modifiées | — | 0/8 |
| dernier index observé dans les statuts | 7 | 7 |
| rouges définitifs avec entendu vide | 0 | 0 |
| décrochages / corrections audio | 0 / 0 | 0 / 0 |
| PCM capturé identique à la source | oui | oui |
| écart maximal d'échantillon PCM | 0 | 0 |
| dernière notification V2 par rapport à EOF | −0,843 s | −0,860 s |

La dernière ligne contrôle l'absence d'arriéré de notifications à la fin de
ce clip ; elle ne mesure pas la latence mot par mot. Les vérifications
synthétiques comparent aussi tous les statuts à chaque bloc PCM avec/sans
instrumentation. La non-régression sur 8 mots n'est pas une validation large.

21 observations natives et 21 calculs de vote archivés. Pas de gain de
détection attendu en mode observation. Pas de balayage acoustique indépendant
ni de réécoute : la vérité de construction et l'identité du PCM sont
vérifiées, la qualité perceptive du montage reste à examiner.

Preuves :

- `vote_T023_36_3_temoin_20260915/` : manifeste, exécution close, log, image,
  `stream_capture.wav`, `verification_pcm.json`.
- `vote_T023_36_3_mesure_20260915/` : mêmes preuves, plus
  `OBSERVATIONS_VOTE.md`, `OBSERVATIONS_VOTE.json`, `build_sources.json`.
- APK témoin SHA-256 : `2d70dc0236ad9b9848ac4fde67bd6b38c2b232e8e8849cd6be7e36096f6260fb`.
- APK de mesure : `f18258b9211194cb05180167e3267ad8c0b3ae889ccfe581c53a3b8a0652942a`.
- PCM commun : `d8da7e3f74c584c259501811207f5fcb738489fed13de73688e679e04b213570`.
- Sauvegarde avant instrumentation : `sauvegardes_vote/20260915_113127/`,
  sources, diff antérieur et APK témoin. Ne pas faire de reset global.

## Nouvelle tête 3 Hafs fournie par l'utilisateur

Source réelle : `C:\Users\kafai\tunnel_pc_a\reponses`.
Copie conservée sans remplacement du pack :
`tetes_candidates/hafs_particules_20260915/`, avec `PROVENANCE.json`.

- Fichier : `tete3_hafs_particules.json` ; SHA-256
  `7e708b20a9a13e53f14b0491c36396992bdb2b078c05208215d774837e03b66e`.
- 1036 entrées, couches 32×1036 puis 1×32 ; normalisation finie,
  écarts-types strictement positifs ; même liste de 12 caractéristiques.
- **Aucun `seuils_mesures`**. Ne pas remplacer l'absence par zéro.
- Le rapport annonce le même encodeur `warsh-v5-epoch6.nemo`, empreinte
  d'encodeur `900a142d2b585d3c`. Cette identité vient du rapport livré ; le
  JSON lui-même conserve une description périmée « conjoint12 (2026-08-21) ».
  Obtenir une provenance machine lisible liée au fichier avant activation.
- Le rappel annoncé de 96 % sur les particules et 0,4 % de faux positifs
  provient de **cibles textuelles modifiées devant un audio correct**, au
  seuil brut zéro. Ce n'est pas une mesure dense30 ni une calibration en
  streaming. Le script réserve le préfixe de clips au test ; vérifier les
  commandes exactes, le cache et la séparation réelle avec l'entraînement.
- Cette tête est un MLP JSON exécuté dans Kotlin, hors ONNX : le rapport
  mentionne un export/quantification à faire, mais remplacer ce JSON n'exige
  pas en soi de réexporter l'encodeur. Vérifier néanmoins la parité sur
  l'état de l'encodeur INT8 réellement utilisé sur téléphone.

`Tete3HafsParticulesTest` vérifie le fichier exact et le logit Python
**37,389693** sur le vecteur déterministe documenté. C'est une parité
arithmétique, pas une validation de détection.

La référence `reference_tete3_hafs.json` reçue décrit quatre mots de
`p000000_faute.wav` (**TTS**). Elle est maintenant à l'emplacement réellement
lu par `Tete3ParitePaqueDeployeAudioReelTest` ; le test ne réussit plus
silencieusement si le fichier manque. Cette référence teste les
caractéristiques et le logit de la **tête actuellement déployée**, pas ceux
de la nouvelle candidate. Son nom historique « AudioReel » n'est pas une
preuve de récitation humaine.

## Replay Samsung après branchement du vote et comparaison de la candidate

Le chemin de vote est activé uniquement par le marqueur de debug
`files/vote_fenetres_actif`. La candidate est chargée dans
`files/tete3_hafs_comparaison.json` et reste en observation ; la tête de
décision du pack n'a pas été remplacée.

Sur le même extrait T023 (36:2..4, 18,405 s, PCM identique), l'APK de travail
`C39D0BE55A8AF7259DFAE358DDFDD01BC3A4617EF1930961F69BC09BEFDB7384` a produit
une session normale fermée, sans décrochage ni demande de répétition. Le mot
attendu `ٱلْمُرْسَلِينَ`, prononcé `ٱلْمُرْسَلُونَ`, est devenu
`provisoire:rouge` dès les deux premières lectures cohérentes, puis
`definitif:rouge` à la fermeture. Les trois votes utiles ont les mêmes bornes
audio `[130560,142080]` et un poids total **2,541991**. La lecture parasite
`إِلَىٰ` (`[193280,202240]`, poids 0,760266) ne l'annule plus : elle forme une
seconde occurrence isolée.

Ce résultat est une amélioration mesurée du jugement sur ce cas : le témoin
précédent finissait `provisoire:vert` après la dernière fenêtre, et la première
version du vote redevenait orange en déclarant toutes les plages disjointes
ambiguës. Il s'agit d'un seul cas ciblé, pas encore d'un taux de campagne.

La comparaison de tête 3 sur ce même audio ne justifie pas son activation :
pour le mot fautif, l'ancienne tête donne les logits `-5,42/-5,94/-5,68` sur
les trois lectures fautives, la candidate `-9,47/-4,74/-9,56`, et les deux
montent sur la lecture parasite (`9,56` contre `8,72`). Comme la candidate n'a
ni seuil calibré ni validation sur les fautes réelles, ces valeurs restent des
traces de comparaison ; le vote texte est la cause du rouge, pas la tête 3.

Preuves du replay :

- `vote_T023_36_3_decision_occurrence_20260915/` (manifeste, exécution, logs,
  capture écran) ;
- `vote_T023_36_3_decision_candidate_20260915/` (premier replay avec candidate,
  sans regroupement d'occurrence) ;
- les lignes `[t3-comparaison]` portent la candidate SHA-256
  `7e708b20a9a13e53f14b0491c36396992bdb2b078c05208215d774837e03b66e`.

Un second cas ciblé de la famille annoncée par la candidate a été rejoué :
T014, 55:10, `وَٱلْأَرْضَ` remplacé par `ٱلْأَرْضَ`, avec un verset de contexte.
La session Samsung est également normale et fermée, mais le modèle libre a
reconnu la forme attendue sur les deux fenêtres intérieures utiles ; le vote
reste donc `provisoire:vert` puis `definitif:vert`. La candidate ne fournit pas
de séparation exploitable (`-9,56` puis `-8,07`, statut `NON_CALIBREE`) et ne
justifie pas son activation. Preuves :
`vote_T014_55_10_candidate_20260915_run/`.

Trois autres faux négatifs historiques ont été contrôlés dans la même
configuration, toujours avec la candidate en comparaison : T002 harakat
(`فِيهَآ`), T031 omission (`مُخْتَلِفُونَ`) et T081 troncature (`كَلَّا`). Les
trois sessions sont normales et fermées sans répétition. Dans chacun, le libre
ASR a fourni la forme attendue sur les fenêtres intérieures ; le vote produit
donc vert. Les logits candidate restent `NON_CALIBREE` et n'apportent pas de
séparation utilisable. Cela confirme une limite de l'audio synthétique : quand
le modèle ne perçoit pas la coupe ou la substitution, la tête 3 ne peut pas
être déclarée gagnante sur le seul logit.

Preuves : `vote_T002_78_23_candidate_20260915_run/`,
`vote_T031_78_3_candidate_20260915_run/` et
`vote_T081_78_4_candidate_20260915_run/`.

## Replay ciblé des 11 cas historiques `green_after_negative`

Les dix extraits restants du rapport historique ont été préparés puis joués
sur le Samsung `R3CY20XW7TD` avec l'APK de travail
`C39D0BE55A8AF7259DFAE358DDFDD01BC3A4617EF1930961F69BC09BEFDB7384`.
T023 avait déjà été rejoué dans la même configuration. Chaque extrait garde
le verset cible et un voisin ; aucun run de 20 versets n'a été relancé. Les
onze sessions ont fini `AUDIO_FINISHED`, avec 0 décrochage et 0 demande de
répétition.

| cas / mot global | ancien dernier statut | vote + décision sur l'extrait | lecture utile |
|---|---|---|---|
| T004 / 30 (55:11) | définitif vert | définitif vert | le libre entend `فِيهَا`, équivalent à la variation injectée |
| T005 / 115 (67:10) | définitif vert | **définitif rouge** | trois fenêtres votent `أَصْحَـٰبَ` contre `أَصْحَـٰبِ` |
| T006 / 30 (78:11) | définitif vert | définitif vert | le libre réentend la forme attendue |
| T013 / 50 (36:10) | définitif vert | définitif vert | le libre réentend la forme attendue |
| T016 / 25 (78:10) | définitif vert | **provisoire orange** (`INDECIS`) | candidats isolés, aucun vote majoritaire |
| T023 / 5 (36:3) | définitif vert | **définitif rouge** | trois fenêtres votent `ٱلْمُرْسَلُونَ` contre `ٱلْمُرْسَلِينَ` |
| T033 / 6 (36:4) | définitif vert | définitif vert | le libre réentend la forme attendue |
| T038 / 4 (36:3) | définitif vert | définitif vert | le libre réentend la forme attendue |
| T064 / 5 (55:4) | définitif vert | définitif vert | insertion : verdict voisin, proxy qui ne compte pas comme rappel |
| T075 / 112 (67:10) | définitif vert | **provisoire orange** (`INDECIS`) | deux fenêtres exploitables absentes ou fragments |
| T075 / 113 (67:10) | définitif vert | provisoire vert | une seule lecture exploitable ; pas assez pour conclure sur la permutation |
| T095 / 38 (67:4) | définitif vert | définitif vert | le libre réentend la forme attendue |

Sur les douze positions mutées couvertes, deux passent au rouge définitif
(T005 et T023) et deux ne sont plus blanchies mais restent en attente
(T016 et T075/112). Les autres verts ne prouvent pas une régression du vote :
le libre y a reconnu la forme attendue, ou bien l'opération est une insertion
sans mot attendu comparable. Le résultat mesure donc une amélioration ciblée
du jugement, pas un taux global de rappel.

La candidate `tete3_hafs_particules.json` était chargée uniquement via
`tete3-comparaison`. Tous les logs la marquent `NON_CALIBREE` et elle n'a
fourni aucun veto au vote texte. Elle reste donc une piste de calibration ;
ces replays ne justifient pas le remplacement de la tête de production.

Preuves : `vote_T004_30_decision_20260915/`,
`vote_T005_115_decision_20260915/`, `vote_T006_30_decision_20260915/`,
`vote_T013_50_decision_20260915/`, `vote_T016_25_decision_20260915/`,
`vote_T023_36_3_decision_occurrence_20260915/`,
`vote_T033_6_decision_20260915/`, `vote_T038_4_decision_20260915/`,
`vote_T064_5_decision_20260915/`, `vote_T075_112_decision_20260915/` et
`vote_T095_38_decision_20260915/`.

## Travail restant pour atteindre la demande

Mise à jour du 15/09 : les points 2 à 4 ci-dessous ont été branchés dans le
chemin expérimental et couverts par les tests natifs. Ils restent à confirmer
sur plusieurs versets Samsung ; le point 5 (candidate tête 3) reste en
observation non calibrée.

1. Calibrer la fiabilité des hypothèses sur les observations natives, avec
   erreurs audio connues ET mots corrects de contrôle. Comparer poids
   uniformes, pics CTC et entropie. Ne pas régler sur T023 seul.
2. Intégrer le choix A/B/C au décideur et juger la lecture retenue en gardant
   les équivalences phonétiques déjà décrites par `Orthographe`. Conserver
   les vraies différences de harakat/lettres et les preuves d'ordre.
3. Traiter ensemble `nette`, le consensus de couleurs, le secours d'omission
   et `meilleurProvisoire`. Une lecture complète contradictoire doit pouvoir
   faire réviser un provisoire ; une lecture découpée ne doit pas devenir
   majoritaire par multiplication de fenêtres inutilisables.
4. Définir et mesurer la clôture du vote selon les fenêtres encore possibles.
   Ne pas verrouiller un premier vert avant les observations contradictoires.
   Ne pas attendre la fin de toute la session pour afficher un résultat.
   Maintenir le refus de `k=1` à la fermeture. Le pont Dart doit afficher la
   preuve choisie, pas un GOP provenant arbitrairement de la dernière fenêtre.
5. Mesurer la candidate tête 3 sur les **mêmes vecteurs/frames** que l'actuelle,
   en observation d'abord ; vérifier sa parité et calibrer ses seuils sur
   fautes audio. Ne pas la convertir en poids de transcription ni lui donner
   un veto vert isolé qui recréerait le défaut.
6. Rejouer uniquement les versets en échec, sur Samsung, avec leur contexte
   nécessaire et un témoin identique. Les 11 cas `green_after_negative` ne
   couvrent pas tous les faux négatifs des 100 sessions. Prévoir aussi des
   témoins propres pour mesurer les faux signalements.
7. Rapporter rappel des fautes, faux signalements, non jugés, indécisions,
   reprises et latence. Un résultat de vote n'est pas encore un statut app.

Nœuds du graphe relus : `piege_verrou_sur_apercu`,
`piege_attestation_normalisee_blanchit`, `piege_gop_vs_free`,
`attente_sens_unique_provisoire`, `mort_k1_a_la_fermeture`.
Le changement de demande du 15/09 permet de revoir le provisoire à sens
unique, mais ne supprime pas la cause historique : les fragments de bord.

## Commandes disponibles

Depuis la racine :

```powershell
python -X utf8 benchmark/preparer_vote_cible.py --case T023 --mot 5 --out benchmark/nouveau_dossier_cible
python -X utf8 benchmark/extraire_vote_fenetres.py benchmark/vote_T023_36_3_mesure_20260915 --temoin benchmark/vote_T023_36_3_temoin_20260915
```

Le préparateur refuse d'écraser une sortie et vérifie le PCM extrait. Le
runner `campagne_100x20.run(serial)` lit désormais `verse_count` du cas ; son
défaut reste 20 pour les anciens manifestes. Donner au module un `OUT` neuf
pour chaque binaire, il refuse de mélanger deux empreintes d'APK.

Depuis `app/android` :

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*recitation2.*' --console=plain
```

La première passe a exécuté 105 tests dont les 16 nouveaux tests du vote,
sans échec ; à ce moment le test de caractéristiques TTS n'avait pas encore
son fichier de référence. Le journal séparé
`validation_tete3_particules_20260915.log` porte la vérification ultérieure
de la candidate et de la référence TTS réellement chargée. Garder cette
distinction ; « tous verts » ne signifie pas automatiquement « tout vérifié ».

Derniere passe complete apres reception de la reference TTS : **119 tests,
0 echec, 0 erreur, 0 saut JUnit**, dont le nouveau test de candidate et
le test de caracteristiques TTS reellement execute. XML, rapport HTML et
comptage archives dans `preuves_tests_vote_20260915_final/` ; le journal de
commande est `validation_native_vote_tete3_final_20260915.log`. Les anciens tests legacy qui
retournent silencieusement faute de leur propre modele restent des limites
distinctes ; leur vert ne certifie pas ces anciens modeles.
