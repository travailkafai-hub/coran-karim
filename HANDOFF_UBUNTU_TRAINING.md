# Handoff — training tajweed + pistes explorées (session Windows, 2026-07-12)

Document rédigé pour permettre à l'agent qui reprend sur Ubuntu de continuer sans redécouvrir ce qui a déjà été fait/tranché aujourd'hui. Voir aussi `.claude/skills/model-training/references/asr.md` (mémoire de référence du projet, mise à jour en continu par les deux côtés) — ce document-ci est un résumé de contexte ciblé, pas un remplacement.

## 1. Training tajweed en cours (au moment du basculement)

Commande exacte (à relancer/reprendre côté Ubuntu avec `--resume`) :
```bash
python finetune_fastconformer.py \
  --tokenizer_dir tokenizers/tajweed_bpe_v1 \
  --train_manifest nemo_manifests_tajweed/train_manifest.jsonl \
  --val_manifest nemo_manifests_tajweed/val_manifest.jsonl \
  --ckpt_dir models/fastconformer-quran-tajweed \
  --num_workers 0 --batch_size 8 --epochs 10 --lr 1e-4
```

**Statut au moment de la rédaction** : step ~10199 (epoch 1 en cours), `val_wer_ctc` en nette amélioration :
- step 1958 → 0.999 (bruit initial, tête CTC réinitialisée pour le nouveau vocabulaire tajweed)
- step 3917 → 0.747
- step 5876 → 0.353
- step 7834 → 0.250 (fin epoch 0)
- step 9794 → 0.191

Trajectoire saine. **Rappel piège classique (déjà documenté dans asr.md)** : `val_wer` (sans `_ctc`) reste bloqué ~40-79% dans les noms de checkpoints (`fastconformer-quran-epoch=00-val_wer=40.463.ckpt` etc.) — c'est la métrique RNNT gelée, **toujours ignorer**, seule `val_wer_ctc` dans `metrics.csv` compte.

