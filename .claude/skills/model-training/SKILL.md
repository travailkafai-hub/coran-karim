---
name: model-training
description: Entraîner, relancer, diagnostiquer ou exporter N'IMPORTE QUEL modèle de ce projet — aussi bien les modèles ASR (Whisper HuggingFace, NeMo FastConformer) pour la récitation coranique que le LoRA Gemma 4 E2B pour le tuteur textuel islamique. Utilise ce skill dès que la demande touche à l'entraînement/fine-tuning d'un modèle, à la relance d'un training existant sur un nouveau dataset, à un crash ou ralentissement pendant l'entraînement, à la construction ou l'enrichissement d'un dataset (audio ASR OU SFT islamique tafsir/hadith/lexique), au calcul de la progression/temps restant d'un run, ou à l'export d'un modèle vers l'app Android (GGML/whisper.cpp, ONNX, adaptateur LoRA). S'applique même si l'utilisateur ne nomme pas explicitement "Whisper", "NeMo" ou "Gemma" — par exemple "relance le training", "pourquoi ça a planté", "exporte ce modèle pour le téléphone", "relance sur tous les récitateurs", "où en est l'entraînement", "ajoute une source au dataset du tuteur", "combien de temps il reste".
---

# Entraînement de modèles — Coran Karim

Ce projet entraîne plusieurs modèles très différents (ASR audio, LLM texte, et potentiellement d'autres à l'avenir — cf. "3 piliers, 3 technos" dans `ARCHITECTURE.md`). Ce skill capture ce qui est commun à tout entraînement dans ce projet ; les détails spécifiques à chaque techno sont dans `references/`.

