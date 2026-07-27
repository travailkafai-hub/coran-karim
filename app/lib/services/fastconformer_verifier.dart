import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'diagnostic_log.dart';

// ── Alignement forcé GOP (cf. ForcedAligner.kt, refonte 2026-07-11) ──────────

/// Résultat d'alignement pour UN mot attendu. [gop] = forced - free (toujours
/// ≤ 0) : proche de 0 = l'audio soutient pleinement le mot attendu (harakat
/// comprises) ; très négatif = le modèle est bien plus sûr d'avoir entendu
/// autre chose ([actual] dit quoi — décodage libre sur la plage de frames que
/// l'alignement attribue à ce mot).
class AlignedWord {
  final int index; // index ABSOLU dans le texte attendu complet
  final double gop;
  final double forced;
  final bool covered; // false = mot encore en cours de prononciation (frontière)
  final String actual;
  // Rescoring NLL tête-à-tête (cf. ForcedAligner.WordResult.rescoreMargin,
  // ConfusableVariants) : NLL(mot attendu) − NLL(meilleure variante
  // confusable) sur les mêmes frames. > 0 : une variante explique MIEUX
  // l'audio (signal ABSOLU, contrairement au gop qui est relatif). Null si
  // le rescoring n'est pas activé (FastConformerVerifier.setRescoringEnabled)
  // ou non calculable pour ce mot. DIAGNOSTIC UNIQUEMENT pour l'instant — ne
  // participe pas au verdict (cf. recitation_provider.dart), le seuil n'est
  // pas encore calibré en conditions réelles device.
  final double? rescoreMargin;
  final String? rescoreHeard;
  // Règles de tajwid RÉELLEMENT détectées sur les frames de ce mot par la
  // TÊTE 2 du modèle (architecture à deux têtes, 2026-07-22).
  //
  // Avant cette architecture, les règles arrivaient sous forme de symboles PUA
  // insérés dans [actual], et on les retrouvait en analysant cette chaîne. Ce
  // n'est plus le cas : lettres et règles sont deux sorties distinctes du
  // modèle, et l'attribution au mot se fait par recouvrement de FRAMES (la
  // même fenêtre que celle qui sert au gop), donc sans dépendre de la position
  // dans le texte. Chaque entrée porte aussi sa confiance, ce qu'un symbole
  // dans une chaîne ne pouvait pas transporter.
  //
  // Vide si le modèle chargé n'a qu'une seule tête (anciens déploiements) —
  // à ne PAS confondre avec « aucune règle réalisée », d'où [hasRuleHead].
  final List<DetectedRule> detectedRules;

  /// VRAI si [actual] ne vient PAS des frames que l'alignement forcé a
  /// attribuées à ce mot, mais du décodage libre GLOBAL du segment (cf.
  /// ForcedAligner.WordResult.actualFromFree). Journalisé `src=libre`.
  ///
  /// Pourquoi c'est important : [actual] DÉCIDE la couleur (`textMatches`
  /// court-circuite le gop). Quand il vient du décodage libre global, ce n'est
  /// plus une mesure de CE mot -- et sur un passage à mots répétés (2:4 contient
  /// `أُنزِلَ` aux index 23 ET 26) l'attribution par le texte ne peut pas
  /// distinguer les occurrences. Sans cette trace, une ligne de log
  /// `entendu="بِمَآ"` était indéchiffrable.
  final bool actualFromFree;

  /// VRAI si la DP a attribué MOINS de frames à ce mot que le minimum
  /// mathématique requis par le CTC (cf. ForcedAligner.WordResult.starved).
  /// Signal COMPLÉMENTAIRE à un `free` peu confiant pour repérer un échec
  /// d'alignement plutôt qu'une vraie faute -- ajouté 2026-07-27 après un mot
  /// (`actual=""`, `free=-0,24`) qui échappait au garde-fou existant (seuil de
  /// confiance non atteint) et déclenchait quand même une correction via la
  /// série d'aperçus négatifs, sans jamais s'afficher rouge à l'écran.
  final bool starved;

  /// Nombre de frames ARTICULÉES attribuées à ce mot par la DP (frames blank
  /// exclues, 80 ms/frame) — donc la durée de prononciation réelle. Alimente
  /// [WordDurationStore], le plancher appris dans la voix de l'utilisateur.
  /// 0 si la DP ne lui a attribué aucune frame.
  final int frames;

