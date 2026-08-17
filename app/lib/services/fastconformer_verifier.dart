import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'diagnostic_log.dart';
import '../models/judgement_options.dart' show TajwidRule;

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
  static const _kModelSubdir = 'models/trois-tetes-2026-08-04-combine';
  static const _kModelFile = 'model.onnx';
  static const _kVocabFile = 'vocab.json';
  // TETE 3 (ecart canonique), OPTIONNELLE -- cf. Tete3.kt : en observation
  // seule (journal), n'influence aucun verdict tant que la parite des 12
  // scores n'est pas verifiee sur device.
  static const _kTete3File = 'tete3.json';
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
  // Seuil de détection PAR CLASSE de la tête tajwid (2026-08-16), remplace le
  // seuil plat 0,5 auparavant en dur côté natif (cf. FastConformerCtc.kt,
  // decodeTajwid). Mesuré sur audio réel (Al-Afasy, 141 versets, agrégat
  // toutes classes confondues faute de la table symbole->classe sur ce
  // poste) : seuil plat = sur-détection +209 % sur la fenêtre de calibrage
  // et +240 % hors fenêtre ; seuils par classe = +28 %/+38 % -- gain net
  // ET tenu hors calibrage, cf. AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md
  // §3ter. Optionnel comme rules.json/tete3.json : absent -> repli natif sur
  // 0,5 pour toutes les classes (comportement d'avant, inchangé).
  static const _kSeuilsFile = 'seuils_tajwid.json';

  bool _loaded = false;

  /// Détail EXPLICITE du dernier échec de chargement -- nul si le modèle est
  /// chargé ou si `ensureLoaded()` n'a encore jamais échoué.
  ///
  /// ── POURQUOI (2026-08-09, demande utilisateur) ───────────────────────────
  /// Avant ce champ, un modèle absent produisait UNIQUEMENT « Le modèle de
  /// récitation est indisponible. » -- vrai mais inexploitable : ni le NOM du
  /// modèle attendu (`trois-tetes-2026-08-04-combine`, change à chaque
  /// déploiement), ni le fichier précis manquant, ni le chemin où le chercher.
  /// Un `pm clear` (ou une désinstallation) l'efface silencieusement, et rien
  /// ne dit ensuite QUOI repousser ni OÙ.
  String? _dernierEchecChargement;
  String? get dernierEchecChargement => _dernierEchecChargement;
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
    final appSupportDir = await getApplicationSupportDirectory();
    Directory appDir = appSupportDir;
    // ── LIVRAISON PLAY ASSET DELIVERY, pack `install-time` (2026-08-11) ─────
    //
    // Le modèle (458,8 Mo) dépasse largement les 200 Mo du module de base
    // d'un AAB (cf. PUBLICATION_PLAY.md §2.2) : il est livré à part, dans le
    // module Gradle `model_pack` (`android { assetPacks += ":model_pack" }`,
    // cf. app/android/model_pack/). En delivery `install-time`, Play installe
    // ce pack EN MÊME TEMPS que l'app -- l'utilisateur n'a rien à attendre,
    // et le modèle est là dès le premier lancement, hors ligne ensuite.
    //
    // PIÈGE VÉRIFIÉ (doc officielle Android, 2026-08-11) : contrairement à ce
    // qu'espérait PUBLICATION_PLAY.md §2.2, un pack `install-time` NE donne
    // PAS de chemin de fichier réel. Seuls `fast-follow`/`on-demand` le font
    // via `AssetPackManager.getPackLocation()` ; `install-time` s'ouvre
    // UNIQUEMENT en flux via `AssetManager` (`context.assets.open(...)`),
    // exactement comme un asset Android classique. Or ONNX Runtime a besoin
    // d'un CHEMIN DE FICHIER (cf. `_kModelFile` plus bas, passé tel quel au
    // natif) -- un flux ne suffit pas.
    //
    // D'où cette étape : `_extraireModeleDepuisAssetPack` demande au natif
    // (`FastConformerCtcPlugin.extractModelFromAssetPack`, qui lit le pack
    // via `AssetManager`) de copier UNE FOIS les fichiers du modèle vers CE
    // MÊME dossier `appSupportDir/$_kModelSubdir/` -- le chemin que la suite
    // de cette fonction vérifie de toute façon. Idempotente (le natif saute
    // la copie si le fichier de destination existe déjà) et sans effet quand
    // le pack n'est pas présent (`flutter run`/`flutter build apk` direct ne
    // fusionnent PAS les asset packs, seul un `.aab` le fait) : dans ce cas
    // le flux de dev habituel (push manuel, ou storage externe ci-dessous en
    // debug) prend le relais sans rien changer.
    await _extraireModeleDepuisAssetPack(appSupportDir);
    // ── FERMÉ EN RELEASE (2026-08-10, demande utilisateur) ──────────────────
    //
    // Le commentaire ci-dessus disait déjà « À retirer pour le deploiement
    // definitif ». Deux raisons, et la seconde est la grave :
    //
    //  1. `/sdcard/Android/data/<pkg>/files` est l'endroit le plus simple pour
    //     EXTRAIRE le modèle : `adb pull`, sans root, y compris sur un build
    //     release.
    //  2. Surtout, n'importe qui peut y DÉPOSER un ONNX fabriqué, que l'app
    //     préférerait au sien puisque l'externe gagnait sur l'interne. Un
    //     modèle substitué falsifie silencieusement TOUS les verdicts, c'est-à-
    //     dire la raison d'être de l'application. La substitution est ici un
    //     risque plus grave que la copie.
    //
    // Conditionné au drapeau debuggable plutôt que supprimé, exactement comme
    // l'entrée de recette de `MainActivity` : le confort de test est conservé
    // (pousser un checkpoint sur un build de dev sans `run-as`), la porte est
    // fermée dans le binaire publié.
    if (kDebugMode) {
      // ── DIAGNOSTIC AVANT CORRECTIF (2026-08-13) ────────────────────────
      // Constat utilisateur : modèle poussé par `adb push` exactement au
      // chemin que ce bloc vérifie, présence et permissions confirmées côté
      // device (`stat` : 0644, inode identique via /sdcard et
      // /storage/emulated/0) -- et pourtant `ensureLoaded()` retombe sur le
      // storage privé, vide. L'ancien `debugPrint` ne prouvait rien : il
      // n'écrit que dans logcat, jamais dans `recitation_diagnostic.log`
      // (celui qu'on peut relire après coup), et il n'existe QUE dans la
      // branche "trouvé" -- silence total dans la branche "pas trouvé", donc
      // aucune preuve pour distinguer "ext est null" de "le fichier n'existe
      // pas selon Dart". On journalise les deux hypothèses séparément avant
      // de changer quoi que ce soit : deviner une correction ici serait
      // exactement l'erreur que ce projet interdit.
      final ext = await getExternalStorageDirectory();
      final cheminExt = ext == null
          ? null
          : File('${ext.path}/$_kModelSubdir/$_kModelFile');
      final existeExt = cheminExt != null && await cheminExt.exists();
      DiagnosticLog.log('FastConformer',
          'verif storage externe : ext=${ext?.path ?? "NULL"} '
          'chemin=${cheminExt?.path ?? "n/a"} existe=$existeExt');
      if (existeExt) {
        appDir = ext!;
        DiagnosticLog.log('FastConformer',
            'modele charge depuis storage EXTERNE (${ext.path}/$_kModelSubdir)');
      }
    }
    final modelFile = File('${appDir.path}/$_kModelSubdir/$_kModelFile');
    final vocabFile = File('${appDir.path}/$_kModelSubdir/$_kVocabFile');
    final wordTokensFile = File('${appDir.path}/$_kModelSubdir/$_kWordTokensFile');
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      final manquant = <String>[
        if (!await modelFile.exists()) _kModelFile,
        if (!await vocabFile.exists()) _kVocabFile,
      ].join(', ');
      _dernierEchecChargement =
          'modèle "$_kModelSubdir" : $manquant introuvable dans '
          '${appDir.path}/$_kModelSubdir/';
      debugPrint('[FastConformer] ${_dernierEchecChargement!} — ignoré');
      DiagnosticLog.log('FastConformer', _dernierEchecChargement!);
      return false;
    }
    // Fichiers présents : tout échec suivant vient d'ailleurs (chargement
    // natif), pas d'un modèle absent -- efface la trace du dernier échec pour
    // ne pas ré-afficher une cause qui n'est plus la bonne.
    _dernierEchecChargement = null;
    final rulesFile = File('${appDir.path}/$_kModelSubdir/$_kRulesFile');
    _hasRuleHead = await rulesFile.exists();
    final seuilsFile = File('${appDir.path}/$_kModelSubdir/$_kSeuilsFile');
    final hasSeuils = await seuilsFile.exists();
    final tete3File = File('${appDir.path}/$_kModelSubdir/$_kTete3File');
    final hasTete3 = await tete3File.exists();
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
        'seuilsPath': hasSeuils ? seuilsFile.path : null,
        // TETE 3 COUPEE (2026-08-04, isolation d'une regression). Mesure qui
        // l'impose : meme sourate 2, meme depart, 1,68 % de mots non verts le
        // matin (build v13, modele mono-tete) contre 10,61 % l'apres-midi
        // (build v5-trois-tetes) -- ET une lenteur signalee par l'utilisateur.
        // DEUX variables avaient change en meme temps (le code tete 3 ET le
        // modele deploye) : on coupe donc la premiere seule pour l'attribuer.
        //
        // Pourquoi tete 3 est le suspect n°1 du COUT : son vecteur de
        // caracteristiques boucle, POUR CHAQUE MOT ET CHAQUE FRAME, sur les
        // 1025 classes avec un exp() puis un ln() (entropie). Le « 3 tetes
        // coutent < 1 % » du graphe parle du MODELE, pas de ce calcul-la.
        // TETE 3 REACTIVEE (2026-08-04) apres avoir ete INNOCENTEE par la
        // mesure : coupee, le taux de mots non verts ne bougeait pas
        // (9,32 / 9,24 / 10,00 % contre 7,77 / 9,24 / 9,24 % avec elle). La
        // regression venait d'ailleurs -- `minAppariements` a 2 et le mauvais
        // `word_tokens.json` (cf. Localisateur.minAppariements).
        // Elle reste en OBSERVATION SEULE : son logit est journalise en [t3],
        // il n'influence aucun verdict tant que la parite des 12 scores n'est
        // pas verifiee sur device (cf. Tete3.kt).
        'tete3Path': hasTete3 ? tete3File.path : null,
      });
      _loaded = ok ?? false;
      debugPrint('[FastConformer] Modèle chargé : $_loaded');
      // Rejoue les reglages v2 : ils ont pu etre poses avant ce chargement.
      if (_loaded) await _envoyerReglagesV2();
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
      if (!_loaded) {
        _dernierEchecChargement =
            'modèle "$_kModelSubdir" : le natif a refusé de le charger '
            '(fichiers présents, cf. journal natif pour la cause)';
      }
      return _loaded;
    } catch (e) {
      _dernierEchecChargement =
          'modèle "$_kModelSubdir" : erreur au chargement natif -- $e';
      debugPrint('[FastConformer] Échec chargement modèle : $e');
      DiagnosticLog.log('FastConformer', _dernierEchecChargement!);
      return false;
    }
  }

  /// Matérialise le modèle du pack Play Asset Delivery `install-time` en
  /// fichiers réels sous `<dir>/$_kModelSubdir/` -- cf. le commentaire long
  /// dans `ensureLoaded()` pour le POURQUOI (ONNX Runtime exige un chemin de
  /// fichier, un pack `install-time` ne donne qu'un flux `AssetManager`).
  ///
  /// Best-effort et SILENCIEUX : une erreur ici ne doit jamais empêcher
  /// `ensureLoaded()` de continuer sur son repli habituel (le fichier
  /// manquera simplement à la vérification qui suit, avec son message
  /// d'échec explicite déjà en place). Ne lève jamais.
  Future<void> _extraireModeleDepuisAssetPack(Directory dir) async {
    try {
      await _channel.invokeMethod<bool>('extractModelFromAssetPack', {
        'destDir': dir.path,
        'subdir': _kModelSubdir,
        // Tous les fichiers optionnels sont inclus : le natif ignore
        // silencieusement (FileNotFoundException) ceux absents du pack, la
        // même tolérance que le reste de cette fonction applique déjà à
        // rules.json/tete3.json/word_tokens.json.
        'files': [
          _kModelFile,
          _kVocabFile,
          _kRulesFile,
          _kSeuilsFile,
          _kTete3File,
          _kWordTokensFile,
        ],
      });
    } catch (e) {
      // Pas de DiagnosticLog ici : au tout premier appel (avant même le
      // chargement), le fichier de log natif peut ne pas encore être relié
      // (cf. setLogFile plus bas) -- un simple debugPrint suffit, la cause
      // réelle d'un modèle absent reste de toute façon rapportée par
      // `_dernierEchecChargement` juste après.
      debugPrint('[FastConformer] extraction pack asset ignorée : $e');
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
    // Même verrou que dans `ensureLoaded()` (2026-08-10) : le modèle externe ne
    // l'emporte qu'en build de développement. Ce second chemin, plus discret
    // que le premier, aurait suffi à laisser la porte ouverte — un verrou posé
    // sur un seul des deux points d'entrée n'en est pas un.
    if (kDebugMode) {
      final ext = await getExternalStorageDirectory();
      if (ext != null &&
          await File('${ext.path}/$_kStreamingModelSubdir/$_kStreamingModelFile')
              .exists()) {
        appDir = ext;
      }
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
  /// Même forme de retour que [feedBufferedAudio] (champ `v2` toujours vide
  /// ici) : les deux chemins sont choisis par un ternaire côté appelant, leurs
  /// types doivent donc coïncider.
  Future<({String committed, String preview, AlignPayload? align,
           List<({int index, String statut, String trace, String heard,
                   Set<TajwidRule> detectedRules, bool tajwidFiable})> v2,
           bool v2Decrochage, int v2DecrochageMot,
           // MODE PRIERE (2026-08-07) -- cf. ChaineRecitation.sautLibre.
           // `v2Libre` : decodage libre de la derniere fenetre, base de
           // l'identification de sourate. `v2SautDe/A` : bornes d'un passage
           // probablement saute -- de quoi le SOUFFLER, pas un verdict.
           String v2Libre, int v2SautDe, int v2SautA})?>
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
        v2: const <({int index, String statut, String trace, String heard,
                     Set<TajwidRule> detectedRules, bool tajwidFiable})>[],
        v2Decrochage: false, // la v2 ne tourne pas sur ce chemin
        v2DecrochageMot: -1,
        v2Libre: '',
        v2SautDe: -1,
        v2SautA: -1,
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
  /// [v2] : changements de statut rendus par la chaîne v2, quand elle tourne
  /// en parallèle (`v2SetEnabled`). Vide sinon — la v1 ne change pas d'un iota.
  /// [v2Decrochage] : la chaîne v2 signale que le récitateur s'est écarté du
  /// texte attendu (plusieurs fenêtres consécutives où le décodage libre
  /// entend quelque chose qui ne se localise nulle part). Champ SÉPARÉ des
  /// statuts par mot -- cf. le commentaire côté Kotlin.
  Future<({String committed, String preview, AlignPayload? align,
           List<({int index, String statut, String trace, String heard,
                   Set<TajwidRule> detectedRules, bool tajwidFiable})> v2,
           bool v2Decrochage, int v2DecrochageMot,
           // MODE PRIERE (2026-08-07) -- cf. ChaineRecitation.sautLibre.
           // `v2Libre` : decodage libre de la derniere fenetre, base de
           // l'identification de sourate. `v2SautDe/A` : bornes d'un passage
           // probablement saute -- de quoi le SOUFFLER, pas un verdict.
           String v2Libre, int v2SautDe, int v2SautA})?>
      feedBufferedAudio(Uint8List pcm16) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('feedBufferedAudio', {'pcm16': pcm16});
      if (raw == null) return null;
      final v2 = <({int index, String statut, String trace, String heard,
                     Set<TajwidRule> detectedRules, bool tajwidFiable})>[];
      for (final m in ((raw['v2'] as List?) ?? const []).cast<Map>()) {
        // La trace porte les TROIS scores. Un `gop` effondré avec un `free`
        // proche de 0 veut dire mauvaise POSITION, pas mauvaise prononciation :
        // sans les trois, le log fait chercher au mauvais endroit.
        String f(Object? v) =>
            v == null ? '-' : (v as num).toDouble().toStringAsFixed(2);
        // TETE 2 : ids de regles -> TajwidRule par INDEX, meme convention que
        // rule_annotation_service.dart et le chemin v1 (recitation_provider.dart)
        // -- TajwidRule.values[i] doit rester le meme ordre que rules.json.
        final regles = <TajwidRule>{
          for (final id in ((m['rules'] as List?) ?? const []))
            if ((id as int) >= 0 && id < TajwidRule.values.length)
              TajwidRule.values[id],
        };
        v2.add((
          index: m['i'] as int,
          statut: m['statut'] as String,
          trace: 'gop=${f(m['gop'])} forced=${f(m['forced'])} '
              'free=${f(m['free'])} frames=${m['frames']} '
              '${(m['interieur'] as bool?) ?? false ? 'INT' : 'bord'}'
              '${(m['sansCreneau'] as bool?) ?? false ? '/sansCreneau' : ''} '
              'margeL=${f(m['margeL'])} margeH=${f(m['margeH'])} '
              'obs=${m['nbObs']} entendu="${m['entendu']}"',
          heard: m['entendu'] as String? ?? '',
          detectedRules: regles,
          // k=2 cote Kotlin : faux tant qu'on n'a pas REGARDE ce mot deux fois
          // dans de bonnes conditions. Dart doit alors se taire sur le tajwid
          // plutot que de conclure a une regle absente (cf. le commentaire du
          // payload cote plugin). Defaut prudent : false.
          tajwidFiable: (m['tajwidFiable'] as bool?) ?? false,
        ));
      }
      return (
        committed: raw['committed'] as String? ?? '',
        preview: raw['preview'] as String? ?? '',
        align: AlignPayload.fromMap(raw['align']),
        v2: v2,
        v2Decrochage: (raw['v2Decrochage'] as bool?) ?? false,
        v2DecrochageMot: (raw['v2DecrochageMot'] as int?) ?? -1,
        v2Libre: raw['v2Libre'] as String? ?? '',
        v2SautDe: (raw['v2SautDe'] as int?) ?? -1,
        v2SautA: (raw['v2SautA'] as int?) ?? -1,
      );
    } catch (e) {
      debugPrint('[FastConformer] Échec feedBufferedAudio : $e');
      return null;
    }
  }

  /// Active la chaîne v2 EN PARALLÈLE de la v1 (mesure de référence :
  /// v1 10,10 % de mots non verts, v2 2,03 % sur le même flux brut).
  Future<void> v2SetEnabled(bool enabled) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('v2SetEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// Texte attendu de la v2 (des MOTS, pas des tokens : la v2 tokenise
  /// elle-même, et génère au passage les écritures équivalentes).
  /// [depart] : position DEJA atteinte par le recitateur dans ce texte
  /// (mode priere). -1 = inconnue, la recherche part du mot 0.
  Future<void> v2SetTarget(List<String> mots,
      {List<int> nonJugeables = const [], int depart = -1}) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('v2SetTarget',
          {'mots': mots, 'nonJugeables': nonJugeables, 'depart': depart});
    } catch (_) {}
  }

  /// Agrandit la cible v2 EN COURS DE SESSION, SANS recréer la chaîne (donc
  /// sans perdre l'ancre ni les mots déjà verrouillés) -- 2026-08-05,
  /// enchaînement de page (`_maybeExtendNextPage`). Avant cet appel,
  /// l'enchaînement de page ne touchait QUE l'ancien aligneur v1
  /// (`extendAlignmentTarget`) : la cible v2, celle qui pilote vraiment
  /// l'écran, restait figée à sa taille de départ pour toute la session --
  /// tout mot enchaîné devenait structurellement hors de portée du
  /// localisateur/décrochage, quel que soit le réglage de patience.
  Future<void> v2ExtendTarget(List<String> mots,
      {List<int> nonJugeables = const []}) async {
    if (!_loaded || mots.isEmpty) return;
    try {
      await _channel.invokeMethod(
          'v2ExtendTarget', {'mots': mots, 'nonJugeables': nonJugeables});
    } catch (_) {}
  }

  /// LA VOIX DU RÉCITATEUR sur les mots [motDebut]..[motFin] (inclus), écrite
  /// en WAV — c'est l'audio EXACT qui a servi à juger ces mots, extrait du
  /// flux brut encore en mémoire (cf. `ChaineRecitation.voixSurPlage`).
  ///
  /// Retourne `null` quand l'audio n'est plus disponible (sorti de l'anneau de
  /// 300 s) ou qu'aucun de ces mots n'a de position connue — cas légitimes,
  /// l'appelant doit le dire à l'utilisateur plutôt que de jouer du vide.
  /// Active/désactive le BLOC DE FUSION (2e observation d'un énoncé, vu avec
  /// le précédent). Défaut `true` = comportement mesuré et en place.
  ///
  /// Existe pour trancher sur DEVICE l'hypothèse « les aperçus 2/4 suffisent,
  /// le second chemin fait trop de contrôle ». Banc JVM (Al-Baqara 433 s,
  /// 295 mots) : fusion=true 14,24 % de non verts / 1494 observations ;
  /// fusion=false 19,32 % / 879 observations. Le banc tournait toutefois en
  /// repli glouton de tokenisation -- d'où ce drapeau pour la recette réelle.
  Future<void> v2SetFusion(bool actif,
      {int preuves = 2,
      double pas = 4.0,
      double largeur = 4.0,
      double maxBloc = 10.0,
      double maxFusion = 18.0}) async {
    // PAS de garde `!_loaded` ici. La recette pose ces drapeaux AVANT
    // d'ouvrir la capture, donc avant le chargement du modele : la garde
    // faisait repartir l'appel sans rien faire ET sans laisser de trace.
    // Deux passes ont ete mesurees le 2026-08-06 en croyant comparer deux
    // configurations, alors qu'elles etaient identiques (5 puis 3 mots non
    // verts = la variance entre deux passes, pas un effet). Le handler natif
    // ne fait que ranger deux champs : il n'a jamais eu besoin du modele.
    _v2FusionSouhaitee = actif;
    _v2PreuvesSouhaitees = preuves;
    _v2Pas = pas;
    _v2Largeur = largeur;
    _v2MaxBloc = maxBloc;
    _v2MaxFusion = maxFusion;
    await _envoyerReglagesV2();
  }

  bool _v2FusionSouhaitee = true;
  int _v2PreuvesSouhaitees = 2;
  double _v2Pas = 4.0;
  double _v2Largeur = 4.0;
  double _v2MaxBloc = 10.0;
  double _v2MaxFusion = 18.0;

  /// Pousse les reglages v2 au natif. Rejoue APRES le chargement du modele :
  /// le plugin recree la chaine a ce moment-la, une valeur posee avant serait
  /// perdue sans qu'aucune ligne ne le dise.
  Future<void> _envoyerReglagesV2() async {
    try {
      await _channel.invokeMethod('v2SetFusion',
          {
            'actif': _v2FusionSouhaitee,
            'preuves': _v2PreuvesSouhaitees,
            'pas': _v2Pas,
            'largeur': _v2Largeur,
            'maxbloc': _v2MaxBloc,
            'maxfusion': _v2MaxFusion,
          });
    } catch (e) {
      // JAMAIS silencieux : un reglage de mesure qui n'arrive pas invalide
      // la mesure entiere, et se lit a tort comme « le parametre ne change
      // rien ».
      DiagnosticLog.log('FastConformer', '[v2] reglages NON APPLIQUES : $e');
    }
  }

  /// FERME la session v2 : dernière analyse de la queue d'audio, hors grille.
  /// Sans cet appel, les derniers mots prononcés restent PROVISOIRES à jamais
  /// (la grille de fenêtres cesse d'avancer dès que le récitateur se tait) --
  /// mesuré le 2026-08-06 : mot `تَنْهَرْ` à gop 0,00, texte exact, resté non
  /// vert parce que la session s'est arrêtée juste après.
  /// @return les mots finalisés par cette dernière passe : `(index, statut)`.
  /// L'appelant DOIT les réinjecter dans le flux de statuts -- ils ne
  /// remontent pas par le chemin habituel, qui est la réponse de `feed()`.
  Future<List<({int index, String statut})>> v2Terminer() async {
    if (!_loaded) return const [];
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('v2Terminer');
      if (r == null) return const [];
      return r
          .map((e) => (
                index: (e['i'] as num).toInt(),
                statut: e['statut'] as String,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Recule l'ancre de la chaine v2 au mot [mot] et libere les verdicts
  /// suivants, SANS recreer la chaine (cf. ChaineRecitation.reculerAncre).
  Future<bool> v2ReculerAncre(int mot) async {
    if (!_loaded) return false;
    try {
      return await _channel
              .invokeMethod<bool>('v2ReculerAncre', {'mot': mot}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> v2ExtraitVoix(int motDebut, int motFin) async {
    if (!_loaded) return null;
    try {
      return await _channel.invokeMethod<String>(
          'v2ExtraitVoix', {'motDebut': motDebut, 'motFin': motFin});
    } catch (_) {
      return null;
    }
  }

  /// Mode de la chaîne v2 CÔTÉ NATIF -- premier maillon du cloisonnement
  /// contrôle/test (REFONTE_IHM.md §14, demande utilisateur 2026-08-05 :
  /// « je veux que tout le process soit dupliqué, aucune communication, tout
  /// soit étanche »).
  ///
  /// AVANT CET APPEL, AUCUN FLAG DE MODE N'EXISTAIT CÔTÉ KOTLIN : `v2Actif`/
  /// `v2Mots` étaient posés sans distinction contrôle/référence, et
  /// `Localisateur.kt` -- le mécanisme d'ancre lui-même -- ne savait donc pas
  /// dans quel mode il tournait. Un correctif d'ancre en mode référence
  /// touchait mécaniquement le mode contrôle.
  ///
  /// [mode] : `'CTL'` (contrôle, usage réel) ou `'REF'` (référence, recette
  /// uniquement) -- mêmes deux valeurs que [DiagnosticLog.modeSession], pour
  /// qu'un même mot signifie la même chose des deux côtés du pont natif.
  Future<void> v2SetMode(String mode) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('v2SetMode', {'mode': mode});
    } catch (_) {}
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
