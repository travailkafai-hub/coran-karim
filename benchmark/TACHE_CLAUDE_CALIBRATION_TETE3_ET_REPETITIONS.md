# Tâche pour Claude — améliorer la décision ASR et mesurer l'apport de la tête 3

Demande utilisateur : continuer à améliorer la détection, notamment lorsqu'une
erreur est reconnue puis devient verte au fil des observations ou des reprises.
Ce document décrit le travail à effectuer et les preuves à produire.

Extension du 15 septembre : l'utilisateur propose un vote entre les textes
entendus, pondéré par leur fiabilité. Voir la
[proposition et le prototype Hafs](PROPOSITION_VOTE_PONDERE_HAFS.md), avec les
cas de désaccord à tester. Les poids de démonstration ne sont pas calibrés.

## État du code à reprendre

Les modifications locales ne sont pas commitées. La dernière campagne Android
reste celle du dossier `campagne_100x20_dense30` ; elle n'a pas été rejouée avec
ces modifications. Relever les empreintes du code et de l'APK utilisé pour les
nouveaux tests.

1. **Reprises corrigées** : `RegistreDePreuves.commencerTentative` isole les
   observations antérieures à la reprise. Le jugement, le contrôle d'ordre et
   les omissions lisent les preuves courantes. Les anciennes observations
   restent archivées. Les verts provisoires et les données de tajwid depuis
   l'ancre sont réinitialisés. Les deux chemins sont couverts :
   `reculerAncre` et `repartirApresSouffle`.
2. **Tête 3 instrumentée** : chaque observation conserve `mesureTete3` et
   `etatTete3`, avec le numéro de fenêtre et les bornes dans l'audio. Les
   métadonnées du pont Android et la trace V2 Flutter les exposent également.
3. **Seuil absent explicite** : les seuils de `Tete3` sont désormais nullables.
   Un seuil manquant ne devient plus zéro. Le score est conservé avec
   `NON_CALIBREE`. Un score non fini n'est plus décrit comme « ok ».
4. **La tête 3 ne tranche toujours pas les couleurs**. Son seuil et son apport
   au jugement doivent être mesurés. La présence d'un fichier de seuils ne
   prouve à elle seule ni sa validité pour cet encodeur ni un gain de détection.

Sources principales :

- [RegistreDePreuves.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/RegistreDePreuves.kt)
- [Decideur.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Decideur.kt)
- [ChaineRecitation.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/ChaineRecitation.kt)
- [Tete3.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Tete3.kt)
- [FastConformerCtcPlugin.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt)
- [fastconformer_verifier.dart](../app/lib/services/fastconformer_verifier.dart)

## Constat sur le paquet actuel

Dans `app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/` :

| Fichier | Entrées | Seuils mesurés dans le JSON | SHA-256 relevé |
|---|---:|---|---|
| `tete3.json` | 1036 | absents | `c594993a1d3687aa33ba7f521866fbeb5e2c2078c2cb7225911540fb43e0ef99` |
| `tete3_warsh.json` | 1036 | absents | `f6ac3851d5ed7896ff56443d151d129669aac03f5bff0efad0387603259f625d` |

L'ancien paquet à quatre têtes contient une tête à **524 entrées** avec des
seuils. Ne pas transférer ses seuils à la tête à 1036 entrées. Relever aussi
l'empreinte de l'ONNX et vérifier quels fichiers sont réellement chargés sur
le téléphone : les fichiers de la copie de travail ne suffisent pas.

Les anciens journaux `seuil2%=0,000 DEVIATION_SUSPECTEE` reposaient sur le zéro
par défaut, pas sur un faux positif mesuré à 2 %. Les compter permet de repérer
des exemples, pas de démontrer une précision de la tête.

## 1. Vérifier la parité du calcul de la tête utilisée

Faire passer les tests Kotlin existants, puis la parité sur le téléphone avec
les poids effectivement chargés. La parité sur la JVM seule ne valide pas tout
le chemin encodeur → extraction des caractéristiques → tête sur appareil.

Depuis la racine :

```powershell
Set-Location app/android
.\gradlew.bat :app:testDebugUnitTest --tests '*recitation2.*' --console=plain
```