**Point important corrigé pendant cette session** : l'encodeur de ce run **n'est PAS entraîné from-scratch** — il charge l'encodeur pré-entraîné NVIDIA (`stt_ar_fastconformer_hybrid_large_pcd_v1.0`, attention à position relative rel_pos) et seule la tête CTC est réinitialisée pour le nouveau vocabulaire tajweed (via `change_vocabulary` ou équivalent). C'est pour ça que le run converge aussi vite (0.999→0.191 en ~10k steps) — un vrai from-scratch serait beaucoup plus lent à démarrer. Ne pas re-tenir la fausse prémisse inverse (elle a circulé un temps dans cette session avant d'être corrigée).

## 2. Contamination riwaya Warsh/Hafs (découverte 2026-07-12, déjà fixée)

**~85 905 clips Warsh (21% du dataset) étaient mélangés au Hafs sans distinction** dans tous les trainings CTC précédents, y compris le run "augmenté" (val_wer_ctc ~1,1%, actuellement déployé sur le téléphone). Fix appliqué : `build_hafs_only_manifest.py` → `data/manifest_hafs_only.jsonl` (307 059 clips Hafs vérifiés, 75,4% du dataset original). Détails complets (méthode de vérification par verset discriminant 3:146/57:24, réciteurs mal-tagués trouvés, etc.) dans `asr.md` section "Contamination riwaya".

**Le run tajweed en cours utilise-t-il déjà ce manifest Hafs-only ?** À VÉRIFIER côté Ubuntu — la commande ci-dessus pointe sur `nemo_manifests_tajweed/`, dont la provenance exacte (Hafs-only ou pas encore filtré) n'a pas été confirmée dans cette session. Si le manifest tajweed n'a pas encore intégré le filtre Hafs-only, c'est un point à corriger avant d'aller plus loin (sinon le training tajweed hérite de la même contamination Warsh que les runs précédents).

## 3. Investigation "entraînement 100% embarqué" (ONNX Runtime Training) — ÉCHEC, ne pas re-dériver à l'aveugle

Contexte : demande utilisateur de personnalisation vocale (mini-LoRA) qui n'envoie AUCUNE donnée hors du téléphone (contrairement au v1 PC-assisté déjà implémenté, cf. section 4).

**Ce qui a été testé, dans l'ordre** :
1. Bascule `onnxruntime-android` → `onnxruntime-training-android:1.19.2` (1.20.0 n'existe pas pour cette variante) côté app Android — **fonctionne**, build + lancement OK sur device réel, même API Java `ai.onnxruntime.*`, aucun code Kotlin à changer. Drop-in valide si on veut reprendre.
2. Génération d'artefacts d'entraînement (`onnxruntime.training.artifacts.generate_artifacts`, côté PC) : le paquet Python `onnxruntime-training` **n'a aucun wheel Windows sur PyPI** — Linux x86_64 uniquement, et seulement cp38 à cp311 (**pas cp312**). Contournement utilisé : WSL Ubuntu-24.04 + Python 3.11 standalone (`python-build-standalone`, installé sans sudo dans `~/`) + `pip install onnxruntime-training onnx torch` (torch requis car `onnxruntime.training.__init__` importe `onnxruntime.training.optim` qui en dépend, même si cette partie n'est pas utilisée).
3. `ConformerEncoder` (classe par défaut utilisée par `EncDecHybridRNNTCTCBPEModel`) n'implémente PAS `AdapterModuleMixin` — nécessite d'échanger la classe de l'instance : `model.encoder.__class__ = ConformerEncoderAdapter` (sous-classe pure, sans `__init__` propre, l'échange fonctionne sans souci).
4. Adaptateur (`LinearAdapterConfig`) attaché à l'encodeur, modèle exporté en ONNX, puis `generate_artifacts()` **plante** :
   ```
   RuntimeError: .../gradient_builder_base.h:123 ... GradientBuilderBase::O(size_t, bool) const
   i < node_->OutputDefs().size() was false.
   ```
   Logs verbeux : le générateur de gradient bute sur de nombreux avertissements "symbolic broadcasting/dimension" dans les couches `self_attn` — **attention à position relative (rel_pos)**, spécifique au Conformer, avec des dimensions symboliques dynamiques (`unk__xxx`) que le générateur de graphe de gradient d'ONNX Runtime Training ne sait pas résoudre. **Ce n'est pas un op manquant contournable** (comme l'absence de perte CTC intégrée, qui elle serait contournable par cross-entropy par frame contre les labels de `ForcedAligner.kt` — jamais testé, le blocage attention est survenu avant) — c'est un bug/limite bas niveau de leur implémentation avec ce type précis d'attention.

**Option `abs_pos` (attention absolue) évaluée et ÉCARTÉE** — discutée 3× dans cette session avant d'être clarifiée, pour éviter de la re-dériver :
- Idée : configurer l'encodeur en `self_attention_model: abs_pos` au lieu de `rel_pos` pour éviter les dimensions symboliques dynamiques qui font planter le gradient-builder.
- **Prémisse fausse initialement** : "le run tajweed repart de zéro sur l'encodeur donc basculer abs_pos est gratuit" — FAUX, cf. section 1 (l'encodeur est bien pré-entraîné rel_pos, pas from-scratch).
- `rel_pos` et `abs_pos` sont des modules d'attention différents (poids `pos_bias_u/v` + `RelPositionMultiHeadAttention` vs MHA classique) — **les poids rel_pos pré-entraînés ne se chargent pas dans abs_pos**. Basculer = jeter le pré-entraînement de l'attention + ré-entraîner ces couches en profondeur (conv/feedforward autour restent réutilisables) = chantier dédié séparé, sans garantie de retrouver la qualité rel_pos.
- **Migrer sur Ubuntu/Linux ne débloque PAS ce point** : Linux fournit juste le wheel Python pour *exécuter* `generate_artifacts` (contourne le problème n°2 ci-dessus) ; le crash du gradient-builder sur rel_pos est indépendant de l'OS et se reproduira identiquement sous Ubuntu.
- **Décision actée** : ne pas prioriser l'entraînement embarqué — garder rel_pos (qualité max, modèle principal) + mini-LoRA v1 PC-assisté (section 4). Ne reconsidérer abs_pos que si l'entraînement embarqué devient une priorité forte, en acceptant explicitement le risque qualité + l'effort de ré-entraînement dédié de l'encodeur.

Rollback effectué côté app (`git revert`) — aucune trace de cette tentative dans le code Android actuel, seulement dans `asr.md` et ce document.

## 4. Mini-LoRA v1 (PC-assisté) — implémenté et fonctionnel

Alternative retenue en attendant : capture des clips de récitation vérifiés corrects (sessions de référence uniquement) sur le téléphone, export MANUEL (partage natif Android, zip — aucune sync automatique, donnée vocale sensible), puis entraînement côté PC via `benchmark/finetune_fastconformer_lora.py` :
- Charge le modèle augmenté actuel, attache un adaptateur NeMo `LinearAdapter` sur l'encodeur (base entièrement gelée), fine-tune sur les clips exportés.
- Export ONNX par le pipeline déjà validé (même approche que `export_augmented_checkpoint.py`).
- Fonctionnel mais ne répond pas à l'objectif "rien ne sort du téléphone" — accepté comme compromis pour l'instant.

## 5. Idée "double tête CTC" (tajweed strict / relâché) — pas implémentée, piste évaluée aujourd'hui

Besoin : permettre à l'app de basculer entre un mode "strict tajweed" (le training en cours, section 1) et un mode "relâché" (sans exigence de précision tajweed), sans charger deux modèles complets sur un téléphone à 6 Go RAM.

**Deux options discutées** :
1. **Double tête CTC sur encodeur partagé** (une tête vocabulaire tajweed, une tête vocabulaire normalisé sans marques) : architecturalement propre, coût de stockage négligeable SI exporté comme un seul graphe ONNX multi-sorties (quelques Mo de plus, une tête = juste une couche linéaire 512→vocab) — **mais si exporté naïvement en deux modèles séparés, chacun duplique l'encodeur en entier (~458 Mo × 2) : à éviter absolument**. Avantage clé : la 2e tête peut être ajoutée **après coup**, une fois le modèle tajweed terminé et gelé — entraînement de la 2e tête seule (pas de backward à travers l'encodeur gelé puisque la tête est la toute dernière couche), rapide (minutes/heures, pas de ré-entraînement depuis le début).
2. **Normalisation du texte attendu selon le mode** (RECOMMANDÉ, moins cher) : garder un seul modèle (celui tajweed, qui reconnaît déjà les nuances fines) et normaliser le texte de comparaison différemment selon le mode — retirer les marques tajweed du texte attendu en mode relâché avant de juger, les garder en mode strict. Réutilise le pattern `ArabicNormalizer` déjà existant côté app (plusieurs niveaux de normalisation déjà en place : `normalize`/`normalizeStrict`/`normalizeTraining`). **Zéro coût modèle, zéro entraînement supplémentaire.**
3. Limite de l'option 2 : si le mode relâché doit aussi être plus TOLÉRANT à l'articulation elle-même (pas juste ignorer les marques mais accepter une prononciation moins précise que ce que le modèle tajweed exige), alors la double tête garde un intérêt propre — sinon la normalisation suffit.

**Pas de décision finale prise** — à trancher selon le besoin réel de l'app (juste masquer l'affichage des exigences tajweed, ou vraiment assouplir le jugement acoustique).

