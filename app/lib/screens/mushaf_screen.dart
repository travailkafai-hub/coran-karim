import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/player_state_model.dart';
import '../models/riwaya.dart';
import '../providers/app_settings_provider.dart';
import '../providers/mushaf_annotation_provider.dart';
import '../providers/player_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer, recitationVerifierProvider;
import '../theme/app_theme.dart';
import '../widgets/mushaf_page_chrome.dart';
import 'mushaf_maquette_screen.dart';
import '../widgets/verse_tile.dart';
import '../widgets/mushaf_header.dart';
import '../providers/recitation_provider.dart';
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
  /// Delai avant que le menu du Mushaf se replie tout seul.
  ///
  /// 4 s a l'origine, porte a 10 s le 2026-09-02 (« reviens au menu, avec
  /// cette fois 10 s -- ca veut dire qu'il a commence a lire »), puis ramene a
  /// 6 s le 2026-09-03 apres usage : 10 s laissaient le menu trop longtemps
  /// sur la page. C'est le meme raisonnement que la tentative de tap-pour-masquer
  /// (cf. son commentaire dans `build`) : le menu doit s'effacer quand
  /// l'utilisateur LIT, pas quand une temporisation arbitraire expire. Faute
  /// de pouvoir capter le geste, 10 s est le proxy retenu -- assez long pour
  /// chercher son verset, assez court pour rendre le plein ecran a qui lit.
  static const _kHeaderAutoHideDelay = Duration(seconds: 6);
  // ── CETTE CONSTANTE IGNORAIT L'ENCOCHE (2026-09-09) ────────────────────
  //
  // Elle valait 120, comme `MushafHeader.preferredSize`, et les deux
  // ignoraient que le contenu de l'en-tete est dans un `SafeArea` : sur un
  // telephone a encoche il deborde (`BOTTOM OVERFLOWED BY 40 PIXELS`, constate
  // sur capture). La duplication en constante locale evitait d'instancier un
  // widget pour lire sa taille -- elle empechait surtout de tenir compte du
  // `MediaQuery`.
  //
  // On passe donc par `MushafHeader.hauteurPour(context)`, seule source. La
  // constante reste pour les rares endroits sans contexte.
  static const _kMushafHeaderHeight = 120.0;
  static double _hauteurHeader(BuildContext context) =>
      MushafHeader.hauteurPour(context);
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
      ? _hauteurHeader(context) + 8
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
    // Position de lecture (2026-08-26, demande utilisateur : « faut se
    // rappeler de la page et l'ouvrir directement au prochain ouverture de
    // l'application ») -- automatique, sans geste, cf. la doc de
    // `enregistrerPositionLecture` (app_settings_provider.dart).
    unawaited(enregistrerPositionLecture(
        widget.surah.number, widget.initialAyahNumber ?? 1));
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
      // La page suivante vient d'arriver : si l'ecoute tajwid tourne, la chaine
      // doit le savoir, sinon tout mot au-dela de la cible initiale reste hors
      // de portee et plus rien n'est juge -- en silence.
      _etendreEcouteTajwid();
      // Le scroll a atteint cette page : elle devient la nouvelle position de
      // lecture retenue (cf. la doc du provider, même raison qu'à
      // l'ouverture dans `initState`).
      unawaited(enregistrerPositionLecture(
          verses.first.surahNumber, verses.first.ayahNumber));
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

  /// Ouvre la VUE PAGE (mise en page façon mushaf) sur la page courante.
  ///
  /// Aller-retour : on empile un écran, celui-ci reste tel quel derrière. La
  /// vue utilise directement le texte de la riwaya active et l'ajuste dans une
  /// page dessinee par Flutter ; il n'y a plus de variante photo a choisir.
  ///
  /// ⚠️ LIMITE ASSUMÉE : la page d'ouverture est celle du PREMIER verset
  /// chargé, pas du verset réellement sous les yeux -- cet écran n'a pas de
  /// suivi de position de scroll (pas d'`ItemPositionsListener`), donc la
  /// position exacte n'est pas connue ici. En faire une estimation à partir de
  /// l'offset de scroll serait une fausse précision : la hauteur d'un verset
  /// varie du simple au décuple. À reprendre le jour où l'écran expose un
  /// verset visible ; d'ici là, mieux vaut une page juste et un peu en amont
  /// qu'une page fausse.
  /// ── LE LIEN VA MAINTENANT DANS LES DEUX SENS (2026-09-04) ───────────────
  ///
  /// Demande utilisateur : « il faut garder le lien entre le mushaf papier et
  /// le mushaf, comme on peut faire du marquage de page ; il n'y a qu'un seul
  /// sens actuellement ».
  ///
  /// La page partait bien vers le papier (`pageInitiale`) mais rien ne
  /// revenait : on pouvait y feuilleter vingt pages, le retour rendait cette
  /// liste exactement où on l'avait laissée. Deux vues du MÊME texte qui
  /// divergent dès qu'on se sert de l'une -- et la page lue au papier, qui est
  /// justement l'endroit qu'on voulait marquer, était perdue à chaque sortie.
  ///
  /// Le papier rend désormais sa page (cf. son `PopScope`). Deux cas au
  /// retour, et ils n'appellent pas le même geste :
  ///   - la page est DANS la sourate déjà affichée -> on scrolle, la liste est
  ///     déjà chargée, rien à recharger ;
  ///   - la page est dans une AUTRE sourate -> on remplace l'écran par le
  ///     Mushaf de cette sourate, ouvert sur le bon verset. `pushReplacement`
  ///     et non `push` : empiler deux Mushaf ferait revenir sur l'ancienne
  ///     sourate au retour suivant, ce qui est exactement le décalage qu'on
  ///     cherche à supprimer.
  ///
  /// `fetchVersesByPage` est servi depuis l'index déjà en mémoire
  /// (`_versesByPage`, cf. QuranApi) : aucun accès réseau sur ce chemin.
  /// Le premier verset RÉELLEMENT visible à l'écran, ou `null`.
  ///
  /// ── L'ALLER PARTAIT TOUJOURS DU DÉBUT DE LA SOURATE (2026-09-04) ────────
  ///
  /// Constat utilisateur : « la recherche ne se fait pas bien, même le premier
  /// sens, surtout si on scrolle puis qu'on veut passer au mushaf papier ».
  ///
  /// `_ouvrirVuePage` prenait `_verses.first.pageNumber` -- la page où COMMENCE
  /// la sourate affichée, jamais celle qu'on regarde. Sur Al-Baqara, ouvrir le
  /// papier depuis le verset 200 renvoyait page 2. Le défaut était connu et
  /// écrit ici même (« à reprendre le jour où l'écran expose un verset
  /// visible ») : c'est ce jour-là.
  ///
  /// COMMENT : `_verseKeys` porte une `GlobalKey` par verset, déjà utilisée par
  /// le défilement. Un `ListView.builder` ne construit que les éléments proches
  /// de l'écran -- donc ceux qui ont un `currentContext` sont précisément les
  /// candidats, et il suffit de garder le premier dont le bas dépasse le haut
  /// de la fenêtre. Aucune estimation d'offset : la hauteur d'un verset varie
  /// du simple au décuple, un calcul à partir du scroll serait une fausse
  /// précision (c'est ce que disait déjà la note d'origine).
  Verse? _versetVisible() {
    final hautFenetre = MediaQuery.of(context).padding.top;
    for (var i = 0; i < _verseKeys.length && i < _verses.length; i++) {
      final ctx = _verseKeys[i].currentContext;
      if (ctx == null) continue; // hors de la fenêtre de construction
      final boite = ctx.findRenderObject();
      if (boite is! RenderBox || !boite.hasSize) continue;
      final bas = boite.localToGlobal(Offset(0, boite.size.height)).dy;
      if (bas > hautFenetre) return _verses[i];
    }
    return null;
  }

  Future<void> _ouvrirVuePage() async {
    final visible = _versetVisible();
    final page = visible?.pageNumber ??
        (_verses.isEmpty ? 1 : (_verses.first.pageNumber ?? 1));
    final lue = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MushafMaquetteScreen(
          pageInitiale: page,
          modeSystemeAuRetour: SystemUiMode.immersiveSticky,
        ),
      ),
    );
    if (!mounted || lue == null || lue == page) return;

    final versets = await QuranApi.fetchVersesByPage(lue);
    if (!mounted || versets.isEmpty) return;
    // ── LE PREMIER VERSET DE LA PAGE (2026-09-04) ──────────────────────────
    //
    // ARBITRÉ EN DEUX TEMPS, et la trace compte parce que les deux choix se
    // défendent. D'abord la FIN de page (« il doit prendre la situation de fin
    // de verset qui existe dans la page ») : celui qui a lu la page entière
    // est rendu là où il en est. Puis l'utilisateur est revenu dessus --
    // « attends, je pense que c'est mieux début de page, c'est plus logique ».
    //
    // Et c'est le choix le plus sûr : viser la fin suppose que la page a été
    // lue jusqu'au bout, ce que RIEN ne garantit -- on peut l'avoir ouverte,
    // parcourue à moitié, ou juste traversée en feuilletant. Se tromper vers
    // le début fait relire quelques versets ; se tromper vers la fin en fait
    // SAUTER. Sur un texte qu'on mémorise, les deux erreurs ne se valent pas.
    final cible = versets.first;

    if (cible.surahNumber == widget.surah.number) {
      _scrollToVerseKey(cible.key, 1.0);
      return;
    }
    _allSurahsCache ??= await QuranApi.fetchSurahs();
    if (!mounted) return;
    final sourate = _allSurahsCache!
        .where((s) => s.number == cible.surahNumber)
        .firstOrNull;
    if (sourate == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MushafScreen(
          surah: sourate,
          initialAyahNumber: cible.ayahNumber,
        ),
      ),
    );
  }

  void _openReadingSettings() {
    // Le signet descend ici depuis la barre du bas (2026-09-05, cf. le bouton
    // Tajwid). On passe la CLE du verset actif et non un booleen « marque » :
    // la feuille lit `marquePagesProvider` elle-meme et se rafraichit donc au
    // moment du tap. Un booleen capture a l'ouverture aurait rejoue exactement
    // le defaut documente en tete de `_ReadingSettingsSheet` -- l'interrupteur
    // de traduction qui mentait parce que sa valeur etait figee.
    final v = _verses.isEmpty ? null : _verses[_activeVerse];
    showReadingSettingsSheet(
      context,
      ref,
      showTranslation: _showTranslation,
      onToggleTranslation: () =>
          setState(() => _showTranslation = !_showTranslation),
      cleVersetActif: v == null
          ? null
          : MarquePagesNotifier.cle(v.surahNumber, v.ayahNumber),
      // `onToggleSignet` et `onOuvrirSignets` ne sont plus passes
      // (2026-09-09) : poser le signet est devenu le bouton rond de l'ecran,
      // et il n'y a plus de LISTE a ouvrir -- un seul signet existe desormais
      // (cf. `marquePagesProvider`), et l'ecran d'accueil y mene deja.
      // `onCarteMentale` n'est plus passe (2026-09-09) : la carte mentale est
      // remontee dans la barre du bas, visible. Cf. le bloc « LA CARTE
      // MENTALE EST ICI » dans `_BottomBar`.
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
    // ── LES DEUX RONDS FLOTTANTS S'EFFACENT (2026-09-12) ──────────────────
    //
    // Demande utilisateur : « le retour en arriere et le marqueur signet, je
    // veux que ca tienne du style et que ce soit le plus transparent
    // possible, plus qu'actuellement -- ca cache l'ecriture ».
    //
    // Troisieme passe sur ce reglage, et les deux precedentes s'annulaient :
    // opaque le 2026-08-05 (l'icone n'etait pas lisible), alpha 110 le
    // 2026-08-07 (« il cache du texte »). On tournait en rond parce que le
    // fond portait TOUT le contraste : l'icone etait creme, donc elle exigeait
    // un rond sombre sous elle, donc le rond devait rester dense.
    //
    // On inverse : c'est l'ICONE qui porte le contraste, accordee au theme de
    // lecture, et le rond n'est plus qu'un voile de la couleur du fond -- il
    // ne fait qu'attenuer ce qu'il recouvre au lieu de le masquer. Le texte
    // coranique transparait donc, et l'icone reste lisible sur les trois
    // themes, y compris Kindle qui n'etait pas distingue jusqu'ici.
    //
    // Alpha 42 au lieu de 110 : le rond reste percu (il donne sa cible au
    // doigt) sans jamais cacher un mot.
    // ── LE VOILE, A MI-CHEMIN (2026-09-12, seconde passe) ────────────────
    // Retour utilisateur sur l'alpha 42 : « la je pense c'est 0 transparence,
    // fais la moitie entre ce qui etait avant et maintenant ». 110 masquait le
    // texte, 42 effacait le bouton : (110 + 42) / 2 = 76. Le rond redevient un
    // reperage franc, le mot en dessous reste lisible.
    final fondRondFlottant = (modeSombre
            ? AppColors.sombreBgDeep
            : kindleMode
                ? AppColors.kindleBgDeep
                : AppColors.cream)
        .withAlpha(76);
    // ── ET PLUS HAUT (meme retour : « les faire encore remonter ») ────────
    // Ils prenaient la marge d'encoche ENTIERE via SafeArea, ce qui les posait
    // bas sur la page. On n'en garde qu'une part : assez pour ne pas passer
    // sous une encoche, assez peu pour qu'ils collent au bord. Plancher de 4
    // pour les ecrans qui ne declarent aucune marge (mode immersif).
    final margeHauteRond = margeHauteBoutonsMushaf(context);
    final encreRondFlottant = modeSombre
        ? AppColors.cream
        : kindleMode
            ? AppColors.kindleInk
            : AppColors.ink;
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
    // Le mode tajwid repeint la page a chaque verdict : les violets viennent
    // de `motsDegradesTajwid`, qui change au fil de la recitation.
    if (ref.watch(mushafEcouteTajwidProvider)) {
      ref.listen(recitationProvider, (_, __) {
        if (mounted) setState(() {});
      });
    }
    ref.listen<PlayerStateModel>(playerProvider, (prev, next) {
      final key = next.currentVerse?.key;
      if (key != null && key != prev?.currentVerse?.key) {
        _scrollToVerseKey(key, next.speed);
      }
      // ── LE GARDE NE VALAIT QU'À L'ARMEMENT (2026-09-04) ─────────────────
      //
      // Constat utilisateur : « le menu ne doit pas se rétracter quand un
      // audio est lancé ; la raison du repli, c'est que le récitateur est en
      // train de LIRE, pas les autres situations -- il écoute, il fait autre
      // chose ».
      //
      // Le refus de replier pendant l'écoute existe depuis le 2026-08-13,
      // mais il est testé UNE SEULE FOIS, au moment où `_scheduleHeaderHide`
      // arme le minuteur. Ouvrir le menu puis lancer l'audio dans les 6 s qui
      // suivent laissait donc un minuteur déjà parti, que rien n'annulait : le
      // menu se repliait en pleine écoute, exactement le cas signalé.
      //
      // On traite donc la TRANSITION vers la lecture, pas seulement l'état à
      // l'armement. Symétriquement, quand la lecture s'arrête, on reprogramme
      // le repli : le plein écran revient de lui-même à qui se remet à lire.
      final joue = next.isPlaying;
      if (joue != (prev?.isPlaying ?? false)) {
        if (joue) {
          // On ANNULE le repli, on ne fait pas REAPPARAITRE le menu : la
          // demande est « ne doit pas se rétracter ». Le faire surgir sur un
          // écran déjà en plein texte, parce qu'on a lancé l'audio depuis la
          // barre du bas, serait un geste que personne n'a demandé.
          _headerHideTimer?.cancel();
        } else {
          _scheduleHeaderHide();
        }
      }
    });

    return Scaffold(
      backgroundColor: modeSombre
          ? AppColors.sombreBg
          // `mushafPapier` (blanc franc) et non `cream` : cf. sa doc dans
          // app_theme.dart -- « le blanc n'est pas vraiment un vrai blanc ».
          : (kindleMode ? AppColors.kindleBg : AppColors.mushafPapier),
      // ── BANDEAU D'ECOUTE TAJWID (2026-09-05) ─────────────────────────────
      //
      // Sans lui, rien ne dirait que le micro tourne : la page est identique a
      // la lecture normale, et c'est justement ce qu'on voulait. Il faut donc
      // un signe -- et surtout un moyen d'ARRETER, sinon l'ecoute continue en
      // silence, ce que le projet interdit (le micro ne tourne jamais sans que
      // l'utilisateur le sache).
      bottomNavigationBar: ref.watch(mushafEcouteTajwidProvider)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                color: const Color(0xFF7E57C2).withValues(alpha: .12),
                child: Row(
                  children: [
                    const Icon(Icons.spellcheck_rounded,
                        size: 18, color: Color(0xFF7E57C2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.mushafTajwidBanner,
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.ink),
                      ),
                    ),
                    TextButton(
                      onPressed: _arreterEcouteTajwid,
                      child: Text(AppLocalizations.of(context)!.commonStop,
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF7E57C2))),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
                    // ── TAP-POUR-MASQUER ESSAYE PUIS RETIRE (2026-09-02) ──
                    // Tentative : un `GestureDetector` translucent autour du
                    // contenu, qui masquait le menu au tap. Retour utilisateur
                    // immediat : « le tap ne marche pas ». Cause : le contenu
                    // est un ScrollView dont les enfants (VerseTile, mots,
                    // surfaces d'annotation) remportent l'arene de gestes sur
                    // toute la surface utile -- il ne restait presque aucun
                    // pixel pour le detecteur parent. Un geste qui ne marche
                    // qu'aux interlignes n'est pas un geste.
                    // Remplace par le minuteur, porte de 4 s a 10 s.
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
                      top: margeHauteRond,
                      left: 8,
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
                          color: fondRondFlottant,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: Icon(Icons.arrow_back_rounded,
                                color: encreRondFlottant),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                    ),
                    // BASCULE « vue page » (2026-09-01). Demande
                    // utilisateur : « comment passer d'un affichage à l'autre
                    // dans l'app ? » -- jusqu'ici la vue page n'existait QUE
                    // dans le banc de recette, donc la réponse était « on ne
                    // peut pas ». Posé en miroir du retour (haut/droite), même
                    // traitement visuel : translucide, jamais masqué par le
                    // minuteur, car une bascule qu'il faut découvrir en tapant
                    // au hasard n'est pas une bascule.
                    //
                    // N'ENLÈVE RIEN : c'est un aller-retour vers un second
                    // écran, l'affichage actuel reste intact derrière (cf. la
                    // demande d'origine, « je demande pas d'enlever ce qu'on a
                    // mais une possibilité en plus »).
                    Positioned(
                      top: margeHauteRond,
                      right: 8,
                      child: Material(
                          color: fondRondFlottant,
                          shape: const CircleBorder(),
                          // ── LE BOUTON ROND POSE LE SIGNET (2026-09-09) ─
                          //
                          // Il ouvrait le Mushaf papier ; celui-ci est remonte
                          // dans l'en-tete (cf. `_SurahNavRow.onMushafPapier`).
                          // Demande utilisateur : « a la place de l'icone
                          // Mushaf papier, rajoute la possibilite de marquer
                          // un signet la ou on est arrive ».
                          //
                          // C'est le bon endroit : poser un signet est le
                          // geste qu'on fait EN LISANT, a l'endroit precis ou
                          // l'on s'arrete. Il etait jusqu'ici enfoui dans le
                          // panneau « ⋯ », d'ou il a ete retire le meme jour
                          // (`reading_settings_sheet.dart`).
                          //
                          // L'icone suit l'etat du verset actif -- pleine s'il
                          // est deja marque, contour sinon : sans cela, rien
                          // ne distingue « poser » de « retirer » avant le tap.
                          child: Builder(builder: (_) {
                            final v = _verses.isEmpty
                                ? null
                                : _verses[_activeVerse];
                            final marque = v != null &&
                                ref.watch(marquePagesProvider) ==
                                    MarquePagesNotifier.cle(
                                        v.surahNumber, v.ayahNumber);
                            return IconButton(
                              tooltip: marque
                                  ? AppLocalizations.of(context)!
                                      .mushafBookmarkRemove
                                  : AppLocalizations.of(context)!
                                      .mushafBookmarkHere,
                              icon: Icon(
                                  marque
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  color: marque
                                      ? AppColors.brass
                                      : encreRondFlottant),
                              onPressed:
                                  v == null ? null : _basculerMarquePage,
                            );
                          }),
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
                      height: _hauteurHeader(context),
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        offset: _headerVisible ? Offset.zero : const Offset(0, -1),
                        child: MushafHeader(
                          modeSombre: modeSombre,
                          surah: widget.surah,
                          onBack: () => Navigator.of(context).maybePop(),
                          onMushafPapier: _ouvrirVuePage,
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
                            // Warsh (2026-09-11, demande utilisateur) : le
                            // bouton reste visible (grise) plutot que de
                            // disparaitre -- « desactive le menu tajwid
                            // quand c'est Warsh avec message d'information
                            // si on clique dessus pour dire qu'il marche
                            // actuellement que pour Hafs, prochainement sur
                            // Warsh ». Justifie : `judgementOptionsEffectivesProvider`
                            // fait DEJA retomber le preset tajwid sur adulte
                            // en Warsh (vocabulaire de regles pas raccorde,
                            // cf. son commentaire) -- ouvrir l'ecran sans le
                            // dire aurait laisse croire a une verification
                            // tajwid qui, en pratique, n'en est pas une.
                            onTajwidTap: _verses.isEmpty
                                ? null
                                : (ref.watch(riwayaProvider) == Riwaya.warsh
                                    ? _afficherInfoTajwidWarsh
                                    : _openKaraokeTajwid),
                            tajwidIndisponible:
                                ref.watch(riwayaProvider) == Riwaya.warsh,
                            onCarteMentaleTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MindMapScreen(surah: widget.surah),
                              ),
                            ),
                            estMarque: _verses.isEmpty
                                ? false
                                : ref.watch(marquePagesProvider) ==
                                    MarquePagesNotifier.cle(
                                      _verses[_activeVerse].surahNumber,
                                      _verses[_activeVerse].ayahNumber,
                                    ),
                            isPlaying: playerState.isPlaying,
                          ),
                        ),
                      ),
                    ),
                    // Barre d'outils du crayon (2026-08-28) -- flotte
                    // au-dessus de la barre du bas, seulement pendant le mode
                    // annotation (cf. `mushafAnnotationModeProvider`, activé
                    // depuis le menu "Plus" -> `reading_settings_sheet.dart`).
                    if (ref.watch(mushafAnnotationModeProvider))
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: _kBottomBarHeight + 8,
                        child: SafeArea(
                          top: false,
                          child: _AnnotationToolbar(modeSombre: modeSombre),
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
    // Bandes laterales retirees pendant l'annotation, cf. plus bas.
    final annotationModeActif = ref.watch(mushafAnnotationModeProvider);
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
        // ── LES DEUX BANDES AVANCENT (2026-08-19) ───────────────────────
        //
        // Demande utilisateur : « chaque clic, on avance -- parce qu'on
        // avance plus qu'on ne recule. Pour reculer, il peut juste defiler
        // d'en bas, il revient en arriere ».
        //
        // La bande GAUCHE reculait. Elle avance desormais comme la droite :
        // on lit vers l'avant, et le retour en arriere se fait au
        // defilement, qui n'a jamais eu de probleme.
        //
        // Ce changement REGLE AUSSI le defaut decrit juste au-dessus (« je
        // peux avancer en bas mais je n'arrive pas a reculer en arriere ») :
        // le bord gauche est la zone du geste systeme « retour » d'Android,
        // qui capte parfois le tap avant l'application. Le decalage de
        // `_kMargeGesteSysteme` reduisait le probleme sans le supprimer.
        // Un cote qui ne PEUT plus rater sa fonction, parce que les deux
        // font la meme, ne peut plus decevoir -- et un tap capte par le
        // systeme reste un retour d'ecran, pas une page perdue.
        //
        // Les deux bandes restent SEPAREES plutot que fusionnees en une
        // seule zone : le centre appartient toujours au texte (selection
        // d'un mot, fiche tajwid), et l'elargir les avalerait.
        // ── LES BANDES SE RETIRENT EN MODE ANNOTATION (2026-09-02) ───────
        //
        // Demande utilisateur : « quand il y a le stylo deploye, ca desactive
        // le clic sur les cotes, car on peut selectionner les mots du bord ;
        // il reste que le scroll qui fonctionne ».
        //
        // Ces deux bandes sont en `translucent` : elles tournent la page ET
        // laissent le tap descendre jusqu'au mot en dessous. Pendant qu'on
        // dessine, un appui pres du bord faisait donc deux choses non
        // voulues d'un coup -- tourner la page et selectionner un mot -- au
        // moment precis ou la main repose naturellement sur les cotes.
        //
        // On les RETIRE de l'arbre plutot que de les rendre inertes : une
        // bande presente mais sans effet reste dans le hit-test et continue
        // d'intercepter. Le defilement, lui, n'est pas touche : il vient du
        // ScrollView en dessous, pas de ces bandes.
        if (!annotationModeActif) ...[
        Positioned(
          left: _kMargeGesteSysteme,
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
      ],
    );
  }

  /// Marques de surlignage du verset [verse], reconstruites depuis la map
  /// plate du provider (cf. mushaf_annotation_provider.dart) -- `null` si
  /// aucun mot du verset n'est marqué (évite d'allouer une Map vide par
  /// verset affiché, l'immense majorité n'en porte aucune).
  Map<int, Color>? _wordHighlightsFor(
      Verse verse, Map<String, int> marques, String riwaya) {
    final n = ArabicNormalizer.splitExpectedWords(verse.textUthmani).length;
    Map<int, Color>? resultat;
    // ── LE VIOLET DU TAJWID, SUR LA PAGE (2026-09-05) ────────────────────
    //
    // On reutilise le mecanisme d'ANNOTATION du mushaf (des couleurs par mot)
    // plutot que d'en inventer un second : le texte sait deja peindre un mot,
    // et le mode ne fait que fournir d'autres couleurs. Rien d'autre ne change
    // dans le rendu de la page.
    //
    // SEULEMENT du violet : ce mode ne signale pas les fautes de lettres ni de
    // harakat -- il travaille une seule chose a la fois.
    if (ref.read(mushafEcouteTajwidProvider)) {
      final notifier = ref.read(recitationProvider.notifier);
      for (final i in notifier.motsDegradesTajwid) {
        final pos = notifier.verseAndLocalIndexFor(i);
        if (pos == null) continue;
        if (pos.$1.surahNumber != verse.surahNumber ||
            pos.$1.ayahNumber != verse.ayahNumber) {
          continue;
        }
        (resultat ??= {})[pos.$2] = const Color(0xFF7E57C2);
      }
    }
    for (var i = 0; i < n; i++) {
      final couleur = marques[MushafHighlightsNotifier.cle(
          verse.surahNumber, verse.ayahNumber, i, riwaya)];
      if (couleur != null) {
        (resultat ??= {})[i] = Color(couleur);
      }
    }
    return resultat;
  }

  /// Tap sur un mot EN MODE ANNOTATION (cf. `mushafAnnotationModeProvider`) :
  /// pose la couleur sélectionnée, ou -- outil gomme (`couleur == null`) ou
  /// tap sur un mot déjà marqué de la MÊME couleur -- retire la marque.
  /// Basculer plutôt qu'empiler : reposer la même couleur sur un mot déjà
  /// marqué est le geste naturel pour « je me suis trompé, j'annule ».
  void _onWordTapAnnoter(Verse verse, int wordIndex) {
    final riwaya = ref.read(riwayaProvider).name;
    final couleur = ref.read(mushafAnnotationColorProvider);
    final notifier = ref.read(mushafHighlightsProvider.notifier);
    final existant = notifier.couleurDe(
        verse.surahNumber, verse.ayahNumber, wordIndex, riwaya);
    if (couleur == null || (existant != null && existant.toARGB32() == couleur.toARGB32())) {
      if (existant != null) {
        notifier.effacer(verse.surahNumber, verse.ayahNumber, wordIndex, riwaya);
      }
      return;
    }
    notifier.definir(
        verse.surahNumber, verse.ayahNumber, wordIndex, riwaya, couleur);
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
        // ── SURLIGNAGE LIBRE ("crayon", 2026-08-28) ─────────────────────
        //
        // Les marques restent visibles hors mode annotation (ce sont des
        // notes posées, pas un outil d'édition transitoire) -- seul le tap
        // qui les POSE dépend du mode ET de l'outil actifs (surligneur
        // uniquement -- en outil crayon, le tap sur un mot doit amorcer un
        // tracé, pas basculer une marque, cf. `_AnnotableVerse`).
        //
        // ── LA GOMME EST COMMUNE AUX DEUX OUTILS (2026-08-28) ────────────
        // « également effacer, ça doit fonctionner sur les deux ». Avant ce
        // correctif, une marque de mot ne s'effaçait qu'en outil surligneur
        // et un trait qu'en outil crayon -- il fallait rebasculer d'outil
        // rien que pour effacer l'AUTRE sorte de marque. La gomme (couleur
        // sélectionnée = null) active désormais le tap-mot ET la surface de
        // trait EN MÊME TEMPS, quel que soit l'outil affiché.
        final annotationMode = ref.watch(mushafAnnotationModeProvider);
        final outilAnnotation = ref.watch(mushafAnnotationToolProvider);
        final couleurAnnotation = ref.watch(mushafAnnotationColorProvider);
        final gommeActive = annotationMode && couleurAnnotation == null;
        final marques = ref.watch(mushafHighlightsProvider);
        final riwaya = ref.watch(riwayaProvider).name;
        final wordHighlights = _wordHighlightsFor(verse, marques, riwaya);
        final surligneurActif = annotationMode &&
            (outilAnnotation == MushafAnnotationTool.highlighter || gommeActive);
        return _AnnotableVerse(
          verse: verse,
          scrollController: _scrollController,
          child: VerseTile(
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
          wordHighlights: wordHighlights,
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
          // `onWordTap` reste non fourni HORS mode annotation, ET hors
          // outil surligneur : sans lui, le texte ne pose aucun détecteur
          // sur les mots, et le geste redescend intact au parent
          // (`onLongPress` ci-dessus, menu du verset) -- notamment en outil
          // crayon, où le tap doit pouvoir amorcer un tracé sans qu'un mot
          // ne le capte au passage. EN outil surligneur, il capte le tap
          // pour poser/retirer une marque -- cf. `_onWordTapAnnoter`.
            onWordTap: surligneurActif
                ? (i) => _onWordTapAnnoter(verse, i)
                : null,
          ),
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
    // ── LE VERSET CHARGÉ N'EST PAS FORCÉMENT LE VERSET SÉLECTIONNÉ ──────────
    //
    // Bug corrigé 2026-08-16, constat utilisateur : « quand je fais pause,
    // que je sélectionne un autre verset, au play ça doit prendre la
    // nouvelle sélection, pas continuer sur ce qui était chargé avant ».
    //
    // `dansCeQuiEstAffiche` (ci-dessous) ne demandait QUE « le verset chargé
    // fait-il partie de cette page ? » -- vrai pour N'IMPORTE LEQUEL des
    // versets affichés. Mettre en pause sur le verset 3, taper le verset 7
    // (met à jour `_activeVerse`, cf. `onTap` des tuiles), puis Play : le
    // verset 7 fait toujours partie de la même page, donc l'ancienne
    // condition prenait la branche `resume()` -- qui reprend le verset 3, en
    // ignorant totalement la nouvelle sélection.
    //
    // Le bon test compare le verset CHARGÉ au verset SÉLECTIONNÉ
    // (`_verses[_activeVerse]`) : transport (pause/reprise) seulement s'ils
    // sont IDENTIQUES, sinon c'est un changement de cible -> lecture neuve.
    final selectionne = _verses[_activeVerse].key;
    final chargeEstLeSelectionne = cle != null && cle == selectionne;
    // Le menu doit etre visible des qu'on touche au transport, et le rester
    // tant que ca joue (cf. `_scheduleHeaderHide`).
    _showHeader();
    if (chargeEstLeSelectionne && player.isPlaying) {
      ref.read(playerProvider.notifier).pause();
    } else if (chargeEstLeSelectionne && player.isPaused) {
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

  /// Tajwid indisponible en Warsh (2026-09-11) -- cf. le commentaire de
  /// `onTajwidTap` dans `_BottomBar` et le garde-fou jumeau de
  /// `judgementOptionsEffectivesProvider`. Meme style de SnackBar que
  /// `_basculerMarquePage` juste au-dessus.
  void _afficherInfoTajwidWarsh() {
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: AppColors.green900,
        content: Text(
          t.mushafTajwidWarshIndisponible,
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
  /// ── LA LISTE DES SIGNETS A ETE RETIREE (2026-09-09) ───────────────────
  ///
  /// `_ouvrirListeSignets` ouvrait une feuille listant tous les signets poses,
  /// avec un `ListTile` par entree et un saut vers `MushafScreen`. Elle n'a
  /// plus d'objet : il n'existe QU'UN signet depuis ce jour (cf.
  /// `marquePagesProvider`, passe de `Set<String>` a `String?`), et l'ecran
  /// d'accueil y mene deja par `_BoutonSignet`.
  ///
  /// Le code est retire plutot que laisse mort : il lisait
  /// `marquePagesProvider` comme une collection (`.toList()`, tri, `cles[i]`),
  /// donc il ne compilerait plus. Ce commentaire garde la trace de ce qui
  /// existait, comme le veut la regle du projet -- le remettre demanderait de
  /// redonner au provider un type collection, ce qui est precisement ce que la
  /// decision utilisateur ecarte.


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
                // ── ECOUTE TAJWID, SANS QUITTER LA PAGE (2026-09-05) ──────
                // Cf. `mushafEcouteTajwidProvider` pour le pourquoi. Placee
                // juste sous « Reciter » : c'est la meme action -- parler --
                // avec une exigence differente.
                _ActionVerset(
                  icone: Icons.spellcheck_rounded,
                  libelle: AppLocalizations.of(context)!.mushafTajwidOnPage,
                  // Warsh (2026-09-11) : meme garde-fou que le bouton
                  // Tajwid de `_BottomBar`, cf. son commentaire.
                  disabled: ref.read(riwayaProvider) == Riwaya.warsh,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (ref.read(riwayaProvider) == Riwaya.warsh) {
                      _afficherInfoTajwidWarsh();
                    } else {
                      _openKaraokeTajwid();
                    }
                  },
                ),
                _ActionVerset(
                  // Icône dédiée (2026-08-28, demande utilisateur) --
                  // `Icons.school_rounded` était aussi celle du hub Coach
                  // ("Mémoriser une sourate"), les deux se confondaient.
                  icone: Icons.psychology_rounded,
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
            // `autoDemarrer` (2026-08-23, demande utilisateur) : l'appui sur
            // "réciter" est déjà le geste explicite qui déclenche cet écran --
            // demander ENSUITE un second tap sur le halo pour vraiment
            // commencer à écouter était redondant. `_autoDemarrage()` attend
            // que le modèle soit chargé et la session prête (jusqu'à 15 s)
            // avant de démarrer seule, donc le chargement du modèle n'a plus
            // besoin d'un geste séparé non plus.
            // ⚠️ CORRECTIF (2026-08-23, même jour) : `autoDemarrer` seul FORCE
            // le mode RÉFÉRENCE (texte visible, aucune correction, cf.
            // `_toggle` : `_isReferenceSession = !widget.forcerModeNormal`) --
            // conçu à l'origine pour le seul banc de recette. Oublié ici :
            // toute récitation lancée depuis le Mushaf devenait une session
            // de référence, texte visible et erreurs jamais signalées.
            // `forcerModeNormal: true` restaure le comportement normal
            // (texte masqué tant que non jugé, correction active).
            builder: (_) => KaraokeRecitationScreen(
                verses: _fragmentFromActive(),
                autoDemarrer: true,
                forcerModeNormal: true)));
  }

  /// Ouvre l'ecran de recitation en MODE TAJWID -- texte visible, seules les
  /// regles signalees.
  ///
  /// ⚠️ Passe par l'ecran de recitation et NON par l'ecoute maison ci-dessous
  /// (`_demarrerEcouteTajwid`, conservee mais plus appelee) : celle-ci n'avait
  /// ni curseur qui suit, ni gestion du decrochage, ni reprise -- « il faut que
  /// le curseur suive les versets, sinon risque de regression ». Tout cela
  /// existe deja ici, mesure et corrige depuis des mois.
  void _openKaraokeTajwid() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => KaraokeRecitationScreen(
            verses: _fragmentFromActive(),
            autoDemarrer: true,
            forcerModeNormal: true,
            modeTajwid: true)));
  }

  /// Ecoute le tajwid SUR CETTE PAGE, sans ouvrir d'autre ecran.
  ///
  /// ⚠️ PLUS APPELEE depuis le 2026-09-05 : le menu passe par
  /// `_openKaraokeTajwid`. Conservee telle quelle (regle du projet : on
  /// n'efface pas un mecanisme, on laisse la trace de pourquoi il ne tourne
  /// pas) -- elle redeviendrait utile le jour ou l'on voudrait vraiment ecouter
  /// sans quitter la page, mais il faudrait alors lui donner le curseur et la
  /// gestion du decrochage que l'ecran de recitation possede deja.
  ///
  /// Meme chaine que la recitation normale (`startControle`), mais : la cible
  /// est le fragment visible, rien n'est masque, et seule la coloration change
  /// -- cf. `_wordHighlightsFor`, qui n'ajoute que du violet dans ce mode.
  Future<void> _demarrerEcouteTajwid() async {
    final notifier = ref.read(recitationProvider.notifier);
    // ── EN CONTINU SUR LA PAGE, PAS UN FRAGMENT (2026-09-05) ────────────
    //
    // Premiere version : `_fragmentFromActive()`, du verset actif a la fin de
    // SA page -- la cible de la recitation normale, qui vise un passage borne.
    // Precision de l'utilisateur : « non, sur la page du mushaf en continu ».
    //
    // Ce mode n'est pas un exercice sur un passage : on lit sa page, et l'app
    // ecoute. La cible est donc TOUT ce que l'ecran porte, et elle s'etend avec
    // lui -- le Mushaf charge la suite au defilement (cf. `_loadMore`), et
    // `v2CibleEtendue` en avertit la chaine, sans quoi tout mot au-dela serait
    // structurellement hors de portee (defaut deja paye le 2026-08-05).
    final fragment = _verses;
    if (fragment.isEmpty) return;
    ref.read(mushafEcouteTajwidProvider.notifier).state = true;
    // Le tajwid d'un mot ne demande pas deux observations : sur une page on ne
    // repasse pas, la fenetre n'a qu'un tour. Meme raison que dans le Coach.
    notifier.tajwidSansDoubleObservation = true;
    await notifier.setupDepuisVerset(
      fragment.map((v) => v.textUthmani).join(' '),
      surah: fragment.first.surahNumber,
      ayah: fragment.first.ayahNumber,
      premierMot: 0,
    );
    _dernierNbVersetsEcoute = fragment.length;
    ref.read(recitationVerifierProvider).microBluetooth =
        ref.read(microBluetoothProvider);
    await notifier.startControle();
    if (mounted) setState(() {});
  }

  /// Nombre de versets deja donnes a la chaine, pour n'etendre que le surplus.
  int _dernierNbVersetsEcoute = 0;

  /// Etend la cible quand le Mushaf a charge la suite.
  ///
  /// Sans cela, l'ecoute resterait bornee aux versets presents au demarrage :
  /// on lirait la page suivante et plus rien ne serait juge, en silence. C'est
  /// le defaut mesure le 2026-08-05 sur l'enchainement de pages -- l'ecran
  /// avancait, la cible de la chaine non.
  void _etendreEcouteTajwid() {
    if (!ref.read(mushafEcouteTajwidProvider)) return;
    if (_verses.length <= _dernierNbVersetsEcoute) return;
    final nouveaux = _verses.sublist(_dernierNbVersetsEcoute);
    _dernierNbVersetsEcoute = _verses.length;
    unawaited(ref.read(recitationProvider.notifier).extendWords(
        nouveaux.map((v) => v.textUthmani).join(' ')));
  }

  /// Arrete l'ecoute tajwid et rend la page a son etat de lecture.
  Future<void> _arreterEcouteTajwid() async {
    final notifier = ref.read(recitationProvider.notifier);
    notifier.tajwidSansDoubleObservation = false;
    await notifier.stopContinuous();
    ref.read(mushafEcouteTajwidProvider.notifier).state = false;
    if (mounted) setState(() {});
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

/// Superpose au verset une surface de tracé libre (mode crayon, 2026-08-28) --
/// capte les gestes SEULEMENT quand ce mode est actif (`IgnorePointer`
/// sinon, cf. plus bas), et peint les traits déjà posés PAR-DESSUS le texte,
/// qu'on soit ou non en mode annotation -- une note posée doit rester
/// visible en lecture normale, comme un vrai surlignage papier.
///
/// ── UN DOIGT DESSINE, DEUX DOIGTS FONT DÉFILER (2026-08-28) ─────────────
///
/// Retour utilisateur, crayon déployé : « il y a une contradiction avec
/// scroll qui veut scroller et l'autre qui veut dessiner ». Cause réelle :
/// la 1ʳᵉ version captait tout geste de pan à un doigt pour dessiner, ce qui
/// avalait aussi le balayage vertical qu'on utilise pour FAIRE DÉFILER la
/// page -- plus aucun moyen de bouger dans le texte sans quitter le crayon.
///
/// Convention reprise des apps d'annotation à stylet (Notability, GoodNotes,
/// Notes Samsung -- référence montrée par l'utilisateur) : **un doigt trace,
/// deux doigts font défiler**. `onScale*` (pas `onPan*`) donne le nombre de
/// pointeurs actifs (`pointerCount`) à chaque mise à jour -- dès qu'un 2ᵉ
/// doigt touche l'écran en cours de geste, le tracé en cours est ABANDONNÉ
/// (jamais persisté à moitié) et le déplacement fait défiler le
/// `ScrollController` de la liste à la place. Le geste ne redevient jamais
/// un tracé même s'il repasse à un seul doigt (ordre de levée des doigts
/// ambigu) -- `_devientDefilement` verrouille la décision pour tout le
/// geste, une fois prise.
class _AnnotableVerse extends ConsumerStatefulWidget {
  final Verse verse;
  final ScrollController scrollController;
  final Widget child;
  const _AnnotableVerse(
      {required this.verse, required this.scrollController, required this.child});

  @override
  ConsumerState<_AnnotableVerse> createState() => _AnnotableVerseState();
}

class _AnnotableVerseState extends ConsumerState<_AnnotableVerse> {
  /// Points NORMALISÉS du trait en cours de tracé (null = aucun geste en
  /// cours, ou geste devenu un défilement -- cf. `_devientDefilement`).
  List<Offset>? _traitEnCours;

  /// Le geste EN COURS a vu un 2ᵉ doigt au moins une fois -> défilement pour
  /// le reste du geste, plus jamais un tracé (cf. doc de la classe).
  bool _devientDefilement = false;

  Offset _normaliser(Offset local, Size taille) =>
      Offset(local.dx / taille.width, local.dy / taille.height);

  void _onScaleStart(ScaleStartDetails d, Size taille) {
    _devientDefilement = false;
    setState(() => _traitEnCours = [_normaliser(d.localFocalPoint, taille)]);
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size taille) {
    if (_devientDefilement || d.pointerCount >= 2) {
      if (!_devientDefilement) {
        // Bascule au 1er instant à 2 doigts : le tracé amorcé ne sera
        // jamais persisté (cf. `_onScaleEnd`, il exige `!_devientDefilement`).
        setState(() {
          _devientDefilement = true;
          _traitEnCours = null;
        });
      }
      final position = widget.scrollController.position;
      widget.scrollController.jumpTo(
          (position.pixels - d.focalPointDelta.dy)
              .clamp(position.minScrollExtent, position.maxScrollExtent));
      return;
    }
    setState(() => _traitEnCours?.add(_normaliser(d.localFocalPoint, taille)));
  }

  Future<void> _onScaleEnd(String riwaya, Color? couleur, Size taille,
      List<MushafStroke> traitsExistants) async {
    final geste = _traitEnCours;
    final futDefilement = _devientDefilement;
    setState(() {
      _traitEnCours = null;
      _devientDefilement = false;
    });
    if (futDefilement || geste == null || geste.length < 2) return;
    if (couleur == null) {
      // ── OUTIL GOMME : efface tout trait EFFLEURÉ par ce geste ───────────
      // Comparaison en PIXELS (dénormalisés via `taille`), pas en unités
      // normalisées -- un même écart normalisé vaut des pixels différents
      // en largeur et en hauteur, le seuil de tolérance doit porter sur ce
      // que le doigt touche réellement à l'écran.
      const seuilPx = 26.0;
      final notifier = ref.read(mushafStrokesProvider.notifier);
      for (final trait in traitsExistants) {
        if (trait.id == null) continue;
        final touche = trait.points.any((sp) {
          final spPx = Offset(sp.dx * taille.width, sp.dy * taille.height);
          return geste.any((gp) {
            final gpPx = Offset(gp.dx * taille.width, gp.dy * taille.height);
            return (spPx - gpPx).distance < seuilPx;
          });
        });
        if (touche) {
          await notifier.effacer(widget.verse.surahNumber,
              widget.verse.ayahNumber, riwaya, trait.id!);
        }
      }
      return;
    }
    await ref.read(mushafStrokesProvider.notifier).ajouter(
        widget.verse.surahNumber, widget.verse.ayahNumber, riwaya, couleur, geste);
  }

  @override
  Widget build(BuildContext context) {
    final annotationMode = ref.watch(mushafAnnotationModeProvider);
    final outil = ref.watch(mushafAnnotationToolProvider);
    final riwaya = ref.watch(riwayaProvider).name;
    final couleur = ref.watch(mushafAnnotationColorProvider);
    // ── LA GOMME EST COMMUNE AUX DEUX OUTILS (2026-08-28) ─────────────────
    // Cf. le commentaire jumeau dans `_buildEntry` (`gommeActive`) : cette
    // surface s'active aussi hors outil crayon dès que la gomme est
    // sélectionnée, pour pouvoir effacer un TRAIT sans rebasculer d'outil.
    final gommeActive = annotationMode && couleur == null;
    final tousLesTraits = ref.watch(mushafStrokesProvider);
    final traits = tousLesTraits[
            MushafStrokesNotifier.cle(widget.verse.surahNumber, widget.verse.ayahNumber, riwaya)] ??
        const <MushafStroke>[];
    // ── LA GOMME NE BLOQUE PLUS LE TAP QUAND IL N'Y A RIEN A GOMMER ────────
    //
    // Defaut signale (2026-09-02) : « la gomme n'enleve pas le surlignement,
    // elle supprime le stylet ».
    //
    // Cause : cette surface couvre le verset entier et arme un
    // `ScaleGestureRecognizer`. Meme en `translucent`, elle remporte l'arene
    // de gestes sur un simple tap, qui n'atteint donc jamais le mot -- alors
    // que `onWordTap` est bien cable pour effacer un surlignage (cf.
    // `surligneurActif` dans `_buildEntry`). Et cote traits, le tap ne faisait
    // rien non plus : `_onScaleEnd` exige `geste.length >= 2`, un vrai
    // balayage. Le tap etait donc capte pour rien, puis jete.
    //
    // Correctif : en GOMME, la surface ne s'active que si ce verset porte
    // reellement des traits. Sans trait, elle sort du hit-test et le tap
    // descend jusqu'au mot, ou il efface le surlignage. Le balayage pour
    // effacer un trait reste intact la ou il y en a.
    //
    // Limite ASSUMEE : sur un verset qui porte a la fois des traits ET des
    // surlignages, la surface reste prioritaire et le tap continue de ne pas
    // atteindre le mot. Traiter ce cas demanderait de decider, au moment du
    // tap, s'il vise un trait ou un mot -- un arbitrage geometrique que rien
    // n'impose aujourd'hui. A reprendre si l'usage le montre genant.
    final actif = annotationMode &&
        (gommeActive || outil == MushafAnnotationTool.pen);

    return Stack(
      children: [
        widget.child,
        if (actif || traits.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !actif,
              child: LayoutBuilder(builder: (context, constraints) {
                final taille = Size(
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                    constraints.maxHeight.isFinite ? constraints.maxHeight : 0);
                return GestureDetector(
                  // OPAQUE en train de DESSINER : le geste ne doit jamais
                  // fuiter vers le `VerseTile` en dessous, sinon un simple
                  // tap pour dessiner un point déclenche AUSSI la sélection
                  // du verset (constaté par l'utilisateur). TRANSLUCENT à la
                  // GOMME : un tap doit au contraire pouvoir continuer
                  // jusqu'au mot en dessous pour y effacer une marque de
                  // surligneur (cf. `surligneurActif` dans `_buildEntry`,
                  // câblé en même temps que cette surface quand la gomme est
                  // active) -- la sélection accidentelle du verset qu'on
                  // évite ci-dessus devient ici un effet secondaire mineur
                  // et sans conséquence (un tap dans le vide sélectionne le
                  // verset, comme partout ailleurs dans le Mushaf).
                  // Sans effet quand cette surface est inactive : ce
                  // `GestureDetector` est alors sous `IgnorePointer`, retiré
                  // du hit-test entier, quel que soit son `behavior`.
                  behavior: gommeActive
                      ? HitTestBehavior.translucent
                      : HitTestBehavior.opaque,
                  // ── EN GOMME : LE GLISSEMENT SEULEMENT ────────────────
                  // `onScale*` reclame le pointeur des qu'il se pose, y
                  // compris pour un tap immobile : le tap n'atteignait donc
                  // jamais le mot, et `_onScaleEnd` le jetait de toute facon
                  // (il exige `geste.length >= 2`). On ecoute donc `onPan*`,
                  // qui ne se declenche qu'au MOUVEMENT : le balayage efface
                  // les traits, le tap descend au mot et y efface le
                  // surlignage. Les deux gestes cohabitent au lieu de se
                  // disputer l'arene.
                  //
                  // Le crayon garde `onScale*` : il a besoin du nombre de
                  // pointeurs (`d.pointerCount`) pour distinguer un trace a
                  // un doigt d'un defilement a deux, ce que `onPan*` ne
                  // fournit pas.
                  onScaleStart: gommeActive
                      ? null
                      : (d) => _onScaleStart(d, taille),
                  onScaleUpdate: gommeActive
                      ? null
                      : (d) => _onScaleUpdate(d, taille),
                  onScaleEnd: gommeActive
                      ? null
                      : (_) => _onScaleEnd(riwaya, couleur, taille, traits),
                  onPanStart: !gommeActive
                      ? null
                      : (d) => setState(() =>
                          _traitEnCours = [_normaliser(d.localPosition, taille)]),
                  onPanUpdate: !gommeActive
                      ? null
                      : (d) => setState(() => _traitEnCours = [
                            ...?_traitEnCours,
                            _normaliser(d.localPosition, taille)
                          ]),
                  onPanEnd: !gommeActive
                      ? null
                      : (_) => _onScaleEnd(riwaya, couleur, taille, traits),
                  child: CustomPaint(
                    size: taille,
                    painter: _TraitsPainter(
                      traits: traits,
                      traitEnCours: _traitEnCours,
                      couleurEnCours: couleur,
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// Peint les traits déjà posés (en pixels, dénormalisés via [size]) plus,
/// s'il y en a un, le trait en cours de tracé -- dans la couleur active,
/// pour un retour visuel immédiat même avant que le geste ne soit terminé
/// et persisté.
class _TraitsPainter extends CustomPainter {
  final List<MushafStroke> traits;
  final List<Offset>? traitEnCours;
  final Color? couleurEnCours;
  const _TraitsPainter(
      {required this.traits, required this.traitEnCours, required this.couleurEnCours});

  void _peindreTrait(Canvas canvas, Size size, List<Offset> points, Color couleur) {
    // Pleine opacité à l'affichage, quelle que soit l'alpha STOCKÉE (cf.
    // kMushafHighlightColors -- pensée pour le fond translucide du
    // surligneur). Une encre de crayon doit être une encre, pas un lavis :
    // demande utilisateur « 4 couleurs élémentaires bien foncées ».
    final peinture = Paint()
      ..color = couleur.withAlpha(255)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(
          Offset(points[0].dx * size.width, points[0].dy * size.height),
          peinture.strokeWidth / 2,
          peinture..style = PaintingStyle.fill);
      return;
    }
    final chemin = Path()
      ..moveTo(points[0].dx * size.width, points[0].dy * size.height);
    for (final p in points.skip(1)) {
      chemin.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(chemin, peinture);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in traits) {
      _peindreTrait(canvas, size, t.points, t.couleur);
    }
    if (traitEnCours != null && couleurEnCours != null) {
      _peindreTrait(canvas, size, traitEnCours!, couleurEnCours!);
    }
  }

  @override
  bool shouldRepaint(covariant _TraitsPainter oldDelegate) =>
      oldDelegate.traits != traits ||
      oldDelegate.traitEnCours != traitEnCours ||
      oldDelegate.couleurEnCours != couleurEnCours;
}

/// Barre d'outils du surlignage libre (« crayon », 2026-08-28) : la palette
/// de couleurs, la gomme, et le bouton qui referme le mode annotation.
///
/// Reste volontairement simple (demande utilisateur : « je veux quelque
/// chose de simple ») -- pas de tracé libre au pixel : un surlignage MOT PAR
/// MOT s'accroche naturellement au texte même si le Mushaf défile ou change
/// de taille de police, ce qu'un tracé en coordonnées absolues ne ferait pas
/// (cf. TajweedText.wordHighlights pour le mécanisme d'affichage, et
/// mushaf_annotation_provider.dart pour la persistance).
class _AnnotationToolbar extends ConsumerWidget {
  final bool modeSombre;
  const _AnnotationToolbar({required this.modeSombre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final outil = ref.watch(mushafAnnotationToolProvider);
    final reduite = ref.watch(mushafAnnotationToolbarReducedProvider);

    // ── VERSION RÉDUITE (2026-08-28) ───────────────────────────────────────
    //
    // « le widget soit minimaliste, placé en bas qui se réduit également ».
    // Une simple pastille flottante, l'icône de l'outil actif -- tap pour
    // redéployer la barre complète. Laisse le plus d'écran possible visible
    // pendant qu'on lit/trace, la barre complète ne revenant qu'au besoin
    // (changer de couleur, d'outil, ou sortir du mode annotation).
    if (reduite) {
      return _PastilleReduction(
        icone: outil == MushafAnnotationTool.pen
            ? Icons.edit_rounded
            : Icons.border_color_rounded,
        modeSombre: modeSombre,
        onTap: () =>
            ref.read(mushafAnnotationToolbarReducedProvider.notifier).state = false,
      );
    }

    final couleurActive = ref.watch(mushafAnnotationColorProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: modeSombre ? AppColors.sombreBgDeep : AppColors.cream,
        borderRadius: BorderRadius.circular(20),
        border: modeSombre
            ? Border.all(color: AppColors.sombreAccent.withAlpha(120))
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.green900.withAlpha(90),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // ── UNE SEULE LIGNE (2026-08-28, retour utilisateur après capture) ──
      //
      // La 1ʳᵉ version tenait sur deux rangées (outils, puis couleurs) --
      // « ya moyen d'organiser sur une seule ligne ? ». Tout tient dans UNE
      // `Row` : outils + séparateur + couleurs + gomme défilent ensemble
      // horizontalement si l'écran est trop étroit (même mécanisme que le
      // correctif de débordement plus bas), pendant que réduction et
      // "terminé" restent épinglés à droite, toujours visibles.
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _OutilBascule(
                    icone: Icons.edit_rounded,
                    selectionne: outil == MushafAnnotationTool.pen,
                    // Convertit la couleur active dans la palette cible :
                    // rouge reste rouge, seul le rendu change. Sans cela la
                    // couleur retenue appartiendrait a l'autre palette et
                    // aucune pastille ne paraitrait selectionnee.
                    onTap: () {
                      ref.read(mushafAnnotationColorProvider.notifier).state =
                          equivalenteDans(
                              couleurActive, MushafAnnotationTool.pen);
                      ref.read(mushafAnnotationToolProvider.notifier).state =
                          MushafAnnotationTool.pen;
                    },
                  ),
                  const SizedBox(width: 6),
                  _OutilBascule(
                    icone: Icons.border_color_rounded,
                    selectionne: outil == MushafAnnotationTool.highlighter,
                    onTap: () {
                      ref.read(mushafAnnotationColorProvider.notifier).state =
                          equivalenteDans(
                              couleurActive, MushafAnnotationTool.highlighter);
                      ref.read(mushafAnnotationToolProvider.notifier).state =
                          MushafAnnotationTool.highlighter;
                    },
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 24,
                    color: modeSombre
                        ? AppColors.sombreAccent.withAlpha(90)
                        : AppColors.cream300,
                  ),
                  const SizedBox(width: 10),
                  for (final c in couleursPour(outil)) ...[
                    _PastilleCouleur(
                      couleur: c,
                      selectionnee: couleurActive?.toARGB32() == c.toARGB32(),
                      onTap: () => ref
                          .read(mushafAnnotationColorProvider.notifier)
                          .state = c,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _OutilGomme(
                    selectionnee: couleurActive == null,
                    tooltip: t.mushafAnnotateEraser,
                    onTap: () => ref
                        .read(mushafAnnotationColorProvider.notifier)
                        .state = null,
                  ),
                ],
              ),
            ),
          ),
          // ── « TOUT EFFACER » EPINGLE, HORS DEFILEMENT (2026-09-02) ────
          // Pose d'abord DANS la zone qui defile horizontalement, il en
          // sortait des que la barre depassait la largeur -- invisible sans
          // faire glisser les outils, donc invisible tout court. C'est
          // exactement ce qui avait fait croire que la gomme manquait.
          // Une action GLOBALE n'a rien a faire dans la liste des outils :
          // elle est epinglee a droite, comme la reduction et « terminé ».
          // Demande utilisateur : « il faut un qui initialise tout ».
          // La gomme travaille mot par mot et trait par trait ; sur
          // des annotations accumulees depuis des mois, la reprendre
          // une par une n'est pas un geste realiste.
          //
          // CONFIRMATION OBLIGATOIRE : l'action est irreversible et
          // porte sur TOUT le Coran, pas seulement la page visible.
          // Le libelle le dit explicitement -- « toutes les sourates »
          // -- parce que l'utilisateur appuie depuis une page, et
          // pourrait croire que seule celle-ci est concernee.
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: AppLocalizations.of(context)!.mushafClearAllTooltip,
            icon: Icon(Icons.delete_sweep_rounded,
                size: 20,
                color: modeSombre
                    ? AppColors.sombreInkSoft
                    : AppColors.inkLight),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  backgroundColor:
              modeSombre ? AppColors.sombreBgDeep : AppColors.cream,
                  title: Text(AppLocalizations.of(context)!.mushafClearAllTitle),
                  content: Text(
                      AppLocalizations.of(context)!.mushafClearAllBody),
                  actions: [
                    TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(AppLocalizations.of(context)!.commonCancel)),
                    TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(AppLocalizations.of(context)!.mushafClearAllTooltip,
                    style: TextStyle(color: Color(0xFFC62828)))),
                  ],
                ),
              );
              if (ok != true) return;
              await ref
                  .read(mushafHighlightsProvider.notifier)
                  .toutEffacer(ref.read(mushafStrokesProvider.notifier));
            },
                  ),

          const SizedBox(width: 6),
          // Réduction -- cf. _PastilleReduction pour l'état replié.
          InkWell(
            onTap: () => ref
                .read(mushafAnnotationToolbarReducedProvider.notifier)
                .state = true,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: modeSombre ? AppColors.sombreAccent : AppColors.inkLight),
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_rounded,
                color:
                    modeSombre ? AppColors.sombreAccent : AppColors.green800),
            tooltip: t.mushafAnnotateDone,
            onPressed: () =>
                ref.read(mushafAnnotationModeProvider.notifier).state = false,
          ),
        ],
      ),
    );
  }
}