Vérifier explicitement les tests :

- `RepetitionPreuvesTest` et `RepetitionFluxTest` ;
- `Tete3CalibrationTest` et `Tete3Test` ;
- `Tete3PariteTest` et `Tete3TraitsTest` pour la portée réelle de leurs fixtures.

Certains anciens tests impriment « parité NON vérifiée » lorsque leurs fichiers
sont absents puis retournent sans échouer. Ne pas les compter comme une preuve
de parité. Utiliser des vecteurs de référence produits avec le **bon modèle**,
et vérifier chaque caractéristique ainsi que le score final. Pour l'appareil,
ajouter si nécessaire un export diagnostic des vecteurs, des logprobs et des
bornes de mots ; le test doit exercer le même calcul que l'app.

## 2. Construire une nouvelle campagne avec vérité de construction vérifiée

Créer un nouveau dossier, par exemple `benchmark/campagne_asr_tete3_reprises/`.
Ne pas écraser les WAV ni le manifeste historiques et ne pas réutiliser leur
fichier `executions.jsonl` pour un autre APK.

Corriger les erreurs du générateur avant la préparation :

- `omission_word` doit réellement supprimer le mot ; les 70 anciens cas sont
  des troncatures à 48 %.
- Une omission de deux mots doit avoir exactement deux index distincts.
- Une lettre ajoutée doit augmenter d'une lettre la base du mot ; distinguer
  substitution et retrait dans les métadonnées.
- Renseigner le récitant donneur et `replacement_text` seulement si ce donneur
  a effectivement été injecté.
- Un préfixe dupliqué suivi du mot intact est une insertion/bégaiement ; il
  ne constitue pas une substitution du mot attendu.

Conserver le protocole demandé : passages de **20 versets**, **6 versets
perturbés sur 20**, erreurs variées, lecture à vitesse réelle dans l'app.
Préparer un audio propre apparié pour chaque passage fautif. Vérifier les
empreintes, les montages et les intervalles PCM ; faire valider à l'écoute
les erreurs de voyelles ou d'une lettre utilisées pour calibrer le modèle.

Le fichier [auditer_montages_dense30.py](campagne_100x20_dense30/auditer_montages_dense30.py)
montre comment vérifier les fichiers historiques octet par octet. Il décrit
leurs transformations réelles ; ce n'est pas un validateur phonétique ni un
générateur de la nouvelle série.

## 3. Exercer la répétition au lieu de terminer au premier décrochage

Commencer par un pilote de dix scénarios avant de lancer la série complète.
Le driver doit gérer le protocole de l'app :

1. Lire l'audio fautif et attendre le vrai événement de reprise et l'ancre.
2. Attendre la fin de l'aide et la reprise effective de la capture.
3. Fournir depuis l'ancre une répétition encore fautive : vérifier que le
   nouveau jugement ne réutilise pas une ancienne validation.
4. Après la nouvelle reprise, fournir le passage correct : vérifier que
   l'erreur est résolue et que le suivi avance.

Un simple WAV contenant trois fois le passage ne prouve pas ce protocole :
l'app peut être en pause lors des deuxième et troisième passages. Instrumenter
ou compléter le driver recette pour synchroniser ses entrées avec les événements
de capture. Garder la même session et sa cible. Chaque segment injecté et chaque
demande de reprise doivent avoir un identifiant de tentative et un horodatage.

Ajouter le témoin « première lecture correcte, répétition incorrecte » et le
témoin « répétition correcte d'un passage correct ». Sur décrochage, conserver
le comportement utilisateur : demander la reprise au bon endroit. Ne pas
modifier ce mécanisme pour obtenir artificiellement plus de fins audio.

## 4. Calibrer puis évaluer une fusion avec le décideur

Produire des jeux de calibration et d'évaluation distincts par passage/audio
source ; un mot donneur, ses variantes et leurs relectures doivent rester dans
le même groupe. Éviter qu'un extrait serve à la fois à choisir le seuil et à
annoncer le gain. Évaluer Hafs et Warsh séparément avec leurs encodeurs/têtes.

