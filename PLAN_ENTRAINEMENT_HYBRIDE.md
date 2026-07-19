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
