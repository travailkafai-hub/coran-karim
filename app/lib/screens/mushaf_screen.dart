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
      _syncKindleAutoTurn(true, ref.read(kindlePageSecondsProvider));
    }
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
    showReadingSettingsSheet(context, ref);
  }

  // Explique l'aya actuellement sélectionnée (celle sur laquelle l'utilisateur
  // a tapé, _activeVerse — demande utilisateur 2026-07-10 : accès direct au
  // Coach IA depuis la lecture, pas seulement depuis le journal d'erreurs).
  // useErrorLog: false -- lire un verset n'est pas une révision d'erreur,
  // même si ce verset a par ailleurs été raté en récitation ; le registre
  // doit rester "sens du verset", pas "mot que j'ai du mal à retenir"
  // (demande utilisateur 2026-07-10, cette page partait sur la mémorisation).
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
    ref.listen(kindleAutoTurnProvider,
        (_, next) => _syncKindleAutoTurn(next, ref.read(kindlePageSecondsProvider)));
    ref.listen(kindlePageSecondsProvider,
        (_, next) => _syncKindleAutoTurn(ref.read(kindleAutoTurnProvider), next));

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
      backgroundColor: kindleMode ? AppColors.kindleBg : AppColors.cream,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.green800))
          : _error != null
              ? _ErrorView(onRetry: _load)
              : Stack(
                  children: [
                    // Pas de motif décoratif ni de badge de défilement en
                    // mode Kindle -- c'est le thème sobre "repos-yeux" qui
                    // remplace ces éléments, pas un mode qui les empile.
                    if (!kindleMode) const QuranPatternBackground(),
                    _buildVerses(playingVerseKey, kindleMode: kindleMode),
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
                                    color: AppColors.green800.withAlpha(150),
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
                          color: AppColors.green900,
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
                            onPlayTap: _verses.isEmpty ? null : _onPlayTap,
                            onMicTap: _verses.isEmpty ? null : _openMemorization,
                            onMicLongPress: _verses.isEmpty ? null : _openKaraoke,
                            onMicDoubleTap:
                                _verses.isEmpty ? null : _openContinuousRecitation,
                            onTranslationTap: () =>
                                setState(() => _showTranslation = !_showTranslation),
                            onCoachTap: _verses.isEmpty ? null : _openCoachExplanation,
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
                            showTranslation: _showTranslation,
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
    if (!enabled) return;
    _debutPage = DateTime.now();
    _kindleAutoTurnTimer = Timer.periodic(Duration(seconds: seconds.round()), (_) {
      if (!mounted) return;
      // Même formule que le tap manuel (§_buildVerses) -- un `*0.7`
      // approximatif ici aurait fait sauter un peu plus ou moins qu'un
      // vrai "page suivante", décalant l'auto-tournage du tap manuel.
      final size = MediaQuery.of(context).size;
      final viewportHeight =
          size.height - _reserveHaut(context) - _reserveBas();
      _kindleJumpPage(viewportHeight, forward: true);
      // La page a tourné TOUTE SEULE : rien à apprendre, le lecteur n'a rien
      // dit. On remet seulement le chronomètre à zéro pour la page suivante.
      _debutPage = DateTime.now();
    });
  }

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
    if (debut == null) return;
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
    // Le réarmement, lui, n'a de sens que si le minuteur tourne : sans lui la
    // valeur apprise n'aurait d'effet qu'à la prochaine activation.
    if (ref.read(kindleAutoTurnProvider)) {
      _syncKindleAutoTurn(true, ref.read(kindlePageSecondsProvider));
    }
  }

  Widget _buildVerses(String? playingVerseKey, {bool kindleMode = false}) {
    final textScale = ref.watch(textScaleProvider);
    final showLoadingFooter = _loadingMore;
    final size = MediaQuery.of(context).size;
    final viewportHeight =
        size.height - _reserveHaut(context) - _reserveBas();
    return Stack(
      children: [
        ListView.builder(
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
            return _buildEntry(_items[i], playingVerseKey, textScale, kindleMode: kindleMode);
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
      {bool kindleMode = false, int? wordStart, int? wordEnd}) {
    switch (entry.kind) {
      case _EntryKind.bismillah:
        return _BismillahBanner(text: entry.bismillah!.textUthmani);
      case _EntryKind.surahBanner:
        return _SurahBanner(surah: entry.surah!);
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
          wordStart: wordStart,
          wordEnd: wordEnd,
          onTap: () => setState(() => _activeVerse = idx),
          onLongPress: () => _menuVerset(idx),
          // Tap sur un mot précis = l'expliquer (demande utilisateur
          // 2026-07-10), pas le jouer -- la lecture reste accessible via
          // le bouton "Lire" une fois le verset sélectionné.
          onWordTap: (wordIdx) {
            setState(() => _activeVerse = idx);
            _openWordExplanation(verse, wordIdx);
          },
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
  void _onPlayTap() {
    if (_verses.isEmpty) return;
    final player = ref.read(playerProvider);
    final active = _verses[_activeVerse];
    final sameVerse = player.currentVerse?.key == active.key;
    if (sameVerse && player.isPlaying) {
      ref.read(playerProvider.notifier).pause();
    } else if (sameVerse && player.isPaused) {
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

  /// Jeu de memorisation sur le verset actif (demande utilisateur 2026-08-06).
  /// Meme ecran que le hub Coach et la barre de recitation -- un seul jeu,
  /// trois portes d'entree.
  void _openJeuMemorisation() {
    final verse = _verses[_activeVerse];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemorizationGameScreen(
          surah: _surahForNumber(verse.surahNumber),
          verses: [verse],
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
  const _SurahBanner({required this.surah});

  @override
  Widget build(BuildContext context) => SurahOrnamentHeader(surah: surah);
}

class _BismillahBanner extends StatelessWidget {
  final String text;
  const _BismillahBanner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.green50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.green100, width: 1),
        ),
        child: Center(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
              fontSize: 24, color: AppColors.green800, height: 1.8),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  final VoidCallback? onPlayTap;
  final VoidCallback? onMicTap;
  final VoidCallback? onMicLongPress;
  final VoidCallback? onMicDoubleTap;
  final VoidCallback? onTranslationTap;
  final VoidCallback? onCoachTap;
  final VoidCallback? onMoreTap;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onBookmarkLongPress;
  /// Le verset actif est-il marque ? Pilote l'icone du signet.
  final bool estMarque;
  final bool showTranslation;
  final bool isPlaying;

  const _BottomBar({
    this.onPlayTap, this.onMicTap, this.onMicLongPress, this.onMicDoubleTap,
    this.onTranslationTap, this.onCoachTap, this.onMoreTap,
    this.onBookmarkTap, this.onBookmarkLongPress, this.estMarque = false,
    this.showTranslation = false, this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // Pas de traduction disponible en mode 100% arabe (REFONTE_IHM.md §7bis)
    // -- bouton retiré plutôt que laissé inactif.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.green800,
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
                // Seul le raccourci « travailler ce verset » reste ici, en
                // bouton discret ci-dessous (décision verrouillée §11.6.1) :
                // pratique quand on bute sur un verset en lisant, et ce n'est
                // pas une duplication (l'écran de mémorisation reste unique et
                // vit dans Coach, la lecture ne fait qu'y renvoyer).
                _BarButton(
                  icon: Icons.school_rounded,
                  label: t.mushafMemorize,
                  onTap: onMicTap ?? () {},
                ),
                if (!isArabic)
                  _BarButton(
                    icon: showTranslation
                        ? Icons.translate : Icons.translate_outlined,
                    label: t.mushafTranslation,
                    color: showTranslation ? AppColors.brass : null,
                    onTap: onTranslationTap ?? () {},
                  ),
                _BarButton(
                  icon: Icons.psychology_alt_rounded,
                  label: t.mushafCoachAi,
                  onTap: onCoachTap ?? () {},
                ),
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
