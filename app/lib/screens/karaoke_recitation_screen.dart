import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/judgement_options.dart' show TajwidRule;
import '../models/recitation_state.dart';
import '../providers/app_settings_provider.dart';
import '../providers/judgement_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/pause_profile_service.dart';
import '../services/quran_api.dart';
import '../providers/error_review_provider.dart';
import '../services/recitation_error_log_service.dart';
import '../services/recitation_start_sequence.dart';
import '../services/reference_timing_extractor.dart';
import '../services/rule_annotation_service.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import '../widgets/recitation_start_overlay.dart';
import '../widgets/tajweed_text.dart';
import '../widgets/tajwid_help_sheet.dart';
import 'memorization_game_screen.dart';
import 'tajwid_rules_screen.dart';

/// Écran "karaoké" — récitation continue immersive.
///
/// Contrairement à [RecitationScreen] (écran de test/debug, conservé tel quel),
/// celui-ci incarne l'expérience cible : le verset est déjà connu et affiché,
/// l'utilisateur récite sans interaction manuelle entre les versets, et un halo
/// ambiant (calqué sur le niveau du micro) fait office d'unique indicateur
/// d'écoute — pas de bouton, pas d'encarts de stats empilés.
///
/// Le modèle de vérification (FastConformer CTC) n'étant encore qu'à ~20% de
/// précision (training en cours), aucun jugement vert/rouge mot-par-mot n'est
/// affiché : seul le mot "courant" reçoit un soulignement doré mobile, et le
/// dernier segment entendu apparaît brièvement en bas de l'écran — un geste
/// d'écoute, pas un verdict.
class KaraokeRecitationScreen extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const KaraokeRecitationScreen({super.key, required this.verses});

  @override
  ConsumerState<KaraokeRecitationScreen> createState() => _KaraokeRecitationScreenState();
}

