# Spécification : streaming causal FastConformer sans tajweed

## Objectif

Remplacer, pour la récitation continue, la re-transcription répétée de segments
complets par l'inférence cache-aware du checkpoint causal déjà validé
`fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo`.

Le premier déploiement reste mono-tête : il vérifie les lettres et les harakat,
mais ne produit aucun verdict acoustique de tajweed. Le chemin bufferisé actuel
reste disponible comme retour arrière.

## Pile technique

- Flutter/Dart pour la capture et l'orchestration.
- Kotlin Android pour le mel-spectrogramme, ONNX Runtime et l'alignement CTC.
- NeMo/PyTorch pour l'export de l'encodeur causal avec caches.
- ONNX Runtime 1.20 côté Android et Python pour la validation hors device.

## Commandes

- Export : `PYTHONPATH="$PWD/benchmark/.venv_nemo/lib/python3.14/site-packages" /usr/bin/python3.14 benchmark/export_streaming_onnx.py`
- Validation ONNX : `PYTHONPATH="$PWD/benchmark/.venv_nemo/lib/python3.14/site-packages" /usr/bin/python3.14 benchmark/validate_streaming_onnx.py`
- Tests Flutter : `cd app && flutter test`
- Analyse : `cd app && flutter analyze`
- Build : `cd app && flutter build apk --debug`
- Tests Android ciblés : `cd app/android && ./gradlew app:testDebugUnitTest`

## Structure concernée

- `benchmark/export_streaming_onnx.py` : export stateful du checkpoint entraîné.
- `benchmark/validate_streaming_onnx.py` : fidélité multi-chunks et contrat.
- `app/android/.../fastconformer/` : état ONNX, CTC incrémental et alignement.
- `app/lib/services/` : sélection du moteur causal et fallback bufferisé.
- `tasks/` : spécification et suivi de l'implémentation.

## Style

Le contrat est explicite et validé avant usage :

```kotlin
data class StreamingModelConfig(
    val chunkFrames: Int,
    val preEncodeCacheFrames: Int,
    val timeCacheFrames: Int,
)
```

Les dimensions ne doivent plus être déduites d'un ancien checkpoint ou
dispersées sous forme de constantes non vérifiées.

## Stratégie de test

1. Test de contrat : l'export doit utiliser le checkpoint causal entraîné et
   exposer les cinq entrées stateful attendues.
2. Test d'intégration Python : PyTorch et ONNX doivent rester proches sur au
   moins trois chunks consécutifs avec transmission des caches.
3. Tests unitaires Kotlin : configuration, fusion CTC inter-chunks et reset.
4. Build Flutter/Android.
5. Test réel sur téléphone : chargement du bon modèle, croissance du cache,
   texte non vide, absence de crash et fallback encore fonctionnel.

## Limites

- Toujours : conserver `audio_signal`, transmettre les caches, ne charger qu'un
  gros modèle à la fois, préserver le fallback et les commentaires historiques.
- Demander avant : changer le contexte `[70,13]`, activer les verdicts tajweed,
  supprimer le chemin bufferisé ou modifier les seuils de jugement.
- Jamais : utiliser `raw_audio`, déployer le modèle causal initial non entraîné,
  charger simultanément les sessions stateless et stateful en production,
  committer les fichiers de training hors périmètre.

## Critères de réussite

- L'ONNX déployé provient de `causal-final.nemo`, sans tête tajweed.
- Chaque chunk audio est inféré une seule fois et les caches évoluent.
- Le collapse CTC reste correct à travers une frontière de chunk.
- `ForcedAligner` reçoit les log-probabilités incrémentales.
- Un reset efface texte, caches et état d'alignement.
- La récitation continue utilise le causal, avec repli explicite sur le moteur
  bufferisé si le modèle stateful est absent ou échoue au chargement.
- Le build passe et une vraie récitation produit du texte sur le téléphone.

## Questions résolues par validation utilisateur

- Le compromis de qualité du causal et son lookahead de 1,04 s sont acceptés.
- Le premier modèle reste sans tajweed.
- Le chemin bufferisé est conservé comme rollback.
