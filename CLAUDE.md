# Coran Karim — guide agent (index, le détail vit dans les .md dédiés)

App Android (Flutter/Kotlin) de récitation coranique : vérification ASR
(FastConformer CTC + Whisper), tuteur textuel (Gemma LoRA), révision (FSRS).
3 piliers, 3 technos — cf. `ARCHITECTURE.md`.

## Documents de référence — lire AVANT d'agir sur le sujet correspondant

| Sujet | Document |
|---|---|
| Point d'entrée courant, changement de machine, état git | `HANDOFF.md` (à tenir à jour) |
| Chantier en cours : tête 3 / écart canonique, et ce qui bloque | `SUITE_TETE3.md` |
| État complet piste NeMo CTC : modèles, WER, déploiement, reste à faire | `ETAT_CTC_NEMO.md` |
| Mémoire technique ASR détaillée (pièges, décisions, méthodes) | `.claude/skills/model-training/references/asr.md` |
| Tuteur Gemma LoRA (bug regex, QAT, datasets) | `.claude/skills/model-training/references/gemma-llm.md` |
| Historique des benchmarks et décisions chiffrées | `benchmark/BENCHMARK_RESULTS.md` |
| Idées validées non implémentées (madd, fenêtre glissante...) | `FONCTIONNALITES_FUTURES.md` |
| Plan/stratégie du run hybride 3 têtes (RNNT + CTC strict/tolérant) | `PLAN_ENTRAINEMENT_HYBRIDE.md` |
| Glossaire des techniques (entraînement vs décodage, qui sert quoi) | `GLOSSAIRE_TECHNIQUES_ASR.md` |
| Problématiques ASR (buffer, GOP, pauses) + état de l'art externe (forums/papers) | `PROBLEMATIQUES_ASR.md` |
| Refonte IHM (presets de tolérance, navigation, plein écran, mindmap) | `REFONTE_IHM.md` |
| Chantier "Suivre une prière" (journal détaillé) | `SUIVI_PRIERE.md` |

Tout entraînement/export/diagnostic de modèle : invoquer le skill
`model-training` d'abord.

Toute analyse d'une session de récitation sur device (« regarde la log »,
« analyse », « qu'est-ce qui cloche ») : invoquer le skill
`analyse-session-recitation`. Il encode la méthode ET les erreurs de méthode
réellement commises le 2026-07-26/27 — omettre les mots non jugés, confondre
cadence et latence, conclure sur un log tronqué, croire les clips alors que 35 %
de l'audio n'y était pas écrit. Sans lui, ces erreurs se répètent : elles se
sont répétées une dizaine de fois en une journée.

Avant d'écrire un correctif sur la chaîne de récitation — et impérativement dès
qu'on s'apprête à toucher un seuil, une tolérance, un critère de jugement, ou à
ajouter un mécanisme de rattrapage : invoquer le skill `solution-de-fond`. Il
encode le test des trois questions (est-ce que je déplace un critère
d'acceptation ? est-ce que je mets le modèle dans les conditions où il
RÉUSSIT ? quelle classe de correctifs je n'aurai plus jamais à écrire ?) et le
préalable de mesure. Écrit le 2026-07-28 après trois correctifs dans la même
séance dont **deux palliatifs**, repérés par l'utilisateur et non par l'agent.

**APRÈS chaque modification de la chaîne de récitation — sans exception et sans
attendre qu'on le demande : invoquer le skill `superviseur-recette`.** Il
contrôle que l'application fait toujours ce pour quoi elle existe (l'ancre suit
le récitateur, aucun verdict sans preuve acoustique, aucun audio détruit, temps
réel tenu) AVANT de parler de taux. Un gain de taux obtenu en dégradant l'un de
ces points est un faux gain, à rejeter. Consigne utilisateur 2026-07-30 : « j'en
ai marre de tes corrections qui cassent beaucoup de choses » — l'agent qui écrit
un correctif est le plus mal placé pour en constater les dégâts, il cherche la
confirmation de son hypothèse et non la régression qu'il vient d'introduire.
Le superviseur est le contrôle **derrière** l'agent, pas devant.
Il commence désormais par **interroger le graphe** (`GRAPHE_RECITATION.md`) :
un mécanisme déjà mesuré perdant (`[MORT]`) réintroduit sans cause nouvelle
**nommée** est un refus bloquant, comme un correctif dont le graphe dit que le
symptôme naît dans une couche plus haute (palliatif).

