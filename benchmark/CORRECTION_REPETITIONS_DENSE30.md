# Détection et répétitions — correction du 15 septembre 2026

## Correction réalisée

Après une demande de reprise, la chaîne effaçait les statuts depuis l'ancre,
mais conservait toutes les anciennes observations comme preuves actives. Le
prochain appel de jugement pouvait remettre les mots au vert sans nouvel audio,
ou utiliser l'ancienne attestation exacte pour blanchir une répétition fautive.
Le chemin de reprise après souffleur présentait le même défaut.

Le registre distingue maintenant l'archive et les preuves de la tentative
courante. Un recul enregistre deux bornes : la position dans la liste des
observations et le premier échantillon de la nouvelle tentative. Cela exclut
aussi une fenêtre traitée plus tard qui recouvrirait l'ancien audio. Les
observations ne sont pas détruites : elles restent disponibles à l'écoute et à
l'audit.

Les règles de décision, les omissions et le contrôle d'ordre utilisent cette
vue courante. Les anciens verts provisoires et les données de tajwid depuis
l'ancre sont réinitialisés. Les mots précédant l'ancre restent acquis. Les
métadonnées envoyées à Flutter décrivent la nouvelle tentative. Le constructeur
de fenêtres reprend à l'horloge brute, même si un bloc de capture était incomplet.

Fichiers du moteur :

- [RegistreDePreuves.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/RegistreDePreuves.kt)
- [Decideur.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Decideur.kt)
- [ChaineRecitation.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/ChaineRecitation.kt)
- [FastConformerCtcPlugin.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt)

## Vérification

Avant correction : 6 échecs sur les 7 premiers tests de reprise, reproduisant
notamment le retour d'un vert sans nouvel audio et le masquage d'une répétition
fautive. [Résultat avant correction](campagne_100x20_dense30/validation_repetitions_avant.xml).

Après correction : les 10 tests de preuves et les 2 tests de flux audio passent.
Les seconds alimentent les vraies fenêtres, le localisateur, l'aligneur et le
décideur avec du PCM synthétique et un front acoustique déterministe. Ils
vérifient un mot correct puis répété faux, et un mot faux puis répété correctement,
avec contrôle des mots voisins. Ils n'utilisent pas le modèle ONNX du téléphone.

La suite `recitation2` compte 87 tests déclarés, zéro échec, dont 6 nouveaux
tests sur les seuils absents, les dimensions et les données non finies de la
tête 3. Deux anciens contrôles de parité tête 3
signalent dans leur sortie que leurs fichiers externes sont absents : leur
parité numérique n'est donc pas validée par ce lancement. Les 12 tests ciblés
de reprise ne dépendent pas de ces fichiers.

```powershell
Set-Location app/android
.\gradlew.bat :app:testDebugUnitTest --tests '*recitation2.*' --console=plain
```

[Journal Gradle](campagne_100x20_dense30/validation_repetitions_gradle.log),
[résumé de validation](campagne_100x20_dense30/validation_repetitions_apres.json).
Le code Kotlin et le pont Android compilent. Ce changement n'a pas été installé
sur téléphone et les 100 sessions archivées n'ont pas été rejouées avec lui.
Le gain global sur les enregistrements réels reste à mesurer.

Les 3 tests Flutter ciblant le recul et le redémarrage de capture passent aussi :

```powershell
Set-Location app
flutter test test/recitation_rewind_test.dart test/recitation_capture_restart_test.dart
```

