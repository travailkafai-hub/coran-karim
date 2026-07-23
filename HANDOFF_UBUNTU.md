# Passation de contexte — session 2026-07-12 (avant migration Ubuntu)

But de ce fichier : ne **rien perdre** en passant de Windows à Ubuntu. Tout l'état
en cours, les décisions, les chemins, les commandes de reprise. Lis aussi
`.claude/skills/model-training/references/asr.md` (mémoire technique détaillée,
mise à jour cette session) et `benchmark/BENCHMARK_RESULTS.md`.

---

## 0. Ce qui tourne EN CE MOMENT (à surveiller au passage Ubuntu)

- **Training tajweed FastConformer CTC** en cours sur le GPU Windows (`.venv`).
  - Sortie : `benchmark/models/fastconformer-quran-tajweed/`
  - Log : `benchmark/logs/tajweed_train.log`
  - État au moment de la passation : **epoch 1, val_wer_ctc ≈ 0.19 et en baisse**
    (0.999 → 0.747 → 0.353 → 0.250 → 0.191). Trajectoire saine.
  - **Si tu bascules Ubuntu maintenant, ce run Windows s'arrête.** Deux choix :
    (a) le laisser finir sous Windows d'abord, (b) reprendre sous Ubuntu depuis
    `last.ckpt` (voir §2), (c) relancer propre sous Ubuntu (recette identique,
    voir §2). Recommandé : laisser finir au moins l'epoch en cours pour avoir un
    checkpoint mûr, puis migrer.

---

## 1. Le gros acquis de la session : dataset 100% Hafs vérifié + tokenizer tajweed

### 1.1 Pureté riwaya (Hafs pur, sans Warsh)
- **Problème trouvé** : ~86k clips **Warsh** étaient mélangés au Hafs dans
  `manifest_unified.jsonl` (21%), contaminant tous les trainings précédents.
- **Manifest propre** : `benchmark/data/manifest_hafs_only.jsonl` = **307 059 clips
  Hafs vérifiés** (257 646 EveryAyah certains + ~49 400 assajda vérifiés un par un
  sur assabile.com + test audio).
- Script : `benchmark/build_hafs_only_manifest.py` (liste d'exclusion Warsh + 2
  mal-tagués : HassanSaleh, AbdulRashidSufi).
- Méthode de vérif audio (réutilisable) documentée dans `asr.md` : transcrire un
  verset discriminant (3:146 qātala/qutila, 57:24 présence de "howa") avec
  `jonatasgrosman/wav2vec2-large-xlsr-53-arabic`.

### 1.2 Normalisation tajweed-préservante
- Script : `benchmark/prepare_nemo_tajweed.py`
- **Ne retire QUE ۞ (rub-el-hizb)**. Garde TOUT le reste : wasla ٱ, dagger alif ٰ,
  maddah ٓ, tatweel ـ, sajda ۩, les 7 marques de waqf, marques rares. (Décision
  utilisateur, vérifiée char par char.)
- Sortie : `benchmark/nemo_manifests_tajweed/{train,val}_manifest.jsonl`
  (284 823 train + 14 991 val, 1251h) + `corpus_text.txt` (pour le tokenizer).

### 1.3 Nouveau tokenizer tajweed
- Script : `benchmark/build_tajweed_tokenizer.py` (⚠️ le chemin avec espaces
  "Coran Karim" casse sentencepiece → passer par un dossier temp sans espace ;
  sous Ubuntu, mets le projet dans un chemin SANS espace et ce piège disparaît).
- Tokenizer : `benchmark/tokenizers/tajweed_bpe_v1/` (BPE 1024, character_coverage=1.0).
- Vérifié : **0 caractère non représentable, roundtrip parfait** sur texte tajweed.

---

## 2. REPRENDRE / RELANCER le training tajweed sous Ubuntu

### 2.1 Le principe
- Base : encodeur **NVIDIA pré-entraîné** `stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo`
  (rel_pos, ne PAS changer, cf. §7). Seule la tête CTC est réinitialisée via
  `change_vocabulary` vers le tokenizer tajweed.
