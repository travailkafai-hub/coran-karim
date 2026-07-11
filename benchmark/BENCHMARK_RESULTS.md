# Benchmark ASR récitation coranique — Whisper-Quran vs Gemma 4 E2B

**Date** : 2026-06-27 · **Machine** : RTX 5080 16 GB · **Jeu de test** : 16 ayahs courts (sourates 112, 108, 110, 111, 36), récitateur Alafasy, texte de référence vérifié via l'API Quran.com.

## Méthode
- **Piste A (transcription)** : audio → texte → WER + détection d'erreur par alignement algorithmique (diff mot-à-mot vs référence).
- **Piste B (jugement direct)** : audio + texte de référence → le modèle juge directement s'il y a une erreur (sans transcription intermédiaire). *Hypothèse à tester : éviter l'étape de transcription réduit-il l'erreur ?*
- **Détection** : pour chaque ayah, un cas « correct » (audio + réf correcte → attendu : pas d'erreur) et un cas « corrompu » (audio + réf avec 1 mot supprimé/substitué/inversé → attendu : erreur détectée).

## Résultats — tableau complet (tous modèles, base non fine-tunés)

| Modèle | Params | WER* | Détection | Faux pos. | Recall | Latence | Taille |
|---|---|---|---|---|---|---|---|
| **whisper-base (tarteel)** 🏆 | 74 M | **5,2 %** | **90,6 %** | **12,5 %** | 93,8 % | 0,2 s | **0,34 GB** |
| whisper-tiny (tarteel) | 39 M | 6,8 % | 87,5 % | 18,8 % | 93,8 % | 0,13 s | 0,1 GB |
| whisper-large-v3-turbo (Maddogg) | 809 M | 14,6 %* | 87,5 % | 25 % | 100 % | 0,12 s | 1,6 GB |
| whisper-medium (tarbiyah-ai) | 769 M | 18,9 % | 75 % | 50 % | 100 % | 0,31 s | 1,5 GB |
| Gemma 4 E2B — piste A (transcription) | 2,3 B | 16,6 % | 81,2 % | 37,5 % | 100 % | 0,8 s | 10,3 GB / **2,5 GB INT4** |
| Gemma 4 E2B — piste B (jugement direct) | 2,3 B | — | 81,2 % | 31,2 % | 93,8 % | 1,0 s | idem |

\* **Le WER des gros modèles est gonflé par la normalisation** : large-v3-turbo et medium produisent un arabe quasi parfait, mais avec des variantes orthographiques (`أَعْطَيْنَاكَ` vs `أَعْطَيْنَـٰكَ`, `يس`→`يسين`) que la métrique compte comme erreurs. tarteel base/tiny gagnent en partie parce qu'ils sont entraînés à sortir exactement l'orthographe uthmani de la référence everyayah/quran.com.

## Conclusions

1. **Out-of-the-box, Whisper-Quran gagne nettement** (WER 5,2 % vs 16,6 %). Logique : Whisper-Quran est *déjà fine-tuné* sur le Coran ; Gemma 4 E2B est un modèle généraliste non spécialisé. Comparaison non équitable à ce stade.

2. **Piste A vs Piste B (modèle base) : égalité** (81,2 % toutes deux). L'hypothèse « le jugement audio direct évite l'erreur de transcription » ne se vérifie pas encore : le modèle base *entend mal* le Coran (ex. `يسٓ`→`يسين`, hallucination sur 110:2), donc la Piste B hérite des mêmes erreurs d'écoute.

3. **Blocant pour l'usage app : 31-37 % de faux positifs** côté Gemma — il signale trop souvent une récitation correcte comme fausse. Inacceptable pour une app de mémorisation (frustration élève). Whisper : 12,5 %.

## Décision & prochaine étape

- **v1 pragmatique** : **Whisper-Quran pour l'ASR** (léger, prouvé) + Gemma pour le tuteur.
- **Test décisif restant** : **Gemma 4 E2B FINE-TUNÉ** sur récitation coranique. C'est là que se joue la voie unifiée (1 seul modèle audio+tuteur). Objectifs à atteindre pour basculer : WER ≤ ~6 % et faux positifs ≤ ~12 %.
- **E4B écarté** : 16 GB bf16 ne tient pas dans 16 GB de VRAM, et 3-4 GB INT4 est limite pour mobile. E2B est la cible.

## Fine-tuning (2026-06-27) — dataset 3 derniers Hizb × 13 récitateurs (10 213 clips)

Splits held-out : `test_voice` (récitateur Hani_Rifai jamais vu), `test_text` (40 versets jamais vus).

### Whisper-base : continued fine-tuning (3 epochs) → SUR-APPRENTISSAGE ⚠️
Comparaison équitable sur les MÊMES held-out (150 clips chacun) :

| Whisper-base | WER | Faux positifs | Détection |
|---|---|---|---|
| BASE — voix inédite | **9,6 %** | **34,7 %** | **82,3 %** |
| BASE — versets inédits | **9,6 %** | **32 %** | **83 %** |
| FT 3 epochs — voix inédite | 16,8 % | 46,7 % | 76,3 % |
| FT 3 epochs — versets inédits | 21,1 % | 50,7 % | 73,7 % |

**Leçon majeure** : le continued FT naïf (3 epochs, LR 1e-5, loss→0,0005) a **mémorisé** les voix d'entraînement et **dégradé** la généralisation. Le modèle base est meilleur. Un bon FT nécessite : peu d'epochs (~0,3-0,5), LR plus bas, early-stopping sur held-out, gel de l'encodeur, plus de voix. → **Fine-tuner ≠ améliorer.**

NB : le WER held-out du base (9,6 %) est supérieur au 5,2 % du 1er benchmark car les held-out sont plus durs (13 voix variées dont inédites) que l'Alafasy propre des 16 ayahs.

### Gemma 4 E2B : LoRA audio (1 epoch, 10k ex. ASR+jugement, loss 2,5→1,7)

Évaluation held-out (N=60), comparée à Whisper base :

| Modèle / piste | held-out | WER | Faux pos. | Recall | Détection |
|---|---|---|---|---|---|
| **Whisper base** | voix inédite | **9,6 %** | 34,7 % | 99 % | **82,3 %** |
| **Whisper base** | versets inédits | **9,6 %** | 32 % | 98 % | **83 %** |
| Gemma BASE — A (transcription) | voix | 52,9 % | 83 % | 100 % | 58 % |
| Gemma BASE — A | texte | 39,4 % | 70 % | 100 % | 65 % |
| Gemma BASE — B (jugement) | voix | — | 78 % | 93 % | 57,5 % |
| Gemma BASE — B | texte | — | 43 % | 97 % | 76,7 % |
| Gemma **LoRA** — A | voix | 116 % ❌ | 90 % | 100 % | 55 % |
| Gemma **LoRA** — A | texte | 96 % ❌ | 88 % | 100 % | 55,8 % |
| Gemma **LoRA** — B | voix | — | **37 %** | 72 % | 67,5 % |
| Gemma **LoRA** — B | texte | — | **22 %** | 65 % | 71,7 % |

**Lecture :**
- **Whisper écrase Gemma** pour la vérification (détection 82-83 %, WER ~10 %) vs Gemma (au mieux 67-72 %).
- **Le LoRA a DÉGRADÉ la transcription (piste A)** de Gemma : WER 96-116 % (radotage/répétitions sur held-out ; encodeur audio gelé = goulot, le LLM seul ne peut pas apprendre à « entendre » le Coran).
- **Le LoRA a amélioré la précision du jugement direct (piste B)** : faux positifs 78%→37 % (voix), 43%→22 % (texte) — MAIS le recall s'effondre (93%→72 %, 97%→65 %) : il devient timide et rate de vraies erreurs. Détection nette ~67-72 %, toujours sous Whisper.

## VERDICT FINAL

**Pour la vérification de récitation (le cœur de l'app), Whisper gagne sans appel.** Le fine-tuning n'a PAS rendu Gemma compétitif sur l'ASR. La vision « un seul modèle Gemma fait tout » ne tient pas empiriquement pour cette tâche (avec encodeur audio gelé + LoRA LLM).

**Caveats honnêtes pour Gemma** : (1) on a gelé l'encodeur audio — adapter l'encodeur/projecteur audio serait plus puissant mais bien plus lourd, non testé ; (2) le radotage pourrait se discipliner ; (3) la force de Gemma reste le **tuteur** (texte), pas l'ASR.

### Architecture recommandée (validée par l'expérience)
- **ASR / vérification → Whisper-base** (léger 0,34 GB, robuste, WER ~10 % held-out).
- **Tuteur / explications / quiz → Gemma 4 E2B** (sa vraie valeur).
- **Pour réduire les faux positifs → personnalisation par la voix de l'utilisateur** (cf. idée produit), PAS plus de fine-tuning ASR Gemma.
- Whisper : utiliser le **base tel quel** (le continued FT 3 epochs a dégradé) ou un recipe prudent (≤0,5 epoch, LR bas, early-stopping, plus de voix).

## Reproduire
```
benchmark/
  data_prep.py        # télécharge audio + texte de référence
  common.py           # normalisation arabe, WER, détection
  bench_whisper.py    # baseline Whisper
  bench_gemma.py <path/local>  # Gemma 4, pistes A & B
  data/results_*.json # résultats détaillés par ayah
```

---

# Phase 2 (2026-07-02 → 2026-07-03) — Passage à l'échelle : dataset unifié, FastConformer, on-device

## Dataset unifié
- Fusion de toutes les sources JSONL (`manifest_unified.jsonl`) : **78 récitateurs distincts**, **414 567 clips** (57 récitateurs EveryAyah/Tarteel classiques `_XXkbps` + 21 récitateurs batch2 `_assajda` téléchargés).
- Manifests NeMo dérivés : `train_manifest.jsonl` (~412k clips) / `val_manifest.jsonl` (~15-20k clips selon la version).

## Whisper fine-tuning à grande échelle

| Modèle | Dataset | Epochs | Meilleur WER (eval) | Statut |
|---|---|---|---|---|
| **whisper-small-ft** (v1) | `train_combined.jsonl` (ancien, plus petit, sans batch2) | 4 | **18,3 %** (0,1834) | Terminé, remplacé |
| **whisper-medium-ft** | idem (ancien dataset, avant unification) | ~1,2 | **10,75 %** (0,1075) | **Déployé sur device** (voir plus bas) |
| **whisper-small-ft** (v2) | `manifest_unified.jsonl` (411 937 clips, 78 récitateurs) | 6 prévues, arrêté à 1,79 (early stopping) | **14,85 %** (0,1485, epoch 1,17) | **Terminé (2026-07-04)** — meilleur checkpoint restauré (`load_best_model_at_end`), sanity check final parfait |

Note technique : le warm-start v1→v2 a nécessité de **charger les poids seuls** (pas l'optimiseur) du checkpoint `whisper-small-ft/checkpoint-30392`, car son état d'optimiseur (sauvé avec transformers 5.12.0) est incompatible avec la version installée (4.57.6) → `trainer.train(resume_from_checkpoint=...)` plantait sur `_load_optimizer_and_scheduler`. Fix : `WhisperForConditionalGeneration.from_pretrained(last_ckpt)` puis `resume_from_checkpoint=None`.

## NeMo FastConformer CTC-only (`nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0`)

Contournement du blocage NVVM (`warprnnt_numba` indisponible sur Windows) : tête RNNT gelée (`_ZeroRNNTLoss`), entraînement **CTC uniquement** (`ctc_loss_weight=1.0`). Voir mémoire `ctc-only-training-metric` : lire `val_wer_ctc`, **pas** `val_wer` (RNNT figée reste ≈1.0).

| Step | val_wer_ctc |
|---|---|
| 2775 (25% ep.0) | 0,465 |
| 5551 (50% ep.0) | 0,446 |
| 8327 (75% ep.0) | **0,433** (meilleur point) |
| 11103 (100% ep.0) | 0,434 |
| 13880 (32% ep.1) | 0,440 ↑ (plateau/remontée) |

**Décision (2026-07-03) : entraînement ARRÊTÉ.** Le plateau/remontée confirme qu'on ne rattraperait pas whisper-medium-ft (11 %) en transcription libre. Pivot : réutiliser l'idée CTC pour de l'**alignement forcé karaoké** plutôt que de la transcription (voir section suivante) — un CTC avec WER élevé peut rester un bon aligneur temporel, car aligner sur un texte déjà connu est une tâche plus facile que deviner le texte.

## Zero-shot Nemotron-3.5-ASR-streaming-0.6B (comparaison, pas de fine-tuning possible)

| Modèle | WER strict (avec tashkeel) | WER ortho (sans tashkeel) |
|---|---|---|
| Nemotron-3.5 zero-shot (50 clips uniformes 2-22s) | 0,87 | 0,67 |
| FastConformer CTC (à l'arrêt) | 0,43-0,46 | ≤ 0,43 |

Nemotron perd nettement. De plus il est **RNNT-only (pas de tête CTC)** → non fine-tunable sur cette machine Windows (même blocage NVVM, pas de repli CTC comme pour FastConformer). Décision : abandonné.

## Déploiement on-device (téléphone, Android, 6 GB RAM)

### Bug sherpa-onnx Whisper → migration whisper.cpp
`sherpa-onnx` (via `sherpa_onnx.dart`) tronque/boucle en fin de phrase. **Cause confirmée** : décodage greedy simplifié sans `suppress_tokens`/`begin_suppress_tokens`/fallback température — vérifié en reproduisant le même greedy via `transformers.generate()` (résultat parfait) vs sherpa (tronqué). `modified_beam_search` non supporté pour Whisper côté sherpa (`Only greedy_search is supported`).

**Migration** : `whisper-medium-ft` (HF) → format OpenAI (conversion manuelle du mapping de poids) → export GGML via script officiel `whisper.cpp/models/convert-h5-to-ggml.py` (patché pour `dynamo=False`, torch 2.11) → **1,5 GB fp16**, validé avec `pywhispercpp` sur clips réels (transcription complète, plus de troncature). Intégré dans l'app via le plugin Flutter `whisper_ggml` (patch local `compileSdk 34→36` + NDK 29.0.13113456 requis par `ffmpeg_kit_flutter_new_min`).

### Contrainte mémoire device : 6 GB RAM
Le modèle whisper-medium-ft GGML fp16 (1,5 GB) est déjà une part significative du budget mémoire. Toute piste d'alignement karaoké complémentaire (voir plus bas) devra être **chargée/déchargée séquentiellement**, pas simultanément avec Whisper, et idéalement quantifiée (int8).

## Recherche : alignement forcé "karaoké" (mot-par-mot, timing)

Objectif : savoir *quand* chaque mot attendu a été prononcé (surlignage temps réel), en complément du jugement de justesse (déjà géré par whisper-medium-ft). Recherche 2026 :

| Piste | Statut | Verdict |
|---|---|---|
| **DASAM** (Diacritic-Aware Segmentation/Alignment, papier juin 2024, testé sur Coran, bat Google STT) | Papier académique, **pas de code/poids publiés** | Non exploitable court terme |
| **Qwen3-ForcedAligner-0.6B** (2026, léger, meilleur que WhisperX en benchmark) | Public, mais **pas d'arabe** (11 langues, arabe absent) | Écarté |
| **Wav2Vec2-XLSR-53 fine-tuné Coran** (papier juin 2026, EveryAyah+Tarteel 870h, WER 0,08 sans tashkeel / 0,23 avec) | Résultats publiés, **checkpoint exact non retrouvé public** | Confirme empiriquement que l'alignement sans tashkeel est plus fiable que l'alignement/transcription avec tashkeel |
| **MMS-300M forced-aligner** (`MahmoudAshraf/mms-300m-1130-forced-aligner`) | ✅ **Testé avec succès** (torchaudio `forced_align`, sans compilation C++) | Vocabulaire romanisé (uroman, 31 symboles latins) — perd la distinction fine des harakat, mais adapté au *timing* pur. Licence CC-BY-NC-4.0 (OK, app gratuite) |
| **wav2vec2-large-xlsr-53-arabic** (`jonatasgrosman`) | ✅ **Testé avec succès** | Vocabulaire **arabe natif + harakat** (51 tokens), pas de romanisation. Timestamps quasi identiques à MMS-300M sur le même clip → signal cohérent entre 2 modèles indépendants |

**Test comparatif** (clip "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ", 5.6s) :

| Mot | MMS-300M | wav2vec2-arabe natif |
|---|---|---|
| بِسْمِ | 0,84 → 1,22s | 0,84 → 1,26s |
| اللَّهِ | 1,30 → 1,85s | 1,28 → 1,93s |
| الرَّحْمَـٰنِ | 1,95 → 3,11s | 1,95 → 3,17s |
| الرَّحِيمِ | 3,19 → 4,68s | 3,19 → 5,58s |

**Recommandation** : `wav2vec2-large-xlsr-53-arabic` en priorité (écriture native, pipeline plus simple, pas de dépendance `uroman`). Fonctionnalité **non intégrée à l'app** à ce stade — recherche/validation seulement.

## Export GGML des fine-tunes : piège `no_timestamps` (résolu 2026-07-04)

Le GGML de whisper-small-ft semblait « cassé » (hallucinations fluides ignorant l'audio, boucles `ههههه` en greedy pur) alors que le fichier était **parfaitement fidèle** (479 tenseurs vérifiés octet-par-octet contre la source) et que les mêmes poids marchaient en HF fp32/fp16 et openai-whisper.

**Cause racine** : nos fine-tunes s'entraînent sur du texte **sans tokens de timestamp** → le modèle « oublie » la prédiction temporelle (oubli catastrophique, proportionnel à la durée du fine-tuning : small-ft ~4 epochs cumulées = cassé, medium-ft ~1,2 epoch = encore à peu près calibré). Or le décodage whisper.cpp applique par défaut ses *règles de timestamps* → elles partent en vrille avec ces probabilités dégénérées, et le fallback température « maquille » l'effondrement en hallucination fluide.

**Fix** : toujours décoder les fine-tunes avec `no_timestamps=True` (pywhispercpp) / `isNoTimestamps: true` (plugin Flutter whisper_ggml — **l'app le fait déjà**). Avec ce flag, small-ft GGML transcrit parfaitement.

Diagnostic éliminé au passage : overflow f16 (aucun poids > 65504), sensibilité précision (HF-f16 parfait), bug d'écriture GGML (diff binaire vierge), bug whisper.cpp small (le small officiel marche), LiteRT/TFLite (bug multilingue connu, écarté).

## Qualité dataset : désalignement des clips `_assajda` — cause trouvée et réparée (2026-07-04)

**Signalé par l'utilisateur** (« les récitateurs ne se trompent pas de texte, c'est forcément notre pipeline ») — analyse confirmant : la cause n'est PAS le récitateur ni le site source, mais **notre propre script** `download_assajda.py`. `split_by_verse_uniform()` découpe chaque sourate MP3 en tranches de **durée strictement égale** (`total // n_verses`) au lieu de suivre les frontières réelles des versets (qui varient en longueur). Résultat : dérive cumulative sur toute la sourate → le fichier nommé « verset 107 » contient en réalité un verset proche mais différent (ex. `SaberAbdulHakam_assajda/26_107.wav` = texte réel de 26:98 ; `MohamedKantaoui_assajda/11_19.wav` = texte réel de 11:17). Sur un échantillon de 800 clips, **89 % étaient touchés** (~135k clips sur 151 787).

**Réparation** (`benchmark/realign_assajda.py`) : les MP3 sourates complets ont été conservés sur disque (`data/train/{reciter}/*.mp3`) → ré-alignement forcé propre plutôt que ré-téléchargement :
1. MP3 sourate → WAV 16kHz (ffmpeg).
2. Émissions CTC par chunks **chevauchants** de 30s (recouvrement 2s, bords rognés) via `jonatasgrosman/wav2vec2-large-xlsr-53-arabic` (GPU fp16).
3. `torchaudio.functional.forced_align` du texte complet de la sourate (mots séparés par le token `|`) contre les émissions → frame de début/fin par mot → frontières verset au midpoint.
4. **Bismillah fantôme** : ajoutée en tête des tokens cibles (sourates ≠ 1, 9) car récitée à l'oral mais absente du texte cible — sans cet ancrage elle se fait absorber par le verset 1 (cause du score bas observé sur les versets d'ouverture).
5. Ré-écrit les WAV versets + `train_{reciter}.jsonl` (champ `align_score` = log-prob moyen, exploitable comme filtre cheap plus tard).

**Piège de validation** : le WER (mot-à-mot) comme métrique de QA est **trompeur ici**, dans les deux sens :
- **Whisper-small-ft** (auto-régressif) *hallucine* sur des versets courts isolés sans contexte (dérive vers un autre passage du Coran) → faux négatifs massifs (WER médian mesuré 0,83 sur données en réalité correctes).
- **CTC brut** (juge indépendant, non spécialisé Coran) fait des confusions lettre-à-lettre (hamza, alef) qui comptent un mot entier comme faux → WER médian 0,60 alors que le contenu est juste.
- **Fix** : comparer en **similarité caractère** (`1 - levenshtein/maxlen`) plutôt qu'en WER mot-à-mot → signal propre : **similarité médiane 0,82, 95 % ≥ 0,6** sur l'échantillon test (338 clips, sourates 12 et 26). Les pires cas restants sont les **lettres disjointes (muqatta'at)** en verset 1 (`الٓر`, `طسٓمٓ`, ~29 sourates sur 114) — limite ASR connue et marginale, pas un vrai désalignement.

**Résultat final (2026-07-04)** : réalignement complet des 37 récitateurs `_assajda`, **141 899 clips réalignés sur 151 787 (93,5 % de couverture)**, **zéro crash forced_align** sur l'ensemble du run (grâce à la version proportionnelle simple, groupage par budget de caractères qui se referme sur tout verset individuellement trop long — ex. 2:282, le plus long verset du Coran — sans jamais faire déraper la taille d'un groupe). QA élargi de confirmation (600 clips, 5 récitateurs distincts) : **similarité caractère médiane 0,79**, cohérent avec les tests par sourate individuelle (0,79-0,82).

Note technique : une piste d'« ancrage séquentiel » (chaque groupe démarre où le précédent s'est arrêté, pour éviter la dérive proportionnelle sur les très longues sourates comme Al-Baqarah) a été tentée puis **abandonnée** — elle a en fait dégradé la qualité (similarité tombée à 0,24 avec un réglage trop agressif) y compris sur des sourates moyennes qui fonctionnaient bien avant. La version simple (estimation proportionnelle pure, marge 30 %) reste la plus fiable ; les très longues sourates (Al-Baqarah et consorts) ont une qualité mesurée plus faible (~0,4-0,5) mais restent traitées sans crash — filtrage possible via le champ `align_score` en aval si besoin.

`manifest_unified.jsonl` reconstruit : **404 679 clips** (262 780 EveryAyah/Tarteel inchangés + 141 899 assajda réalignés, tag `reciter` conservé, champ `align_score` ajouté). Manifests NeMo régénérés : **375 621 train / 19 770 val**.

## Nettoyage YouTube (même diagnostic, même remède) — 2026-07-04

Filtrage WER complet des 13 562 clips YouTube (juge whisper-small-ft, seuil 0,7) :

| | |
|---|---|
| Clips propres (WER ≤ 0,7) | 3 371 |
| Clips rejetés (WER > 0,7) | 10 191 (75 %) |
| Fusionnés dans `manifest_unified.jsonl` | +2 470 |

**Dataset final 100 % nettoyé** : `manifest_unified.jsonl` = **407 149 clips**. Manifests NeMo finaux : **377 967 train / 19 894 val**.

## Décision méthodologique importante : pas de warm-start sur le prochain training

`whisper-small-ft` (14,85 % WER) a été entraîné sur `manifest_unified.jsonl` **avant** la correction assajda — donc avec ~34 % de paires audio/texte contradictoires dans son training (l'ensemble de test `test_voice_full.jsonl` est en revanche 100 % propre, composé uniquement de récitateurs EveryAyah `Hani_Rifai`/`Yasser_Ad-Dussary`/`Abdul_Basit_Mujawwad`, jamais affectés — le chiffre 14,85 % est donc fiable en tant que mesure, juste obtenu via un entraînement partiellement contaminé).

**Décision (utilisateur)** : ne pas reprendre les poids de ce checkpoint contaminé. Prochain entraînement whisper-small **depuis le modèle de base** (`openai/whisper-small`), sortie dans un nouveau dossier (`models/whisper-small-ft-clean`), sur le dataset désormais 100 % propre. Attendu : amélioration mesurable sous 14,85 % (probable mais pas garantie — voir discussion dans l'historique de session), à confirmer empiriquement.

## Recherche CTC état de l'art (2026-07-04)

Recherche menée suite à une bascule déjà actionnable trouvée en cours de route : le modèle de base FastConformer utilisé jusqu'ici (`..._pc_v1.0`, Punctuation+Capitalization) a **0 token diacritique sur 1024** dans son vocabulaire BPE (vérifié directement via inspection du tokenizer NeMo) — il ne peut donc *structurellement* jamais produire de harakat correctes, quelle que soit la qualité des données. La variante `..._pcd_v1.0` (+Diacritics) a **137/1024 tokens harakat** et annonce 6,55 % WER zero-shot sur EveryAyah (domaine coranique) — confirmé en sanity check local : la sortie zero-shot contient déjà les harakat complètes et colle de très près à la référence. **Tous les entraînements CTC précédents (plateau 43-46 % WER) étaient donc plafonnés par un choix de modèle de base, pas seulement par les données contaminées.** Bascule faite, entraînement relancé sur `pcd` (`models/fastconformer-quran-pcd`).

Au-delà de cette bascule, l'état de l'art CTC actuel pertinent pour ce projet :

- **Self-conditioned CTC / InterCTC** (Nozaki & Komatsu 2021, repris largement depuis) : ajoute une perte CTC sur une couche intermédiaire de l'encodeur, et réinjecte cette prédiction intermédiaire dans les couches suivantes — casse partiellement l'hypothèse d'indépendance conditionnelle propre à CTC, gain mesuré sans coût d'inférence. **Directement supporté par NeMo** (aucun code custom requis) :
  ```yaml
  model:
    interctc:
      loss_weights: [0.3]
      apply_at_layers: [8]   # ex. pour un encodeur à ~17-18 couches
  ```
  Piste concrète pour une prochaine itération d'entraînement si le `val_wer_ctc` du run `pcd` plafonne encore.
- **CR-CTC** (Consistency Regularization on CTC, 2024) : deux vues augmentées (SpecAugment différent) du même spectrogramme, on force la cohérence entre les deux distributions CTC produites. Réduit le sur-confiance/« pic » typique de CTC (une des faiblesses connues face à RNNT/attention), gains rapportés sur plusieurs benchmarks. Plus intrusif à implémenter que InterCTC (nécessite double forward pass) — à garder en réserve si InterCTC ne suffit pas.
- **Zipformer** (2023, toujours la référence 2025-2026) : encodeur U-Net-like à fréquences d'images variables par bloc, ~2× moins de FLOPs/mémoire que Conformer à qualité égale ou supérieure. Changerait l'architecture d'encodeur elle-même (pas un simple flag) — pertinent seulement si on réentraîne un modèle from-scratch plutôt que de fine-tuner FastConformer.
- **Cache-aware streaming CTC** (confirmé lors de la recherche précédente, toujours d'actualité) : config NeMo officielle `fastconformer_ctc_bpe_streaming.yaml`, chunks configurables (80/160/560/1120 ms côté Nemotron-ASR-Streaming anglophone, architecture équivalente). Aucun checkpoint arabe pré-entraîné public — à convertir depuis notre propre fine-tune `pcd` une fois la qualité non-streaming validée.
- **Insight architectural le plus utile pour l'app** : la littérature sur le *keyword spotting en flux avec alignement CTC* (ex. "CTC-aligned Audio-Text Embedding for Streaming Open-vocabulary KWS", Interspeech 2025 W-CTC) traite un problème structurellement plus proche du nôtre que la transcription libre. Notre besoin réel (suivi mot-à-mot en direct + arrêt immédiat sur erreur) n'est **pas** de la transcription ouverte suivie d'un diff texte — c'est de la **vérification contre un texte de référence connu à l'avance** (le verset). Cadrage à privilégier pour l'implémentation future : à chaque frame, aligner l'émission CTC contre les tokens du mot attendu (comme un forced-align incrémental) et détecter la divergence par chute du score d'alignement, plutôt que décoder puis comparer des chaînes. Plus robuste au bruit CTC lettre-à-lettre (déjà observé dans ce projet lors du QA du réalignement assajda) et nativement plus rapide (complexité O(longueur du mot attendu), pas O(vocabulaire complet)).

## Décisions actées (résumé)
1. **whisper-medium-ft = modèle de production ASR**, déployé on-device via whisper.cpp/GGML (WER ~11 %).
2. **whisper-small-ft v2 terminé (14,85 % WER)** — nette amélioration vs v1 (18,3 %) grâce au dataset unifié (78 récitateurs). **Export GGML validé (466 Mo, 3,2× plus léger que medium)** après résolution du piège `no_timestamps` — candidat sérieux pour remplacer medium on-device (6 Go RAM), à comparer en usage réel.
3. **FastConformer CTC** : plafond historique (43-46 % WER) attribué à un choix de modèle de base sans tokens diacritiques (`pc`) — bascule vers `pcd` (137 tokens harakat), nouveau training en cours sur données propres. L'idée CTC reste valable pour un futur aligneur karaoké et pour la vérification mot-à-mot en direct.
4. **Nemotron-3.5** écarté (perd au benchmark + non fine-tunable ici).
5. **Alignement karaoké** : 2 candidats validés en test isolé (MMS-300M, wav2vec2-arabe natif), intégration app pas encore faite.