  /// VRAI quand la DP n'a donné aucune frame à ce mot alors que la place
  /// suffisait, et que sa seconde chance est épuisée : il n'y a aucune preuve
  /// acoustique à juger, mais il ne faut plus le différer (l'ancre bloquerait).
  /// Cf. ForcedAligner.WordResult.noEvidence — le mot est présent dans la liste
  /// pour que l'ancre avance, et le jugement le saute.
  final bool noEvidence;

  const AlignedWord({
    required this.index,
    required this.gop,
    required this.forced,
    required this.covered,
    required this.actual,
    this.rescoreMargin,
    this.rescoreHeard,
    this.detectedRules = const [],
    this.actualFromFree = false,
    this.starved = false,
    this.frames = 0,
    this.noEvidence = false,
  });
}

/// Une règle de tajwid détectée par la tête 2, avec sa confiance.
/// [id] indexe `rules.json` du modèle déployé (cf.
/// export_dual_head_checkpoint.py) — c'est le même ordre que
/// `RULE_CLASSES` côté Python et `TajwidRule.values` côté app.
class DetectedRule {
  final int id;
  final double prob; // 0..1 — permet de distinguer réalisée / à peine esquissée

  const DetectedRule(this.id, this.prob);
}

/// Une passe d'alignement complète. [isFinal] : segment figé — l'audio de ces
/// mots ne sera plus jamais réanalysé, jugements définitifs. [frontier] :
/// premier mot que l'audio ne couvre pas complètement (= mot courant UI).
class AlignPayload {
  final int seq;
  final int anchor;
  final int frontier;
  final bool isFinal;
  final List<AlignedWord> words;
  // Chemin du clip WAV capturé pour CE segment figé (mini-LoRA personnalisation
  // vocale, cf. FONCTIONNALITES_FUTURES.md "Personnalisation voix -- niveau 3",
  // implémenté 2026-07-12) -- non null seulement si la capture est active
  // (FastConformerVerifier.setClipCapture) ET que ce payload correspond à un
  // commit normal (pas le repli "borne dure" qui réutilise l'aperçu sans clip).
  final String? clipPath;

  const AlignPayload({
    required this.seq,
    required this.anchor,
    required this.frontier,
    required this.isFinal,
    required this.words,
    this.clipPath,
  });

  static AlignPayload? fromMap(dynamic m) {
    if (m is! Map) return null;
    final rawWords = m['words'];
    final words = <AlignedWord>[];
    if (rawWords is List) {
      for (final w in rawWords) {
        if (w is! Map) continue;
        words.add(AlignedWord(
          index: (w['i'] as num).toInt(),
          gop: (w['gop'] as num).toDouble(),
          forced: (w['forced'] as num).toDouble(),
          covered: w['covered'] as bool? ?? false,
          actual: w['actual'] as String? ?? '',
          rescoreMargin: (w['rescoreMargin'] as num?)?.toDouble(),
          rescoreHeard: w['rescoreHeard'] as String?,
          actualFromFree: w['srcFree'] as bool? ?? false,
          starved: w['starved'] as bool? ?? false,
          frames: (w['frames'] as num?)?.toInt() ?? 0,
          noEvidence: w['noEvidence'] as bool? ?? false,
          detectedRules: [
            for (final r in (w['rules'] as List? ?? const []))
              if (r is Map)
                DetectedRule((r['id'] as num).toInt(),
                    (r['prob'] as num?)?.toDouble() ?? 0.0),
          ],
        ));
      }
    }
    return AlignPayload(
      seq: (m['seq'] as num?)?.toInt() ?? -1,
      anchor: (m['anchor'] as num?)?.toInt() ?? 0,
      frontier: (m['frontier'] as num?)?.toInt() ?? 0,
      isFinal: m['final'] as bool? ?? false,
      words: words,
      clipPath: m['clipPath'] as String?,
    );
  }
}