## 6. Fichiers clés

- `benchmark/finetune_fastconformer.py` — script de training principal (CTC-only, contournement NVVM documenté dans asr.md).
- `benchmark/finetune_fastconformer_lora.py` — mini-LoRA v1 PC-assisté.
- `benchmark/build_hafs_only_manifest.py`, `benchmark/build_tajweed_tokenizer.py`, `benchmark/prepare_nemo_tajweed.py` — pipeline de préparation tajweed.
- `.claude/skills/model-training/references/asr.md` — mémoire de référence complète (lire en premier avant toute action training, contient bien plus de détails historiques que ce résumé).
- `benchmark/BENCHMARK_RESULTS.md` — historique des résultats (à tenir à jour si de nouveaux chiffres changent une ligne du tableau récapitulatif dans asr.md).

## 7. Pièges Windows→Linux à surveiller en migrant

- `num_workers=0` était requis sous Windows (DataLoader crashe sinon) — à re-tester sous Linux, probablement plus permissif (`num_workers` > 0 devrait fonctionner et accélérer le chargement).
- `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` avait corrigé une fragmentation VRAM progressive sur un run très long (Windows) — à surveiller aussi sous Linux si le ralentissement revient (symptôme : GPU-Util 100% mais power.draw et bande passante mémoire qui chutent).
- Le logger CSV (pas TensorBoard) évitait un conflit protobuf TF/venv sous Windows — probablement plus la même contrainte sous Linux si l'environnement est reconstruit proprement, mais vérifier avant de changer si ce n'est pas nécessaire.