Le hook `.claude/hooks/exige-superviseur.py` rend l'obligation réelle en
bloquant le gel de version tant qu'aucune **preuve** ne date d'après la
modification. Deux natures de preuve depuis le 2026-07-30 :
- fichier de la chaîne **live** (celle qui peint l'écran) → **recette à deux
  téléphones**, comme avant ;
- fichier **non branché** (`recitation2/`, bancs) → **tests JVM au vert**. Le
  hook a été écrit pendant la phase où l'on retouchait sans fin une chaîne déjà
  branchée ; exiger une recette d'un code que rien n'appelle n'ajoute aucune
  sécurité et pousse à accumuler du travail non commité — précisément ce qui a
  fait perdre neuf versions mesurées, dont la meilleure du projet.
  ⚠️ Le jour où la v2 est branchée à l'écran, elle sort de `HORS_LIGNE` et
  repasse à la recette.

Banc de recette à deux téléphones : `./benchmark/recette_2tel.sh <sourate>
<durée>` (une commande, aucun tap). Les téléphones sont sur un autre poste :
`benchmark/adb_pcb.sh` pilote adb à distance, `benchmark/installer_pcb.sh`
transfère et installe l'APK. `benchmark/verifier_erreurs.py` confronte chaque
mot signalé au modèle sur l'audio brut — un mot que le modèle lit correctement
est un faux positif de la chaîne, pas une faute de récitation.

Dès que le même bout de code en est à sa 4ᵉ/5ᵉ version dans la session, qu'un
symptôme déjà corrigé réapparaît, ou qu'on retombe sur une piste déjà tentée :
invoquer le skill `recul-architectural` — arrêt du code, analyse structurelle,
état de l'art, pistes à faire arbitrer. Garde-fou anti-boucle (2026-07-26).
Le déclenchement est **automatique** : le hook `.claude/hooks/detect-boucle.py`
(branché dans `.claude/settings.json`) compte les réécritures successives d'un
même passage et injecte le rappel tout seul — un agent qui boucle ne se voit
pas boucler, il ne faut pas compter sur son jugement. Seuil réglable en tête du
script (`REGION_CHURN_TRIGGER`), calibré avec l'utilisateur le 2026-07-26.

Après toute modification d'un écran ou flux **avec état** (lecteur audio,
enregistreur, navigation, formulaire) — avant de déclarer que c'est corrigé —
invoquer le skill `scenarios-utilisateur` : il fait passer une checklist
d'axes (interruption, répétition rapide, changement de cible en cours
d'action, reprise après coupure, ressource indisponible, concurrence) au lieu
de ne tester que le chemin qu'on vient de corriger. Écrit le 2026-08-01 après
que le bug du bouton play/pause du Mushaf, corrigé et vérifié par logs sur
son chemin testé (play→pause→resume), a immédiatement révélé un second bug
sur un chemin voisin jamais essayé (lire puis revenir en arrière).

## Règles du projet (décisions utilisateur, ne pas re-dériver)