Collecter pour chaque observation :

- APK/ONNX/tête et empreintes ; scénario, tentative, mot et type d'erreur réel ;
- `statut` émis par l'app, jamais un verdict recalculé en comparant deux
  transcriptions dans le script d'analyse ;
- logit tête 3, seuil éventuel, état de disponibilité/calibration ;
- fenêtre, début/fin absolus, intérieur/bord, attestation, GOP et marges ;
- premier signal négatif, demande de répétition, verdict final et délai.

Les lignes nouvelles ont `t3Etat`, `t3Logit`, `t3Seuil2Pct`, `preuveFenetre`
et `preuveAbs`. Les lignes natives `[t3] mot=N` portent également `f` et `abs`.
Attention : `finAbs` correspond au début de la dernière frame CTC ; une frame
unique peut avoir `debutAbs == finAbs`. Pour découper le son, inclure la durée
de cette dernière frame et borner l'extrait au flux disponible.

Sur le jeu de calibration, mesurer le seuil pour la cible historique de **2 %
de faux signalements**. Conserver aussi la courbe complète, l'effectif de vrais
mots corrects et l'intervalle d'incertitude. Un petit échantillon ne démontre pas
une contrainte à 2 %. Documenter les abstentions séparément.

Comparer deux variantes sur le même jeu tenu à l'écart :

- **A :** décideur actuel avec correction des reprises ; tête 3 observatrice ;
- **B :** proposition de fusion documentée, utilisant les scores calibrés de
  la tentative courante. Exemple à tester : désaccord confirmé dans deux
  fenêtres empêchant le raccourci de validation verte. Comparer cette option
  à un signal provisoire puis confirmation, sans figer sur une unique mesure.

Ne pas annoncer « B détecte mieux » uniquement parce que le nombre de rouges
augmente. Mesurer le rappel sur les erreurs réellement jouées, les faux
signalements sur les témoins corrects, les erreurs encore vertes, la couverture
des verdicts et les délais. Rapporter les taux par famille et par tentative,
avec effectifs et intervalles. Séparer les montages non atteints avant reprise
des erreurs effectivement entendues sans verdict.

## 5. Exemples à examiner en priorité

- T005/mot 115, T013/mot 50 : signal négatif puis vert avant toute demande de
  reprise ; examiner le raccourci `nette` et les preuves qu'il retient.
- T075/mots 112–113 : `deplace` puis vert ; vérifier si les observations
  temporelles montrent une vraie nouvelle lecture ou un réalignement du même
  audio. La correction des reprises explicites ne résout pas à elle seule ce cas.
- Les substitutions et troncatures avec ancien signal tête 3 et vert app :
  [audit_tete3_avant_reprise.json](campagne_100x20_dense30/audit_tete3_avant_reprise.json).

Consulter d'abord [le rapport rectifié](campagne_100x20_dense30/MOTS_MAL_JUGES_CAMPAGNE_DENSE30_POUR_CODEX.md).
Les anciens « 75 % de faux négatifs du fallback » mélangent un mot remplacé
et un mot conservé après ajout ; ce taux ne doit pas piloter une calibration.

## Livrables attendus de Claude

Dans le nouveau dossier :

- `PROTOCOLE.md`, scripts de préparation/exécution/analyse, manifeste et vérité
  des montages, empreintes des sources et des binaires ;
- références Python/device et `PARITE_TETE3.md` avec les différences mesurées ;
- `CALIBRATION_TETE3.json` avec le modèle, la riwaya, le jeu de calibration,
  le seuil, les effectifs et les faux signalements mesurés ;
- journaux, WAV d'entrée, captures, `tentatives.csv` et `observations.jsonl` ;
- `COMPARAISON_A_B.md` contenant les métriques avant/après et une conclusion
  sur le gain réellement observé, y compris les régressions éventuelles ;
- si la fusion améliore la détection à qualité contrôlée : modification du
  décideur, tests de non-régression et note expliquant ses conditions d'activation.

En cas de données insuffisantes, produire les mesures et nommer précisément ce
qui manque. Garder les signaux non calibrés identifiés comme tels.