/// Deuxième vérificateur ASR (FastConformer CTC, entraîné sur le corpus Coran,
/// cf. benchmark/models/fastconformer-quran-pcd), tournant EN PARALLÈLE de
/// whisper.cpp — PAS un remplacement tant que le training n'est pas terminé et
/// comparé sur test_voice_full.jsonl (whisper-medium-ft ~11% WER de référence).
///
/// Objectif de cette intégration précoce : valider tout le pipeline (export
/// ONNX -> mel Kotlin -> inférence -> décodage CTC -> détokenisation) PENDANT
/// que le training tourne encore côté PC, pour qu'il suffise de remplacer le
/// fichier .onnx une fois le modèle final prêt — pas de surprise d'intégration
/// à ce moment-là.
///
/// Chaîne Kotlin : MethodChannel (pas FFI comme whisper_ggml — l'API ONNX
/// Runtime Android est Kotlin/Java, pas une lib C à lier directement) — voir
/// android/app/src/main/kotlin/.../fastconformer/FastConformerCtcPlugin.kt.
class FastConformerVerifier {
  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');
  // Entraînement MIXTE, epoch 02 (2026-07-16, exporté sans arrêter le run en
  // cours). Premier modèle de ce projet à avoir vu des erreurs de prononciation
  // pendant son entraînement : tous les précédents n'avaient été nourris QUE de
  // Coran parfaitement récité (284823 clips, 0 erreur -- l'augmentation TTS
  // avait été perdue lors de la reconstruction du manifeste le 12/07), d'où un
  // biais qui lui faisait "corriger" les fautes vers la forme canonique -- une
  // erreur invisible pour le GOP (si le modèle est sûr du canonique,
  // forced == free -> gop=0 -> vert, aucun seuil ne rattrape ça).
  // Mélange : Coran 150h (replay anti-oubli) + Arabic Speech Corpus x10 (vraie
  // voix, arabe NON coranique vocalisé -> aucun prior canonique possible) +
  // TTS x5 (18084 erreurs délibérées sin/sad, harakat) = 34% de contre-exemples.
  // Gain mesuré sur 150 clips d'erreurs tenus hors entraînement
  // (cf. benchmark/eval_error_detection.py) :
  //     détection d'erreur : 18.7% -> 57.3%   (x3)
  //     erreur manquée     : 28.7% -> 18.0%
  //     CER coranique      :  9.03% -> 9.46%  (contrôle anti-oubli, stable)
  // Même tokenizer tajweed_bpe_v1 -> vocab.json et word_tokens.json identiques
  // (ce dernier CORRIGÉ du token '▁' parasite, cf. build_word_token_lookup.py).
  // Rollback : 'models/fastconformer-ctc-tajweed-v2-059' (déployé, ou
  // 'models/fastconformer-ctc-pcd' -- fichiers jamais supprimés du PC).
  //
  // MODÈLE STAGE1B-260H (2026-07-19, hybride "vrai tajweed", cf.
  // PLAN_ENTRAINEMENT_HYBRIDE.md §5ter). Meilleure version mesurée :
  //   détection d'erreur identique (~65%), corrections silencieuses vers le
  //   canonique 10,7% (vs 14,7% mixed-e02, -4 pts), CER canonique 6,85%
  //   (vs 9,18% mixed-e02) -- meilleur sur TOUTES les métriques + émet les
  //   17 symboles de règles tajwid (U+E000..U+E010) que l'app annote sur la
  //   cible d'alignement (RecitationNotifier.setupVerses) et surface en badges
  //   (RecitedWord.expectedRules). Tokenizer DIFFÉRENT (tajweed_rules_bpe_v1,
  //   1024 tokens dont 41 pièces à symbole) -> vocab.json propre à ce dossier.
  //   PAS de word_tokens.json (la normalizeTraining supprimerait les symboles :
  //   incohérent avec ce vocab) -> repli tokenisation greedy de CtcTokenizer.kt
  //   (gère les symboles PUA comme n'importe quelle pièce).
  // ROLLBACK IMMÉDIAT : remettre 'models/fastconformer-ctc-mixed-e02'
  //   ci-dessous (toujours présent sur l'appareil, jamais écrasé) + revenir
  //   au commit précédent pour l'annotation cible. Les deux modèles coexistent
  //   dans files/models/ du device.
  // Modèle À DEUX TÊTES (2026-07-22) : tête 1 lettres+harakat (poids
  // mixed-e14 INCHANGÉS, val_wer_ctc 0,124), tête 2 regles tajwid
  // (rappel 0,90 / précision 0,98, F1 0,936 sur les 17 classes).
  // Mesuré en remplacement de rules-260h :
  //   - le désaccord de tokenisation `ٱ+ل` disparaît (la correction ne rapporte
  //     plus rien : +18,53 -> -0,67), car la tête lettres n'a jamais vu de
  //     symbole de règle et retrouve donc SA tokenisation d'entraînement ;
  //   - la discrimination juste/faux est réparée : les cas où une variante
  //     FAUTIVE scorait mieux que le mot correct passent de 45 % à 16 %.
  // Nécessite rules.json à côté du modèle (cf. _kRulesFile) — sans lui la
  // vérification tajwid reste inactive au lieu de tout accuser à tort.
  // Rollback : 'models/fastconformer-ctc-rules-260h' (toujours sur l'appareil),
  // ou 'models/fastconformer-ctc-mixed-e02' (fichiers jamais supprimés du PC).
  //
  // MODÈLE CAUSAL V1 SANS TÊTE TAJWID (2026-07-26) : checkpoint
  // fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo, entraîné avec
  // convolutions causales. Le premier export stateless `model.onnx` reste le
  // fallback bufferisé ; `model_streaming.onnx` transmet désormais les trois
  // caches et consomme le contrat `streaming_config.json`. L'absence volontaire
  // de rules.json maintient hasRuleHead=false et interdit tout verdict tajwid
  // sans preuve acoustique.
  // Le modèle dual-head précédent reste dans son propre dossier sur le PC pour
  // un rollback sans réexport.
  static const _kModelSubdir = 'models/fastconformer-ctc-causal-v1';
  static const _kModelFile = 'model.onnx';
  static const _kVocabFile = 'vocab.json';
  // Dictionnaire mot -> IDs de tokens précalculé avec le VRAI tokenizer NeMo
  // (benchmark/build_word_token_lookup.py) — remplace la tokenisation greedy
  // heuristique de CtcTokenizer.kt comme source PRIMAIRE pour l'alignement
  // forcé (celle-ci reste un repli pour les mots hors dictionnaire, ex. texte
  // hors-Coran). Optionnel : absent → CtcTokenizer.kt gère tout en greedy.
  static const _kWordTokensFile = 'word_tokens.json';
  // Noms des classes de la TÊTE 2 (modèles à deux têtes, cf.
  // benchmark/export_dual_head_checkpoint.py). Sa PRÉSENCE est ce qui
  // distingue un modèle à deux têtes d'un ancien modèle : sans lui, la
  // vérification tajwid doit rester inactive plutôt que de conclure
  // « aucune règle réalisée » sur des détections qui n'existent pas.
  static const _kRulesFile = 'rules.json';