- Script : `benchmark/finetune_fastconformer.py` (option `--tokenizer_dir` ajoutée
  cette session ; monitor corrigé sur `val_wer_ctc` au lieu de `val_wer`).
- Mode CTC-only (RNNT gelé via `_ZeroRNNTLoss`) — **sous Ubuntu, le blocage NVVM
  disparaît potentiellement** (warprnnt_numba peut charger sous Linux) → tu
  pourrais entraîner le hybride RNNT+CTC complet. Mais pour reprendre CE run,
  rester CTC-only (cohérence).

### 2.2 ⚠️ Piège des chemins audio (Windows → Linux)
Les manifests `nemo_manifests_tajweed/*.jsonl` ont des chemins **absolus Windows**
(`D:/Coran Karim/benchmark/data/train_wav/...`). Ils **ne marcheront pas** sous
Ubuntu. Dans `manifest_hafs_only.jsonl` : 257 646 chemins relatifs (`data/...`, OK)
mais 49 413 chemins absolus Windows (assajda, à corriger).
→ **Sous Ubuntu : régénérer les manifests** en relançant `prepare_nemo_tajweed.py`
APRÈS avoir corrigé les chemins absolus dans `manifest_hafs_only.jsonl` (remplacer
le préfixe `D:/Coran Karim/benchmark/` par le chemin Ubuntu, ou rendre relatif).

### 2.3 À copier sur la machine Ubuntu
- Tout l'audio : `benchmark/data/train_wav/` (les WAV 16kHz) — **le plus gros**.
- `benchmark/data/manifest_hafs_only.jsonl` (après correction des chemins).
- Le base .nemo : `benchmark/.hf/nemo_models/stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo`
- Le tokenizer : `benchmark/tokenizers/tajweed_bpe_v1/`
- (Si reprise depuis checkpoint) `benchmark/models/fastconformer-quran-tajweed/last.ckpt` (~1,4 Go)
- Les scripts : `finetune_fastconformer.py`, `prepare_nemo_tajweed.py`.

### 2.4 Commande de LANCEMENT PROPRE (recommandé sous Ubuntu — repart de la base pcd)
```bash
# venv Linux avec nemo_toolkit installé (cf. §6)
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
python finetune_fastconformer.py \
  --tokenizer_dir tokenizers/tajweed_bpe_v1 \
  --train_manifest nemo_manifests_tajweed/train_manifest.jsonl \
  --val_manifest   nemo_manifests_tajweed/val_manifest.jsonl \
  --ckpt_dir       models/fastconformer-quran-tajweed \
  --num_workers 8 --batch_size 8 --epochs 10 --lr 1e-4
```
(Sous Linux, `--num_workers 8` OK — contrairement à Windows qui exige 0.)
Sous Windows il fallait aussi `PYTHONUTF8=1` pour éviter un crash de log arabe.

### 2.5 Commande de REPRISE depuis checkpoint (si tu veux garder l'acquis du run Windows)
```bash
python finetune_fastconformer.py \
  --resume models/fastconformer-quran-tajweed/last.ckpt \
  --tokenizer_dir tokenizers/tajweed_bpe_v1 \
  --train_manifest nemo_manifests_tajweed/train_manifest.jsonl \
  --val_manifest   nemo_manifests_tajweed/val_manifest.jsonl \
  --ckpt_dir       models/fastconformer-quran-tajweed \
  --num_workers 8 --batch_size 8 --epochs 10
```
⚠️ La reprise cross-OS charge les poids+optimiseur ; le dataloader NeMo n'est pas
resumable (fast-forward). Vu qu'on n'est qu'à ~1 epoch, un **relancement propre**
(2.4) est probablement plus simple qu'une reprise cross-OS.

