import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/player_state_model.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';
import '../widgets/verse_tile.dart';
import '../widgets/mushaf_header.dart';
import '../widgets/reading_settings_sheet.dart';
import '../widgets/coach_explanation_sheet.dart';
import '../widgets/surah_ornament_header.dart';
import '../widgets/quran_pattern_background.dart';
import 'coach_screen.dart';
import 'recitation_screen.dart';
import 'karaoke_recitation_screen.dart';
import 'memorization_game_screen.dart';
import 'mind_map_screen.dart';

class MushafScreen extends ConsumerStatefulWidget {
  final Surah surah;
  // Verset à afficher/scroller directement à l'ouverture (demande utilisateur
  // 2026-07-18, "Shazam coranique" : après avoir identifié un passage entendu
  // en ambiance, ouvrir directement dessus plutôt que le début de la sourate).
  final int? initialAyahNumber;
  const MushafScreen({super.key, required this.surah, this.initialAyahNumber});

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

enum _EntryKind { verse, bismillah, surahBanner }

// Un item de la liste rendue : soit un verset (référence par index dans
// `_verses`, la liste plate à travers toutes les sourates chargées), soit
// une bannière insérée entre deux sourates (nom de sourate, puis Bismillah).
class _ListEntry {
  final _EntryKind kind;
  final int? verseIndex;
  final Verse? bismillah;
  final Surah? surah;
  const _ListEntry.verse(int index)
      : kind = _EntryKind.verse, verseIndex = index, bismillah = null, surah = null;
  const _ListEntry.bismillah(Verse verse)
      : kind = _EntryKind.bismillah, bismillah = verse, verseIndex = null, surah = null;
  const _ListEntry.surahBanner(Surah s)
      : kind = _EntryKind.surahBanner, surah = s, verseIndex = null, bismillah = null;
}

class _MushafScreenState extends ConsumerState<MushafScreen> {
  List<Verse> _verses = [];
  bool _loading = true;
  String? _error;
  int _activeVerse = 0;
  bool _showTranslation = false;

  // Défilement infini entre sourates (demande utilisateur 2026-07-18 :
  // "actuellement on affiche sourate par sourate, impossible de passer à la
  // prochaine sourate" -> "défilement infini automatique", comme un vrai
  // Mushaf papier). `_verses`/`_verseKeys` restent une liste PLATE, à travers
  // toutes les sourates chargées -- tout le code existant (index actif,
  // fragment pour le karaoké, scroll par index) continue de fonctionner sans
  // changement. `_items` est la liste de RENDU (verset, ou bannière
  // Bismillah/nom de sourate insérée entre deux sourates).
  List<Surah> _loadedSurahs = [];
  /// Page suivante du Mushaf a charger (1-604), null quand il n'y en a plus.
  ///
  /// ── PAGE, PLUS SOURATE (2026-08-06, demande utilisateur) ────────────────
  /// « dans le mushaf il faut enchainer les PAGES, c'est un seul mushaf ;
  /// reutilise la separation entre les sourates comme dans la page recitation ».
  /// L'enchainement se faisait sourate par sourate (`fetchVerses`) : ouvrir
  /// Al-Baqara depuis la sourate precedente chargeait ses 286 versets d'un
  /// seul coup, et un mushaf ne se lit pas par sourates entieres mais par
  /// pages. Meme granularite que l'ecran de recitation, qui enchaine deja par
  /// page (`_maybeExtendNextPage`).
  int? _nextPage;
  bool _loadingMore = false;
  List<Surah>? _allSurahsCache;
  List<_ListEntry> _items = [];

  final _scrollController = ScrollController();

  // Mode Kindle (demande utilisateur 2026-08-01) -- 4e version, la plus
  // simple : après deux échecs d'un système de PAGES séparé (seuil de mots --
  // sautait du contenu ; découpage par pixel puis par mot -- corrects mais
  // plus fragiles et plus longs que nécessaire), retour au défilement
  // continu existant (déjà stable) + un saut de scroll animé au tap
  // ("un défilement éclair pour que le texte monte d'un coup", proposition
  // de l'utilisateur) -- cf. `_kindleJumpPage`. Zéro système de pagination
  // à maintenir.
  Timer? _kindleAutoTurnTimer;

  // Une clé par verset pour pouvoir faire défiler jusqu'au verset en cours de
  // lecture — hauteurs variables (texte + trad. optionnelle), donc
  // Scrollable.ensureVisible plutôt qu'un calcul d'offset.
  List<GlobalKey> _verseKeys = [];

  // À moins de 1200px du bas, on déclenche déjà le chargement de la sourate
  // suivante -- l'enchaînement doit être invisible, jamais un blanc/un à-coup
  // pendant que le lecteur arrive en bas.
  static const _kLoadMoreThreshold = 1200.0;

  // Lecture plein écran -- REFONTE_IHM.md §3. Le header (nom de sourate,
  // navigation) n'est plus un appBar fixe : il glisse depuis le haut au tap
  // sur la bande haute de l'écran, et se remasque après quelques secondes
  // sans interaction. La barre d'actions du bas (lecture/micro/réglages)
  // reste toujours visible -- ce sont des contrôles fonctionnels, pas du
  // chrome de navigation, le plein écran ne vise que le texte + son header.
  bool _headerVisible = true;
  Timer? _headerHideTimer;
  static const _kHeaderAutoHideDelay = Duration(seconds: 4);
  // Doit correspondre à MushafHeader.preferredSize (widgets/mushaf_header.dart)
  // -- dupliqué en constante locale ici pour éviter d'instancier un widget
  // juste pour lire sa taille.
  static const _kMushafHeaderHeight = 120.0;
  // Même principe pour _BottomBar (icônes + libellés + marges + SafeArea) --
  // approximation, comme _kMushafHeaderHeight ci-dessus.
  static const _kBottomBarHeight = 92.0;
  // Marge minimale gardée quand le chrome est masqué (plein écran réel,
  // demande utilisateur 2026-08-01 : "le menu en bas doit disparaître
  // vraiment", et l'espace qu'il libère doit redevenir utilisable pour le
  // contenu -- pas juste visuellement caché avec le padding qui reste figé
  // à la taille du chrome visible).
  static const _kHiddenChromeMargin = 12.0;

  /// Distance gardée entre la poignée de rappel et l'encoche système : sous
  /// cette marge, la zone de gestes d'Android capte le tap en premier et la
  /// poignée ne répond pas (constaté sur device, 2026-08-05).
  static const _kMargeGesteSysteme = 24.0;

  // Bouton retour rond : `top: 8` + IconButton (48 de haut par défaut).
  static const _kBoutonRetourHauteur = 8.0 + 48.0;

  /// Place à réserver EN HAUT pour que le texte ne passe jamais sous un
  /// élément flottant.
  ///
  /// ── LE DÉFAUT QUE CE GETTER SUPPRIME (2026-08-05) ──────────────────────
  ///
  /// La réserve était écrite en clair à quatre endroits, sous la forme
  /// `_headerVisible ? _kMushafHeaderHeight + 8 : _kHiddenChromeMargin`. Elle
  /// ne connaissait donc QUE le header. Or le bouton retour est
  /// `Positioned(top: 8)` et **ne se masque jamais** (retour utilisateur
  /// 2026-07-19 : c'était la seule façon de revenir en arrière). Résultat :
  /// dès que le minuteur de 4 s masquait le header, la réserve tombait à
  /// 12 px et le bouton recouvrait le texte coranique -- constaté sur capture,
  /// le mot `فِى` du verset 6:7 était illisible sous le rond.
  ///
  /// Le correctif n'est pas d'ajouter 56 px quelque part : c'est que la
  /// réserve DÉRIVE de ce qui est visible. Un futur élément flottant permanent
  /// devra être ajouté ici, et nulle part ailleurs -- il n'y a plus quatre
  /// formules à retrouver et à garder cohérentes.
  ///
  /// L'encoche est comptée explicitement : le bouton est dans un `SafeArea`,
  /// la liste ne l'est pas.
  double _reserveHaut(BuildContext context) => _headerVisible
      ? _kMushafHeaderHeight + 8
      : MediaQuery.of(context).padding.top + _kBoutonRetourHauteur;

  /// Place à réserver EN BAS. La barre du bas, elle, glisse hors de l'écran
  /// quand le chrome est masqué : rien ne reste, la marge minimale suffit.
  double _reserveBas() =>
      _headerVisible ? _kBottomBarHeight + 8 : _kHiddenChromeMargin;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHeaderHide();
    // `kindleAutoTurnProvider` est un état global (pas ré-initialisé par
    // écran) -- s'il était déjà activé avant d'arriver sur CET écran, il faut
    // démarrer le minuteur ici ; `ref.listen` dans build() ne réagit qu'aux
    // CHANGEMENTS futurs, pas à l'état déjà en place à l'ouverture.
    if (ref.read(kindleAutoTurnProvider)) {
      _demarrerCalibration();
    }
  }

