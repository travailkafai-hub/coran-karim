# ASR (Whisper / NeMo FastConformer) pour récitation coranique

Ce fichier capture le workflow établi dans ce projet pour entraîner, reprendre et déployer des modèles ASR arabes sur le corpus coranique. Avant d'agir, lis `benchmark/BENCHMARK_RESULTS.md` pour le contexte à jour (résultats déjà obtenus, décisions actées) — ce fichier est la mémoire vive du projet et évite de refaire des essais déjà tranchés.

## Dataset

- Manifest unifié : `benchmark/data/manifest_unified.jsonl` — champs `key`, `reciter`, `mp3`, `text`, `wav` (chemin **absolu**). Actuellement 78 récitateurs, ~414k clips (mix EveryAyah/Tarteel `_XXkbps` + batch2 `_assajda`).
- Reconstruction depuis toutes les sources : `benchmark/rebuild_manifest_unified.ps1`.
- Format NeMo (pour FastConformer) : `benchmark/nemo_manifests/{train,val}_manifest.jsonl` (champs `audio_filepath`/`text`/`duration`), généré par `benchmark/prepare_nemo_data.py --manifest data/manifest_unified.jsonl`.
- Avant de lancer un training « sur tous les récitateurs » ou « sur le dataset complet », vérifie que le manifest utilisé par le script pointe bien vers `manifest_unified.jsonl` et pas un ancien manifest partiel (`train_combined.jsonl`, `train_full.jsonl`) — c'est une confusion fréquente qui fait tourner un training sur une fraction des données sans que ça saute aux yeux.

**⚠️ Vérifier la couverture du vocabulaire tokenizer AVANT tout training (leçon 2026-07-05, coûteuse)** : croiser l'ensemble des caractères du corpus contre les caractères couverts par les pièces BPE du tokenizer (`vocab_pieces.json`). Un caractère hors-vocab est **inapprenable** — le modèle sort `<unk>` pour toujours, quel que soit le nombre d'epochs, et chaque occurrence compte comme une erreur WER permanente. Découvert tardivement sur le training pcd : **9 caractères hors-vocab**, dont l'alef wasla `ٱ` (U+0671) présent dans **76% des lignes** (élision de « ال » en script Uthmani) — un plafond artificiel de plusieurs points de WER. Après normalisation dans `prepare_nemo_data.py` (wasla→alef, dagger alif→alef, petit waw/yeh→waw/yeh, hamza combinante→hamza, maddah/tatweel/marques de section→supprimés) : val_wer_ctc passé de ~9,7% à **~2,5%** dès le premier point de validation. Le check tient en 10 lignes de Python (Counter sur le corpus vs set des chars du vocab) — le faire systématiquement pour tout nouveau modèle de base ou nouveau corpus.

## Fine-tuning Whisper (HuggingFace `Seq2SeqTrainer`)

