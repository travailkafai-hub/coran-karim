# Tâches : streaming causal FastConformer

## Tâche 1 — Prouver le contrat stateful

- [x] Ajouter un test qui rejette l'ancien checkpoint non causal.
- [x] Exporter `causal-final.nemo` avec les cinq entrées stateful.
- [x] Écrire les métadonnées `121/112/9/8`.
- [x] Vérifier au moins trois chunks et un cache qui progresse.

Vérification :
`PYTHONPATH="$PWD/benchmark/.venv_nemo/lib/python3.14/site-packages" /usr/bin/python3.14 benchmark/validate_streaming_onnx.py`

Fichiers : deux scripts `benchmark/`, métadonnées générées non committées.

## Tâche 2 — Sécuriser les primitives Kotlin

- [x] Tester le chargement/contrôle des métadonnées.
- [x] Tester le collapse CTC à travers deux chunks.
- [x] Tester le reset complet de l'état pur.

Vérification : `cd app/android && ./gradlew app:testDebugUnitTest`

Fichiers : primitives Kotlin et tests JVM, 3 à 5 fichiers.

## Tâche 3 — Porter la session ONNX causal

- [x] Consommer les dimensions exportées.
- [x] Transmettre et remplacer les caches à chaque appel.
- [x] Retourner texte et nouvelles log-probabilités sans double inférence.
- [x] Alimenter l'alignement forcé avec le payload existant.

Vérification : tests Android puis `cd app && flutter build apk --debug`.

Fichiers : session et plugin Kotlin, 2 à 4 fichiers.

## Tâche 4 — Brancher le mode continu

- [ ] Charger le modèle stateful pour `continuous=true`.
- [ ] Fermer la session stateless avant le causal.
- [ ] Préserver le fallback bufferisé.
- [ ] Réinitialiser sur arrêt, correction et nouvelle session.

Vérification : tests Flutter ciblés, analyse et build.

Fichiers : deux services Dart, éventuellement l'interface de vérification.

## Tâche 5 — Valider et livrer

- [ ] Déployer le modèle stateful et l'APK sur le téléphone.
- [ ] Vérifier chargement, caches, transcript et absence de tajweed.
- [ ] Tester le rollback bufferisé.
- [ ] Effectuer la revue à cinq axes.
- [ ] Committer chaque incrément avec un périmètre explicite.