  /// Un tournage AUTOMATIQUE : la page tourne, l'horloge de mesure repart, et
  /// on retient que ce tournage n'est pas de la main du lecteur -- c'est ce
  /// qui rend un retour arriere interpretable.
  void _tournerAutomatiquement(double seconds) {
    if (!mounted) return;
    // Même formule que le tap manuel (§_buildVerses) -- un `*0.7`
    // approximatif ici aurait fait sauter un peu plus ou moins qu'un
    // vrai "page suivante", décalant l'auto-tournage du tap manuel.
    final size = MediaQuery.of(context).size;
    final viewportHeight = size.height - _reserveHaut(context) - _reserveBas();
    _kindleJumpPage(viewportHeight, forward: true);
    DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
        'tournage AUTOMATIQUE (delai ${seconds.toStringAsFixed(1)}s) '
        '-- rien appris, le lecteur n\'a rien dit');
    // La page a tourné TOUTE SEULE : rien à apprendre, le lecteur n'a rien
    // dit. On remet le chronomètre de MESURE à zéro pour la page suivante.
    _debutPage = DateTime.now();
    _dernierTournageAutomatique = true;
  }

  /// Repousse le prochain tournage automatique SANS toucher a l'horloge de
  /// mesure : le lecteur est actif, la page ne doit pas tourner sous ses yeux,
  /// mais la duree de lecture de cette page continue de courir depuis son
  /// affichage.
  void _reporterMinuteur() {
    if (!ref.read(kindleAutoTurnProvider) || _calibrationEnCours) return;
    final s = ref.read(kindlePageSecondsProvider);
    _kindleAutoTurnTimer?.cancel();
    _kindleAutoTurnTimer = Timer.periodic(Duration(seconds: s.round()), (_) {
      _tournerAutomatiquement(s);
    });
  }

  /// Remet le mode automatique en attente de mesure (cf. `_calibrationEnCours`).
  void _demarrerCalibration() {
    _kindleAutoTurnTimer?.cancel();
    _calibrationEnCours = true;
    _debutPage = null; // aucun intervalle connu : le 1er tap n'apprendra rien
    DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
        'calibration demandee : deux taps pour donner la cadence');
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _kindleAutoTurnTimer?.cancel();
    _headerHideTimer?.cancel();
    // Restaure le chrome système normal en quittant l'écran de lecture --
    // ne pas laisser toute l'app en immersif au-delà de cet écran.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHeaderHide() {
    _headerHideTimer?.cancel();
    // ── LE MENU RESTE PENDANT LA LECTURE (2026-08-13) ──────────────────────
    // Demande utilisateur : « quand on lance l'audio dans le Mushaf, laisse le
    // menu affiché, ne le réduis pas ».
    //
    // Le repli automatique sert la lecture SILENCIEUSE : on lit, le chrome
    // s'efface, on a le plein écran. Pendant une écoute, il dessert -- les
    // commandes de transport (pause, vitesse, répétition) sont précisément ce
    // dont on a besoin sous la main, et il fallait retoucher l'écran pour les
    // faire revenir à chaque fois.
    //
    // On ne coupe pas le mécanisme, on le suspend le temps de l'écoute : dès
    // que l'audio s'arrête, le prochain `_showHeader` reprogramme le repli et
    // le plein écran revient de lui-même.
    if (ref.read(playerProvider).isPlaying) return;
    _headerHideTimer = Timer(_kHeaderAutoHideDelay, () {
      if (mounted) setState(() => _headerVisible = false);
    });
  }

  void _showHeader() {
    setState(() => _headerVisible = true);
    _scheduleHeaderHide();
  }

  Future<void> _load() async {
    try {
      final needsBismillah =
          widget.surah.number != 1 && widget.surah.number != 9;
      final verses = await QuranApi.fetchVerses(widget.surah.number);
      final bismillah =
          needsBismillah ? await QuranApi.fetchBismillah() : null;
      setState(() {
        _verses = verses;
        _verseKeys = List.generate(verses.length, (_) => GlobalKey());
        _loadedSurahs = [widget.surah];
        final dernierePage = verses.isEmpty ? null : verses.last.pageNumber;
        _nextPage = (dernierePage != null && dernierePage < 604)
            ? dernierePage + 1
            : null;
        _items = [
          if (bismillah != null) _ListEntry.bismillah(bismillah),
          for (var i = 0; i < verses.length; i++) _ListEntry.verse(i),
        ];
        _loading = false;
      });
      final targetAyah = widget.initialAyahNumber;
      if (targetAyah != null) {
        final idx = verses.indexWhere((v) => v.ayahNumber == targetAyah);
        if (idx >= 0) {
          setState(() => _activeVerse = idx);
          _scrollToIndex(idx, const Duration(milliseconds: 400));
        }
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!_loadingMore &&
        _nextPage != null &&
        pos.maxScrollExtent - pos.pixels < _kLoadMoreThreshold) {
      _chargerPageSuivante();
    }
  }

  /// Charge la PAGE suivante du Mushaf et l'ajoute a la suite, dans le meme
  /// scroll continu -- en inserant une banniere de sourate + Bismillah a
  /// CHAQUE debut de sourate rencontre dans la page (une page peut en contenir
  /// plusieurs, et At-Tawbah n'a pas de Bismillah).
  ///
  /// Idempotent : `_loadingMore` protege des appels rapproches, le scroll
  /// declenchant `_onScroll` a chaque frame tant qu'on est pres du bas.
  ///
  /// ⚠️ ECHEC JOURNALISE, pas seulement `debugPrint` : l'ancienne version
  /// avalait toute exception dans un `debugPrint` invisible en production --
  /// un `firstWhere` sans correspondance suffisait a arreter l'enchainement
  /// pour de bon, sans que rien ne le dise.
  Future<void> _chargerPageSuivante() async {
    final page = _nextPage;
    if (page == null || _loadingMore) return;
    _loadingMore = true;
    try {
      _allSurahsCache ??= await QuranApi.fetchSurahs();
      final nouveaux = await QuranApi.fetchVersesByPage(page);
      if (!mounted) return;
      if (nouveaux.isEmpty) {
        setState(() => _nextPage = page < 604 ? page + 1 : null);
        return;
      }
      // Filet : ne jamais reintroduire un verset deja charge (meme regle que
      // l'ecran de recitation -- une page peut chevaucher ce qu'on a deja).
      final connus = _verses.map((v) => v.key).toSet();
      final verses = nouveaux.where((v) => !connus.contains(v.key)).toList();
      if (verses.isEmpty) {
        setState(() => _nextPage = page < 604 ? page + 1 : null);
        return;
      }
      Verse? bismillah;
      if (verses.any((v) => v.ayahNumber == 1 &&
          v.surahNumber != 1 && v.surahNumber != 9)) {
        bismillah = await QuranApi.fetchBismillah();
      }
      if (!mounted) return;
      setState(() {
        final baseIdx = _verses.length;
        _verses = [..._verses, ...verses];
        _verseKeys = [
          ..._verseKeys,
          ...List.generate(verses.length, (_) => GlobalKey()),
        ];
        final ajouts = <_ListEntry>[];
        var precedente = _loadedSurahs.isEmpty ? null : _loadedSurahs.last.number;
        final chargees = [..._loadedSurahs];
        for (var i = 0; i < verses.length; i++) {
          final v = verses[i];
          // Debut de sourate = separation, exactement comme l'ecran de
          // recitation : banniere de nom puis Bismillah (sauf 1 et 9).
          if (v.surahNumber != precedente) {
            final s = _allSurahsCache!
                .where((x) => x.number == v.surahNumber)
                .toList();
            if (s.isNotEmpty) {
              ajouts.add(_ListEntry.surahBanner(s.first));
              if (chargees.every((c) => c.number != s.first.number)) {
                chargees.add(s.first);
              }
            }
            if (v.ayahNumber == 1 &&
                v.surahNumber != 1 && v.surahNumber != 9 && bismillah != null) {
              ajouts.add(_ListEntry.bismillah(bismillah));
            }
            precedente = v.surahNumber;
          }
          ajouts.add(_ListEntry.verse(baseIdx + i));
        }
        _items = [..._items, ...ajouts];
        _loadedSurahs = chargees;
        _nextPage = page < 604 ? page + 1 : null;
      });
    } catch (e) {
      DiagnosticLog.log('Mushaf', 'echec chargement page $page : $e');
      debugPrint('[Mushaf] échec chargement page $page : $e');
    } finally {
      _loadingMore = false;
    }
  }

  // Nom de la sourate propriétaire d'un verset donné -- nécessaire pour les
  // titres (Coach IA, explication de mot) depuis que `_verses` peut couvrir
  // plusieurs sourates : `widget.surah` n'est plus forcément celle du verset
  // actif.
  Surah _surahForNumber(int number) => _loadedSurahs.firstWhere(
        (s) => s.number == number,
        orElse: () => widget.surah,
      );

  void _openReadingSettings() {
    showReadingSettingsSheet(
      context,
      ref,
      showTranslation: _showTranslation,
      onToggleTranslation: () =>
          setState(() => _showTranslation = !_showTranslation),
    );
  }

  // Explique l'aya actuellement sélectionnée (celle sur laquelle l'utilisateur
  // a tapé, _activeVerse — demande utilisateur 2026-07-10 : accès direct au
  // Coach IA depuis la lecture, pas seulement depuis le journal d'erreurs).
  // useErrorLog: false -- lire un verset n'est pas une révision d'erreur,
  // même si ce verset a par ailleurs été raté en récitation ; le registre
  // doit rester "sens du verset", pas "mot que j'ai du mal à retenir"
  // (demande utilisateur 2026-07-10, cette page partait sur la mémorisation).
  //
  // Icône retirée de la barre du bas le 2026-08-10 (constat utilisateur :
  // « une icône coach IA qui n'est plus utilisée » -- le tuteur Gemma qui
  // alimentait ce sheet a été retiré le même jour, cf. pubspec.yaml). Le
  // sheet (`CoachExplanationSheet`) reste utile via sa cascade non-IA ;
  // méthode conservée intacte (même logique que `_openWordExplanation`
  // juste en dessous) pour la rebrancher proprement si un jour cette entrée
  // directe redevient utile, plutôt que de la supprimer.
  // ignore: unused_element
  void _openCoachExplanation() {
    if (_verses.isEmpty) return;
    final verse = _verses[_activeVerse];
    final surah = _surahForNumber(verse.surahNumber);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: AppLocalizations.of(context)!.mushafExplanationTitleSurahVerse(
          isArabic ? surah.nameArabic : surah.nameSimple, verse.ayahNumber),
      useErrorLog: false,
    );
  }

  // Explique un mot précis tapé dans le verset (demande utilisateur
  // 2026-07-10 : granularité mot, pas seulement verset entier).
  //
  // Plus appelée depuis le 2026-08-09 (retrait du branchement `onWordLongPress`
  // ci-dessous, demande utilisateur : « à faire après ») -- conservée intacte
  // pour la rebrancher proprement plus tard, plutôt que de la supprimer.
  // ignore: unused_element
  void _openWordExplanation(Verse verse, int wordIdx) {
    // Même filtre que tajweedSpansPerWord/TajweedText (source de [wordIdx]
    // via onWordTap) -- sans lui, une marque décorative isolée (ex. "۞")
    // désynchronise cet index de la liste ici recalculée, et le mauvais mot
    // s'affiche dans l'explication (bug corrigé 2026-07-11, même classe que
    // le décalage de coloration tajwid).
    final words = verse.textUthmani
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && ArabicNormalizer.normalize(w).isNotEmpty)
        .toList();
    if (wordIdx < 0 || wordIdx >= words.length) return;
    final surah = _surahForNumber(verse.surahNumber);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: AppLocalizations.of(context)!.mushafExplanationTitleSurahVerseWord(
          isArabic ? surah.nameArabic : surah.nameSimple, verse.ayahNumber,
          words[wordIdx]),
      focusWord: words[wordIdx],
      focusWordIndex: wordIdx,
      useErrorLog: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);

    final kindleMode = ref.watch(kindleModeProvider);
    final modeSombre = ref.watch(modeSombreProvider);
    ref.listen(kindleAutoTurnProvider,
        (_, next) => _syncKindleAutoTurn(next, ref.read(kindlePageSecondsProvider)));
    ref.listen(kindlePageSecondsProvider,
        (_, next) => _syncKindleAutoTurn(ref.read(kindleAutoTurnProvider), next));
    ref.listen(kindleAutoTurnProvider, (_, actif) {
      if (actif) {
        _demarrerCalibration();
      } else {
        _syncKindleAutoTurn(false, 0);
      }
    });

    // Curseur de lecture (demande utilisateur 2026-07-06 : la lecture reste
    // sur cette page, avec un fond bleu qui suit le verset en cours et un
    // scroll automatique jusqu'à lui — pas de navigation vers un autre écran).
    final playingVerseKey =
        playerState.isActive ? playerState.currentVerse?.key : null;
    // Ne PAS filtrer sur isPlaying/isPaused ici : au moment exact où
    // currentVerse change (play()), le statut vaut encore "loading" — un
    // filtre sur le statut ratait donc systématiquement le déclenchement.
    ref.listen<PlayerStateModel>(playerProvider, (prev, next) {
      final key = next.currentVerse?.key;
      if (key != null && key != prev?.currentVerse?.key) {
        _scrollToVerseKey(key, next.speed);
      }
    });

    return Scaffold(
      backgroundColor: modeSombre
          ? AppColors.sombreBg
          : (kindleMode ? AppColors.kindleBg : AppColors.cream),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.green800))
          : _error != null
              ? _ErrorView(onRetry: _load)
              : Stack(
                  children: [
                    // Pas de motif décoratif ni de badge de défilement en
                    // mode Kindle -- c'est le thème sobre "repos-yeux" qui
                    // remplace ces éléments, pas un mode qui les empile.
                    // Le motif de fond est un decor CLAIR : sur fond noir il
                    // fait un voile grisatre et mange le contraste du texte.
                    if (!kindleMode && !modeSombre)
                      const QuranPatternBackground(),
                    _buildVerses(playingVerseKey,
                        kindleMode: kindleMode, modeSombre: modeSombre),
                    // Bande invisible en haut de l'écran (~15% de hauteur) :
                    // seule active quand le header est masqué (sinon le
                    // header, positionné par-dessus, intercepte le tap en
                    // premier -- ordre du Stack). Ne capte JAMAIS les taps
                    // plus bas dans le texte (mots/versets gardent leurs
                    // propres gestes, cf. onWordTap plus bas).
                    // POIGNÉE DE RAPPEL DU MENU (2026-08-05, corrigée le
                    // jour même). Elle remplace la bande de tap invisible qui
                    // occupait 15 % du haut de l'écran.
                    //
                    // DEUX DÉFAUTS CORRIGÉS D'UN COUP, tous deux signalés par
                    // l'utilisateur sur la première version :
                    //
                    //  1. « le tiret du menu en bas ne s'active pas » — il
                    //     était en `IgnorePointer`, donc purement décoratif :
                    //     il DÉSIGNAIT le menu sans permettre de le rappeler.
                    //     Un repère qu'on ne peut pas toucher invite un geste
                    //     qui ne marche pas ; il est maintenant la cible.
                    //  2. « il entre en concurrence avec le menu du téléphone »
                    //     — collé au bord inférieur, il tombait dans la zone de
                    //     gestes d'Android, qui capte en premier. Il est donc
                    //     remonté de [_kMargeGesteSysteme] AU-DESSUS de
                    //     l'encoche système, hors de portée de ce conflit.
                    //
                    // La zone tapable est volontairement plus large que le
                    // trait (44 x 4 visibles, 120 x 44 tapables) : un repère
                    // fin doit rester fin, mais viser 4 pixels de haut n'est
                    // pas un geste réaliste.
                    if (!_headerVisible)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: MediaQuery.of(context).padding.bottom +
                            _kMargeGesteSysteme,
                        child: Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _showHeader,
                            child: SizedBox(
                              width: 120,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: 44,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    // Le vert foncé à 59 % d'opacité tient sur
                                    // le fond crème et sur le sépia du mode
                                    // Kindle, mais devient INVISIBLE sur le
                                    // fond noir (`sombreBg` = #0B0B0B) --
                                    // constat utilisateur 2026-08-09. En mode
                                    // sombre on passe donc à l'or du thème
                                    // (`sombreAccent`), et à pleine opacité :
                                    // ce repère est le SEUL moyen de faire
                                    // revenir l'entête une fois masqué, un
                                    // repère qu'on ne voit pas est un écran
                                    // sans issue.
                                    color: modeSombre
                                        ? AppColors.sombreAccent
                                        : AppColors.green800.withAlpha(150),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Bouton retour TOUJOURS visible, independant du header --
                    // retour utilisateur 2026-07-19 ("comment revenir sur
                    // ecran principal ?") : le header masque etait la SEULE
                    // facon de revenir en arriere, fragile (il faut se
                    // souvenir de taper la zone haute). Petit, discret,
                    // jamais cache par le minuteur.
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SafeArea(
                        child: Material(
                          // OPAQUE (2026-08-05) : semi-transparent, le mot
                          // coranique juste en dessous transparaissait a
                          // travers le bouton -- signale par l'utilisateur sur
                          // capture (verset 66, mot visible dans le rond vert).
                          //
                          // ── ARBITRAGE INVERSE (2026-08-07) ──────────────
                          // « Je veux que le retour arriere soit plus
                          // transparent, il cache du texte. » L'opacite reglait
                          // un defaut de LISIBILITE DU BOUTON ; elle en creait
                          // un de LISIBILITE DU TEXTE, qui prime -- c'est un
                          // Mushaf, le texte passe avant le chrome.
                          // Compromis retenu : nettement translucide (alpha
                          // 110) mais pose sur un fond sombre, donc l'icone
                          // creme reste lisible. En mode nuit on l'accorde au
                          // fond noir plutot qu'au vert du theme clair.
                          color: (modeSombre
                                  ? AppColors.sombreBgDeep
                                  : AppColors.green900)
                              .withAlpha(110),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: AppColors.cream),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ),
                    ),
                    // Le header lui-même, hauteur fixe, qui glisse hors écran
                    // (translation -- ne touche pas à ses contraintes de
                    // layout internes, donc pas de risque de rognage/overflow
                    // du contenu). Pas de tap-pour-masquer sur le header
                    // lui-même : il contient un IconButton (retour) et
                    // superposer un GestureDetector.onTap risquerait de
                    // capter la même zone que ce bouton -- masquage laissé au
                    // minuteur automatique (4s), plus sûr.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: _kMushafHeaderHeight,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        offset: _headerVisible ? Offset.zero : const Offset(0, -1),
                        child: MushafHeader(
                          modeSombre: modeSombre,
                          surah: widget.surah,
                          onBack: () => Navigator.of(context).maybePop(),
                          onMindMap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MindMapScreen(surah: widget.surah),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Mini-lecteur retiré (retour utilisateur 2026-07-19 : "le
                    // bandeau de lecture n'est pas interessant") -- doublait
                    // le bouton Lire/Pause de _BottomBar juste en dessous ; le
                    // verset en cours de lecture reste visible par son
                    // surlignage dans le texte (VerseTile), pas besoin d'une
                    // 2e barre pour ça.
                    //
                    // Barre du bas -- ex-`Scaffold.bottomNavigationBar`,
                    // déplacée ici le 2026-08-01 pour suivre la même
                    // visibilité que le header (`_headerVisible`) : plein
                    // écran "vraiment" veut dire que CE chrome disparaît
                    // aussi, pas seulement le header du haut (demande
                    // utilisateur explicite, l'ancienne version le gardait
                    // "toujours visible" par choix -- 2026-07-19 -- mais ça
                    // empêchait un vrai plein écran).
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        offset: _headerVisible ? Offset.zero : const Offset(0, 1),
                        child: SafeArea(
                          top: false,
                          child: _BottomBar(
                            modeSombre: modeSombre,
                            onPlayTap: _verses.isEmpty ? null : _onPlayTap,
                            onMicTap: _verses.isEmpty ? null : _openMemorization,
                            onMicLongPress: _verses.isEmpty ? null : _openKaraoke,
                            onMicDoubleTap:
                                _verses.isEmpty ? null : _openContinuousRecitation,
                            onReciteTap: _verses.isEmpty ? null : _openKaraoke,
                            onChainTap:
                                _verses.isEmpty ? null : _openJeuMemorisation,
                            onMoreTap: _openReadingSettings,
                            onBookmarkTap:
                                _verses.isEmpty ? null : _basculerMarquePage,
                            onBookmarkLongPress: _ouvrirListeSignets,
                            estMarque: _verses.isEmpty
                                ? false
                                : ref.watch(marquePagesProvider).contains(
                                      MarquePagesNotifier.cle(
                                        _verses[_activeVerse].surahNumber,
                                        _verses[_activeVerse].ayahNumber,
                                      ),
                                    ),
                            isPlaying: playerState.isPlaying,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  // Mode Kindle (demande utilisateur 2026-08-01, dernière version) : après
  // deux échecs d'un système de PAGES séparé (seuil de mots -- sautait du
  // contenu ; découpage par pixel puis par mot -- corrects mais jamais aussi
  // simples/robustes que l'existant), retour à la proposition de l'utilisateur
  // : garder le défilement continu tel quel (déjà stable, remplit tout
  // l'écran nativement, aucun système de pagination à maintenir), et ne
  // simuler la "page" qu'au moment du tap -- un saut de scroll animé d'une
  // hauteur d'écran ("un défilement éclair pour que le texte monte d'un
  // coup"). Zéro nouveau calcul de mise en page.
  void _kindleJumpPage(double viewportHeight, {required bool forward}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final target =
        (pos.pixels + (forward ? viewportHeight : -viewportHeight)).clamp(0.0, pos.maxScrollExtent);
    _scrollController.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _syncKindleAutoTurn(bool enabled, double seconds) {
    _kindleAutoTurnTimer?.cancel();
    if (!enabled) {
      _calibrationEnCours = false;
      return;
    }
    // Tant que la cadence n'a pas ete MESUREE entre deux taps, rien ne tourne.
    if (_calibrationEnCours) {
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'tournage automatique EN ATTENTE : la cadence sera mesuree entre '
          'vos deux prochains taps, rien ne tourne d\'ici la');
      return;
    }
    _debutPage = DateTime.now();
    _kindleAutoTurnTimer = Timer.periodic(Duration(seconds: seconds.round()),
        (_) => _tournerAutomatiquement(seconds));
  }

  // ── LE DEFILEMENT MANUEL COMPTE AUTANT QUE LE TAP (2026-08-07) ──────────
  //
  // Specification utilisateur : « quand je touche l'ecran, si je descends, ca
  // impacte le delai et il doit se remettre a zero. Exemple : delai de 20 s,
  // ca tourne a 20 s, je n'ai pas fini, je glisse en bas pour finir -- donc
  // toute la page je ne l'ai pas encore lue -- le nouveau delai doit
  // recommencer. Alors que si je finis avant, le clic pour tourner la page :
  // le temps doit diminuer, mais repartir de zero. On ne va pas traiter le
  // scroll pour afficher plus. »
  //
  // TROIS REGLES, ET UNE SEULE MESURE.
  //  1. TOUT geste de l'utilisateur remet le chronometre a zero. Il est en
  //     train de lire : la page ne doit pas tourner sous ses yeux parce qu'un
  //     minuteur lance avant son geste arrive a echeance.
  //  2. Un defilement EN ARRIERE dit « ca a tourne trop tot, je n'avais pas
  //     fini » -- exactement ce que dit le tap arriere. Le delai s'allonge.
  //  3. Un defilement EN AVANT ne dit RIEN sur la cadence : le lecteur va
  //     simplement voir la suite. On remet le chronometre a zero, on n'apprend
  //     pas. (« on ne va pas traiter le scroll pour afficher plus »)
  //
  // POURQUOI CE N'ETAIT PAS COUVERT : le minuteur est un `Timer.periodic`
  // arme une fois pour toutes. Il ne connaissait que le tap (`_tapManuel` le
  // rearme) ; pendant qu'on faisait defiler a la main, il continuait de
  // courir et pouvait tourner la page en pleine lecture.
  //
  // ⚠️ NE PAS APPRENDRE DU DEFILEMENT PROGRAMME. `_kindleJumpPage` utilise
  // `animateTo`, qui emet les memes notifications qu'un doigt. Seule la
  // presence de `dragDetails` distingue un vrai geste -- sans ce test, chaque
  // tournage automatique se prendrait pour un geste du lecteur et
  // s'auto-confirmerait en boucle, le defaut meme que `_tapManuel` evite.
  double? _pixelsDebutGeste;

  /// Le tournage automatique attend-il d'etre CALIBRE par deux taps ?
  ///
  /// ── LE DELAI SE MESURE, IL NE SE SUPPOSE PLUS (2026-08-07) ──────────────
  ///
  /// Demande utilisateur : « je veux que le declenchement du delai automatique
  /// se fasse en mesurant le delai entre deux taps, pour la premiere fois ».
  ///
  /// CE QUI SE PASSAIT AVANT, et que le journal a montre : activer le mode
  /// armait le minuteur sur la valeur STOCKEE (30 s au depart, ou ce qui
  /// restait d'une lecture precedente). La page tournait donc sur une cadence
  /// qui n'etait pas celle du jour, le lecteur revenait en arriere, et le
  /// delai ne faisait plus que grimper -- mesure du 15:49-15:51 : 12,5 -> 13,5
  /// -> 14,7 -> 16,0 -> 17,4 s, cinq retours arriere, et PAS UN SEUL tap avant
  /// pour le faire redescendre.
  ///
  /// Maintenant : a l'activation, aucun minuteur. Le premier tap n'apprend
  /// rien (il n'y a pas encore d'intervalle), le second donne la cadence, et
  /// c'est SEULEMENT la que le tournage automatique demarre. On ne suppose
  /// plus, on mesure.
  ///
  /// EFFET DE BORD VOULU : cela regle aussi le defaut de la reouverture
  /// d'ecran (le chronometre partait a l'ouverture, donc « depuis que l'ecran
  /// est pret » et non « depuis que la lecture a commence »).
  bool _calibrationEnCours = false;

  bool _surDefilement(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      if (n.dragDetails == null) return false; // defilement programme
      _pixelsDebutGeste = n.metrics.pixels;
      return false;
    }
    if (n is ScrollEndNotification && _pixelsDebutGeste != null) {
      final depart = _pixelsDebutGeste!;
      _pixelsDebutGeste = null;
      final delta = n.metrics.pixels - depart;
      // Un micro-mouvement n'est pas une intention de lecture.
      if (delta.abs() < 8) return false;
      final debut = _debutPage;
      // Regle 2 : revenu en arriere -> la page avait tourne trop tot.
      // ⚠️ SEULEMENT apres un tournage AUTOMATIQUE (cf.
      // `_dernierTournageAutomatique`) : revenir sur ses pas apres avoir
      // tourne soi-meme ne dit rien du delai automatique.
      if (delta < 0 && debut != null && _dernierTournageAutomatique) {
        final ecoule =
            DateTime.now().difference(debut).inMilliseconds / 1000.0;
        ref
            .read(kindlePageSecondsProvider.notifier)
            .apprendre(ecoule, enAvant: false);
      }
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'defilement manuel ${delta < 0 ? "ARRIERE" : "avant"} '
          '(${delta.abs().toStringAsFixed(0)} px) -- chronometre remis a zero'
          // Ne PAS annoncer un allongement que le filtre `< 1 s` a pu
          // refuser : la ligne disait « delai allonge » alors que rien
          // n'avait bouge (constate dans le journal du 15:49).
          '${delta < 0 ? ", retour arriere signale" : ", rien appris"}');
      // ── DEUX HORLOGES, PAS UNE (corrige 2026-08-07) ────────────────────
      //
      // `_debutPage` servait A LA FOIS de base de MESURE (« depuis quand
      // cette page est affichee ») et de REPORT du minuteur (« il vient de
      // bouger, ne tourne pas maintenant »). Tout defilement la remettait a
      // zero -- donc lire une page en faisant glisser une fois pour en voir
      // le bas ne mesurait QUE le temps depuis ce glissement. La cadence
      // apprise etait systematiquement PLUS COURTE que la realite, ce qui
      // faisait tourner trop tot, ce qui provoquait un retour arriere, ce qui
      // rallongeait le delai... la boucle observee dans le journal.
      //
      // Desormais : le defilement REPOUSSE le minuteur (il lit, on ne tourne
      // pas) mais ne touche PAS a `_debutPage`. Seul un tournage de page
      // remet l'horloge de mesure a zero, ce qui est sa definition meme.
      _reporterMinuteur();
    }
    return false;
  }

  /// Le dernier tournage de page a-t-il ete AUTOMATIQUE ?
  ///
  /// Le signal « trop tot » (retour en arriere) n'a de sens que dans ce cas :
  /// si c'est le LECTEUR qui a tourne puis qui revient, le delai automatique
  /// n'y est pour rien. Mesure du 2026-08-07 qui l'impose :
  ///     15:56:27  tap avant            <- il tourne LUI-MEME
  ///     15:56:32  EN ARRIERE apres 5.5s : 17.4 -> 18.9
  /// Le delai automatique a ete allonge a cause d'un geste manuel.
  bool _dernierTournageAutomatique = false;

  /// Instant d'arrivée sur la page courante — base de l'apprentissage de la
  /// cadence, cf. [KindlePageSecondsNotifier.apprendre].
  DateTime? _debutPage;

  /// Le lecteur a tourné la page LUI-MÊME : c'est lui qui donne la cadence.
  ///
  /// C'est le seul endroit d'où l'estimation apprend. Un tournage automatique
  /// n'apprend rien — il exécute ce qui a déjà été appris, et s'en servir
  /// reviendrait à confirmer sa propre estimation en boucle.
  void _tapManuel({required bool enAvant}) {
    final debut = _debutPage;
    _debutPage = DateTime.now();
    // Le lecteur a tourne LUI-MEME : un retour arriere qui suivrait ne dira
    // rien du delai automatique (cf. `_dernierTournageAutomatique`).
    _dernierTournageAutomatique = false;
    if (debut == null) {
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'tap ${enAvant ? "avant" : "arriere"} -- aucun debut de page connu, '
          'rien appris (premier geste de la session)');
      return;
    }
    // ── ON APPREND TOUJOURS, MÊME TOURNAGE AUTOMATIQUE ÉTEINT ────────────
    //
    // Demande utilisateur (2026-08-06) : « que la durée du défilement s'adapte
    // au clic ; si après un défilement j'ai cliqué après un certain temps, il
    // ajuste ; et également au sens — est-ce que je recule ou j'avance ».
    //
    // Le mécanisme existait déjà (cf. `KindlePageSecondsNotifier.apprendre` :
    // en avant on prend le temps réel, en arrière on rallonge d'un quart car
    // reculer ne dit pas le bon temps mais seulement qu'il était trop court,
    // et un geste sous la seconde est ignoré). Il était seulement BRIDÉ par
    // `!kindleAutoTurnProvider` : il n'apprenait que si le tournage
    // automatique tournait déjà.
    //
    // C'est l'inverse de ce qu'il faut : ce sont les taps MANUELS qui portent
    // la cadence de lecture, et c'est d'eux qu'il faut apprendre -- pour que
    // le jour où l'utilisateur active le tournage automatique, il soit déjà
    // à son rythme au lieu de partir d'une valeur par défaut.
    final ecoule = DateTime.now().difference(debut).inMilliseconds / 1000.0;
    ref.read(kindlePageSecondsProvider.notifier)
        .apprendre(ecoule, enAvant: enAvant);
    // Deuxieme tap : la cadence est mesuree, le tournage peut demarrer.
    if (_calibrationEnCours && enAvant && ecoule >= 1.0) {
      _calibrationEnCours = false;
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'calibration TERMINEE : ${ecoule.toStringAsFixed(1)}s mesurees entre '
          'deux taps -- le tournage automatique demarre');
    }
    // Le réarmement, lui, n'a de sens que si le minuteur tourne : sans lui la
    // valeur apprise n'aurait d'effet qu'à la prochaine activation.
    if (ref.read(kindleAutoTurnProvider)) {
      _syncKindleAutoTurn(true, ref.read(kindlePageSecondsProvider));
    }
  }

  Widget _buildVerses(String? playingVerseKey,
      {bool kindleMode = false, bool modeSombre = false}) {
    final textScale = ref.watch(textScaleProvider);
    final showLoadingFooter = _loadingMore;
    final size = MediaQuery.of(context).size;
    final viewportHeight =
        size.height - _reserveHaut(context) - _reserveBas();
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _surDefilement,
          child: ListView.builder(
          controller: _scrollController,
          // top = hauteur du header -- il n'est plus un appBar de Scaffold qui
          // réserve automatiquement cet espace (c'est maintenant un overlay
          // flottant, §3 plein écran), donc le contenu doit commencer en
          // dessous explicitement pour ne pas apparaître caché dessous.
          // ⚠️ 2026-08-01 : cette réserve doit suivre `_headerVisible`, sinon
          // le plein écran masque le chrome sans jamais rendre l'espace
          // libéré au contenu (signalé par l'utilisateur : "ne tient pas des
          // zones qui deviennent disponibles après la disparition du menu").
          padding: EdgeInsets.only(
            top: _reserveHaut(context),
            bottom: _reserveBas(),
          ),
          itemCount: _items.length + (showLoadingFooter ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.green800),
                ),
              );
            }
            return _buildEntry(_items[i], playingVerseKey, textScale,
                kindleMode: kindleMode, modeSombre: modeSombre);
          },
        ),
        // ── LE CHANGEMENT DE PAGE N'APPARTIENT PAS AU MODE KINDLE ────────
        //
        // Demande utilisateur (2026-08-06) : « la gestion du defilement dans
        // le Mushaf n'est pas liee a l'option Kindle ; Kindle c'est la
        // COULEUR, mais la gestion du changement de page doit etre presente
        // aussi dans l'autre mode ».
        //
        // Ces deux zones de tap etaient posees `if (kindleMode)`. Le mode
        // Kindle n'est pourtant qu'un THEME -- fond `kindleBg` et trame
        // retiree (cf. `backgroundColor` et `QuranPatternBackground`). Lier la
        // navigation a un choix de couleur obligeait a passer en Kindle pour
        // tourner les pages, et faisait perdre la navigation a qui prefere le
        // theme creme.
        //
        // Elles sont donc TOUJOURS presentes. Le mode Kindle ne change plus
        // que l'apparence, et le tourne-page automatique
        // (`_syncKindleAutoTurn`) reste pilote par son propre reglage.
        // ── LES BANDES SONT DECALEES DU BORD (2026-08-06) ────────────────
        //
        // Defaut signale : « je peux avancer en bas mais je n'arrive pas a
        // reculer en arriere ». Une seule chose distingue les deux cotes : le
        // bord GAUCHE est la zone du geste systeme « retour » d'Android, qui
        // capte ce qui s'y passe avant l'application. Le fichier connaissait
        // deja le probleme -- `_kMargeGesteSysteme` est utilisee pour le
        // bouton du bas -- mais pas sur les cotes.
        //
        // Les deux bandes sont donc decalees de cette marge et elargies. On
        // les garde SYMETRIQUES : si le defaut venait d'ailleurs, une
        // asymetrie de code aurait rendu le diagnostic impossible.
        ),
        Positioned(
          left: _kMargeGesteSysteme,
          top: _reserveHaut(context),
          bottom: 0,
          width: 64,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _tapManuel(enAvant: false);
              _kindleJumpPage(viewportHeight, forward: false);
            },
          ),
        ),
        Positioned(
          right: _kMargeGesteSysteme,
          top: _reserveHaut(context),
          bottom: 0,
          width: 64,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _tapManuel(enAvant: true);
              _kindleJumpPage(viewportHeight, forward: true);
            },
          ),
        ),
      ],
    );
  }

  // Extrait du switch de `_buildVerses` (jusqu'au 2026-08-01, dupliqué en
  // dur dans l'itemBuilder) -- réutilisé tel quel par le mode Kindle
  // paginé (§ _buildKindlePages) pour ne PAS réimplémenter le rendu d'un
  // verset/bannière une 2e fois dans un langage légèrement différent.
  Widget _buildEntry(_ListEntry entry, String? playingVerseKey, double textScale,
      {bool kindleMode = false,
      bool modeSombre = false,
      int? wordStart,
      int? wordEnd}) {
    switch (entry.kind) {
      case _EntryKind.bismillah:
        return _BismillahBanner(
            text: entry.bismillah!.textUthmani,
            // `kindleMode` était disponible ici mais n'était pas transmis :
            // le bandeau ne connaissait que le mode sombre, donc en mode
            // Kindle il retombait sur la palette du thème CLAIR (dégradé
            // vert, bordure green100, encre green800) posée sur un fond
            // sépia. Constat utilisateur 2026-08-09.
            kindleMode: kindleMode,
            modeSombre: modeSombre);
      case _EntryKind.surahBanner:
        return _SurahBanner(surah: entry.surah!, modeSombre: modeSombre);
      case _EntryKind.verse:
        final idx = entry.verseIndex!;
        final verse = _verses[idx];
        return VerseTile(
          // En mode Kindle un même verset peut être rendu en DEUX morceaux
          // (page N et page N+1) potentiellement montés en même temps
          // (PageView garde la page voisine en mémoire) -- réutiliser la
          // même GlobalKey partagée (`_verseKeys`, utilisée par le scroll
          // continu pour Scrollable.ensureVisible) ferait planter l'app
          // (« Duplicate GlobalKey »). Pas de clé stable nécessaire ici,
          // le mode Kindle ne fait pas défiler jusqu'à un verset.
          key: kindleMode ? null : _verseKeys[idx],
          verse: verse,
          isActive: _activeVerse == idx,
          isPlayingCursor: playingVerseKey != null && verse.key == playingVerseKey,
          showTranslation: _showTranslation,
          textScale: textScale,
          kindleMode: kindleMode,
          modeSombre: modeSombre,
          wordStart: wordStart,
          wordEnd: wordEnd,
          onTap: () => setState(() => _activeVerse = idx),
          onLongPress: () => _menuVerset(idx),
          // ── EXPLICATION PAR MOT RETIRÉE (2026-08-09, demande utilisateur)
          //
          // « j'enlève les explications des mots Coran, ce sera à faire
          // après ». `_openWordExplanation` (cf. plus haut) reste intacte --
          // seul ce branchement disparaît, pour la rebrancher proprement
          // plus tard. Historique du geste avant ce retrait : tap simple
          // (2026-07-10), passé en appui long (2026-08-07) pour ne plus
          // concurrencer le changement de page en mode lecture.
          //
          // `onWordTap`/`onWordLongPress` non fournis : sans eux, le texte
          // ne pose aucun détecteur sur les mots, et le geste redescend
          // intact au parent (`onLongPress` ci-dessus, menu du verset).
        );
    }
  }


  // Bouton Lire/Pause de la barre du bas : son icône bascule selon
  // `isPlaying`, mais AVANT ce correctif il appelait toujours `_playFromActive`
  // -- donc un 2e tap pendant la lecture relançait `play()` (position remise à
  // zéro) au lieu de mettre en pause. Symptôme utilisateur : "je fais pause,
  // il recommence" (2026-08-01). On ne bascule pause/resume QUE si le verset
  // actif est déjà celui chargé dans le player -- changer de verset doit
  // continuer à (re)lancer une lecture depuis le début, pas reprendre l'ancien.
  // `playerProvider` est un état GLOBAL (un seul lecteur pour toute l'app,
  // pas par écran) -- donc "isPlaying" seul ne suffit pas à décider quoi
  // faire : si la sourate A joue encore et qu'on ouvre la sourate B, taper
  // "Lire" doit lancer B, pas mettre A en pause. Sans la comparaison de
  // verset, un tap sur B est interprété comme une pause de A (bug constaté
  // 2026-08-01 : "je change de sourate, je fais play, ça reste sur la
  // première" -- la 1ère). Donc : pause/resume SEULEMENT si le verset actif
  // de CET écran est déjà celui réellement chargé dans le lecteur ; sinon on
  // (re)lance toujours depuis le début sur le nouveau verset/sourate.
  // ── CE QUE LE BOUTON MONTRE, LE BOUTON DOIT LE FAIRE (2026-08-13) ────────
  //
  // Constat utilisateur : « après le play je clique sur pause, la lecture se
  // refait, et au deuxième clic il y a la pause ».
  //
  // Cause : l'icône vient de `playerState.isPlaying` -- l'état GLOBAL du
  // lecteur -- alors que la décision ci-dessous exigeait que le verset joué
  // soit exactement `_activeVerse`. Or la lecture enchaîne toute seule sur le
  // verset suivant : dès le premier enchaînement les deux divergent, le tap
  // tombait dans le `else` et RELANÇAIT depuis le verset actif. Le deuxième
  // tap, lui, retrouvait l'égalité et mettait bien en pause.
  //
  // Le bon discriminant n'est pas « le même verset » mais « le même
  // PASSAGE » : ce qui joue appartient-il à ce que cet écran affiche ?
  //   - oui  -> le bouton est une commande de transport : pause / reprise ;
  //   - non  -> c'est un autre passage (autre sourate, autre écran), on lance
  //             ici, ce qui préserve le correctif du 2026-08-01 (« je change
  //             de sourate, je fais play, ça reste sur la première »).
  void _onPlayTap() {
    if (_verses.isEmpty) return;
    final player = ref.read(playerProvider);
    final cle = player.currentVerse?.key;
    final dansCeQuiEstAffiche =
        cle != null && _verses.any((v) => v.key == cle);
    // Le menu doit etre visible des qu'on touche au transport, et le rester
    // tant que ca joue (cf. `_scheduleHeaderHide`).
    _showHeader();
    if (dansCeQuiEstAffiche && player.isPlaying) {
      ref.read(playerProvider.notifier).pause();
    } else if (dansCeQuiEstAffiche && player.isPaused) {
      ref.read(playerProvider.notifier).resume();
    } else {
      _playFromActive();
    }
  }

  void _playFromActive() {
    if (_verses.isEmpty) return;
    _playVerse(_verses[_activeVerse]);
  }

  void _playVerse(Verse verse) {
    ref.read(playerProvider.notifier).play(verse, _verses);
  }

  // Fait défiler la liste jusqu'au verset dont la clé est passée. Durée de
  // l'animation calée sur la vitesse de lecture (demande utilisateur
  // 2026-07-06) : à 1.25×/1.5× le scroll doit suivre plus vite, pas traîner
  // derrière l'audio ; bornée pour rester lisible aux vitesses extrêmes.
  void _scrollToVerseKey(String key, double speed) {
    final idx = _verses.indexWhere((v) => v.key == key);
    if (idx < 0 || idx >= _verseKeys.length) return;
    final ms = (400 / speed).round().clamp(150, 600);
    _scrollToIndex(idx, Duration(milliseconds: ms));
  }

  // ListView.builder ne construit que les items proches de l'écran : si le
  // verset ciblé est loin (lecture qui saute plusieurs versets, ou liste
  // scrollée manuellement ailleurs), son GlobalKey n'a pas encore de
  // BuildContext. On saute d'abord vers une position estimée pour forcer sa
  // construction, puis on affine avec ensureVisible une fois le vrai
  // BuildContext disponible (quelques frames suffisent).
  void _scrollToIndex(int idx, Duration duration, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _verseKeys[idx].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: duration,
          curve: Curves.easeInOut,
        );
        return;
      }
      if (attempt >= 4 || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final estimate = (idx / _verses.length) * pos.maxScrollExtent;
      _scrollController.jumpTo(estimate.clamp(0.0, pos.maxScrollExtent));
      _scrollToIndex(idx, duration, attempt: attempt + 1);
    });
  }

  /// Marque ou démarque le verset actif (2026-08-05).
  ///
  /// Le retour visuel est IMMÉDIAT et nomme le verset : sans lui, marquer et
  /// démarquer produiraient exactement la même absence de réaction, et on ne
  /// saurait jamais dans quel sens le geste a joué.
  Future<void> _basculerMarquePage() async {
    if (_verses.isEmpty) return;
    final v = _verses[_activeVerse];
    final ajoute = await ref
        .read(marquePagesProvider.notifier)
        .basculer(v.surahNumber, v.ayahNumber);
    if (!mounted) return;
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.green900,
        content: Text(
          '${ajoute ? t.mushafBookmarkAdded : t.mushafBookmarkRemoved}'
          '  ${v.surahNumber}:${v.ayahNumber}',
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.cream),
        ),
      ));
  }

  void _openMemorization() {
    final verse = _verses[_activeVerse];
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CoachScreen(verses: [verse])));
  }

  /// Appui long sur un verset : « à partir d'ici » (demande utilisateur
  /// 2026-08-05 — « une petite fenêtre qui s'affiche pour démarrer la
  /// récitation à partir de là où on a commencé, le jeu à partir de là »).
  ///
  /// LE VERSET DEVIENT ACTIF AVANT D'OUVRIR LE MENU, et ce n'est pas un détail
  /// d'implémentation : `_openKaraoke` et `_openMemorization` partent tous deux
  /// de `_activeVerse`. Sans cette ligne, un appui long sur le verset 40
  /// lancerait la récitation au verset actif précédent — l'action ne
  /// correspondrait pas au verset touché, et le geste mentirait.
  /// Liste des signets, avec acces direct a chacun.
  ///
  /// Demande utilisateur (2026-08-06) : « tu as ajouté favoris dans le Mushaf
  /// [...] mais le problème, il n'y a pas d'accès direct pour y aller après ».
  /// Un signet qu'on ne peut pas rouvrir n'est pas un signet.
  ///
  /// Le saut se fait par `initialAyahNumber`, le meme chemin que le « Shazam
  /// coranique » (2026-07-18) -- pas un second mecanisme de navigation.
  Future<void> _ouvrirListeSignets() async {
    final t = AppLocalizations.of(context)!;
    final cles = ref.read(marquePagesProvider).toList()
      ..sort((a, b) {
        final pa = a.split(':').map(int.parse).toList();
        final pb = b.split(':').map(int.parse).toList();
        return pa[0] != pb[0] ? pa[0].compareTo(pb[0]) : pa[1].compareTo(pb[1]);
      });
    List<Surah> sourates = const [];
    try {
      sourates = await QuranApi.fetchSurahs();
    } catch (_) {
      // Best-effort : sans les metadonnees on affiche quand meme la reference
      // numerique plutot que rien.
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.mushafBookmarksTitle,
                  style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 10),
              if (cles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(t.mushafNoBookmarks,
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.inkLight)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: cles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = cles[i].split(':').map(int.parse).toList();
                      final s = sourates.where((x) => x.number == p[0]);
                      final nom = s.isEmpty ? 'Sourate ${p[0]}' : s.first.nameSimple;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bookmark_rounded,
                            color: AppColors.brass),
                        title: Text(nom,
                            style: GoogleFonts.manrope(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        subtitle: Text('${p[0]}:${p[1]}',
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppColors.inkLight)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.inkLight),
                        onTap: s.isEmpty
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => MushafScreen(
                                      surah: s.first,
                                      initialAyahNumber: p[1]),
                                ));
                              },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu du verset (appui long) : une BULLE compacte a trois choix.
  ///
  /// Demande utilisateur (2026-08-06) : « je la veux dans le style du menu,
  /// une bulle qui propose les trois choix ». La feuille precedente occupait
  /// toute la largeur avec des `ListTile` a sous-titres repetes (« A partir de
  /// ce verset » trois fois) : beaucoup de surface pour trois actions courtes.
  ///
  /// LE VERSET DEVIENT ACTIF AVANT D'OUVRIR, et ce n'est pas un detail :
  /// `_openKaraoke`, `_openMemorization` et `_openJeuMemorisation` partent tous
  /// de `_activeVerse`. Sans cette ligne, un appui long sur le verset 40
  /// lancerait l'action sur le verset actif precedent -- le geste mentirait.
  void _menuVerset(int index) {
    setState(() => _activeVerse = index);
    final t = AppLocalizations.of(context)!;
    final verse = _verses[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.green900.withAlpha(60),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Row(
                    children: [
                      Text(
                        '${verse.surahNumber}:${verse.ayahNumber}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppColors.inkLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // « A partir de ce verset » vaut pour les trois : il se
                      // dit une fois, pas sur chaque ligne.
                      Expanded(
                        child: Text(t.mushafFromHere,
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppColors.inkLight)),
                      ),
                    ],
                  ),
                ),
                _ActionVerset(
                  icone: Icons.mic_rounded,
                  libelle: t.mushafRecite,
                  onTap: () { Navigator.pop(ctx); _openKaraoke(); },
                ),
                _ActionVerset(
                  icone: Icons.school_rounded,
                  libelle: t.mushafMemorize,
                  onTap: () { Navigator.pop(ctx); _openMemorization(); },
                ),
                // TROISIEME CHOIX (2026-08-06) : le jeu de memorisation
                // n'etait atteignable que depuis le hub Coach et la barre de
                // l'ecran de recitation -- jamais depuis le TEXTE, qui est
                // pourtant l'endroit ou on decide de travailler un verset.
                _ActionVerset(
                  icone: Icons.videogame_asset_rounded,
                  libelle: t.memorizationGameTitle,
                  onTap: () { Navigator.pop(ctx); _openJeuMemorisation(); },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Jeu de memorisation a partir du verset actif (demande utilisateur
  /// 2026-08-06). Meme ecran que le hub Coach et la barre de recitation --
  /// un seul jeu, trois portes d'entree.
  ///
  /// BUG CORRIGE (2026-08-07) : cette porte d'entree passait `verses:
  /// [verse]`, un SEUL verset -- la partie s'arretait donc immediatement
  /// apres lui, contrairement aux deux autres portes d'entree
  /// (`karaoke_recitation_screen.dart:_openMemorizationGame`,
  /// `coach_hub_screen.dart`) qui demarrent sur toute la PAGE du Mushaf a
  /// partir du verset choisi. Meme regle reprise ici : la partie est de
  /// toute facon illimitee desormais (le notifier charge la page suivante
  /// tout seul, cf. `memorization_game_provider.dart`), donc ce depart ne
  /// fixe plus qu'un POINT DE DEPART, pas une borne.
  void _openJeuMemorisation() {
    final verse = _verses[_activeVerse];
    final page = verse.pageNumber;
    final pageVerses = page == null
        ? [verse]
        : _verses
            .where((v) => v.pageNumber == page && v.ayahNumber >= verse.ayahNumber)
            .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemorizationGameScreen(
          surah: _surahForNumber(verse.surahNumber),
          verses: pageVerses,
        ),
      ),
    );
  }

  /// Appui long sur le micro : mode karaoké (récitation continue immersive,
  /// expérience cible) depuis le verset actif. La suite est chargée PAGE PAR
  /// PAGE par l'écran lui-même (cf. `_maybeExtendNextPage`), à l'approche de
  /// la fin -- l'enchaînement reste donc illimité, y compris sur la sourate
  /// suivante.
  ///
  /// Bug corrigé 2026-07-16 : on passait ici `_verses.sublist(_activeVerse)`,
  /// soit TOUTE la fin de la sourate. Sur Al-Baqara ça faisait **6121 mots**
  /// d'un coup (log device : "cible d'alignement : 6121 mots"), là où le
  /// principe retenu est une page à la fois. Effet pervers : l'extension
  /// page par page se cale sur `_verses.last.pageNumber` -- en chargeant tout,
  /// cette dernière page était celle de la FIN de la sourate, donc le
  /// mécanisme ne pouvait jamais servir, et toute la sourate restait tokenisée
  /// et alignée en mémoire pour rien.
  void _openKaraoke() {
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => KaraokeRecitationScreen(verses: _fragmentFromActive())));
  }

  /// Versets du verset actif jusqu'à la fin de SA page (repli : toute la fin de
  /// la sourate si la pagination est inconnue -- `pageNumber` est nullable côté
  /// API).
  List<Verse> _fragmentFromActive() {
    final rest = _verses.sublist(_activeVerse);
    final page = rest.first.pageNumber;
    if (page == null) return rest;
    final sameFirstPage = rest.takeWhile((v) => v.pageNumber == page).toList();
    return sameFirstPage.isEmpty ? rest : sameFirstPage;
  }

  /// Double-tap sur le micro : écran de test/debug (transcript brut visible),
  /// utilisé en interne pour juger la qualité du modèle pendant l'entraînement.
  void _openContinuousRecitation() {
    // Même borne d'une page qu'en karaoké (cf. _fragmentFromActive) : cet écran
    // de debug partageait le bug des 6121 mots chargés d'un coup.
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => RecitationScreen(verses: _fragmentFromActive())));
  }

  // Ancienne entree "Identifier" (Shazam coranique) de cet ecran -- RETIREE
  // (2026-07-19, demande utilisateur) : remontee sur la page principale a
  // cote de "Suivre une priere" (surah_list_screen.dart::_openShazamFromHome),
  // point d'entree plus naturel pour une fonction mains-libres. Voir
  // l'historique git pour l'implementation precedente si besoin (elle
  // sautait directement dans le scroll continu si la sourate etait deja
  // chargee, plutot que de repousser un ecran -- a reprendre si on veut
  // remettre un acces depuis l'ecran de lecture lui-meme).
}

