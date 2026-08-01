# État du training NeMo FastConformer CTC — inventaire des modèles & reste à faire

Document de synthèse rédigé le 2026-07-19 pour consolider en un seul endroit
l'historique complet de la piste **NeMo FastConformer CTC** (récitation
coranique) : quels modèles existent, ce qu'ils valent, ce qui est déployé
réellement, et ce qui reste ouvert. Compile `benchmark/BENCHMARK_RESULTS.md`,
`.claude/skills/model-training/references/asr.md`, `FONCTIONNALITES_FUTURES.md`,
`HANDOFF.md`/`HANDOFF_UBUNTU.md`/`HANDOFF_UBUNTU_TRAINING.md`, et une relecture
directe des logs/scripts du 16-19 juillet non encore reportés dans ces
fichiers. Ne remplace aucun d'eux — c'est une vue d'ensemble, pas une nouvelle
source de vérité (`asr.md` reste la mémoire technique de référence).

---

## 1. Principe commun à tous les runs

- **Base** : `nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0` (hybride
  RNNT+CTC, encodeur Conformer `rel_pos` pré-entraîné, **137/1024 tokens
  harakat** — condition nécessaire pour produire des diacritiques, la variante
  `pc` sans `d` n'en a aucun et plafonne structurellement). L'encodeur n'est
  **jamais** réinitialisé (c'est pour ça que `val_wer_ctc` démarre déjà autour
  de 0,19-0,25 dès l'epoch 0 sur un nouveau vocabulaire).
- **CTC-only** : la tête RNNT est gelée (`_ZeroRNNTLoss`, gradient nul) —
  contournement d'un blocage NVVM (`warprnnt_numba`) sous Windows. Seule
  `val_wer_ctc` est une métrique valide ; `val_wer` (sans suffixe) reste bloqué
  ~40-100% et doit être ignoré partout (checkpoints, logs).
- **Script principal** : `benchmark/finetune_fastconformer.py` (et ses
  variantes `_augmented.py`, `_lora.py`, `_noonnx.py`).
- **Chaque changement de vocabulaire** (tajweed, mixed) réinitialise la tête
  CTC via `change_vocabulary` — le reste de l'encodeur est repris tel quel.

---

## 2. Inventaire des modèles (`benchmark/models/fastconformer-quran-*`)

| Dossier | Base vocab | Dataset | Meilleur `val_wer_ctc` | Statut |
|---|---|---|---|---|
| `fastconformer-quran` (pc, historique) | `pc` (0 token harakat) | dataset non filtré Warsh/Hafs | 0,43-0,46 (plafond) | **Abandonné** — plafond structurel du vocab `pc`, cause racine identifiée a posteriori |
| `fastconformer-quran-pcd` | `pcd` | dataset non filtré Warsh/Hafs (contaminé, ~21% Warsh) | ~2,5% (interne) | Ancien modèle déployé (avant 07-16) ; contamination Warsh découverte après coup, n'a jamais été corrigée pour ce run |
| `fastconformer-quran-clean` | `pcd` | tentative dataset nettoyé | non documenté en détail | Existe sur disque, peu de traces dans les mémoires — à considérer comme exploratoire |
| `fastconformer-quran-augmented` | `pcd` | dataset + augmentation (SpecAugment etc.) | 0,219-0,223 (interne), mais mesuré contaminé Warsh a posteriori | Superseded par `tajweed-augmented` |
| `fastconformer-quran-tajweed` | tokenizer **tajweed** dédié (BPE 1024, garde wasla/dagger alif/maddah/waqf/sajda) | `nemo_manifests_tajweed/` (284 823 train / 14 991 val, Hafs-only visé — **filtre Hafs jamais confirmé appliqué à ce manifest précis**, cf. §6) | epoch 9 → **0,058** | Run de base tajweed — repris ensuite par `tajweed-v2` |
| `fastconformer-quran-tajweed-augmented` | tokenizer tajweed | idem + augmentation | epoch01 **0,032 (artefact de mesure, invalide — glitch resume/CUDA graphs)**, epoch06 **0,055 (réel, confirmé par benchmark externe)** | **Déployé dans l'app le 2026-07-16** (epoch06), remplaçant `pcd`. Gain net sur test YouTube, mais perd face à `pcd` sur généralisation Warsh (compromis assumé) |
| `fastconformer-quran-tajweed-v2` | tokenizer tajweed | reprise du run `tajweed` (pas `augmented`) depuis `epoch=09-val_wer_ctc=0.058.ckpt` | epoch 9-10 → **0,056** (meilleur retenu ; un `0,013` transitoire jugé non fiable) | Arrêté volontairement (SIGTERM) à 89% d'epoch 10, jamais déployé tel quel — **exporté en `.nemo` pour servir de point de départ à `tajweed-mixed`** |
| `fastconformer-quran-tajweed-mixed` | tokenizer tajweed | `nemo_manifests_mixed/` — voir §3 | epoch14 → **0,123-0,124** (WER élevé car dataset volontairement diversifié, pas comparable directement aux WER précédents) | **C'est le modèle réellement déployé sur le téléphone aujourd'hui** (epoch14, malgré le nom de dossier device `mixed-e02`, cf. §4) |
| `fastconformer-quran-personal` | pcd/tajweed | clips utilisateur vérifiés | — | Mini-LoRA v1 PC-assisté (personnalisation voix niveau 3), fonctionnel mais nécessite un export manuel des clips (pas de sync automatique) |

---

## 3. Le chantier "mixed" — pourquoi il existe (biais canonique)

Constat déclencheur (§8 de `FONCTIONNALITES_FUTURES.md`, confirmé sur device) :
le modèle **corrige silencieusement** les vraies erreurs de récitation vers le
texte canonique (ex. l'utilisateur dit `الحمدِ` par erreur, le modèle finit par
transcrire `الحمدُ` une fois qu'il a plus de contexte) — parce qu'il n'a
**jamais vu, à l'entraînement, une seule récitation volontairement fautive**.
Diagnostic confirmé le 16/07 (`build_mixed_manifest.py`) : les 4 manifests
tajweed précédents contenaient **284 823 clips, 0% d'erreur** (l'augmentation
TTS de 18 084 clips avait même été perdue lors d'une reconstruction du 12/07).

**Composition du nouveau manifest** (`nemo_manifests_mixed/train_mixed.jsonl`,
131 882 lignes) :
- Coran sous-échantillonné (~150h, anti-oubli/replay).
- **Arabic Speech Corpus × 10** (~38h) — vraie voix humaine arabe non
  coranique vocalisée, aucun prior canonique possible.
- **TTS × 5** (~48h, 18 084 clips sources) — erreurs synthétiques délibérées
  (confusions sin/sad, harakat). Limite documentée : la voix TTS est corrélée
  à 100% avec la présence d'une erreur dans ces clips → risque que le modèle
  apprenne "voix synthétique = j'écoute, vraie voix = je corrige" plutôt que la
  vraie leçon (d'où l'ASC en contre-mesure).
- `val_canonical.jsonl` (14 991), `val_errors.jsonl`/`val_errors_annotated.jsonl`
  (1 988 chacun), `val_mixed.jsonl` (3 976).

**Progression mesurée** (`benchmark/eval_error_detection.py`, taux de
détection d'erreur / taux de "correction canonique invisible" / CER) :

| Checkpoint | Détection erreur | Erreur ratée | CER |
|---|---|---|---|
| baseline (tajweed-v2, pré-mixed) | 18,7% | 28,7% | 9,03% |
| mixed epoch02 | 52,7% (ou 57,3% selon la source — écart non résolu, cf. §6) | 18,0% | 10,05% (ou 9,46%) |
| mixed epoch05 | 60,0% | 15,3% | 9,31% |
| **mixed epoch14 (déployé)** — mesuré le 2026-07-19, n=150 | **65,3%** | **14,7%** | **9,18%** |
| mixed epoch14 (déployé) — n=400 (échantillon plus large, même run) | 65,0% | 17,5% | 6,27% |

**Mesuré le 2026-07-19** (comblant le trou signalé précédemment) via
`eval_error_detection.py` sur `mixed-e14-snapshot.nemo`, en corrigeant au vol
les chemins des manifests (`nemo_manifests_mixed/val_errors_annotated.jsonl` /
`val_canonical.jsonl` pointent vers `/mnt/ssd5`/`/mnt/hdd`, chemins absolus
d'une autre machine — remap vers les chemins réels de cette machine
`/media/kafai/NouveauNom/...` et `/run/media/kafai/HDD/...`, sans modifier les
fichiers du dépôt). Confirme la tendance continue d'amélioration jusqu'à
epoch14 sur les 3 métriques (n=150, directement comparable aux lignes
précédentes). Détail par type (n=150) : `letter` nettement mieux détecté que
`harakat` (~55-56% de fidélité sur harakat, quasi la limite déjà observée par
le rescoring GOP à epoch02 — la piste harakat reste la plus faible).

**Écart CER 9,18% (n=150) vs 6,27% (n=400) non résolu** — le script prend les
N premières lignes du manifest sans mélanger ; les 150 premiers clips
canoniques ne sont donc pas un sous-échantillon aléatoire des 400, simple
artefact d'ordre de fichier, pas un vrai désaccord de mesure. Le chiffre n=150
reste la référence pour comparer aux lignes précédentes du tableau (même
protocole d'échantillonnage).

---

## 4. Déploiement réel dans l'app — écart nom/contenu à connaître

`app/lib/services/fastconformer_verifier.dart:120` :
```dart
static const _kModelSubdir = 'models/fastconformer-ctc-mixed-e02';
```
Le nom du dossier et le commentaire du fichier (justification pour "epoch 2")
sont **obsolètes** : d'après `HANDOFF.md` §2, le contenu réel du dossier a été
remplacé par le checkpoint **epoch 14** (`val_wer_ctc≈0,1234`) sans renommer
le dossier ni mettre à jour le commentaire ("plus simple de garder le nom et
remplacer le contenu"). **Le modèle qui tourne aujourd'hui sur le téléphone
est donc epoch14, pas epoch2** — à corriger (au moins le commentaire, idéalement
aussi le nom de dossier côté device) pour éviter une confusion future.

Scripts d'export de ce checkpoint (**tous non commités** au 19/07) :
`benchmark/ckpt_to_nemo_epoch14.py`, `benchmark/build_word_token_lookup_mixed_e14.py`,
`benchmark/validate_epoch14_local.py`.

---

## 5. Pistes de post-traitement testées en parallèle (16-17/07)

Deux idées pour compenser les limites du décodage CTC greedy pur, testées et
tranchées différemment :

### a) Rescoring tête-à-tête (NLL canonique vs NLL prononcé)
`benchmark/variant_rescoring_eval.py` — compare la loss CTC du texte canonique
contre celle du texte réellement prononcé (au lieu du GOP forced-vs-free jugé
aveugle sur certaines fautes). Après correction d'un bug initial (WAV TTS à
24kHz au lieu de 16kHz, faussant un premier essai à 0%) : **letter 80,8%
(690/854), harakat 49,6% (quasi hasard), total 64,3% → verdict GO** (seuil
>75% atteint sur "letter").

**Branché dans l'app le 2026-07-19** (`ConfusableVariants.kt`,
`ForcedAligner.ctcForwardNll`/`WordResult.rescoreMargin`,
`FastConformerCtcPlugin.setRescoringEnabled`, `AlignedWord.rescoreMargin` côté
Dart) — **désactivé par défaut**, signal **diagnostique uniquement** (loggé
dans `[GOP] ... rescore=...`), **ne participe pas au verdict** `judged`
(`recitation_provider.dart`) : le seuil τ n'est pas calibré en conditions
device réelles (cf. mesures §5a-bis ci-dessous, marge par-fenêtre-de-mot
différente de la marge par-clip-isolé validée offline). Activer via
`FastConformerVerifier.setRescoringEnabled(true)` une fois un seuil choisi.

#### a-bis) Version "aveugle" du rescoring : décodage contraint par variantes générées

`benchmark/constrained_decoding_eval.py` (2026-07-19) — différence avec (a) :
au lieu de comparer NLL(canonique) à NLL(ce qui a été *réellement* prononcé,
connu du holdout), on énumère à l'avance toutes les variantes confusables à 1
édition du mot **attendu seul** (harakat substituées + confusions de lettres
apprises du corpus TTS, `ConfusableVariants.kt` côté app) et on élit celle qui
explique le mieux l'audio — c'est exactement ce que fera l'app en production
(le mot réellement dit n'est jamais connu à l'avance).

**Test A — détection sur `val_errors_annotated.jsonl` (1808 clips fautifs,
mixed-e14)** : identification du mot exact parmi les candidats — **82,1%
letter, 45,0% harakat** (total 62,5%) ; détection qu'*une* variante bat le
canonique (τ=0, seuil le plus permissif) — **91,3% letter, 75,7% harakat**.

**Test B — faux positifs sur `val_canonical.jsonl` (150 versets corrects)** :
à τ=0, **77,9% des versets** ont au moins une variante qui bat le canonique à
tort (2,77% des candidats individuels). Le compromis τ mesuré :

| τ | détection letter | détection harakat | versets flagués à tort |
|---|---|---|---|
| 0 | 91,3% | 75,7% | 77,9% |
| 3 | 78,3% | 54,5% | 59,7% |
| 8 | 39,2% | 25,1% | 40,3% |
| 20 | 4,6% | 1,9% | 8,7% |

**Lecture** : aucun τ unique n'offre un compromis net (à τ=20, faux positifs
bas mais détection quasi nulle) — la marge par-fenêtre-de-mot bruite
davantage que la marge par-clip-isolé du test (a) (mot isolé, silence propre
en début/fin, meilleure conditions). **Ne PAS calibrer τ sur ces seuls
chiffres offline** : ils bornent l'ordre de grandeur, pas un seuil prêt à
déployer — nécessite une calibration sur clips device réels (bruit ambiant,
frontières de mots moins nettes que dans un holdout TTS synthétique) avant
d'envisager d'activer `setRescoringEnabled` en production ou de faire
participer `rescoreMargin` au verdict.

### b) Global-match (validation globale avant fragmentation mot-par-mot)
`benchmark/global_match_eval.py` — idée : valider un fragment entier quand le
décodage libre colle au texte attendu, ne fragmenter (`ForcedAligner`
mot-par-mot) que si mismatch. Résultat sur vrais négatifs : **109/150 (72,7%)**
validés sans fragmentation. **Cette piste a été adoptée et implémentée** —
commit `3fb04c3` ("Corrige la troncature per-mot via validation globale",
16/07, le plus récent du dépôt) : corrige un bug réel de troncature per-mot
observé sur device. Marqué **"à tester en conditions réelles sur device"** dans
le commit — pas encore confirmé en usage réel.

---

## 6. Ce qui reste à faire (consolidé)

### Mesure / validation (bloquant avant de considérer "mixed" stable)
- ~~Chiffrer epoch14 avec `eval_error_detection.py`~~ **Fait le 2026-07-19**
  (cf. §3) : 65,3% détection / 14,7% erreur ratée / CER 9,18% (n=150) —
  confirme la tendance continue d'amélioration, harakat reste le point faible.
- **Vérifier si un training plus récent existe côté Ubuntu** (`HANDOFF.md`
  §2 signale qu'un training a continué là-bas depuis, sans confirmation locale
  possible depuis cette machine/copie du repo).
- **Résoudre l'écart de chiffres epoch02** (52,7% vs 57,3% détection, 10,05%
  vs 9,46% CER — deux sources donnent des valeurs différentes, non tranché).
- **Confirmer le global-match (commit `3fb04c3`) en usage réel sur device** —
  marqué "à tester" au moment du commit.
- ~~Vérifier si `nemo_manifests_tajweed/` utilise bien le manifest Hafs-only~~
  **Vérifié le 2026-07-26** (question ouverte depuis le 12/07, jamais
  tranchée) : croisement direct des noms de dossier réciteur présents dans
  `nemo_manifests_dual/{train,val}_manifest.jsonl` (lignée
  `tajweed → mixed → rules → dual`, utilisée pour l'entraînement causal
  streaming) contre `EXCLUDE_RECITERS` de `build_hafs_only_manifest.py`.
  Résultat : **0 clip** des 21 réciteurs tagués Warsh ni des 2 mal-tagués
  (`HassanSaleh_assajda`, `AbdulRashidSufi_assajda`). Les clips `_assajda`
  présents (9 479 train / 315 val) proviennent exactement des 12 réciteurs
  vérifiés Hafs page par page (`AbdallahMatroud`, `SaberAbdulHakam`,
  `AlzainMohamedAhmed`, `AbdulWadudHaneef`, `AdelKalbani`, `MustaphaLahouni`,
  `AbdallahKamel`, `KhalidAlJalil`, `MohamedElBarak`, `MohamedMohisni`,
  `AntarMuslim`, `AhmedSaoud`). Manifest propre pour cette lignée.

### Intégration app
- ~~**Rescoring NLL canonique/prononcé** (§5a)~~ **Branché le 2026-07-19**
  (désactivé par défaut, diagnostic uniquement — cf. §5a) : reste à faire,
  **calibrer τ sur clips device réels** (pas seulement le holdout TTS
  offline) avant d'activer ou de le faire participer au verdict.
- **Corriger le nom de dossier / commentaire `_kModelSubdir`** (§4) pour
  refléter epoch14 réellement déployé, éviter une confusion pour un futur
  redéploiement.

### Pistes de qualité identifiées mais non commencées

- 🔴 **Corpus de fragments courts 3-8 s — DEUX methodes essayees, DEUX ont
  echoue (2026-07-31/08-01), rester vigilant avant tout 3e essai.**
  Objectif : combler le trou [0-3 s) mesure ci-dessous en decoupant les
  clips longs reels sur des frontieres de mots. Le probleme n'est PAS de
  decouper -- c'est d'estimer une frontiere de mot FIABLE a l'interieur d'un
  clip.
  **v1 -- proportions externes** (`word_timings_ref.json`, mediane murattal
  quran.com d'AUTRES recitateurs, mise a l'echelle de la duree du clip) :
  WER 37,2 % meme sur des fragments "proprement bornes" (mesure par decodage
  reel + WER norme contre le texte assigne). Purge de 9 recitateurs
  identifies comme mal etiquetes (cf. `recitateurs_exclus.py`) : 37,2 % ->
  36,0 %, quasi aucun effet -- la cause n'etait PAS les donnees sources.
  **v2 -- alignement Viterbi CTC force** (`spans_mots()`, deja dans le
  projet, `banc_regles_gop.py`) : PIRE, 43,3 %. Cause confirmee par
  inspection directe des spans : l'alignement CTC est POINTU par nature (un
  mot mesure a 1 frame quand son voisin en fait 31, pour des mots de longueur
  comparable) -- il marque l'instant de confiance maximale du modele, pas
  l'etendue acoustique du mot. **Ce piege etait DEJA documente** dans ce
  fichier au sujet de `build_confusable_splice_augmentation.py` (2026-07-14,
  commit `2ae8dc7`) : « l'alignement CTC est peaky... a rouvrir seulement
  s'il remplace l'etendue reelle du phoneme ». Verifie avant d'implementer
  la v2, ca aurait evite l'essai.
  **Piste correcte, non tentee** : ne pas utiliser les spans Viterbi comme
  bornes directes -- s'en servir seulement comme REPERES DE POSITION (le pic)
  et reconstruire une frontiere par un modele de duree (ex. elargissement
  symetrique borne sur la duree mediane du mot, ou frontiere au milieu de
  l'ecart entre deux pics voisins plutot qu'au bord du span). Vrai travail
  d'ingenierie, pas une correction de fin de session -- **ne pas relancer un
  3e essai sans ecrire d'abord le protocole de verification AVANT
  generation** (petit echantillon, decodage reel, WER norme -- c'est cette
  etape, sautee pour la v1, qui a permis a 18 Go d'etre generes et
  a moitie entraines sur des donnees fausses avant qu'une verification soit
  demandee).

- 🟡 **Rééquilibrer les durées d'entraînement vers le COURT, pas le long**
  (2026-07-31, demande utilisateur explicite : « plutôt sur des durées plus
  courtes que sur des durées plus longues »). Mesure faite en séparant les
  sources du manifeste `nemo_manifests_dual/train_manifest.jsonl` (156 892
  clips mélangeaient récitation réelle, TTS de phrases fautées et divers — une
  première lecture non séparée donnait une médiane trompeuse de 3,1 s). Sur les
  **59 232 clips de récitation réelle seuls** (`train_wav_local/`) :
  ```
  [ 0- 3s)   2,6 %   <- TROU
  [ 3- 8s)  26,7 %
  [ 8-13s)  22,4 %
  [13-20s)  21,0 %
  [20-30s)  15,4 %   <- filtres par max_duration=20, hors sujet (cf. ci-dessous)
  [30-60s)  11,9 %   <- filtres par max_duration=20, hors sujet
  ```
  Piste initialement envisagée dans le mauvais sens (étendre `max_duration`
  vers 30-60 s pour couvrir la queue filtrée) — écartée par l'utilisateur :
  la chaîne calibrée ce soir vise 6-13 s et évite activement les segments
  longs (garde-fou à 30 s, seuil de pause calibré). Étendre l'entraînement vers
  le long entraînerait un régime que l'app n'expose presque jamais.
  Le vrai trou est **[0-3s), à seulement 2,6 %** — la zone des segments coupés
  en frontière (mot tronqué, phrase amputée en tête). Les seuls clips courts
  en nombre (TTS phrases fautées, 81 380 clips, médiane 1,7 s) sont des **mots
  isolés synthétiques**, pas des fragments naturels de récitation coupée : ni
  la même prosodie, ni le même contexte tronqué.
  **Piste concrète, pas encore lancée** : ré-échantillonner par découpe
  aléatoire (y compris coupes en plein mot, pour imiter ce que la segmentation
  produit vraiment) des 59 232 clips réels existants vers 3-8 s. Aucune
  nouvelle capture nécessaire. Concerne l'entraînement de l'**encodeur**
  (robustesse aux frontières), sans lien avec la tête tajwid en cours ce soir.

**Triage de priorité (2026-07-19, demande utilisateur)** — trois groupes :
🟢 à tester en premier (pas de réentraînement, testable offline tout de suite) ;
🟡 quasi-gratuit mais au bon moment (pas dans le premier run hybride, pour
garder les variables contrôlées) ; 🔴 deuxième lieu (chantier lourd, bloqué,
ou dépendant d'un résultat pas encore obtenu). Les pistes "double tête",
"règles/qalqala" et "RNNT" ne sont plus listées ici : elles sont **absorbées
par `PLAN_ENTRAINEMENT_HYBRIDE.md`**.

- ~~🟢 **Décodage contraint au texte attendu**~~ **Testé le 2026-07-19**
  (`benchmark/constrained_decoding_eval.py`, cf. §5a-bis) : gain réel mais pas
  un GO immédiat en l'état — 82,1%/45,0% (letter/harakat) d'identification
  correcte du mot fautif, mais 77,9% des versets *corrects* auraient au moins
  un faux positif au seuil le plus permissif. **Branché en app comme signal
  diagnostique désactivé par défaut** (`ForcedAligner.rescoreMargin`,
  `setRescoringEnabled`) — reste : calibrer le seuil sur device réel avant
  toute activation ou tout impact sur le verdict.
- 🟡 **InterCTC / self-conditioned CTC** — supporté nativement par NeMo (une
  config YAML `interctc.loss_weights`), gain documenté sans coût d'inférence.
  Quasi-gratuit MAIS ne pas l'empiler dans le premier run hybride (déjà 3
  variables nouvelles : tokenizer règles + RNNT + séquencement 1a/1b — si le
  run déçoit, impossible d'attribuer la cause). À activer au run suivant, ou
  en A/B court après le run hybride.
- 🟡 **N-gram + KenLM au décodage** (shallow fusion) — effort faible, PAS de
  réentraînement, mais ⚠️ **côté localisation/"Suivre une prière" UNIQUEMENT**
  (tête RNNT/transcription libre) : un LM coranique pousse vers le texte
  canonique, exactement le biais que la vérification combat. L'appliquer à la
  tête stricte serait contre-productif — le périmètre fait partie du test.
- 🔴 **CR-CTC** (consistency regularization, double forward SpecAugment) —
  en réserve si InterCTC ne suffit pas (documenté ainsi dès l'origine), ne pas
  tester avant.
- 🔴 **Vérification de la durée du madd** (§1 de `FONCTIONNALITES_FUTURES.md`)
  — attendre le verdict du set humain de violations de règles (Phase 3.2 du
  plan hybride) : si les symboles de règles fonctionnent acoustiquement, le
  madd en profite ; sinon le pivot DSP couvre madd ET qalqala d'un coup.
  Tester avant ce verdict = travailler deux fois.
- 🔴 **Warsh (2e riwaya)** — chantier produit séparé et lourd (texte différent,
  numérotation décalée, ré-alignement forcé) ; rien à y gagner tant que le
  pipeline Hafs n'est pas stabilisé.
- 🔴 **Cache-aware streaming réel** — nécessite un ré-entraînement from-scratch
  (convolutions causales) ; l'architecture par segments fonctionne en attendant.
  Ne rouvrir qu'en cas de besoin produit fort de latence sub-seconde.
- **Mini-LoRA v3 "vraiment on-device"** (ONNX Runtime Training) — **non
  viable confirmé** (crash du gradient-builder sur l'attention `rel_pos`,
  indépendant de l'OS) ; rester sur le mini-LoRA v1 PC-assisté sauf
  changement d'architecture (abs_pos), lui-même écarté (jetterait le
  pré-entraînement de l'attention).
- **Dégeler la tête RNNT (entraînement hybride complet, pas CTC-only)** —
  **piste OUVERTE et désormais DÉBLOQUÉE techniquement** (décision utilisateur
  2026-07-19 : ne fermer aucune piste tant que le retour en arrière reste
  possible — et il l'est : le `.nemo` de base hybride est intact, chaque run
  va dans son propre dossier, aucun checkpoint n'est écrasé).

  **Déblocage réalisé le 2026-07-19** (historique : l'hypothèse "le blocage
  NVVM disparaît sous Linux" était fausse telle quelle — le blocage existait
  aussi sous Ubuntu, mais pour une cause réparable : `libnvvm.so` absent du
  système, pas un problème d'OS). Chaîne complète validée :
  1. **Wheel `nvidia-cuda-nvcc-cu12==12.8.93`** installé dans
     `.venv_nemo/lib/python3.14/site-packages` (⚠️ `pip --target` saute les
     fichiers si le dossier `nvidia/` existe déjà — extraire le wheel
     manuellement par zipfile dans ce cas).
  2. **Deux symlinks requis** (numba ne trouve pas les libs sinon) :
     `nvidia/cuda_nvcc/nvvm/lib64/libnvvm.so.4 → libnvvm.so` (le regex de
     numba exige un nom **versionné**, le `.so` nu ne matche pas) et
     `nvidia/cuda_nvcc/lib64 → ../cuda_runtime/lib` (numba cherche
     `libcudart` dans `CUDA_HOME/lib64`, le wheel n'a qu'un `lib`).
  3. **Variable d'env au lancement** :
     `CUDA_HOME=$SITE/nvidia/cuda_nvcc` (numba ne lit ni
     `NUMBA_CUDA_NVVM` ni `LD_LIBRARY_PATH` pour ça, uniquement
     `CUDA_HOME`/`CUDA_PATH` sur cette version).
  4. **Patch local NeMo** (`nemo/.../rnnt_loss/utils/cuda_utils/gpu_rnnt_kernel.py`,
     3 blocs identiques) : `min(g, clamp)`/`max(g, -clamp)` dans un kernel
     CUDA crashent avec numba 0.66 + Python 3.14 ("Signature mismatch: 2
     argument types given, but function takes 1") — bug numba reproduit sur
     kernel minimal, contourné par des comparaisons `if` explicites,
     sémantique identique. Patch commenté dans le fichier, **dans le venv
     seulement** (perdu si réinstallation de NeMo — à réappliquer, chercher
     "PATCH LOCAL" dans ce fichier).
  5. Note GPU : le RTX 5080 (CC 12.0, Blackwell) n'est pas dans la liste des
     architectures de numba 0.66 (max 9.0) — le PTX compute_90 est
     JIT-recompilé par le driver, fonctionne (validé), pas une erreur.

  **Validation** : (a) test synthétique `RNNTLoss` forward+backward GPU OK ;
  (b) **smoke test sur le vrai modèle** (`mixed-e14-snapshot.nemo`, vrai clip
  de `val_canonical`) : loss hybride 0.7·RNNT + 0.3·CTC, backward complet,
  gradients non-nuls sur l'encodeur, le decoder RNNT et le joint. Valeurs
  observées cohérentes avec le diagnostic : **loss CTC = 0,22** (tête
  entraînée) vs **loss RNNT = 1041** (tête vierge — confirme qu'elle n'a
  jamais rien appris et qu'un entraînement hybride repart de zéro sur cette
  branche). Script : scratchpad `smoke_hybrid_rnnt.py` (session 2026-07-19).

  **Rollback complet possible** : supprimer `nvidia/cuda_nvcc*` du venv +
  annuler le patch (ou simplement ne pas définir `CUDA_HOME` : sans elle, le
  mode CTC-only fonctionne exactement comme avant, le patch est inerte).
  Aucun checkpoint, aucun script du dépôt modifié.

  **Contraintes/risques pour le futur run hybride** :
  - **VRAM** : la loss RNNT matérialise un tenseur B×T×U×V — nettement plus
    gourmand que CTC sur ce GPU 16 Go ; prévoir un `batch_size` réduit (et ne
    pas cumuler avec la 2e tête CTC dans le même run si ça coince — séquencer).
  - **Risque documenté si la sortie RNNT est un jour DÉCODÉE** (pas seulement
    entraînée) : le prediction network RNNT est un modèle de langage interne
    plus fort que le CTC — il pourrait aggraver le biais "correction vers le
    canonique" que le chantier mixed combat. Test de validation obligatoire
    avant tout usage produit : comparer transcription CTC vs RNNT sur
    `val_errors_annotated.jsonl` (protocole `eval_error_detection.py`).
    L'alignement mot-par-mot (`ForcedAligner`) reste sur la tête CTC dans
    tous les cas.
  - Le script `finetune_fastconformer.py` actuel force `_ZeroRNNTLoss` — un
    run hybride demande une variante (ou un flag `--rnnt`) qui garde la vraie
    loss et pondère `ctc_loss_weight` (ex. 0.3), non écrite à ce jour.
- **2e tête CTC "relâchée" (strict tajweed / tolérant) sur l'encodeur partagé**
  — idée du 2026-07-12 (`HANDOFF_UBUNTU_TRAINING.md` §5), **distincte de la
  tête RNNT native** (le modèle final viserait 3 têtes : RNNT native + CTC
  tajweed strict + CTC normalisé tolérant). La 2e tête CTC peut s'ajouter
  **après coup** sur l'encodeur gelé (une couche linéaire 512→vocab,
  entraînement rapide, pas de ré-entraînement complet) ; exporter en un seul
  graphe ONNX multi-sorties (surtout PAS deux modèles séparés qui
  dupliqueraient l'encodeur ~458 Mo chacun).

### Hygiène de dépôt
- **Rien n'est commité depuis le 16/07** sur la partie training (scripts
  epoch14, `nemo_manifests_mixed/`, etc.) ni sur l'app — `HANDOFF.md` recommande
  de vérifier le périmètre avec l'utilisateur avant de committer en bloc
  (l'app et le benchmark ont des cycles de vie différents).

---

## 7bis. Tête tajwid MULTI-LABEL (2026-07-24) — remplace le CTC+softmax

### Diagnostic (chaîne complète, cf. session du 24/07)

Mesure device décisive : sur ٱلنَّاسِ (114:2, نّ doublé + assimilation du
lam), la tête tajwid (CTC+softmax+blank, 18 classes) ne détectait JAMAIS
`ghunnah` ET `laam_shamsiyah` en même temps — un log `[TAJWID]` montrait
`emises=laam_shamsiyah` puis `emises=` (vide) selon la passe, jamais les
deux. Cause : les deux règles se réalisent sur les MÊMES frames (le lam
s'assimile littéralement dans le noun doublé), mais un softmax partagé
FORCE une seule classe gagnante par frame — l'autre ressort "non détectée"
par construction, quelle que soit la prononciation réelle. Confirmé dans le
code d'entraînement (`finetune_dual_head.py::_tajwid_loss`, `F.ctc_loss`
avec cible séquentielle ordonnée) et dans l'annotation source (`uthmani_tajweed.jsonl`,
`<laam_shamsiyah>ل</laam_shamsiyah><ghunnah>نّ</ghunnah>` — deux lettres
adjacentes, positions distinctes, mais acoustiquement fusionnées).

### Fix : sigmoïde indépendante par classe

- **Labels** : `build_frame_level_tajwid_labels.py` (nouveau) — dérive une
  fenêtre de FRAMES par règle (alignement forcé de la tête 1, ±1 frame de
  marge) au lieu d'une séquence positionnelle. Sortie :
  `nemo_manifests_dual/tajwid_frame_spans_{train,val}.jsonl`. Ajoute aussi
  `waqf_lazim`/`waqf_awla` (positions déjà connues via
  `app/assets/data/quran_waqf.json`, fenêtre = silence réel détecté après le
  mot — cf. FONCTIONNALITES_FUTURES.md §9). **19 classes au total**
  (17 régles tajwid + 2 waqf), plus de blank.
- **Loss** : `finetune_dual_head.py::_tajwid_loss` réécrite en
  `F.binary_cross_entropy_with_logits` par frame par classe, indépendante
  (remplace `F.ctc_loss`). `pos_weight` par classe calibré par
  `calibrate_tajwid_pos_weight.py` (sqrt de l'inverse-fréquence, plafonné à
  15 — idée utilisateur : atténuer l'impact des classes dominantes comme
  `ham_wasl` sans laisser les classes rarissimes comme `waqf_lazim` — 318
  frames positives sur tout le corpus — exploser la loss).
- **Tête** : `ConvTajwidHead(..., N_RULES)` (plus de `+1` pour le blank).
- **Export** : `export_dual_head_multilabel.py` (nouveau, remplace
  `export_dual_head_checkpoint.py` pour cette lignée) — sortie
  `tajwid_logprobs` = `logsigmoid(logits)` par classe, indépendant.
- **Kotlin** : `FastConformerCtc.kt::decodeTajwid` réécrit (seuil
  `logsigmoid > 0` = proba > 50%, par classe indépendamment, collapse de
  plateau par classe — plus d'argmax global). `ForcedAligner.kt::tajwidGop`
  simplifié : le meilleur logsigmoid PROPRE à chaque classe sur la fenêtre du
  mot (plus de marge compétitive "score - meilleure autre classe", qui n'a
  plus de sens hors softmax). Garde-fou `-inf` → `-50f` (underflow ONNX de
  `logsigmoid` sur les classes très confidemment absentes, mesuré `ecart
  tajwid=inf` PyTorch/ONNX lors de la validation d'export — sans impact sur
  le seuil, mais à plafonner avant tout calcul aval).
- **Dart** : `TajwidRule` (judgement_options.dart) étendu avec `waqfLazim`/
  `waqfAwla` (ordre = ids 17/18, DOIT matcher `RULE_CLASSES` Python).
  `rule_reliability.json` : les deux classes waqf marquées
  `insufficient_data` (aucune mesure recall/précision sur eval tenu à l'écart
  à ce jour — ne jamais afficher un vert/rouge confiant dessus).

### Runs (`benchmark/models/fastconformer-dual-head-v1/`)

| Run | Base (`--init_nemo`) | val_tajwid final | Statut |
|---|---|---|---|
| `stagea-multilabel-v1` | `mixed-e14-snapshot.nemo` (brut) | 0,0497 (8 epochs) | ⚠️ **régression tête lettres** — perd tout l'acquis Stage B (voir ci-dessous) |
| `stagea-multilabel-v2-pauseaugbase` | `stageb-convhead-pause-aug-v1/stageb-final.nemo` | *(en cours de re-run)* | Base = Stage B + pause-aug |
| `stagea-multilabel-v3-cleanbase` | `stageb-convhead-v1/stageb-final.nemo` (2026-07-23 10:21, Stage B SANS pause-aug) | **0,0459** (8 epochs, meilleur) | ✅ **Déployé sur device** (21:59) |

**Régression découverte sur v1** (constat utilisateur en test live, confirmé
log : "قُلْ هُوَ ٱللَّهُ أَحَدٌ" propre AVANT → "قُلْ هُوَرُونَ" dégradé APRÈS) :
`stagea` gèle l'encodeur+tête1 pendant l'entraînement, donc leurs poids
viennent ENTIÈREMENT du `--init_nemo` fourni. `mixed-e14-snapshot.nemo` est
le tout premier checkpoint, AVANT tout le travail d'affinage ultérieur
(Stage A tajwid warmup → Stage B dégel complet → Stage B pause-aug). Repartir
de lui pour v1 a fait perdre trois étapes d'affinage de la tête lettres d'un
coup. v3 repart de `stageb-convhead-v1` (juste avant la branche pause-aug,
"Stage B propre") — récupère l'essentiel de l'acquis sans la variable
pause-aug ; v2 (en cours) permettra de mesurer si la variable pause-aug
apporte réellement quelque chose sur ce point de départ ou si elle est,
elle, la cause d'une régression différente (à trancher par comparaison
directe une fois les deux terminés).

### Déploiement device (dossier fixe `files/models/fastconformer-ctc-dual-head/`)

Chronologie des exports poussés sur le téléphone le 24/07 (le dossier est
toujours écrasé au même endroit, la trace ci-dessous sert à savoir QUEL
modèle a produit quel log/clip de test) :
- 06:08 — `fastconformer-ctc-dual-head-pauseaug` (ancien, CTC+softmax,
  18 classes) — celui testé pendant toute la 1ère partie de la session.
- 20:45 — `fastconformer-ctc-dual-head-multilabel` (v1, régression lettres).
- 21:59 — `fastconformer-ctc-dual-head-multilabel-v3` (v3, base propre) —
  **version actuellement déployée**.

### Reste à faire

- Terminer et évaluer v2 (pause-aug base) pour trancher si la variable
  pause-aug doit être réintégrée (Stage B complet) par-dessus v3.
- Éventuel Stage B complet (dégel total, comme l'ancien pipeline) sur la
  meilleure des deux bases une fois choisie — le Stage A seul a déjà donné
  0,0459, un Stage B pourrait encore améliorer sans risque de régression
  cette fois (on repart d'une base déjà bonne, pas de mixed-e14 brut).
- Recalibrer `_kTajwidGopRealized` (actuellement -1.2, hérité de l'ancien
  système) sur les vraies marges multi-label mesurées en usage réel — la
  valeur "traduit" à peu près pareil (proba ≈30%) mais n'a jamais été
  validée empiriquement dans ce nouveau régime.

---

## 7. Incertitudes explicites (à vérifier avant de s'appuyer dessus)

- Chiffres epoch02 divergents entre le commentaire Dart et les logs retrouvés
  (§6).
- Filtre Hafs-only appliqué ou non au manifest `nemo_manifests_tajweed/` d'origine.
- Existence ou non d'un training Ubuntu plus récent qu'epoch14.
- Le "0,013" transitoire de `tajweed-v2` epoch9 (probable artefact CUDA
  graphs, jamais creusé formellement — cohérent avec le glitch déjà documenté
  et confirmé invalide pour `tajweed-augmented` epoch01).

---

## RESTE À FAIRE — le fine-tune STREAMING n'a JAMAIS été lancé (constat 2026-07-25)

Constat de l'utilisateur, vérifié : **9 runs FastConformer existent, aucun n'est
un entraînement streaming.**

`quran-clean`, `quran-personal`, `tajweed`, `tajweed-v2`, `tajweed-augmented`,
`tajweed-mixed`, `mixed-e14-rules-ctc`, `hybrid-v1`, `dual-head-v1`.

Pire : les quatre scripts « streaming » du dépôt sont **tous des tentatives de
bascule SANS réentraînement**, sur un checkpoint entraîné en offline —
- `test_streaming_ctc.py` : « cache-aware chunked_limited **SANS
  reentrainement** — juste un changement de [config] »
- `test_official_stream_step.py` : `att_context_style = "chunked_limited"` posé
  sur le checkpoint existant
- `export_streaming_onnx.py` : export en `att_context_size [70,1]` du modèle
  offline
- `simulate_kotlin_streaming.py` : simulation de la politique côté Kotlin

C'est exactement ce que l'en-tête de `BufferedTranscriber.kt` décrit comme
impossible depuis le **2026-07-04** :

> le checkpoint est entraîné en mode offline avec des convolutions NON causales
> (subsampling + convs depthwise regardent ~4 frames dans le futur) […] le
> découpage chunk-par-chunk avec cache corrompt chaque frontière → décode
> **100 % blank** ; même le chemin officiel NeMo `conformer_stream_step` crashe.
> Le vrai streaming exige un fine-tune dédié avec convolutions causales.

**On a donc tenté quatre fois par la configuration, et jamais lancé
l'entraînement qui le rendrait possible.** La capacité existe (GPU, venv NeMo,
manifests, recette RNNT réparée le 2026-07-19) — c'est un manquement de
priorisation, pas un obstacle technique.

### Pourquoi ça compte plus que tout le reste du travail applicatif

Mesures du 2026-07-25 sur device :
- charge CPU de l'inférence : **12–15 %** — le calcul n'est PAS le goulot
- latence de validation : 2,1–4,9 s, dont ~10 % seulement d'inférence
- coût quadratique de la boucle : un segment de 7 s est transcrit à 1, 3, 4, 6
  et 7 s → **21 s d'audio traitées pour 7 s de parole**

L'app fait de l'**ASR d'énoncé complet en boucle pour simuler du streaming**.
Toutes les pathologies combattues le 2026-07-25 en découlent : dérive de
normalisation, syllabes doublées (`بِمَامَآمَآ`, `يُؤْمِنُونَ يُؤْمِنُونَ`),
texte `entendu` instable d'une passe à l'autre, verdicts qui changent.

### Ce qu'il faut lancer

Fine-tune **à partir du meilleur checkpoint existant** (pas de zéro) avec
convolutions causales :
- `encoder.att_context_style = chunked_limited`
- `encoder.att_context_size` borné (ex. `[70, 1]`)
- `encoder.conv_context_size = causal`, `causal_downsampling = true`
- manifests déjà construits, recette GPU déjà validée

⚠️ Avant de relancer une bascule de configuration sans entraînement : **elle a
déjà été tentée quatre fois et échoue par construction.** Ne pas la refaire.
