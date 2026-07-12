import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../models/recitation_state.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/pause_profile_service.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import '../widgets/tajweed_text.dart';
import '../widgets/tajwid_help_sheet.dart';

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
      notifier.setup(text);
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
      await ref.read(recitationProvider.notifier).extendWords(chunk.text);
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

  @override
  void dispose() {
    _breath.dispose();
    _wordFailedSub?.cancel();
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
        RecitationErrorLogService.instance.logError(
          surahNumber: verse.surahNumber,
          ayahNumber: verse.ayahNumber,
          wordIndex: local,
          expectedWord: words[wordIndex].display,
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
    if (_autoCorrecting) return; // un mot à la fois
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
    DiagnosticLog.log('Correction', 'wordFailed déclenché : wordIndex(global)=$wordIndex '
        'mot="${wordIndex < words.length ? words[wordIndex].display : "?"}" '
        'status=${wordIndex < words.length ? words[wordIndex].status : "?"} '
        'verset=${verse.key} local(dans verset)=$local');
    _autoCorrecting = true;
    final notifier = ref.read(recitationProvider.notifier);
    // À lire AVANT rewindAndUnlock (qui modifie l'ancre) : combien de mots
    // après le premier sont concernés par CETTE plage fautive (un saut de
    // plusieurs mots verrouille toute la plage en un coup, cf. rewindAndUnlock)
    // — demande utilisateur 2026-07-06 : le réciteur doit dire TOUS les vrais
    // mots sautés, pas juste le premier.
    final rangeEnd = notifier.rewindRangeEnd();
    final wordsAfter = (rangeEnd - wordIndex - 1).clamp(0, 10);
    final verifier = ref.read(recitationVerifierProvider);
    try {
      await verifier.pauseCapture();
      final reciter = ref.read(playerProvider).reciter;
      // Ne rejoue QUE le mot précédent + la plage fautive (demande
      // utilisateur 2026-07-05/06), pas tout le verset — c'est au réciteur de
      // se souvenir de la suite, mais il doit entendre TOUT ce qu'il faut
      // redire (y compris les mots sautés).
      try {
        await WordCorrectionAudio.playWordRange(verse, reciter,
            errorWordIndex: local, wordsAfter: wordsAfter);
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
      // Recul + déverrouillage (demande utilisateur 2026-07-06, précisée à
      // plusieurs reprises) : le réciteur doit REFAIRE cette plage avec un
      // nouvel audio, pas continuer sur la suite. S'il se trompe encore, la
      // plage re-échoue naturellement -> wordFailed refire -> même boucle de
      // correction, jusqu'à ce que ce soit correct (vert) et qu'on avance.
      notifier.rewindAndUnlock(wordIndex);
      // Vide le buffer de transcription AVANT de reprendre l'écoute (demande
      // utilisateur 2026-07-06) : sans ça, de l'audio déjà dans le buffer
      // avant la pause (pas encore figé au moment de l'erreur) peut ressurgir
      // après la reprise et se faire rejuger tel quel — le mot semblait
      // "déjà retenté" sans que le réciteur ait eu la main pour vraiment
      // répéter. Après ce vidage, seul l'audio de la VRAIE nouvelle tentative
      // sera transcrit.
      await verifier.resetBuffer();
    } finally {
      await verifier.resumeCapture();
      _autoCorrecting = false;
      _correctionCooldownUntil =
          DateTime.now().add(const Duration(seconds: 4));
      if (mounted) {
        setState(() => _resumeHintIndex = wordIndex);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Répète le mot indiqué ↓'),
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
  ({String text, List<List<TextSpan>> spans}) _buildChunk(
      List<Verse> verses, int? prevSurahBefore, Verse bismillahVerse) {
    final style = GoogleFonts.scheherazadeNew(
        fontSize: 30, height: 2.1, color: AppColors.cream);
    final parts = <String>[];
    final spans = <List<TextSpan>>[];
    var prevSurah = prevSurahBefore;
    for (final v in verses) {
      if (_bismillahBefore(v, prevSurah)) {
        parts.add(bismillahVerse.textUthmani);
        spans.addAll(tajweedSpansPerWord(
            bismillahVerse.textUthmani, bismillahVerse.textUthmaniTajweed, style));
      }
      parts.add(v.textUthmani);
      spans.addAll(tajweedSpansPerWord(v.textUthmani, v.textUthmaniTajweed, style));
      prevSurah = v.surahNumber;
    }
    return (text: parts.join(' '), spans: spans);
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

  Future<void> _toggle(RecitationSessionState st, RecitationNotifier n) async {
    if (st.status == RecitationStatus.listening) {
      if (_manuallyPaused) setState(() => _manuallyPaused = false);
      await n.stopContinuous();
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
      if (!_isReferenceSession) {
        // Session normale : seuil de gel adapté à la référence dédiée si elle
        // existe, sinon au profil global (cf. applyBestFor).
        await _pauseProfile.applyBestFor(_initialPassageKey);
      }
      await n.startContinuous();
    }
  }

  /// Demande si CETTE récitation (passage jamais fait) doit servir de
  /// référence de rythme (pas de correction, juste mesure des pauses) ou
  /// être une récitation normale (correction automatique active, mais sans
  /// profil de pause encore établi pour ce passage). Retourne `null` si
  /// l'utilisateur annule (aucune récitation ne démarre alors).
  Future<bool?> _askReferenceChoice() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Première récitation de ce passage'),
        content: const Text(
          'Veux-tu que cette récitation serve de référence pour ton rythme '
          'naturel (pauses mesurées, sans correction automatique), ou '
          'réciter normalement dès maintenant (avec correction automatique) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Réciter normalement'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Faire une référence'),
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
    if (rst.accuracy < 60) {
      // Expliquer POURQUOI (demande utilisateur 2026-07-05) : le refus vient
      // du score de reconnaissance, avec les chiffres et quoi faire.
      final missed = rst.total - rst.correctCount - rst.unclearCount;
      setState(() => _sessionNotice =
          'Référence non enregistrée : seulement ${rst.accuracy.round()}% des mots '
          'ont été bien reconnus (${rst.correctCount}/${rst.total} corrects'
          '${rst.unclearCount > 0 ? ', ${rst.unclearCount} imprécis' : ''}'
          '${missed > 0 ? ', $missed non reconnus' : ''}). '
          'Une référence doit refléter une récitation fiable — rapproche-toi du '
          'micro, réduis le bruit ambiant, et réessaie à ton rythme naturel.');
      return;
    }
    _profileSaved = true;
    final pauses = await _pauseProfile.fetchSessionPauses();
    await _pauseProfile.saveFor(_initialPassageKey, pauses);
    if (mounted) {
      setState(() {
        _hasProfile = true;
        _sessionNotice = 'Ta manière de réciter ce passage est mémorisée ✓ '
            '(${rst.accuracy.round()}% de reconnaissance, '
            '${pauses.length} pauses apprises)';
      });
    }
  }

  /// Feuille de réglage de la sensibilité du jugement GOP (demande
  /// utilisateur 2026-07-12) : curseur tolérant <-> strict, effectif
  /// immédiatement (cf. ref.listen(correctionSensitivityProvider) dans
  /// build()), y compris en pleine récitation -- pas besoin de s'arrêter
  /// pour ajuster.
  void _openSensitivitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final sensitivity = ref.watch(correctionSensitivityProvider);
          String label;
          if (sensitivity < 0.35) {
            label = 'Tolérant';
          } else if (sensitivity > 0.65) {
            label = 'Strict';
          } else {
            label = 'Équilibré (par défaut)';
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensibilité de la correction',
                      style: GoogleFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 6),
                  Text(
                    'Plus tolérant : accepte des harakat/prononciations '
                    'imprécises en vert. Plus strict : exige une '
                    'prononciation plus proche du modèle pour valider un mot.',
                    style: TextStyle(color: AppColors.cream.withOpacity(0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Tolérant',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: sensitivity,
                          activeColor: AppColors.brassLight,
                          inactiveColor: Colors.white24,
                          onChanged: (v) =>
                              ref.read(correctionSensitivityProvider.notifier).state = v,
                        ),
                      ),
                      const Text('Strict',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  Center(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.brassLight,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('La prochaine récitation redéfinira ta référence pour ce passage.'),
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
    // réglage (cf. _openSensitivitySheet) sur le moteur de jugement, sans
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
    final ref0 = _verses.first;
    final subtitle = _verses.length == 1
        ? 'Verset ${ref0.key}'
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
          if (!listening) _toggle(st, notifier);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ambientBackground(),
            AnimatedBuilder(
              animation: _breath,
              builder: (context, _) =>
                  _halo(st.soundLevel, listening, () => _toggle(st, notifier)),
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
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.brassLight,
                letterSpacing: 0.4,
              ),
            ),
          ),
          // Sensibilité du jugement (vert/orange/rouge) réglable EN DIRECT,
          // y compris pendant l'écoute (demande utilisateur 2026-07-12).
          IconButton(
            tooltip: 'Sensibilité de la correction',
            icon: const Icon(Icons.speed_rounded, color: Colors.white70, size: 20),
            onPressed: () => _openSensitivitySheet(context),
          ),
          // Pendant l'écoute : bouton pause/reprise (demande utilisateur
          // 2026-07-10). Sinon, à l'arrêt : geste explicite pour refaire
          // volontairement la référence.
          if (st.status == RecitationStatus.listening)
            IconButton(
              tooltip: _manuallyPaused ? 'Reprendre' : 'Mettre en pause',
              icon: Icon(
                _manuallyPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: AppColors.brassLight,
              ),
              onPressed: _togglePause,
            )
          else if (_hasProfile == true)
            IconButton(
              tooltip: 'Refaire ma récitation de référence',
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
    if (_sessionNotice != null && !listening) {
      title = null;
      body = _sessionNotice;
    } else if (_willBeReferenceSession && !listening) {
      title = 'Récitation de référence';
      body = 'Première récitation de ce passage : récite à ton rythme naturel — '
          'ta manière de réciter (pauses, tempo) sera mémorisée et respectée '
          'pour toutes tes prochaines récitations.';
    } else if (_isReferenceSession && listening) {
      title = 'Référence en cours d\'enregistrement';
      body = 'Récite naturellement, à ton rythme.';
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
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brassLight,
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
                          'entendu',
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
    final listening = st.status == RecitationStatus.listening;
    final finalizing = st.status == RecitationStatus.processing;
    String label;
    if (finalizing) {
      label = 'Finalisation…';
    } else if (listening && _manuallyPaused) {
      label = 'En pause — touche ⏸ pour reprendre';
    } else if (listening) {
      label = 'À l\'écoute — touche le cercle pour t\'arrêter';
    } else if (st.status == RecitationStatus.finished) {
      label = 'Touche l\'écran pour recommencer';
    } else if (_willBeReferenceSession) {
      label = 'Touche l\'écran pour enregistrer ta récitation de référence';
    } else {
      label = 'Touche l\'écran pour commencer';
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
            '${surah.number} · ${surah.nameSimple} · ${surah.versesCount} versets',
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
                  'TRANSCRIPT COMPLET',
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
                      'Rien entendu pour l\'instant.',
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