### 2.6 Métrique à lire
`val_wer_ctc` dans `models/fastconformer-quran-tajweed/finetune-quran/version_*/metrics.csv`.
**JAMAIS `val_wer`** (tête RNNT gelée = bruit, affiche 40/70/79). Les noms de
checkpoints `val_wer=40.x` sont donc trompeurs (bug de nommage corrigé pour les
futurs runs → utilisera `val_wer_ctc`).

---

## 3. Feature "explication par tap" (mot/verset) — DÉPLOYÉE, avec un piège

### 3.1 Données (générées, cascade offline)
- Scripts : `benchmark/build_explanation_cascade.py`,
  `benchmark/build_explanation_offset_index.py`, `benchmark/build_word_root_index.py`.
- Fichiers : `benchmark/data/quran_sciences/` : `ayah_explanations.jsonl` (128 Mo) +
  `.offsets.json`, `word_explanations.jsonl` (177 Mo) + `.offsets.json`,
  `word_root_index.jsonl`. Palier 3 (érudit) séparé dans `tier3/` (à héberger en
  ligne, pas embarqué).
- 3 langues : AR (paliers 1/2/3), FR (1/2 seulement), EN (1/2/3).

### 3.2 App
- `app/lib/services/quran_sciences_service.dart` (lookup offset direct),
  `app/lib/widgets/coach_explanation_sheet.dart` (UI cascade + langue + Approfondir),
  `app/lib/models/cascade_explanation.dart`.
- **Lecture vocale TTS ajoutée cette session** :
  `app/lib/services/explanation_tts_service.dart` (voix = langue, texte nettoyé
  par `cleanForTts` : retire citations arabes en fr/en, notes, refs), bouton dans
  la feuille. Dépendance `flutter_tts` + query TTS dans AndroidManifest.

### 3.3 ⚠️ PIÈGE MAJEUR : `flutter install` efface les données déployées
Désinstaller/réinstaller l'app **efface son dossier privé** → les 5 fichiers
`quran_sciences/` disparaissent → l'app retombe sur Gemma ("aucune explication").
**Après CHAQUE build/install de l'app, relancer :**
```bash
bash benchmark/deploy_quran_sciences.sh
```
(À terme : faire télécharger ces fichiers par l'app elle-même au 1er lancement,
comme les modèles ASR — chantier non fait.)

---

## 4. Gemma 4 E2B — tuteur (pilier B) — CONTEXTE COMPLET

Réf. détaillée : `.claude/skills/model-training/references/gemma-llm.md` +
`QAT_TRAINING_PLAN.md`. Résumé opérationnel autoportant ci-dessous.

### 4.1 Modèle & environnement
- Modèle de base local : `benchmark/models/gemma-4-E2B-it` (Gemma 4 E2B, bf16).
- **Venv obligatoire : `benchmark/.venv_nemotron`** — le SEUL qui a
  `AutoModelForMultimodalLM` (transformers 5.13.dev). Le `.venv` principal
  (transformers 4.57) ne connaît PAS cette classe → Gemma 4 ne s'y charge pas.
  bitsandbytes + trl y ont été installés cette session (pour le QAT).
- Gemma 4 E2B est **multimodal** (texte+vision+audio) → toujours le charger avec
  `AutoModelForMultimodalLM`, pas `AutoModelForCausalLM`.

### 4.2 ⚠️ LE BUG LoRA à ne JAMAIS refaire (regex des target_modules)
Gemma 4 : les `q_proj/k_proj/.../down_proj` du `language_model` sont des
`nn.Linear` **directs, SANS suffixe `.linear`**. Seuls `vision_tower` (112) et
`audio_tower` (36) ont un wrapper `.linear`. Donc :
- ❌ `target_modules=r".*\.linear$"` → attache le LoRA UNIQUEMENT aux branches
  vision/audio (jamais traversées en entraînement texte-seul) → `lora_B` reste
  **exactement zéro** → adaptateur no-op total, indétectable au forward. **Ça a
  invalidé plusieurs runs (v2 4-epoch inclus).**
- ✅ Bon regex :
  ```python
  target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$"
  ```
