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

  /// GOP TAJWID gradué, par classe de règle (index = id de règle, même ordre
  /// que `rules.json` / [TajwidRule.values]) — « 2ᵉ palier » (2026-07-23,
  /// idée utilisateur : « la tête 1 fait l'alignement, la tête tajwid juge le
  /// tajwid, donc on doit avoir DEUX gop »).
  ///
  /// [detectedRules] ci-dessus vient d'un décodage GLOUTON : tout-ou-rien. Si
  /// à sa meilleure frame la ghunnah est à 0,45 et le blanc à 0,50, l'argmax
  /// prend le blanc et la règle ressort « non détectée » alors qu'elle était
  /// clairement présente — c'est ce qui produisait des `emises=` vides sur des
  /// règles pourtant réalisées.
  ///
  /// Ici on garde la mesure CONTINUE : pour chaque classe, la meilleure marge
  /// sur les frames du mot entre le score de la classe et celui de la classe
  /// gagnante à la même frame. Toujours ≤ 0 :
  ///   `0`            → la règle est la classe gagnante (réalisation nette)
  ///   `-0,5 / -1,5`  → présente mais dominée (réalisation partielle)
  ///   très négatif   → absente
  /// C'est la forme d'un gop (`forced − free`) appliquée à la tête 2. Vide si
  /// le modèle chargé n'a qu'une seule tête.
  final List<double> tajwidGop;

  const AlignedWord({
    required this.index,
    required this.gop,
    required this.forced,
    required this.covered,
    required this.actual,
    this.rescoreMargin,
    this.rescoreHeard,
    this.detectedRules = const [],
    this.tajwidGop = const [],
  });

  /// GOP tajwid de la règle [ruleId], ou null si non mesurable (modèle à une
  /// seule tête, ou id hors plage).
  double? gopForRule(int ruleId) =>
      (ruleId >= 0 && ruleId < tajwidGop.length) ? tajwidGop[ruleId] : null;
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
          detectedRules: [
            for (final r in (w['rules'] as List? ?? const []))
              if (r is Map)
                DetectedRule((r['id'] as num).toInt(),
                    (r['prob'] as num?)?.toDouble() ?? 0.0),
          ],
          // GOP tajwid gradué par classe (cf. AlignedWord.tajwidGop). Clé
          // absente sur un modèle à une seule tête -> liste vide.
          tajwidGop: [
            for (final g in (w['tajwidGop'] as List? ?? const []))
              if (g is num) g.toDouble(),
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
  static const _kModelSubdir = 'models/fastconformer-ctc-dual-head';
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
    final appDir = await getApplicationSupportDirectory();
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
  // Modèle distinct de celui du mode segment-par-segment ci-dessus : encodeur
  // basculé en attention chunked_limited + cache d'état en entrée/sortie
  // (benchmark/export_streaming_onnx.py, validé fidèle au PyTorch natif).
  static const _kStreamingModelSubdir = 'models/fastconformer-ctc-pcd-streaming';
  static const _kStreamingModelFile = 'model_streaming.onnx';
  bool _streamingLoaded = false;

  Future<bool> ensureStreamingLoaded() async {
    if (_streamingLoaded) return true;
    final appDir = await getApplicationSupportDirectory();
    final modelFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kStreamingModelFile');
    final vocabFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kVocabFile');
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      debugPrint('[FastConformer] Modèle streaming absent (${modelFile.path}) — ignoré');
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadStreamingModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
      });
      _streamingLoaded = ok ?? false;
      debugPrint('[FastConformer] Modèle streaming chargé : $_streamingLoaded');
      return _streamingLoaded;
    } catch (e) {
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

  // ── Streaming "bufferisé" (fallback fiable) ─────────────────────────────────
  // Le vrai streaming cache-aware (ci-dessus) ne fonctionne pas : notre
  // checkpoint est entraîné avec des convolutions non-causales, incompatibles
  // avec l'inférence par cache en flux (confirmé : même l'API officielle NeMo
  // conformer_stream_step plante dessus). Solution qui marche : re-transcrire
  // le buffer audio complet de la session avec le modèle OFFLINE (déjà validé)
  // toutes les ~1,5s de nouvel audio — latence perçue ~1,5-3s, mais continu,
  // sans coupure manuelle. Réutilise le modèle chargé via ensureLoaded().
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
  Future<bool> setAlignmentTarget(List<String> strictWords, int anchor) async {
    if (!_loaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setAlignmentTarget', {
        'words': strictWords,
        'anchor': anchor,
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
    if (!_loaded) return;
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
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('setClipCapture', {'dir': dir});
    } catch (e) {
      debugPrint('[FastConformer] Échec setClipCapture : $e');
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

  /// Étend la cible d'alignement avec des mots supplémentaires (formes
  /// STRICTES d'entraînement), à la SUITE de la cible actuelle — SANS toucher
  /// l'ancre. Enchaînement sur la sourate suivante sans interrompre la session.
  Future<bool> extendAlignmentTarget(List<String> strictWords) async {
    if (!_loaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('extendAlignmentTarget', {
        'words': strictWords,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[FastConformer] Échec extendAlignmentTarget : $e');
      return false;
    }
  }
}