/// Échantillon de couleur de la barre d'outils -- affiché en PLEIN (alpha
/// remis à 255) : ici c'est un choix à faire, pas un fond de texte, il doit
/// se voir net (cf. `kMushafHighlightColors`, semi-transparentes pour
/// l'usage inverse : rester lisible PAR-DESSUS le texte).
/// Bouton du sélecteur d'outil (crayon / surligneur) -- pastille carrée aux
/// angles arrondis plutôt que ronde, pour se distinguer visuellement des
/// pastilles de couleur juste en dessous (deux familles de boutons, deux
/// formes -- pas la même chose au premier coup d'œil).
/// État réduit de la barre d'outils (cf. `_AnnotationToolbar`) : une pastille
/// flottante minimale, juste l'icône de l'outil actif. Placée là où la barre
/// complète se tenait, pour que le tap de réouverture reste au même endroit.
class _PastilleReduction extends StatelessWidget {
  final IconData icone;
  final bool modeSombre;
  final VoidCallback onTap;
  const _PastilleReduction(
      {required this.icone, required this.modeSombre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: modeSombre ? AppColors.sombreBgDeep : AppColors.cream,
            shape: BoxShape.circle,
            border: modeSombre
                ? Border.all(color: AppColors.sombreAccent.withAlpha(120))
                : null,
            boxShadow: [
              BoxShadow(
                color: AppColors.green900.withAlpha(90),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icone,
              size: 20,
              color: modeSombre ? AppColors.sombreAccent : AppColors.green800),
        ),
      ),
    );
  }
}

