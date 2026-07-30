# Graph Report - .  (2026-07-30)

## Corpus Check
- 99 files · ~246,132 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1436 nodes · 2394 edges · 96 communities (78 shown, 18 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 120 edges (avg confidence: 0.93)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Provider de recitation (jugement Dart)
- ForcedAligner (DP CTC)
- Provider de lecture audio
- COUCHE 3 - Buffer et segmentation
- Etat de recitation (modele Dart)
- Pistes de coupe EN ATTENTE + commits
- COUCHE 5 - Alignement + bascule causale
- Portier RMS, VAD et bancs de mesure
- Amorcage de l'application
- COUCHE 4 - Mel + inference ONNX
- Export ONNX des checkpoints
- Bancs 2-tetes (dual-head)
- Options de jugement (prereglages)
- Etat du lecteur
- Revision des erreurs
- Provider des seuils de jugement
- COUCHE 6 - Jugement et affichage
- Durees de reference et mots frontiere
- Branches de test GOP (revert cibles)
- Resync et branches d'experimentation
- BufferedTranscriber (symboles AST)
- Modele de verset
- Contexte droit + traces de diagnostic
- Selection du reciteur
- MelSpectrogram (symboles AST)
- Piste RNNT hybride 3 tetes
- Baseline GOP par mot
- Banc du double decoupage
- Banc de la fenetre glissante
- Resync sur apercu (REFUTE)
- COUCHES 1-2 - Micro et transport
- FastConformerCtc (symboles AST)
- RescueBuffer (symboles AST)
- Banc d'appariement global
- StreamingModelConfig (contrat causal)
- Bancs ancre et arbitrage resync
- Banc de normalisation fixe
- Deploiement 260h + refonte IHM
- CausalAlignmentSession (symboles AST)
- Modele de reciteur
- VERROU SUR APERCU et palliatifs retires
- Banc des politiques de coupe
- Banc de rescoring par variantes
- Bascule vers le modele causal
- SYMPTOMES - ou ils naissent vs ou ils se voient
- Banc de normalisation causale
- Utilitaires de banc communs
- Confrontation des erreurs au modele
- WavReader / WavWriter
- Plugin d'enregistrement audio
- Resume de log de recitation
- Tableau de session
- Moteur Kotlin (AST)
- Groupe 53
- Banc de mesure
- Banc de mesure
- Moteur Kotlin (AST)
- Code Dart (AST)
- Banc de mesure
- Banc de mesure
- Banc de mesure
- Code Dart (AST)
- Code Dart (AST)
- Code Dart (AST)
- Banc de mesure
- Banc de mesure
- Grappe de commits lies
- Grappe de commits lies
- Pistes MORTES (mesurees perdantes)
- Moteur Kotlin (AST)
- Banc de mesure
- Banc de mesure
- Banc de mesure
- Banc de mesure
- Moteur Kotlin (AST)
- Moteur Kotlin (AST)
- Moteur Kotlin (AST)
- Banc de mesure
- Grappe de commits lies
- Banc de mesure
- Banc de mesure
- Pistes MORTES (mesurees perdantes)
- Pistes MORTES (mesurees perdantes)
- Code Dart (AST)
- Pistes EN ATTENTE
- Banc de mesure
- Banc de mesure
- Grappe de commits lies
- Grappe de commits lies
- Pistes MORTES (mesurees perdantes)
- PIEGES deja rencontres
- REGLES de methode
- REGLES de methode

## God Nodes (most connected - your core abstractions)
1. `2026-07-11 Commit initial — Coran Karim` - 112 edges
2. `③ Buffer et segmentation (Kotlin)` - 82 edges
3. `2026-07-25 Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuv` - 52 edges
4. `2026-07-12 Refonte ASR (GOP forced-alignment), récitation continue, cascade d'explications offline` - 47 edges
5. `④ Inference ASR (mel + ONNX)` - 39 edges
6. `2026-07-23 Revert ciblé du moteur ASR vers l'état avant les 2 GOP (a2d3054), test isolé` - 38 edges
7. `2026-07-23 Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat` - 38 edges
8. `2026-07-19 Coran 100% local (fini le "Connexion requise" hors-ligne), rescoring NLL diagnostique, correcti` - 34 edges
9. `2026-07-26 feat: porte le moteur Android sur le causal stateful` - 33 edges
10. `⑥ Jugement et affichage (Dart)` - 32 edges

## Surprising Connections (you probably didn't know these)
- `CONFUSIONS = Map<Char, CharArray> = mapOf(` --implements--> `③ Buffer et segmentation (Kotlin)`  [EXTRACTED]
  app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ConfusableVariants.kt → CHAINE_RECITATION.md
- `EXPECTED_CHANNEL_CACHE_SHAPE = listOf(1L, 17L, 70L, 512L)` --implements--> `③ Buffer et segmentation (Kotlin)`  [EXTRACTED]
  app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/StreamingModelConfig.kt → CHAINE_RECITATION.md
- `EXPECTED_INPUT_NAMES = setOf(` --implements--> `③ Buffer et segmentation (Kotlin)`  [EXTRACTED]
  app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerStreamingSession.kt → CHAINE_RECITATION.md
- `EXPECTED_TIME_CACHE_SHAPE = listOf(1L, 17L, 512L, 8L)` --implements--> `③ Buffer et segmentation (Kotlin)`  [EXTRACTED]
  app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/StreamingModelConfig.kt → CHAINE_RECITATION.md
- `HARAKAT = "ًٌٍَُِْ"` --implements--> `③ Buffer et segmentation (Kotlin)`  [EXTRACTED]
  app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ConfusableVariants.kt → CHAINE_RECITATION.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Chaine complete micro -> couleur affichee** — couche_1_micro, couche_2_transport, couche_3_buffer, couche_4_asr, couche_5_alignement, couche_6_jugement [EXTRACTED 1.00]
- **Commits touchant RESYNC_ACTIF** — commit_db98d26, commit_bca8706, commit_a0c8935, commit_41df3e3 [EXTRACTED 1.00]
- **Commits touchant MAX_SILENCE_SAMPLES** — commit_bca8706, commit_827be11, commit_08556f8, commit_c9c531f, commit_5b14b8d, commit_e800305 [EXTRACTED 1.00]
- **Commits touchant MAX_SEGMENT_SECONDS** — commit_db98d26, commit_a786239, commit_2ced1b1, commit_827be11, commit_196bff1, commit_08556f8, commit_58db2fa, commit_4b42b4a, commit_24d7521, commit_ed2ca8a, commit_5b14b8d, commit_d671c33 [EXTRACTED 1.00]
- **Commits touchant RIGHT_CONTEXT_SECONDS** — commit_bca8706, commit_d709c7d, commit_a0c8935, commit_363a3a1 [EXTRACTED 1.00]
- **Commits touchant OVERLAP_SECONDS** — commit_cd5c0f0, commit_58db2fa, commit_4b42b4a, commit_24d7521, commit_ed2ca8a, commit_5b14b8d, commit_d671c33 [EXTRACTED 1.00]
- **Commits touchant MIN_FRAMES_FOR_JUDGMENT** — commit_827be11, commit_08556f8, commit_d9418ce, commit_86dfb91, commit_548fe14, commit_22b27e3, commit_fc506f6 [EXTRACTED 1.00]
- **Commits touchant SILENCE_RMS_THRESHOLD** — commit_a786239, commit_9a7efa7, commit_08556f8, commit_d06c6ee, commit_c9c531f, commit_5b14b8d, commit_e800305 [EXTRACTED 1.00]
- **Commits touchant DEFAULT_COMMIT_SILENCE_MS** — commit_827be11, commit_08556f8, commit_3af3501, commit_ab23576, commit_5b14b8d, commit_e800305 [EXTRACTED 1.00]
- **Commits touchant MIN_NEW_SECONDS** — commit_08556f8, commit_5b14b8d, commit_e800305 [EXTRACTED 1.00]
- **Commits touchant MIN_COMMIT_SECONDS** — commit_827be11, commit_08556f8, commit_5b14b8d, commit_548fe14, commit_e800305 [EXTRACTED 1.00]
- **Commits touchant MIN_RESYNC_HITS** — commit_bca8706, commit_a0c8935, commit_934b6e7, commit_4606d64, commit_eb231af [EXTRACTED 1.00]
- **Pistes MORTES - mesurees perdantes, ne pas reintroduire** — mort_rayon_coupe_2s, mort_resync_sur_apercu, mort_relachement_proportion, mort_sonde_4_lettres, mort_conserve_zero, mort_portier_rms_desactive, mort_coupe_chaque_pause, mort_fenetre_glissante_naive, mort_stats_normalisation_fixes, mort_validation_groupee_gop, mort_cache_aware, mort_anneau_120s_cause, mort_harakat_rescoring, mort_entrainement_on_device [EXTRACTED 1.00]
- **Pistes EN ATTENTE - recuperables par git show** — attente_contexte_droit_dp, attente_borne_droite_coupe, attente_cible_etendue, attente_coupe_fin_de_mot, attente_max_silence_09, attente_resync_texte, attente_buffer_decale, attente_rescoring_letter, attente_vad_silero, attente_mel_incremental [EXTRACTED 1.00]
- **PIEGES - erreurs deja commises, souvent plusieurs fois** — piege_audio_signal, piege_val_wer_ctc, piege_deux_echelles_temps, piege_gop_vs_free, piege_ctcmin_vs_plausible, piege_35pct_audio_absent, piege_verrou_sur_apercu, piege_resync_avant_seulement, piege_normalisation_dicte_archi, piege_moitie_logique_compense, piege_gop_relatif, piege_9_versions_perdues, piege_arbitrer_resync_faux, piege_tokenize_greedy, piege_waqf [EXTRACTED 1.00]
- **Symptomes : couche ou ils se voient vs couche ou ils naissent** — sympt_mot_tronque, sympt_entendu_vide, sympt_mot_jamais_place, sympt_bloc_abandonne, sympt_charabia, sympt_audio_jamais_consomme, sympt_faux_positifs, sympt_decrochage, sympt_lag_validation, sympt_coupe_plein_mot [EXTRACTED 1.00]
- **REGLES DE METHODE - garde-fou de process** — regle_pas_de_palliatif, regle_mesure_avant_kotlin, regle_un_seul_changement, regle_jamais_ecraser, regle_identifier_la_couche, regle_correlation_causalite, regle_preuve_acoustique [EXTRACTED 1.00]

## Communities (96 total, 18 thin omitted)

### Community 0 - "Provider de recitation (jugement Dart)"
Cohesion: 0.01
Nodes (189): _activeRules, _alignChunk, _alignSub, _anchorExp, _applyDiagnosticCapture, applyGopWordBaseline, applyJudgementOptions, applyRuleReliability (+181 more)

### Community 1 - "ForcedAligner (DP CTC)"
Cohesion: 0.06
Nodes (23): BufferedTranscriber, BooleanArray, DoubleArray, FloatArray, IntArray, Zone, CtcOutputs, DetectedRule (+15 more)

### Community 2 - "Provider de lecture audio"
Cohesion: 0.04
Nodes (46): _advance, dispose, _kPrefReciterId, next, _onComplete, pause, play, playerProvider (+38 more)

### Community 3 - "COUCHE 3 - Buffer et segmentation"
Cohesion: 0.05
Nodes (46): 2026-07-11 Commit initial — Coran Karim, 2026-07-26 feat: porte le moteur Android sur le causal stateful, _kMaxSegmentMs (constante), _kMinSegmentMs (constante), _kSilenceCutMs (constante), _kSilenceDbfs (constante), CACHE_LEN (constante), CHUNK_FRAMES (constante) (+38 more)

### Community 4 - "Etat de recitation (modele Dart)"
Cohesion: 0.06
Nodes (42): [EN ATTENTE] Mel incremental + FFT iterative, 2026-07-12 Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android, 2026-07-12 Revert "Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android", 2026-07-26 feat: verrouille le contrat du modèle causal, 2026-07-12 Documente l'échec de l'entraînement 100% on-device (ONNX Runtime Training), ④ Inference ASR (mel + ONNX), computeAll(pcm), computeLogProbs(pcm) (+34 more)

### Community 5 - "Pistes de coupe EN ATTENTE + commits"
Cohesion: 0.14
Nodes (37): [EN ATTENTE] Contexte droit AUSSI a la DP, [EN ATTENTE] MAX_SILENCE_SAMPLES 0,3 s -> 0,9 s, [EN ATTENTE] Resync comparant du TEXTE (et non des ids de tokens), branche chunkwise-aligner, 2026-07-28 Sort le gel a la borne dure du thread audio, et cesse d'ecrire l'audio deux fois, 2026-07-28 Contexte des DEUX cotes pour l'encodeur, jugement seulement au centre, 2026-07-28 Pilotage des telephones a distance, et confrontation systematique au modele, 2026-07-29 v23 : le resync est coupe, et la mesure lui donne tort (8,16 % -> 6,12 %) (+29 more)

### Community 6 - "COUCHE 5 - Alignement + bascule causale"
Cohesion: 0.05
Nodes (33): ③ Buffer et segmentation (Kotlin), energieParFrame(audio, nFrames), feed(newSamples, scope), fenetreDeRecherche(wordIndex), horodater(words, origin, spf), indexOfSub(list, sub, from), RescueBuffer.append(samples), rmsAt(buf, from, len) (+25 more)

### Community 7 - "Portier RMS, VAD et bancs de mesure"
Cohesion: 0.06
Nodes (34): alignTarget, continuous, copyWith, correctCount, detectedRules, display, errorCount, expectedRules (+26 more)

### Community 8 - "Amorcage de l'application"
Cohesion: 0.17
Nodes (34): [EN ATTENTE] VAD reel (Silero, ~1 Mo), branche asr-nemo-solutions, 2026-07-25 Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuv, 2026-07-25 Rend la correction immediate : 15,9 s -> 0,003 s avant le retour de l'ancre, 2026-07-16 Revue d'architecture karaoké + plan d'exécution P0/P1/P2 (Fable), 2026-07-28 Recul architectural : 12 faux positifs sur 12, le modele hors de cause, 2026-07-24 Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe, 2026-07-23 Bancs de mesure pour la segmentation ASR + option stats fixes dans mel_numpy_reference (+26 more)

### Community 9 - "COUCHE 4 - Mel + inference ONNX"
Cohesion: 0.07
Nodes (28): active, _aiguiller, _buildNav, _canal, createState, _ecran, icon, init (+20 more)

### Community 10 - "Export ONNX des checkpoints"
Cohesion: 0.08
Nodes (28): 2026-07-29 Les regressions massives n'existaient pas : je comptais deux recitations pour une, 2026-07-29 Banc : ou est l'ancre contre ou en est VRAIMENT le reciteur, seconde par seconde, 2026-07-29 Skill : le mot SAUTE, quatrieme facon de ne pas etre vert -- et la seule invisible, 2026-07-29 Recul architectural : l'ancre decroche parce que le verdict d'apercu est jete, pas parce qu'on , 2026-07-29 Banc : les mots enjambes par le resync sont-ils recuperables ?, 2026-07-29 Le resync ne devine plus : il aligne aux deux ancres et garde la meilleure, 2026-07-27 Journalise la duree reelle par mot, pour mesurer le gain d'un plancher "voix propre", 2026-07-27 Mesure l'apport reel des durees de reference et documente la piste "recitation de reference" (+20 more)

### Community 11 - "Bancs 2-tetes (dual-head)"
Cohesion: 0.08
Nodes (17): EncCTCWrapper, main(), Tensor, Export SANS ETAT (memes conventions que export_tajweed_checkpoint.py, cf. CLAUDE, encoder(audio_signal=mel, length) -> ctc_decoder -> log_softmax.     Memes noms, EncCTCWrapper, main(), Tensor (+9 more)

### Community 12 - "Options de jugement (prereglages)"
Cohesion: 0.12
Nodes (21): main(), Test du modele 2 tetes sur un audio CONTINU (sourate entiere en un seul fichier,, load_expected_words(), main(), process_clip(), no_grad, Test du modele 2 tetes sur une SOURATE ENTIERE recitee par un professionnel (202, Texte plat (tags retires) + [(start, end, classe)] en offsets du texte     plat (+13 more)

### Community 13 - "Etat du lecteur"
Cohesion: 0.08
Nodes (27): 2026-07-16 Corrige la troncature per-mot via validation globale (idée utilisateur), 2026-07-19 Coran 100% local (fini le "Connexion requise" hors-ligne), rescoring NLL diagnostique, correcti, 2026-07-27 L'ancre ne cale plus : resynchronisation par le decodage libre, et +1 en mode reference, 2026-07-16 Corrige la cécité aux erreurs de prononciation (cause racine : token parasite), buildFrom (fonction), buildVariants (fonction), coveredWordsFromFree (fonction), ctcForwardNll (fonction) (+19 more)

### Community 14 - "Revision des erreurs"
Cohesion: 0.08
Nodes (24): activeRules, adulteDefault, badgeLabel, capsToUnclear, copyWith, enfantDefault, fromJson, fromKey (+16 more)

### Community 15 - "Provider des seuils de jugement"
Cohesion: 0.08
Nodes (23): copyWith, currentIndex, currentVerse, duration, error, hasVerse, isActive, isPaused (+15 more)

### Community 16 - "COUCHE 6 - Jugement et affichage"
Cohesion: 0.12
Nodes (22): [EN ATTENTE] Buffer de secours DECALE, 2026-07-27 Skill : impose UN format de compte rendu unique, avec confirmation WAV par mot, 2026-07-27 Skill analyse-session-recitation : fige la methode et les erreurs deja commises, 2026-07-27 Corrige deux bugs qui rendaient le secours muet et multipliaient les non juges, 2026-07-27 Documente le buffer de secours decale comme piste VIVANTE, pas ecartee, 2026-07-27 Le secours produisait toujours une liste vide : forceJudgeIndex manquant, 2026-07-29 Le discriminant du decrochage : conserve=0, l'audio non garde entre deux segments, 2026-07-29 Consigne : l'app ne sait pas suivre un reciteur qui REPETE (+14 more)

### Community 17 - "Durees de reference et mots frontiere"
Cohesion: 0.09
Nodes (22): ayahErrorDetailsProvider, ayahs, byNumber, counts, errorKindBreakdownProvider, grouped, out, results (+14 more)

### Community 18 - "Branches de test GOP (revert cibles)"
Cohesion: 0.09
Nodes (22): applyPreset, _contextDependentRules, json, judgementOptionsProvider, _kPrefJudgement, n, _persist, r0 (+14 more)

### Community 19 - "Resync et branches d'experimentation"
Cohesion: 0.10
Nodes (21): [EN ATTENTE] Rescoring de variantes pour les LETTRES, ⑤ Alignement force et scores, align(logprobs, wordTokens, anchor), coveredWordsFromFree(free, tokens), ctcMinFrames(toks), decodeFreeSpan(free, span), greedyDecodeRange(logprobs, from, to), plausibleMinFrames(wi, toks, ref) (+13 more)

### Community 20 - "BufferedTranscriber (symboles AST)"
Cohesion: 0.10
Nodes (20): 2026-07-20 Passation de session 2026-07-20 pour l'agent suivant, ⑥ Jugement et affichage (Dart), applyGopWordBaseline(baseline), applyJudgementOptions(opts), classifyError(wordIndex), _judge(words, i, status), secoursMeilleur(orig, rj), [PIEGE] La MOITIE de la logique de jugement existe pour compenser la segmentation (+12 more)

### Community 21 - "Modele de verset"
Cohesion: 0.15
Nodes (4): CausalAlignmentSession, FloatArray, IntArray, DiagnosticLog

### Community 22 - "Contexte droit + traces de diagnostic"
Cohesion: 0.10
Nodes (19): ayahNumber, fromJson, key, nameArabic, nameSimple, nameTranslationFr, number, pageNumber (+11 more)

### Community 23 - "Selection du reciteur"
Cohesion: 0.34
Nodes (18): branche master, 2026-07-23 WIP : localisation (l10n) des libellés tajwid, jeu de mémorisation, baseline GOP par mot, 2026-07-23 Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat, 2026-07-23 Revert ciblé du moteur ASR vers l'état avant les 2 GOP (a2d3054), test isolé, 2026-07-23 Fiabilise le jugement tajwid : 2 têtes branchées, GOP dépiégé, stats honnêtes, 2026-07-20 Le mode tajwid vérifie enfin le tajwid (règle attendue vs règle réalisée), 2026-07-23 Branche de test : moteur ASR à l'état 5d97e09 (1 GOP + tête tajwid séparée), 2026-07-12 Correctifs récitation (perf, sensibilité, référence globale), cascade offline, mini-LoRA v1 (PC (+10 more)

### Community 24 - "MelSpectrogram (symboles AST)"
Cohesion: 0.11
Nodes (17): _availabilityBadge, build, createState, currentId, _fmtSize, initState, _offlineCount, _refresh (+9 more)

### Community 25 - "Piste RNNT hybride 3 tetes"
Cohesion: 0.21
Nodes (5): FastConformerStreamingSession, FeedResult, FloatArray, OrtEnvironment, OrtSession

### Community 26 - "Baseline GOP par mot"
Cohesion: 0.12
Nodes (16): 2026-07-19 Documente l'état CTC NeMo + débloque la loss RNNT (NVVM réparé sous Ubuntu), 2026-07-19 Construit un set de validation YouTube vraiment non-vu, réciteurs vérifiés, 2026-07-19 Invalide le test cross-récitateur YouTube : confondu par un découpage 30s, 2026-07-19 Glossaire techniques ASR : entraînement vs décodage, et quoi brancher maintenant, 2026-07-19 Corrige un crash SIGSEGV (fork+CUDA) du stage 1b — num_workers=0, 2026-07-19 Mesure préliminaire du test d'interférence (checkpoint intermédiaire, pas final), 2026-07-19 Reclasse la piste 'données RNNT dédiées' de contingence à expérience prévue, 2026-07-19 Documente le mode enfant : couche de comparaison, pas une 3e tête (+8 more)

### Community 27 - "Banc du double decoupage"
Cohesion: 0.13
Nodes (14): GopWordBaseline, gopWordBaselineProvider, json, mean, n, raw, reliable, result (+6 more)

### Community 28 - "Banc de la fenetre glissante"
Cohesion: 0.21
Nodes (11): Engine, frontier_words(), gated_stream(), main(), Compare TROIS politiques de decoupage sur du vrai audio, en mesurant ce qui caus, Reproduit le portier RMS de BufferedTranscriber.feed() : au-dela de     MAX_SILE, Bornes (debut, fin) des segments DANS LE FLUX CONSERVE, selon la     politique d, Compte les mots decodes qui touchent un bord de segment (a moins de     FRONTIER (+3 more)

### Community 29 - "Resync sur apercu (REFUTE)"
Cohesion: 0.22
Nodes (11): Engine, main(), merge_overlap(), Simule HORS DEVICE les politiques de segmentation de BufferedTranscriber, pour r, appendMergingOverlap : evite de reecrire les mots deja figes., Rejoue le flux bloc par bloc. sliding=False -> politique actuelle., Renvoie [(texte_mot, frame_debut, frame_fin)], + nb de frames.         Equivalen, remap() (+3 more)

### Community 30 - "COUCHES 1-2 - Micro et transport"
Cohesion: 0.14
Nodes (8): ① Capture micro (Dart), ② Transport Dart→Kotlin, feedBufferedAudio(pcm16), "feedBufferedAudio" (handler), _processContinuousChunk(bytes,n), start(expectedWords), stopIfCurrentSession(gen), [PIEGE] 35 % de l'audio n'existait dans AUCUN fichier

### Community 31 - "FastConformerCtc (symboles AST)"
Cohesion: 0.15
Nodes (11): FastConformerCtcPlugin, MethodCall, MethodChannel, onAttachedToEngine(), onDetachedFromEngine(), onMethodCall(), MainActivity, FlutterActivity (+3 more)

### Community 32 - "RescueBuffer (symboles AST)"
Cohesion: 0.24
Nodes (11): collapse(), corrupt_word(), free_decode(), load_model(), main(), no_grad, Tolerance de bord (cf. matchesTolerant app) : prefixe/suffixe partagé     d'au m, Diff textuel GLOBAL, mot-a-mot, sans aucune frontière de frames --     c'est le (+3 more)

### Community 33 - "Banc d'appariement global"
Cohesion: 0.19
Nodes (12): 2026-07-27 Enregistre le clip du gel a la borne dure : 35 % de l'audio n'existait dans aucun fichier, 2026-07-26 docs: consigne la livraison du streaming causal, 2026-07-26 Mesure le causal dans le regime REEL de l'app, et comble le trou "detection de fautes", 2026-07-26 fix: resynchronise la reprise après correction, 2026-07-26 fix: recalcule le score après un recul, 2026-07-26 feat: orchestre le démarrage de la récitation, 2026-07-26 feat: ajoute le compte à rebours avant récitation, 2026-07-26 docs: valide le causal sur appareil (+4 more)

### Community 34 - "StreamingModelConfig (contrat causal)"
Cohesion: 0.17
Nodes (13): 2026-07-26 feat: complète le paquet causal avec son tokenizer, 2026-07-26 feat: active le modèle causal dans le flux continu, 2026-07-12 Refonte ASR (GOP forced-alignment), récitation continue, cascade d'explications offline, _kAsrVersion (constante), align (fonction), alignmentPayload (fonction), greedyDecode (fonction), loadWordTokenLookup (fonction) (+5 more)

### Community 35 - "Bancs ancre et arbitrage resync"
Cohesion: 0.17
Nodes (13): 2026-07-27 Buffer de secours en lecture seule : rejuge un mot non place, avec contexte, 2026-07-26 chore: point de retour avant le streaming causal, 2026-07-26 feat: bascule l'app sur le modele causal sans tajwid, 2026-07-26 feat: maintient le décodage CTC entre les chunks, 2026-07-26 feat: fiabilise l'export ONNX causal stateful, append (fonction), appendArgmax (fonction), appendLogProbs (fonction) (+5 more)

### Community 36 - "Banc de normalisation fixe"
Cohesion: 0.36
Nodes (11): branche test-2-gop, 2026-07-23 Branche de test 2-GOP : moteur ASR à l'état c9c531f (2 têtes + segmentation recouvrement 2s), 2026-07-23 Corrige un crash natif JNI (SIGABRT) sur le thread du pool de coroutines, 2026-07-23 Corrige le crash natif ONNX (vraie cause : R8 obfusquait ai.onnxruntime.**), 2026-07-27 Corrige la regression du matin : l'ancre ne peut plus bloquer sur un mot non place, 2026-07-27 Segments chevauchants : 3 s de contexte pour ne plus commencer en plein mot, 2026-07-23 Diagnostique et corrige les blocages d'ancre sur récitation hésitante, 2026-07-23 Revert temporaire ASR vers l'état 2-GOP (5d97e09), pour test isolé avant segmentation (+3 more)

### Community 37 - "Deploiement 260h + refonte IHM"
Cohesion: 0.23
Nodes (11): 2026-07-16 Corrige 8/10 findings de la revue de code (2 restants documentés délibérément), 2026-07-16 Documente la revue de code (10/10 findings confirmes) + investigation du lag, 2026-07-27 Distingue "la DP a echoue" de "mot saute" par la place reellement disponible, 2026-07-20 Corrige la pénalité systématique des symboles de règles dans le GOP (Kotlin), 2026-07-16 Contre-revue Sonnet + développement du rescoring tête-à-tête (résultat réel), 2026-07-20 Renforce le correctif GOP : renormalisation pré-softmax + exclusion du chadda nu, 2026-07-27 Collecte les durees de reference mot-a-mot, en vue d'un plancher d'alignement realiste, 2026-07-27 Cesse de condamner un mot quand c'est la DP qui a echoue (+3 more)

### Community 38 - "CausalAlignmentSession (symboles AST)"
Cohesion: 0.32
Nodes (3): DoubleArray, FloatArray, MelSpectrogram

### Community 39 - "Modele de reciteur"
Cohesion: 0.27
Nodes (9): dot(), dtwSimilarity(), FloatArray, OrtEnvironment, OrtSession, load(), normalizeRows(), save() (+1 more)

### Community 40 - "VERROU SUR APERCU et palliatifs retires"
Cohesion: 0.18
Nodes (5): OU EST L'ANCRE, contre OU EN EST VRAIMENT LE RECITATEUR, seconde par seconde.  L, ⚠️ CE BANC A PRODUIT UNE PREDICTION FAUSSE — LIRE AVANT DE S'EN SERVIR.  Le 2026, resync(), sq(), DateTime?

### Community 41 - "Banc des politiques de coupe"
Cohesion: 0.32
Nodes (10): decode(), log_mel(), main(), normalize_fixed(), normalize_per_feature(), ndarray, Valide (ou invalide) le remplacement de la normalisation "per_feature" (mean/std, Log-mel NON normalise, (80, T). (+2 more)

### Community 42 - "Banc de rescoring par variantes"
Cohesion: 0.17
Nodes (12): 2026-07-20 Refonte du volet Coach : la mémorisation rassemblée en un hub, 2026-07-19 Déploie le modèle stage1b-260h dans le cœur ASR + câble les modes de jugement, 2026-07-19 Continue stage1b sur 260h Coran (vs 150h) : 2 bugs de chemins corrigés + gain net mesuré, 2026-07-19 Export stage1b-260h pour déploiement app (ONNX CTC + asset mots annotés), 2026-07-19 Carte mentale des sourates (REFONTE_IHM.md §7) : rendu graphview + contenu initial, 2026-07-20 Tiroir de lecture scrollable + filigrane à motif du mushaf, 2026-07-19 Redesign SurahOrnamentHeader v2 : médaillon SVG au lieu du cadre CustomPainter, 2026-07-19 Spécification détaillée de la refonte IHM (exécutable sans invention) (+4 more)

### Community 43 - "Bascule vers le modele causal"
Cohesion: 0.18
Nodes (10): hashCode, id, kDefaultReciter, kReciters, nameAr, nameFr, operator, Reciter (+2 more)

### Community 44 - "SYMPTOMES - ou ils naissent vs ou ils se voient"
Cohesion: 0.29
Nodes (9): casse(), coupes_blancs(), coupes_energie(), dec(), dec_lp(), logprobs(), nz(), Cherche le micro-silence le plus proche de la cible, comme le fait le     moteur (+1 more)

### Community 45 - "Banc de normalisation causale"
Cohesion: 0.29
Nodes (8): ctc_forced_nll(), load_model(), logprobs_for_clip(), main(), no_grad, -log P(token_ids | audio) sous le CTC -- plus BAS = meilleure     explication de, Reproduit EXACTEMENT le chemin de production (EncCTCWrapper des scripts     d'ex, _ZeroRNNTLoss

### Community 46 - "Utilitaires de banc communs"
Cohesion: 0.20
Nodes (10): [REGLE] Identifier la couche ou le defaut NAIT, pas celle ou il se VOIT, [SYMPTOME] Audio capte mais jamais consomme, [SYMPTOME] Bloc de mots abandonnes, [SYMPTOME] Texte charabia sur segment long, [SYMPTOME] 47,4 % des coupes tombent en plein mot, [SYMPTOME] Decrochage 124-180 : six hypotheses refutees, [SYMPTOME] entendu vide, gop effondre, free NORMAL, [SYMPTOME] 12 faux positifs sur 12, MODELE HORS DE CAUSE (+2 more)

### Community 47 - "Confrontation des erreurs au modele"
Cohesion: 0.22
Nodes (9): [EN ATTENTE] Borne droite de coupe (targetOffset + radius), [EN ATTENTE] Couper a une FIN DE MOT connue, 2026-07-29 Rayon de coupe elargi a 2 s : essaye, mesure, rejete, 2026-07-28 L'installation distante echouait en silence : trois recettes analysees sur un binaire perime, 2026-07-29 Le rejeu deterministe attend la FIN DU FICHIER, pas une duree de montre, 2026-07-28 La coupe ne depend plus de l'horloge -- mais le taux n'y gagne pas, findCutOffset(buf, target, minKeep), [MORT] Rayon de coupe elargi a 2 s (+1 more)

### Community 48 - "WavReader / WavWriter"
Cohesion: 0.33
Nodes (8): log_mel_frames(), main(), normalize(), Rejoue le streaming causal HORS DEVICE en faisant varier la SEULE politique de n, Toutes les frames log-mel (AVANT normalisation) -- equivalent de     MelSpectrog, mean/std appliques a la fenetre d'entree, selon [policy].      cumulative  : tou, read_wav(), run()

### Community 49 - "Plugin d'enregistrement audio"
Cohesion: 0.31
Nodes (6): diff_has_error(), normalize(), Shared utilities: Arabic normalization, WER, algorithmic mistake detection., Algorithmic mistake detection: align recited words vs reference words.     Retur, wer(), words()

### Community 50 - "Resume de log de recitation"
Cohesion: 0.36
Nodes (6): lire(), main(), Modele, non_verts(), norm(), Mots signales OU non juges, avec leur etat. Les lignes du secours sont     ecart

### Community 51 - "Tableau de session"
Cohesion: 0.22
Nodes (9): 2026-07-26 Retire la validation groupee par GOP : mesuree sans aucun gain, 2026-07-26 Bascule sur le repli bufferise : garde le modele causal, abandonne le cache-aware, 2026-07-27 Teste Nemotron 3.5 comme encodeur de base : faisabilite prouvee, perf insuffisante, 2026-07-26 Ne juge plus un mot quand le modele est sur de ce qu'il entend (trou d'alignement), 2026-07-26 Ignore la sortie generee par graphify, [MORT] Streaming cache-aware, _kCausalStreamingEnabled (constante), _kFreeConfidentStrict = -0.02 (+1 more)

### Community 52 - "Moteur Kotlin (AST)"
Cohesion: 0.29
Nodes (3): FloatArray, IntArray, StreamingCtcState

### Community 53 - "Groupe 53"
Cohesion: 0.46
Nodes (4): AudioRecorderPlugin, MethodCall, MethodChannel, AudioRecord

### Community 54 - "Banc de mesure"
Cohesion: 0.29
Nodes (5): main(), parse(), Résumé lisible d'un log de récitation : mot attendu / mot entendu, au PREMIER ju, Retourne {index: {txt, events[], corrections[]}} dans l'ordre d'apparition., Test de BOUT EN BOUT de la chaine de recitation : l'app detecte-t-elle reellemen

### Community 55 - "Banc de mesure"
Cohesion: 0.39
Nodes (7): cible_sourate2(), commentaire(), lire(), main(), preuve_non_juge(), Laquelle des TROIS preuves a épargné ce mot ?      Savoir laquelle a tiré est le, Mots attendus, filtrés comme `splitExpectedWords` côté app : les signes     de w

### Community 57 - "Code Dart (AST)"
Cohesion: 0.29
Nodes (7): JudgementOptions, PlayerStateModel, RecitationSessionState, JudgementOptionsNotifier, PlayerNotifier, RecitationNotifier, StateNotifier

### Community 58 - "Banc de mesure"
Cohesion: 0.52
Nodes (6): hms(), main(), parse(), Analyse un log de test DEVICE (recitation) et en sort un rapport lisible.  POURQ, secs(), section()

### Community 59 - "Banc de mesure"
Cohesion: 0.43
Nodes (5): afficher(), inventaire(), analyser(), derniere_recitation(), Indice de debut de la derniere recitation (remise a zero de l'ancre).

### Community 60 - "Banc de mesure"
Cohesion: 0.43
Nodes (6): causal_log_mel_frames(), main(), ndarray, Reproduit EXACTEMENT le pipeline streaming Kotlin (FastConformerStreamingSession, Frames log-mel NON normalisees, calcul strictement causal (= Kotlin v2)., run_streaming()

### Community 61 - "Code Dart (AST)"
Cohesion: 0.33
Nodes (6): build, CoranKarimApp, _openDownloads, appLocaleProvider, ConsumerWidget, MaterialPageRoute

### Community 62 - "Code Dart (AST)"
Cohesion: 0.33
Nodes (6): HomeScreen, _HomeScreenState, initState, ConsumerState, ConsumerStatefulWidget, prayerSettingsProvider

### Community 63 - "Code Dart (AST)"
Cohesion: 0.40
Nodes (6): _PointDEntree, _PointDEntreeState, ReciterSelectScreen, _ReciterSelectScreenState, State, StatefulWidget

### Community 64 - "Banc de mesure"
Cohesion: 0.53
Nodes (5): decode_m4a(), main(), normalize(), Test youtube_align sur Un fichier An-Naba (40 versets, ~5 min)., sim()

### Community 65 - "Banc de mesure"
Cohesion: 0.40
Nodes (4): main(), STAGE 1 du fine-tune STREAMING — adaptation causale de l'encodeur.  CONTEXTE (20, Neutralise la branche RNNT : l'app n'utilise que le CTC, et le RNNT est     le c, _ZeroRNNTLoss

### Community 66 - "Grappe de commits lies"
Cohesion: 0.33
Nodes (6): 2026-07-26 perf: limite le controle initial a une page, 2026-07-26 fix: preserve les diagnostics de recitation, 2026-07-26 feat: fait progresser le coach ayah par ayah, 2026-07-26 feat: planifie les rappels de priere locaux, 2026-07-26 feat: recentre l'ornement des sourates, 2026-07-25 Valide les mots par GROUPE quand le GOP est bon, au lieu de carver mot par mot

### Community 67 - "Grappe de commits lies"
Cohesion: 0.33
Nodes (6): 2026-07-20 Passation : ajoute les 2 derniers commits + la nature bi-chantier de cc94417, 2026-07-20 Passation : ajoute les corrections de fin de session, 2026-07-20 Règles tajwid : le garde-fou passe d'un blocage à un plafond, 2026-07-20 Cartes mentales des 114 sourates + erreurs catégorisées par type (+ refonte Invocations/Rites d, 2026-07-20 Traces de diagnostic récitation : mode, changements de mode, ancre, 2026-07-20 Sépare prononciation et tajwid : l'alignement forcé repasse sur le texte nu

### Community 68 - "Pistes MORTES (mesurees perdantes)"
Cohesion: 0.33
Nodes (6): _onAligned(payload), [MORT] Relachement de la regle de proportion, [MORT] Validation groupee par GOP, [PIEGE] La majorite des mots sont verrouilles sur des APERCUS, donc sur un audio INCOMPLET, [REGLE] Ne JAMAIS compenser une perte d'information d'une couche basse par une tolerance ajoutee dans une couche haute, [SYMPTOME] Mot tronque (sad-alif pour sadiqin)

### Community 69 - "Moteur Kotlin (AST)"
Cohesion: 0.70
Nodes (4): fromJson(), StreamingModelConfig, toIntList(), toLongList()

### Community 70 - "Banc de mesure"
Cohesion: 0.50
Nodes (4): fetch_surah(), main(), Collecte les timings mot-a-mot de plusieurs recitateurs depuis quran.com et prod, Segments d'une sourate entiere pour un recitateur. 114 appels par     recitateur

### Community 71 - "Banc de mesure"
Cohesion: 0.60
Nodes (4): main(), norm(), WER du modele causal PAR CONTEXTE d'attention (2026-07-25).  Le `val_wer_ctc` du, wer()

### Community 73 - "Banc de mesure"
Cohesion: 0.50
Nodes (3): Rejoue HORS DEVICE l'algorithme exact de findResyncOffset sur les dérives réelle, resync(), sq()

### Community 79 - "Grappe de commits lies"
Cohesion: 0.50
Nodes (4): branche gradient-aligner, branche test-1-gop, 2026-07-30 Alignement par gradient : blocage de stack documente, branche laissee vide, 2026-07-30 Le log du secours donne les TROIS scores, et le superviseur devient obligatoire

### Community 82 - "Pistes MORTES (mesurees perdantes)"
Cohesion: 0.67
Nodes (3): cibleAvecVoisins(zone, idx, toks), rescueWord(idx, tokens, from, to), [MORT] Sonde de 4 lettres

### Community 83 - "Pistes MORTES (mesurees perdantes)"
Cohesion: 0.67
Nodes (3): RescueBuffer.extract(from, to), [MORT] Anneau de secours 30 s -> 120 s comme CAUSE du decrochage, RESCUE_RING_SECONDS = 120

## Knowledge Gaps
- **489 isolated node(s):** `WordResult`, `RecitationSegment`, `_kSimThreshold`, `_kUnclearSimThreshold`, `_kLookahead` (+484 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `2026-07-11 Commit initial — Coran Karim` connect `COUCHE 3 - Buffer et segmentation` to `Provider de recitation (jugement Dart)`, `Banc d'appariement global`, `StreamingModelConfig (contrat causal)`, `Bancs ancre et arbitrage resync`, `Banc de normalisation fixe`, `Deploiement 260h + refonte IHM`, `Pistes de coupe EN ATTENTE + commits`, `CausalAlignmentSession (symboles AST)`, `Amorcage de l'application`, `Etat de recitation (modele Dart)`, `Export ONNX des checkpoints`, `COUCHE 5 - Alignement + bascule causale`, `Etat du lecteur`, `COUCHE 6 - Jugement et affichage`, `BufferedTranscriber (symboles AST)`, `Selection du reciteur`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `③ Buffer et segmentation (Kotlin)` connect `COUCHE 5 - Alignement + bascule causale` to `COUCHE 3 - Buffer et segmentation`, `Etat de recitation (modele Dart)`, `Pistes MORTES (mesurees perdantes)`, `Pistes de coupe EN ATTENTE + commits`, `Banc de normalisation fixe`, `Amorcage de l'application`, `Export ONNX des checkpoints`, `Etat du lecteur`, `Utilitaires de banc communs`, `Confrontation des erreurs au modele`, `COUCHE 6 - Jugement et affichage`, `Pistes MORTES (mesurees perdantes)`, `Pistes MORTES (mesurees perdantes)`, `BufferedTranscriber (symboles AST)`, `Pistes EN ATTENTE`, `Pistes MORTES (mesurees perdantes)`, `PIEGES deja rencontres`, `COUCHES 1-2 - Micro et transport`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **Why does `ForcedAligner` connect `ForcedAligner (DP CTC)` to `Deploiement 260h + refonte IHM`, `Modele de verset`?**
  _High betweenness centrality (0.043) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `2026-07-11 Commit initial — Coran Karim` (e.g. with `2026-07-24 Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe` and `2026-07-23 Bancs de mesure pour la segmentation ASR + option stats fixes dans mel_numpy_reference`) actually correct?**
  _`2026-07-11 Commit initial — Coran Karim` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 18 inferred relationships involving `2026-07-25 Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuv` (e.g. with `2026-07-16 Revue d'architecture karaoké + plan d'exécution P0/P1/P2 (Fable)` and `2026-07-23 Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat`) actually correct?**
  _`2026-07-25 Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuv` has 18 INFERRED edges - model-reasoned connections that need verification._
- **What connects `WordResult`, `RecitationSegment`, `_kSimThreshold` to the rest of the system?**
  _489 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Provider de recitation (jugement Dart)` be split into smaller, more focused modules?**
  _Cohesion score 0.010526315789473684 - nodes in this community are weakly interconnected._