- **Aucune piste n'est éliminée tant que le retour en arrière est possible**
  (décision 2026-07-19). Concrètement : ne JAMAIS écraser un checkpoint,
  chaque nouveau run va dans un nouveau dossier `benchmark/models/...`, les
  modèles déployés sont préservés dans `benchmark/models_deployes/`, le
  `.nemo` de base NVIDIA n'est jamais modifié.
  → Corollaire : pour libérer de l'espace, on **déplace** un run vers le HDD,
  on ne le supprime jamais (cf. §"Runs archivés sur le HDD" plus bas). Un
  dossier absent de `benchmark/models/` n'est donc PAS une preuve que le run
  n'existe plus — vérifier le HDD avant de conclure ou de relancer.
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
- **Avant tout changement important (nouvelle fonctionnalité, refonte,
  branchement d'une piste dans l'app...), committer d'abord l'état courant**
  (décision 2026-07-19) — même partiellement/par périmètre si besoin (cf.
  règle ci-dessus). Sans ce point de départ propre, impossible de distinguer
  après coup ce qui appartenait à la session précédente de ce que le
  changement en cours a introduit, et aucun retour en arrière ciblé n'est
  possible (cf. "aucune piste n'est éliminée tant que le retour en arrière
  est possible" plus haut — un commit est CE point de retour).
  → **Comment faire ce commit concrètement** (ajouté 2026-07-23 après un
  rappel de l'utilisateur : la règle existait, elle a quand même été oubliée
  au moment de coder). L'arbre de travail porte en permanence un **gros état
  non commité PRÉEXISTANT** — mesuré ce jour-là : 147 fichiers modifiés sous
  `app/`, **115 fichiers supprimés** (`app/assets/mindmaps/*.json`,
  `.claude/scheduled_tasks.lock`...), plus des dossiers non suivis
  (`app/android/build/`, `HANDOFF_UBUNTU*.md`, mindmaps `ar/en/fr/`).
  Ce bruit n'appartient PAS à la session en cours.
  ⇒ **Ne JAMAIS faire `git add -A` / `git commit -a`.** Committer fichier par
  fichier, en connaissance de cause.
  ⇒ Pour isoler ce que la session a réellement touché, comparer les dates de
  modification au timestamp du dernier commit — c'est fiable et instantané :
  ```bash
  git status --porcelain | grep "^ M" | sed 's/^ M //' | while read -r f; do
    m=$(stat -c %Y "$f"); [ "$m" -gt "$(git log -1 --format=%ct)" ] && \
      echo "$(date -d @$m +%H:%M)  $f"
  done | sort
  ```

- **Toucher à la segmentation ASR (`BufferedTranscriber`) sans mesure préalable
  hors device = perte de temps garantie** (décision 2026-07-23, après une
  journée entière). Ce jour-là, QUATRE correctifs « évidents » ont été testés
  et **tous rejetés par la mesure** : stats de normalisation fixes (ne corrige
  rien ET +1,28 pt de WER), désactivation du portier RMS (70,2 % contre
  22,8 %), coupe à chaque pause (103,5 %), fenêtre glissante naïve (WER > 100 %
  par duplication de texte). Le code en place s'est révélé le moins mauvais.
  Bancs à utiliser AVANT de modifier une ligne de Kotlin :
  | Banc | Ce qu'il répond |
  |---|---|
  | `benchmark/analyze_device_log.py <log>` | ce qu'a vraiment fait l'app (texte figé, blocages d'ancre, audio jeté par le portier, régressions d'aperçu) |
  | `benchmark/simulate_sliding_window.py` | rejoue une politique de segmentation bloc par bloc sur du vrai audio et sort son WER |
  | `benchmark/test_norm_fixed_vs_perfeature.py` | effet de la normalisation, du silence et de la longueur du buffer |
  Détail des mesures et des trois hypothèses mortes : `FONCTIONNALITES_FUTURES.md` §4.
- **Export ONNX vers l'app : TOUJOURS `audio_signal` (mel), JAMAIS `raw_audio`**
  (piège tombé DEUX fois : 2026-07-13 puis 2026-07-19). Le plugin Kotlin
  calcule le mel-spectrogramme lui-même (`MelSpectrogram.kt`) et appelle le
  modèle avec `{"audio_signal": mel (batch,80,time), "length"}`. Un export
  "E2E" (`raw_audio` → preprocessor+encoder+ctc, cf. les scripts
  `export_*_full_pipeline.py`) valide pourtant très bien PyTorch==ONNX — il
  est juste **inutilisable par l'app** : le modèle se charge (`Modèle
  chargé : true`, rassurant et trompeur) mais CHAQUE transcription échoue en
  silence avec `[BufferedTranscriber] echec retranscription: Unknown input
  name audio_signal, expected one of [raw_audio, length]` → aucune
  transcription, aucun suivi, aucune coloration.
  → Partir de `export_tajweed_checkpoint.py` ou
  `export_rules_260h_checkpoint.py` (wrapper encodeur+ctc_decoder seul),
  jamais d'un `*_full_pipeline.py`.
  → **Vérification obligatoire avant tout déploiement** (doit afficher
  `audio_signal`) :
  `python3 -c "import onnxruntime as ort; print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"`
  → Corollaire de diagnostic : "le modèle est chargé" ne prouve RIEN sur son
  utilisabilité. Toujours vérifier une vraie transcription (log natif
  `DiagnosticLog`/logcat), pas seulement la ligne de chargement.
- **PROPOSER ET FAIRE VALIDER AVANT DE DÉVELOPPER** (consigne utilisateur
  2026-07-25, après deux correctifs implémentés sans accord qui ont dégradé
  l'app). Sur toute modification de la chaîne de récitation (ASR, buffer,
  segmentation, jugement) : **exposer d'abord** la cause identifiée, le
  correctif envisagé, et **les effets de bord attendus** — puis ATTENDRE la
  validation. Ne pas coder, ne pas builder, ne pas installer avant.
  → Ce qui a motivé la consigne : j'ai ajouté une borne de gel en temps réel
  (5 s) pour réduire le retard de validation, **en ayant moi-même identifié
  et écrit** que cela ferait tomber les coupes en plein mot. Mesuré après
  coup : retard 43 s → 8 s, mais segments coupés en plein mot 5/7 → 11/14, et
  beaucoup de rouge à l'écran. J'ai ensuite empilé un second correctif
  (« armer le gel, attendre un silence bref ») toujours sans validation.
  ⇒ Règle absolue : **si un effet de bord est identifié pendant l'analyse, il
  interdit l'implémentation directe** — il doit être présenté et arbitré par
  l'utilisateur, pas « assumé » unilatéralement puis mesuré après coup sur
  son temps.
  ⇒ Ne jamais enchaîner un correctif sur un correctif non validé.
- **PAS DE CORRECTIF PALLIATIF — chercher et traiter la cause d'origine**
  (consigne utilisateur 2026-07-25, après un correctif proposé puis refusé).
  Un correctif qui neutralise un **symptôme** dans une couche AVAL alors que
  le défaut NAÎT dans une couche AMONT est à rejeter, même s'il "règle" le cas
  observé dans le log.
  → Cas concret qui a motivé la consigne : les troncatures de capture du
  buffer (mot coupé en plein milieu) produisaient de faux rouges (9 contre 4
  vraies fautes sur une session). Correctif tenté : requalifier `correct` tout
  mot dont le texte entendu est un fragment cohérent de l'attendu, dans la
  couche de JUGEMENT (`_onAligned`). Effet de bord inacceptable relevé par
  l'utilisateur : **un récitateur qui ne dit que la moitié d'un mot était
  alors validé** — précisément ce que l'app existe pour détecter. La cause
  réelle est la coupe en plein mot dans `BufferedTranscriber` ; c'est là qu'il
  faut travailler (recouvrement d'audio au gel, coupe qui évite le milieu d'un
  mot), pas ajouter de la tolérance en aval.
  ⇒ Méthode imposée avant tout correctif :
  1. **Identifier la couche où le défaut naît**, pas celle où il se voit
     (remonter : jugement → alignement → buffer/segmentation → capture/micro).
  2. Si la cause est en amont, **le dire** et proposer le travail de fond avec
     la mesure requise — quitte à ne rien livrer immédiatement. Ne pas
     "dépanner" en attendant.
  3. **Ne jamais compenser une perte d'information d'une couche basse par une
     tolérance ajoutée dans une couche haute** : ça dégrade la fonction
     première (vérifier la récitation) et masque le vrai défaut, qui devient
     ensuite invisible dans les logs.
  4. Un palliatif n'est acceptable QUE s'il est explicitement demandé, borné
     dans le temps, et documenté comme tel (avec la cause d'origine nommée).
- **NE JAMAIS REPORTER UNE ACTION EN INVOQUANT L'HEURE OU LE MOMENT** (décision
  utilisateur 2026-08-01, après avoir refusé de tester WhisperX pour le
  décalage "pas ce soir, une autre fois avec un vrai budget de
  vérification") : « arrête de me parler en précisant le temps, ce soir/demain
  c'est pas toi qui décide de reporter ». Si une ressource manque ou qu'une
  action reste à faire et que les moyens de la faire sont disponibles (accès
  réseau, environnement installable, GPU libre...), elle se fait — le moment
  de la journée n'est jamais un critère pour reporter. Reporter n'est légitime
  que pour une vraie raison technique (ressource indisponible, dépendance
  bloquante, décision qui doit être arbitrée) — jamais parce qu'il est tard.
- **Ne JAMAIS supprimer un commentaire existant qui documente une tentative
  passée, un piège ou un "pourquoi"** (décision 2026-07-19, suite à un doute
  légitime de l'utilisateur sur le rescoring NLL : sans cette règle, un futur
  agent ne peut plus distinguer "jamais essayé" de "essayé et retiré sans
  laisser de trace"). Si une approche documentée dans un commentaire ne
  marche plus ou est remplacée : **ajouter** une note à côté expliquant que
  ça ne marche pas/plus (et pourquoi), ne pas effacer le commentaire
  d'origine. Ces commentaires sont la seule trace fiable de ce qui a déjà été
  tenté — les faire disparaître fait perdre cette mémoire pour de bon, aucun
  historique git ne compense un agent qui ne pense pas à `git log -p` avant
  d'agir.

## Spécificités de CETTE machine (Ubuntu, RTX 5080 16 Go)

- **Chemin projet** : `/media/kafai/NouveauNom/Coran Karim` (espace dans le
  nom → attention sentencepiece et scripts shell). L'audio d'entraînement
  volumineux est sur le disque externe : `/run/media/kafai/HDD/Coran Karim/`.
- **La partition RACINE (`/`) ne fait que 97 Go, partagée avec l'OS** —
  distincte du SSD projet (`/media/kafai/NouveauNom`, 742 Go) et du HDD
  (`/run/media/kafai/HDD`, plusieurs To libres). Piège payé le 2026-08-01 :
  l'installation de WhisperX + le téléchargement d'un modèle HuggingFace ont
  rempli `/` (`~/.cache/huggingface`, `~/.cache/pip`) jusqu'à moins de 1 Go
  libre, sans lien avec l'espace du SSD projet (qui avait 86 Go libres au même
  moment). `HF_HOME` et `PIP_CACHE_DIR` sont redirigés vers le HDD dans
  `~/.bashrc` (`/run/media/kafai/HDD/caches/`) — **toujours vérifier `df -h /`
  avant un `pip install` ou un téléchargement de modèle**, l'espace du SSD
  projet ne dit rien sur l'espace de la partition système.
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
- **Les deux disques sont en NTFS** : SSD monté en `fuseblk` (ntfs-3g), HDD en
  `ntfs3`. Conséquences : pas de permissions POSIX fiables (utiliser
  `rsync --no-perms --no-owner --no-group`, sinon erreurs à répétition), et
  les caractères `: ? * < > | "` sont **interdits** dans les noms de fichiers
  — vérifier avant toute copie de checkpoints, un nom invalide fait échouer la
  copie. Les `=` des noms NeMo (`epoch=09-val_wer_ctc=0.059.ckpt`) passent
  sans problème. Les symlinks fonctionnent malgré le symlink cassé du venv
  (celui-ci vient d'un reparse tag Windows, pas d'une limite du FS).

## Runs archivés sur le HDD (2026-07-20) — CHERCHER ICI avant de conclure

Pour libérer le SSD (79 Go → 180 Go libres), 20 runs terminés ont été
**déplacés** (jamais supprimés) du SSD vers le HDD, **en conservant le chemin
relatif** — seule la racine disque change :

```
/media/kafai/NouveauNom/Coran Karim/benchmark/models/<X>   (SSD, avant)
/run/media/kafai/HDD/Coran Karim/benchmark/models/<X>      (HDD, maintenant)
```

Chaque dossier a été copié puis vérifié (nombre de fichiers **et** taille en
octets identiques) avant suppression de la source — 20/20 OK, aucun échec.

**Runs déplacés** (~105 Go) :
- **Toute la piste Whisper** (15 dossiers) : `whisper-medium-ft`,
  `whisper-small-ft`, `whisper-small-ft-clean`, `whisper-medium-ft-fixed-tok`,
  `whisper-medium-ft-onnx`, `whisper-medium-ft-onnx-int8`, `whisper-full-ft`,
  `whisper-largev3turbo-quran`, `whisper-medium-quran`, `whisper-phase4-noisy`,
  `whisper-base-ft`, `whisper-small-ft-onnx`, `whisper-small-ft-onnx-int8`,
  `whisper-medium-sherpa`, `whisper-tiny-ar-quran`
- **FastConformer pré-tajweed** : `fastconformer-quran`,
  `fastconformer-quran-augmented`, `fastconformer-quran-pcd`
- **Gros Gemma régénérables** : `gemma-4-E2B-it` (modèle de base),
  `gemma-4-E2B-tutor-v6-merged`

**Restés sur le SSD** (pistes actives ou récentes, accès rapide) :
`fastconformer-quran-hybrid-v1` (run hybride en cours),
`fastconformer-quran-tajweed-mixed` (source du modèle déployé, epoch 14),
`fastconformer-quran-tajweed`, `-tajweed-v2`, `-tajweed-augmented`, les LoRA
Gemma, `sherpa-arabic-*`. `benchmark/models_deployes/` n'a pas été touché.

⚠️ Un run archivé reste **parfaitement utilisable** : il suffit de pointer le
chemin HDD, ou de le recopier sur le SSD si l'I/O compte. Ne jamais le
réentraîner en croyant qu'il a été perdu.

Non déplacé volontairement : `benchmark/data/train_wav_local/` (213 Go) est un
**doublon exact** de `/run/media/kafai/HDD/Coran Karim/benchmark/data/train_wav/`
(414 569 fichiers de chaque côté, arborescences identiques, MD5 identiques sur
échantillon). Décision utilisateur 2026-07-20 : on garde la copie SSD pour la
vitesse d'entraînement (414 k petits fichiers en accès aléatoire depuis un
disque à plateaux = goulot d'étranglement probable). C'est la réserve d'espace
la plus évidente si le SSD resature — la supprimer ne perd aucune donnée.