class _OutilBascule extends StatelessWidget {
  final IconData icone;
  final bool selectionne;
  final VoidCallback onTap;
  const _OutilBascule(
      {required this.icone, required this.selectionne, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 34,
        decoration: BoxDecoration(
          color: selectionne ? AppColors.green100 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selectionne ? AppColors.green900 : AppColors.cream300,
            width: selectionne ? 1.5 : 1,
          ),
        ),
        child: Icon(icone,
            size: 18,
            color: selectionne ? AppColors.green900 : AppColors.inkLight),
      ),
    );
  }
}

class _PastilleCouleur extends StatelessWidget {
  final Color couleur;
  final bool selectionnee;
  final VoidCallback onTap;
  const _PastilleCouleur(
      {required this.couleur, required this.selectionnee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: couleur.withAlpha(255),
          shape: BoxShape.circle,
          border: Border.all(
            color: selectionnee ? AppColors.green900 : AppColors.cream300,
            width: selectionnee ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _OutilGomme extends StatelessWidget {
  final bool selectionnee;
  final String tooltip;
  final VoidCallback onTap;
  const _OutilGomme(
      {required this.selectionnee, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: selectionnee ? AppColors.green50 : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selectionnee ? AppColors.green900 : AppColors.cream300,
              width: selectionnee ? 2.5 : 1,
            ),
          ),
          // Icone CONTRASTEE quand l'outil est actif (2026-09-02) : elle
          // restait en `inkLight` meme selectionnee, si bien qu'on ne voyait
          // pas qu'on etait en train de gommer -- et l'on cherchait pourquoi
          // le tap n'effacait rien alors qu'un autre outil etait actif.
          child: Icon(Icons.remove_circle_outline_rounded,
              size: 17,
              color: selectionnee ? AppColors.green900 : AppColors.inkLight),
        ),
      ),
    );
  }
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
  /// Signet : ces deux-la ne sont plus cablés a un bouton de la barre depuis
  /// le 2026-09-05 (le signet a demenage dans le tiroir « Plus », cf. le
  /// commentaire du bouton Tajwid). Champs CONSERVES : l'ecran les fournit
  /// toujours, et les rebrancher tient a une ligne le jour ou la barre
  /// retrouve de la place.
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onBookmarkLongPress;
  /// Mode « Tajwid » : lecture sur la page, seules les regles sont signalees.
  final VoidCallback? onTajwidTap;
  /// Vrai en riwaya Warsh (2026-09-11) : le bouton reste visible mais grise
  /// (`onTajwidTap` affiche alors un message d'information au lieu
  /// d'ouvrir l'ecran -- cf. son commentaire d'appel). Cf. le garde-fou
  /// jumeau de `judgementOptionsEffectivesProvider`.
  final bool tajwidIndisponible;

