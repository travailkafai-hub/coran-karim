# Plan d'entraînement — modèle hybride 3 têtes (RNNT + CTC strict règles + CTC tolérant)

Rédigé le 2026-07-19, juste après le déblocage de la loss RNNT (cf.
`ETAT_CTC_NEMO.md` § "Dégeler la tête RNNT"). Ce document est LA référence du
prochain grand run — stratégie, finalité produit, datasets, phases, garde-fous.
Décision utilisateur cadre : aucune piste éliminée tant que le retour en
arrière est possible ; tout nouveau run va dans un nouveau dossier, aucun
checkpoint écrasé.

---

## 1. Finalité produit (pourquoi ce modèle, pour quoi faire)

Trois besoins distincts de l'app, servis par trois têtes sur UN encodeur
partagé (contrainte 6 Go RAM device — jamais deux encodeurs chargés) :

| Tête | Besoin produit | Ce qu'elle doit savoir faire |
|---|---|---|
| **CTC strict "règles"** (nouveau tokenizer) | Vérification exigeante de la récitation : harakat, lettres confusables, ET les règles de tajwid sans symbole écrit (qalqala, ghunnah, ikhfa, idgham, iqlab, nuances de madd — 17 classes) | Transcrire **fidèlement ce qui est dit** (y compris les fautes — anti-biais canonique, acquis du chantier mixed à conserver) + émettre des symboles de règles là où la règle est **acoustiquement réalisée** |
| **CTC tolérant** (vocabulaire normalisé) | Mode débutant / relâché : juger le squelette du texte sans exiger la précision tajweed | Sortie normalisée (style `prepare_nemo_data.py`), robuste, peu sensible aux nuances |
| **RNNT** (native, débloquée 2026-07-19) | Transcription libre de qualité — notamment **"Suivre une prière"** (identifier quel verset est récité, sans texte cible connu) | Son modèle de langage interne (prediction network), qui est un DÉFAUT pour la vérification d'erreurs, est un ATOUT pour la localisation dans le texte canonique |

**Insight architectural central** : les deux biais opposés du projet se
répartissent naturellement — la vérification a besoin d'un modèle qui
n'anticipe PAS le texte canonique (têtes CTC, corpus mixed), la localisation
Shazam-like a besoin d'un modèle qui l'anticipe (RNNT). Un seul encodeur, deux
philosophies de décodage, chacune au bon endroit.

### Exigence produit découverte en discussion (2026-07-19) : ciblage par règle, pas de score global

L'app prévoit d'afficher la **liste des 17 règles à l'utilisateur, qui choisit
lui-même lesquelles il veut se faire corriger** (un débutant peut activer
seulement qalqala, un avancé toutes). Conséquence directe sur l'évaluation :
**un score moyen sur les 17 classes ne suffit pas** — il faut une fiche de
fiabilité **par règle individuelle**, puisque chaque règle sera activée/
désactivée indépendamment par l'utilisateur. Une règle avec un recall faible
(ex. `madda_necessary`, la plus rare) ne doit probablement PAS être proposée
au choix tant qu'elle n'est pas fiable, même si la moyenne globale est bonne.
**Implication pour la Phase 3** : le rapport final doit classer les 17 règles
par niveau de fiabilité (prêtes à proposer / à surveiller / pas encore
fiables), pas juste donner un chiffre agrégé.

### Un 3e usage découvert en discussion (2026-07-19) : mode "enfant" — PAS une 3e tête

Au-delà d'adulte-strict et adulte-tolérant-tajwid, un mode enfant a besoin
d'une tolérance différente : un enfant peut réellement confondre des lettres
proches (سص, طت, ضد...) par immaturité articulatoire, pas par "erreur" au
même sens qu'un adulte. Exiger la même précision letter-level serait injuste.

**Ce mode ne change RIEN à l'entraînement, aux têtes, ni au run en cours** —
c'est une couche de comparaison **après décodage**, pas un vocabulaire de
modèle. Prérequis déjà acquis (mixed-e14) : le modèle transcrit fidèlement
la lettre réellement prononcée (pas corrigée vers le canonique) — donc l'info
"l'enfant a dit ص au lieu de س" est déjà disponible dans n'importe quelle
sortie (stricte, tolérante ou RNNT). Le mode enfant n'a besoin que d'une
**table de tolérance** appliquée à la comparaison finale, sur les paires déjà
cataloguées dans `generate_tts_augmentation.py::CONFUSABLE_PAIRS` (سص, طت,
ضد, ذز, حه, قك, عء) — la même table que celle utilisée pour générer des
erreurs d'entraînement (strictes pour un adulte), réutilisée à l'envers
(tolérées pour un enfant). Zéro coût modèle, zéro impact sur le training en
cours ou sur la décision Phase 2 (2e tête) — à implémenter côté app,
indépendamment, quand le besoin produit se précise.

---

## 2. Le piège stratégique n°1 : les symboles de règles ne doivent pas être décoratifs

Les positions des règles de tajwid sont une **fonction déterministe du texte**
(qalqala = lettre qalqala + sukun, ikhfa = noon sakina + lettre d'ikhfa...).
Si 100% des clips d'entraînement appliquent correctement les règles (récitateurs
professionnels), le modèle apprendra à émettre les symboles **depuis le contexte
textuel sans écouter** — exactement le mécanisme du biais canonique déjà combattu.
Le symbole serait alors une décoration inutile : jamais il ne manquerait quand
un élève rate la règle.

**Contre-mesures prévues, par ordre de réalisme :**
1. **Arabic Speech Corpus étiqueté SANS symboles de règles** (déjà dans le
   corpus mixed) : de l'arabe réel où les règles ne sont pas appliquées — le
   modèle voit "des lettres identiques, pas de réalisation acoustique, pas de
   symbole". Imparfait (vocabulaire différent du Coran) mais gratuit.
2. **Set humain d'erreurs de règles délibérées** (protocole §8 de
   `FONCTIONNALITES_FUTURES.md`, auto-étiquetage : "je récite ce verset SANS la
   qalqala") — petit volume, mais **utilisé d'abord comme SET D'ÉVALUATION**,
   pas d'entraînement : il mesure si la tête stricte détecte réellement une
   règle manquante. **C'est le juge de paix de toute la piste symboles.**
3. **Si l'éval (2) donne ~hasard** → les symboles sont décoratifs → pivot
   documenté : vérification des règles par DSP/tête de classification dédiée
   (options déjà chiffrées au §1 de `FONCTIONNALITES_FUTURES.md` pour le madd),
   la tête stricte restant utile pour harakat+lettres. Ne pas s'obstiner.

⚠️ Le TTS n'est d'AUCUNE aide ici : XTTS prononce l'arabe standard, il ne sait
ni appliquer ni rater une qalqala/ghunnah de façon contrôlée. Les erreurs TTS
restent cantonnées aux lettres et harakat.

### Test intermédiaire fait le 2026-07-19 (checkpoint epoch07/11, contre-mesure 1)

Mesuré recall (clips Coran, la règle est vraiment récitée) vs faux positifs
(clips ASC+TTS, aucune règle attendue) — script `test_rule_detection.py`,
n=120 par groupe, détail par classe n≤50 :

| | Résultat |
|---|---|
| Recall qalaqah | 97,5-100% |
| Faux positifs qalaqah | 0% |
| Faux positifs, N'IMPORTE quelle règle (17 confondues) | **0/120 (0%)** |
| Recall par classe (17) | 72-100%, la plupart 92-100% (point faible : `madda_necessary`, 72%, classe la plus rare — 143 occurrences dans tout le Coran) |