Scripts de référence : `benchmark/whisper_finetune_small.py`, `whisper_finetune_medium.py`. Pattern éprouvé à réutiliser pour tout nouveau script du même type :
- `bf16=True`, batch_size réduit + `gradient_accumulation_steps` pour compenser (VRAM partagée avec d'autres usages GPU).
- `warmup_steps=500`, `eval_strategy="steps"`, `EarlyStoppingCallback(early_stopping_patience=8)` — patience haute car le WER mesuré en cours de route est bruité (peu d'échantillons d'éval), c'est la loss qui est le signal fiable pour juger la convergence.
- `predict_with_generate=True`, `save_total_limit=3`, `dataloader_num_workers=8`.
- Sanity check WER sur 3 clips avant ET après l'entraînement (voir `sanity_check()` dans les scripts existants) — un moyen rapide de confirmer que le training a bien progressé sans attendre l'éval complète.

### Reprendre un training sur un dataset agrandi (warm-start)

Si on relance un training existant sur un manifest **plus gros** qu'au moment du dernier checkpoint (typiquement : nouveaux récitateurs ajoutés), **ne pas** faire `trainer.train(resume_from_checkpoint=last_ckpt)` en confiance aveugle. L'état de l'optimiseur d'un ancien checkpoint (souvent sauvé avec une version différente de `transformers`) est fréquemment incompatible et plante avec :
```
ValueError: loaded state dict contains a parameter group that doesn't match the size of optimizer's group
```
Solution robuste — reprendre les **poids seulement**, repartir avec un optimiseur neuf :
```python
from transformers.trainer_utils import get_last_checkpoint
last_ckpt = get_last_checkpoint(OUT) if os.path.isdir(OUT) else None
load_from = last_ckpt if last_ckpt else BASE
model = WhisperForConditionalGeneration.from_pretrained(load_from)
# ... construire le trainer normalement ...
trainer.train(resume_from_checkpoint=None)  # PAS last_ckpt
```
C'est un vrai compromis (on perd le scheduler LR / l'historique d'optimiseur), mais c'est nettement préférable à un crash, et le modèle repart quand même des poids déjà entraînés (pas de régression).

## Contamination riwaya (Warsh mélangé au Hafs, découvert 2026-07-12)

**~85 905 clips Warsh (21% de `manifest_unified.jsonl`, 407 149 clips) étaient mélangés au Hafs sans distinction** dans tous les trainings CTC précédents (y compris le run "augmenté" arrêté à val_wer_ctc ~1,1%). Découvert en cherchant à isoler du Hafs pur pour un entraînement sensible au tajweed — mais le problème contaminait déjà tout entraînement antérieur, tajweed ou pas.

**Origine** : le lot `_assajda` (scrapé depuis assabile.com/assajda.com) et un réciteur marocain séparé (`OmarQazabri_128kbps`, `download_moroccan.py`) contiennent des récitateurs **Warsh** (Maroc/Algérie), pas Hafs. La métadonnée `riwaya: "Warsh"/"Hafs"` existait déjà, correctement renseignée, dans `download_assajda.py::ASSAJDA_RECITERS` — mais n'a **jamais été propagée** dans le manifest ni utilisée pour filtrer en aval. Piège classique : la classification avait déjà été faite une fois (au moment du script de téléchargement) et s'est perdue faute d'être portée jusqu'au pipeline d'entraînement.

**Piège de la classification par nom** : deviner la riwaya depuis la consonance du nom du récitateur est **peu fiable** — `MustaphaLahouni` et `AlzainMohamedAhmed` sonnent respectivement maghrébin et soudanais, mais sont bien tagués Hafs dans le code. Toujours vérifier contre une métadonnée source réelle plutôt que deviner, même quand la supposition semble évidente.

**Les tags eux-mêmes sont non fiables (vérifié 2026-07-12)** : le commentaire du script dit littéralement « Warsh pour Maghreb/Algérie, Hafs pour le reste » = supposition géographique, pas une vérification. Or (a) un réciteur maghrébin peut réciter Hafs, (b) certains réciteurs enregistrent en PLUSIEURS riwayat (Omar Al-Kazabri fait Hafs ET Warsh ; Abdul Rashid Sufi fait 8 riwayat). Vérification manuelle des 14 réciteurs `_assajda` tagués « Hafs », un par un, contre leur page **assabile.com** (qui indique explicitement « Hafs A'n Assem » / « Warsh A'n Nafi' ») : **2 étaient mal tagués** — `HassanSaleh_assajda` apparaît en fait dans la liste Warsh officielle d'assabile, et `AbdulRashidSufi_assajda` (8 riwayat, collection par défaut non confirmée Hafs) exclu par prudence. Les 12 autres confirmés Hafs.

**Méthode de vérification audio par verset discriminant (réutilisable)** : quand la page/bio ne tranche pas (réciteur multi-riwaya), transcrire un clip du réciteur sur un verset où Hafs et Warsh diffèrent **audiblement** (pas juste une harakat) avec un modèle CTC arabe **neutre** (`jonatasgrosman/wav2vec2-large-xlsr-53-arabic`, pas nos modèles Coran biaisés Hafs qui « corrigeraient »). Versets utiles : **3:146** (Hafs `قَٰتَلَ` qātala / Warsh `قُتِلَ` qutila — présence/absence du alef long) ; **57:24** (Hafs `ٱللَّهَ هُوَ ٱلْغَنِىُّ` avec `هُوَ` / Warsh sans). Confirmé ainsi que `Muhammad_AbdulKareem_128kbps` (EveryAyah, Soudanais qui enregistre aussi du Dawri — donc suspect) récite bien **Hafs** dans son enregistrement EveryAyah → conservé. ⚠️ Piège du décalage de numérotation : en Warsh, la numérotation des versets diffère (Bismillah comptée autrement en sourate 1, décalage constaté aussi en sourates 2 et 57) — ne pas apparier les versets Hafs/Warsh par clé identique sans vérifier le contenu.

**Fix** : `build_hafs_only_manifest.py` — exclut les 21 réciteurs `_assajda` tagués Warsh + le doublon marocain + les 2 mal-tagués (HassanSaleh, AbdulRashidSufi) + le lot YouTube entier (`youtube_clean`, provenance/riwaya non vérifiée par clip, volume marginal 0,6%). Résultat : `data/manifest_hafs_only.jsonl`, **307 059 clips Hafs vérifiés** (75,4% du dataset original de 407 149). Décomposition : 257 646 EveryAyah (source everyayah.com mono-Hafs, certains) + ~49 400 assajda de 12 réciteurs vérifiés Hafs page par page.

**Règle générale à vérifier avant tout entraînement multi-source dans ce projet** : dès qu'un dataset combine plusieurs sources de récitateurs (surtout scraping large ou YouTube), vérifier explicitement la riwaya/qira'a de chaque source avant de les mélanger comme si elles étaient équivalentes — les différences Hafs/Warsh (madd, hamza, tafkhim/tarqiq du raa, numérotation des versets, diacritiques) sont suffisamment systématiques pour dégrader silencieusement un modèle censé être précis sur une seule riwaya.

## Fine-tuning NeMo FastConformer CTC-only (contournement NVVM)

Script de référence : `benchmark/finetune_fastconformer.py`. Le modèle de base est `nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0` (hybride RNNT+CTC, encodeur partagé). Sur cette machine Windows, la loss RNNT (`warprnnt_numba`) ne peut pas charger NVVM (`NvvmSupportError`) — impossible à corriger facilement, donc on entraîne **CTC uniquement** :
```python
class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0  # gradient nul, DP RNNT jamais exécuté
m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
m.loss = _ZeroRNNTLoss()
m.ctc_loss_weight = 1.0
```
**Piège critique de lecture des métriques** : `val_wer` / `training_batch_wer` restent bloqués à ~1.0 (tête RNNT gelée, artefact attendu — **ignorer complètement ces colonnes**). La vraie métrique à suivre est `val_wer_ctc` / `training_batch_wer_ctc` dans `metrics.csv`. Si quelqu'un s'inquiète d'un `val_wer` proche de 100%, vérifier d'abord `val_wer_ctc` avant de conclure à un problème.

Contraintes Windows additionnelles : `num_workers=0` (sinon `DataLoader` crashe), logger CSV plutôt que TensorBoard (conflit protobuf sinon).

**Ralentissement progressif GPU — fragmentation VRAM, pas un goulot CPU (2026-07-04)** : symptôme observé après plusieurs heures d'un même run : la vitesse tombe de ~6 it/s (début de run) à ~0.2 it/s, alors que `nvidia-smi` affiche 100% GPU-Util en continu — trompeur. Diagnostic : quand ça ralentit, `power.draw` chute à ~25% du cap et `utilization.memory` (bande passante) à ~1-2%, alors que la VRAM tourne proche du plafond (~97%, 15.6/16.3 Go avec `batch_size=8` sur des clips jusqu'à 30s mélangés aléatoirement). C'est la signature d'un allocateur CUDA qui fragmente/thrashe près de la limite mémoire (le GPU "travaille" mais gère de la mémoire, pas du calcul), pas d'un vrai goulot CPU/dataloader — vérifié en confirmant qu'aucune contention CPU externe n'expliquait le ralentissement au moment du diagnostic. Fix (zéro impact qualité, aucun changement de batch_size/LR) : ajouter avant le lancement
```
$env:PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True"
```
Confirmé après coup : bande passante mémoire remontée à ~38%, power.draw à ~204W, vitesse revenue à ~6.2 it/s (identique au début de run). À surveiller si ça revient sur un run très long malgré le flag (piste alors : réduire `batch_size` ou `max_duration` pour garder plus de marge VRAM).

Piège de lecture au `--resume` depuis un `.ckpt` mi-epoch : le dataloader NeMo n'est pas resumable (pas de `state_dict` sampler) → Lightning **fast-forward** (itère sans calcul) depuis le début de l'epoch jusqu'au point de reprise avant de reprendre l'entraînement réel. Ça affiche des vitesses ~50-350 it/s complètement factices pendant quelques dizaines de secondes — ne pas les confondre avec la vraie vitesse ; mesurer par delta de position sur le log une fois dépassé le point de reprise.

Le `ModelCheckpoint` périodique (`every_n_train_steps`) compte les **global steps** (= steps optimiseur, après `accumulate_grad_batches`), pas la position affichée par la barre de progression tqdm (qui avance de 1 par micro-batch). Avec `accumulate_grad_batches=4`, la barre affiche 4× le global_step — vérifier lequel des deux est utilisé avant de dimensionner l'intervalle. Un intervalle de 5000 steps s'est révélé trop large (perte de ~5h de calcul lors d'un ralentissement) ; réduit à 1000.

**Résultat de référence** : ce mode plafonne autour de WER_ctc 0.43-0.46 sur le dataset actuel — nettement en dessous de whisper-medium-ft (~11%). Ne pas s'attendre à le dépasser en transcription libre ; utile surtout comme piste d'alignement forcé (karaoké) où la tâche est plus facile (texte déjà connu).

## Export vers l'app Android (whisper.cpp / GGML)

**Ne jamais utiliser sherpa-onnx pour Whisper** — son décodage greedy simplifié (pas de `suppress_tokens` ni de fallback température) tronque ou boucle en fin de phrase, bug confirmé sans correctif disponible côté sherpa-onnx (`Only greedy_search is supported`). Le pipeline validé passe par whisper.cpp :

1. **HF → format OpenAI Whisper** : conversion manuelle du mapping de poids (voir `benchmark/convert_hf_to_openai_whisper.py` comme référence — mapping inverse de `transformers.models.whisper.convert_openai_to_hf.WHISPER_MAPPING`).
2. **OpenAI → GGML** : script officiel `whisper.cpp/models/convert-h5-to-ggml.py` (le télécharger si absent). Il attend `vocab.json` + `added_tokens.json` dans le dossier du checkpoint HF — s'ils n'existent pas (tokenizer "fast" uniquement), les générer depuis `tokenizer.json` :
   ```python
   import json
   d = json.load(open("tokenizer.json", encoding="utf-8"))
   vocab = d["model"]["vocab"]
   added = {t["content"]: t["id"] for t in d["added_tokens"]}
   json.dump(vocab, open("vocab.json", "w", encoding="utf-8"), ensure_ascii=False)
   json.dump(added, open("added_tokens.json", "w", encoding="utf-8"), ensure_ascii=False)
   ```
   Le script a aussi besoin de `mel_filters.npz` — le trouver dans `.venv/Lib/site-packages/whisper/assets/` (package `openai-whisper` installé localement) plutôt que de cloner le repo `openai/whisper`.
3. **Valider AVANT d'intégrer dans l'app** : tester le `.bin` GGML produit avec `pywhispercpp` sur quelques clips réels, **impérativement avec `no_timestamps=True`**. Nos fine-tunes s'entraînent sans tokens de timestamp → le modèle oublie la prédiction temporelle (d'autant plus que le fine-tuning est long), et le décodage whisper.cpp par défaut (règles de timestamps actives) produit alors des hallucinations fluides qui ignorent l'audio, voire des boucles `ههههه` en greedy pur. Ce n'est PAS un bug de conversion : le même fichier transcrit parfaitement avec le flag. Le plugin Flutter passe déjà `isNoTimestamps: true` — garder ce comportement. Symptôme associé si on l'oublie : sortie coranique plausible mais sans rapport avec l'audio, clips courts corrects mais longs cassés.
4. **Intégration Flutter** : plugin `whisper_ggml` (PAS `sherpa_onnx`). Nécessite `compileSdk = 36` et `ndkVersion = "29.0.13113456"` côté `android/app/build.gradle.kts` (dépendance transitive `ffmpeg_kit_flutter_new_min`) — si le plugin publié sur pub.dev a un `compileSdk` trop bas codé en dur dans son propre `android/build.gradle`, le patcher localement via `dependency_overrides` (voir `patches/whisper_ggml/` comme exemple déjà fait pour ce projet).

## Bascule pc → pcd : le choix du modèle de base plafonnait le CTC, pas seulement les données

Le modèle de base utilisé initialement, `nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0` (Punctuation+Capitalization), a **0 token diacritique sur 1024** dans son vocabulaire BPE (vérifiable directement : `[t for t in range(1024) if any(h in tokenizer.ids_to_tokens([t])[0] for h in 'ًٌٍَُِّْ')]` retourne vide). Il ne peut donc **structurellement** jamais produire de harakat correctes, quelle que soit la qualité du dataset — c'est ce qui plafonnait tous les entraînements CTC précédents à 43-46% WER, pas (seulement) la contamination du dataset assajda.

La variante `nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0` (+Diacritics) a **137/1024 tokens harakat** et un WER zero-shot de 6,55% sur EveryAyah (domaine coranique). Pour tout futur entraînement CTC arabe avec sortie diacritisée attendue, **toujours vérifier le nombre de tokens harakat du modèle de base avant d'entraîner** — un modèle `pc` (sans `d`) est un piège silencieux : l'entraînement tourne normalement, la loss baisse, mais le plafond de qualité est fixé dès le chargement du modèle, pas par les données. Avec `pcd` + dataset propre : `val_wer_ctc` = 20,3% dès 25% de la 1ère epoch (à comparer aux 43-46% qui ne bougeaient plus avec `pc`).

## Export FastConformer CTC (NeMo) vers ONNX pour mobile

Deux approches testées, une seule fonctionne aujourd'hui :

**❌ Pipeline fusionné (audio brut → logprobs en un seul graphe ONNX)** : échoue à l'export. `torch.onnx.export` (mode `dynamo=True` par défaut) plante sur le control-flow data-dependent de `normalize_batch` (`GuardOnDataDependentSymNode`) ; avec `dynamo=False` (tracer legacy TorchScript), ça avance plus loin mais plante ensuite sur le STFT (`torch.stft(..., return_complex=True)`) : **`torch.onnx` ne supporte pas l'export d'un STFT à sortie complexe** — limitation connue de l'exporteur PyTorch, pas un bug du modèle. Contournement possible mais non implémenté : reformuler le STFT via une matrice DFT précalculée + matmul (évite les tenseurs complexes) — piste à explorer si on veut absolument un seul fichier ONNX.

**✅ Pipeline en deux étapes (features mel précalculées → ONNX)** : fonctionne et est validé bit-exact.
```python
model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(nemo_path)
model.export("model.onnx")  # exporte encodeur + tête CTC, PAS le preprocessing
```
Entrées ONNX : `audio_signal` (features mel, `[B, 80, T]`) + `length` (`[B]`) — **pas l'audio brut**. Sortie : `logprobs` `[B, T, vocab_size+1]` (log-softmax, blank = dernier index). Validé : inférence ONNX pure (`onnxruntime`, CPU) donne un texte **strictement identique** à l'inférence NeMo/PyTorch native sur échantillons testés (0 divergence).

Conséquence pratique : le calcul du mel-spectrogramme doit être fait **côté appelant** (mobile), pas dans le graphe ONNX. Voir section suivante pour la formule exacte validée.

### Charger un checkpoint Lightning (`.ckpt`) en cours de training pour export (sans interrompre le training)

`EncDecHybridRNNTCTCBPEModel.load_from_checkpoint(ckpt)` échoue (`TypeError: ... not NoneType` dans `register_artifact`) : le tokenizer BPE est un artifact résolu relativement au dossier du `.nemo` d'origine (`app_state.nemo_file_folder`), absent d'un `.ckpt` Lightning seul. Fix : restaurer d'abord le `.nemo` de base (tokenizer OK), puis écraser les poids avec le `state_dict` du `.ckpt` :
```python
model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(base_nemo_path)  # tokenizer OK
ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)  # torch>=2.6 : weights_only=True par defaut, echoue sur DictConfig
model.load_state_dict(ckpt["state_dict"], strict=False)  # doit donner missing=0 unexpected=0
```
Utile pour valider un pipeline d'export **en parallèle d'un training en cours**, sans attendre la fin — snapshot d'un checkpoint intermédiaire, export testé, puis re-export du modèle final une fois le training terminé (même script, juste changer le chemin du `.ckpt`).

## Calcul mel-spectrogramme NeMo — formule exacte validée (pour portage natif Kotlin/C++)

`AudioToMelSpectrogramPreprocessor` (config du modèle `pcd`, standard NeMo) : `sample_rate=16000, n_fft=512, win_length=400 (25ms), hop_length=160 (10ms), window=hann(periodic=False), preemph=0.97, n_mels=80, fmin=0, fmax=8000, mel_norm=slaney, mag_power=2.0, log(x+2**-24), normalize=per_feature (mean/std par bin mel, ddof=1, +1e-5)`.

Reimplémentation pure numpy validée bit-exact (mean abs diff ~0.001 sur échelle normalisée [-3,3], 1 seule frame de bord sur ~4800 qui diverge — négligeable pour le décodage) : `benchmark/mel_numpy_reference.py`, validation croisée dans `benchmark/validate_mel_numpy.py`.

**Piège découvert (a fait échouer la première tentative, diff max 3.2 avant fix)** : quand `win_length < n_fft` (ici 400 < 512), `torch.stft` ne prend PAS simplement les `win_length` premiers échantillons de chaque frame — il lit une frame complète de `n_fft` échantillons `[t*hop, t*hop+n_fft)`, et seule la portion **centrée** de `win_length` échantillons `[t*hop + (n_fft-win_length)//2, ...)` est pondérée par la fenêtre de Hann (le reste de la frame `n_fft` est implicitement zéro). Lire `x[start:start+win_length]` au lieu de `x[start+win_pad:start+win_pad+win_length]` produit un résultat qui *ressemble* à un spectrogramme valide (même nombre de frames, ordre de grandeur correct) mais avec un contenu par-bin complètement décalé — bug silencieux, à re-vérifier avec un test à impulsion (signal quasi-nul avec un seul pic) si jamais un portage natif futur montre à nouveau un écart inexpliqué.

Filterbank mel "slaney" réimplémenté sans dépendance à `librosa` (formule Hz↔mel standard + normalisation par aire de triangle) — validé identique à `librosa.filters.mel(norm='slaney')` à 1e-9 près, voir `mel_filterbank_slaney()` dans `mel_numpy_reference.py`.

**FFT réutilisable** : `whisper.cpp` (déjà vendu dans `patches/whisper_ggml/android/src/whisper/whisper.cpp/whisper.cpp:2354-2429`) contient déjà une FFT Cooley-Tukey radix-2 récursive (entrée réelle `vector<float>`, sortie complexe entrelacée `[re,im,re,im,...]`) — directement réutilisable pour n_fft=512 (puissance de 2) plutôt que d'en écrire une nouvelle.

## Détokenisation BPE NeMo — pas besoin de SentencePiece natif

`tokenizer.ids_to_text(ids)` sur un modèle BPE NeMo (vérifié sur `pcd`) est équivalent à la version naïve : `"".join(piece_for_id[i] for i in ids).replace("▁", " ").strip()`. Pas besoin d'embarquer la lib SentencePiece côté mobile — juste le vocab (1024 entrées pour `pcd`, extrait du `.nemo`/`vocab.txt`) sous forme de liste id→piece, embarquable en asset texte trivial.

## Contrainte device cible : 6 Go RAM

Le téléphone de test n'a que 6 Go de RAM. Toujours garder ça en tête pour :
- La taille des modèles déployés (whisper-medium-ft en GGML fp16 = 1.5 Go, déjà une part significative du budget).
- Ne **jamais** charger deux gros modèles simultanément en mémoire sur device (ex: un modèle de transcription + un modèle d'alignement séparé) — les charger/décharger séquentiellement si les deux sont nécessaires.
- Préférer la quantification (int8) quand un modèle supplémentaire doit être ajouté.

## Repères de résultats (mettre à jour au fil des expériences)

Voir `benchmark/BENCHMARK_RESULTS.md` pour l'historique complet et détaillé. Résumé rapide pour éviter de refaire des essais déjà tranchés :

| Modèle | WER | Statut |
|---|---|---|
| whisper-medium-ft | ~11% | **Modèle de prod actuel**, déployé on-device (GGML/whisper.cpp) |
| whisper-small-ft | ~14.85% (v2, dataset unifié 78 récitateurs) | Alternative plus légère (244M vs 769M params) — entraînement v2 arrêté volontairement à checkpoint-8000 (WER ~34% à ce stade) pour prioriser l'investigation CTC ; reprenable |
| FastConformer CTC (base `pc`, dataset contaminé) | ~43-46% (plafonne) | Abandonné — cause racine identifiée : `pc` n'a aucun token diacritique, plafond structurel |
| FastConformer CTC (base `pcd`, dataset propre) | 20,3% à 25% d'epoch 0 → 9,7% epoch 3 (texte avec chars hors-vocab) → **~2,5% epoch 4 après fix vocabulaire** (training en cours) | En cours — dépasse whisper-medium-ft sur la val NeMo ; pas encore comparé sur `test_voice_full.jsonl` (benchmark indépendant à faire avant toute décision de prod) |
| Nemotron-3.5-ASR (zero-shot) | ~67-87% | Écarté — perd au benchmark, non fine-tunable ici (RNNT-only, pas de tête CTC, même blocage NVVM) |

## Intégration mobile FastConformer CTC (plan, en cours)

Contrairement à whisper.cpp (FFI vers `libwhisper.so`, tout le pipeline audio→texte en C++), le pipeline ONNX FastConformer attend des features précalculées (voir section export ci-dessus) — le plan retenu est **Kotlin pur + ONNX Runtime Android officiel**, pas de nouveau module C/C++/JNI :
1. Port Kotlin du mel-spectrogramme validé (`mel_numpy_reference.py` → Kotlin), FFT réutilisée/portée depuis `whisper.cpp` (radix-2, déjà dans le projet).
2. Inférence via la lib officielle `com.microsoft.onnxruntime:onnxruntime-android` (API Kotlin/Java native, pas de C API à lier manuellement).
3. Décodage CTC greedy (argmax + collapse repeats + suppression blank) + détokenisation BPE (jointure simple, voir section dédiée) en Kotlin.
4. Nouveau `MethodChannel` (`com.corankarim/fastconformer_ctc`) plutôt que FFI — l'API ONNX Runtime Android est orientée JVM (Kotlin/Java), une extension du pattern FFI existant de `whisper_ggml` n'est pas adaptée ici.
5. Modèle ONNX (~458 Mo, non quantifié) + vocab (1024 lignes) déployés dans le dossier modèles de l'app comme les autres modèles (pas embarqués dans l'APK), même pattern que `models/whisper-medium-ggml/`.
6. Intégration app : deuxième vérificateur en parallèle de whisper dans `recitation_verifier.dart`, réutilisant le même segment WAV déjà découpé par le VAD existant (pas de refonte du pipeline audio pour ce premier jet).

Objectif explicite de cette intégration précoce (demandé par l'utilisateur) : valider le pipeline complet **pendant** que le training tourne encore, pour ne découvrir aucune surprise d'intégration une fois le modèle final prêt — il suffira alors de remplacer le fichier `.onnx`.

### État de l'implémentation (2026-07-04)

Code écrit (snapshot du checkpoint à 20% val_wer_ctc, PAS le modèle final) :
- `android/app/src/main/kotlin/.../fastconformer/MelSpectrogram.kt` — mel-spectrogramme + FFT (portage Kotlin de `mel_numpy_reference.py`, revu ligne à ligne — un vrai bug trouvé et corrigé : Kotlin interdit la conversion implicite Float→Double, contrairement à Java/numpy).
- `FastConformerCtc.kt` — session ONNX Runtime + décodage CTC greedy + détokenisation BPE.
- `WavReader.kt` — lecture WAV PCM16 minimale (parse le chunk `data`, tolère des chunks additionnels avant).
- `FastConformerCtcPlugin.kt` — `MethodChannel` (`com.corankarim/fastconformer_ctc`, méthodes `loadModel`/`transcribe`/`dispose`), enregistré dans `MainActivity.kt`.
- `lib/services/fastconformer_verifier.dart` — wrapper Dart, branché dans `recitation_verifier.dart` en second vérificateur **debug uniquement** (n'affecte pas le flux de score whisper) : copie synchrone du WAV avant l'appel non-attendu (évite une course avec la suppression du segment par whisper), logge `CTC="..."` vs `whisper="..."` côte à côte.
- `build.gradle.kts` : ajout `com.microsoft.onnxruntime:onnxruntime-android:1.20.0` + `kotlinx-coroutines-android:1.9.0`.
- Modèle préparé pour déploiement : `benchmark/models/fastconformer-quran-pcd/onnx_export/deploy/fastconformer-ctc-pcd/{model.onnx, vocab.json}` — à copier sur l'appareil dans le dossier support de l'app (`ApplicationSupportDirectory/models/fastconformer-ctc-pcd/`), même convention que `models/whisper-medium-ggml/`.

**Build réel confirmé** (contrairement à la note précédente) : `flutter build apk`/`flutter install` fonctionnent sans erreur sur ce projet (le compilateur Kotlin autonome cassé mentionné plus haut est un problème isolé à un test ad-hoc hors-Gradle, pas au vrai toolchain du projet). Testé sur device réel (Samsung, Android 16) avec succès — le modèle offline transcrit correctement de la vraie voix ("بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ" reconnu à plusieurs reprises, latence ~200-500ms).

**Bug de timing corrigé** : `WhisperOnnxVerifier.stop()` coupait l'abonnement au flux de résultats (`_rawSub`/`_tokenSub`) dès que `_recorder.stop()` retournait, mais la transcription tournait en fire-and-forget (`_drainQueue()` non attendu) — le résultat arrivant après coup était silencieusement perdu. Fix : `stop()` attend maintenant `_pendingCtrl.stream.firstWhere((n) => n == 0)` si une transcription est en cours. Symptôme observé avant fix : logs confirmant une transcription correcte, écran bloqué sur le message de chargement.

## Streaming CTC : incompatibilité architecturale (2026-07-04)

Tentative de vrai streaming cache-aware (frame-par-frame, latence sub-seconde) au lieu du découpage VAD par segments. Piste initialement validée en zero-shot côté Python (`test_streaming_ctc.py` : qualité comparable à l'offline en basculant juste `att_context_style="chunked_limited"` sans réentraînement) puis exportée en ONNX stateful (`export_streaming_onnx.py`, cache d'encodeur en entrée/sortie via `export_cache_support=True`, validée fidèle au PyTorch natif à 4e-5 près sur 5 chunks consécutifs).

**Sur device réel, le décodage ne produisait quasiment rien** (blank presque partout, parfois une seule diacritique isolée). Diagnostic en deux temps :
1. D'abord suspecté un bug de featurisation côté Kotlin (normalisation calculée sur trop peu de contexte, frames récentes corrompues par du zero-padding de fin non-causal) — corrigé (calcul causal strict + stats cumulatives de session), sans amélioration.
2. Reproduction exacte du pipeline en Python (`simulate_kotlin_streaming.py`, 3 stratégies de normalisation × avec/sans silence initial) : **toutes vides**, même avec normalisation "oracle" (stats sur l'énoncé entier, meilleur cas possible). Puis test avec l'API de streaming **officielle** NeMo (`conformer_stream_step` + `CacheAwareStreamingAudioBuffer`, `test_official_stream_step.py`) : **crash** dès le premier chunk (`RuntimeError: cannot reshape tensor of 0 elements` dans `rel_shift`, attention relative).

**Conclusion** : ce n'est pas un bug d'implémentation (ni le mien, ni un export ONNX défaillant) — le modèle est entraîné avec des convolutions **non-causales** (subsampling + convs depthwise du Conformer regardent quelques frames dans le futur), ce qui casse fondamentalement le découpage chunk-par-chunk avec cache : le cache ne peut représenter que du contexte gauche, mais les couches convolutives du modèle ont besoin de contexte droit qu'elles n'ont jamais appris à ignorer. Le fait que l'API *officielle* NeMo échoue aussi confirme que ce n'est pas spécifique à notre export. Le zero-shot "qualité comparable" observé plus tôt (`test_streaming_ctc.py`) fonctionnait uniquement parce que ce test appelait `model.transcribe()` sur l'énoncé **complet** (le masque d'attention change, mais les convolutions voient tout le signal d'un coup) — pas un vrai découpage séquentiel avec cache.

**Vrai streaming = chantier de ré-entraînement**, pas un changement de config : il faudrait repartir d'une config NeMo avec convolutions causales dès le départ (`fastconformer_hybrid_..._streaming.yaml`), incompatible avec notre checkpoint actuel sans fine-tuning dédié — pas fait, à planifier séparément après la fin du training offline en cours.

**Solution retenue en attendant (`BufferedTranscriber.kt`)** : au lieu du vrai streaming, ré-exécuter le modèle **offline** (déjà validé, correct) sur le buffer audio complet de la session toutes les ~1,5s de nouvel audio. Latence perçue ~1,5-3s (pas sub-seconde), mais continu — pas de coupure manuelle entre versets, et surtout **ça marche réellement** contrairement au cache-aware.

**Instabilité additionnelle découverte en usage réel** : la re-transcription du buffer croissant peut s'effondrer (quasi-vide, ou mélanger le contenu de plusieurs versets) une seconde après avoir parfaitement reconnu le même contenu, puis récupérer — confirmé sur test réel (Al-Fatiha) : une snapshot couvrant les versets 4-6 quasi-parfaite suivie de re-transcriptions dégradées du même passage. Cause : la normalisation "per_feature" (mean/std recalculés sur TOUT le buffer à chaque appel) dérive à mesure que le buffer dépasse largement la durée d'un clip d'entraînement (un verset, quelques secondes à ~30s) — le modèle n'a jamais appris à être robuste à un enoncé aussi long ni à un ratio parole/silence aussi variable.

Mitigation v2 (insuffisante seule) : plafonner le silence conservé dans le buffer à ~300ms par pause — atténue mais n'élimine pas la dérive.

**Fix v3 (2026-07-05), retenu** : `BufferedTranscriber` fige (commit) définitivement la transcription du segment courant sur une pause franche (~700ms de silence continu, `COMMIT_SILENCE_SAMPLES`), reconcatène dans un texte permanent jamais reconsidéré, et repart sur un buffer vide — chaque segment reste ainsi proche de la distribution d'entraînement. Durci après relecture indépendante (agent) qui a identifié un trou réel : sans borne dure, une récitation continue sans pause suffisante laisse le buffer regonfler sans limite et réintroduit la dérive silencieusement — exactement le cas d'usage principal de la fonctionnalité. Ajouté : `MAX_SEGMENT_SECONDS` (20s, force un gel même sans silence détecté — risque résiduel accepté de coupure en plein mot dans ce cas limite, rare) et `MIN_COMMIT_SECONDS` (2.5s, évite de figer un segment trop court sur des statistiques peu fiables). Pas d'overlap audio entre segments (dédup texte non trivial avec le CTC greedy actuel qui ne renvoie aucune info de timing) — accepté comme limitation.

Côté scoring (`RecitationNotifier._realignFromFullText`), ré-aligner entièrement à partir de zéro à chaque mise à jour (le texte n'étant pas garanti append-only même avec le fix v3) ET ne jamais laisser le pointeur reculer (une re-transcription ponctuellement dégradée est ignorée plutôt qu'affichée).

**Piste "stats fixes" testée et REJETÉE (2026-07-05, `test_fixed_normalization.py`)** : hypothèse = remplacer la normalisation "per_feature" par des statistiques fixes précalculées sur le corpus éliminerait la dérive des buffers longs. Résultat mesuré : clips isolés per_feature 2,83% vs stats fixes 3,97% (+1,14 pt de coût) ; fin de sessions concaténées ~37% **dans les deux cas** (aucun gain). Conclusion importante : la dégradation sur audio long n'est PAS causée par la normalisation — le modèle lui-même se dégrade au-delà de la distribution d'entraînement (clips d'un verset), quelle que soit la stratégie de calibrage (2,83% isolé → ~37% en fin de session de 7 versets concaténés). **Les segments courts (~un verset) ne sont donc pas un contournement mais l'architecture correcte** pour ce checkpoint ; la qualité du découpage est le vrai levier. Suite logique : découpage guidé par les marques de waqf du texte (positions de pause légitimes connues a priori) + profil de pauses personnel appris de la lecture de référence de l'utilisateur (déjà enregistrée pour l'empreinte vocale). Stats fixes générées quand même dans `onnx_export/mel_fixed_stats.json` si besoin futur.

## Vérification par embeddings audio-à-audio (niveau 1 "personnalisation voix", 2026-07-04)

Idée de l'utilisateur (mémoire `voice-personalization-idea`, proposée le 2026-06-27) : au lieu de décoder en texte pour vérifier (instable, cf. ci-dessus), comparer directement l'audio de la nouvelle récitation à une **récitation de référence déjà vérifiée correcte** du même utilisateur pour le même passage — enregistrée pendant les phases "Lecture"/"Entraîne" qui précèdent déjà la phase "Contrôle" dans l'app.

**Deux approches testées côté recherche (Python, avant tout portage mobile) :**
- **Alignement forcé** (`test_forced_align_verification.py`, réutilise l'aligneur `wav2vec2-arabe` déjà validé pour la réparation du dataset) : **décevant**. Texte correct vs texte d'un verset différent → écart de score faible (0.82-0.94 vs 0.80-0.93, se chevauche). Un mot substitué au milieu d'un texte correct → pas fiablement repéré (le mot substitué peut scorer PLUS HAUT que des mots corrects voisins). L'alignement forcé trouve toujours "le mieux possible", ce n'est pas conçu pour rejeter une hypothèse fausse.
- **Similarité DTW sur les embeddings de l'encodeur** (`test_embedding_dtw.py`, notre propre modèle FastConformer) : **nettement mieux**. Même verset récité par des récitateurs différents → similarité moyenne 0.94 ; versets différents → 0.86. Écart net et cohérent (4/5 cas bien discriminés). Le cas d'usage réel (même personne, référence vérifiée vs nouvelle tentative) devrait discriminer encore mieux qu'un test cross-récitateur.

**Implémentation (niveau 1 uniquement, niveaux 2/3 non implémentés)** :
- `benchmark/export_embedding_model.py` : ré-exporte l'encodeur pour exposer EN PLUS sa représentation brute (avant la tête CTC, 512-dim/frame) comme sortie `embeddings`, à côté des `logprobs` habituels — validé fidèle au PyTorch natif (diff 3.5e-5).
- `android/.../fastconformer/VoiceFingerprint.kt` : calcule l'embedding d'un WAV, sérialise/désérialise en binaire simple (T, 512 floats), et implémente le DTW (programmation dynamique sur distance cosinus, O(Ta·Tb)) pour comparer deux séquences.
- `FastConformerCtcPlugin.kt` : `loadFingerprintModel`/`saveFingerprint`/`compareFingerprint`/`disposeFingerprint`.
- `lib/services/voice_fingerprint_service.dart` : API Dart — `saveReference(wavPath, passageKey)` (stocke `ApplicationDocumentsDirectory/voice_fingerprints/<passageKey>.bin`) et `compareToReference(wavPath, passageKey) -> double?`.

**⚠️ Piège déjà identifié par l'utilisateur avant même l'implémentation** : la 1ère lecture peut contenir des erreurs → ce n'est PAS une référence fiable en soi. `VoiceFingerprintService.saveReference()` ne fait AUCUNE vérification lui-même — c'est à l'appelant (code UI, pas encore écrit) de ne sauvegarder une référence QUE si elle a été vérifiée correcte par ailleurs (ex: bon score ASR pendant la phase Entraîne). Donnée vocale sensible (religieuse) → stockage on-device uniquement, jamais synchronisé.

**Non fait** : le branchement dans l'UI (CoachScreen, phases Lecture/Entraîne/Contrôle) — la mécanique de calcul/stockage/comparaison est prête et compile, mais rien n'appelle encore `saveReference`/`compareToReference` depuis un écran réel. Prochaine étape si on continue cette piste.

## Personnalisation voix — niveau 3 : mini-LoRA personnel (plan, PAS implémenté)

Niveau 3 de l'idée originale : ré-entraîner légèrement le modèle sur les récitations vérifiées correctes d'un utilisateur spécifique, pour s'adapter à sa voix/accent au-delà de la simple comparaison DTW (niveau 1). Explicitement noté par l'utilisateur dès la proposition initiale comme "lourd, plutôt serveur/nuit" — confirmé par cette session : **pas réaliste en entraînement réellement on-device** avec notre stack actuelle.

**Pourquoi pas on-device** : ONNX Runtime Mobile (notre moteur d'inférence sur le téléphone) ne fait QUE de l'inférence, pas d'entraînement — pas de rétropropagation, pas d'optimiseur. Il existe bien "ONNX Runtime Training"/du fine-tuning via PyTorch Mobile/ExecuTorch, mais ce serait un moteur mobile entièrement différent de celui déjà en place, à réintégrer de zéro. Risque et effort élevés, non justifiés tant que le modèle principal n'est pas stabilisé.

**Plan réaliste (PC-side périodique, pas temps réel)** :
1. Collecter sur le téléphone les enregistrements de la phase Lecture/Entraîne déjà vérifiés corrects (même mécanisme que niveau 1 — on a déjà "un audio + un texte de référence + une vérification").
2. Synchroniser ces clips vers ce PC (mécanisme à définir — pas de serveur dans l'architecture actuelle, donc probablement une sync manuelle/périodique déclenchée par l'utilisateur, pas automatique).
3. Réutiliser le pipeline d'entraînement NeMo déjà en place (`finetune_fastconformer.py`) pour un fine-tuning LÉGER (peu d'epochs, LR bas, éventuellement geler l'essentiel de l'encodeur et n'entraîner qu'un adaptateur LoRA plutôt que tous les poids — pas encore configuré dans ce projet, NeMo supporte les adaptateurs PEFT/LoRA via `nemo.collections.common.parts.adapter_modules` mais jamais utilisé ici).
4. Exporter le modèle personnalisé résultant (même pipeline `export_pcd_checkpoint.py`/`export_embedding_model.py`) et le redéployer sur le téléphone de cet utilisateur spécifiquement (pas un modèle partagé global).

**Questions ouvertes non résolues** : volume de données minimal pour un LoRA utile (probablement quelques minutes de voix vérifiée, à valider empiriquement) ; risque de sur-adaptation si les clips "vérifiés corrects" contiennent en fait des erreurs de vérification (niveau 1 lui-même imparfait) ; mécanisme de sync téléphone↔PC à concevoir (pas de solution existante dans ce projet). À reprendre une fois le training principal terminé et le niveau 1 testé en conditions réelles.

## Modèle de langage coranique pour le décodage (plan, PAS implémenté, 2026-07-04)

Idée de l'utilisateur : le CTC actuel décode l'audio en texte SANS AUCUNE connaissance de ce qu'est une séquence coranique plausible — chaque frame est classée indépendamment (greedy) ou quasi-indépendamment (beam search sans LM), donc le modèle ne "sait" pas que "الحمد لله رب" doit très probablement être suivi de "العالمين". Un modèle de langage (LM) entraîné sur le texte du Coran comblerait ça.

**Pourquoi c'est particulièrement puissant ICI (pas juste une astuce générique ASR)** : le Coran est un texte **fermé et intégralement connu** (~77 400 mots, ~6236 versets, déjà en base) — contrairement à la parole générale (vocabulaire ouvert, infini). Un LM entraîné sur un corpus aussi contraint et répétitif (formules récurrentes : "إن الله", "الحمد لله"...) devrait être beaucoup plus discriminant qu'un LM généraliste.

**Important, en réponse à la question directe de l'utilisateur** : ceci n'entre PAS en compétition avec le training acoustique en cours (CTC audio→texte, sur GPU). Un LM texte-seul s'entraîne sur le texte coranique SEUL (aucun audio requis), en quelques minutes sur CPU, et n'intervient qu'AU DÉCODAGE (rescoring/biaisage du beam search), pas dans les poids de l'encodeur/tête CTC. Les deux peuvent avancer strictement en parallèle, aucune raison d'interrompre le training actuel pour ça.

**3 approches, effort croissant** :
1. **N-gram + KenLM (shallow fusion)** — effort FAIBLE. Corpus = texte canonique déjà en base. NeMo supporte nativement le décodage beam search avec fusion KenLM (`pyctcdecode`/`BeamSearchDecoderWithLM`) — pas de retraining du modèle acoustique, juste un changement de config de décodage. Le candidat naturel à essayer en premier.
2. **LM neuronal (petit transformer/RNN) + rescoring N-best** — effort MOYEN, gain probablement marginal par rapport à (1) vu à quel point le corpus coranique est déjà contraint/répétitif (les n-grammes excellent sur ce genre de domaine fermé).
3. **Décodage CONTRAINT au texte attendu** (pas un LM général — un filtre dur) — effort MOYEN, mais réutilise directement l'architecture "vérification contre texte connu" déjà au cœur de ce projet (cf. section "Recherche CTC état de l'art" dans BENCHMARK_RESULTS.md) : puisqu'on connaît déjà le verset visé dans la plupart des écrans de l'app, restreindre le décodage aux seules séquences compatibles avec CE texte précis élimine l'ambiguïté entièrement — plus puissant qu'un LM généraliste pour ce cas d'usage précis, mais ne couvre pas le cas "l'utilisateur saute un verset/se trompe de passage".

**Recommandation** : commencer par (1), peu coûteux, ne touche pas au training en cours, bénéficierait à tous les pipelines existants (buffered fallback, karaoké) une fois branché. Garder (3) comme complément pour le Coach (per-aya, texte cible toujours précisément connu).

Si une nouvelle expérience change une de ces lignes, mets à jour `BENCHMARK_RESULTS.md` (pas seulement ce tableau) pour que la mémoire du projet reste fiable.

## Biais du modèle vers le texte canonique — le modèle "corrige" les vraies erreurs (plan, PAS implémenté, 2026-07-05)

**Découvert par test réel** (checkpoint 2,07%, app v20/v21) : l'utilisateur récite délibérément "الحمدِ" (kasra) au lieu de "الحمدُ" (damma, texte attendu). À 1s d'audio (peu de contexte), le modèle transcrit correctement "الْحَمْدِى" — il a bien entendu l'erreur. Mais 3s plus tard, avec plus de contexte (la suite du verset), le segment figé devient "الْحَمْدُ" — le modèle est "revenu" au texte canonique alors que l'utilisateur n'avait rien redit de travers. Observé aussi côté app : le mot passe rouge puis vert tout seul (corrigé par le fix "verrouillage rouge/vert" du 2026-07-05, cf. `recitation_provider.dart._judgeOnce` — mais ça ne corrige que le SYMPTÔME affiché, pas la cause modèle).

**Cause probable** : le modèle n'a JAMAIS vu, dans ses données d'entraînement, une seule récitation volontairement fautive — chaque paire audio/texte du corpus est une récitation correcte. Pour les formules très répétées ("الحمد لله", présent dans chaque Fatiha récitée par ~80 récitateurs × plusieurs fois), le modèle a appris "ce son → exactement ce texte canonique" avec une confiance écrasante, sans jamais apprendre qu'un son légèrement différent peut correspondre à un texte légèrement différent. Pas un problème de "trop d'epochs" — un problème de **diversité des erreurs** absente des données.

**Piste envisagée, discutée avec l'utilisateur, PAS implémentée** : augmenter les données d'entraînement avec des récitations **délibérément fautives** (harakat changées, mots substitués/sautés), étiquetées avec le texte **réellement prononcé** (fautif), pas le texte corrigé.

- **Point critique soulevé par l'utilisateur, à respecter absolument** : l'étiquette doit correspondre à ce qui a été RÉELLEMENT dit. Coller le texte canonique en face d'un audio fautif referait exactement le mécanisme qui a créé le biais — ça l'aggraverait, pas l'inverse.
- **Pourquoi on ne peut pas juste utiliser les erreurs accidentelles des utilisateurs** : aucun moyen fiable de connaître la vérité exacte derrière une erreur non intentionnelle (juste l'entendre ne suffit pas sans transcription humaine experte).
- **Source réaliste retenue en discussion** : des fautes **délibérées et auto-étiquetées** par quelqu'un qui sait exactement quelle erreur il vient de faire (exactement le protocole des tests manuels du 2026-07-05 : "je vais dire X au lieu de Y"). Ne scale pas à des milliers d'heures, mais donne un petit corpus fiable de fautes courantes (harakat inversées, substitutions, mots sautés) à construire progressivement.
- **Piste complémentaire (pas un substitut)** : audio arabe général non-coranique (lectures, audiolivres) pour diversifier l'acoustique générale et réduire la sur-spécialisation sur la cadence coranique spécifique — mécanisme différent (robustesse générale, pas fidélité aux déviations), les deux pistes peuvent coexister.

**Ne pas confondre avec les pistes "modèle de langage pour le décodage" ci-dessus** : ces 3 options (n-gram, LM neuronal, décodage contraint) vont dans le sens INVERSE — elles renforcent le biais vers le texte connu. Ne pas les appliquer en pensant régler ce problème-ci, elles l'aggraveraient.

Ne touche pas au training en cours (idée d'augmentation de données pour un futur run, pas celui en cours).