// Marque le passage à la sourate suivante dans le scroll continu (défilement
// infini automatique, demande utilisateur 2026-07-18) -- distincte de la
// Bismillah (qui la suit juste en dessous) pour que le lecteur voie sans
// ambiguïté qu'une nouvelle sourate commence, comme le ferait une page de
// Mushaf papier.
// Bandeau de séparation entre sourates -- ancienne version: simple pilule
// arrondie (couleur unie + nom FR/AR). Remplacé le 2026-07-19 (demande
// utilisateur : "design arabe" façon cartouche de mushaf imprimé, cf. photos
// de référence) par SurahOrnamentHeader (widgets/surah_ornament_header.dart,
// cadre à motifs + étoiles à 8 branches + cartouche calligraphique). Ce
// wrapper garde le nom de classe `_SurahBanner` utilisé plus haut dans ce
// fichier (évite de toucher au switch de l'itemBuilder).
class _SurahBanner extends StatelessWidget {
  final Surah surah;
  /// Le bandeau ornemental est un decor CLAIR. Sur fond noir il forme un pave
  /// blanc au milieu de la page -- constate sur capture (2026-08-07). On le
  /// laisse tel quel mais assombri par un voile, plutot que de reecrire un
  /// second bandeau : l'ornement garde son dessin, il cesse d'eblouir.
  final bool modeSombre;
  const _SurahBanner({required this.surah, this.modeSombre = false});