**Signal encourageant, mais PAS encore la preuve définitive.** Ce test oppose
audio "style Coran professionnel" contre "style ASC/TTS" — le modèle pourrait
avoir appris un raccourci de DOMAINE ("ça sonne comme une récitation
professionnelle → j'active les symboles") plutôt qu'une vraie détection
MOMENT-PAR-MOMENT de la règle, et les deux hypothèses donnent le même
résultat ici (tous les récitateurs pro du corpus appliquent toujours les
règles correctement). **Seul le test (2) ci-dessus (set humain, qalqala
volontairement omise DANS un style Coran par ailleurs correct) peut trancher
entre les deux hypothèses** — toujours pas fait, toujours le vrai juge de
paix. Ce test intermédiaire élimine au moins l'hypothèse la plus grossière
(symboles émis n'importe où/n'importe quand sans rapport à l'audio).

### Triangulation CTC vs RNNT sur les 17 règles (2026-07-19)

Idée : les deux têtes partagent le MÊME encodeur mais ont des paradigmes de
décodage opposés (CTC frame-indépendant vs RNNT autorégressif avec mémoire de
langage interne). Si la détection des règles était un artefact décoratif
propre à l'entraînement CTC, les deux devraient diverger nettement. Testé
sur les MÊMES clips (comparaison appariée), `test_ctc_vs_rnnt_rules.py`,
n≤50/classe, dataset fiable (`nemo_manifests_rules/val_manifest.jsonl`,
PAS le YouTube invalidé ci-dessous) :

| Règle | CTC | RNNT | Règle | CTC | RNNT |
|---|---|---|---|---|---|
| madda_necessary (n=32) | 72% | 75% | idgham_shafawi | 92% | 90% |
| madda_obligatory | 96% | 92% | iqlab | 96% | 96% |
| madda_permissible | 98% | 98% | idgham_wo_ghunnah | 94% | 96% |
| madda_normal | 96% | 96% | idgham_mutajanisayn (n=13) | 85% | 77% |
| ghunnah | 98% | 96% | idgham_mutaqaribayn (n=3) | 100% | 100% |
| ikhafa | 94% | 94% | laam_shamsiyah | 100% | 100% |
| ikhafa_shafawi | 96% | 96% | ham_wasl | 94% | 96% |
| idgham_ghunnah | 100% | 98% | slnt | 90% | 92% |
| qalaqah | 96% | 96% | | | |

**Convergence quasi parfaite sur 15/17 règles** (±2-4pts, le seul écart
notable — `idgham_mutajanisayn`, -8pts — porte sur n=13, pas significatif).
Signal de triangulation utile (deux décodeurs indépendants convergent, rend
l'hypothèse "décoratif" moins probable) — **et rassurant sur le risque
redouté** : RNNT ne sur-détecte pas systématiquement par rapport à CTC (pas
de dérive canonique visible ici). **Ne règle toujours PAS** la question
cross-récitateur/violation-délibérée (mêmes 54 récitateurs qu'en training) —
le set humain reste le seul test définitif.

### Exigence produit (2026-07-19) : fiabilité PAR règle, pas de score agrégé

L'app affichera la liste des 17 règles, l'utilisateur choisira lui-même
lesquelles activer — donc chaque règle a besoin de sa propre fiche de
fiabilité (voir §1), pas d'une moyenne. Sur la base des deux tests
ci-dessus, classement provisoire : **prêtes** (≥92% des deux côtés) — la
majorité des 17 ; **à surveiller** (madda_necessary ~72-75%, classe la plus
rare) ; **échantillon insuffisant pour trancher** (idgham_mutajanisayn n=13,
idgham_mutaqaribayn n=3) — reprendre la mesure avec plus de clips avant de
classer ces deux dernières.

### Tentative de test cross-récitateur via YouTube (2026-07-19) — INVALIDÉE, méthode à refaire

Motivation : les 54 récitateurs Hafs disponibles sont TOUS déjà utilisés en
train+val (overlap 53/53) — aucune généralisation cross-récitateur testée
jusqu'ici. `manifest_youtube_clean.jsonl` (3371 clips, jamais touché par ce
training) semblait un pool gratuit pour ça. **Provenance vérifiée avant
usage** (demande explicite) : croisement avec les titres vidéo d'origine —
66% attribués à des Qaris mondialement reconnus (Alafasy, Sudais, Al-Hussary
— titre "Accurate Tajweed recitation" explicite —, Al-Muaqly, Baleelah...),
31% à des récitateurs nommés moins célèbres, 3% (103 clips) sans aucune
attribution (exclus). Sous-set "gold tier" (Imams des Haramain + références
historiques uniquement, 1979 clips) construit pour la confiance maximale.

**Premier test (recall par règle, n=50/classe) : effondrement à 26-44%**
(vs 97,5-100% sur le split classique) — semblait indiquer un échec de
généralisation. **Deuxième test, déclenché par une question méthodologique
de l'utilisateur** (vérifier qu'on cible bien LA position où la règle
s'applique, pas juste "n'importe où dans le clip") : mesure du CER de base
(lettres/harakat, symboles retirés) sur les mêmes clips → **72,75% (médiane
95%)** — le modèle sort du quasi-charabia sur la plupart des clips
(`REF: [verset complet] / HYP: إِنمٌ`).

**Cause racine identifiée** (`youtube_align.py` ligne `CHUNK_S = 30`) : ces
clips sont découpés en **blocs fixes de 30s, sans respect des frontières de
versets** (coupe à l'aveugle puis appariement du texte a posteriori) — hors
distribution du training (`max_duration=20s`, clips single-verset de
quelques secondes). **L'effondrement mesuré n'a rien à voir avec la
détection de règles ni avec la généralisation cross-récitateur** — c'est un
échec de transcription général sur un format audio jamais vu. Les chiffres
26-44% et 72,75% CER sont **à jeter, pas à interpréter**.

**Verdict** : cette piste ne peut PAS répondre à la question de
généralisation cross-récitateur sans un vrai ré-alignement forcé du YouTube
(extraire les frontières verset par verset à l'intérieur des blocs de 30s,
comme déjà fait pour `_assajda` en juillet) — un chantier à part entière, pas
une correction rapide. **Non fait à ce jour** ; la seule mesure de recall
valide reste celle sur le split classique (97,5-100%, mêmes 54 récitateurs
que le train — donc ne teste toujours PAS la généralisation cross-récitateur).
Scripts conservés (`build_youtube_heldout_rules.py`,
`nemo_manifests_rules/val_youtube_goldtier.jsonl`) pour une reprise future
si le ré-alignement forcé est fait.

---

## 3. Réponse à la question "rajouter encore des erreurs TTS ?"

**Oui, mais pas "plus de la même chose" — trois ajouts ciblés, dans cet ordre :**

1. **Des clips TTS CORRECTS, priorité absolue.** Mesuré ce jour : les 18 195
   clips TTS actuels sont **100% fautifs** (8 472 lettre + 9 723 harakat, zéro
   clip canonique). La corrélation "voix synthétique ⇒ erreur" est donc totale —
   le risque documenté dans `build_mixed_manifest.py` (le modèle apprend "voix
   TTS → j'écoute, vraie voix → je corrige") est au maximum possible. Générer
   ~15-20k clips TTS **canoniques** (mêmes mots, mêmes voix, même pipeline,
   `kind: "correct"`) casse cette corrélation pour un coût quasi nul (le script
   `generate_tts_augmentation.py` existe, il suffit d'un mode sans substitution).
2. **Plus d'erreurs harakat, et plus variées.** C'est LE point faible mesuré
   partout : fidélité harakat 55,7% (epoch14) vs 76,3% lettre ; rescoring
   harakat 49,6% = hasard. Étendre aux **tanwin et shadda** (explicitement
   exclus du script actuel) et aux positions au-delà des @1/@3 dominantes
   aujourd'hui. Le volume lettre (8,5k, détection 76-80%) est en rendement
   décroissant — ne pas en rajouter.
3. **Plus de voix.** 11 voix seulement aujourd'hui (7 YouTube + 4 autres).
   Ajouter des références de clonage (autres récitateurs YouTube déjà filtrés
   par WER) réduit le sur-ajustement au timbre — важно surtout si on ajoute du
   volume via (1) et (2).

**Et en complément non-TTS** : le petit set humain d'erreurs délibérées (§2.2
ci-dessus) vaut plus cher par clip que n'importe quel lot TTS — à enregistrer
en priorité pour l'ÉVAL des règles, et si le volume le permet, quelques-uns en
training.

---

## 4. Architecture technique du run

- **Base** : `.nemo` `stt_ar_fastconformer_hybrid_large_pcd_v1.0` (encodeur
  rel_pos pré-entraîné, jamais réinitialisé — décision parquée, ne pas re-dériver).
  Point de départ des poids encodeur : à trancher au lancement entre (a) base
  pcd vierge, (b) warm-start depuis `mixed-e14` (garde l'acquis anti-biais ;
  ⚠️ warm-start poids seuls, jamais l'optimiseur — leçon documentée).
  **Recommandation : (b)**, l'acquis mixed (65% détection) a coûté cher.
- **Tête RNNT** : native du modèle, entraînée pour la première fois (elle est
  vierge — loss ~1041 constatée). `change_vocabulary` s'applique aussi à elle
  (joint/decoder redimensionnés sur le nouveau vocab).
- **Tête CTC stricte** : `change_vocabulary` vers le **nouveau tokenizer
  "tajweed-rules"** (cf. Phase 0).
- **Tête CTC tolérante** : ⚠️ NeMo ne supporte PAS deux têtes CTC dans un
  `EncDecHybridRNNTCTCBPEModel` — elle sera un module séparé (une couche
  `Conv1d 512→vocab_normalisé`) entraîné **après coup sur l'encodeur gelé**
  (boucle PyTorch simple, pas NeMo — la tête étant la dernière couche, pas de
  backward à travers l'encodeur, entraînement en heures). Export final : **un
  seul graphe ONNX multi-sorties** (pattern déjà validé par
  `export_embedding_model.py` qui ajoute une sortie `embeddings`) — jamais
  deux ONNX séparés (dupliqueraient l'encodeur ~458 Mo chacun).
- **Loss hybride** : convention NeMo `ctc_loss_weight` — démarrer à **0.3**
  (0.7·RNNT + 0.3·CTC, standard NVIDIA pour ces modèles hybrides).
- **VRAM** : le joint RNNT (B×T×U×V) est gérable avec `fuse_loss_wer=True` +
  `fused_batch_size` petit (4) — ordre de grandeur ~60 Mo par batch de 4 clips
  de 10s avec V=1024+règles, pas le mur redouté. Garder
  `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`, `batch_size` 4-8 avec
  accumulation, cap `max_duration`.
- **Environnement (cette machine Ubuntu)** : venv `.venv_nemo` via
  `PYTHONPATH` + `/usr/bin/python3.14` (binaire venv cassé) + **`CUDA_HOME`
  obligatoire** pour la loss RNNT (recette `ETAT_CTC_NEMO.md`) ; patch local
  NeMo "PATCH LOCAL" à vérifier présent avant lancement.

---

## 4ter. ÉTAT D'EXÉCUTION (mis à jour 2026-07-19 — le run est LANCÉ)

**Phase 0 exécutée et validée le 2026-07-19** :
- `dl_uthmani_tajweed.py` : 6 236 versets × 2 scripts téléchargés (API quran.com,
  même source que les couleurs de l'app — l'idée d'origine).
- `build_rules_annotated_corpus.py` : 56 197 symboles insérés (dont 3 834
  qalqala), ancrage canonique par alignement Levenshtein (la distance résiduelle
  vient du numéro de verset ajouté par l'API, absorbé proprement). Placement
  vérifié à la main sur 1:1, 112:1, 113:1 — qalqala exactement après ق/د.
- `build_rules_tokenizer.py` : `tokenizers/tajweed_rules_bpe_v1` (BPE 1024),
  couverture 100% (87 chars + 17 symboles + les 12 marques du §3 de
  FONCTIONNALITES_FUTURES), roundtrip parfait, zéro <unk>. Bonus : BPE a appris
  des fusions phonologiquement sensées (sukun+qalqala).
- `build_rules_manifests.py` : 131 882 train / 3 976 val — 34 222 clips Coran
  **100% annotés** (matching par verse_key + texte exact, 0 mismatch), 100%
  des audios présents sur le SSD local, **0 récitateur Warsh** (54 récitateurs
  audités contre la liste d'exclusion — question historique tranchée pour ce
  sous-ensemble).
- Smoke test complet du script hybride (20 batches) : mécanique validée de
  bout en bout (vraie loss RNNT + checkpoints + snapshot .nemo). Deux bugs
  réels attrapés et corrigés : PicklingError Python 3.14 (fix fork), monitor
  1a incohérent.

**Crash réel rencontré et corrigé (2026-07-19)** : le stage 1b complet a crashé
~1,9 epoch après son lancement — `SIGSEGV` Python natif dans
`_PyObject_MakeTpCall` (rapport apport Ubuntu), pas une erreur NeMo/PyTorch de
haut niveau (le `torch.AcceleratorError: launch timed out` visible dans le
log est une conséquence en cascade pendant le teardown, pas la cause). Cause
probable : `multiprocessing.set_start_method("fork", force=True)` (ajouté le
même jour pour contourner un `PicklingError` Python 3.14) appliqué APRÈS que
le process principal ait initialisé CUDA (`model.cuda()` avant la création
des workers) — cas documenté comme non défini par PyTorch/NVIDIA, cohérent
avec un crash aléatoire et tardif jamais reproduit sur les runs plus courts
(1a, ab03, ab07, tous < 2 epochs). **Fix** : `num_workers=0` par défaut (plus
aucun worker DataLoader forké → le `PicklingError` d'origine ne se produit
jamais non plus, pas besoin de fork du tout). Perte quasi nulle : checkpoint
`epoch=02-val_wer_ctc=0.180` sauvé juste avant le crash, run repris depuis
`periodic/last.ckpt` sans redémarrage à zéro.

**Décisions d'hyperparamètres actées (et leur statut épistémique)** :
- `ctc_loss_weight` : 1a=0.5 (**neutre prouvé** — encodeur gelé, les têtes
  n'interagissent pas) ; 1b = **A/B mesuré le 2026-07-19** (1 epoch chacun
  depuis le même snapshot 1a, run_tag `ab03`/`ab07`) au lieu d'appliquer
  aveuglément l'hypothèse "CTC dominante" — demande utilisateur explicite de
  ne pas appliquer sans preuve. **Résultat** : 0.7 bat 0.3 sur la métrique
  primaire (`val_wer_ctc` 0,2211 vs 0,2345, ~1,3pt) sans coûter au RNNT
  (`val_wer` 0,1459 vs 0,1457, différence négligeable) — hypothèse confirmée
  empiriquement, pas supposée. **Stage 1b complet lancé avec 0.7**, en
  poursuite depuis le checkpoint `ab07` (pas de redémarrage à zéro — l'epoch
  déjà investie compte pour les 12 prévues, 11 restantes).
- Warm-start encodeur mixed-e14 (hypothèse raisonnée ; ablation "base pcd
  vierge" prévue si l'éval Phase 3 déçoit).

**Checklist de déploiement app (à faire APRÈS le run, avant tout déploiement)** :
1. Régénérer `word_tokens.json` avec le nouveau tokenizer (pattern
   `build_word_token_lookup_*`).
2. Décider du sort des symboles PUA en sortie modèle côté app : strip dans la
   normalisation de comparaison de mots + exploitation séparée pour la
   vérification des règles.
3. Ré-adapter les branchements rescoring NLL / décodage contraint (faits le
   19/07 sur le vocab mixed) au nouveau vocab.
4. Enregistrer le **set humain de violations de règles** (juge de paix,
   toujours pas fait) avant de prétendre "règles vérifiées".

## 4bis. Vue d'ensemble du séquencement (qui apprend quand)

| Étape | Encodeur | Tête RNNT | Tête CTC stricte | Tête CTC tolérante | Données | Durée |
|---|---|---|---|---|---|---|
| **1a** | 🧊 gelé (warm-start mixed-e14) | 🔥 apprend (de zéro) | 🔥 apprend (de zéro, nouveau vocab règles) | — | mixed complet | ~1-2 epochs, rapide |
| **1b** | 🔥 apprend (LR bas 3e-5) | 🔥 apprend (LR 1e-4) | 🔥 apprend (LR 1e-4) | — | mixed complet | ~10-15 epochs, 20-30h |
| **2** | 🧊 gelé (meilleur ckpt 1b) | 🧊 gelée | 🧊 gelée | 🔥 apprend seule (Conv1d, hors NeMo) | mixed, labels normalisés | heures |
| **3** | — évaluation, garde-fous, export ONNX multi-sorties — | | | | val + set humain règles | — |

Logique : ne jamais laisser des gradients de têtes vierges saccager un
encodeur acquis (1a le protège en le gelant) ; ne dégeler l'encodeur (1b)
qu'une fois les têtes stabilisées, avec un LR qui affine sans réapprendre ;
la tête tolérante s'ajoute en dernier sur du définitivement figé (2), donc
elle ne peut rien casser.

## 5. Phases d'exécution

### Phase 0 — Préparation données/tokenizer (CPU, pas de GPU, peut démarrer tout de suite)
1. **Télécharger `text_uthmani_tajweed`** (114 sourates, API quran.com — même
   méthode que les téléchargements tafsir). ⚠️ Piège documenté : ce champ ne
   contient pas toujours les mêmes caractères que `text_uthmani` (4278/6236
   versets diffèrent) — l'utiliser UNIQUEMENT comme source de
   **positions/classes de règles**, ancrer les caractères sur `text_uthmani`
   canonique (pattern `_remapWordColors` déjà validé côté app).
2. **Choisir les symboles** : 1 caractère Unicode réservé par classe (17),
   hors de tout caractère du corpus (zone à usage privé U+E000+, vérifié
   absent). Simple, réversible, pas de regroupement prématuré des familles.
3. **Construire le corpus texte annoté** + **nouveau tokenizer BPE 1024**
   (`build_tajweed_tokenizer.py` adapté ; ⚠️ espace dans le chemin projet
   casse sentencepiece → passer par un dossier temporaire sans espace).
4. **Check de couverture vocabulaire** (le check 10 lignes documenté dans
   `asr.md` — leçon wasla, coûteuse) : chaque caractère du corpus annoté doit
   être couvert, 0 `<unk>`.
5. **Régénérer les manifests** style mixed, avec remap des chemins pour cette
   machine (`/mnt/ssd5` → `/media/kafai/NouveauNom`, `/mnt/hdd` →
   `/run/media/kafai/HDD`) : clips Coran → texte avec symboles de règles ;
   ASC → texte vocalisé SANS symboles ; TTS → texte fautif SANS symboles.
   ⚠️ **Vérifier au passage la provenance Hafs-only** du corpus Coran utilisé
   (question ouverte héritée, jamais tranchée — c'est le moment).
6. **Génération TTS additionnelle** (§3 : correct + harakat étendues + voix) —
   en parallèle du reste, GPU léger.
7. **Enregistrer le set humain d'erreurs de règles** (utilisateur, protocole
   §8 : quelques dizaines de clips auto-étiquetés "verset X sans qalqala/sans
   ghunnah/madd trop court") → `val_rules_violations.jsonl`, réservé à l'éval.

### Phase 1 — Run principal hybride (GPU, le gros morceau)

**Le problème de séquencement que la stratégie doit résoudre** : au lancement,
l'encodeur est BON (warm-start mixed-e14, des semaines d'acquis) mais les DEUX
têtes NeMo sont VIERGES (le `change_vocabulary` vers le tokenizer règles
réinitialise la tête CTC ; la tête RNNT n'a jamais rien appris — loss ~1041
constatée au smoke test). Entraîner tout d'un bloc = les gradients énormes et
chaotiques des têtes fraîches traversent l'encodeur et peuvent **détruire son
acquis dans les premières centaines de steps**, avant que les têtes ne
deviennent raisonnables. D'où un entraînement en deux temps :

**Étape 1a — Têtes seules, encodeur GELÉ (~1-2 epochs, rapide)**
- `encoder.freeze()` : forward seul, aucun gradient ne le traverse — les deux
  têtes (decoder+joint RNNT, tête CTC stricte) apprennent contre des
  représentations stables et déjà excellentes.
- LR "de tête fraîche" : 1e-3 → 5e-4 (les têtes partent de zéro, elles peuvent
  encaisser un LR élevé ; l'encodeur ne risque rien, il est gelé).
- Bonus vitesse : encodeur gelé = pas de backward encodeur, steps nettement
  plus rapides et VRAM réduite — cette étape coûte peu.
- Critère de passage à 1b : loss RNNT descendue de ~1000 à un ordre de
  grandeur "normal" (< ~50 par clip) ET `val_wer_ctc` de la tête stricte
  descendu sous ~0.3 (les têtes "voient" correctement l'encodeur).

**Étape 1b — Dégel complet, loss hybride (~10-15 epochs, le cœur du run)**
- Tout s'entraîne : encodeur + RNNT + CTC stricte, loss
  `0.7·RNNT + 0.3·CTC` (`ctc_loss_weight=0.3`, standard NVIDIA).
- **LR différenciés par groupe de paramètres** — c'est le point clé de
  protection de l'acquis : encodeur à ~3e-5 (il affine, il ne réapprend pas),
  têtes à ~1e-4. Si le script ne gère pas les groupes, repli acceptable : LR
  unique bas (5e-5) pour tout le monde, un peu plus lent mais sûr.
- Warmup court (500 steps) + gradient clipping (1.0) en ceinture de sécurité
  supplémentaire au moment du dégel.
- Sélection du checkpoint : sur `val_wer_ctc` (la tête stricte est la tête
  produit primaire) ; `val_wer` (RNNT) suivi en second — c'est la PREMIÈRE
  fois qu'il devient une vraie métrique (mettre à jour la règle "toujours
  ignorer val_wer" dans la doc à ce moment-là).

**Stratégie de données par tête (v1 : simple ; v2 : raffinement si besoin)**
- **v1** : les deux têtes voient le MÊME corpus mixed complet (canonique +
  ASC + TTS fautif, étiquettes fidèles au prononcé). C'est le comportement
  NeMo standard (une loss hybride par batch), zéro code custom. La tête RNNT
  apprendra donc aussi à transcrire fidèlement les fautes — acceptable, et
  son biais canonique résiduel sera mesuré en Phase 3.3 de toute façon.
- **v2 (reclassé de "contingence" à "expérience prévue", 2026-07-19 — question
  utilisateur)** : le corpus mixed actuel (150h Coran **sous-échantillonné**
  + ASC + TTS fautif) a été conçu pour **combattre** le biais canonique — donc
  optimal pour CTC (vérification), mais potentiellement **contre-productif**
  pour RNNT dont la valeur (localisation "Suivre une prière") vient
  précisément d'un biais canonique fort. Masquer la loss RNNT sur les
  échantillons non-Coran (ASC, TTS) ET/OU la calculer sur le corpus Coran
  **complet non dilué** (`manifest_hafs_only.jsonl`, 307 059 clips, ~300h+ vs
  150h actuels) pendant que la loss CTC continue de voir le mix complet —
  l'encodeur reste partagé (même audio traité dans les deux cas), seule la
  contribution RNNT au gradient change. Compute disponible (GPU peu chargé) →
  **à faire en round dédié après la Phase 3**, informé par la mesure réelle
  de qualité RNNT en localisation (pas seulement `val_wer`) plutôt que lancé
  à l'aveugle. Demande de surcharger `training_step` de NeMo (masquage par
  tag de source dans le manifest) — faisable, pas fait à ce jour.

**Logistique**
- Script : variante `--rnnt` de `finetune_fastconformer.py` (à écrire —
  vraie loss RNNT au lieu de `_ZeroRNNTLoss`, `ctc_loss_weight=0.3`, flags
  `--freeze-encoder` pour 1a et groupes de LR pour 1b, monitor `val_wer_ctc`).
- Sortie : `benchmark/models/fastconformer-quran-hybrid-rules-v1/` (nouveau
  dossier, rien d'écrasé) — sous-dossiers `stage1a/` et `stage1b/`.
- Checkpoints : `save_top_k=3` + noms uniques par epoch (config du script
  augmented, PAS le pointeur "last" recyclé du script pcd — leçon documentée)
  + periodic tous les 1000 global steps.
- Ordre de grandeur durée : le run mixed CTC-only a fait ~15 epochs sur 131k
  clips en ~10h ; 1a est rapide (encodeur gelé), 1b ~1,5-2× plus lent par
  step que du CTC-only → prévoir 20-30h au total, planifier les reprises.

### Phase 2 — Mode tolérant : TESTER avant de construire (inversé le 2026-07-19)

**Changement de plan suite à question utilisateur** : ne pas construire la 2e
tête par précaution — la sortie de la tête stricte (lettres+harakat+symboles)
contient déjà toute l'info nécessaire au mode tolérant si on se contente de
**retirer les symboles après coup** (normalisation, coût zéro, aucun
entraînement). Une 2e tête dédiée n'a de valeur QUE si une hypothèse précise
se vérifie : que l'entraînement aux nuances acoustiques fines (règles) **abîme**
la reconnaissance de base lettres/harakat pour une récitation valide mais sans
tajwid formel (interférence entre tâches) — auquel cas retirer le symbole ne
répare rien, c'est la transcription de base elle-même qui serait dégradée.

**Étape 2.1 — Test d'interférence (obligatoire avant toute décision)** :
1. Transcrire `val_canonical.jsonl` avec la tête stricte (Phase 1), retirer
   les symboles de règles de la sortie.
2. Comparer le WER lettre/harakat résultant à celui de **mixed-e14** (baseline
   sans aucun entraînement règles) sur le même set.
3. **Pas de dégradation mesurable** → normalisation seule suffit, verdict :
   **pas de 2e tête**, économie du travail de la Phase 2.2 ci-dessous.
   **Dégradation réelle et significative** → passer à 2.2, avec une preuve
   concrète du besoin plutôt qu'une précaution.

**Mesure préliminaire faite le 2026-07-19 sur checkpoint epoch07/11 (PAS le
final)** : CER 9,72% (règles désymbolisé, n=150) vs 9,18% (baseline
mixed-e14) — écart de **+0,54 point, pas un zéro parfait**. Ni assez grand
pour conclure "dégradation confirmée", ni assez petit pour conclure "zéro
interférence" avec confiance : échantillon modeste (n=150), checkpoint pas
final (le training continue), et une partie de l'écart peut venir de la
réinitialisation de la tête CTC (`change_vocabulary`) plutôt que d'une vraie
interférence règles/lettres. **À refaire avec le checkpoint final** (fin des
11 epochs) avant de trancher — ne pas décider sur cette mesure intermédiaire.

**Étape 2.2 — Tête CTC tolérante (SEULEMENT si 2.1 confirme le besoin)** :
- Geler le meilleur checkpoint Phase 1, entraîner la couche
  `Conv1d 512→vocab_normalisé` seule (script court `train_tolerant_head.py`,
  `torch.nn.CTCLoss`, labels via `prepare_nemo_data.py::normalize_text`).
- Rapide (heures), sur l'encodeur figé — ne peut rien casser côté tête stricte.

### Phase 3 — Évaluation, garde-fous, export
1. `eval_error_detection.py` sur la tête stricte — baseline à battre :
   **epoch14 = 65,3% détection / 14,7% ratées / CER 9,18%** (n=150).
2. **Éval règles sur `val_rules_violations.jsonl`** (set humain, §2.2) — le
   juge de paix : détection proche du hasard ⇒ symboles décoratifs ⇒ pivot DSP
   pour les règles, sans jeter le reste du run.
3. **RNNT vs CTC sur `val_errors_annotated.jsonl`** — quantifier le biais
   canonique de la tête RNNT AVANT tout usage décodé ; la cantonner à "Suivre
   une prière" si (quand) elle corrige plus que la CTC.
4. Benchmark généralisation (YouTube + Warsh squelette, protocole du
   2026-07-16) vs epoch14 déployé.
5. Export ONNX multi-sorties (logprobs_strict + logprobs_tolerant [+
   embeddings]), validation bit-exact PyTorch↔ONNX, déploiement dans un
   NOUVEAU sous-dossier device (pas d'écrasement de `mixed-e02`), test app
   réel.

---

## 5bis. Comparaison directe au modèle déployé (mixed-e14) — checkpoint final, 2026-07-19

Question posée en fin de session : "est-ce que c'est mieux que l'ancien ?" —
protocole `eval_error_detection.py` (le même qui a servi à mesurer mixed-e14),
symboles de règles retirés avant comparaison (cohérent avec la décision
Phase 2.1 : la normalisation est la couche de comparaison réelle) :

| Métrique (n=150) | mixed-e14 (déployé) | Nouveau modèle hybride (stage1b-final) |
|---|---|---|
| Détection d'erreur (fidèle) | 65,3% | **65,3%** (identique) |
| Corrigé à tort vers canonique (invisible) | 14,7% | **10,7%** (meilleur, -4pts) |
| CER anti-oubli | 9,18% | 9,69% (légèrement moins bon, +0,51pt — même écart que Phase 2.1) |

**Meilleur sur la métrique la plus importante** (corrections silencieuses, le
problème central du chantier mixed) à détection égale, pour un coût mineur en
CER canonique. Plus deux capacités entièrement nouvelles absentes de
mixed-e14 : détection des 17 règles de tajwid (92-100% recall, confirmé par
triangulation CTC/RNNT) et tête RNNT fonctionnelle (localisation).

## 5ter. Continuation sur 260h (vs 150h) — stage1b-260h, 2026-07-19

**Contexte** : le run stage1b (150h) ci-dessus tournait sur une sous-echantillon
Coran limitee a 150h/1251h disponibles ; l'utilisateur a demande d'augmenter
ce budget. `build_mixed_manifest.py --quran-hours 260` relance depuis
`stage1b/stage1b-final.nemo` (seed identique, meme mix ASC×10/TTS×5, donc
memes contre-exemples, seul le volume Coran change 150h -> 260h, 337.5h
total). Sortie dans `stage1b-260h/` (rien ecrase, `stage1b/` et
`stage1b-continued/` — ce dernier vide, tue avant le premier vrai
checkpoint — restent intacts).

**Deux bugs trouves et corriges avant de pouvoir mesurer quoi que ce soit** :
1. `build_rules_manifests.py` ne reconnaissait pas le nouveau point de montage
   HDD (`/run/media/kafai/HDD/...`) — les clips Coran n'etaient PAS annotes
   avec les symboles de regles (0/156892). Corrige (reconnait aussi
   `/train_wav/` en plus de `/train_wav_local/`) ; reverifie : 59232/59232
   clips Coran annotes, 0 mismatch.
2. `build_mixed_manifest.py` ne remappait jamais les chemins de
   `val_canonical.jsonl` (seul QURAN_TRAIN etait remappe) — pointaient vers
   un montage `/mnt/hdd/...` disparu. Invisible jusqu'a ce qu'un eval essaie
   reellement de lire ces fichiers (`FileNotFoundError`). Corrige (meme
   `remap_audio_path()` applique a QURAN_VAL), sans impact sur le training
   deja termine (`val_canonical.jsonl` n'entre pas dans l'entrainement, seul
   l'eval directe l'utilise).

**Convergence** : `val_wer_ctc` 0,157 (epoch 1) -> **0,147** (meilleur, epoch
5, retrouve a l'epoch 7) sur 8 epochs — deja meilleur que l'ancien run 150h
**totalement convergu** (plafonne a 0,1635 vers l'epoch 7-10 sur 11 epochs).

**Comparaison officielle** (`eval_error_detection_rules_stripped.py` —
wrapper de `eval_error_detection.py` qui ne fait QUE retirer les symboles de
regles de la sortie avant comparaison, meme metrique/meme protocole/meme
n=150) :

| Métrique (n=150) | mixed-e14 (déployé) | Hybride 150h | **Hybride 260h** |
|---|---|---|---|
| Détection d'erreur (fidèle) | 65,3% | 65,3% | 64,7% (bruit, n=150) |
| Corrigé à tort vers canonique (invisible) | 14,7% | 10,7% | **10,7%** (identique) |
| CER anti-oubli | 9,18% | 9,69% (legerement pire) | **6,85%** (nettement meilleur) |

**Le point faible du run 150h (CER canonique degrade de +0,51pt) est
resolu** — les 110h de Coran supplementaires ont clairement aide a preserver
l'acquis canonique, SANS perdre le gain anti-biais (corrections silencieuses
toujours a 10,7%, -4pts vs deploye). Verdict : gain net sur toute la ligne,
plus les capacites deja listees en 5bis (regles tajwid, RNNT). Ce checkpoint
(`stage1b-260h/stage1b-final.nemo`) est desormais la meilleure version du
run hybride a ce jour.

## 5quater. GOP mal calibré sur device vs ancien modèle — diagnostic complet, cause racine PAS résolue (2026-07-20 soir)

**Symptôme signalé par l'utilisateur** : en mode adulte (censé être tolérant,
aucune règle tajwid active), le nouveau modèle (stage1b-260h) bloque
beaucoup plus que l'ancien (mixed-e14) sur des mots bien prononcés,
notamment "ٱللَّهِ"/"ٱلرَّحْمَـٰنِ"/"ٱلرَّحِيمِ"/"رَبِّ".

**Pistes testées, dans l'ordre, chacune mesurée avant de passer à la suivante** :

1. **Symboles de règles polluant `free`** (le max par frame incluait les 40
   classes-symboles) — CONFIRMÉ et CORRIGÉ (`ForcedAligner.kt`, commit
   `64215d0`). Coût mesuré avant fix : -177,83 sur la propre transcription.
2. **Symboles polluant aussi `forced`** (pas seulement `free`) — CONFIRMÉ :
   sur un mot SANS aucune règle ("يَوْمِ"), ancien modèle gop=-0,03 vs
   nouveau -20,09 sur le MÊME audio. Masquage+renormalisation pré-softmax
   appliqué à `forced` ET `free` (commit `a2d3054`). Gain mesuré : -20,09 →
   -9,59 — réel mais incomplet.
3. **Chadda tokenisé seul** (sans lettre ni voyelle, ex. "رَبِّ" →
   [رَ, بِ, ّ]) — identifié comme cause plausible de gop catastrophique sur
   les mots à lettre doublée y compris dans l'ANCIEN modèle. Exclu du calcul
   du gop (même commit `a2d3054`). Effet sur device : marginal, le blocage
   sur "ٱللَّهِ"/"رَبِّ" a persisté.
4. **Fenêtre de contexte (buffer court en streaming)** — RÉFUTÉ par mesure
   directe : à contexte tronqué IDENTIQUE (2,5s/3,0s/4,0s), l'ancien modèle
   est déjà proche de 0,00 partout, le nouveau reste à -5 à -6 SANS
   amélioration en donnant plus de contexte (jusqu'à 4s). Donc PAS un
   problème de fenêtre glissante — abandonné avant d'investir dans la
   refonte d'architecture proposée en §4 de `FONCTIONNALITES_FUTURES.md`.
5. **Poids de la loss hybride** (`ctc_loss_weight`) — vérifié dans
   `hparams.yaml` du run réel (pas le plan écrit à l'avance, qui divergeait) :
   stage1b-260h entraîné avec `ctc_loss_weight=0,3` (loss = 0,7·RNNT +
   0,3·CTC, RNNT dominant), contre l'ancien modèle entraîné CTC-only
   (`ctc_loss_weight=1,0`, aucune concurrence RNNT). Hypothèse testée par
   continuation : reprise depuis `stage1b-260h/stage1b-final.nemo`,
   `--ctc_loss_weight 1.0`, 4 epochs complets, LR bas (5e-5, cf. script) —
   dossier `stage1b-ctc-recovery/` (rien écrasé).

   **RÉSULTAT : NÉGATIF.** gop sur "ٱللَّهِ" à 2,5/3,0/4,0s de contexte :
   epoch0 = -5,89/-5,45/-5,58 ; epoch3 = -5,18/-5,21/-5,33 ; final (4
   epochs) = -5,31/-5,33/-5,45. Aucune tendance vers 0 sur les 4 epochs —
   essentiellement identique à avant (stage1b-260h original :
   -5,71/-5,10/-5,31).

**Ce que ce résultat négatif prouve, et ce qu'il NE prouve PAS** : rebasculer
le poids et continuer l'entraînement depuis un checkpoint déjà façonné par
8 epochs de loss RNNT-dominante, à LR bas (volontairement choisi pour ne
PAS détruire l'acquis), ne suffit pas à corriger la calibration. Ça
NE PROUVE PAS que le poids RNNT n'était pas la cause à l'origine — un LR
plus élevé ou (surtout) un réentraînement complet CTC-only DEPUIS stage1a
(pas une continuation) pourrait donner un résultat différent, mais c'est un
chantier de plusieurs heures sans garantie, pas fait à ce jour. Piste
alternative jamais testée directement : le vocabulaire élargi aux 40
symboles tajwid dégraderait la calibration de façon intrinsèque,
indépendamment du poids RNNT (cohérent avec la trouvaille #2 ci-dessus, qui
montre déjà un effet mesurable des symboles sur des mots ordinaires).

**Décision initiale (dépassée par la suite, gardée pour l'historique)** : ne
pas relancer un entraînement de plusieurs heures sans garantie, architecture
double-modèle (ancien pour le gop, nouveau seulement pour les symboles).
Jamais implémentée — la suite de la même soirée a donné un résultat plus
complet, voir ci-dessous.

## 5quinquies. Piste 3 (mixed-e14 intact + tokenizer tajwid + VRAI CTC-only) — résultat final, et cause racine trouvée (2026-07-20 nuit)

**Piste 3, méthodologie** : contrairement à ctc-recovery (continuation depuis
un checkpoint déjà façonné par 8 epochs de loss hybride RNNT-dominante), on
repart de `mixed-e14-snapshot.nemo` INTACT, `change_vocabulary` vers
`tokenizers/tajweed_rules_bpe_v1`, puis le VRAI script CTC-only
(`finetune_fastconformer.py`, celui qui a produit mixed-e14 à l'origine :
`set_fuse_loss_wer(False)` + `_ZeroRNNTLoss`, pas juste `ctc_loss_weight=1.0`
sur le script hybride). 4 epochs, `nemo_manifests_rules/` (260h + regles),
sortie `models/fastconformer-quran-mixed-e14-rules-ctc/`.

**Résultat benchmark standard (n=150, `eval_error_detection_rules_stripped.py`)** :

| Métrique (n=150) | mixed-e14 | stage1b-260h | **piste 3 finale (4 epochs)** |
|---|---|---|---|
| Détection d'erreur (fidèle) | 65,3% | 64,7% | 64,7% |
| Corrigé à tort (invisible) | 14,7% | 10,7% | 12,7% |
| CER anti-oubli | 9,18% | 6,85% | 7,40% |
| Fidélité harakat (fautes délibérées) | — | — | 55,7% |
| Fidélité lettre (fautes délibérées) | — | — | 72,5% |
| Détection règles tajwid (Mishary, Al-Baqarah) | — | 98% | **100%** (37/37) |

Qualité de transcription solide, meilleure que mixed-e14, comparable à
stage1b-260h. **Mais le gop reste catastrophique sur les mêmes mots**
("ٱللَّهِ", "ٱلرَّحِيمِ"/"ٱلرَّحْمَـٰنِ") même sur ce checkpoint, la piste la
plus propre méthodologiquement des 3 testées — confirmant que ce n'est PAS
un problème de méthode d'entraînement (les 3 pistes, poids/checkpoint/script
différents, échouent identiquement sur les mêmes mots).

**CAUSE RACINE TROUVÉE (mesure sur le dataset, pas plus de conjecture
entraînement)** : la Bismillah est récitée **~44% plus vite en médiane** que
le reste du Coran dans `data/manifest_unified.jsonl` (407 149 clips) —
plusieurs réciteurs à 3-4x le débit normal (AdelKalbani 4,00 mots/s vs
médiane générale 0,86 ; HosseinBousseksso 3,51 ; KhalidAlJalil 3,22),
traitée comme une formule rituelle rapide plutôt qu'un verset posé à réciter.
Ça explique tout d'un coup :
- Pourquoi ce sont TOUJOURS les mêmes mots (Bismillah) qui échouent, peu
  importe la méthode d'entraînement — le facteur commun aux 3 pistes est le
  MÊME corpus, avec ce même biais répété ~une fois par sourate × ~80 réciteurs.
- Pourquoi l'ancien modèle (mixed-e14) s'en sort quand même : il n'a jamais
  eu à trancher "lettre ou symbole de règle" à ces positions précises (pas de
  vocabulaire de règles) — seul le nouveau modèle doit prendre cette décision
  fine exactement là où les données sont le plus bâclées, les deux effets se
  cumulent.

**Vérification indépendante de la sensibilité harakat du gop** (raison
d'être du gop, cf. §"Biais du modèle vers le texte canonique" dans
FONCTIONNALITES_FUTURES.md) : sur 5 clips TTS à harakat délibérément fausse
(`nemo_manifests_mixed/val_errors_annotated.jsonl`, `err_kind=="harakat"`),
forcer le texte canonique attendu contre l'audio réellement différent donne
un gop modeste mais réel (-0,16 à -0,90, contre ~0,00 pour un vrai match) --
3 des 5 exemples resteraient "correct" à tort avec les seuils actuels
(-0.45/-1.60). Le gop remplit donc SEULEMENT PARTIELLEMENT sa mission
d'origine.

**Décision produit finale (2026-07-20 nuit)** :
1. **Ne pas abandonner le gop** (rouvrirait le biais canonique déjà documenté
   que le gop a été construit pour combattre) mais rendre le diff textuel
   (`_realignFromFullText`, déjà présent comme repli, jamais supprimé)
   SÉLECTIONNABLE par l'utilisateur (`JudgementOptions.useGopScoring`,
   toggle dans la feuille de réglages de vérification). Les deux moteurs
   tournent TOUJOURS en parallèle et se journalisent (`[GOP]`/`[TEXTDIFF]`),
   un seul pilote l'affichage — permet de comparer empiriquement sur de
   vraies sessions plutôt que de trancher sur quelques clips hors-ligne.
2. **Retirer le contrôle de prononciation sur les 4 mots de la Bismillah**
   spécifiquement (`RecitedWord.isBasmala`, vrai pour tout segment
   `surah=1/ayah=1` -- couvre Al-Fatiha 1:1 ET la Bismillah insérée devant
   toute autre sourate, texte verbatim identique) : forcés `correct` dans les
   DEUX moteurs de jugement (gop et texte), comme le fait déjà le mode
   "cycle de prière" pour l'ensemble d'Al-Fatiha. Ce n'est pas une faute du
   récitant, c'est un artefact du corpus d'entraînement.

**Piste non tranchée, notée pour plus tard si le besoin revient** :
construire un petit lot de Basmala bien articulées (réciteurs connus pour
une Basmala posée, ou TTS à tempo contrôlé) et fine-tuner spécifiquement
dessus -- viserait à corriger la CAUSE plutôt que de désactiver le contrôle,
mais pas fait à ce jour (le contournement produit ci-dessus est jugé
suffisant pour l'instant).

## 5sexies. Calibration gop par mot (`gop_word_baseline.json`) — généralise le contournement Bismillah (2026-07-20 nuit)

**Constat qui a motivé cette piste** : l'exemption Bismillah (§5quinquies) ne
traite QUE 4 mots codés en dur. Or la mesure sur le dataset laissait
présager que d'autres mots (tout ce qui porte un chadda/gémination) ont le
même défaut structurel. Idée utilisateur : au lieu de repérer les mots
difficiles un par un, calculer une VRAIE ligne de base par mot depuis des
récitations connues comme correctes, et juger l'ÉCART à cette ligne de base
plutôt que le gop brut contre un seuil global.

**Méthode** (`benchmark/build_gop_word_baseline.py`) : modèle piste 3 final
(`fastconformer-quran-mixed-e14-rules-ctc/fastconformer-quran-best.nemo`),
corpus = UNIQUEMENT les clips Coran réels du manifest (`train_wav`/
`train_wav_local`, exclut `tts_augmentation` et `asc` -- seulement des
récitations professionnelles). Alignement forcé sur texte NU (symboles
retirés, comme `alignTarget=training` côté app), mêmes correctifs que
`ForcedAligner.kt` (masquage+renormalisation symboles, exclusion chadda nu).
Regroupé par mot canonique NU (pas de fragmentation selon qu'une règle soit
annotée à cette occurrence précise) ; garde une trace séparée avec/sans
règle attendue pour vérifier si ça change quelque chose.

**Résultat** : 42 927 clips traités sur 59 232 (72,5%, le reste ignoré pour
durée hors bornes ou alignement infaisable), **12 702 mots distincts** avec
assez de données (n≥3). Confirme et généralise largement la piste Bismillah
-- les 20 mots au gop moyen le plus bas sont TOUS des mots à chadda/
gémination ("مِّنَ" moyenne -7,58 sur n=1051, "مِّنْ" -5,62 sur n=557, "مِّن"
-5,47 sur n=1590, "ذَٰلِكَ" -5,26 sur n=1286, "ٱللَّهِ" -3,96 sur n=2803...),
avec des échantillons bien plus larges que ce qu'on avait mesuré à la main.
Un seuil global aurait faussement signalé TOUS ces mots très fréquents en
usage normal.

**Intégration app** : `benchmark/data/gop_word_baseline.json` copié en asset
(`app/assets/data/gop_word_baseline.json`, déclaré dans `pubspec.yaml`),
chargé par `gop_baseline_provider.dart` (même pattern que
`rule_reliability.json`). `RecitationNotifier._normalizedGop(word, rawGop)`
recentre le gop sur la moyenne du mot (`rawGop - baseline.mean`) quand la
ligne de base est assez fiable (n≥5, sinon repli sur le gop brut -- jamais de
régression) ; les seuils existants (`_gopCorrect`/`_gopUnclear`, sensibilité
utilisateur) s'appliquent ensuite SANS changement au gop recentré. Le gop
brut ET le gop recentré sont journalisés (`[GOP] ... gop=X normGop=Y`) pour
comparer facilement.

**Portée de ce correctif** : ne remplace PAS l'exemption Bismillah stricte
(`isBasmala`, garde-fou absolu peu importe la calibration) -- la calibration
gère les cas INTERMÉDIAIRES (mots durs mais pas au point de mériter une
exemption totale), l'exemption gère le cas EXTRÊME déjà identifié.
Complémentaires, pas redondants.

**Pas encore fait** : validation sur device (build compile, installé une
fois, mais pas encore testé en conditions réelles faute de téléphone
reconnecté au moment de l'écriture) ; pas de recalibration automatique si le
modèle change (la table est liée au checkpoint piste 3 précis qui l'a
produite -- à regénérer si le modèle déployé change).

## 5septies. Le corpus de fautes n'a pas de CONTEXTE — mesures et plan (2026-07-31)

**Cause racine du fait qu'une vraie faute passe au vert dans l'app.** Le
manifeste `nemo_manifests_dual` contient 81 380 entrées de fautes délibérées,
mais seulement **16 276 clips distincts**, répétés ~5 fois, et **tous des mots
isolés** (durée médiane 1,71 s, 1 mot, maximum 1) contre 10,40 s et 9 mots pour
le Coran récité. Le modèle n'a donc jamais vu une **phrase** contenant une
faute : il a appris deux régimes disjoints — court = fidèle, long = canonique.
Vérifié sur 12 modèles sur 12.

### Audibilité du corpus — première vérification, jamais faite jusqu'ici

Critère : sur l'audio du clip, `logP(texte étiquette) > logP(texte canonique)`
par alignement forcé. L'alignement forcé n'a rien à réécrire, contrairement au
décodage libre — c'est ce qui le rend insensible au biais canonique du modèle.

| lot | audible | note |
|---|---|---|
| `tts_augmentation` (celui de l'entraînement) | **17 078 / 18 195 = 93,9 %** | ت→ط 99 %, د→ض 99 %, ك→ق 98 %, harakat 84-93 % |
| `tts_paired` (autre script) | 4 077 / 5 339 = 76,4 % | non utilisé à l'entraînement |

⚠️ **Le QA d'origine ne pouvait pas voir ce défaut** : `qa_tts_paired.py`
accepte jusqu'à `CER_REJECT = 0,5` contre le texte demandé, or une réécriture
canonique à une lettre près fait CER 0,17. Il rendait 94 % de clips « OK » sans
jamais mesurer l'audibilité. Sa branche `OK_BIAIS_CANONIQUE` va plus loin :
quand l'ASR entend le canonique, elle **suppose** le biais de l'ASR et garde le
clip (77 cas, effet borné, mais c'est une supposition non vérifiée inscrite
dans un outil de qualité).

### Rendement de XTTS selon ce qu'on lui demande

| demandé à XTTS | fautes audibles |
|---|---|
| 1 mot isolé | **93,9 %** |
| phrase 2-3 mots | 29 % |
| phrase 3-6 mots | 10 % |
| **assemblage de mots synthétisés seuls** (4-8 mots) | 42 %, 57 % au critère à deux faces |

Le TTS a le **même réflexe canonique que l'ASR** : plus il a de contexte, plus
il corrige le texte qu'on lui donne. La substitution l'atteint pourtant bien
(10 séquences de tokens sur 10 diffèrent après le tokenizer XTTS, et le
nettoyeur conserve les harakat) — c'est le modèle acoustique qui corrige.

⇒ **Solution retenue : fabriquer le contexte par assemblage.** Chaque mot est
synthétisé seul (régime fidèle), le clip du mot fauté est **contrôlé**, puis les
mots sont mis bout à bout. La version correcte est assemblée par le **même
chemin à partir des mêmes clips**, à un mot près : sans cette symétrie on
entraînerait un détecteur de montage. Distinct du montage audio mort, qui
remplaçait une frame de 80 ms **dans** un mot ; sa note de décès autorisait
explicitement le mot entier.

### Deux pistes réfutées le même jour — gardées comme telles

| piste | mesure qui la tue |
|---|---|
| `gop` recalculé en **fenêtre étroite** | séparation +0,682 contre +3,595 en fenêtre large, 0/4. Privé de contexte, `free` s'effondre autant que `forced` |
| **Deux passes** (localiser avec contexte, entendre sans) | détecte 100 % mais signale **97-99 % des mots corrects** ; aucun seuil sur le CER ne sépare (médiane 1,000 des deux côtés). L'extraction plafonne à 20 % de mots exacts sur de l'audio **correct**, après calibration du décalage (−4 frames) et de l'étendue (mi-chemin entre voisins). Raison structurelle : le modèle est causal avec 5,6 s de contexte gauche, qu'un extrait découpé en plein flux n'a pas |

### Coût à l'EXÉCUTION — la question qui tranche l'architecture

| | surcoût sur téléphone |
|---|---|
| **3 têtes** | **< 1 %** — l'encodeur porte 94,9 % des paramètres et tourne **une fois** ; une tête est une couche linéaire (512→19 = ~10 k paramètres) |
| deux passes | **~3×** le calcul ASR — 25 extraits par bloc de 10 s, chacun avec son invocation ONNX et son mel |

### Composition proposée, par étape

**Étape 1 — encodeur + tête lettres** (la seule où la composition est un arbitrage) :

| | aujourd'hui | proposé | pourquoi |
|---|---|---|---|
| Coran récité | 77,0 % (260,0 h) | 60 % | le défaut est un **excès** d'a priori canonique — en rajouter l'aggrave |
| fautes **en phrase** | 0 % | 15 % | le régime entièrement absent |
| fautes mot isolé | 12,9 % (43,4 h) | 15 % | rend le modèle fidèle à courte portée, 93,9 % sont bonnes |
| MSA hors Coran | 10,1 % (34,1 h) | 10 % | empêche l'encodeur de supposer que tout est du Coran |

Le point n'est pas le 60 % : c'est que les fautes passent de **12,9 % toutes
isolées** à **30 % dont la moitié en phrase**.

**Étapes 2 et 3 — têtes, encodeur GELÉ.** Chaque tête a son propre jeu de
données, et le gel garantit qu'elles **ne peuvent pas abîmer la transcription**.
La tête « écart au canonique » va à 50/50 fauté/correct : une tête de
classification a besoin des deux classes à parité, et une classe jamais vue ne
sera jamais signalée.

**Garde-fous de l'étape 1** (une case qui se dégrade annule le run) : erreur mot
sur Coran propre ≤ 7,77 %, faux positifs de la chaîne ≤ 2,03 %, invariance au
gain conservée, et **recul de la réécriture canonique** mesuré sur des phrases
tenues à l'écart de l'entraînement (15 %).

Outils : `controle_paires_fautees.py`, `assainir_corpus_fautes.py`,
`generate_phrases_concat.py` (passe 1), `assembler_phrases_fautees.py`
(passe 2), `build_manifest_phrases_fautees.py`.


## 6. Critères de succès / d'arrêt

- **Succès tête stricte** : ≥ epoch14 sur détection lettre/harakat ET
  détection de violations de règles significativement > hasard sur le set
  humain.
- **Succès RNNT** : WER libre < tête CTC sur val canonique (sa raison d'être) ;
  usage limité à la localisation tant que son biais canonique n'est pas mesuré.
- **Succès tête tolérante** : WER squelette ≈ tête stricte normalisée, avec
  moins de faux positifs en mode relâché sur device.
- **Arrêt/pivot** : symboles de règles au hasard sur le set humain → pivot DSP
  (règles) en gardant harakat/lettres ; VRAM ingérable en hybride → retomber
  ctc_loss_weight=1.0 (CTC-only, comportement actuel) sans rien perdre.

## 7. Rollback (garanti à chaque étape)

Nouveau tokenizer = nouveaux dossiers ; le modèle déployé (`mixed-e02`/epoch14)
n'est touché à aucun moment ; le `.nemo` de base et tous les checkpoints
antérieurs restent intacts ; sans `CUDA_HOME`, tout l'outillage retombe en
mode CTC-only identique à avant le 2026-07-19.