[Journal Flutter](campagne_100x20_dense30/validation_repetitions_flutter.log).
L'analyse Dart du service modifié ne relève aucune erreur ni avertissement,
avec 6 suggestions de style :
[journal d'analyse](campagne_100x20_dense30/validation_verifier_analyse.log).

## Tête 3 : données utilisables pour une calibration

Le paquet courant à cinq têtes contient des têtes Hafs et Warsh à 1036 entrées
sans `seuils_mesures`. Le chargeur remplaçait cette absence par zéro, que le
journal présentait ensuite comme un seuil à 2 % de faux signalements.

L'absence est maintenant conservée : le score reste disponible, avec l'état
`NON_CALIBREE`. Les entrées incompatibles ou non finies ne sont pas présentées
comme correctes. Chaque observation conserve le score, son éventuel seuil et
son état. La trace native et les métadonnées V2 exposent la fenêtre et les
bornes audio pour relier une décision aux mesures correspondantes.

Cette tête reste observatrice. Aucun seuil d'un autre modèle n'a été transféré
et aucune nouvelle règle de couleur fondée sur son logit n'est activée. Le
[document de travail pour Claude](TACHE_CLAUDE_CALIBRATION_TETE3_ET_REPETITIONS.md)
décrit la parité sur appareil, les témoins propres et fautifs, les reprises
synchronisées et la comparaison de deux variantes du décideur.

## Ce que l'audit des 100 WAV corrige dans les anciens résultats

L'audit a vérifié les empreintes des 100 WAV, reconstruit leurs 600 éditions
depuis les sources et comparé les pistes PCM intégrales. Le manifeste décrit
parfois l'intention plutôt que l'opération réalisée :

| Étiquette historique | Montage réellement vérifié |
|---|---|
| `omission_word` (70) | Début du mot conservé à 48 %, donc troncature |
| `omission_2words` (60) | 33 suppressions de deux mots, 27 de trois mots |
| `extra_letter` (65) | 15 ajouts, 24 substitutions, 26 retraits de lettre de base |
| `near_word_substitution_fallback` (28) | 7 substitutions et 21 préfixes dupliqués suivis du mot original intégral |

322 opérations portent aussi un `replacement_text` donneur inutilisé. Ce texte
ne doit pas être présenté comme le mot injecté. L'absence d'un verdict peut
concerner un montage encore non joué lorsque l'app demande une reprise ; ce
n'est pas automatiquement un échec de détection.

Le nouveau rapport détaille **369 opérations couvrant 505 positions de mots**.
Les signaux V2 et tête 3 sont lus dans le même snapshot avant fermeture, avec
leur numéro de ligne et leur phase avant/après demande. Les 26 761 signaux tête 3
de ces snapshots ne sont plus recopiés sur chaque observation d'un même mot.

Reproduire l'audit puis le rapport :

```powershell
python -X utf8 benchmark/campagne_100x20_dense30/auditer_montages_dense30.py
python -X utf8 benchmark/campagne_100x20_dense30/extraire_mots_mal_juges.py
```

[Rapport vérifié](campagne_100x20_dense30/MOTS_MAL_JUGES_CAMPAGNE_DENSE30_POUR_CODEX.md),
[audit PCM](campagne_100x20_dense30/audit_montages.json),
[audit tête 3 avant reprise](campagne_100x20_dense30/audit_tete3_avant_reprise.json).

## Pistes encore à mesurer

1. **Vert après un signal négatif avant toute demande de reprise.** Dix opérations
   hors insertion du premier export présentent cette transition, dont une
   duplication conservant le mot intact. Elles sont toutes antérieures à la
   première demande de reprise. Le défaut corrigé ci-dessus ne suffit donc pas
   à expliquer ces transitions. Examiner le raccourci d'attestation `nette`,
   le consensus entre fenêtres et le cas `deplace` révisé sur un nouvel
   alignement : T005/mot 115, T013/mot 50, T075/mots 112–113 notamment.
2. **Un signal tête 3 peut coexister avec un vert.** Avant la première reprise,
   c'est le cas de 4/24 acceptations vertes sur les substitutions proches,
   2/16 sur les substitutions de diacritiques, 5/52 sur les troncatures.
   L'ancien code journalisait `DEVIATION_SUSPECTEE` avec le seuil zéro par
   défaut, sans le transformer en statut V2. Ce décompte ne prouve donc pas
   une capacité calibrée de détection.
   Mesurer une règle de confirmation avec des témoins propres et des erreurs
   phonétiques validées avant de faire de ce signal une condamnation automatique.
3. **Mesurer des tentatives qui se terminent réellement.** Une nouvelle campagne
   doit répondre à la reprise avec un audio prévu : tentative fautive, répétition
   fautive, puis répétition correcte. Rapporter détection, acceptations à tort,
   absence de verdict et délai séparément pour chaque tentative. Les snapshots
   historiques s'arrêtant à la demande de reprise ne prouvent pas cette capacité.
4. **Corriger le générateur avant une nouvelle série.** Préparer les vraies
   omissions d'un mot et les ajouts d'une lettre dans un nouveau dossier, garder
   les WAV historiques avec leurs empreintes, et vérifier le montage PCM avant
   toute inférence sur les taux par famille.

Ces pistes concernent la sensibilité du jugement sur une tentative donnée.
Le correctif livré résout la contamination entre tentatives, sans recalibrer
les seuils acoustiques à partir des anciens taux mal étiquetés.