  /// Carte mentale de la sourate. Cf. le bloc « LA CARTE MENTALE EST ICI »
  /// dans le corps : elle a quitte l'en-tete le 2026-09-09, et n'a PAS ete
  /// rangee dans le panneau « ⋯ » -- decision utilisateur.
  final VoidCallback? onCarteMentaleTap;
  /// Lecture sur fond noir : le vert du theme s'y confond avec la page.
  final bool modeSombre;
  /// Le verset actif est-il marque ? Pilotait l'icone du signet dans cette
  /// barre jusqu'au 2026-09-05 ; depuis, le signet vit dans le tiroir « Plus »
  /// et y lit `marquePagesProvider` directement. Champ conserve avec ses deux
  /// callbacks jumelles (cf. [onBookmarkTap]) : plus rien ne le lit ici.
  final bool estMarque;
  final bool isPlaying;

  const _BottomBar({
    this.onPlayTap, this.onMicTap, this.onMicLongPress, this.onMicDoubleTap,
    this.onReciteTap, this.onChainTap,
    this.onMoreTap,
    this.onBookmarkTap, this.onBookmarkLongPress, this.estMarque = false,
    this.onTajwidTap, this.tajwidIndisponible = false, this.onCarteMentaleTap,
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
                // ── LE TAJWID PREND LA PLACE DU SIGNET (2026-09-05) ───────
                //
                // Demande utilisateur : « l'acces avec l'appui fort ne me
                // convient pas, je veux un acces rapide depuis le menu avec
                // une icone propre ; par exemple le signet, range-le a un
                // autre endroit ».
                //
                // Le mode tajwid n'etait atteignable que par appui LONG sur un
                // verset (bulle `_menuVerset`) -- un geste que rien n'annonce.
                // C'est le meme reproche, mot pour mot, que celui qui avait
                // fait remonter « Reciter » et « Enchainement » dans cette
                // barre le 2026-08-09 : une fonction qui n'a pas d'icone
                // n'existe pas pour celui qui ne connait pas le geste.
                //
                // La barre etait pleine (six boutons). Le SIGNET part dans le
                // tiroir « Plus », ou il gagne au passage ce qui lui manquait :
                // ses deux gestes deviennent deux lignes ECRITES -- « Signet »
                // et « Mes signets » -- alors que la liste ne s'ouvrait que
                // par un appui long tout aussi invisible (defaut deja signale
                // le 2026-08-06 : « il n'y a pas d'acces direct pour y aller
                // apres »). L'entree de la bulle `_menuVerset` reste, elle :
                // elle agit « a partir de CE verset », ce que la barre ne sait
                // pas faire.
                //
                // ICONE : `record_voice_over` -- la voix qu'on ECOUTE, a
                // distinguer du micro plein de « Reciter » qui, lui, controle
                // la memorisation. Libelle non traduit, comme « Tajwid sur la
                // page » dans la bulle : le mot est le meme en francais et en
                // anglais, et l'arabe le reconnait (تجويد).
                _BarButton(
                  icon: Icons.record_voice_over_rounded,
                  label: t.mushafBarTajwid,
                  // Grise en Warsh (2026-09-11) -- `onTajwidTap` reste actif
                  // (message d'info), seule l'apparence change : cf.
                  // `tajwidIndisponible`.
                  color: tajwidIndisponible
                      ? AppColors.cream.withAlpha(90)
                      : null,
                  onTap: onTajwidTap ?? () {},
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
                  // Cf. le commentaire jumeau dans `_menuVerset` -- même
                  // changement, même raison (confusion avec l'icône Coach).
                  icon: Icons.psychology_rounded,
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
                  // ── « Enchainement » -> « Chaine » (2026-09-09) ─────────
                  //
                  // Demande utilisateur : « Enchainement prend beaucoup
                  // d'espace, trouve un autre mot ». Douze caracteres sur une
                  // barre qui en compte desormais sept, c'etait le libelle qui
                  // ecrasait les autres.
                  //
                  // « Chaine » dit la meme chose en deux fois moins de place,
                  // et redit l'icone (`link_rounded`, une chaine) au lieu de
                  // la doubler. Litteral et non `t.memorizationGameTitle` :
                  // cette cle est le TITRE DE L'ECRAN du jeu, ou « Enchainement »
                  // reste juste -- on ne raccourcit que le bouton. Meme voie
                  // que « Tajwid » juste au-dessus, deja litteral ici.
                  label: t.mushafBarChain,
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
                // ── LA CARTE MENTALE EST ICI, PAS DANS UN TIROIR ────────
                //
                // Elle occupait l'en-tete jusqu'au 2026-09-09, ou le Mushaf
                // papier a pris sa place. Je l'avais alors descendue dans le
                // panneau « ⋯ » -- refuse par l'utilisateur le meme jour :
                // « je ne suis pas d'accord pour cacher la carte mentale,
                // trouve un endroit dans le menu ».
                //
                // Il a raison : un panneau qu'il faut ouvrir n'est pas un
                // acces, c'est un rangement. La barre est le menu visible de
                // cet ecran ; une vue d'ensemble de la sourate y a sa place au
                // meme titre que Reciter ou Memoriser.
                //
                // La place a ete prise sur le libelle du jeu, pas sur la
                // lisibilite des autres (cf. « Chaine » plus haut).
                if (onCarteMentaleTap != null)
                  _BarButton(icon: Icons.hub_outlined, label: t.mushafBarMap,
                      onTap: onCarteMentaleTap!),
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
          // ── SEPT BOUTONS AU LIEU DE SIX (2026-09-09) ────────────────────
          // La rangee est en `spaceEvenly` sans contrainte de largeur : un
          // libelle trop long poussait les voisins hors de l'ecran, sans
          // erreur ni avertissement -- il se serait vu seulement a l'usage,
          // et seulement sur les petits ecrans. Une ligne, et l'ellipse si
          // ca ne rentre pas : le bouton se retrecit au lieu de deborder.
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
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
  /// Grise l'icone et le libelle SANS desactiver `onTap` (2026-09-11, meme
  /// principe que `tajwidIndisponible` dans `_BarButton` -- le tap doit
  /// rester actif pour afficher un message d'information).
  final bool disabled;
  const _ActionVerset(
      {required this.icone,
      required this.libelle,
      required this.onTap,
      this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final c = disabled ? AppColors.inkLight.withAlpha(140) : AppColors.green800;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Icon(icone, color: c, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(libelle,
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: disabled ? AppColors.inkLight.withAlpha(140) : AppColors.ink)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.inkLight, size: 20),
          ],
        ),
      ),
    );
  }
}