**Avant d'agir**, lis `benchmark/BENCHMARK_RESULTS.md` (mémoire vive des résultats déjà obtenus) et charge le fichier de référence pertinent :
- Question ASR (Whisper, NeMo FastConformer, récitation, export mobile audio) → lis `references/asr.md`.
- Question Gemma/LLM tuteur (LoRA, dataset islamique tafsir/hadith/lexique, SFT) → lis `references/gemma-llm.md`.
- Question transverse (checkpoint, environnement, statut d'un run) → tout est ci-dessous, pas besoin d'aller plus loin.

## Documentation d'entraînement — l'index complet (mis à jour 2026-07-25)

Ces documents contiennent l'essentiel de la mémoire d'entraînement. **Les lire
avant d'agir sur le sujet correspondant** — plusieurs journées ont été perdues à
re-dériver ce qui y était déjà écrit.

| Document | Ce qu'il contient |
|---|---|
| `ETAT_CTC_NEMO.md` | Inventaire des runs NeMo, WER, déploiement, **reste à faire** (dont le fine-tune streaming jamais lancé) |
| `PLAN_ENTRAINEMENT_HYBRIDE.md` | Stratégie du run 3 têtes (RNNT + CTC strict/tolérant), §5quater sur la calibration GOP |
| `benchmark/BENCHMARK_RESULTS.md` | Historique chiffré de tous les benchmarks et décisions |
| `QAT_TRAINING_PLAN.md` | Plan de réentraînement QAT du Coach IA (Gemma) — **absent de l'index CLAUDE.md** |
| `HANDOFF_UBUNTU_TRAINING.md` | Training tajweed + pistes explorées — **absent de l'index CLAUDE.md** |
| `REVUE_ARCHITECTURE_KARAOKE.md` | Revue d'architecture du karaoké temps réel — **absent de l'index CLAUDE.md** |
| `PROBLEMATIQUES_ASR.md` | Problématiques ASR (buffer, GOP, pauses) + état de l'art externe |
| `GLOSSAIRE_TECHNIQUES_ASR.md` | Quelle technique sert à quoi (entraînement vs décodage) |
| `JOURNAL_TESTS_LOGS.md` | Mesures device horodatées — indispensable avant toute hypothèse |
| `ARCHITECTURE_RECITATION.md` | Chaîne audio → jugement, limites structurelles |

⚠️ **Avant toute analyse : `git branch -a` et `git log` des branches sœurs.**
Le dépôt porte plusieurs branches de moteur (`test-1-gop`, `test-2-gop`,
`asr-nemo-solutions`) qui diffèrent de centaines de lignes sur la chaîne ASR.
Le 2026-07-25, une journée a été passée à re-dériver un mécanisme (recouvrement
de segment sur mots entiers) **déjà implémenté dans `test-2-gop` depuis le 23**.

## Environnement — CETTE machine est Ubuntu, pas Windows (corrigé 2026-07-25)

⚠️ La version précédente de ce fichier décrivait un environnement **Windows**
(`benchmark/.venv/Scripts/python.exe`). C'est faux sur cette machine et un agent
qui suit ces instructions échoue : `benchmark/.venv` et `.venv_nemotron` **sont**
des venvs Windows (`Scripts/`), inutilisables ici.

**Venv NeMo à utiliser** (NeMo 2.5.0, torch 2.11 cu128, Python 3.14) — son
binaire `bin/python3.14` est un symlink cassé (reparse tag Windows), donc on
appelle l'interpréteur système avec le `PYTHONPATH` du venv :

```bash
SITE="benchmark/.venv_nemo/lib/python3.14/site-packages"
PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 benchmark/mon_script.py
```

**Loss RNNT** : ajouter `CUDA_HOME="$SITE/nvidia/cuda_nvcc"` (libnvvm installée
dans le venv le 2026-07-19). Sans ça, seul le CTC-only fonctionne.

**Chemins** : projet sur `/media/kafai/NouveauNom/Coran Karim` (espace dans le
nom → attention sentencepiece et scripts shell) ; audio volumineux sur
`/run/media/kafai/HDD/Coran Karim/`. Les deux disques sont en NTFS : pas de
permissions POSIX fiables (`rsync --no-perms --no-owner --no-group`), et les
caractères `: ? * < > | "` sont interdits dans les noms de fichiers.

**Manifests à chemins morts** : `benchmark/nemo_manifests_mixed/` pointe vers
`/mnt/ssd5/...` et `/mnt/hdd/...` (autre machine). Remap :
`/mnt/ssd5/Coran Karim/` → `/media/kafai/NouveauNom/Coran Karim/`,
`/mnt/hdd/Coran Karim/` → `/run/media/kafai/HDD/Coran Karim/`. Faire des copies
corrigées, ne pas modifier les manifests du dépôt.

**Piège protobuf/TensorFlow** (valable partout) : toujours en tête de script,
avant tout autre import :
```python
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
```

**Runs archivés** : 20 runs terminés ont été DÉPLACÉS sur le HDD en conservant
le chemin relatif. Un dossier absent de `benchmark/models/` n'est PAS une preuve
que le run n'existe plus — vérifier le HDD avant de conclure ou de relancer.

## Discipline de checkpoint — vérifier AVANT de lancer, pas après un crash

Un run de plusieurs heures sur ce setup (Windows, un seul GPU, aucune supervision externe type cluster/orchestrateur) n'a **aucun filet de sécurité** en dehors de ce que le script sauvegarde lui-même. Leçon coûteuse (2026-07-05) : `gemma_finetune_tutor.py` ne sauvegardait le modèle **qu'une seule fois**, après la boucle complète (2 epochs, ~12h) — un crash à 90% aurait tout reperdu, y compris pour un simple redémarrage Windows involontaire. Fixé en ajoutant une sauvegarde périodique toutes les N steps optimiseur (voir `references/gemma-llm.md` pour le pattern exact) ; le même principe s'applique aux scripts ASR (NeMo a `ModelCheckpoint(every_n_train_steps=...)` intégré — juste vérifier l'intervalle n'est pas déraisonnablement grand, cf. `references/asr.md`).

**Avant de lancer tout nouveau training ou variante d'un script existant, vérifie explicitement qu'un checkpoint intermédiaire est prévu** — ne suppose pas que c'est le cas juste parce que le script tourne "normalement". Le coût d'ajouter une sauvegarde périodique est quasi nul (un adaptateur LoRA fait quelques Mo ; même un modèle complet ne coûte qu'un peu de temps disque) comparé au risque de reperdre des heures de calcul GPU.

## Contrôle qualité du dataset — avant l'entraînement, pas après

Quand un dataset est construit par extraction automatisée depuis une source semi-structurée (texte scrapé, HTML, PDF...), la manière de découper "quel texte appartient à quelle entrée/étiquette" est le point le plus facile à rater silencieusement. Leçon concrète (2026-07-05, construction du dataset SFT islamique) : découper les entrées d'un dictionnaire arabe en cherchant le mot-titre comme sous-chaîne dans le texte semblait marcher, mais un mot court réapparaît presque toujours ailleurs par coïncidence (note de bas de page citant un autre ouvrage, mot plus long qui le contient) — le contenu attribué au mauvais mot ne plante rien, le modèle apprend juste une fausse association, silencieusement.

**Principe général, applicable à n'importe quel modèle/dataset de ce projet** : quand l'exactitude de "quel contenu va avec quelle étiquette" compte pour ce que le modèle va apprendre, ancre le découpage sur une frontière **structurelle** de la source (balises HTML, positions d'offsets connues, colonnes d'un fichier structuré...) plutôt que sur une correspondance de contenu/heuristique (recherche de sous-chaîne, correspondance floue). Et quel que soit le soin apporté à l'extraction, **vérifie manuellement un échantillon contre une vérité connue indépendamment** avant de considérer le dataset prêt pour l'entraînement — c'est ce contrôle manuel, pas la relecture du code, qui révèle ce genre de bug. Détails et code exact dans `references/gemma-llm.md`.

## Statut d'un run en cours

Pour savoir où en est un training déjà lancé (pourcentage, temps restant), le plus fiable est de lire le fichier de log directement (`logs/*.log` — chercher le plus récemment modifié si le nom exact n'est pas connu) plutôt que d'interroger les process système. Attention à la définition exacte du compteur de steps affiché par le script (cumulé sur toutes les epochs, ou remis à zéro à chaque epoch ?) avant de calculer un pourcentage ou une estimation de temps restant — vérifier dans le code du script plutôt que supposer, une erreur d'interprétation ici change l'estimation d'un facteur proche du nombre d'epochs (constaté : ~19h estimées à tort au lieu de ~8,6h réelles). Voir `references/gemma-llm.md` pour l'exemple concret sur Gemma.