class _KaraokeRecitationScreenState extends ConsumerState<KaraokeRecitationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  final _pauseProfile = PauseProfileService();
  // Mini-LoRA personnalisation vocale (FONCTIONNALITES_FUTURES.md,
  // "Personnalisation voix -- niveau 3", implémenté 2026-07-12) : capture des
  // clips uniquement pendant une session de référence (cf. _toggle),
  // dossier temporaire actif tant que la session tourne.

  // La référence (manière de réciter ce passage : pauses, tempo) ne
  // s'enregistre JAMAIS en douce : c'est une étape explicite, annoncée avant
  // de commencer et confirmée après (demande utilisateur 2026-07-05 —
  // "l'utilisateur doit être conscient qu'il va définir comment il récite").
  bool? _hasProfile; // null = vérification en cours (profil DÉDIÉ à ce passage)
  // Profil GLOBAL (agrégé sur d'autres passages déjà validés, cf.
  // PauseProfileService) jugé assez stable pour ne plus reproposer de
  // session de référence à chaque nouveau passage (demande utilisateur
  // 2026-07-12 : "pendant les premières récitations [propose], quand on aura
  // quelque chose de stable on ne propose plus"). null = vérification en cours.
  bool? _globalStable;
  bool _isReferenceSession = false;
  bool _profileSaved = false;
  String? _sessionNotice; // confirmation/échec affiché après la session
  StreamSubscription<int>? _wordFailedSub;
  bool _autoCorrecting = false; // évite deux corrections en même temps
  DateTime? _correctionCooldownUntil; // anti-rafale, voir _onWordFailed

  /// Nombre de mots joués AVANT le mot raté, pour donner l'élan (décision
  /// utilisateur 2026-07-25 : « que le mot ou deux mots max »).
  ///
  /// La MÊME constante pilote le recul de l'ancre : l'ancre doit revenir
  /// exactement là où on demande au réciteur de reprendre, sinon son audio et
  /// l'alignement forcé sont décalés (cf. le bloc de mesure dans
  /// _onWordFailed). Les deux ne doivent JAMAIS être réglés séparément.
  static const int _kCorrectionWordsBefore = 1;
  bool _promptingWord = false; // souffleur en cours, voir _promptCurrentWord
  // "Un seul essai forcé" (demande utilisateur 2026-07-16 soir) : le mot pour
  // lequel on a DÉJÀ joué l'audio de correction + reculé l'ancre une fois.
  // Si wordFailed refire sur ce MÊME mot juste après (le réciteur n'a pas
  // repris exactement ce que le modèle attendait), on ne reboucle plus
  // (pause/audio/recul) -- le réciteur est laissé libre d'avancer sur la
  // suite, le modèle SUIT sans re-bloquer. Repose sur le vécu réel : boucle
  // de 4+ minutes sur "لَيَصْرِمُنَّهَا" sans jamais aboutir, le réciteur étant
  // pourtant confiant d'avoir bien récité. Remis à null dès qu'un mot
  // DIFFÉRENT échoue, pour que celui-ci ait droit à son propre essai.
  int? _lastAutoCorrectedWordIndex;

  // Pause manuelle (demande utilisateur 2026-07-10 : "il faut que je gère la
  // pause aussi et après je continue") — distincte du STOP (halo central, qui
  // termine la session). La pause ne fait QUE couper la capture audio le
  // temps d'une interruption (appel, réflexion...) sans rien perdre de la
  // progression (mots déjà jugés, ancre d'alignement) : même primitive
  // pauseCapture()/resumeCapture() déjà utilisée pendant la correction
  // automatique (cf. _onWordFailed), juste déclenchée manuellement ici.
  bool _manuallyPaused = false;

  // Indication explicite d'où reprendre après une correction automatique
  // (demande utilisateur 2026-07-05 : "je sais pas d'où je dois recommencer").
  // MISE À JOUR 2026-07-06 (demande utilisateur précisée à plusieurs
  // reprises) : pointe désormais le mot FAUTIF LUI-MÊME (pas le suivant) —
  // rewindAndUnlock() ramène l'ancre d'alignement dessus et le déverrouille,
  // pour que le réciteur le redise avec un nouvel audio et qu'il puisse
  // redevenir vert si c'est correct cette fois.
  int? _resumeHintIndex;

  // Défilement automatique vers le mot en cours (demande utilisateur
  // 2026-07-05 : "le défilement doit suivre la vitesse de lecture").
  // UNE clé stable PAR MOT (jamais réattribuée à un autre widget) — une
  // unique GlobalKey réutilisée pour "le mot courant du moment" a provoqué
  // deux crashes réels en test (2026-07-06) : "Duplicate keys found" (deux
  // mots marqués current simultanément, bug d'état amont — voir _onStructured)
  // et "_dependents.isEmpty is not true" (Flutter ne supporte pas de déplacer
  // une GlobalKey entre positions/parents différents d'un build à l'autre).
  // Une clé par index, jamais déplacée, élimine les deux à la racine.
  // Null tant que _initAsync() n'a pas fini (voir _ready).
  List<GlobalKey>? _wordKeys;
  int? _lastAutoScrolledIndex;
  DateTime? _manualScrollUntil;

  // Coloration tajwid lettre-par-lettre (demande utilisateur 2026-07-05 :
  // tajwid "partout où le texte apparaît") pour les mots PAS ENCORE jugés —
  // une fois jugé, le mot passe en vert/orange/rouge (fond), qui prime sur la
  // couleur tajwid du texte pour ne jamais se disputer la même couleur.
  // Un groupe de spans par mot (aligné sur les mêmes indices que RecitedWord).
  // Null tant que _initAsync() n'a pas fini (voir _ready) -- dépend
  // potentiellement d'un fetch réseau (Bismillah), donc plus "late final".
  List<List<TextSpan>>? _tajwidSpans;
  bool _ready = false;
  RecitationStartStage? _startStage;
  int _bismillahWordCount = 0;

  // Liste MUTABLE (contrairement à widget.verses, figé à l'ouverture) — permet
  // d'enchaîner sur la sourate suivante sans fermer/rouvrir l'écran (demande
  // utilisateur 2026-07-11 : "récitation en flux continu... enchaîner sur une
  // autre sourate"). Initialisée depuis widget.verses, puis étendue PAGE PAR
  // PAGE par _maybeExtendNextPage() à mesure que la récitation approche de la
  // fin -- PAS sourate entière d'un coup (revu le même jour après un test réel
  // montrant "1:1 → 2:286" chargé instantanément : Al-Baqarah entière, 286
  // versets, alors que le réciteur n'avait fini que la Fatiha. "il faut faire
  // ça dynamiquement, une page avant et une page après").
  late List<Verse> _verses;
  bool _extending = false; // évite deux extensions concurrentes
  // Dernier verset pour lequel WordCorrectionAudio.prefetch a été déclenché
  // (demande utilisateur 2026-07-11 : "en cas d'erreur ça prend beaucoup de
  // temps pour réagir" -- log natif a confirmé 4,5-9,2s de fetch réseau
  // bloquant au moment de la correction). Évite de relancer le prefetch à
  // chaque frame tant qu'on reste sur le même verset.
  String? _prefetchedVerseKey;
  bool _noMorePages = false; // page 604 (fin du Mushaf) déjà atteinte
  // Nombre de mots restant AVANT la fin du texte connu qui déclenche la
  // recherche de la page suivante — assez tôt pour que le fetch réseau
  // (Bismillah + texte + audio de correction) ait le temps de finir avant que
  // le réciteur n'atteigne réellement la fin.
  static const int _kExtendLookaheadWords = 8;

  // Fenêtre de rendu bornée AU-DELÀ du pointeur (demande utilisateur
  // 2026-07-11, suite à un gel de 3+ minutes constaté en test réel : ajouter
  // une sourate longue -- ex. Al-Baqarah, 6121 mots -- forçait Flutter à
  // construire/mettre en page des MILLIERS de widgets-mots en une seule passe
  // synchrone dans le Wrap, bloquant tout le pipeline audio le temps du
  // rendu). Les mots très en avance sur le pointeur sont de toute façon
  // quasi invisibles (WordStatus.pending, opacity 0.04, cf. _wordSpan) --
  // aucune perte d'expérience à ne pas les construire tant qu'on n'en
  // approche pas. Largement au-delà de ce qui tient à l'écran (plusieurs
  // versets d'avance), donc invisible en usage normal.
  static const int _kRenderLookaheadWords = 150;

  // Métadonnées (nom arabe/français, nombre de versets) des sourates déjà
  // rencontrées dans _verses — préchargées avant chaque affichage (initial ou
  // extension) pour que _SurahTransitionBanner puisse les lire de façon
  // SYNCHRONE au build (demande utilisateur 2026-07-11 : "séparer visuellement
  // les sourates avec le nom de la sourate, un rendu graphique plus beau").
  final Map<int, Surah> _surahMeta = {};

  Future<Surah> _fetchSurahMeta(int surahNumber) async {
    final cached = _surahMeta[surahNumber];
    if (cached != null) return cached;
    final json = await QuranApi.fetchSurahInfo(surahNumber);
    return Surah.fromJson(json);
  }

  // Clé de profil de pauses CAPTURÉE UNE FOIS au démarrage (pas un getter sur
  // _verses, qui grandit avec les extensions) -- un profil de rythme reste
  // attaché au passage de DÉPART, pas à toute la récitation ininterrompue qui
  // peut s'ensuivre.
  late final String _initialPassageKey;

  // Bismillah attendue au début de toute sourate SAUF Al-Fatiha (déjà son
  // propre verset 1) et At-Tawbah (n'en comporte pas) — demande utilisateur
  // 2026-07-09 : sans ça, dire "بسم الله الرحمن الرحيم" avant de réciter (usage
  // normal) fait comparer le VRAI premier mot de la sourate contre "بسم", qui
  // ne correspond pas -> le premier mot ressort faux à tort. Texte récupéré
  // via QuranApi.fetchBismillah() (verset 1:1 réel) -- JAMAIS tapé à la main
  // (texte sacré : un caractère tapé à la main a cassé "الرحيم" une fois déjà,
  // 2026-07-09, un "ي" persan invisible à l'œil au lieu du "ي" arabe standard).
  // Logique exacte : voir _bismillahBefore, appliquée verset par verset dans
  // _buildChunk (généralisé 2026-07-11 pour gérer plusieurs débuts de sourate
  // dans un même lot chargé -- cf. _maybeExtendNextPage).

  @override
  void initState() {
    super.initState();
    _verses = List.of(widget.verses);
    _initialPassageKey = widget.verses.map((v) => v.key).join('-');
    _breath = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _initAsync();
    _pauseProfile.hasProfileFor(_initialPassageKey).then((has) {
      if (mounted) setState(() => _hasProfile = has);
    });
    _pauseProfile.isGlobalStable().then((stable) {
      if (mounted) setState(() => _globalStable = stable);
    });
    // Correction automatique (demande utilisateur 2026-07-05) : dès qu'un mot
    // est verrouillé rouge, pause + lecture réciteur + reprise, sans tap —
    // seulement si le réglage est activé (sinon comportement inchangé,
    // correction disponible uniquement au tap sur le mot). ref.keepAlive()
    // dans recitationProvider (cf. recitation_provider.dart) garantit que
    // cette instance ne change plus sous nos pieds après cet abonnement.
    _wordFailedSub =
        ref.read(recitationProvider.notifier).wordFailed.listen(_onWordFailed);
  }

  Future<void> _initAsync() async {
    // Récupérée INCONDITIONNELLEMENT (mise en cache statique par QuranApi,
    // quasi gratuite si déjà chargée) : même si CETTE session ne l'utilise pas
    // tout de suite, un enchaînement ultérieur sur la page suivante
    // (_maybeExtendNextPage) en aura besoin, et _bismillahWordCount doit
    // déjà être prêt à ce moment-là (le texte de la Bismillah, donc son
    // nombre de mots, ne change jamais).
    final bismillahVerse = await QuranApi.fetchBismillah();
    final chunk = _buildChunk(_verses, null, bismillahVerse);
    final text = chunk.text;
    final tajwidSpans = chunk.spans;
    final wordKeys = List.generate(
        ArabicNormalizer.splitExpectedWords(text).length, (_) => GlobalKey());
    final bismillahWordCount =
        ArabicNormalizer.splitExpectedWords(bismillahVerse.textUthmani).length;
    // Métadonnées (nom, nombre de versets) de la/les sourate(s) initiale(s) —
    // pour le bandeau de transition (cf. _SurahTransitionBanner), affiché dès
    // le tout premier mot, pas seulement aux enchaînements ultérieurs.
    final initialSurahs = _verses.map((v) => v.surahNumber).toSet();
    final metaEntries = await Future.wait(initialSurahs.map((n) async {
      try {
        return MapEntry(n, await _fetchSurahMeta(n));
      } catch (_) {
        return null;
      }
    }));
    if (!mounted) return;
    // setup() AVANT de rendre l'écran interactif (_ready=true) : sinon un tap
    // assez rapide entre les deux tombe sur state.words encore vide et
    // startContinuous() s'arrête en silence (garde `state.words.isEmpty`,
    // aucune erreur) -- bug réel constaté 2026-07-10, "ça ne charge pas".
    // MAIS setup() ne peut pas s'appeler ICI directement (encore dans le
    // callback async déclenché depuis initState) -- Riverpod refuse de
    // modifier un provider "pendant que l'arbre de widgets se construit"
    // (exception réelle constatée 2026-07-10 juste après ce correctif).
    // addPostFrameCallback reporte l'appel juste après la fin du frame
    // courant -- largement avant qu'un tap humain soit physiquement possible,
    // donc la garantie d'ordre (setup avant tap) reste intacte.
    setState(() {
      _tajwidSpans = tajwidSpans;
      _wordKeys = wordKeys;
      _bismillahWordCount = bismillahWordCount;
      for (final e in metaEntries) {
        if (e != null) _surahMeta[e.key] = e.value;
      }
      _ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(recitationProvider.notifier);
      // setupVerses (verset-conscient) : annote les règles tajwid pour le
      // modèle stage1b-260h (cible d'alignement = forme apprise avec symboles).
      // Fire-and-forget : l'await interne (chargement des annotations, ~1x)
      // ne bloque pas le frame ; _ready garde déjà l'écran non-interactif tant
      // que ce callback n'a pas tourné (même garantie qu'avant avec setup()).
      unawaited(notifier.setupVerses(chunk.segments));
      // Sensibilité déjà réglée par l'utilisateur (persistée) -- ref.listen
      // (build()) ne rattrape que les CHANGEMENTS suivants, pas l'état
      // initial (même raison que le préchauffage de correction ci-dessous).
      notifier.setSensitivity(ref.read(correctionSensitivityProvider));
    });
    // Préchauffe le tout premier verset dès maintenant -- ref.listen (build())
    // ne se déclenche que sur les changements d'état SUIVANTS, pas sur l'état
    // initial (cf. _maybePrefetchCorrectionAudio).
    _maybePrefetchCorrectionAudio(0);
  }

  /// Enchaînement automatique sur la PAGE suivante du Mushaf (pas la sourate
  /// entière -- revu 2026-07-11 après un test réel montrant l'ancien
  /// comportement : "1:1 → 2:286" chargé d'un coup, Al-Baqarah entière/6100
  /// mots dès la fin de la Fatiha. "il faut faire ça dynamiquement, une page
  /// avant et une page après" : une page de Mushaf ne fait que quelques
  /// versets, un incrément raisonnable au lieu d'un bond de plusieurs
  /// milliers de mots dans le texte cible d'alignement). Dès que la
  /// récitation approche de la fin du texte connu (cf.
  /// `_kExtendLookaheadWords`), va chercher la page suivante en arrière-plan
  /// et l'ajoute à la session EN COURS — sans jamais toucher aux mots déjà
  /// jugés/à l'ancre d'alignement (RecitationNotifier.extendWords).
  /// Best-effort : si le fetch réseau n'a pas fini avant que le réciteur
  /// atteigne réellement le dernier mot connu, la session se termine
  /// normalement (comportement inchangé) plutôt que de bloquer l'attente.
  Future<void> _maybeExtendNextPage() async {
    if (_extending || _noMorePages || !mounted) return;
    if (_verses.isEmpty) return;
    final lastVerse = _verses.last;
    final lastPage = lastVerse.pageNumber;
    if (lastPage == null) return; // pagination inconnue -- pas d'enchaînement possible
    final nextPage = lastPage + 1;
    if (nextPage > 604) {
      _noMorePages = true;
      return;
    }
    _extending = true;
    try {
      final fetched = await QuranApi.fetchVersesByPage(nextPage);
      if (!mounted || fetched.isEmpty) return;
      // Filet de sécurité : ne jamais réintroduire un verset déjà chargé.
      final known = _verses.map((v) => v.key).toSet();
      final nextVerses = fetched.where((v) => !known.contains(v.key)).toList();
      if (nextVerses.isEmpty) return;
      final bismillahVerse = await QuranApi.fetchBismillah();
      // _buildChunk insère une Bismillah devant CHAQUE début de sourate dans
      // ce lot (une page peut contenir plusieurs débuts de sourate, contraire
      // à l'ancienne version qui en supposait exactement un par appel).
      final chunk = _buildChunk(nextVerses, lastVerse.surahNumber, bismillahVerse);
      // Métadonnées pour le bandeau de transition -- best-effort, seulement
      // pour les sourates pas déjà en cache.
      final newSurahs = nextVerses.map((v) => v.surahNumber).toSet()
        ..removeWhere(_surahMeta.containsKey);
      final metaEntries = await Future.wait(newSurahs.map((n) async {
        try {
          return MapEntry(n, await _fetchSurahMeta(n));
        } catch (_) {
          return null;
        }
      }));
      if (!mounted) return;
      final newWordCount = ArabicNormalizer.splitExpectedWords(chunk.text).length;
      final newKeys = List.generate(newWordCount, (_) => GlobalKey());
      DiagnosticLog.log('Karaoke', 'Enchaînement page $nextPage : '
          '+${nextVerses.length} versets, +$newWordCount mots');
      setState(() {
        _verses = [..._verses, ...nextVerses];
        _tajwidSpans = [...?_tajwidSpans, ...chunk.spans];
        _wordKeys = [...?_wordKeys, ...newKeys];
        for (final e in metaEntries) {
          if (e != null) _surahMeta[e.key] = e.value;
        }
      });
      await ref.read(recitationProvider.notifier).extendVerses(chunk.segments);
    } catch (e) {
      // Best-effort : un échec ici (réseau, API) ne doit pas interrompre la
      // récitation en cours -- la session se termine juste normalement à la
      // fin du texte déjà connu, comme avant cette fonctionnalité.
      DiagnosticLog.log('Karaoke', 'Échec enchaînement page suivante : $e');
    } finally {
      _extending = false;
    }
  }

  /// Préchauffe l'audio de correction (URLs + segments + fichier MP3 local,
  /// cf. `WordCorrectionAudio.prefetch`) dès que [pointer] entre dans un
  /// NOUVEAU verset -- avant qu'une éventuelle erreur ne le nécessite.
  /// Demande utilisateur 2026-07-11 ("en cas d'erreur ça prend beaucoup de
  /// temps pour réagir") : le fetch à la demande dans `_onWordFailed` a été
  /// mesuré à 4,5-9,2s sur un réseau dégradé, capture déjà en pause tout ce
  /// temps. Fire-and-forget (best-effort) : ne bloque jamais le fil audio
  /// principal.
  void _maybePrefetchCorrectionAudio(int pointer) {
    final verse = _verseContaining(pointer);
    if (verse == null || verse.key == _prefetchedVerseKey) return;
    _prefetchedVerseKey = verse.key;
    final reciter = ref.read(playerProvider).reciter;
    unawaited(WordCorrectionAudio.prefetch(verse, reciter));
  }

  /// « Souffleur » : joue le mot ATTENDU courant (celui sur lequel le réciteur
  /// est bloqué) par la voix du récitateur choisi — à la demande explicite de
  /// l'utilisateur (demande 2026-07-16 : "un moyen d'aide si le user veut que
  /// le récitateur dise le mot suivant").
  ///
  /// Distinct de la correction automatique (`_onWordFailed`), qui se déclenche
  /// SEULE sur une erreur détectée, rejoue une PLAGE (mot précédent + mots
  /// sautés) puis FORCE à refaire cette plage (`rewindAndUnlock`). Ici on ne
  /// juge rien et on ne recule rien : le réciteur a juste un trou de mémoire,
  /// il demande le mot, il l'entend, il continue. Aucun mot n'est marqué.
  ///
  /// Réutilise le même garde-fou audio que la correction automatique, pour une
  /// raison non négociable : pendant la lecture, le HAUT-PARLEUR est capté par
  /// le MICRO. Sans `pauseCapture` + `resetBuffer`, la voix du récitateur
  /// serait transcrite et jugée comme étant celle de l'utilisateur — il aurait
  /// des mots validés (ou fautés) sans avoir ouvert la bouche.
  Future<void> _promptCurrentWord() async {
    // Ne jamais se superposer à une correction automatique en cours : les deux
    // manipulent capture + buffer, s'entrelacer corromprait l'état.
    if (_autoCorrecting || _promptingWord) return;
    final st = ref.read(recitationProvider);
    final pointer = st.pointer;
    final verse = _verseContaining(pointer);
    final local = _localIndexInVerse(pointer);
    if (verse == null || local == null) return;

    setState(() => _promptingWord = true);
    final verifier = ref.read(recitationVerifierProvider);
    final wasListening = st.status == RecitationStatus.listening;
    DiagnosticLog.log('Souffleur', 'demande mot pointer=$pointer '
        'mot="${pointer < st.words.length ? st.words[pointer].display : "?"}" '
        'verset=${verse.key} local=$local');
    try {
      if (wasListening) await verifier.pauseCapture();
      final reciter = ref.read(playerProvider).reciter;
      try {
        // wordsBefore/After = 0 : STRICTEMENT le mot demandé. Contrairement à
        // la correction (qui rejoue le mot précédent pour donner l'élan), ici
        // l'utilisateur sait où il en est — il veut le mot, pas le contexte.
        await WordCorrectionAudio.playWordRange(verse, reciter,
            errorWordIndex: local, wordsBefore: 0, wordsAfter: 0);
      } catch (e) {
        // Même raison que dans _onWordFailed : audio/timing indisponible pour
        // ce récitateur/verset ne doit jamais casser la session en cours.
        DiagnosticLog.log('Souffleur', 'échec lecture : $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(AppLocalizations.of(context)!.karaokeAudioUnavailable),
          ));
        }
      }
      // Laisse le haut-parleur se taire avant de rouvrir le micro.
      await Future.delayed(const Duration(milliseconds: 400));
      // Bug corrigé 2026-07-16 (revue de code, Finding #5) : le check `!mounted`
      // était AVANT ce resetBuffer(), donc sortir de l'écran pendant le délai
      // ci-dessus sautait la purge -- mais le `finally` appelle resumeCapture()
      // INCONDITIONNELLEMENT, rouvrant le micro avec l'audio du récitateur
      // encore dans le buffer natif (réintroduit la classe de bug "micro
      // entend le haut-parleur" corrigée par ailleurs dans ce même diff).
      // Purge D'ABORD (ne dépend pas du widget monté), check `mounted` APRÈS,
      // uniquement pour le `setState` qui suit.
      if (wasListening) await verifier.resetBuffer();
      if (!mounted) return;
    } finally {
      if (wasListening) await verifier.resumeCapture();
      if (mounted) setState(() => _promptingWord = false);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _wordFailedSub?.cancel();
    // ── CAUSE RACINE CORRIGÉE (2026-07-25) ───────────────────────────────
    // Ici, `dispose()` SUPPRIMAIT le dossier temporaire de capture
    // (`discardTempDir`) sans prévenir le côté natif, qui gardait le chemin
    // et continuait d'y écrire un WAV à chaque segment figé. Résultat mesuré
    // sur device : `open failed: ENOENT` sur 30 segments d'affilée,
    // silencieusement avalé par le `catch` best-effort de
    // BufferedTranscriber -- donc AUCUN enregistrement conservé dès qu'on
    // quittait l'écran une fois, et pour toutes les sessions suivantes
    // (le vérificateur n'étant pas `autoDispose`, son BufferedTranscriber
    // survit aux écrans). Asymétrie de fond : le chemin propre (bouton stop
    // -> `_maybeCommitVoiceClips`) appelait bien `setClipCapture(null)`, la
    // sortie d'écran non.
    //
    // Correctif : on prévient le natif (comme le chemin propre) et on ne
    // supprime PLUS rien -- les captures vivent dans un dossier durable et
    // doivent survivre à la sortie d'écran, c'est tout leur intérêt pour le
    // diagnostic. Fire-and-forget : `dispose()` est synchrone et ne doit
    // jamais retarder la fermeture de l'écran.
    // Inconditionnel depuis le 2026-07-25 : la capture n'est plus ARMÉE par
    // cet écran (c'est le provider qui le fait, cf. _applyDiagnosticCapture),
    // donc l'écran ne peut plus savoir si elle tourne. Or c'est justement ce
    // qu'il faut couper en sortant. L'appel est idempotent et sans coût.
    unawaited(ref.read(recitationVerifierProvider).setClipCapture(null));
    super.dispose();
  }

  Future<void> _onWordFailed(int wordIndex) async {
    // Journalisation persistante (Coach IA) : indépendante des réglages de
    // correction automatique ci-dessous, jamais pendant une session de
    // référence (même raison que plus bas : ce n'est pas une vraie erreur de
    // récitation, juste une mesure du rythme naturel du récitant).
    if (!_isReferenceSession) {
      final verse = _verseContaining(wordIndex);
      final local = _localIndexInVerse(wordIndex);
      final words = ref.read(recitationProvider).words;
      if (verse != null && local != null && wordIndex < words.length) {
        final notifier = ref.read(recitationProvider.notifier);
        final kind = notifier.classifyError(wordIndex);
        // Détail par règle précise (demande utilisateur 2026-07-22 : stats
        // par règle de tajwid, pas seulement un compteur "tajwid" global) --
        // ne recalculer que si le classement l'a déjà retenu comme tel, même
        // méthode que classifyError en interne (unrealizedRulesFor).
        final rules = kind == RecitationErrorKind.tajwid
            ? notifier.unrealizedRulesFor(wordIndex, words[wordIndex].detectedRules)
            : const <TajwidRule>[];
        // Mot "frontière" (2026-07-22, demande utilisateur) : ikhafa/iqlab/
        // idgham... sont à cheval sur deux mots -- si c'est le cas ici, on
        // garde le texte du mot SUIVANT pour que l'affichage montre la paire
        // plutôt qu'un seul mot isolé (cf. RuleAnnotationService.isBoundaryWord,
        // rempli depuis boundary_words.jsonl/quran_rules_boundary.json).
        final isBoundary = rules.isNotEmpty &&
            RuleAnnotationService.instance
                .isBoundaryWord(verse.surahNumber, verse.ayahNumber, local);
        final pairWord = isBoundary && wordIndex + 1 < words.length
            ? words[wordIndex + 1].display
            : null;
        // Les écarts TAJWID SONT enregistrés (décision utilisateur
        // 2026-07-23) : détecter et nommer les fautes de tajwid EST la
        // raison d'être du coach -- un coach qui contrôle le tajwid sans
        // savoir restituer les erreurs n'a aucune valeur. J'avais un moment
        // retiré cet enregistrement au motif qu'on ne sait pas distinguer
        // « le récitant ne l'a pas faite » de « le modèle ne l'a pas vue » ;
        // c'était supprimer la fonctionnalité au lieu de fiabiliser la
        // mesure. La bonne réponse est de ne juger le tajwid QUE dans des
        // conditions où la détection est fiable, ce qui est désormais le cas :
        //   - jugement sur segment FIGÉ uniquement (audio complet, contexte
        //     plein pour ConvTajwidHead) -- c'était la cause des `emises=`
        //     vides sur des règles pourtant réalisées ;
        //   - tolérance de frontière pour les règles de jonction (une règle
        //     détectée sur le mot voisin compte comme réalisée) ;
        //   - filtrage par fiabilité mesurée par règle (rule_reliability.json
        //     + _capByRuleReliability) : une classe non fiable n'est jamais
        //     contrôlée d'office.
        // Mesuré sur clips complets : rappel 0,96 (ikhafa) à 0,97
        // (idgham_ghunnah), F1 global 0,975 -- assez fiable pour être restitué.
        RecitationErrorLogService.instance.logError(
          surahNumber: verse.surahNumber,
          ayahNumber: verse.ayahNumber,
          wordIndex: local,
          expectedWord: words[wordIndex].display,
          // Type d'erreur calculé à CHAUD (lettre / harakat / tajwid / sauté) :
          // il faut l'entendu, qui n'est conservé que sur le mot courant --
          // impossible à reconstruire après coup. Cf.
          // RecitationNotifier.classifyError pour la méthode et ses limites.
          kind: kind,
          rules: rules,
          pairWord: pairWord,
        );
      }
    }
    if (!ref.read(autoCorrectionEnabledProvider)) return;
    // Jamais de correction pendant une récitation de RÉFÉRENCE (demande
    // utilisateur 2026-07-06) : ce moment sert uniquement à observer le
    // rythme naturel du réciteur (pauses, tempo) pour PauseProfileService —
    // l'interrompre pour corriger fausserait justement ce qu'on cherche à
    // mesurer.
    if (_isReferenceSession) return;
    // Strict/tolérant (demande utilisateur 2026-07-06) : en mode tolérant,
    // seul le rouge (mot faux) déclenche la correction — l'orange (mot
    // reconnu mais imprécis) est accepté sans interruption.
    final words = ref.read(recitationProvider).words;
    if (wordIndex < words.length &&
        words[wordIndex].status != WordStatus.error &&
        !ref.read(strictCorrectionProvider)) {
      return;
    }
    // Bug corrigé 2026-07-16 (revue de code, Finding #4) : ce guard ne
    // vérifiait que _autoCorrecting, pas _promptingWord (souffleur) -- les
    // deux flux appellent pauseCapture()/WordCorrectionAudio.playWordRange()
    // sur le MÊME lecteur audio statique ; un mot qui échoue pendant que le
    // souffleur joue lançait une correction en parallèle, les deux jeux
    // d'abonnements posSub/doneSub s'entrechoquant.
    if (_autoCorrecting || _promptingWord) return; // un mot/une action a la fois
    // Anti-rafale (demande utilisateur 2026-07-06 : "il me donne pas le temps
    // pour répéter") -- constaté en test réel : quand la reconnaissance
    // décroche (bruit/silence mal interprété), plusieurs mots peuvent
    // s'abandonner en cascade en quelques secondes, chacun redéclenchant sa
    // propre correction automatique dos à dos, sans jamais laisser de vraie
    // fenêtre de silence pour répéter. Un délai minimum entre deux
    // corrections force cette fenêtre, quelle que soit la cause exacte de la
    // cascade côté reconnaissance.
    final cooldown = _correctionCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    if (verse == null || local == null) return;
    // Un seul essai forcé (demande utilisateur 2026-07-16 soir, réglable via
    // followWithoutBlockingProvider) : ce MÊME mot a déjà eu droit à un recul
    // + audio de correction juste avant, et wordFailed refire dessus -- le
    // réciteur n'a pas repris exactement ce que le modèle attendait, mais
    // peut très bien avoir raison (le modèle n'est pas infaillible, cf. les
    // cas de suppression CTC constatés ce jour). Quand le réglage est
    // ACTIVÉ (par défaut), on ne reboucle plus ici : pas de nouvelle
    // pause/audio/recul, le mot garde son statut jugé tel quel et l'ancre
    // continue d'avancer sur ce que dit le réciteur ensuite -- le modèle
    // SUIT au lieu de bloquer. Le souffleur manuel (_promptCurrentWord) reste
    // disponible si le réciteur veut lui-même réentendre/se corriger.
    // DÉSACTIVÉ -- comportement d'origine : chaque échec rejoue l'audio et
    // recule l'ancre, sans limite.
    if (ref.read(followWithoutBlockingProvider) &&
        _lastAutoCorrectedWordIndex == wordIndex) {
      _lastAutoCorrectedWordIndex = null;
      DiagnosticLog.log('Correction',
          'wordFailed déjà corrigé une fois sur ce mot -> on suit sans rebloquer : '
          'wordIndex(global)=$wordIndex');
      return;
    }
    // ── LE MOT EST-IL ENCORE FAUX ? (garde-fou 2026-07-25) ────────────────
    // `wordFailed` porte un index, pas un verdict : entre son émission et cet
    // instant, une passe d'alignement plus récente a pu rejuger le mot BON.
    // Cas mesuré, log 17:35:29 -- correction déclenchée sur `mot=41
    // "ٱلَّذِينَ"` (`entendu=""` -> error), puis **253 ms plus tard** la passe
    // suivante rendait `entendu="ٱلَّذِينَ" -> correct (lock=true)`.
    // L'utilisateur voyait donc le mot VERT à l'écran et entendait quand même
    // la correction : « il me corrige inna alladhina alors qu'il est vert ».
    // On relit donc l'état courant, et on abandonne s'il n'est plus négatif.
    final current =
        wordIndex < words.length ? words[wordIndex].status : WordStatus.pending;
    if (current != WordStatus.error &&
        current != WordStatus.unclear &&
        current != WordStatus.skipped) {
      DiagnosticLog.log('Correction',
          'ABANDON : le mot $wordIndex est repasse a $current avant la correction');
      return;
    }
    DiagnosticLog.log('Correction', 'wordFailed déclenché : wordIndex(global)=$wordIndex '
        'mot="${wordIndex < words.length ? words[wordIndex].display : "?"}" '
        'status=$current '
        'verset=${verse.key} local(dans verset)=$local');
    _lastAutoCorrectedWordIndex = wordIndex;
    _autoCorrecting = true;
    final notifier = ref.read(recitationProvider.notifier);
    // (Ici se calculait `wordsAfter` = nombre de mots de la plage fautive
    // au-delà du premier, via `notifier.rewindRangeEnd()`, pour les REJOUER
    // tous — demande utilisateur 2026-07-06 : « le réciteur doit dire TOUS les
    // vrais mots sautés, pas juste le premier ». Retiré le 2026-07-25 : la
    // règle de lecture est passée à DEUX MOTS MAXIMUM sur demande explicite de
    // l'utilisateur (cf. l'appel à playWordRange plus bas). Le recul de l'ancre
    // couvre toujours toute la plage — `rewindAndUnlock` la calcule lui-même,
    // il n'a jamais eu besoin de cette variable — donc l'exigence « redire tous
    // les mots sautés » reste tenue : seule la LECTURE audio est raccourcie.)
    final verifier = ref.read(recitationVerifierProvider);
    try {
      // ── ORDRE CORRIGE (2026-07-25, mesure a l'appui) ────────────────────
      // AVANT : `await pauseCapture()` (3,6 s + 6,4 s d'appels plateforme),
      // PUIS l'audio du mot, PUIS le recul de l'ancre. Chronologie mesuree sur
      // une correction reelle :
      //   17:08:58.550  wordFailed declenche (mot 30 "هُمْ" faux)
      //   17:09:02.157  pauseCapture()                       +3,6 s
      //   17:09:08.583  pause confirmee                      +6,4 s
      //   17:09:08.588  audio du mot enfin joue
      //   17:09:14.471  [ANCRE] recul 40 -> 30               +5,9 s
      // Soit **15,9 s** entre la detection et le retour de l'ancre sur le mot
      // rate -- pendant lesquelles l'app a continue a juger et VERROUILLER les
      // mots 32 a 39, huit mots passes au vert puis deverrouilles par le recul.
      // A l'ecran : huit mots qui verdissent puis redeviennent en attente,
      // douze secondes apres la faute.
      //
      // MAINTENANT : tout ce qui compte est instantane et sans appel
      // plateforme -- arret logiciel de la chaine, puis recul de l'ancre, PUIS
      // seulement l'audio. Plus aucun mot ne peut etre valide pendant la
      // lecture, et l'ancre est deja revenue sur le mot rate quand le
      // reciteur entend la correction.
      //
      // Le micro reste physiquement actif pendant la lecture : les blocs sont
      // jetes par `_appPaused` (aucun n'atteint `feed()`), donc ni
      // transcription contaminee ni WAV pollue. Choix assume et valide par
      // l'utilisateur -- c'est le prix a payer pour supprimer 10 s d'attente.
      // `pauseCaptureForPlayback` et non `pauseCaptureSoft` (regression
      // corrigee le 2026-07-25) : la premiere version laissait le micro ACTIF
      // pendant la lecture, la lecture perturbait l'enregistrement Android et
      // le flux PCM ne revenait JAMAIS -- dernier bloc a 17:23:50.473, plus
      // rien apres la reprise, l'utilisateur ne pouvait plus continuer. La
      // pause materielle protege l'integrite de l'enregistrement ; elle est
      // donc conservee, mais lancee en tache de fond pour ne rien retarder.
      verifier.pauseCaptureForPlayback();
      // ── L'ANCRE DOIT REVENIR OU ON DEMANDE AU RECITEUR DE REPRENDRE ──────
      // On lui fait entendre `_kCorrectionWordsBefore` mot(s) AVANT le mot
      // rate (pour l'elan), il reprend donc naturellement a ce mot-la. Si
      // l'ancre ne recule que jusqu'au mot rate, son audio commence un mot
      // trop tot et l'aligneur force ce mot-la sur le suivant.
      //
      // MESURE QUI L'IMPOSE (log 17:43:20 -> 17:43:50) :
      //   recul 40 -> 33 (sur "عَلَىٰ")   puis segment "أُو۟لَـٰٓئِكَ عَلَى ٱ…"  (debute au mot 32)
      //   recul 40 -> 34 (sur "هُدًى")    puis segment "عَلَىٰ هُدًى مِّن رَّ…"   (debute au mot 33)
      //   recul 40 -> 36 (sur "رَّبِّهِمْ") puis segment "هُدًى مِّن رَّبِّهِۦ…"    (debute au mot 34)
      // Systematiquement un mot d'ecart. Consequences observees :
      //  - syllabes doublees dans `entendu` (`رَّبِّيْبِّهِمْ`, `بِمُؤْمِنؤْمِنِينَ`,
      //    `ءَامَمَنَّنَّا`) -- pas un audio duplique, un alignement DECALE ;
      //  - des mots DEJA valides repassent negatifs (4 regressions mesurees :
      //    mots 34, 36, 73, 77 ; le mot 36 a recu SEPT jugements) ;
      //  - une seule progression d'un mot par correction (33, 34, 36), d'ou
      //    « je suis oblige de reciter ».
      // Le decalage etait de NOTRE fait : c'est nous qui faisons entendre le
      // mot precedent.
      final rewindTo = (wordIndex - _kCorrectionWordsBefore).clamp(0, wordIndex);
      notifier.rewindAndUnlock(rewindTo);
      if (mounted) setState(() => _resumeHintIndex = rewindTo);
      final reciter = ref.read(playerProvider).reciter;
      // Ne rejoue QUE le mot précédent + la plage fautive (demande
      // utilisateur 2026-07-05/06), pas tout le verset — c'est au réciteur de
      // se souvenir de la suite, mais il doit entendre TOUT ce qu'il faut
      // redire (y compris les mots sautés).
      try {
        // DEUX MOTS MAXIMUM : le mot precedent (pour l'elan) + le mot rate.
        // Rien apres.
        //
        // REMPLACE la regle du 2026-07-06 (« le reciteur doit entendre TOUT ce
        // qu'il faut redire, y compris les mots sautes », d'ou `wordsAfter`
        // jusqu'a 10) -- decision utilisateur du 2026-07-25, explicite :
        // « il faut qu'il me corrige que le mot ou deux mots max et apres me
        // donne la main pour reciter ». Mesure qui l'a motivee : sur une
        // correction reelle, `fromIdx=1 toIdx=8` a rejoue HUIT mots, soit
        // ~7,6 s d'audio avant de rendre la main.
        //
        // Consequence assumee : sur un saut de plusieurs mots, le reciteur
        // n'entend que le premier. L'ancre recule bien sur TOUTE la plage
        // (cf. rewindAndUnlock ci-dessus, `remis en attente: N mot(s)`), donc
        // il sait ou reprendre et redit la suite de memoire.
        await WordCorrectionAudio.playWordRange(verse, reciter,
            errorWordIndex: local,
            wordsBefore: _kCorrectionWordsBefore, wordsAfter: 0);
      } catch (e) {
        // Ne bloque pas la correction si l'audio (URL/segments de timing)
        // est indisponible pour ce récitateur/verset — constat réel
        // 2026-07-10 (sourate 99 : aucune correction audible déclenchée sur
        // des mots pourtant verrouillés rouge). Sans ce catch, une exception
        // ici empêchait rewindAndUnlock plus bas -> le mot restait verrouillé
        // à jamais, sans jamais pouvoir être retenté.
        DiagnosticLog.log('Correction', 'Échec lecture audio de correction : $e');
      }
      // Silence net avant de réécouter : marque clairement "à toi de parler"
      // plutôt qu'un enchaînement immédiat qui ressemble à une boucle.
      await Future.delayed(const Duration(milliseconds: 600));
      // Écran fermé/quitté PENDANT l'attente ci-dessus (constat réel
      // 2026-07-10, crash "Tried to use RecitationNotifier after dispose was
      // called") -- le provider autoDispose peut avoir disparu, on abandonne
      // proprement plutôt que de planter.
      if (!mounted) return;
      // (Le recul + déverrouillage vivait ICI -- demande utilisateur
      // 2026-07-06 : le réciteur doit REFAIRE cette plage avec un nouvel
      // audio, pas continuer sur la suite. S'il se trompe encore, la plage
      // re-échoue naturellement -> wordFailed refire -> même boucle. Cette
      // exigence est INCHANGEE ; seul le MOMENT a bougé, remonté avant la
      // lecture audio le 2026-07-25 pour que plus aucun mot ne soit validé
      // pendant qu'on joue la correction. Ne pas le redescendre.)
      // Vide le buffer de transcription AVANT de reprendre l'écoute (demande
      // utilisateur 2026-07-06) : sans ça, de l'audio déjà dans le buffer
      // avant la pause (pas encore figé au moment de l'erreur) peut ressurgir
      // après la reprise et se faire rejuger tel quel — le mot semblait
      // "déjà retenté" sans que le réciteur ait eu la main pour vraiment
      // répéter. Après ce vidage, seul l'audio de la VRAIE nouvelle tentative
      // sera transcrit.
      await verifier.resetBuffer();
    } finally {
      // Attend que la pause lancée en tâche de fond ait ATTERRI avant de
      // relancer le micro -- sinon `resume()` pourrait devancer `pause()` et le
      // micro resterait coupé. Le coût plugin restant se paie ICI, après la
      // lecture, quand le réciteur écoute plutôt qu'il ne parle.
      await verifier.resumeCaptureAfterPlayback();
      _autoCorrecting = false;
      _correctionCooldownUntil =
          DateTime.now().add(const Duration(seconds: 4));
      if (mounted) {
        setState(() => _resumeHintIndex = wordIndex);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(AppLocalizations.of(context)!.karaokeRepeatIndicated),
        ));
      }
    }
  }

  /// Vrai si une Bismillah doit être comptée AVANT [v] dans le flux de mots —
  /// vrai pour le tout premier verset de la session ET pour le premier verset
  /// de CHAQUE sourate ajoutée par enchaînement (demande utilisateur
  /// 2026-07-11), sauf Al-Fatiha (déjà son propre verset 1) et At-Tawbah
  /// (n'en comporte pas). [prevSurah] = numéro de sourate du verset
  /// PRÉCÉDENT dans `_verses` (null pour le tout premier verset de la liste).
  bool _bismillahBefore(Verse v, int? prevSurah) =>
      v.ayahNumber == 1 &&
      v.surahNumber != 1 &&
      v.surahNumber != 9 &&
      v.surahNumber != prevSurah;

  /// Construit le texte plat + les spans tajwid pour [verses], en insérant la
  /// Bismillah avant chaque début de sourate qui en a besoin (même règle que
  /// [_bismillahBefore], utilisée par ailleurs pour retrouver le verset d'un
  /// mot). Généralise ce qui était un simple bool "cette sourate a besoin
  /// d'une Bismillah" (valable seulement quand un fetch = une sourate entière)
  /// -- l'extension page par page (demande utilisateur 2026-07-11) peut
  /// charger un lot contenant 0, 1 ou plusieurs débuts de sourate (fin d'une
  /// sourate + début de la suivante sur la même page du Mushaf).
  /// [prevSurahBefore] = sourate du dernier verset AVANT [verses] dans
  /// `_verses` (null au tout premier appel de la session).
  ({String text, List<List<TextSpan>> spans, List<RecitationSegment> segments})
      _buildChunk(
          List<Verse> verses, int? prevSurahBefore, Verse bismillahVerse) {
    final style = GoogleFonts.scheherazadeNew(
        fontSize: 30, height: 2.1, color: AppColors.cream);
    final parts = <String>[];
    final spans = <List<TextSpan>>[];
    // Segments verset-clés pour l'annotation des règles tajwid (cf.
    // RecitationNotifier.setupVerses). La Bismillah insérée en tête de sourate
    // est le verset 1:1 (mots identiques) -> annotée sous cette clé.
    final segments = <RecitationSegment>[];
    var prevSurah = prevSurahBefore;
    for (final v in verses) {
      if (_bismillahBefore(v, prevSurah)) {
        parts.add(bismillahVerse.textUthmani);
        spans.addAll(tajweedSpansPerWord(
            bismillahVerse.textUthmani, bismillahVerse.textUthmaniTajweed, style));
        segments.add((surah: 1, ayah: 1, text: bismillahVerse.textUthmani));
      }
      parts.add(v.textUthmani);
      spans.addAll(tajweedSpansPerWord(v.textUthmani, v.textUthmaniTajweed, style));
      segments.add(
          (surah: v.surahNumber, ayah: v.ayahNumber, text: v.textUthmani));
      prevSurah = v.surahNumber;
    }
    return (text: parts.join(' '), spans: spans, segments: segments);
  }

  /// Verset contenant le mot [wordIndex] (les mots affichés = concaténation
  /// des versets, découpés avec la même règle `\s+` que setup()) — compte une
  /// Bismillah (toujours le même nombre de mots, `_bismillahWordCount`) à
  /// chaque frontière de sourate qui en a besoin, pas seulement au début de
  /// la session (cf. `_bismillahBefore`).
  Verse? _verseContaining(int wordIndex) {
    var offset = 0;
    int? prevSurah;
    for (final v in _verses) {
      if (_bismillahBefore(v, prevSurah)) {
        if (wordIndex < offset + _bismillahWordCount) return null; // dans la Bismillah elle-même
        offset += _bismillahWordCount;
      }
      prevSurah = v.surahNumber;
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) return v;
      offset += count;
    }
    return null;
  }

  /// Sourate "propriétaire" du mot [wordIndex] — contrairement à
  /// [_verseContaining] (qui renvoie null pour les mots de la Bismillah, pas
  /// un verset), attribue les mots de Bismillah à la sourate qu'ils
  /// PRÉCÈDENT. Sert uniquement à détecter les frontières de sourate dans
  /// [_verseArea] pour y insérer [_SurahTransitionBanner].
  int? _surahOwning(int wordIndex) {
    var offset = 0;
    int? prevSurah;
    for (final v in _verses) {
      if (_bismillahBefore(v, prevSurah)) {
        if (wordIndex < offset + _bismillahWordCount) return v.surahNumber;
        offset += _bismillahWordCount;
      }
      prevSurah = v.surahNumber;
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) return v.surahNumber;
      offset += count;
    }
    return null;
  }

  /// Position 0-based de [wordIndex] (global, tous versets concaténés) DANS
  /// son propre verset — nécessaire pour les segments de timing audio
  /// (`QuranApi.fetchAyahSegments`, indexés par mot au sein d'un même verset ;
  /// vérifié par appel réel : cette API ne compte pas non plus les marques de
  /// waqf isolées comme un mot séparé, donc ce filtre reste cohérent avec
  /// elle).
  int? _localIndexInVerse(int wordIndex) {
    var offset = 0;
    int? prevSurah;
    for (final v in _verses) {
      if (_bismillahBefore(v, prevSurah)) {
        if (wordIndex < offset + _bismillahWordCount) return null; // dans la Bismillah elle-même
        offset += _bismillahWordCount;
      }
      prevSurah = v.surahNumber;
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) return wordIndex - offset;
      offset += count;
    }
    return null;
  }

  /// Vrai si LANCER une récitation maintenant en ferait une session de
  /// référence (pas de profil dédié pour ce passage, ET profil global pas
  /// encore stable -- cf. `_toggle`). Reflète exactement la décision qui y
  /// est prise, pour que les bandeaux/labels affichés AVANT le tap restent
  /// cohérents avec ce qui se passera réellement (demande utilisateur
  /// 2026-07-12 : ne plus laisser croire à une session de référence une fois
  /// le profil global stable).
  bool get _willBeReferenceSession =>
      _hasProfile == false && _globalStable != true;

  Future<void> _startWithCountdown(RecitationNotifier notifier) async {
    if (_startStage != null) return;
    final verifier = ref.read(recitationVerifierProvider);
    var modelUnavailable = false;
    final sequenceId = DateTime.now().millisecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    try {
      final started = await RecitationStartSequence().run(
        prepareModel: verifier.ensureContinuousModelLoaded,
        startCapture: () {
          // Poussé AVANT start() : la valeur est lue à l'ouverture du flux.
          ref.read(recitationVerifierProvider).noiseSuppress =
              ref.read(noiseSuppressProvider);
          return notifier.startContinuous(
              referenceSession: _isReferenceSession);
        },
        canContinue: () => mounted,
        onStage: (stage) {
          if (stage == RecitationStartStage.modelUnavailable) {
            modelUnavailable = true;
          }
          DiagnosticLog.log(
            'KaraokeStart',
            'event=stage sequence_id=$sequenceId stage=${stage.name} '
                'elapsed_ms=${stopwatch.elapsedMilliseconds}',
          );
          if (mounted) setState(() => _startStage = stage);
        },
      );
      if (!mounted || started || !modelUnavailable) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.karaokeModelUnavailable),
        ),
      );
    } catch (e, st) {
      DiagnosticLog.log(
        'KaraokeStart',
        'event=failed sequence_id=$sequenceId '
            'elapsed_ms=${stopwatch.elapsedMilliseconds} '
            'error_type=${e.runtimeType} detail=$e\n$st',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.karaokeStartFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _startStage = null);
    }
  }

  Future<void> _toggle(RecitationSessionState st, RecitationNotifier n) async {
    if (st.status == RecitationStatus.listening) {
      if (_manuallyPaused) setState(() => _manuallyPaused = false);
      await n.stopContinuous();
      // Fermer la capture audio à CHAQUE arrêt, indépendamment du profil :
      // `_maybeSaveProfile` sort immédiatement hors session de référence
      // (`if (_profileSaved || !_isReferenceSession) return;`), donc s'y fier
      // laisserait la capture native active après une récitation normale --
      // exactement le genre d'état résiduel qui a causé le bug ENOENT du
      // 2026-07-25 (cf. dispose()). L'appel est idempotent.
      await _closeAudioCapture();
      _maybeSaveProfile();
    } else if (st.status != RecitationStatus.processing) {
      _profileSaved = false;
      // Chaque récitation est indépendante (demande utilisateur 2026-07-12) :
      // repart de la sensibilité par défaut, jamais de celle laissée par une
      // récitation précédente (même passage ou non).
      ref.read(correctionSensitivityProvider.notifier).state = 0.5;
      // Si la vérification d'existence du profil n'est pas encore résolue
      // (ouverture d'écran + tap immédiat), on l'attend — sinon la session de
      // référence n'est pas marquée comme telle et rien n'est enregistré
      // (bug constaté au premier test réel, 2026-07-05).
      _hasProfile ??= await _pauseProfile.hasProfileFor(_initialPassageKey);
      _globalStable ??= await _pauseProfile.isGlobalStable();
      // Pas encore de référence DÉDIÉE pour ce passage -> proposer le choix,
      // SAUF si le profil global (autres passages déjà validés) est déjà
      // stable (demande utilisateur 2026-07-12 : "pendant les premières
      // récitations [propose], quand on aura quelque chose de stable on ne
      // propose plus" -- le rythme de pause est une caractéristique de la
      // personne, pas du texte, donc plus besoin de reproposer une fois
      // suffisamment caractérisé sur d'autres sourates). Demande utilisateur
      // 2026-07-10 d'origine : la session de référence forcée à la première
      // récitation d'un passage n'était pas un choix, alors que certains
      // préfèrent la correction automatique dès le premier essai.
      if (_hasProfile == false && _globalStable != true) {
        final wantsReference = await _askReferenceChoice();
        if (wantsReference == null) return; // dialogue annulé
        _isReferenceSession = wantsReference;
      } else {
        _isReferenceSession = false;
      }
      setState(() => _sessionNotice = null);
      // MODE journalisé (2026-07-27, demande utilisateur) : les deux modes
      // partagent toute la chaîne ASR mais pas leurs garde-fous, et rien dans
      // le log ne permettait de les distinguer -- il fallait le DÉDUIRE de
      // l'absence de `wordFailed déclenché`, ce qui est indirect et invitait
      // aux erreurs d'interprétation. Les conséquences sont rappelées sur la
      // ligne même, pour qu'une analyse de log n'ait pas à retourner au code :
      //   - pas de correction => pas de recul d'ancre, donc un mot différé ne
      //     repassera JAMAIS (le contrat "2 chances max" de ForcedAligner
      //     suppose que le réciteur redise le mot -- faux dans ce mode) ;
      //   - pas d'applyBestFor => le seuil de gel reste au défaut, donc la
      //     segmentation n'est pas celle d'une session normale ;
      //   - aucune erreur journalisée, aucune stat remise à zéro.
      DiagnosticLog.log('MODE',
          _isReferenceSession
              ? 'session de REFERENCE : correction DESACTIVEE (donc aucun recul '
                  'd\'ancre), seuil de gel NON personnalise (defaut), aucune '
                  'erreur journalisee, profil de pauses enregistre a la fin si '
                  'precision >= 60%'
              : 'session NORMALE : correction active, seuil de gel personnalise '
                  'si un profil existe');
      if (!_isReferenceSession) {
        // Session normale : seuil de gel adapté à la référence dédiée si elle
        // existe, sinon au profil global (cf. applyBestFor).
        await _pauseProfile.applyBestFor(_initialPassageKey);
      }
      // ── Capture audio de DIAGNOSTIC ─────────────────────────────────────
      // Historique : la capture n'était activée QUE sur une session de
      // référence (elle servait le mini-LoRA, qui exigeait un texte canonique
      // fiable comme vérité terrain). Objectif abandonné ; les WAV servent
      // maintenant à diagnostiquer la chaîne ASR, donc il les faut sur une
      // récitation NORMALE, avec ses erreurs et ses coupures de mots.
      //
      // DÉPLACÉ dans RecitationNotifier.startContinuous
      // (`_applyDiagnosticCapture`) le 2026-07-25, et retiré d'ici. Deux
      // raisons :
      //   1. Deux tests de suite ont produit un log complet mais AUCUN audio
      //      (`capture de clips desactivee`) parce qu'ils partaient d'un écran
      //      qui n'activait pas la capture -- c'est une propriété de « une
      //      session tourne », pas d'un écran.
      //   2. Laisser les deux en place créait DEUX dossiers de capture par
      //      démarrage (mesuré dans le log du 14:48 : deux lignes
      //      `capture de clips activee ->` à 731 ms d'écart, dont une vers un
      //      dossier aussitôt abandonné), donc un dossier vide par récitation
      //      et un log trompeur.
      // Ne pas réintroduire un appel ici : `_closeAudioCapture()` plus bas
      // reste utile (il coupe la capture à l'arrêt) et est idempotent.
      // Remise à zéro des stats d'erreur des sourates récitées (demande
      // utilisateur 2026-07-23 : « si je veux réciter une sourate, elle met à
      // zéro les stats par rapport à cette sourate »). Les compteurs
      // reflètent ainsi la TENTATIVE EN COURS, pas un cumul de toutes les
      // récitations passées -- sinon ils ne font que croître et on ne voit
      // jamais si on progresse sur la sourate. Les autres sourates ne sont
      // pas touchées. Jamais pendant une session de RÉFÉRENCE : elle ne
      // journalise aucune erreur (cf. _onWordFailed), donc effacer serait une
      // perte sèche des stats de la dernière vraie récitation.
      if (!_isReferenceSession) {
        for (final s in _verses.map((v) => v.surahNumber).toSet()) {
          await RecitationErrorLogService.instance.clearSurah(s);
        }
        // Les vues de stats (hub Coach) lisent via ces providers : les
        // invalider force le rafraîchissement, sinon elles afficheraient
        // encore les compteurs de la récitation précédente.
        ref.invalidate(surahErrorSummariesProvider);
        ref.invalidate(errorKindBreakdownProvider);
        ref.invalidate(tajwidRuleBreakdownProvider);
      }
      await _startWithCountdown(n);
    }
  }

  /// Demande si CETTE récitation (passage jamais fait) doit servir de
  /// référence de rythme (pas de correction, juste mesure des pauses) ou
  /// être une récitation normale (correction automatique active, mais sans
  /// profil de pause encore établi pour ce passage). Retourne `null` si
  /// l'utilisateur annule (aucune récitation ne démarre alors).
  Future<bool?> _askReferenceChoice() {
    final t = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.karaokeFirstRecitationTitle),
        content: Text(t.karaokeFirstRecitationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.karaokeReciteNormally),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.karaokeMakeReference),
          ),
        ],
      ),
    );
  }

  /// Coupe/reprend la capture audio SANS terminer la session (contrairement
  /// au tap sur le halo, qui appelle stopContinuous() et clôt tout). Pendant
  /// la pause, aucun mot n'est jugé, aucune ancre ne bouge -- la récitation
  /// reprend exactement là où elle s'était arrêtée.
  Future<void> _togglePause() async {
    final verifier = ref.read(recitationVerifierProvider);
    if (_manuallyPaused) {
      // Vide le buffer avant de reprendre (même raison que la reprise post-
      // correction, cf. _onWordFailed) : sans ça, de l'audio capté juste
      // avant la pause mais pas encore figé pourrait ressurgir et se faire
      // rejuger après coup, comme si le réciteur ne l'avait jamais dit.
      await verifier.resetBuffer();
      await verifier.resumeCapture();
      setState(() => _manuallyPaused = false);
    } else {
      await verifier.pauseCapture();
      setState(() => _manuallyPaused = true);
    }
  }

  /// Fin d'une session de RÉFÉRENCE : si la récitation était bonne, sa
  /// manière de réciter (pauses) est mémorisée définitivement pour ce passage.
  /// Les sessions normales ne touchent jamais à la référence validée.
  Future<void> _maybeSaveProfile() async {
    if (_profileSaved || !_isReferenceSession) return;
    final rst = ref.read(recitationProvider);
    if (rst.total == 0) return;
    final t = AppLocalizations.of(context)!;
    if (rst.accuracy < 60) {
      // Expliquer POURQUOI (demande utilisateur 2026-07-05) : le refus vient
      // du score de reconnaissance, avec les chiffres et quoi faire.
      final missed = rst.total - rst.correctCount - rst.unclearCount;
      final extra =
          '${rst.unclearCount > 0 ? t.karaokeUnclearSuffix(rst.unclearCount) : ''}'
          '${missed > 0 ? t.karaokeMissedSuffix(missed) : ''}';
      setState(() => _sessionNotice = t.karaokeReferenceNotSaved(
          rst.accuracy.round(), rst.correctCount, rst.total, extra));
      // Le PROFIL DE PAUSES n'est pas retenu (récitation trop peu fiable pour
      // servir de référence de rythme), mais l'AUDIO est conservé quand même
      // depuis le 2026-07-25 : une session ratée est justement celle qu'on
      // veut pouvoir écouter pour comprendre pourquoi (cf.
      // _closeAudioCapture).
      await _closeAudioCapture();
      return;
    }
    _profileSaved = true;
    final pauses = await _pauseProfile.fetchSessionPauses();
    await _pauseProfile.saveFor(_initialPassageKey, pauses);
    await _closeAudioCapture();
    // ── DEDUCTION DES DUREES, SUR LE TELEPHONE (2026-07-27) ────────────────
    // Automatique (decision utilisateur) : la session de reference vient de
    // produire exactement la matiere premiere necessaire -- des clips contigus
    // et la correspondance clip -> plage de mots. On recolle les paires de
    // clips pour reconstituer les mots coupes par la segmentation (67 % des
    // erreurs mesurees le 2026-07-27 tombaient sur un bord de segment) et on
    // en tire les durees reelles dans la voix du reciteur.
    // Volontairement APRES saveFor : meme si l'extraction echoue, le profil de
    // pauses -- la raison d'etre historique de cette session -- est acquis.
    final notifier = ref.read(recitationProvider.notifier);
    final segs = notifier.referenceSegments;
    if (segs.length >= 2) {
      final n = await ReferenceTimingExtractor(
              ref.read(recitationVerifierProvider))
          .run(segs, ref.read(recitationProvider).words);
      DiagnosticLog.log('RefTiming',
          'extraction post-session : $n mots mesures sur ${segs.length} segments');
    }
    if (mounted) {
      setState(() {
        _hasProfile = true;
        _sessionNotice = t.karaokeReferenceSaved(
            rst.accuracy.round(), pauses.length);
      });
    }
  }

  /// Clôt la capture audio de la session qui vient de finir : désactive la
  /// capture côté natif, sans rien supprimer.
  ///
  /// ── SIMPLIFIÉ LE 2026-07-25 ───────────────────────────────────────────
  /// Cette méthode prenait un paramètre `keep` : elle remontait les seuls
  /// segments 100 % corrects vers un stockage permanent (mini-LoRA), ou
  /// jetait TOUT le dossier si la récitation globale était jugée peu fiable
  /// (< 60 % de précision). Les deux branches détruisaient de l'audio.
  /// L'objectif mini-LoRA est abandonné et les WAV servent désormais au
  /// diagnostic : on garde tout, quelle que soit la qualité de la
  /// récitation -- une session ratée est précisément celle qu'on veut
  /// pouvoir écouter. Le paramètre `keep` n'a donc plus de sens.
  /// Inconditionnel (cf. dispose) : cet écran n'arme plus la capture, il ne
  /// peut donc plus tester un drapeau local pour savoir s'il y a quelque chose
  /// à fermer. Idempotent côté natif.
  Future<void> _closeAudioCapture() async {
    await ref.read(recitationVerifierProvider).setClipCapture(null);
  }

  /// Feuille de réglage de la sensibilité du jugement GOP (demande
  /// utilisateur 2026-07-12) : curseur tolérant <-> strict, effectif
  /// immédiatement (cf. ref.listen(correctionSensitivityProvider) dans
  /// build()), y compris en pleine récitation -- pas besoin de s'arrêter
  /// pour ajuster.
  /// TOUS les paramètres de vérification, accessibles ICI, sur l'écran de
  /// récitation, derrière une icône (demande utilisateur 2026-07-20 : « tous
  /// les paramètres de vérification seront sur la page de récitation moyennant
  /// une icône »).
  ///
  /// POURQUOI ICI et pas dans un écran de réglages : ces réglages ne servent
  /// QUE pendant la récitation, et souvent EN COURS de récitation (« je suis
  /// jugé trop sévèrement, je desserre tout de suite »). Les enfermer dans un
  /// écran distant obligerait à sortir de la session pour les toucher.
  /// La sensibilité était déjà réglable en direct ici (2026-07-12) ; cette
  /// feuille étend le principe à toute la famille « vérification ».
  ///
  /// Le RÉCITATEUR n'est PAS ici : c'est un choix transverse (écoute,
  /// souffleur, corrections audio) qui vit dans les Réglages généraux.
  /// Lance le jeu de mémorisation (QCM mot par mot) depuis la sourate/le
  /// passage en cours de récitation ici (demande utilisateur 2026-07-24 :
  /// c'est l'écran de récitation du Coach qui doit activer ce chemin, pas la
  /// page de lecture -- celle-ci reste dédiée à la lecture/aux explications).
  /// Même règle de portée que `MemorizationAyahPickerScreen`
  /// (jeux-memorisation SKILL.md) : jamais toute la sourate d'un coup,
  /// seulement les versets de LA MÊME PAGE du Mushaf à partir du premier
  /// verset de ce passage.
  Future<void> _openMemorizationGame(BuildContext context) async {
    final first = widget.verses.first;
    final surahs = await QuranApi.fetchSurahs();
    final surah = surahs.firstWhere((s) => s.number == first.surahNumber,
        orElse: () => surahs.first);
    final page = first.pageNumber;
    final pageVerses = page == null
        ? [first]
        : widget.verses
            .where((v) => v.pageNumber == page && v.ayahNumber >= first.ayahNumber)
            .toList();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemorizationGameScreen(surah: surah, verses: pageVerses),
      ),
    );
  }

  void _openVerificationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final t = AppLocalizations.of(context)!;
          final sensitivity = ref.watch(correctionSensitivityProvider);
          final autoCorr = ref.watch(autoCorrectionEnabledProvider);
          final strict = ref.watch(strictCorrectionProvider);
          final followFree = ref.watch(followWithoutBlockingProvider);
          final useGop = ref.watch(judgementOptionsProvider).useGopScoring;
          // DEUX positions, plus trois (demande utilisateur 2026-07-26) : le
          // palier central « équilibré » n'apportait pas de choix lisible --
          // on tranche entre tolérant et strict. Le seuil du garde-fou
          // « trou d'alignement » suit le même réglage (cf. `_freeConfident`
          // dans recitation_provider.dart), donc un seul curseur gouverne
          // toute la sévérité du jugement.
          final strictSensitivity = sensitivity >= 0.5;
          final label = strictSensitivity
              ? t.prayerFollowSensitivityStrict
              : t.prayerFollowSensitivityTolerant;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.karaokeVerificationSettingsTitle,
                          style: GoogleFonts.fraunces(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cream)),
                      const SizedBox(height: 16),

                      // ── Mode de vérification (presets + 17 règles) ────────
                      _SheetRow(
                        icon: Icons.auto_awesome,
                        title: t.karaokeVerificationModeTitle,
                        subtitle: t.karaokeVerificationModeSubtitle,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TajwidRulesScreen())),
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // ── Sensibilité (réglable en direct) ──────────────────
                      Text(t.karaokeSensitivityTitle,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cream)),
                      const SizedBox(height: 4),
                      Text(
                        t.karaokeSensitivityDescription,
                        style: TextStyle(
                            color: AppColors.cream.withValues(alpha: 0.75),
                            fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                              value: false,
                              label: Text(t.prayerFollowSensitivityTolerant)),
                          ButtonSegment(
                              value: true,
                              label: Text(t.prayerFollowSensitivityStrict)),
                        ],
                        selected: {strictSensitivity},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => ref
                            .read(correctionSensitivityProvider.notifier)
                            .state = s.first ? 1.0 : 0.0,
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith(
                              (st) => st.contains(WidgetState.selected)
                                  ? AppColors.ink
                                  : AppColors.cream),
                          backgroundColor: WidgetStateProperty.resolveWith(
                              (st) => st.contains(WidgetState.selected)
                                  ? AppColors.brassLight
                                  : Colors.transparent),
                          side: WidgetStateProperty.all(
                              const BorderSide(color: Colors.white24)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(label,
                            style: const TextStyle(
                                color: AppColors.brassLight,
                                fontWeight: FontWeight.w600)),
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // ── Moteur de jugement (2026-07-20) ───────────────────
                      // gop (défaut) : alignement forcé, sensible aux nuances
                      // de harakat mais sur-pénalise certains mots (chadda,
                      // hamzat wasl) même bien récités. texte : ancienne
                      // comparaison textuelle floue, moins fine sur les
                      // harakat mais sans ce défaut -- gardée, jamais
                      // supprimée, pour comparer les deux en conditions
                      // réelles avant de trancher.
                      _SheetSwitch(
                        icon: Icons.compare_arrows_rounded,
                        title: t.karaokeEngineTitle,
                        subtitle: useGop
                            ? t.karaokeEngineActiveSubtitle
                            : t.karaokeEngineInactiveSubtitle,
                        value: useGop,
                        onChanged: (v) => ref
                            .read(judgementOptionsProvider.notifier)
                            .setUseGopScoring(v),
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // ── Comportement de correction ────────────────────────
                      _SheetSwitch(
                        icon: Icons.hearing_rounded,
                        title: t.karaokeAutoCorrectionTitle,
                        subtitle: t.karaokeAutoCorrectionSubtitle,
                        value: autoCorr,
                        onChanged: (v) => ref
                            .read(autoCorrectionEnabledProvider.notifier)
                            .set(v),
                      ),
                      _SheetSwitch(
                        icon: Icons.rule_rounded,
                        title: t.karaokeStrictnessTitle,
                        subtitle: strict
                            ? t.karaokeStrictnessStrictSubtitle
                            : t.karaokeStrictnessTolerantSubtitle,
                        value: strict,
                        onChanged: (v) => ref
                            .read(strictCorrectionProvider.notifier)
                            .set(v),
                      ),
                      _SheetSwitch(
                        icon: Icons.fast_forward_rounded,
                        title: t.karaokeFollowFreeTitle,
                        subtitle: followFree
                            ? t.karaokeFollowFreeOnSubtitle
                            : t.karaokeFollowFreeOffSubtitle,
                        value: followFree,
                        onChanged: (v) => ref
                            .read(followWithoutBlockingProvider.notifier)
                            .set(v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Refaire volontairement sa référence (geste explicite, top bar).
  void _requestNewReference() {
    setState(() {
      _hasProfile = false;
      _sessionNotice = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.karaokeNewReferenceSnackbar),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Le texte attendu (Bismillah éventuelle incluse) vient d'un fetch API --
    // pas encore prêt au tout premier frame (voir _initAsync). Écran
    // volontairement minimal (pas de spinner qui casserait l'immersion
    // karaoké) : ambiance seule, le temps que ça arrive (quasi instantané une
    // fois la Bismillah en cache).
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppColors.green900,
        body: SizedBox.expand(),
      );
    }
    // Sensibilité de jugement réglable EN DIRECT (demande utilisateur
    // 2026-07-12) -- répercute tout changement fait depuis la feuille de
    // réglage (cf. _openVerificationSheet) sur le moteur de jugement, sans
    // interrompre la récitation en cours.
    ref.listen(correctionSensitivityProvider, (prev, next) {
      ref.read(recitationProvider.notifier).setSensitivity(next);
    });
    // Fin automatique (tous les mots validés sans tap manuel) : mémoriser le
    // profil de pauses de la session si la récitation était bonne.
    ref.listen(recitationProvider, (prev, next) {
      if (next.status == RecitationStatus.finished &&
          prev?.status != RecitationStatus.finished) {
        _maybeSaveProfile();
      }
      // Enchaînement sur la page suivante du Mushaf (demande utilisateur
      // 2026-07-11, "récitation en flux continu... enchaîner sur une autre
      // sourate", chargement borné page par page après revue le même jour) :
      // dès que la récitation approche de la fin du texte CONNU, va chercher
      // la suite en arrière-plan AVANT d'y arriver -- sinon la session se
      // termine normalement (pointer >= words.length -> finished) au lieu
      // d'enchaîner.
      if (next.status == RecitationStatus.listening &&
          next.words.length - next.pointer <= _kExtendLookaheadWords) {
        _maybeExtendNextPage();
      }
      _maybePrefetchCorrectionAudio(next.pointer);
      // Le repère "reprends ici" s'efface dès que ce mot a reçu un jugement
      // (l'utilisateur a repris, l'indication n'est plus utile).
      final hint = _resumeHintIndex;
      if (hint != null &&
          hint < next.words.length &&
          next.words[hint].status != WordStatus.pending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _resumeHintIndex = null);
        });
      }
    });
    final st = ref.watch(recitationProvider);
    // Défilement automatique vers le mot en cours (demande utilisateur
    // 2026-07-05 : suivre la vitesse de lecture pendant la récitation).
    // Calculé directement depuis l'état affiché par CE build (plutôt que via
    // ref.listen(prev,next), peu fiable ici car le mot "current" peut changer
    // plusieurs fois entre deux frames) — plus robuste, et ne redéclenche
    // qu'au changement réel d'index (demande utilisateur 2026-07-06 : le
    // scroll automatique ne se déclenchait pas de façon fiable).
    final currentIdx = st.words.indexWhere((w) => w.status == WordStatus.current);
    if (currentIdx != -1 && currentIdx != _lastAutoScrolledIndex) {
      _lastAutoScrolledIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // L'utilisateur vient de scroller manuellement -> on ne le contredit
        // pas tout de suite (demande utilisateur : le scroll manuel doit
        // rester utilisable pendant la récitation).
        final until = _manualScrollUntil;
        if (until != null && DateTime.now().isBefore(until)) return;
        if (currentIdx >= _wordKeys!.length) return;
        final ctx = _wordKeys![currentIdx].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
      });
    }
    final notifier = ref.read(recitationProvider.notifier);
    final listening = st.status == RecitationStatus.listening;
    final starting = _startStage != null;
    final t = AppLocalizations.of(context)!;
    final ref0 = _verses.first;
    final subtitle = _verses.length == 1
        ? t.recitationVerseTitle(ref0.key)
        : '${ref0.key} → ${_verses.last.key}';

    return Scaffold(
      backgroundColor: AppColors.green900,
      body: GestureDetector(
        // Un tap n'importe où ne DÉMARRE l'écoute que si elle est arrêtée —
        // l'arrêter, une fois en cours, exige un tap précis sur le halo
        // central (voir _halo). Constat réel (2026-07-09, sourate An-Nas) :
        // toute la surface de l'écran arrêtait l'enregistrement, un tap
        // accidentel en toute fin de récitation coupait les derniers mots
        // avant qu'ils soient entendus.
        onTap: () {
          if (!listening && !starting) _toggle(st, notifier);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ambientBackground(),
            AnimatedBuilder(
              animation: _breath,
              builder: (context, _) => _halo(
                st.soundLevel,
                listening,
                () {
                  if (!starting) _toggle(st, notifier);
                },
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(context, subtitle, st),
                  _referenceBanner(st),
                  Expanded(child: Center(child: _verseArea(st))),
                  _heardCaption(st),
                  _bottomHint(st),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            if (_startStage case final stage?)
              Positioned.fill(child: RecitationStartOverlay(stage: stage)),
          ],
        ),
      ),
    );
  }

  // ── Fond ambiant : dégradé + trame géométrique discrète ──────────────────
  Widget _ambientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.3,
          colors: [AppColors.green700, AppColors.green900],
        ),
      ),
      child: CustomPaint(painter: _LatticePainter(), size: Size.infinite),
    );
  }

  // ── Halo signature : "qandil" lumineux qui respire avec le micro ─────────
  Widget _halo(double level, bool listening, VoidCallback onStopTap) {
    final breathT = (math.sin(_breath.value * 2 * math.pi) + 1) / 2; // 0..1
    final base = listening ? 0.55 + level * 0.5 : 0.32 + breathT * 0.08;
    final scale = listening ? 1.0 + level * 0.22 : 1.0 + breathT * 0.03;
    final circle = Center(
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.brassLight.withOpacity(0.22 * base),
                AppColors.brass.withOpacity(0.10 * base),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
    // Seule zone tactile pour ARRÊTER l'écoute (voir GestureDetector parent) —
    // ignore le tap tant qu'on n'écoute pas, pour ne pas capter les taps
    // destinés à démarrer/redémarrer ailleurs sur l'écran.
    if (!listening) return IgnorePointer(child: circle);
    return GestureDetector(onTap: onStopTap, child: circle);
  }

  // ── Barre supérieure minimale ─────────────────────────────────────────────
  Widget _topBar(BuildContext context, String subtitle, RecitationSessionState st) {
    return Padding(
      // Marge droite ramenée de 20 à 4 (correctif 2026-07-25, cf. le bouton
      // pause rogné plus bas) : 16 dp récupérés sur un écran qui n'en avait
      // plus. `visualDensity: compact` sur les boutons secondaires en récupère
      // 8 de plus chacun. La barre a désormais de la réserve même si un
      // bouton s'y ajoute un jour.
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.brassLight,
                letterSpacing: 0.4,
              ),
            ),
          ),
          // Souffleur (demande utilisateur 2026-07-16) : le réciteur bloque sur
          // un mot et demande à l'entendre. Uniquement pendant l'écoute — hors
          // session, il n'y a pas de "mot courant" à souffler. Désactivé
          // pendant une correction automatique (qui pilote déjà capture+audio)
          // et pendant sa propre lecture.
          if (st.status == RecitationStatus.listening)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.of(context)!.karaokeHearExpectedWordTooltip,
              icon: Icon(
                Icons.volume_up_rounded,
                color: (_autoCorrecting || _promptingWord)
                    ? Colors.white24
                    : AppColors.brassLight,
                size: 20,
              ),
              onPressed: (_autoCorrecting || _promptingWord)
                  ? null
                  : _promptCurrentWord,
            ),
          // Sensibilité du jugement (vert/orange/rouge) réglable EN DIRECT,
          // y compris pendant l'écoute (demande utilisateur 2026-07-12).
          // Icône UNIQUE d'accès à TOUS les paramètres de vérification
          // (demande utilisateur 2026-07-20). Disponible aussi PENDANT
          // l'écoute : c'est souvent en récitant qu'on veut desserrer ou
          // durcir le jugement.
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: AppLocalizations.of(context)!.karaokeVerificationSettingsTitle,
            icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
            onPressed: () => _openVerificationSheet(context),
          ),
          // Bascule vers le jeu de mémorisation (QCM mot par mot) pour ce
          // même passage (demande utilisateur 2026-07-24) -- c'est l'écran
          // de récitation qui active ce chemin, pas la page de lecture.
          //
          // Masqué PENDANT l'écoute (correctif 2026-07-25) : sur un écran de
          // 360 dp, cinq boutons de 48 dp + les marges (28 dp) ne laissaient
          // que 92 dp au titre et **rognaient le bouton pause hors de l'écran**
          // -- l'utilisateur ne pouvait plus mettre en pause du tout
          // (capture d'écran à l'appui, `RIGHT OVERFLOWED BY 12 PIXELS`).
          // C'est cette icône, ajoutée le 2026-07-24, qui a fait déborder la
          // rangée. On ne basculait de toute façon jamais vers un QCM en
          // pleine récitation : la cacher pendant l'écoute est aussi le bon
          // choix fonctionnel, pas seulement un gain de place.
          if (st.status != RecitationStatus.listening)
            IconButton(
              tooltip: AppLocalizations.of(context)!.coachHubGameActionTitle,
              icon: const Icon(Icons.videogame_asset_rounded,
                  color: Colors.white70, size: 20),
              onPressed: () => _openMemorizationGame(context),
            ),
          // Pendant l'écoute : bouton pause/reprise (demande utilisateur
          // 2026-07-10). Sinon, à l'arrêt : geste explicite pour refaire
          // volontairement la référence.
          if (st.status == RecitationStatus.listening)
            IconButton(
              tooltip: _manuallyPaused
                  ? AppLocalizations.of(context)!.karaokeResumeTooltip
                  : AppLocalizations.of(context)!.karaokePauseTooltip,
              icon: Icon(
                _manuallyPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: AppColors.brassLight,
              ),
              onPressed: _togglePause,
            )
          else if (_hasProfile == true)
            IconButton(
              tooltip: AppLocalizations.of(context)!.karaokeRedoReferenceTooltip,
              icon: const Icon(Icons.tune_rounded, color: Colors.white54, size: 20),
              onPressed: _requestNewReference,
            )
          else
            const SizedBox(width: 48), // équilibre visuel avec le bouton retour
        ],
      ),
    );
  }

  /// Bandeau explicite : l'utilisateur SAIT qu'il enregistre sa manière de
  /// réciter (ou qu'elle vient d'être mémorisée). Rien ne se fait en douce.
  Widget _referenceBanner(RecitationSessionState st) {
    final listening = st.status == RecitationStatus.listening;
    String? title;
    String? body;
    final t = AppLocalizations.of(context)!;
    if (_sessionNotice != null && !listening) {
      title = null;
      body = _sessionNotice;
    } else if (_willBeReferenceSession && !listening) {
      title = t.karaokeReferenceRecordingTitle;
      body = t.karaokeReferenceRecordingBody;
    } else if (_isReferenceSession && listening) {
      title = t.karaokeReferenceInProgressTitle;
      body = t.karaokeReferenceInProgressBody;
    }
    if (body == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brass.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brassLight.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  const Icon(Icons.mic_none_rounded,
                      size: 15, color: AppColors.brassLight),
                  const SizedBox(width: 6),
                  // Expanded (correctif 2026-07-25) : « RÉFÉRENCE EN COURS
                  // D'ENREGISTREMENT » en capitales avec letterSpacing 1.2 ne
                  // tient pas dans les 251 dp disponibles sur un écran de
                  // 360 dp -- c'est CE débordement que montrait le marqueur
                  // hachuré de la capture d'écran. Le titre s'ajuste
                  // maintenant au lieu de déborder ; le français est la langue
                  // la plus longue des trois, donc si ça tient ici ça tient
                  // partout.
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brassLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
            ],
            Text(
              body,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.cream.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Verset : mots animés, sans jugement vert/rouge marqué ────────────────
  // Découpé en BLOCS par sourate (pas un unique Wrap géant) — permet
  // d'insérer un bandeau de transition entre deux sourates (demande
  // utilisateur 2026-07-11 : "séparer visuellement les sourates avec le nom
  // de la sourate, un rendu graphique plus beau") au lieu d'enchaîner le
  // texte à plat. Chaque bloc reste un Wrap RTL normal, inchangé.
  Widget _verseArea(RecitationSessionState st) {
    if (st.words.isEmpty) {
      return const CircularProgressIndicator(color: AppColors.brassLight);
    }
    final renderEnd =
        math.min(st.words.length, st.pointer + _kRenderLookaheadWords);
    final blocks = <Widget>[];
    var blockStart = 0;
    int? blockSurah;
    for (var i = 0; i <= renderEnd; i++) {
      final surah = i < renderEnd ? _surahOwning(i) : null;
      // Frontière = fin de la fenêtre de rendu, OU changement de sourate
      // détecté (jamais au tout premier mot : blockSurah est encore null à
      // ce moment-là).
      final boundary = i == renderEnd ||
          (surah != null && blockSurah != null && surah != blockSurah);
      if (boundary) {
        if (i > blockStart) blocks.add(_wordWrapBlock(st, blockStart, i));
        blockStart = i;
        if (i < renderEnd && surah != null) {
          final meta = _surahMeta[surah];
          if (meta != null) blocks.add(_SurahTransitionBanner(meta));
        }
      }
      blockSurah = surah ?? blockSurah;
    }
    return NotificationListener<ScrollNotification>(
      // Un scroll DÉMARRÉ PAR UN GLISSEMENT (dragDetails non-null) = geste
      // manuel de l'utilisateur, par opposition à Scrollable.ensureVisible
      // (programmatique, dragDetails null) — on suspend juste l'auto-scroll
      // le temps que l'utilisateur regarde ce qu'il voulait revoir.
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _manualScrollUntil = DateTime.now().add(const Duration(seconds: 5));
        }
        return false;
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(children: blocks),
      ),
    );
  }

  Widget _wordWrapBlock(RecitationSessionState st, int start, int end) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 18,
        children: [
          for (var i = start; i < end; i++) ...[
            _wordSpan(st.words[i], i),
            // Numéro de fin de verset (demande utilisateur 2026-07-10 :
            // "texte continu", pas de repère d'aya pendant la récitation,
            // contrairement à l'écran de lecture) -- même convention que
            // le Mushaf (le numéro marque la FIN du verset, pas son début).
            if (_isLastWordOfVerse(i)) _KaraokeVerseBadge(_verseContaining(i)!.ayahNumber),
          ],
        ],
      ),
    );
  }

  /// Vrai si [wordIndex] est le DERNIER mot de son verset (le mot suivant
  /// appartient à un autre verset, ou il n'y a plus de mot après) -- jamais
  /// vrai pour un mot de la Bismillah (pas un verset à part entière ici).
  bool _isLastWordOfVerse(int wordIndex) {
    final verse = _verseContaining(wordIndex);
    if (verse == null) return false;
    final words = ref.read(recitationProvider).words;
    if (wordIndex + 1 >= words.length) return true;
    return _verseContaining(wordIndex + 1) != verse;
  }

  // Coloration tajwid lettre-par-lettre TOUJOURS visible (demande utilisateur
  // 2026-07-05, "partout où le texte apparaît") -- le jugement vert/orange/
  // rouge est porté par le FOND, jamais par la couleur du texte, pour que les
  // deux systèmes ne se disputent jamais le même pixel.
  Widget _wordSpan(RecitedWord w, int index) {
    final isCurrent = w.status == WordStatus.current;
    final tajwidWord =
        index < _tajwidSpans!.length ? _tajwidSpans![index] : null;

    Color? bgTint;
    Color? borderTint;
    var opacity = 1.0;
    var underline = false;
    // Fonds plus vifs (retour utilisateur 2026-07-06 : "il y a plus le
    // rouge, le vrai rouge et l'orange" — trop discrets depuis l'intégration
    // du tajwid). Le texte reste coloré tajwid (jamais touché ici) ; le
    // jugement se voit maintenant au fond ET au contour, plus franchement.
    switch (w.status) {
      case WordStatus.correct:
        bgTint = const Color(0xFF6fe3a8).withOpacity(0.38);
        borderTint = const Color(0xFF6fe3a8);
        break;
      case WordStatus.unclear:
        bgTint = const Color(0xFFffcc80).withOpacity(0.42);
        borderTint = const Color(0xFFffcc80);
        break;
      case WordStatus.error:
        // Rouge SEULEMENT si verrouillé (demande utilisateur 2026-07-09 :
        // "il se met en rouge puis en vert, c'est perturbant") -- un aperçu
        // pas encore figé peut sembler faux un instant avant de se stabiliser
        // correctement une fois plus d'audio reçu (mot encore incomplet).
        // Tant que ce n'est pas définitif, on n'affiche rien de spécial
        // plutôt que de faire clignoter rouge->vert.
        if (w.locked) {
          bgTint = const Color(0xFFff8a80).withOpacity(0.42);
          borderTint = const Color(0xFFff8a80);
        }
        break;
      case WordStatus.skipped:
        underline = true;
        break;
      case WordStatus.current:
        break; // le contour doré ci-dessous suffit
      case WordStatus.pending:
        // Texte non-encore-récité MASQUÉ (demande utilisateur 2026-07-06 :
        // "je veux que le texte non récité soit caché, qu'il s'affiche au
        // fur et à mesure qu'on parle") -- quasi invisible plutôt que
        // simplement estompé, pour que ça serve vraiment d'aide à la
        // mémorisation (pas juste un effet visuel). La forme du mot (espace
        // réservé par l'Opacity ci-dessous) reste perceptible pour ne pas
        // casser le rythme visuel de la ligne.
        // SAUF en session de RÉFÉRENCE (demande utilisateur 2026-07-09) :
        // cette session sert à capturer le rythme naturel de lecture (pauses)
        // en suivant le texte des yeux -- masquer le texte n'a pas de sens
        // ici (pas un test de mémoire) et perturbe la lecture normale.
        opacity = _isReferenceSession ? 1.0 : 0.04;
        break;
    }

    final textWidget = (tajwidWord != null && tajwidWord.isNotEmpty)
        ? RichText(text: TextSpan(children: tajwidWord))
        : Text(
            w.display,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 30, height: 2.1, color: AppColors.cream),
          );

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bgTint,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          bottom: BorderSide(
            color: isCurrent
                ? AppColors.brassLight
                : (borderTint ??
                    (underline ? AppColors.brassLight.withOpacity(0.5) : Colors.transparent)),
            width: 2,
          ),
        ),
      ),
      child: Opacity(opacity: opacity, child: textWidget),
    );
    final tappable = w.status == WordStatus.error || w.status == WordStatus.unclear;
    Widget result =
        tappable ? GestureDetector(onTap: () => _openWordHelp(index), child: chip) : chip;

    if (index == _resumeHintIndex) {
      result = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          result,
          Positioned(
            top: -20,
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, _) {
                final t = (math.sin(_breath.value * 2 * math.pi) + 1) / 2;
                return Opacity(
                  opacity: 0.45 + t * 0.55,
                  child: const Icon(Icons.keyboard_double_arrow_down_rounded,
                      color: AppColors.brassLight, size: 20),
                );
              },
            ),
          ),
        ],
      );
    }
    if (index < _wordKeys!.length) {
      result = KeyedSubtree(key: _wordKeys![index], child: result);
    }
    return result;
  }

  /// Tap sur mot orange/rouge (demande utilisateur 2026-07-05) : ouvre la
  /// fiche tajwid + boucle de correction (écouter / se réenregistrer / valider).
  /// Reste disponible même quand la correction automatique est activée (ex:
  /// rejouer volontairement, ou si l'auto-correction est désactivée).
  void _openWordHelp(int wordIndex) {
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    if (verse == null || local == null) return;
    final st = ref.read(recitationProvider);
    showTajwidHelpSheet(
      context,
      ref,
      verse: verse,
      playlist: _verses,
      focusWord: st.words[wordIndex].display,
      wordIndex: wordIndex,
      localWordIndex: local,
    );
  }

  // ── Dernier segment entendu — un souffle, pas un verdict. Tappable : ouvre
  // le transcript complet défilable (demande utilisateur 2026-07-05 — voir
  // tout ce qui a été entendu depuis le début, pas juste la fin tronquée).
  Widget _heardCaption(RecitationSessionState st) {
    final tail = st.rawTranscript.trim();
    final show = tail.isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: !show
          ? const SizedBox(height: 34, key: ValueKey('empty'))
          : GestureDetector(
              onTap: () => _showFullTranscript(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                key: ValueKey(tail.length),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.karaokeHeardLabel,
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            letterSpacing: 1.4,
                            color: AppColors.brassLight.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.unfold_more_rounded,
                            size: 12, color: AppColors.brassLight.withOpacity(0.5)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        tail.length > 90 ? '…${tail.substring(tail.length - 90)}' : tail,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.amiri(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: AppColors.cream.withOpacity(0.65),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Vue défilable du transcript COMPLET depuis le début de la session — pas
  /// tronqué. S'ouvre au tap sur "entendu", se met à jour en direct si la
  /// récitation continue (le bandeau reste ouvert), scroll auto en bas sauf si
  /// l'utilisateur remonte lire l'historique.
  void _showFullTranscript(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green900,
      isScrollControlled: true,
      builder: (ctx) => const _FullTranscriptSheet(),
    );
  }

  Widget _bottomHint(RecitationSessionState st) {
    final t = AppLocalizations.of(context)!;
    final listening = st.status == RecitationStatus.listening;
    final finalizing = st.status == RecitationStatus.processing;
    String label;
    if (finalizing) {
      label = t.karaokeFinalizing;
    } else if (listening && _manuallyPaused) {
      label = t.karaokePausedHint;
    } else if (listening) {
      label = t.karaokeListeningHint;
    } else if (st.status == RecitationStatus.finished) {
      label = t.karaokeFinishedHint;
    } else if (_willBeReferenceSession) {
      label = t.karaokeReferenceStartHint;
    } else {
      label = t.karaokeTapToStartHint;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          listening && _manuallyPaused
              ? Icons.pause_circle_outline_rounded
              : listening
                  ? Icons.graphic_eq
                  : Icons.touch_app_outlined,
          size: 14,
          color: AppColors.brassLight.withOpacity(0.6),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppColors.cream.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}

/// Bandeau de transition entre deux sourates (demande utilisateur
/// 2026-07-11 : "séparer visuellement les sourates avec le nom de la
/// sourate, un rendu graphique plus beau" — pas un enchaînement à plat du
/// texte). Reprend le langage visuel doré/ornemental déjà utilisé ailleurs
/// dans l'app (MushafHeader, _KaraokeVerseBadge) : filets fins encadrant un
/// petit motif, nom arabe en grand, repère FR/numéro en dessous.
class _SurahTransitionBanner extends StatelessWidget {
  final Surah surah;
  const _SurahTransitionBanner(this.surah);

  Widget _rule() => Expanded(
        child: Container(height: 1, color: AppColors.brassLight.withOpacity(0.25)),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Row(
            children: [
              _rule(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.star_rounded,
                    size: 9, color: AppColors.brassLight.withOpacity(0.55)),
              ),
              _rule(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'سورة ${surah.nameArabic}',
            textDirection: TextDirection.rtl,
            style: GoogleFonts.amiri(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.brassLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.karaokeSurahTransitionMeta(surah.number,
                isArabic ? surah.nameArabic : surah.nameSimple, surah.versesCount),
            style: GoogleFonts.manrope(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: AppColors.cream.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _rule(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.star_rounded,
                    size: 9, color: AppColors.brassLight.withOpacity(0.55)),
              ),
              _rule(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pastille de numéro de verset insérée dans le flux de mots de la
/// récitation karaoké -- même convention visuelle que le Mushaf
/// (_VerseNumberBadge de verse_tile.dart), dupliquée ici en privé faute de
/// pouvoir importer un widget privé d'un autre fichier.
class _KaraokeVerseBadge extends StatelessWidget {
  final int number;
  const _KaraokeVerseBadge(this.number);

  static String _toArabicIndic(int n) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((d) => digits[int.parse(d)]).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.brassLight, width: 1.2),
      ),
      child: Center(
        child: Text(
          _toArabicIndic(number),
          style: GoogleFonts.amiri(
            fontSize: 12,
            color: AppColors.brassLight,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Trame géométrique discrète (facettes fines), en clin d'œil aux motifs
/// islamiques sans les reproduire littéralement — reste très en retrait
/// (opacité faible) pour ne pas concurrencer le halo ni le texte.
class _LatticePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brassLight.withOpacity(0.035)
      ..strokeWidth = 1;
    const step = 46.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Feuille défilable montrant le transcript COMPLET (pas tronqué), mise à
/// jour en direct pendant que la récitation continue. Auto-scroll en bas à
/// chaque nouveau texte, sauf si l'utilisateur a remonté manuellement lire
/// l'historique (comportement classique "chat" — ne pas lui arracher la vue).
class _FullTranscriptSheet extends ConsumerStatefulWidget {
  final String? passageSubtitle;
  const _FullTranscriptSheet({this.passageSubtitle});

  @override
  ConsumerState<_FullTranscriptSheet> createState() => _FullTranscriptSheetState();
}

class _FullTranscriptSheetState extends ConsumerState<_FullTranscriptSheet> {
  final _scroll = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final atBottom =
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
      if (atBottom && _userScrolledUp) {
        setState(() => _userScrolledUp = false);
      } else if (!atBottom && !_userScrolledUp) {
        setState(() => _userScrolledUp = true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    if (_userScrolledUp) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(recitationProvider.select((s) => s.rawTranscript)).trim();
    _scrollToBottomIfNeeded();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, sheetScroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.brassLight.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.karaokeTranscriptFullTitle,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brassLight,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: text.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context)!.karaokeNothingHeardYet,
                      style: GoogleFonts.manrope(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        text,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.amiri(
                          fontSize: 19,
                          height: 1.9,
                          color: AppColors.cream.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}


// ── Briques de la feuille « Paramètres de vérification » ─────────────────────

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SheetRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.brassLight, size: 22),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.cream)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(
                fontSize: 11.5, color: Colors.white60)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      );
}

class _SheetSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SheetSwitch(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.brassLight, size: 22),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.cream)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(
                fontSize: 11.5, color: Colors.white60)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.brassLight,
        ),
        onTap: () => onChanged(!value),
      );
}