- **Vérif fiable** (à faire après tout changement de regex — `print_trainable_parameters()`
  seul NE SUFFIT PAS, il affiche un % non-nul même avec le mauvais regex) :
  ```python
  print({n.split('.')[1] for n,m in model.named_modules() if pattern.match(n)})  # doit contenir 'language_model'
  ```
  Et après un court training : vérifier qu'au moins quelques `lora_B` ont
  `abs().max() > 0` (sinon le LoRA n'a touché aucune couche réellement utilisée).

### 4.3 Dataset tafsir (enrichi cette session)
- Fichier : `benchmark/data/gemma_islamic_sft_v2.jsonl` = **51 604 exemples,
  100% tafsir** (hadith retiré), équilibré **AR 52% / FR 24% / EN 24%**.
- Sources : 15 tafsirs AR (Ibn Kathir, Tabari, Qurtubi, Jalalayn, Baghawi, Saadi,
  Muyassar, Kashshaf, Ibn Ashur, Razi, Alusi, Bahr al-Muhit, Baydawi, Shawkani,
  Durr al-Manthur) + 6 EN + 4 FR + Mufradat (ar-Raghib) + Nuzhat al-A'yun (Ibn
  al-Jawzi, wujuh wal-naza'ir) + chapitres wujuh d'Itqan/Burhan.
- Principe : chaque `target` **CITE sa source exacte** (le modèle apprend à
  attribuer, jamais à inventer). Format `{system, user, target}`.
- Générateur : `benchmark/gemma_make_islamic_sft.py` (les nouvelles sources sont
  dans `TAFSIR_META` ET dans les listes de rotation `ar_slugs/fr_slugs/en_slugs`).
- Données brutes tafsir : `benchmark/data/tafsir/*.jsonl` (via API spa5k +
  turath.io ; scripts `dl_tafsir_*.py`, `dl_turath_ulum_quran.py`, `dl_wujuh_entries.py`).

### 4.4 Training LoRA standard (PTQ — déjà fait, v6)
- Script : `benchmark/gemma_finetune_tutor.py` (r=16, alpha=32).
- Checkpoints tous les 200 steps + état complet (`training_state.pt`) → reprise
  via `GEMMA_RESUME=1`. Env `GEMMA_SFT` / `GEMMA_OUT` pour surcharger dataset/sortie.
- Masquage du prompt (labels `-100`), troncature qui **préserve la citation
  finale** (bug déjà corrigé : tronquer aveuglément coupait la source).
- **v6 déjà entraîné (r16 corrigé), fusionné, exporté `.litertlm`, déployé,
  sanity check OK** (génère une réponse sourcée cohérente).

### 4.5 Export `.litertlm` (déployé on-device via LiteRT-LM)
Commande qui marche (ne rien changer) :
```bash
litert-torch export_hf <merged_dir> <out_dir> \
  --task=text_generation \
  --quantization_recipe=dynamic_wi4_afp32 \
  --bundle_litert_lm=True --externalize_embedder=True \
  --jinja_chat_template_override=litert-community/gemma-4-E2B-it-litert-lm
```
⚠️ `--jinja_chat_template_override` **obligatoire** : sans lui, l'export prend le
template du LoRA qui contient des `map.get()` non supportés par LiteRT-LM →
`Failed to start streaming (code: 13)`.
- Fusion : recharger la base fp16 **fraîche** (pas la copie 4-bit), appliquer le
  LoRA, `merge_and_unload()` (cf. `merge_tutor_lora_v6.py`).
- App : `app/lib/services/tutor_llm_service.dart` (LiteRT-LM). Palliatif
  `_truncateToFirstParagraph` contre la dégénérescence en répétition.

### 4.6 QAT (Quantization-Aware Training) — LE chantier pour Ubuntu/WSL
- **Pourquoi** : v6 (fine-tuné bf16 pleine précision PUIS quantifié INT4)
  **dégénère en répétition après 1-3 phrases sur l'appareil** (le LoRA appris en
  pleine précision ne "survit" pas à l'arrondi INT4). Le QAT charge le modèle en
  4-bit (bitsandbytes NF4) **pendant** l'entraînement → l'adaptateur apprend à
  compenser le bruit de quantification.
- Scripts prêts : `benchmark/gemma_finetune_tutor_qat.py` (r=**128**, alpha=256,
  `BitsAndBytesConfig(load_in_4bit, nf4, compute_dtype=float16, double_quant=False)`
  + `prepare_model_for_kbit_training`) + `benchmark/validate_qat_setup.py`
  (à relancer AVANT tout run : vérifie 205 modules matchés dans `language_model`,
  193M params entraînables — pas de repli vision/audio).
- **Pourquoi Ubuntu** : sous Windows, bitsandbytes 4-bit + LoRA gros rang provoque
  une **fragmentation VRAM** (GPU 100% util mais 2% bande passante, ~88W/360W) —
  `expandable_segments` non supporté sur ce Windows. **Confirmé par l'utilisateur :
  ce problème n'existe PAS sous Ubuntu.** Donc le QAT DOIT tourner sous WSL/Linux.
- Référence qui a marché (autre projet) : `E:\RECUP_EMTEC\Projet Harcelement\detox\
  finetune\finetune_qat.py` + `merge_qat.py` + `eval_int4_sim.py` (Gemma 3 1B,
  bons résultats réels). Mêmes bnb_config et logique de fusion.
- Setup venv QAT sous Linux : `pip install torch transformers peft trl bitsandbytes
  accelerate datasets truststore` (torch requis même si non utilisé directement).
- Après QAT : fusionner (base fp16 fraîche + LoRA QAT), exporter `.litertlm`
  (même commande §4.5), valider avec `sanity_check_tutor_v6.py`, comparer la
  dégénérescence (devrait être nettement réduite).
- Repli si QAT échoue : INT8 (`dynamic_wi8_afp32`, ~5 Go) sur le LoRA v6 existant,
  OU garder la troncature côté app.

### 4.7 À copier sur Ubuntu pour Gemma
- `benchmark/models/gemma-4-E2B-it` (base, ~10 Go bf16).
- `benchmark/data/gemma_islamic_sft_v2.jsonl` (dataset).
- Scripts : `gemma_finetune_tutor_qat.py`, `gemma_finetune_tutor.py`,
  `validate_qat_setup.py`, `gemma_make_islamic_sft.py`.
- (Le LoRA v6 déjà entraîné si tu veux le garder : `benchmark/models/gemma-4-E2B-tutor-lora`.)

---

## 5. Décisions PARQUÉES (ne pas re-dériver — déjà tranchées)

1. **abs_pos vs rel_pos** : GARDER rel_pos. Basculer abs_pos = jeter le
   pré-entraînement de l'attention (chantier de ré-entraînement dédié, sans
   garantie qualité). Ubuntu ne débloque PAS le crash rel_pos d'ONNX Runtime
   Training (indépendant de l'OS). Détail complet dans `asr.md`.
2. **Entraînement 100% on-device (ONNX Runtime Training)** : non viable en l'état
   (crash gradient-builder sur attention rel_pos). Rester sur mini-LoRA v1
   PC-assisté. `onnxruntime-training-android:1.19.2` = drop-in validé si on
   retente. `onnxruntime-training` Python = Linux/cp38-cp311 uniquement (→ WSL).
3. **Idée "2 têtes CTC" pour le toggle tajweed** (NON implémentée, à creuser si
   voulu) : un encodeur partagé + 2 têtes CTC — une entraînée avec tajweed (mode
   strict), une sur texte normalisé (mode relâché) — pour que l'app bascule
   strict/relâché sans 2 modèles complets. Répond au besoin "désactiver la
   sensibilité tajweed dans l'app". Pas encore proposé formellement/chiffré.
4. **Warsh (phase 2)** : possibilité de proposer les 2 riwayat dans l'app. Chantier
   séparé : texte Warsh différent (API QuranHub `quran-warsh`), numérotation des
   versets décalée, ré-alignement forcé des clips Warsh nécessaire. Données audio
   Warsh repérées (EveryAyah 3 récitateurs + assabile). Pas commencé.
5. **LM coranique au décodage** (KenLM n-gram) : piste faible effort pour améliorer
   le décodage CTC, pas commencée (cf. BENCHMARK_RESULTS.md).

---

## 6. Environnements / venvs / outils

- `benchmark/.venv` : **NeMo 2.7.3** + torch cu128 + sentencepiece. C'est LUI qui
  entraîne le FastConformer. (Sous Ubuntu : recréer un venv équivalent avec
  `nemo_toolkit[asr]`, torch CUDA, sentencepiece.)
- `benchmark/.venv_nemotron` : transformers 5.13.dev (a `AutoModelForMultimodalLM`
  pour Gemma 4) + bitsandbytes + trl. Pour le Gemma tuteur / QAT.
- `benchmark/.venv_linux` : (existe déjà, à vérifier son contenu sous Ubuntu).
- Flutter : `C:\Users\Adam\flutter\bin\flutter.bat` (Windows) → sous Ubuntu,
  réinstaller Flutter SDK.
- ADB : `C:\Users\Adam\AppData\Local\Android\Sdk\platform-tools\adb.exe`,
  device `R3CY20XW7TD` (SM S931B). ⚠️ En Git Bash, `export MSYS_NO_PATHCONV=1`
  avant les `adb shell`/`push` avec chemins `/data/...` (sinon chemins mutilés).
- Package app : `com.corankarim.coran_karim`.

---

## 7. Rappels architecture (pourquoi les choix)

- FastConformer = **hybride 2 têtes** : RNNT (gelée dans nos runs) + CTC (entraînée).
  Ce sont les "2 têtes" natives — pas une conception à nous.
- Encodeur = NVIDIA pcd pré-entraîné, `self_attention_model: rel_pos`, d_model 512,
  8 heads. On ne le réinitialise PAS (c'est ce qui donne val_wer_ctc 0.25 dès
  l'epoch 0 : l'encodeur sait déjà entendre l'arabe).
- 3 piliers, 3 technos : Récitation = FastConformer CTC (ce training) / Whisper ;
  Tuteur = Gemma 4 E2B LoRA ; Révision = FSRS.

---

## 8. Fichiers CRÉÉS/MODIFIÉS cette session (récap)

Scripts benchmark (créés) : `build_hafs_only_manifest.py`, `prepare_nemo_tajweed.py`,
`build_tajweed_tokenizer.py`, `dl_tafsir_linguistic.py`, `dl_turath_ulum_quran.py`,
`dl_wujuh_entries.py`, `dl_tafsir_major_classics.py`, `dl_tafsir_english.py`,
`build_explanation_cascade.py`, `build_word_root_index.py`,
`gemma_finetune_tutor_qat.py`, `validate_qat_setup.py`, `deploy_quran_sciences.sh`.
Modifiés : `finetune_fastconformer.py` (--tokenizer_dir, change_vocabulary,
monitor val_wer_ctc), `gemma_make_islamic_sft.py`.

App (créés) : `explanation_tts_service.dart`. Modifiés : `coach_explanation_sheet.dart`,
`pubspec.yaml` (flutter_tts), `AndroidManifest.xml` (query TTS).

Docs (créés) : `QAT_TRAINING_PLAN.md`, `WORD_AYAH_EXPLANATION_PLAN.md`, ce fichier.
Skill mis à jour : `.claude/skills/model-training/references/asr.md` (contamination
riwaya, méthode vérif audio, abs_pos écarté), `gemma-llm.md`.

Données générées : `manifest_hafs_only.jsonl`, `nemo_manifests_tajweed/`,
`tokenizers/tajweed_bpe_v1/`, `data/quran_sciences/*` (cascade + offsets),
`data/tafsir/*` (10 nouvelles sources), `gemma_islamic_sft_v2.jsonl`.
