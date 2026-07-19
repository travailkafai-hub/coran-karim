# Coran Karim — guide agent (index, le détail vit dans les .md dédiés)

App Android (Flutter/Kotlin) de récitation coranique : vérification ASR
(FastConformer CTC + Whisper), tuteur textuel (Gemma LoRA), révision (FSRS).
3 piliers, 3 technos — cf. `ARCHITECTURE.md`.

## Documents de référence — lire AVANT d'agir sur le sujet correspondant

| Sujet | Document |
|---|---|
| Point d'entrée courant, changement de machine, état git | `HANDOFF.md` (à tenir à jour) |
| État complet piste NeMo CTC : modèles, WER, déploiement, reste à faire | `ETAT_CTC_NEMO.md` |
| Mémoire technique ASR détaillée (pièges, décisions, méthodes) | `.claude/skills/model-training/references/asr.md` |
| Tuteur Gemma LoRA (bug regex, QAT, datasets) | `.claude/skills/model-training/references/gemma-llm.md` |
| Historique des benchmarks et décisions chiffrées | `benchmark/BENCHMARK_RESULTS.md` |
| Idées validées non implémentées (madd, fenêtre glissante...) | `FONCTIONNALITES_FUTURES.md` |
| Chantier "Suivre une prière" (journal détaillé) | `SUIVI_PRIERE.md` |

Tout entraînement/export/diagnostic de modèle : invoquer le skill
`model-training` d'abord.

## Règles du projet (décisions utilisateur, ne pas re-dériver)

- **Aucune piste n'est éliminée tant que le retour en arrière est possible**
  (décision 2026-07-19). Concrètement : ne JAMAIS écraser un checkpoint,
  chaque nouveau run va dans un nouveau dossier `benchmark/models/...`, les
  modèles déployés sont préservés dans `benchmark/models_deployes/`, le
  `.nemo` de base NVIDIA n'est jamais modifié.
- **Métrique CTC** : lire `val_wer_ctc` uniquement. `val_wer` (tête RNNT
  historiquement gelée) = bruit, toujours ignorer.
- **Modèle déployé sur le téléphone** : dossier device
  `models/fastconformer-ctc-mixed-e02` mais contenu réel = **epoch 14** du run
  tajweed-mixed (nom historique conservé volontairement, cf. `HANDOFF.md` §2).
- **RNNT débloqué le 2026-07-19** (NVVM réparé, loss hybride validée sur le
  vrai modèle) — piste ouverte, recette et contraintes dans `ETAT_CTC_NEMO.md`
  §RNNT et `asr.md`. Vision cible discutée : 3 têtes (RNNT native + CTC
  tajweed strict + CTC normalisé tolérant) sur l'encodeur partagé.
- Avant de committer : vérifier le périmètre avec l'utilisateur (app et
  benchmark ont des cycles de vie différents), ne pas tout committer en bloc.

## Spécificités de CETTE machine (Ubuntu, RTX 5080 16 Go)

- **Chemin projet** : `/media/kafai/NouveauNom/Coran Karim` (espace dans le
  nom → attention sentencepiece et scripts shell). L'audio d'entraînement
  volumineux est sur le disque externe : `/run/media/kafai/HDD/Coran Karim/`.
- **Manifests à chemins morts** : les manifests `benchmark/nemo_manifests_mixed/`
  pointent vers `/mnt/ssd5/...` et `/mnt/hdd/...` (autre machine/session).
  Remap : `/mnt/ssd5/Coran Karim/` → `/media/kafai/NouveauNom/Coran Karim/`
  et `/mnt/hdd/Coran Karim/` → `/run/media/kafai/HDD/Coran Karim/`
  (faire des copies corrigées, ne pas modifier les manifests du dépôt).
- **Venv NeMo** : `benchmark/.venv_nemo` (NeMo 2.5.0, torch 2.11 cu128,
  Python 3.14). ⚠️ son binaire `bin/python3.14` est un symlink cassé
  (reparse tag Windows) — lancer via :
  `PYTHONPATH="benchmark/.venv_nemo/lib/python3.14/site-packages" /usr/bin/python3.14 script.py`
- **Loss RNNT** : nécessite en plus
  `CUDA_HOME="$SITE/nvidia/cuda_nvcc"` (libnvvm installée dans le venv le
  2026-07-19, cf. `ETAT_CTC_NEMO.md` pour la recette complète et le patch
  local NeMo associé). Sans cette variable, seul le CTC-only fonctionne —
  comportement d'avant, inchangé.
- `benchmark/.venv` et `.venv_nemotron` sont des venvs **Windows**
  (`Scripts/`, inutilisables ici) ; `.venv_tts` est Linux mais sans NeMo.