  @override
  Widget build(BuildContext context) {
    final entete = SurahOrnamentHeader(surah: surah);
    if (!modeSombre) return entete;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.45, 0, 0, 0, 0,
        0, 0.45, 0, 0, 0,
        0, 0, 0.45, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: entete,
    );
  }
}

class _BismillahBanner extends StatelessWidget {
  final String text;
  final bool kindleMode;
  final bool modeSombre;
  const _BismillahBanner(
      {required this.text, this.kindleMode = false, this.modeSombre = false});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          // Même dégradé de vert que le verset en cours de lecture
          // (`VerseTile`) -- demande utilisateur 2026-08-09 : le bandeau de la
          // Bismillah et le surlignage du verset doivent porter le code
          // couleur vert de l'app, en dégradé, pas un aplat.
          // Même résolution de palette que `VerseTile` : sombre > kindle >
          // clair. Le dégradé vert n'appartient qu'au thème clair ; les deux
          // autres modes ont déjà leur teinte de fond et ne doivent pas
          // recevoir un second traitement par-dessus.
          color: modeSombre
              ? AppColors.sombreBgDeep
              : (kindleMode ? AppColors.kindleBgDeep : null),
          gradient: (modeSombre || kindleMode)
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.readingCursorBg,
                    AppColors.readingCursorBgEnd
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: modeSombre
                  ? AppColors.sombreAccent.withAlpha(90)
                  : (kindleMode
                      ? AppColors.kindleAccent.withAlpha(120)
                      : AppColors.green100),
              width: 1),
        ),
        child: Center(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
              fontSize: 24,
              color: modeSombre
                  ? AppColors.sombreInk
                  : (kindleMode ? AppColors.kindleInk : AppColors.green800),
              height: 1.8),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  final VoidCallback? onPlayTap;
  final VoidCallback? onMicTap;
  final VoidCallback? onMicLongPress;
  final VoidCallback? onMicDoubleTap;
  /// Réciter (karaoké) -- icône dédiée (2026-08-09, demande utilisateur :
  /// « où sont Réciter et Jeu dans ce menu principal ? »). Avant cette date,
  /// `_openKaraoke` n'était atteignable que par appui long sur un verset
  /// (bulle `_menuVerset`) -- pas depuis la barre, jugée trop discrète.
  final VoidCallback? onReciteTap;
  /// Enchaînement (ex-"Jeu de mémorisation", renommé le 2026-08-09 -- "Jeu"
  /// jugé hors de l'univers du Coran) -- même raison que [onReciteTap].
  final VoidCallback? onChainTap;
  final VoidCallback? onMoreTap;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onBookmarkLongPress;
  /// Lecture sur fond noir : le vert du theme s'y confond avec la page.
  final bool modeSombre;
  /// Le verset actif est-il marque ? Pilote l'icone du signet.
  final bool estMarque;
  final bool isPlaying;

  const _BottomBar({
    this.onPlayTap, this.onMicTap, this.onMicLongPress, this.onMicDoubleTap,
    this.onReciteTap, this.onChainTap,
    this.onMoreTap,
    this.onBookmarkTap, this.onBookmarkLongPress, this.estMarque = false,
    this.isPlaying = false,
    this.modeSombre = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          // Sur fond noir, le vert fonce du theme se confond avec la page --
          // « le menu cache en mode dark est invisible » (utilisateur,
          // 2026-08-07). On l'eclaircit et on lui donne un liseré : ce n'est
          // pas une couleur de marque ici, c'est un repere qui doit se voir.
          color: modeSombre ? AppColors.sombreBgDeep : AppColors.green800,
          border: modeSombre
              ? Border(
                  top: BorderSide(
                      color: AppColors.sombreAccent.withAlpha(120), width: 1))
              : null,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.green900.withAlpha(120),
              blurRadius: 20, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarButton(
                  icon: isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: isPlaying ? t.mushafPause : t.mushafPlay,
                  color: AppColors.brass,
                  onTap: onPlayTap ?? () {},
                ),
                // SIGNET -- remplace l'etoile « Favoris » (2026-08-05).
                // Celle-ci portait un `onTap: () {}` vide depuis sa creation :
                // rien n'etait casse, la fonction n'avait jamais existe.
                // L'icone REFLETE l'etat du verset actif : un signet qui a la
                // meme apparence marque ou non ne dit rien de ce qu'il a fait.
                _BarButton(
                  icon: estMarque
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  label: t.mushafFavorites,
                  color: estMarque ? AppColors.brass : null,
                  onTap: onBookmarkTap ?? () {},
                  // APPUI LONG = la liste des signets (2026-08-06, demande
                  // utilisateur : « il n'y a pas d'accès direct pour y aller
                  // après »). Poser un signet sans pouvoir y revenir ne sert
                  // a rien. Le tap garde son role -- marquer/demarquer le
                  // verset courant -- et l'appui long ouvre la liste.
                  onLongPress: onBookmarkLongPress,
                ),
                // GROS MICRO DE RÉCITATION RETIRÉ le 2026-07-20 (demande
                // utilisateur : « le micro de récitation mémorisation doit
                // être déplacé dans Coach »). Il portait 3 gestes : tap =
                // mémoriser ce verset, appui long = karaoké continu,
                // double-tap = écran de test interne. La RÉCITATION (karaoké,
                // continu) vit désormais dans le hub Coach, zone « Réciter »,
                // avec tous ses réglages (REFONTE_IHM.md §11.2 zone C).
                // Seul le raccourci « travailler ce verset » restait ici.
                //
                // ── RÉCITER ET ENCHAÎNEMENT REVIENNENT DANS LA BARRE
                // (2026-08-09) ── Demande utilisateur : « où sont Réciter et
                // Jeu dans ce menu principal ? ». Ils n'étaient atteignables
                // que par appui long sur un verset (bulle `_menuVerset`) --
                // pas assez visible. Ne remplace pas la bulle (garde son
                // utilité : agir "à partir de CE verset" précis), s'ajoute à
                // elle comme raccourci depuis la barre principale.
                _BarButton(
                  icon: Icons.mic_rounded,
                  label: t.mushafRecite,
                  onTap: onReciteTap ?? () {},
                ),
                _BarButton(
                  icon: Icons.school_rounded,
                  label: t.mushafMemorize,
                  onTap: onMicTap ?? () {},
                ),
                // ── "JEU" RENOMMÉ "ENCHAÎNEMENT" (2026-08-09) ──────────────
                // Demande utilisateur : « Jeu » ne colle pas à l'univers du
                // Coran. Le mécanisme enchaîne les mots rappelés avec un
                // record de longueur -- `Icons.link_rounded` (chaîne) illustre
                // ça directement plutôt qu'une icône de manette de jeu.
                //
                // Traduction sortie d'ici le même jour (demande utilisateur :
                // « mettre traduction dans les trois points ») -- déplacée
                // dans la feuille "Plus" (`reading_settings_sheet.dart`).
                _BarButton(
                  icon: Icons.link_rounded,
                  label: t.memorizationGameTitle,
                  onTap: onChainTap ?? () {},
                ),
                // "Coach IA" retiré d'ici le 2026-08-10 (constat utilisateur :
                // icône plus utilisée -- le tuteur Gemma qui l'alimentait a
                // été retiré le même jour). Cf. `_openCoachExplanation` dans
                // MushafScreen, conservée pour un rebranchement futur.
                // "Identifier" retire d'ici (2026-07-19) -- remonte sur la
                // page principale a cote de "Suivre une priere" (icones app
                // bar, cf. surah_list_screen.dart), plus l'entree naturelle
                // pour une fonction "mains-libres" qu'un onglet d'ecran de
                // lecture precis.
                _BarButton(icon: Icons.more_horiz_rounded, label: t.mushafMore,
                    onTap: onMoreTap ?? () {}),
              ],
            ),
          ),
        ),
      );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _BarButton({required this.icon, required this.label,
      this.color, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.cream.withAlpha(200);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.manrope(
              fontSize: 10, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.green700),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.commonConnectionRequired,
                style: GoogleFonts.manrope(
                    color: AppColors.inkLight, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry,
                child: Text(AppLocalizations.of(context)!.commonRetry)),
          ],
        ),
      );
}

/// Une action de la bulle du verset : icone + libelle, sur une seule ligne.
class _ActionVerset extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final VoidCallback onTap;
  const _ActionVerset(
      {required this.icone, required this.libelle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Icon(icone, color: AppColors.green800, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(libelle,
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.inkLight, size: 20),
          ],
        ),
      ),
    );
  }
}