  bool _loaded = false;
  bool _hasRuleHead = false;

  /// Le modèle déployé expose-t-il une TÊTE TAJWID (architecture à deux têtes) ?
  /// Déterminé par la présence de `rules.json` à côté du modèle.
  ///
  /// ⚠️ À TESTER AVANT toute conclusion du type « cette règle n'a pas été
  /// réalisée » : sur un modèle à une seule tête, aucune règle n'est jamais
  /// détectée, et confondre « le modèle ne sait pas détecter » avec « le
  /// récitant n'a pas réalisé la règle » ferait passer en orange TOUS les mots
  /// porteurs d'une règle.
  bool get hasRuleHead => _hasRuleHead;

  /// Résout les chemins modèle/vocab côté app-support (même convention que
  /// whisper-medium-ggml) et charge la session ONNX côté Kotlin. Idempotent :
  /// ne recharge pas si déjà fait. Retourne false si le modèle n'est pas
  /// encore déployé sur l'appareil (pas une erreur — juste "pas encore prêt").
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    if (_streamingLoaded) await disposeStreaming();
    // TEST OVERRIDE (2026-07-24) : sur un build release (non debuggable),
    // run-as ne marche pas -> impossible de pousser un modele dans le storage
    // privé (getApplicationSupportDirectory). Le dossier EXTERNE
    // getExternalStorageDirectory() = /storage/emulated/0/Android/data/<pkg>/
    // files EST accessible en `adb push`. On charge donc de PREFERENCE le
    // modele depuis là s'il y est present (teste un nouveau checkpoint sans
    // build debuggable), sinon repli sur le storage privé habituel. A retirer
    // pour le deploiement definitif.
    Directory appDir = await getApplicationSupportDirectory();
    final ext = await getExternalStorageDirectory();
    if (ext != null &&
        await File('${ext.path}/$_kModelSubdir/$_kModelFile').exists()) {
      appDir = ext;
      debugPrint('[FastConformer] TEST: modele depuis storage EXTERNE '
          '(${ext.path}/$_kModelSubdir)');
    }
    final modelFile = File('${appDir.path}/$_kModelSubdir/$_kModelFile');
    final vocabFile = File('${appDir.path}/$_kModelSubdir/$_kVocabFile');
    final wordTokensFile = File('${appDir.path}/$_kModelSubdir/$_kWordTokensFile');
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      debugPrint('[FastConformer] Modèle/vocab absents (${modelFile.path}) — ignoré');
      return false;
    }
    final rulesFile = File('${appDir.path}/$_kModelSubdir/$_kRulesFile');
    _hasRuleHead = await rulesFile.exists();
    final hasWordTokens = await wordTokensFile.exists();
    if (!hasWordTokens) {
      debugPrint('[FastConformer] word_tokens.json absent — alignement forcé '
          'utilisera la tokenisation greedy (repli) pour tous les mots');
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
        'wordTokensPath': hasWordTokens ? wordTokensFile.path : null,
        'rulesPath': _hasRuleHead ? rulesFile.path : null,
      });
      _loaded = ok ?? false;
      debugPrint('[FastConformer] Modèle chargé : $_loaded');
      // Trace le modèle REELLEMENT charge (cf. _kBuildTag dans
      // diagnostic_log.dart, meme motivation) : plusieurs checkpoints ont ete
      // deployes/compares le 2026-07-16, et leurs plages de gop typiques
      // different beaucoup (pcd ~0, tajweed -5 a -9). Sans cette ligne, un log
      // ne permet pas de savoir quel modele a produit les scores qu'on y lit.
      DiagnosticLog.log('FastConformer',
          'modele charge=$_loaded subdir=$_kModelSubdir '
          'word_tokens=${hasWordTokens ? "oui" : "non (repli greedy)"}');
      // Relie le fichier de log natif (BufferedTranscriber, ForcedAligner) au
      // MÊME fichier persistant que le côté Dart (cf. diagnostic_log.dart) —
      // une seule chronologie, récupérable par adb pull sans connexion
      // continue (demande utilisateur 2026-07-11).
      final logPath = DiagnosticLog.path;
      if (_loaded && logPath != null) {
        unawaited(
            _channel.invokeMethod('setLogFile', {'path': logPath}));
      }
      // Rescoring NLL (cf. AlignedWord.rescoreMargin) : activé UNIQUEMENT en
      // debug pour l'instant (2026-07-19) -- diagnostic pas encore calibré
      // sur device réel (seuil non déterminé, cf. ETAT_CTC_NEMO.md §5a-bis),
      // ne doit jamais tourner en release avant calibration. But de ce
      // if kDebugMode : générer des lignes "[GOP] ... rescore=..." pendant
      // les tests manuels de calibration, sans exposer de toggle UI.
      if (_loaded && kDebugMode) {
        unawaited(setRescoringEnabled(true));
      }
      return _loaded;
    } catch (e) {
      debugPrint('[FastConformer] Échec chargement modèle : $e');
      return false;
    }
  }

  /// Transcrit un segment WAV déjà découpé (même fichier que whisper.cpp reçoit
  /// — pas de refonte du pipeline audio pour ce premier jet). Retourne null en
  /// cas d'échec (modèle non chargé, erreur native) — appelant doit tolérer.
  Future<String?> transcribe(String wavPath) async {
    if (!_loaded) return null;
    try {
      final text = await _channel.invokeMethod<String>('transcribe', {'wavPath': wavPath});
      return text;
    } catch (e) {
      debugPrint('[FastConformer] Échec transcription : $e');
      return null;
    }
  }

  Future<void> dispose() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    _loaded = false;
  }

  // ── Streaming cache-aware (vrai flux continu, karaoké) ──────────────────────
  // Même checkpoint causal que le fallback segment-par-segment, mais export
  // cache-aware distinct, avec son contrat versionné.
  static const _kStreamingModelSubdir = 'models/fastconformer-ctc-causal-v1';
  static const _kStreamingModelFile = 'model_streaming.onnx';
  static const _kStreamingConfigFile = 'streaming_config.json';
  bool _streamingLoaded = false;

  // ── CACHE-AWARE DESACTIVE (2026-07-26) — le MODELE n'est pas en cause ────
  // Mesure decisive sur l'audio reel de l'utilisateur (82 s captees sur
  // device, `stream_1785083047340.wav`), MEME modele causal, MEME decoupe de
  // 12 s, la seule difference etant le chemin d'alimentation :
  //     causal en SEGMENTS (sans cache) : 4 segments sur 4 transcrits juste
  //     ancien modele offline, idem      : 3 sur 4
  // Le causal est donc MEILLEUR que l'ancien modele sur cette voix et ce
  // telephone -- il ne faut surtout pas revenir au modele precedent.
  //
  // En revanche le chemin cache-aware (`feedCausalAudio`) decroche en session
  // reelle : le compteur de tokens se fige (`ids=9` pendant 140 s sur une
  // session de 187 s, `ids=3` sur une autre), l'aligneur n'a plus rien a
  // juger, aucun mot ne passe au vert et le curseur gele SANS afficher ni
  // orange ni rouge. CINQ politiques de gestion du cache ont ete testees hors
  // device sur cet audio et TOUTES rejetees par la mesure (fenetre glissante
  // de normalisation, remise a zero sur silence / a intervalle fixe / a la
  // frontiere de verset / combinee sur la politique BufferedTranscriber) --
  // detail chiffre dans PROBLEMATIQUES_ASR.md §1.5.
  //
  // On bascule donc sur le repli bufferise, qui utilise le MEME checkpoint
  // causal via son export sans etat (`_kModelSubdir` pointe deja dessus).
  // Cout assume : on perd la latence du vrai streaming, on retrouve celle du
  // buffer. Gain : une app qui fonctionne avec le meilleur modele disponible.
  //
  // TOUT le code cache-aware est CONSERVE (Kotlin, export, config) : remettre
  // ce drapeau a `true` suffira a le reactiver une fois la cause traitee
  // (entrainement sur sessions longues, cf. piste B du recul architectural --
  // les clips d'entrainement plafonnent a 20 s alors que la session
  // d'inference n'a aucune borne).
  static const bool _kCausalStreamingEnabled = false;

  Future<bool> ensureStreamingLoaded() async {
    if (!_kCausalStreamingEnabled) {
      DiagnosticLog.log('FastConformer',
          'streaming cache-aware DESACTIVE (_kCausalStreamingEnabled=false) '
          '-- repli bufferise sur le meme modele causal, cf. commentaire');
      return false;
    }
    if (_streamingLoaded) return true;
    Directory appDir = await getApplicationSupportDirectory();
    final ext = await getExternalStorageDirectory();
    if (ext != null &&
        await File('${ext.path}/$_kStreamingModelSubdir/$_kStreamingModelFile')
            .exists()) {
      appDir = ext;
    }
    final modelFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kStreamingModelFile');
    final vocabFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kVocabFile');
    final configFile =
        File('${appDir.path}/$_kStreamingModelSubdir/$_kStreamingConfigFile');
    final wordTokensFile =
        File('${appDir.path}/$_kStreamingModelSubdir/$_kWordTokensFile');
    if (!await modelFile.exists() ||
        !await vocabFile.exists() ||
        !await configFile.exists()) {
      debugPrint('[FastConformer] Modèle/config streaming absent '
          '(${modelFile.path}) — repli bufferisé');
      return false;
    }
    final hasWordTokens = await wordTokensFile.exists();
    // Libère le fallback seulement une fois le déploiement causal complet
    // confirmé : les deux graphes font chacun ~459 Mo et ne doivent pas
    // cohabiter sur le téléphone 6 Go.
    if (_loaded) await dispose();
    try {
      final ok = await _channel.invokeMethod<bool>('loadStreamingModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
        'configPath': configFile.path,
        'wordTokensPath': hasWordTokens ? wordTokensFile.path : null,
      });
      _streamingLoaded = ok ?? false;
      _hasRuleHead = false;
      DiagnosticLog.log('FastConformer',
          'modele causal stateful charge=$_streamingLoaded '
          'subdir=$_kStreamingModelSubdir');
      final logPath = DiagnosticLog.path;
      if (_streamingLoaded && logPath != null) {
        unawaited(_channel.invokeMethod('setLogFile', {'path': logPath}));
      }
      return _streamingLoaded;
    } catch (e) {
      _streamingLoaded = false;
      debugPrint('[FastConformer] Échec chargement modèle streaming : $e');
      return false;
    }
  }

  /// Envoie un bloc de PCM16LE brut (mono 16kHz) et retourne le texte COMPLET
  /// décodé jusqu'ici (pas un delta — plus simple à afficher, on remplace au
  /// lieu d'accumuler côté UI). Retourne null si le modèle streaming n'est pas
  /// chargé ou en cas d'erreur native.
  Future<String?> feedAudioChunk(Uint8List pcm16) async {
    if (!_streamingLoaded) return null;
    try {
      return await _channel.invokeMethod<String>('feedAudioChunk', {'pcm16': pcm16});
    } catch (e) {
      debugPrint('[FastConformer] Échec feedAudioChunk : $e');
      return null;
    }
  }

  Future<void> resetStreaming() async {
    if (!_streamingLoaded) return;
    try {
      await _channel.invokeMethod('resetStreaming');
    } catch (_) {}
  }

  Future<void> disposeStreaming() async {
    if (!_streamingLoaded) return;
    try {
      await _channel.invokeMethod('disposeStreaming');
    } catch (_) {}
    _streamingLoaded = false;
  }

  /// Flux causal principal : texte append-only, alignement forcé et compteurs
  /// de cache proviennent de la même inférence ONNX.
  Future<({String committed, String preview, AlignPayload? align})?>
      feedCausalAudio(Uint8List pcm16) async {
    if (!_streamingLoaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('feedCausalAudio', {'pcm16': pcm16});
      if (raw == null) return null;
      return (
        committed: raw['committed'] as String? ?? '',
        preview: raw['preview'] as String? ?? '',
        align: AlignPayload.fromMap(raw['align']),
      );
    } catch (e) {
      debugPrint('[FastConformer] Échec feedCausalAudio : $e');
      return null;
    }
  }

  // ── Streaming "bufferisé" (fallback fiable) ─────────────────────────────────
  // Note historique sur l'ancien checkpoint PCD : son streaming cache-aware
  // ne fonctionne pas car il est entraîné avec des convolutions non-causales,
  // incompatibles
  // avec l'inférence par cache en flux (confirmé : même l'API officielle NeMo
  // conformer_stream_step plante dessus). Solution qui marche : re-transcrire
  // le buffer audio complet de la session avec le modèle OFFLINE (déjà validé)
  // toutes les ~1,5s de nouvel audio — latence perçue ~1,5-3s, mais continu,
  // sans coupure manuelle. Ce chemin est maintenant le rollback du checkpoint
  // causal stateful et réutilise le modèle chargé via ensureLoaded().
  /// Retourne les deux parties du transcript : `committed` (segments figés,
  /// append-only, plus jamais révisés) et `preview` (segment courant, encore
  /// susceptible de changer à chaque re-transcription). Le scoring s'ancre sur
  /// la partie figée — re-partir du mot 0 à chaque passe calait dès que le
  /// début du texte était perdu par une re-transcription.
  Future<({String committed, String preview, AlignPayload? align})?>
      feedBufferedAudio(Uint8List pcm16) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('feedBufferedAudio', {'pcm16': pcm16});
      if (raw == null) return null;
      return (
        committed: raw['committed'] as String? ?? '',
        preview: raw['preview'] as String? ?? '',
        align: AlignPayload.fromMap(raw['align']),
      );
    } catch (e) {
      debugPrint('[FastConformer] Échec feedBufferedAudio : $e');
      return null;
    }
  }

  Future<void> resetBuffered() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('resetBuffered');
    } catch (_) {}
  }

  // ── Alignement forcé GOP ────────────────────────────────────────────────────

  /// Déclare le texte attendu (formes STRICTES : harakat conservées, variantes
  /// uthmani rabattues — ArabicNormalizer.normalizeStrict, même normalisation
  /// que le corpus d'entraînement) et l'ancre de départ. Retourne true si
  /// l'alignement est actif (modèle chargé + tokenisation OK) — sinon le
  /// scoring Dart doit retomber sur le diff textuel historique.
  Future<bool> setAlignmentTarget(List<String> strictWords, int anchor,
      {List<int?>? refMinFrames}) async {
    if (!_loaded && !_streamingLoaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setAlignmentTarget', {
        'words': strictWords,
        'anchor': anchor,
        // Planchers de durée de référence (frames), parallèles à `words` --
        // clé ABSENTE si aucune référence (le natif retombe alors sur le seul
        // plancher CTC, comportement d'avant ce champ). Cf. WordTimingService.
        if (refMinFrames != null) 'refMinFrames': refMinFrames,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[FastConformer] Échec setAlignmentTarget : $e');
      return false;
    }
  }

  /// Active/désactive le rescoring NLL par mot (cf. AlignedWord.rescoreMargin).
  /// Désactivé par défaut : coût additionnel (un forward CTC par variante
  /// confusable sur chaque mot d'une passe finale) pas encore mesuré sur
  /// device, et le signal n'est PAS branché au verdict (diagnostic loggé
  /// uniquement — cf. "[GOP]" dans le log persistant, champ rescore). Validé
  /// offline (2026-07-19) : benchmark/constrained_decoding_eval.py, 82,1%
  /// d'identification correcte sur les fautes de lettres, 45,0% harakat.
  Future<void> setRescoringEnabled(bool enabled) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('setRescoringEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('[FastConformer] Échec setRescoringEnabled : $e');
    }
  }

  /// Repositionne l'ancre d'alignement (correction/recul : la prochaine passe
  /// compare l'audio au mot [anchor], pas à la suite).
  Future<void> setAlignmentAnchor(int anchor) async {
    if (!_loaded && !_streamingLoaded) return;
    try {
      await _channel.invokeMethod('setAlignmentAnchor', {'anchor': anchor});
    } catch (e) {
      debugPrint('[FastConformer] Échec setAlignmentAnchor : $e');
    }
  }

  /// Active/désactive la capture de clips VÉRIFIÉS CORRECTS (mini-LoRA
  /// personnalisation vocale, cf. FONCTIONNALITES_FUTURES.md
  /// "Personnalisation voix -- niveau 3", implémenté 2026-07-12). [dir] =
  /// null désactive (défaut). N'écrit rien tant que non activé — zéro coût
  /// hors session de référence.
  Future<void> setClipCapture(String? dir) async {
    // PAS de garde `if (!_loaded) return;` (retiree le 2026-07-25) : le plugin
    // retient la valeur dans `pendingClipCaptureDir` et l'applique a la
    // creation du BufferedTranscriber, precisement pour pouvoir etre appele
    // AVANT le chargement du modele.
    //
    // Bug qu'elle a cause : l'activation de la capture a ete deplacee dans
    // `RecitationNotifier.startContinuous` (pour qu'elle ne dependre plus d'un
    // ecran), donc AVANT que le modele soit charge. L'appel repartait en
    // silence, `pendingClipCaptureDir` restait nul, et le log affichait
    // `capture de clips desactivee` -- AUCUN WAV pour toute la session, alors
    // que le reglage diagnostic etait bien a `true`. Impossible de verifier ce
    // que le modele avait reellement entendu, ce qui est tout l'objet de ces
    // captures. Meme raison que pour `setLogEnabled`, deja sans garde.
    try {
      await _channel.invokeMethod('setClipCapture', {'dir': dir});
    } catch (e) {
      debugPrint('[FastConformer] Échec setClipCapture : $e');
    }
  }

  /// Coupe/rétablit le journal de diagnostic NATIF (cf. DiagnosticLog.kt), en
  /// miroir de `DiagnosticLog.enabled` côté Dart. Un seul réglage utilisateur
  /// pilote les deux, sinon « diagnostic désactivé » ne voudrait rien dire :
  /// le natif émet ses lignes depuis le thread d'inférence, c'est lui le plus
  /// susceptible de peser sur le retard qu'on cherche à mesurer.
  ///
  /// Volontairement SANS garde `_loaded` (contrairement à setClipCapture) : le
  /// réglage doit pouvoir être poussé avant le chargement du modèle, et le
  /// plugin le retient dans un champ statique.
  Future<void> setLogEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setLogEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('[FastConformer] Échec setLogEnabled : $e');
    }
  }

  /// Alignement one-shot d'un WAV complet (mode coach, segment unique) contre
  /// la cible déclarée via [setAlignmentTarget]. Null si indisponible.
  Future<AlignPayload?> alignFile(String wavPath) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('alignFile', {'wavPath': wavPath});
      return AlignPayload.fromMap(raw);
    } catch (e) {
      debugPrint('[FastConformer] Échec alignFile : $e');
      return null;
    }
  }

  /// Vide la trace fine NATIVE (accumulée en mémoire) dans le fichier de log.
  /// À appeler uniquement hors récitation. Retourne le nombre de lignes.
  Future<int> flushNativeTrace() async {
    try {
      return await _channel.invokeMethod<int>('flushTrace') ?? 0;
    } catch (e) {
      debugPrint('[FastConformer] Échec flushTrace : $e');
      return 0;
    }
  }

  /// Mode où l'ancre ne doit JAMAIS caler : un mot que la DP ne place pas fait
  /// avancer l'ancre de +1 immédiatement, sans attendre la « seconde chance ».
  /// Activé en session de RÉFÉRENCE, où la correction est désactivée : le
  /// contrat « 2 chances » y suppose un recul d'ancre qui n'arrive jamais, donc
  /// différer revient à caler.
  Future<void> setNeverBlockAnchor(bool value) async {
    try {
      await _channel.invokeMethod('setNeverBlockAnchor', {'value': value});
    } catch (e) {
      debugPrint('[FastConformer] Échec setNeverBlockAnchor : $e');
    }
  }

  /// Remet à zéro l'horloge de la trace native (début de session).
  Future<void> resetNativeTrace() async {
    try {
      await _channel.invokeMethod('traceReset');
    } catch (_) {}
  }

  /// Étend la cible d'alignement avec des mots supplémentaires (formes
  /// STRICTES d'entraînement), à la SUITE de la cible actuelle — SANS toucher
  /// l'ancre. Enchaînement sur la sourate suivante sans interrompre la session.
  Future<bool> extendAlignmentTarget(List<String> strictWords,
      {List<int?>? refMinFrames}) async {
    if (!_loaded && !_streamingLoaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('extendAlignmentTarget', {
        'words': strictWords,
        if (refMinFrames != null) 'refMinFrames': refMinFrames,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[FastConformer] Échec extendAlignmentTarget : $e');
      return false;
    }
  }
}
