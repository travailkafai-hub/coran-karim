import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/judgement_options.dart' show TajwidRule, JudgementPreset;
import '../providers/judgement_provider.dart' show judgementOptionsProvider;
import '../models/recitation_state.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/pause_profile_service.dart';
import '../services/portion_service.dart';
import '../services/quran_api.dart';
import '../providers/error_review_provider.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart';
import 'coach_sessions.dart'
    show sessionsArchiveProvider, tailleArchiveProvider, portionsProvider;
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

  /// Démarre la récitation SANS attendre le tap d'ouverture (banc de recette à
  /// deux téléphones, 2026-07-28).
  ///
  /// Pourquoi ce drapeau plutôt qu'un `input tap` dans le script : le tap est
  /// une étape manuelle de plus à chaque itération, et il échoue en silence
  /// (écran pas encore prêt, dialogue système par-dessus). On analyse alors une
  /// session qui n'a jamais démarré sans que rien ne le dise. Ici le démarrage
  /// est dans le même chemin de code que le tap — il attend que la cible
  /// d'alignement soit prête, et il le journalise.
  final bool autoDemarrer;

  /// Retire la Basmala de la cible d'alignement (banc de recette, 2026-07-28).
  ///
  /// Le récitateur enregistré n'attaque PAS par la Basmala : l'audio de
  /// Al-Baqara commence directement sur `الٓمٓ`. La garder dans la cible fait
  /// donc démarrer les deux côtés décalés de quatre mots — mesuré : 8 rouges
  /// consécutifs sur tout le verset 2:5 et 26 mots franchis sans verdict, alors
  /// que le modèle lit l'audio quasi parfaitement (vérifié hors device).
  /// On ne mesure alors plus la chaîne, on mesure un décalage de départ.
  final bool sansBasmala;

  /// FORCE le mode normal (CTL) même en `autoDemarrer` (2026-08-05, mesure de
  /// diagnostic ponctuelle). La recette impose d'ordinaire la référence (cf.
  /// le commentaire plus bas sur `_isReferenceSession`) : ce drapeau permet
  /// EXCEPTIONNELLEMENT de vérifier un audio déterministe sous SAUT
  /// REFUSE/décrochage, actifs uniquement en normal. Défaut false : tout
  /// appel existant du banc garde exactement le comportement d'avant.
  final bool forcerModeNormal;

  /// RELECTURE (Coach, 2026-08-13) — verdicts figés à réafficher.
  ///
  /// Demande utilisateur, répétée trois fois avant que je l'entende : « je
  /// veux la même fenêtre du karaoké où le texte est colorié », « pour éviter
  /// la multitude d'écrans ». Le Coach n'ouvre donc plus une liste de mots
  /// fautifs hors de leur texte, ni un écran maison avec ses propres
  /// couleurs : il rouvre CET écran, avec son rendu et sa palette, alimenté
  /// par la base au lieu du micro.
  ///
  /// Clé = `(sourate, verset, mot dans le verset)`, exactement la forme
  /// stockée par `session_words`/`portion_words` -- surtout PAS un index
  /// global, qui dépend de l'insertion des Bismillah et ne survivrait pas à
  /// un passage lu autrement.
  ///
  /// Quand ce champ est non nul, l'écran n'ouvre NI le micro NI la chaîne
  /// d'analyse : aucun chemin de la récitation en direct n'est emprunté, donc
  /// aucune régression possible sur elle.
  final Map<(int, int, int), ({WordStatus statut, String entendu})>? relecture;

  /// Titre du bandeau en mode relecture (nom de sourate ou libellé de portion).
  final String? titreRelecture;

  /// Nombre de mots réellement ATTEINTS par l'ancre, pour une relecture de
  /// SESSION. Indispensable : `session_words` ne stocke que les EXCEPTIONS
  /// (les mots non verts). Sans cette borne, tous les mots justes restaient
  /// `pending`, donc peints à 4 % d'opacité -- l'écran n'affichait qu'un seul
  /// mot, le fautif, sur fond vide (constaté sur capture, 2026-08-13).
  ///
  /// `null` pour une PORTION : là, chaque mot touché a sa propre ligne, donc
  /// l'absence de ligne signifie vraiment « jamais récité » et le gris est le
  /// bon rendu.
  final int? motsAtteintsRelecture;

  const KaraokeRecitationScreen({
    super.key,
    required this.verses,
    this.autoDemarrer = false,
    this.sansBasmala = false,
    this.forcerModeNormal = false,
    this.relecture,
    this.titreRelecture,
    this.motsAtteintsRelecture,
  });

  /// Vrai quand l'écran sert à revoir des verdicts archivés, pas à réciter.
  bool get estRelecture => relecture != null;

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
  StreamSubscription<int>? _decrochageSub;
  StreamSubscription<int>? _nonVertSub;
  StreamSubscription<int>? _lockedSub;

  // ── ÉTAT MIS À JOUR À CHAQUE `build`, LU PAR `dispose()` (2026-08-11) ─────
  //
  // Constat utilisateur, log device à l'appui : `dispose()` échoue à CHAQUE
  // sortie d'écran avec `Bad state: Cannot use "ref" after the widget was
  // disposed` sur `_compterMots()` (qui fait `ref.read(recitationProvider)`)
  // -- donc `SessionArchiveService.terminer()` n'écrit jamais `ended_at`, et
  // la session la plus récente reste invisible dans « Mes récitations »,
  // INDÉPENDAMMENT de tout rafraîchissement (le rafraîchissement relit une
  // donnée qui n'a simplement jamais été écrite). Reproduit deux fois de
  // suite, sur deux sorties d'écran différentes -- pas un cas rare.
  //
  // Ce champ retient le DERNIER état vu par `build()` (mis à jour à chaque
  // frame via le `ref.watch` déjà fait pour l'affichage, cf. plus bas) :
  // `_compterMots()` s'appuie dessus au lieu de relire `ref` directement,
  // ce qui rend le bilan de clôture indépendant de la validité de `ref` au
  // moment de `dispose()`.
  RecitationSessionState? _dernierEtatConnu;
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

  // ── MINUTEUR DE SILENCE, RETIRÉ (2026-08-05) ──────────────────────────
  // A existé du 2026-08-01 au 2026-08-05 sous le nom `_armerSilence` /
  // `_kSilenceCorrectionDelay` (Timer 4 s réarmé à chaque avancée du
  // pointeur, déclenchant la correction si le mot suivi ne bougeait plus).
  // Retiré : la valeur avait déjà été retouchée trois fois (3 s -> 2 s -> 4 s)
  // pour la même raison -- « il se déclenche alors que je continue de
  // parler » -- signe que le critère (absence de progression) ne distinguait
  // pas un récitateur arrêté d'un mot simplement plus long à reconnaître.
  // Mesuré le jour du retrait : déclenché sur "الٓمٓ" et sur "يُؤْمِنُونَ بِمَا"
  // dès l'ouverture de session / après un trou de reconnaissance, dans les
  // deux cas alors que le récitateur n'avait pas décroché. Décision
  // utilisateur : un récitateur bloqué dispose du souffleur manuel
  // (`_promptCurrentWord`, tap sur le mot) ; l'aide AUTOMATIQUE ne vient
  // plus que du décrochage v2 (`decrochageDetecte`, cf. `_onWordFailed`),
  // qui exige une preuve (texte hors sujet ou trou persistant sur deux
  // fenêtres), pas la seule absence de progression.

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

  /// État reconstruit depuis la base (mode relecture, cf. `estRelecture`).
  RecitationSessionState? _etatRelecture;

  /// Index du mot que L'ÉCRAN doit suivre — jamais `-1`.
  ///
  /// ── POURQUOI CETTE FONCTION EXISTE (2026-08-12) ──────────────────────────
  /// Symptôme utilisateur : « quand le contrôle de récitation dure, il y a un
  /// blocage de l'écran, il ne suit plus, il doit toujours suivre ».
  ///
  /// Le défilement ET l'enchaînement de page dépendaient tous les deux du
  /// MÊME signal, le mot marqué `WordStatus.current`. Quand ce marqueur
  /// disparaît (la chaîne n'a plus de mot « en cours » à désigner), les deux
  /// meurent ensemble et DÉFINITIVEMENT :
  ///   - le défilement voit `-1` et ne fait plus rien ;
  ///   - l'enchaînement retombe sur `pointer`, dont le commentaire d'origine
  ///     dit lui-même qu'il « reste bloqué près de 0 quand la v2 pilote » --
  ///     donc `words.length - 0` ne repasse jamais sous le seuil, et la page
  ///     suivante ne se charge plus jamais.
  ///
  /// La correction ne devine pas POURQUOI `current` disparaît : elle supprime
  /// la dépendance à un signal unique. Le repli est le mot JUGÉ le plus
  /// avancé, qui ne recule jamais et existe dès qu'un seul mot a été traité.
  /// C'est un choix d'AFFICHAGE : aucun critère de jugement n'est touché ici,
  /// on décide seulement où regarder.
  int _indexASuivre(RecitationSessionState st) {
    final courant =
        st.words.indexWhere((w) => w.status == WordStatus.current);
    if (courant >= 0) return courant;
    for (var i = st.words.length - 1; i >= 0; i--) {
      if (st.words[i].status != WordStatus.pending) return i;
    }
    return st.pointer.clamp(0, st.words.isEmpty ? 0 : st.words.length - 1);
  }
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

  /// Derniere composition de bandeaux tracee (cf. `[COUTURE]` dans
  /// `_verseArea`) -- evite de reecrire la meme ligne a chaque frame.
  String? _derniereSignatureRanges;

  /// Jusqu'a quand afficher le glyphe pause/play au centre.
  ///
  /// Retour utilisateur (2026-08-06) : « le play/pause, ce n'est pas pour
  /// rester sur l'ecran / occuper l'ecran ; juste qu'il s'affiche et c'est
  /// bon ». La premiere version etait un voile PERMANENT avec un fond
  /// assombri : il fallait le traverser pour lire le texte, alors qu'on veut
  /// juste etre averti au moment du geste.
  DateTime? _glypheEtatJusqua;
  Timer? _glypheTimer;

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
  /// Marge de mots qu'on garde TOUJOURS chargée devant le récitateur.
  ///
  /// ── UNE PAGE D'AVANCE, PAS UNE RÉACTION DE DERNIÈRE SECONDE (2026-08-12) ─
  /// Principe posé par l'utilisateur : « il faut préparer tout le temps une
  /// page à l'avance, que le texte n'arrive jamais au bout ». La valeur
  /// précédente (8 mots) déclenchait l'enchaînement quand le récitateur était
  /// déjà sur les derniers mots : si le chargement tardait, ou si le signal
  /// qui le déclenche manquait une seule fois, on butait sur la fin du texte
  /// et l'écran se figeait -- symptôme rapporté (« la page reste bloquée au
  /// verset 5 alors que j'ai récité plus »).
  ///
  /// Une page du Mushaf fait ~140 mots ; on garde cet ordre de grandeur en
  /// marge. La récitation ne touche donc jamais le bord du texte chargé, et
  /// le mécanisme n'a plus besoin d'être ponctuel pour être fiable. Coût :
  /// une page de plus en mémoire, lue depuis un asset local -- négligeable.
  static const int _kExtendLookaheadWords = 150;

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

  /// Longueur du FIL DE LUMIERE : nombre de mots eclaires derriere le curseur.
  /// Borne l'effet ET son cout -- seuls ces mots-la se reconstruisent au rythme
  /// de l'animation (cf. `_wordSpan`). Une page en porte plus de cent.
  static const int _kTraineeMots = 6;

  /// Duree d'affichage du glyphe pause/play au centre.
  static const int _kGlypheEtatMs = 1100;

  // Métadonnées (nom arabe/français, nombre de versets) des sourates déjà
  // rencontrées dans _verses — préchargées avant chaque affichage (initial ou
  // extension) pour que _SurahTransitionBanner puisse les lire de façon
  // SYNCHRONE au build (demande utilisateur 2026-07-11 : "séparer visuellement
  // les sourates avec le nom de la sourate, un rendu graphique plus beau").
  final Map<int, Surah> _surahMeta = {};

  /// Métadonnées d'une sourate (nom, nombre de versets) — pour le bandeau de
  /// transition.
  ///
  /// ── LU EN LOCAL, PLUS SUR LE RESEAU (2026-08-13) ────────────────────────
  /// Mesuré sur device, à l'ouverture d'une mémorisation : cette seule étape
  /// coûtait 974 à 2241 ms sur des ouvertures de 1039 à 2609 ms au total --
  /// autrement dit ~90 % de l'attente, et une variabilité typique du réseau.
  /// `QuranApi.fetchSurahInfo` tape `api.quran.com/chapters/{id}` alors que
  /// `fetchSurahs()` sert EXACTEMENT les mêmes objets `Surah` depuis
  /// `assets/data/quran_chapters.json`, embarqué et mis en cache statique.
  ///
  /// Gain secondaire, et il compte autant : la récitation elle-même appelle
  /// cette méthode à chaque enchaînement de page (`_maybeExtendNextPage`).
  /// Elle n'a donc plus besoin du réseau pour passer d'une sourate à l'autre.
  ///
  /// Repli réseau conservé pour le cas où l'asset ne connaîtrait pas ce
  /// numéro : on ne perd aucun cas qui marchait avant.
  Future<Surah> _fetchSurahMeta(int surahNumber) async {
    final cached = _surahMeta[surahNumber];
    if (cached != null) return cached;
    final locales = await QuranApi.fetchSurahs();
    for (final s in locales) {
      if (s.number == surahNumber) return s;
    }
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
    // ── RELECTURE : on prépare le TEXTE, jamais la chaîne (2026-08-13) ──────
    // `_prepareTexteSeul` fait exactement ce que `_initAsync` fait d'utile ici
    // (Bismillah, blocs, spans tajwid, clés de mots, métadonnées de sourate)
    // et s'arrête avant `setup()` : ni micro, ni cible d'alignement, ni
    // abonnements aux flux de jugement. Un écran de Coach ne doit pas pouvoir
    // écrire dans l'archive ni déclencher une correction audio.
    if (widget.estRelecture) {
      _prepareTexteSeul();
      return;
    }
    // L'ecran ne doit pas s'eteindre pendant qu'on recite (2026-08-13) :
    // l'extinction coupe le suivi. Relache dans `dispose`, et de toute facon
    // par le systeme si l'app quitte le premier plan (cf. MainActivity).
    _garderEcranAllume(true);
    _initAsync();
    _pauseProfile.hasProfileFor(_initialPassageKey).then((has) {
      if (mounted) setState(() => _hasProfile = has);
    });
    _pauseProfile.isGlobalStable().then((stable) {
      if (mounted) setState(() => _globalStable = stable);
    });
    if (widget.autoDemarrer) _autoDemarrage();
    // Correction automatique (demande utilisateur 2026-07-05) : dès qu'un mot
    // est verrouillé rouge, pause + lecture réciteur + reprise, sans tap —
    // seulement si le réglage est activé (sinon comportement inchangé,
    // correction disponible uniquement au tap sur le mot). ref.keepAlive()
    // dans recitationProvider (cf. recitation_provider.dart) garantit que
    // cette instance ne change plus sous nos pieds après cet abonnement.
    _wordFailedSub = ref.read(recitationProvider.notifier).wordFailed.listen(
        (i) => _onWordFailed(i,
            raison: 'mot precedent egalement en echec (deux consecutifs)'));
    // ARCHIVE DU COACH : tout mot verrouillé non vert, sans condition.
    // Distinct de `wordFailed` à dessein -- celui-ci pilote la correction et
    // est filtré (réglage, anti-rafale, mode) ; un mot rouge qui n'interrompt
    // pas reste un mot rouge à revoir plus tard.
    _nonVertSub = ref
        .read(recitationProvider.notifier)
        .wordLockedNonGreen
        .listen(_archiverMotNonVert);
    // SUIVI PERMANENT PAR PORTION (sourate/Hizb, 2026-08-10) : TOUT mot
    // verrouillé, vert compris (cf. `wordLocked`, distinct de
    // `wordLockedNonGreen` ci-dessus) -- une portion doit pouvoir passer un
    // mot déjà connu comme faux au vert si une récitation ultérieure le
    // réussit, ce que le flux non-vert seul ne permet jamais de voir.
    _lockedSub = ref
        .read(recitationProvider.notifier)
        .wordLocked
        .listen(_archiverMotDansPortion);
    // DÉCROCHAGE (2026-08-01) : le récitateur dit autre chose que le texte --
    // deux mots décodés consécutifs hors du texte attendu. Flux SÉPARÉ de
    // `wordFailed` (qui, lui, parle d'un mot attendu mal jugé) : ici, ce
    // n'est pas un mot qui est faux, c'est la récitation qui a quitté le
    // texte. On reprend la main sur le mot courant.
    _decrochageSub =
        ref.read(recitationProvider.notifier).decrochageDetecte.listen((ancre) {
      // NE PAS décrocher avant que la récitation ait VRAIMENT commencé
      // (2026-08-05, même raison que le minuteur de silence retiré ci-dessus,
      // confirmée par l'utilisateur sur ce cas précis : « je n'ai pas parlé,
      // ça doit attendre »). Mesuré sur device : décrochage déclenché à
      // 17:46:44 sur "الٓمٓ" (premier mot réel après la Bismillah, jamais
      // encore verrouillé), à partir de deux fragments non reconnus ("مٍ" à
      // 17:46:36, "تَ" à 17:46:44) séparés de 8 s de silence -- des restes de
      // "الٓمٓ" mal reconnu, pas du texte étranger.
      final words = ref.read(recitationProvider).words;
      final premierReel = words.indexWhere((w) => !w.isBasmala);
      if (premierReel >= 0 && ancre <= premierReel && !words[premierReel].locked) {
        DiagnosticLog.log('Decrochage',
            'ignoré : premier mot réel (mot=$premierReel) pas encore verrouillé');
        return;
      }
      // OUBLI archivé ICI, indépendamment du verdict final du mot (2026-08-09,
      // cf. `_archiverOubli`) : que la reprise soit jugée verte ou non, le
      // décrochage a bien eu lieu.
      unawaited(_archiverOubli(ancre, avecAudio: true));
      _onWordFailed(ancre,
          surSilence: true, raison: 'decrochage v2 (hors texte ou trou)');
    });
  }

  /// Prépare le TEXTE seul, pour la relecture du Coach (2026-08-13).
  ///
  /// Reprend le début de [_initAsync] -- Bismillah, découpe en blocs, spans
  /// tajwid, clés de mots, métadonnées de sourate -- et s'arrête AVANT
  /// `setup()`. C'est cette frontière qui garantit qu'une relecture ne peut
  /// pas ouvrir le micro, écrire dans l'archive, ni déclencher de correction.
  static const _canalEcran = MethodChannel('coran_karim/ecran');

  /// Empeche l'ecran de s'eteindre pendant la recitation (best-effort : une
  /// plateforme qui ne repond pas ne doit jamais faire echouer une session).
  void _garderEcranAllume(bool actif) {
    _canalEcran.invokeMethod('garderAllume', {'actif': actif}).catchError((e) {
      DiagnosticLog.log('Karaoke', 'garderAllume($actif) indisponible : $e');
      return null;
    });
  }

  Future<void> _prepareTexteSeul() async {
    // Chronometrage par etape (2026-08-13) : l'utilisateur signale que
    // l'ouverture d'une memorisation « prend du temps ». On mesure avant de
    // toucher quoi que ce soit -- une optimisation posee sur une intuition
    // optimise en general ce qui ne coute rien.
    final t0 = DateTime.now();
    final bismillahVerse = await QuranApi.fetchBismillah();
    final t1 = DateTime.now();
    final chunk = _buildChunk(_verses, null, bismillahVerse);
    final t2 = DateTime.now();
    final wordKeys = List.generate(
        ArabicNormalizer.splitExpectedWords(chunk.text).length,
        (_) => GlobalKey());
    final t3 = DateTime.now();
    final initialSurahs = _verses.map((v) => v.surahNumber).toSet();
    final metaEntries = await Future.wait(initialSurahs.map((n) async {
      try {
        return MapEntry(n, await _fetchSurahMeta(n));
      } catch (_) {
        return null;
      }
    }));
    final t4 = DateTime.now();
    if (!mounted) return;
    setState(() {
      _tajwidSpans = chunk.spans;
      _wordKeys = wordKeys;
      _bismillahWordCount =
          ArabicNormalizer.splitExpectedWords(bismillahVerse.textUthmani).length;
      for (final e in metaEntries) {
        if (e != null) _surahMeta[e.key] = e.value;
      }
      _rebuildWordVerseMap();
      final t5 = DateTime.now();
      _etatRelecture = _construireEtatRelecture(chunk.text);
      final t6 = DateTime.now();
      int ms(DateTime a, DateTime b) => b.difference(a).inMilliseconds;
      DiagnosticLog.log('Relecture',
          'ouverture ${ms(t0, t6)} ms | bismillah=${ms(t0, t1)} '
          'blocs+tajwid=${ms(t1, t2)} cles=${ms(t2, t3)} '
          'meta=${ms(t3, t4)} tableVersets=${ms(t4, t5)} '
          'etat=${ms(t5, t6)} | versets=${_verses.length} '
          'mots=${wordKeys.length}');
      _ready = true;
    });
  }

  /// État de session RECONSTRUIT depuis les verdicts archivés.
  ///
  /// Le rendu (`_verseArea`) ne sait lire qu'un [RecitationSessionState] : on
  /// lui en fabrique un, plutôt que d'écrire un second moteur d'affichage qui
  /// dériverait immanquablement du premier. C'est tout l'intérêt de réutiliser
  /// cet écran -- une seule palette, une seule mise en page, un seul endroit
  /// à corriger.
  ///
  /// Un mot absent de l'archive reste `pending` : il n'a jamais été récité.
  /// On ne le peint PAS en vert -- précision explicite de l'utilisateur
  /// (2026-08-12) : « quand j'ai dit que les non jugés peuvent être comptés
  /// verts, ça ne veut pas dire de les rendre verts ». La règle du 2026-08-11
  /// portait sur le POURCENTAGE, pas sur la couleur.
  RecitationSessionState _construireEtatRelecture(String texte) {
    final verdicts = widget.relecture!;
    final mots = ArabicNormalizer.splitExpectedWords(texte);
    final out = <RecitedWord>[];
    var dernierJuge = -1;
    for (var i = 0; i < mots.length; i++) {
      final verse = _verseContaining(i);
      final local = _localIndexInVerse(i);
      final v = (verse == null || local == null)
          ? null
          : verdicts[(verse.surahNumber, verse.ayahNumber, local)];
      if (v != null) dernierJuge = i;
      // Mot ATTEINT par l'ancre et absent de l'archive : il a ete recite
      // JUSTE -- c'est tout le principe d'une table qui ne garde que les
      // exceptions. Au-dela de l'ancre (ou pour une portion, cf.
      // `motsAtteintsRelecture`), l'absence signifie « jamais recite ».
      final atteint = widget.motsAtteintsRelecture != null &&
          i < widget.motsAtteintsRelecture!;
      if (atteint) dernierJuge = i;
      out.add(RecitedWord(
        display: mots[i],
        normalized: ArabicNormalizer.normalize(mots[i]),
        strict: ArabicNormalizer.normalizeStrict(mots[i]),
        training: ArabicNormalizer.normalizeTraining(mots[i]),
        status: v?.statut ??
            (atteint ? WordStatus.correct : WordStatus.pending),
        // `locked` reste faux : rien n'est en cours de jugement ici. Il ne
        // sert qu'à la chaîne vivante.
        heard: v?.entendu ?? '',
        isBasmala: verse == null,
      ));
    }
    return RecitationSessionState(
      words: out,
      // Le pointeur borne la fenêtre de rendu (cf. `_verseArea`). En relecture
      // on veut pouvoir parcourir TOUT le texte : on le place au dernier mot
      // connu, et le défilement libre fait le reste.
      pointer: dernierJuge < 0 ? 0 : dernierJuge,
      status: RecitationStatus.idle,
    );
  }

  Future<void> _initAsync() async {
    // PRÉCHARGEMENT DU RÉGLAGE DE CORRECTION (2026-08-05) -- ne pas retirer.
    // Ce provider démarre à `true` en dur puis lit sa valeur PERSISTÉE en
    // asynchrone, et il n'est créé qu'au premier `ref.read`. Sans ce
    // préchargement, ce premier read était celui de la PREMIÈRE correction :
    // elle lisait le défaut `true`, les suivantes la vraie valeur. Mesuré sur
    // device (réglage persisté à `false`) : 1ʳᵉ correction jouée, 2ᵉ et 3ᵉ
    // « IGNORÉ : correction automatique désactivée » -- systématique, ce que
    // l'utilisateur avait bien vu comme « toujours le deuxième KO ».
    // Le créer ici laisse plusieurs secondes à la lecture avant qu'une
    // correction soit seulement possible.
    ref.read(autoCorrectionEnabledProvider);
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
      _rebuildWordVerseMap();
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
        _rebuildWordVerseMap();
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
  /// il demande le mot, il l'entend, il continue.
  ///
  /// ⚠️ MIS À JOUR (2026-08-09) : « Aucun mot n'est marqué » n'est plus tout
  /// à fait vrai -- demander le mot est désormais archivé comme un OUBLI
  /// (`_archiverOubli`, cf. sa doc), demande utilisateur explicite. Ce qui
  /// reste vrai : le MOT lui-même (sa couleur à l'écran, son statut de
  /// jugement acoustique) n'est ni jugé ni reculé ici -- seule une trace est
  /// ajoutée, séparée du jugement.
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
    // PAS `st.pointer` (2026-08-05) : quand la v2 pilote, `_onV2` met à jour
    // les MOTS mais jamais le pointeur, qui reste donc à 0 -- toujours DANS
    // la Bismillah. `_verseContaining(0)` y rend `null` (exclusion
    // volontaire), donc la fonction s'arrêtait en silence AVANT la première
    // ligne de log : le bouton ne faisait jamais rien dès qu'une session
    // tournait avec la v2 (mesuré : zéro ligne `[Souffleur]` sur toute une
    // journée de tests). Même correctif que partout ailleurs dans ce
    // fichier : suivre le mot marqué `current`, pas le pointeur.
    final suivi = st.words.indexWhere((w) => w.status == WordStatus.current);
    final pointer = suivi >= 0 ? suivi : st.pointer;
    final verse = _verseContaining(pointer);
    final local = _localIndexInVerse(pointer);
    if (verse == null || local == null) return;

    // OUBLI archivé (2026-08-09, demande utilisateur) : demander le mot AU
    // SOUFFLEUR est la preuve qu'il manquait -- jusqu'ici « on ne juge rien »
    // (délibéré, 2026-07-16, cf. la doc de cette fonction), mais ne rien
    // enregistrer faisait disparaître un vrai trou de mémoire. Sans audio
    // (`avecAudio` défaut false) : l'anneau ne contient à cet instant que le
    // silence qui a précédé la demande, rien à en tirer.
    unawaited(_archiverOubli(pointer));

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
        // wordsAfter = 1 (2026-08-05, demande utilisateur : "l'audio doit
        // dire deux mots") -- le mot demandé PLUS le suivant, pour donner un
        // peu d'élan à la reprise. Même réglage que la correction déclenchée
        // par décrochage (`wordsBefore: 0, wordsAfter: 1`) : dans les deux
        // cas le récitateur est arrêté et doit repartir, pas rejouer ce qu'il
        // vient de dire.
        await WordCorrectionAudio.playWordRange(verse, reciter,
            errorWordIndex: local, wordsBefore: 0, wordsAfter: 1);
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
    _garderEcranAllume(false);
    _breath.dispose();
    _glypheTimer?.cancel();
    _wordFailedSub?.cancel();
    _decrochageSub?.cancel();
    _nonVertSub?.cancel();
    _lockedSub?.cancel();
    // Clôture de l'archive à la SORTIE D'ÉCRAN aussi, pas seulement à la fin
    // naturelle : quitter en cours de route est le cas le plus fréquent, et
    // une session sans `ended_at` n'apparaît nulle part dans le Coach. Le
    // bilan est calculé ICI (synchrone, l'état est encore lisible) et
    // l'écriture part en fire-and-forget -- `dispose()` ne doit rien attendre.
    //
    // ── ENTOURÉ D'UN try/catch (2026-08-09) ────────────────────────────────
    //
    // BUG CORRIGÉ, constat utilisateur : après pause puis retour en arrière,
    // le micro restait actif ET le Coach ne montrait pas la récitation --
    // les DEUX symptômes signalés ensemble, et c'est le même défaut. Ce bloc
    // vit AVANT le code plus bas qui relâche le micro
    // (`notifier.stopContinuous()` / `verifier.stop()`, correctif du
    // 2026-08-06 déjà). Une exception ICI (par ex. `_compterMots()` qui lit
    // `ref.read(recitationProvider)`, ou `ref.invalidate` sur un `ref` en
    // cours de démontage -- Riverpod ne garantit pas sa validité à tout
    // instant de `dispose()`) interrompt la fonction et fait sauter TOUT ce
    // qui suit, y compris la libération du micro. Le commentaire du
    // correctif de 2026-08-06 disait « le micro doit être relâché DANS TOUS
    // LES CAS » -- ce try/catch est ce qui rend ça vrai même quand ce bloc
    // plus récent échoue.
    try {
      if (SessionArchiveService.instance.sessionCourante != null) {
        final (total, verts, atteints, nonJuges) = _compterMots();
        SessionArchiveService.instance.terminer(
          wordsTotal: total,
          wordsGreen: verts,
          wordsReached: atteints,
          wordsSkipped: nonJuges,
        );
      }
    } catch (e) {
      DiagnosticLog.log(
          'Archive', 'sortie d\'ecran : cloture archive a echoue : $e');
    }
    // ── INVALIDATION DU CACHE, DANS SON PROPRE try/catch (2026-08-11) ──────
    //
    // Séparée du bloc ci-dessus : `terminer()` (l'écriture qui compte
    // réellement -- sans elle la session reste invisible pour toujours,
    // cf. la doc de `_dernierEtatConnu`) ne doit JAMAIS être empêchée par un
    // échec de CE geste, purement cosmétique (`_openCoachTab()` dans
    // main.dart réinvalide de toute façon systématiquement à l'ouverture de
    // l'onglet Coach -- ce bloc n'est qu'un raccourci pour l'avoir déjà à
    // jour si l'onglet était déjà ouvert derrière). BUG CORRIGÉ (2026-08-07,
    // doc d'origine) : sans invalidation, l'écran Coach déjà monté montrait
    // sa dernière lecture. `ref.invalidate` peut lever `Bad state: Cannot
    // use "ref" after the widget was disposed` selon le chemin de sortie --
    // mesuré reproductible sur ce fichier avant qu'il ne soit séparé de
    // `_compterMots()`/`terminer()` ci-dessus, qui n'a plus besoin de `ref`
    // du tout depuis ce même correctif.
    try {
      ref.invalidate(sessionsArchiveProvider);
      ref.invalidate(tailleArchiveProvider);
      ref.invalidate(portionsProvider);
    } catch (e) {
      DiagnosticLog.log(
          'Archive', 'sortie d\'ecran : invalidation cache a echoue (sans consequence) : $e');
    }
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
    // ── RELÂCHER LE MICRO EN QUITTANT L'ÉCRAN (2026-08-06) ────────────────
    //
    // Défaut constaté par l'utilisateur, en lisant le Mushaf : « je vois le
    // micro allumé, il n'y a pas de raison, je ne suis pas en récitation ».
    // Vérifié sur l'appareil :
    //     appops get com.corankarim.coran_karim RECORD_AUDIO
    //     -> RECORD_AUDIO: allow; time=+8m35s ago (RUNNING)
    // L'application détenait donc le micro depuis huit minutes, c'est-à-dire
    // depuis qu'elle avait quitté la récitation.
    //
    // CAUSE : seul `_recorder.stop()` relâche le micro, et il n'est appelé que
    // par `RecitationVerifier.stop()`. `pauseCapture()` fait `_recorder.pause()`
    // -- l'objet `AudioRecord` reste vivant, et Android maintient son
    // indicateur de confidentialité tant qu'il l'est. `_closeAudioCapture()`,
    // malgré son nom, ne coupe que l'écriture du WAV (`setClipCapture(null)`).
    // Et `dispose()` n'appelait ni l'un ni l'autre.
    //
    // Même racine que le défaut déjà documenté ce jour (`capture ouverte` = 3,
    // trace de fermeture = 0, d'où les derniers mots jamais jugés) -- mais avec
    // une conséquence bien plus grave : garder le micro d'un utilisateur qui ne
    // récite plus.
    //
    // Fire-and-forget : `dispose()` est synchrone et ne doit jamais retarder la
    // fermeture de l'écran. `stopContinuous()` d'abord -- il ferme proprement
    // la session v2 (dernière fenêtre hors grille) ; puis `stop()` en ceinture,
    // car `stopContinuous()` sort tout de suite si la session n'est plus
    // `isActive`, et le micro doit être relâché DANS TOUS LES CAS.
    final notifier = ref.read(recitationProvider.notifier);
    final verifier = ref.read(recitationVerifierProvider);
    unawaited(() async {
      try {
        await notifier.stopContinuous();
      } catch (e) {
        DiagnosticLog.log('ASR', 'sortie d\'ecran : stopContinuous a echoue : $e');
      }
      try {
        await verifier.stop();
        DiagnosticLog.log('ASR', 'sortie d\'ecran : micro relache');
      } catch (e) {
        DiagnosticLog.log('ASR', 'sortie d\'ecran : stop() a echoue : $e');
      }
    }());
    super.dispose();
  }


  /// Archive un mot verrouillé non vert : le verdict ET la voix du récitant.
  ///
  /// ⚠️ L'EXTRACTION EST URGENTE, pas différable. La voix vit dans un anneau
  /// de 300 s côté natif et `v2ExtraitVoix` écrit toujours dans le MÊME
  /// fichier de cache : la prochaine extraction écrase celle-ci. C'est
  /// exactement ce que l'utilisateur a décrit — « j'ai écouté ma voix sur la
  /// première erreur, puis il n'y a plus de voix ». On copie donc le fichier
  /// dans l'archive tout de suite (cf. SessionArchiveService.archiverMot).
  ///
  /// La fenêtre est `mot-1 .. mot` (le mot précédent porte la liaison et le
  /// madd de fin, un mot seul s'écoute mal) — même choix que la fiche d'aide.
  Future<void> _archiverMotNonVert(int wordIndex) async {
    if (_isReferenceSession) return;
    if (SessionArchiveService.instance.sessionCourante == null) return;
    final words = ref.read(recitationProvider).words;
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final mot = words[wordIndex];
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    String? extrait;
    try {
      extrait = await ref
          .read(recitationVerifierProvider)
          .v2ExtraitVoix(wordIndex > 0 ? wordIndex - 1 : wordIndex, wordIndex);
    } catch (e) {
      // Audio sorti de l'anneau, ou chaîne déjà fermée : le verdict s'archive
      // quand même. Ne jamais laisser une panne d'audio faire perdre la trace.
      DiagnosticLog.log('Archive', 'extrait voix impossible mot=$wordIndex : $e');
    }
    await SessionArchiveService.instance.archiverMot(
      wordIndex: wordIndex,
      expectedWord: mot.display,
      status: mot.status.name,
      surahNumber: verse?.surahNumber,
      ayahNumber: verse?.ayahNumber,
      wordInAyah: local,
      heardWord: mot.heard,
      kind: ref.read(recitationProvider.notifier).classifyError(wordIndex).name,
      audioSource: extrait,
    );
  }

  /// Suivi PERMANENT par portion (sourate, ou tranche de Hizb/demi-Hizb) --
  /// distinct de [_archiverMotNonVert] : celui-ci écrit pour TOUT mot
  /// verrouillé (vert compris), dans `portion_words` (verdict qui ne meurt
  /// jamais), pas dans `session_words` (journal daté à 7 jours). Les DEUX
  /// écritures coexistent, chacune alimente son propre écran du Coach.
  ///
  /// L'extrait audio n'est tenté QUE pour un mot non vert -- inutile de
  /// consommer l'anneau natif (300 s, urgent) pour un mot déjà correct dont
  /// personne n'aura besoin de réentendre la preuve.
  Future<void> _archiverMotDansPortion(int wordIndex) async {
    if (_isReferenceSession) return;
    final words = ref.read(recitationProvider).words;
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final mot = words[wordIndex];
    if (mot.isBasmala) return; // jamais jugée, cf. _compterMots -- rien à suivre
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    if (verse == null || local == null) return;
    String? extrait;
    if (mot.status != WordStatus.correct) {
      try {
        extrait = await ref
            .read(recitationVerifierProvider)
            .v2ExtraitVoix(wordIndex > 0 ? wordIndex - 1 : wordIndex, wordIndex);
      } catch (e) {
        DiagnosticLog.log(
            'Archive', 'extrait voix (portion) impossible mot=$wordIndex : $e');
      }
    }
    try {
      final granularite = ref.read(portionGranularityProvider);
      final portion =
          await PortionService.resolve(verse: verse, granularity: granularite);
      await SessionArchiveService.instance.upsertPortionWord(
        surahNumber: verse.surahNumber,
        unitKey: portion.unitKey,
        label: portion.label,
        firstAyah: portion.firstAyah,
        lastAyah: portion.lastAyah,
        wordsTotal: portion.wordsTotal,
        ayahNumber: verse.ayahNumber,
        wordInAyah: local,
        expectedWord: mot.display,
        status: mot.status.name,
        heardWord: mot.heard,
        kind: mot.status == WordStatus.correct
            ? null
            : ref.read(recitationProvider.notifier).classifyError(wordIndex).name,
        audioSource: extrait,
      );
    } catch (e) {
      // La portion est un suivi en plus, jamais une condition de la
      // récitation en cours : une panne ici ne doit rien bloquer.
      DiagnosticLog.log('Archive', 'archivage portion impossible mot=$wordIndex : $e');
    }
  }

  /// Mots que L'ANCRE A DÉPASSÉS SANS QUE LE MODÈLE NE LES AIT JAMAIS JUGÉS
  /// (2026-08-11, constat utilisateur : « je parle de ceux que le modèle n'a
  /// pas jugé, c'est-à-dire déjà passé par l'ancre, il reste indéfiniment non
  /// jugé »). Un tel mot ne déclenche JAMAIS `wordLocked` (il ne passe pas par
  /// `_judge`, `locked` reste faux) : sans ce balayage, il resterait invisible
  /// pour toujours dans `portion_words`, comptant contre le pourcentage de la
  /// portion au même titre qu'un mot jamais récité -- exactement le défaut
  /// signalé.
  ///
  /// AUCUNE NOUVELLE INSTRUMENTATION CÔTÉ CHAÎNE : la même donnée que
  /// `_compterMots()` utilise déjà (`_dernierEtatConnu`, l'ancre max =
  /// dernier mot avec un statut définitif) suffit -- ce balayage lit ce qui
  /// existe, il n'attend rien de nouveau. Écrit `status: 'skipped'` dans
  /// `portion_words` : ni un succès ni un échec (cf.
  /// `PortionResume.reussite`/`badge`, qui excluent ce statut des deux
  /// compteurs, même principe que la Bismillah dans `_compterMots`).
  ///
  /// `_motsNonJugesArchives` évite de retenter le même mot à chaque appel
  /// (throttlé par l'appelant, cf. `_majBilanPeriodique`) -- un mot qui reste
  /// `pending` le reste par définition tant que l'ancre ne recule pas dessus,
  /// pas la peine de réécrire la même ligne en boucle.
  final Set<int> _motsNonJugesArchives = {};

  Future<void> _archiverMotsNonJugesDansPortions() async {
    if (_isReferenceSession) return;
    final etat = _dernierEtatConnu;
    if (etat == null) return;
    final words = etat.words;
    final ancreMax = words.lastIndexWhere((w) =>
            w.status != WordStatus.pending && w.status != WordStatus.current) +
        1;
    for (var i = 0; i < ancreMax; i++) {
      // `!locked` plutôt que `status == pending` (corrigé 2026-08-11) : un mot
      // PROVISOIRE (ex. `provisoire:rouge`) porte déjà un statut mais n'a
      // jamais été figé, donc `wordLocked` ne s'est jamais déclenché dessus et
      // il n'existe nulle part en base -- exactement le cas du mot 20
      // (صِرَٰطَ) de la session Al-Fatiha du 2026-08-11 : rouge à l'écran,
      // absent des compteurs, et surtout IMPOSSIBLE À CONTESTER faute de
      // ligne à mettre à jour. Le test sur `pending` seul le manquait.
      if (words[i].locked) continue; // déjà jugé et archivé par `wordLocked`
      if (words[i].isBasmala) continue;
      if (!_motsNonJugesArchives.add(i)) continue; // déjà traité
      final verse = _verseContaining(i);
      final local = _localIndexInVerse(i);
      if (verse == null || local == null) continue;
      // ── UN PROVISOIRE VERT N'EST PAS UN « NON JUGÉ » (2026-08-11) ─────────
      //
      // Correctif du correctif ci-dessus, sur remarque utilisateur directe :
      // « il s'affiche vert à l'écran donc c'est ok, pourquoi le considérer
      // [comme une] faute ». Cas mesuré : mot لَيُنۢبَذَنَّ passé
      // `provisoire:orange` -> `provisoire:vert` sans jamais être verrouillé
      // -- `_compterMots()` (session) le compte déjà comme un vert normal
      // (il lit la COULEUR affichée, pas l'état verrouillé), et c'est le bon
      // comportement, confirmé par l'utilisateur. Ce scanner-ci neutralisait
      // AVEUGLÉMENT tout mot non verrouillé, vert compris -- deux règles
      // différentes pour la même question, sans raison de fond. La bonne
      // distinction n'est pas « verrouillé ou non », c'est « la couleur
      // affichée est-elle positive » : un provisoire ROUGE/ORANGE jamais
      // confirmé reste neutralisé (c'est lui le vrai défaut d'origine, cf.
      // le mot 20 cité plus haut) ; un provisoire VERT compte comme un mot
      // acquis normal, exactement comme le fait déjà la session.
      final status =
          words[i].status == WordStatus.correct ? 'correct' : 'skipped';
      try {
        final granularite = ref.read(portionGranularityProvider);
        final portion = await PortionService.resolve(
            verse: verse, granularity: granularite);
        await SessionArchiveService.instance.upsertPortionWord(
          surahNumber: verse.surahNumber,
          unitKey: portion.unitKey,
          label: portion.label,
          firstAyah: portion.firstAyah,
          lastAyah: portion.lastAyah,
          wordsTotal: portion.wordsTotal,
          ayahNumber: verse.ayahNumber,
          wordInAyah: local,
          expectedWord: words[i].display,
          heardWord: words[i].heard,
          status: status,
        );
      } catch (e) {
        DiagnosticLog.log(
            'Archive', 'archivage mot non juge impossible mot=$i : $e');
      }
    }
  }

  /// Archive un OUBLI : décrochage repris, ou souffleur manuel sollicité.
  ///
  /// Demande utilisateur (2026-08-09) : « quand je fais un décrochage puis je
  /// répète, malgré que j'ai bien répété ça se met en vert, mais quand même
  /// c'est un oubli à renseigner ; ou bien quand il clique sur haut-parleur
  /// pour qu'il écoute le souffleur, ça doit être considéré comme erreur ».
  ///
  /// ⚠️ DISTINCT de `_archiverMotNonVert` : celui-là attend le verdict FINAL
  /// (`wordLockedNonGreen`, qui ne se déclenche QUE si le mot reste non vert).
  /// Ici on archive IMMÉDIATEMENT, sans attendre ce verdict -- si on
  /// attendait, un mot qui redevient vert après reprise ne laisserait AUCUNE
  /// trace du lapsus, exactement le défaut signalé.
  ///
  /// `status: 'oubli'` est un troisième état de l'archive, à côté de
  /// error/unclear/correct : il ne dit rien sur la PRONONCIATION (elle peut
  /// être parfaite à la reprise), seulement qu'une aide extérieure a été
  /// nécessaire pour continuer.
  ///
  /// [avecAudio] : tentative d'extraction de la voix récitée, pertinente pour
  /// un décrochage (on veut entendre ce qui a fait perdre le fil) mais pas
  /// pour le souffleur manuel (l'anneau ne contient alors que le SILENCE qui
  /// a précédé la demande d'aide -- rien à en tirer, et ça consommerait la
  /// même fenêtre urgente qu'une vraie erreur en attente ailleurs).
  // ── UN SEUL "OUBLI" PAR ÉPISODE DE DÉCROCHAGE, PAS UN PAR SIGNAL
  // (2026-08-10) ──────────────────────────────────────────────────────────
  //
  // Constat utilisateur, capture d'écran à l'appui : le même mot ("لُّبَدًا",
  // 90:6) archivé CINQ fois de suite dans une même session. Log confirmé
  // (`recitation_diagnostic.log`, 19:06:39 à 19:07:04) : le natif [v2] fait
  // le point toutes les ~3 fenêtres hors texte ; tant que le récitateur reste
  // coincé sur le MÊME mot, il resignale un `DECROCHAGE (saut)` avec la MÊME
  // `reprise=29 "لُّبَدًا"` à chaque nouveau lot de 3 fenêtres -- quatre
  // signaux natifs pour un seul épisode réel de blocage.
  //
  // Le natif a raison de continuer à insister (c'est ce qui permet au
  // souffleur/à la reprise de fonctionner tant que le récitateur ne
  // redémarre pas) -- le défaut n'est PAS dans la détection, il est dans
  // L'ARCHIVAGE : cette méthode n'avait aucune mémoire du dernier mot déjà
  // consigné, donc chaque signal redondant devenait une ligne d'historique
  // séparée, gonflant artificiellement le nombre d'erreurs affiché.
  //
  // Le garde-fou vit ICI (la seule fois où l'app écrit dans l'historique),
  // pas côté natif : `_dernierMotArchiveOubli` ne bloque qu'un DOUBLON
  // immédiat sur le MÊME mot -- un vrai nouvel oubli sur ce mot, plus tard
  // dans la session après qu'un autre mot ait progressé, sera de nouveau
  // archivé normalement (la variable aura changé entre-temps).
  int? _dernierMotArchiveOubli;

  Future<void> _archiverOubli(int wordIndex, {bool avecAudio = false}) async {
    if (_isReferenceSession) return;
    if (_dernierMotArchiveOubli == wordIndex) return;
    _dernierMotArchiveOubli = wordIndex;
    final words = ref.read(recitationProvider).words;
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final mot = words[wordIndex];
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    if (verse == null || local == null) return;

    // Coach hub (stats cumulées, `RecitationErrorLogService`) : kind FORCÉ à
    // `oubli`, jamais `classifyError()` -- ce dernier compare attendu/entendu
    // pour qualifier une MAUVAISE PRONONCIATION, question qui ne se pose pas
    // ici (le mot n'a pas été mal dit, il a fallu de l'aide pour le dire).
    RecitationErrorLogService.instance.logError(
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      wordIndex: local,
      expectedWord: mot.display,
      kind: RecitationErrorKind.oubli,
    );

    if (SessionArchiveService.instance.sessionCourante == null) return;
    String? extrait;
    if (avecAudio) {
      try {
        extrait = await ref
            .read(recitationVerifierProvider)
            .v2ExtraitVoix(wordIndex > 0 ? wordIndex - 1 : wordIndex, wordIndex);
      } catch (e) {
        DiagnosticLog.log(
            'Archive', 'extrait voix (oubli) impossible mot=$wordIndex : $e');
      }
    }
    await SessionArchiveService.instance.archiverMot(
      wordIndex: wordIndex,
      expectedWord: mot.display,
      status: 'oubli',
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      wordInAyah: local,
      kind: 'oubli',
      audioSource: extrait,
    );
  }

  DateTime? _dernierBilan;

  /// Bilan intermédiaire, au plus une fois toutes les 10 s (cf. l'appelant).
  void _majBilanPeriodique() {
    if (SessionArchiveService.instance.sessionCourante == null) return;
    final maintenant = DateTime.now();
    if (_dernierBilan != null &&
        maintenant.difference(_dernierBilan!).inSeconds < 10) {
      return;
    }
    _dernierBilan = maintenant;
    final (total, verts, atteints, nonJuges) = _compterMots();
    SessionArchiveService.instance.majBilan(
      wordsTotal: total,
      wordsGreen: verts,
      wordsReached: atteints,
      wordsSkipped: nonJuges,
    );
    unawaited(_archiverMotsNonJugesDansPortions());
  }

  /// (total, verts, atteints, nonJuges) — LE DÉNOMINATEUR EST L'ANCRE MAX,
  /// pas la cible ni le nombre de mots jugés. S'arrêter au milieu d'une
  /// sourate n'est pas une faute ; et compter sur les mots jugés fait
  /// *baisser* le taux d'erreur à chaque mot que la chaîne perd (piège mesuré
  /// le 2026-07-29 : un correctif passait de 7,22 % à 3,45 % en sautant
  /// 9 mots que la version précédente jugeait verts — lu sur l'ancre max, il
  /// montait à 13,40 %).
  ///
  /// `nonJuges` (2026-08-11) est rendu À CÔTÉ de ces trois-là, sans les
  /// modifier : il sert au taux montré à l'utilisateur (un mot que la chaîne
  /// n'a pas su figer ne le pénalise pas) tout en laissant le diagnostic lire
  /// les chiffres bruts. Cf. le bloc de commentaire dans le corps.
  (int, int, int, int) _compterMots() {
    // `_dernierEtatConnu` (mis à jour à chaque `build`, cf. sa doc) plutôt
    // que `ref.read(recitationProvider)` : cette méthode est appelée depuis
    // `dispose()`, où `ref` n'est plus fiable (cf. le commentaire du champ).
    // Fallback sur `ref.read` seulement si jamais aucun build n'a encore eu
    // lieu (ne devrait pas arriver ici, mais reste correct sans dépendre de
    // l'ordre d'initialisation).
    final RecitationSessionState etat =
        _dernierEtatConnu ?? ref.read(recitationProvider);
    final words = etat.words;
    // `current` EXCLU, pas seulement `pending` (corrigé 2026-08-06 sur la
    // mesure) : `current` est le mot que le défilement suit, il n'a reçu aucun
    // verdict. Le compter gonflait le dénominateur d'une unité --
    // `words_reached = 296` en base pour une ancre réelle de 295, mesuré sur
    // la recette déterministe. Un mot jamais jugé n'a rien à faire dans un
    // taux de réussite.
    final ancreMax = words.lastIndexWhere((w) =>
            w.status != WordStatus.pending && w.status != WordStatus.current) +
        1;
    // ── LA BISMILLAH EXCLUE DU TAUX (2026-08-09, constat utilisateur : « 70 %
    // alors qu'un seul mot en erreur ») ────────────────────────────────────
    //
    // `ancreMax` marque la DERNIÈRE position jugée, pas une plage sans trou :
    // la Bismillah (mots 0..3) est structurellement `pending` pour toujours
    // (décision 2026-07-20, « jamais jugée »), mais dès qu'un vrai mot PLUS
    // LOIN dans le texte est jugé, elle se retrouve comprise dans la plage
    // `0..ancreMax` -- la boucle ci-dessous la comptait alors comme « atteinte
    // mais pas verte », en plein milieu d'une plage par ailleurs correcte.
    // Sur une courte sourate (peu de mots au dénominateur), 4 mots jamais
    // jugés suffisent à faire chuter le taux très fort pour une seule vraie
    // faute.
    //
    // Un mot que le produit a explicitement choisi de ne jamais juger n'est
    // ni un succès ni un échec : il sort des deux compteurs, numérateur et
    // dénominateur.
    // ── LES MOTS QUE LA CHAÎNE N'A PAS SU JUGER SONT COMPTÉS À PART
    // (2026-08-11, règle utilisateur) ──────────────────────────────────────
    //
    // « les mots non jugés dans récitation ne doivent pas pénaliser, ils
    // doivent être jugés justes dans le pourcentage [...] on part du 100 % et
    // on enlève les mots en erreur ». Un mot que l'ancre a dépassé sans
    // verdict figé (jamais `locked` : soit resté `pending`, soit un
    // `provisoire:*` que le Décideur n'a pas confirmé) est un défaut de
    // l'application, pas une faute du récitateur -- il ne doit rien lui
    // coûter. Même règle que côté portion (`PortionResume.reussite`).
    //
    // ⚠️ LE COMPTEUR DE DIAGNOSTIC EST PRÉSERVÉ, c'est tout l'objet du
    // TROISIÈME retour. Le piège du 2026-07-29 rappelé ci-dessus reste
    // entier : si un mot perdu SORTAIT du dénominateur, une chaîne qui casse
    // afficherait un meilleur taux (mesuré : 7,22 % -> 3,45 % en sautant
    // 9 mots verts, alors que la vérité était 13,40 %). On ne touche donc NI
    // `comptes` (toujours l'ancre max, Bismillah exclue) NI `verts`
    // (toujours les seuls mots réellement jugés corrects) : le non-jugé est
    // rendu SÉPARÉMENT et stocké dans sa propre colonne, ce qui laisse les
    // deux lectures possibles -- celle de l'utilisateur (« ça ne me pénalise
    // pas ») et celle du diagnostic (« la chaîne a perdu N mots »).
    var verts = 0;
    var comptes = 0;
    var nonJuges = 0;
    for (var i = 0; i < ancreMax; i++) {
      if (words[i].isBasmala) continue;
      comptes++;
      if (words[i].status == WordStatus.correct) {
        verts++;
      } else if (!words[i].locked) {
        nonJuges++;
      }
    }
    return (words.length, verts, comptes, nonJuges);
  }

  /// Clôt l'archive de la session avec son bilan.
  ///
  /// LE DÉNOMINATEUR EST L'ANCRE MAX, PAS LA CIBLE. S'arrêter au milieu d'une
  /// sourate n'est pas une faute : diviser par la cible ferait passer une
  /// récitation juste pour mauvaise. Et ce n'est pas non plus le nombre de
  /// mots JUGÉS -- compter là-dessus fait *baisser* le taux d'erreur à chaque
  /// mot perdu par la chaîne (piège mesuré le 2026-07-29 : un correctif
  /// passait de 7,22 % à 3,45 % en sautant 9 mots que la version précédente
  /// jugeait verts ; lu sur l'ancre max, il montait à 13,40 %).
  ///
  /// Appelé à la fin naturelle ET à la sortie d'écran : sans `ended_at`, la
  /// session resterait invisible dans le Coach.
  Future<void> _cloturerArchive() async {
    if (SessionArchiveService.instance.sessionCourante == null) return;
    final (total, verts, atteints, nonJuges) = _compterMots();
    await SessionArchiveService.instance.terminer(
      wordsTotal: total,
      wordsGreen: verts,
      wordsReached: atteints,
      wordsSkipped: nonJuges,
    );
    // Derniers mots que l'ancre a dépassés sans jugement, avant de fermer --
    // cf. `_archiverMotsNonJugesDansPortions`. Sans cet appel ici, un mot
    // tombé dans ce trou pendant les 10 dernières secondes (fenêtre du
    // throttle périodique) ne serait jamais rattrapé.
    await _archiverMotsNonJugesDansPortions();
    // Cf. le même correctif dans dispose() -- ici l'écriture est ATTENDUE,
    // donc l'invalidation après coup est sans ambiguïté d'ordre.
    if (mounted) {
      ref.invalidate(sessionsArchiveProvider);
      ref.invalidate(tailleArchiveProvider);
      ref.invalidate(portionsProvider);
    }
  }

  /// [surSilence] : appelé par le décrochage v2 (§_decrochageSub), pas
  /// par le flux `wordFailed` -- le récitateur a quitté le texte ou un trou
  /// persiste, on lui souffle le mot même si un seul mot est en échec.
  Future<void> _onWordFailed(
    int wordIndex, {
    bool surSilence = false,
    // ORIGINE DU DÉCLENCHEMENT (2026-08-05, demande utilisateur : pouvoir
    // répondre "pourquoi la correction est partie" en LISANT le log, sans
    // relire le code). Les trois appelants passent une valeur explicite --
    // cf. la ligne 'wordFailed déclenché' plus bas, seul endroit où c'est
    // journalisé, juste avant que l'audio parte réellement.
    String raison = '(non précisée)',
  }) async {
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
    // ── LE RÉGLAGE NE COUPE QUE LES ERREURS, JAMAIS LE DÉCROCHAGE ────────
    //
    // Spécification utilisateur (2026-08-06) : « quand c'est désactivé, il n'y
    // a pas de blocage SAUF en cas de décrochage, qui reste tout le temps
    // actif ». Le décrochage n'est pas une erreur de prononciation : c'est le
    // récitateur qui a quitté le texte ou s'est arrêté — l'application ne peut
    // plus rien lui dire d'utile tant qu'elle ne l'a pas retrouvé.
    //
    // Avant ce correctif, ce garde-fou barrait AUSSI `surSilence`, donc le
    // décrochage ne partait jamais dès qu'on décochait la correction — alors
    // que c'est justement le cas où l'aide est indispensable.
    // ── LA CORRECTION SUR ERREUR ISOLEE EST RETIREE (2026-08-07) ──────────
    //
    // Decision utilisateur : « enleve-moi ce mode, en restant sur audio en cas
    // de decrochage seulement ».
    //
    // POURQUOI, ET C'EST UNE RAISON STRUCTURELLE, PAS UN REGLAGE : le verdict
    // arrive 4 a 8 s apres le mot -- 4 s de fenetre d'analyse, plus souvent
    // une seconde fenetre pour verrouiller (k=2 observations concordantes).
    // En 4 a 8 s le recitant a dit 8 a 15 mots de plus. Interrompre porte donc
    // TOUJOURS sur du passe : « vu le delai, il sera moins utile, il va
    // generer de la frustration, pas plus ».
    //
    // Mesures du jour qui l'illustrent : correction jouee sur `مُصْلِحُونَ`
    // alors que la fenetre suivante le validait 500 ms plus tard ; correction
    // jouee sur un mot dont l'application venait elle-meme d'ecrire
    // `status=WordStatus.correct` 5 ms plus tot.
    //
    // CE QUI RESTE : le DECROCHAGE (`surSilence`), c'est-a-dire le cas ou le
    // recitant a perdu le fil -- la, le delai ne coute rien puisqu'il ne
    // recite plus. Et rien n'est perdu de ce qu'on n'interrompt plus : les
    // verdicts ET la voix de chaque mot non vert sont archives (Coach), donc
    // revisables a froid.
    //
    // Le journal d'erreurs ci-dessus est deliberement AVANT ce point : on
    // continue d'enregistrer tout ce qu'on ne dit plus.
    if (!surSilence) {
      DiagnosticLog.log('Correction',
          'mot $wordIndex : erreur isolee, aucune interruption (mode retire '
          'le 2026-08-07 -- le verdict arrive 4 a 8 s trop tard). Le mot reste '
          'colore et archive pour revue dans le Coach.');
      return;
    }
    // Jamais de correction pendant une récitation de RÉFÉRENCE (demande
    // utilisateur 2026-07-06) : ce moment sert uniquement à observer le
    // rythme naturel du réciteur (pauses, tempo) pour PauseProfileService —
    // l'interrompre pour corriger fausserait justement ce qu'on cherche à
    // mesurer.
    if (_isReferenceSession) {
      DiagnosticLog.log('Correction',
          'IGNORÉ mot $wordIndex : session de référence');
      return;
    }
    // Strict/tolérant (demande utilisateur 2026-07-06) : en mode tolérant,
    // seul le rouge (mot faux) déclenche la correction — l'orange (mot
    // reconnu mais imprécis) est accepté sans interruption.
    // (Ne s'applique pas au déclencheur "silence" : le mot n'y est pas encore
    // jugé du tout -- le récitateur ne l'a simplement jamais dit.)
    final words = ref.read(recitationProvider).words;
    if (!surSilence &&
        wordIndex < words.length &&
        words[wordIndex].status != WordStatus.error &&
        !ref.read(strictCorrectionProvider)) {
      return;
    }
    // ── NE JAMAIS REVENIR EN ARRIÈRE (2026-08-01) ─────────────────────────
    // Un `wordFailed` peut arriver EN RETARD, sur un mot que le récitateur a
    // déjà dépassé -- la v2 juge par fenêtres et ses verdicts remontent avec
    // du décalage. Mesure sur device :
    //     19:39:42.008 [Attente] minuteur armé sur le mot 12   <- position réelle
    //     19:39:42.014 wordFailed déclenché : mot 10 "هُدًى"    <- 6 ms plus tard
    //     19:39:42.161 Correction-Audio fromIdx=5 toIdx=6      -> هُدًى لِّلْمُتَّقِينَ
    // L'utilisateur venait de dire ces deux mots, ils étaient validés, et on
    // les lui rejouait : « j'ai bien dit hudan lil muttaqin, il me le corrige ;
    // moi j'ai arrêté pour qu'il me dise les mots SUIVANTS ».
    // On ignore donc tout signal portant sur un mot situé DERRIÈRE celui que
    // la v2 suit. Corriger le passé n'a aucun intérêt : ce qui aide, c'est la
    // suite.
    final suiviMaintenant =
        words.indexWhere((w) => w.status == WordStatus.current);
    // ── UN DECROCHAGE SE REPETE TOUJOURS (2026-08-07) ─────────────────────
    //
    // Une premiere version ignorait ici un decrochage designant un mot situe
    // plus de 3 mots en arriere, pour eviter de faire repeter du passe. RETIRE
    // le jour meme, sur precision de l'utilisateur : « decrochage, c'est
    // forcement on repete, avec audio ».
    //
    // Et il a raison sur le fond : ce filet faisait DOUBLE EMPLOI avec la
    // correction posee a la source (`ChaineRecitation` : une fenetre qui se
    // localise efface l'alerte). Les decrochages perimes n'arrivent donc plus
    // jusqu'ici ; ceux qui arrivent sont reels, et un vrai decrochage doit
    // toujours etre souffle -- le recitant a perdu le fil, c'est le seul
    // moment ou le delai ne coute rien puisqu'il ne recite plus.
    //
    // Filtrer une seconde fois EN AVAL aurait etouffe de vrais decrochages :
    // exactement le palliatif que le projet interdit (corriger la ou le defaut
    // se VOIT et non la ou il NAIT).
    if (!surSilence && suiviMaintenant >= 0 && wordIndex < suiviMaintenant) {
      DiagnosticLog.log('Correction',
          'signal en retard sur le mot $wordIndex alors que le récitateur en '
          'est au mot $suiviMaintenant -> ignoré (on ne rejoue pas le passé)');
      return;
    }
    // ── DÉCROCHAGE, PAS FAUTE ISOLÉE (2026-08-01) ─────────────────────────
    // AVANT : chaque mot rouge isolé déclenchait pause + audio + recul de
    // l'ancre. Or la mesure de référence du projet (2026-07-28,
    // `verifier_erreurs.py` sur 125 mots jugés : 8 non verts, 0 vraie
    // erreur) dit que la quasi-totalité des rouges isolés sont des faux
    // positifs de la CHAÎNE, pas des fautes du récitateur -- interrompre
    // dessus casse une récitation par ailleurs juste.
    //
    // Demande utilisateur : « quand le récitateur décroche, et non l'arrêter
    // à chaque faux positif ou une faute de haraka ». On ne bloque donc plus
    // que sur les deux signes d'un VRAI décrochage :
    //   (a) DEUX mots consécutifs en échec -- un récitateur parti sur un
    //       autre verset/une autre sourate produit une rafale, jamais un
    //       accident isolé ; un faux positif de chaîne ou une harakat
    //       approximative reste, lui, isolé ;
    //   (b) un DÉCROCHAGE v2 (cf. `_decrochageSub`) -- texte hors sujet ou
    //       trou persistant sur deux fenêtres, signalé par la chaîne Kotlin.
    // Les autres mots non verts ne bloquent plus : ils gardent leur couleur,
    // restent consultables après coup (tap sur le mot -> souffleur).
    // ── RÈGLE DES DEUX MOTS CONSÉCUTIFS : RETIRÉE (2026-08-06) ──────────
    //
    // Elle vivait ici et disait : un mot non vert ISOLÉ ne bloque pas, il faut
    // que le précédent soit lui aussi en échec.
    //
    //     final precedent = wordIndex - 1;
    //     final precedentEnEchec = ... error || skipped ...
    //     if (!precedentEnEchec) return;
    //
    // POURQUOI ELLE AVAIT ÉTÉ POSÉE (2026-08-01), et ça reste vrai : mesure du
    // 2026-07-28 (verifier_erreurs.py, 125 mots jugés) -- 8 mots non verts,
    // ZÉRO vraie erreur. Les rouges isolés sont très majoritairement des faux
    // positifs de la chaîne, et interrompre dessus est insupportable.
    //
    // POURQUOI ELLE EST RETIRÉE. Spécification utilisateur (2026-08-06) :
    // « j'ai activé la correction automatique, donc il aurait dû me bloquer à
    // CHAQUE erreur ; quand c'est désactivé il n'y a pas de blocage sauf en cas
    // de décrochage ». La règle décidait à la place de l'utilisateur : cocher
    // « correction automatique » veut dire « reprends-moi », pas « reprends-moi
    // une fois sur deux ». Le réglage retrouve son sens littéral, et celui qui
    // ne veut pas être interrompu le décoche -- le décrochage continuant de le
    // rattraper (cf. le garde-fou plus haut, qui ne barre plus `surSilence`).
    //
    // ⚠️ SI LES INTERRUPTIONS SUR FAUX POSITIFS REVIENNENT, la réponse n'est
    // PAS de remettre cette règle : c'est de réduire les faux positifs. Les
    // remettre reviendrait à masquer le défaut au lieu de le traiter, et à
    // reprendre à l'utilisateur une décision qu'il a explicitement demandée.
    // Bug corrigé 2026-07-16 (revue de code, Finding #4) : ce guard ne
    // vérifiait que _autoCorrecting, pas _promptingWord (souffleur) -- les
    // deux flux appellent pauseCapture()/WordCorrectionAudio.playWordRange()
    // sur le MÊME lecteur audio statique ; un mot qui échoue pendant que le
    // souffleur joue lançait une correction en parallèle, les deux jeux
    // d'abonnements posSub/doneSub s'entrechoquant.
    // ⚠️ CES RETOURS ÉTAIENT SILENCIEUX (2026-08-05) : un décrochage pouvait
    // être signalé par le natif puis mourir ici sans une seule ligne de log.
    // Mesuré : 1ʳᵉ correction complète, 2ᵉ décrochage signalé mais AUCUN
    // `wordFailed déclenché` ni `Correction-Audio` derrière.
    if (_autoCorrecting || _promptingWord) {
      DiagnosticLog.log('Correction',
          'IGNORÉ mot $wordIndex : action déjà en cours '
          '(_autoCorrecting=$_autoCorrecting _promptingWord=$_promptingWord)');
      return; // un mot/une action a la fois
    }
    // Anti-rafale (demande utilisateur 2026-07-06 : "il me donne pas le temps
    // pour répéter") -- constaté en test réel : quand la reconnaissance
    // décroche (bruit/silence mal interprété), plusieurs mots peuvent
    // s'abandonner en cascade en quelques secondes, chacun redéclenchant sa
    // propre correction automatique dos à dos, sans jamais laisser de vraie
    // fenêtre de silence pour répéter. Un délai minimum entre deux
    // corrections force cette fenêtre, quelle que soit la cause exacte de la
    // cascade côté reconnaissance.
    final cooldown = _correctionCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      DiagnosticLog.log('Correction',
          'IGNORÉ mot $wordIndex : anti-rafale actif jusqu\'à $cooldown');
      return;
    }
    final verse = _verseContaining(wordIndex);
    final local = _localIndexInVerse(wordIndex);
    if (verse == null || local == null) {
      DiagnosticLog.log('Correction',
          'IGNORÉ mot $wordIndex : position introuvable '
          '(verset=${verse?.key} local=$local) -- mot hors des versets chargés '
          'ou dans la Bismillah');
      return;
    }
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
    // Exception `surSilence` (2026-08-01) : sur un silence, le mot courant
    // n'a AUCUN jugement (le récitateur ne l'a jamais dit) -- il est `current`
    // ou `pending`, ce qui ferait abandonner ce garde-fou alors que c'est
    // précisément le cas où il faut souffler.
    final current =
        wordIndex < words.length ? words[wordIndex].status : WordStatus.pending;
    if (!surSilence &&
        current != WordStatus.error &&
        current != WordStatus.unclear &&
        current != WordStatus.skipped) {
      DiagnosticLog.log('Correction',
          'ABANDON : le mot $wordIndex est repasse a $current avant la correction');
      return;
    }
    DiagnosticLog.log('Correction', 'wordFailed déclenché : raison=$raison '
        'wordIndex(global)=$wordIndex '
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
      // ── PAS DE RECUL D'ANCRE QUAND LA v2 PILOTE (2026-08-01) ─────────────
      // `rewindAndUnlock` agit sur l'ancre et les verdicts de la v1. Or la v1
      // est COUPÉE dès que la v2 pilote (`v1Coupee` dans le plugin) : son
      // ancre reste figée là où elle s'est arrêtée, très en arrière de la
      // position réelle. La reculer encore faisait remonter l'affichage mot
      // par mot en arrière -- défaut signalé par l'utilisateur, visible dans
      // le log : `[ANCRE] recul 7 -> 6`, puis `6 -> 5`, puis `5 -> 4`, alors
      // que la v2 en était au mot 16.
      // La v2 n'a pas besoin de ce recul : elle réestime sa position à chaque
      // fenêtre depuis l'acoustique, et sait déjà suivre un récitateur qui
      // reprend en arrière (`bande.recul`).
      if (!notifier.v2PiloteAffichage) {
        notifier.rewindAndUnlock(rewindTo);
      }
      // ── L'ANCRE DE LA v2 RECULE, ELLE (2026-08-07) ──────────────────────
      //
      // Le commentaire ci-dessus reste VRAI et n'est pas contredit : reculer
      // l'ancre de la V1 pendant que la v2 pilote faisait remonter l'affichage
      // a l'envers, et la v2 sait effectivement suivre un recitant qui reprend
      // en arriere (`bande.recul`). Rien de tout cela ne change.
      //
      // CE QUI CHANGE, ET POURQUOI CE N'EST PAS LA MEME CHOSE : la
      // specification utilisateur du 2026-08-07 ne demande pas de SUIVRE le
      // recitant -- ca, la v2 le fait deja. Elle demande de L'ATTENDRE :
      // « repeter depuis ce decrochage et attendre que la personne repete ».
      // Or attendre n'a de sens que si les mots concernes peuvent etre
      // REJUGES ; tant qu'ils restent figes dans le Decideur, la repetition
      // ne produirait aucun verdict et l'attente serait decorative.
      //
      // `reculerAncre` fait exactement cela et rien de plus : il oublie les
      // verdicts POSTERIEURS au point de reprise (ceux d'avant restent
      // acquis) et redescend le point de recherche. Il ne recree pas la
      // chaine -- ce qui aurait efface toute la session.
      //
      // SORTIES DE L'ATTENTE, faute de reponse a la question posee : il n'y a
      // pas de minuteur de blocage. La chaine continue d'ecouter ; si le
      // recitant ne reprend pas et poursuit plus loin, le localisateur le
      // retrouve et l'ancre repart d'elle-meme. L'attente ne peut donc pas
      // figer l'application -- c'est le choix le plus sur tant que le
      // comportement voulu n'est pas tranche.
      //
      // JAMAIS EN SUIVI DE PRIERE : `ChaineRecitation.reculerAncre` refuse de
      // lui-meme quand `sautLibre` est actif.
      unawaited(ref.read(recitationVerifierProvider).v2ReculerAncre(rewindTo));
      DiagnosticLog.log('Correction',
          'ancre v2 reculee au mot $rewindTo -- les verdicts posterieurs sont '
          'liberes, le passage peut etre repris et rejuge');
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
            // DEUX SITUATIONS, DEUX AUDIOS (2026-08-01) :
            //
            //  - CORRECTION d'une faute : on redit le mot précédent PUIS le
            //    mot fautif (`_kCorrectionWordsBefore`), pour que le
            //    récitateur reprenne avec l'élan et se réentende dessus.
            //
            //  - BLOCAGE (silence, décrochage) : il faut lui donner LA SUITE.
            //    Rejouer le mot d'avant serait lui répéter ce qu'il vient de
            //    dire correctement -- défaut signalé par l'utilisateur :
            //    « j'ai dit هُدًى لِّلْمُتَّقِينَ et l'audio me répète les deux
            //    mots que je viens de dire alors qu'ils sont bien jugés ; il
            //    fallait me dire la suite ». On part donc du premier mot NON
            //    validé (déjà calculé par l'appelant) et on en donne deux.
            wordsBefore: surSilence ? 0 : _kCorrectionWordsBefore,
            wordsAfter: 1);
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
      if (!widget.sansBasmala && _bismillahBefore(v, prevSurah)) {
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
  /// Table PRECALCULEE mot -> verset, et ensemble des indices de fin de verset.
  ///
  /// ── POURQUOI ELLE EXISTE (2026-07-27) ────────────────────────────────────
  /// `_verseContaining` parcourait TOUS les versets et REDECOUPAIT le texte
  /// arabe de chacun (`splitExpectedWords`) a chaque appel. Or le rendu appelle
  /// `_isLastWordOfVerse` pour CHAQUE mot, et celui-ci appelle
  /// `_verseContaining` DEUX fois. Sur une page de 246 mots et ~30 versets :
  ///     246 mots x 2 appels x 30 versets ~ 15 000 decoupages de chaine arabe
  /// a chaque reconstruction de l'ecran -- et l'ecran se reconstruit a chaque
  /// payload d'alignement, soit toutes les ~1,5 s.
  ///
  /// Ce n'est pas qu'un probleme de confort (« l'ecran est lourd, le scroll ne
  /// repond pas », constat utilisateur) : les allers-retours MethodChannel qui
  /// alimentent le natif en PCM reviennent par le THREAD PRINCIPAL, celui-la
  /// meme qui execute ces decoupages. Un rendu lourd retarde donc l'audio --
  /// c'est le mecanisme qui avait produit une file de 35 s le matin meme.
  ///
  /// Ici : construite UNE fois quand le texte change, puis acces en O(1).
  List<Verse?> _verseByWord = const [];
  List<int?> _surahByWord = const [];
  Set<int> _lastWordOfVerse = const {};

  void _rebuildWordVerseMap() {
    final map = <Verse?>[];
    final sur = <int?>[];
    final last = <int>{};
    // Index du mot DANS son verset, rempli dans la meme passe (2026-08-13).
    // `_localIndexInVerse` reparcourt tous les versets a chaque appel : sur
    // une relecture il est appele une fois par mot, d'ou un cout qui grimpe
    // avec le produit mots x versets. Mesure : 343-367 ms pour 335 mots sur
    // 25 versets, contre 42 ms pour 40 mots sur 5 versets.
    final loc = <int?>[];
    int? prevSurah;
    for (final v in _verses) {
      if (_bismillahBefore(v, prevSurah)) {
        for (var k = 0; k < _bismillahWordCount; k++) {
          map.add(null); // dans la Bismillah elle-meme
          sur.add(v.surahNumber); // ... mais elle APPARTIENT a cette sourate
          loc.add(null);
        }
      }
      prevSurah = v.surahNumber;
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      for (var k = 0; k < count; k++) {
        map.add(v);
        sur.add(v.surahNumber);
        loc.add(k);
      }
      if (count > 0) last.add(map.length - 1);
    }
    _verseByWord = map;
    _surahByWord = sur;
    _localByWord = loc;
    _lastWordOfVerse = last;
  }

  Verse? _verseContaining(int wordIndex) {
    // Table precalculee (cf. _rebuildWordVerseMap). Repli sur le calcul
    // d'origine si elle n'est pas encore prete -- jamais de resultat different,
    // seulement plus lent.
    if (wordIndex >= 0 && wordIndex < _verseByWord.length) {
      return _verseByWord[wordIndex];
    }
    return _verseContainingSlow(wordIndex);
  }

  Verse? _verseContainingSlow(int wordIndex) {
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
    // O(1) depuis la table precalculee -- meme motif et meme raison que
    // _verseContaining : cette fonction etait appelee pour CHAQUE mot a chaque
    // reconstruction, en reparcourant tous les versets a chaque appel.
    if (wordIndex >= 0 && wordIndex < _surahByWord.length) {
      return _surahByWord[wordIndex];
    }
    return _surahOwningSlow(wordIndex);
  }

  int? _surahOwningSlow(int wordIndex) {
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
  /// Table precalculee des index locaux (cf. `_rebuildWordVerseMap`).
  List<int?> _localByWord = const [];

  int? _localIndexInVerse(int wordIndex) {
    // Table d'abord, calcul complet en repli -- meme resultat, jamais
    // different, seulement plus lent (meme principe que `_verseContaining`).
    if (wordIndex >= 0 && wordIndex < _localByWord.length) {
      return _localByWord[wordIndex];
    }
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
  /// référence. TOUJOURS FAUX depuis le 2026-08-05 : ce getter calculait la
  /// condition (pas de profil dédié, profil global pas stable) qui menait
  /// autrefois au dialogue « référence ou correction ? ». Ce dialogue a été
  /// retiré (cf. le commentaire sur `_isReferenceSession` dans `_toggle` :
  /// « LA REFERENCE QUITTE L'INTERFACE, PAS LE PROJET ») -- toute récitation
  /// lancée depuis cet écran est désormais NORMALE, sans exception.
  ///
  /// BUG CORRIGÉ (constat utilisateur : « il y a toujours un message sur la
  /// récitation de référence sur la page de récitation ») : ce getter n'avait
  /// pas été mis à jour lors du retrait du dialogue, donc le bandeau
  /// `_referenceBanner` et l'indication `_bottomHint` continuaient d'annoncer
  /// une session de référence qui ne se produirait jamais -- vrai dès qu'un
  /// passage n'avait pas encore de profil de pauses dédié, donc quasiment
  /// toujours. Cf. `_isReferenceSession` pour le mode réellement fonctionnel,
  /// qui reste accessible au banc de recette via `autoDemarrer`.
  bool get _willBeReferenceSession => false;

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
          // Cloisonnement 2026-08-05 : deux points d'entrée distincts au lieu
          // d'un paramètre booléen -- cf. la doc de startControle/startTest
          // dans recitation_provider.dart.
          return _isReferenceSession
              ? notifier.startTest()
              : notifier.startControle();
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
      // ── MESSAGE EXPLICITE (2026-08-09, demande utilisateur) ──────────────
      // « les messages d'erreur [doivent être] explicites, exemple absence
      // du modèle IA : donner le nom du modèle ». Le texte traduit générique
      // reste la première ligne (compréhensible sans connaître le projet) ;
      // le détail technique de `verifier.dernierEchecChargementModele`
      // (nom du modèle attendu, fichier manquant, chemin) s'ajoute EN DESSOUS
      // quand il existe -- c'est lui qui dit quoi repousser et où, au lieu de
      // devoir relire le code pour le retrouver (ce qui vient de coûter du
      // temps réel, cf. le modèle effacé par erreur le même jour).
      final detail = verifier.dernierEchecChargementModele;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: detail == null
              ? const Duration(seconds: 4)
              : const Duration(seconds: 8),
          content: Text(detail == null
              ? AppLocalizations.of(context)!.karaokeModelUnavailable
              : '${AppLocalizations.of(context)!.karaokeModelUnavailable}\n$detail'),
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

  /// Attend que la session soit réellement prête, puis emprunte le MÊME chemin
  /// que le tap. Deux conditions, pour ne pas démarrer dans le vide :
  /// la cible d'alignement doit être chargée (`words`), et la vérification de
  /// profil doit avoir répondu (`_hasProfile`) — sinon la session de référence
  /// n'est pas marquée comme telle et rien n'est enregistré (bug du 2026-07-05).
  Future<void> _autoDemarrage() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final st = ref.read(recitationProvider);
      if (st.words.isNotEmpty && _hasProfile != null) {
        if (st.status == RecitationStatus.listening) return;
        DiagnosticLog.log('RECETTE',
            'demarrage automatique (${st.words.length} mots, profil=$_hasProfile)');
        await _toggle(st, ref.read(recitationProvider.notifier));
        return;
      }
    }
    DiagnosticLog.log('RECETTE',
        'demarrage automatique ABANDONNE : session pas prete apres 15 s');
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
      // ── LA FIN RÉELLE D'UNE RÉCITATION, C'EST ICI (2026-08-06) ──────────
      //
      // DÉFAUT MESURÉ dès le premier essai de l'utilisateur : « j'ai effectué
      // une récitation, dans Coach aucune récitation n'est enregistrée ».
      // Vérifié dans la base du téléphone, pas déduit :
      //     sessions -> (1, '2026-08-06T22:41:13', ended_at=NULL, sourate 113)
      //     session_words -> 0
      // La session était donc bien ouverte ; elle n'a jamais été FERMÉE, et la
      // liste du Coach ne montre que `ended_at IS NOT NULL`.
      //
      // CAUSE : je n'avais branché la clôture que sur `RecitationStatus
      // .finished` et sur `dispose()`. Or la fin ordinaire d'une récitation,
      // c'est le tap sur le halo -- ce chemin-ci -- et il ne passe par aucun
      // des deux : le log s'arrête sur `pauseCapture() | micro en pause`, sans
      // rien après. Les deux hooks d'origine restent en place (fin
      // automatique, sortie d'écran), celui-ci est le chemin normal.
      await _cloturerArchive();
    } else if (st.status != RecitationStatus.processing) {
      _profileSaved = false;
      // Repère "reprends ici" (2026-08-05) : sans ce nettoyage, un repère posé
      // par une correction d'une session ANTÉRIEURE restait affiché sur un mot
      // qui n'a plus jamais été rejugé depuis -- mesuré sur device, souligné
      // sur "ذَٰلِكَ" alors que le journal natif de la nouvelle session n'avait
      // jugé aucun mot au-delà de la Bismillah. Le repère ne s'efface que
      // "quand ce mot reçoit un jugement" (cf. ligne plus bas) ; si ça
      // n'arrive plus jamais, il ne partait jamais tout seul.
      if (_resumeHintIndex != null) setState(() => _resumeHintIndex = null);
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
      if (widget.autoDemarrer) {
        // Banc de recette : le dialogue « référence ou correction ? » attend un
        // tap et bloque le démarrage automatique — c'est ce qui faisait
        // s'arrêter la session juste après `demarrage automatique` dans le log,
        // sans rien d'autre pour le dire. Le banc impose le mode RÉFÉRENCE :
        // c'est celui qu'on mesure (pas de correction, donc pas de recul
        // d'ancre qui viendrait masquer un défaut d'alignement).
        // SAUF `forcerModeNormal` (2026-08-05) : mesure ponctuelle pour
        // verifier un audio deterministe sous SAUT REFUSE/decrochage.
        _isReferenceSession = !widget.forcerModeNormal;
      } else {
        // ── LA REFERENCE QUITTE L'INTERFACE, PAS LE PROJET (2026-08-05) ────
        //
        // Demande utilisateur : « enleve la recitation de reference, la
        // finalite de l'app ne va pas l'utiliser -- mais tu peux la garder
        // pour toi comme un chemin de recette », et la raison qu'il en donne
        // est la bonne : « elle ne demande pas la repetition ». Un mode qui
        // n'interrompt jamais et ne fait jamais redire un mot n'apprend rien
        // a personne -- l'app existe pour corriger, pas pour constater.
        //
        // ⚠️ LE MODE RESTE ENTIEREMENT FONCTIONNEL, et il le doit : c'est
        // l'instrument qui dit QUI a tort. Le 2026-08-05, deux signalements
        // (un violet sur `حولهۥ`, un rouge sur `أبصارهم`) n'ont pu etre
        // qualifies de faux positifs QUE parce que l'audio venait d'un
        // recitateur professionnel, donc forcement juste. Avec la voix de
        // l'utilisateur, les deux cas restaient indecidables.
        //
        // Seule la QUESTION posee a l'utilisateur disparait. Le banc l'active
        // par `widget.autoDemarrer` (branche ci-dessus), et c'est desormais le
        // SEUL chemin qui y mene -- ce qui garantit aussi qu'aucune session
        // ordinaire ne tombe dedans par accident, ce que le dialogue rendait
        // possible des que le profil de pauses etait absent.
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
        // ── ARCHIVE DE SESSION (2026-08-06) ──────────────────────────────
        // Ouverte AVANT le premier mot : sans elle, `archiverMot` n'a pas de
        // session ou se rattacher et l'archivage est silencieusement perdu.
        // Jamais en session de reference (comme la journalisation d'erreurs
        // juste en dessous : ce n'est pas une vraie recitation notee).
        await SessionArchiveService.instance.demarrer(
          surahNumber: _verses.isEmpty ? null : _verses.first.surahNumber,
          fromAyah: _verses.isEmpty ? null : _verses.first.ayahNumber,
          toAyah: _verses.isEmpty ? null : _verses.last.ayahNumber,
          preset: ref.read(judgementOptionsProvider).preset.name,
        );
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
  // ── DIALOGUE « reference ou correction ? » — PLUS APPELE (2026-08-05) ─────
  //
  // Conserve intact plutot que supprime : il porte la formulation exacte des
  // deux modes, et un futur besoin (un mode « evaluation » assume, par
  // exemple) repartirait de la. Le mode REFERENCE lui-meme n'est pas mort --
  // seul le CHOIX propose a l'utilisateur l'est, cf. le commentaire du bloc
  // qui fixe `_isReferenceSession`. Le banc y accede par `autoDemarrer`.
  //
  // ⚠️ Ne pas le rebrancher sans repondre a l'objection qui l'a fait retirer :
  // ce mode « ne demande pas la repetition », donc il ne corrige personne.
  // ignore: unused_element
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
  /// Montre le glyphe d'etat au centre pendant [_kGlypheEtatMs], puis
  /// l'efface. Un seul timer : une bascule rapide repousse l'echeance au lieu
  /// d'en empiler plusieurs.
  void _montrerGlypheEtat() {
    _glypheTimer?.cancel();
    setState(() => _glypheEtatJusqua =
        DateTime.now().add(const Duration(milliseconds: _kGlypheEtatMs)));
    _glypheTimer = Timer(const Duration(milliseconds: _kGlypheEtatMs), () {
      if (mounted) setState(() => _glypheEtatJusqua = null);
    });
  }

  Future<void> _togglePause() async {
    _montrerGlypheEtat();
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
      // Un test se termine sur CE bouton bien plus souvent que sur l'arrêt :
      // sans ce vidage, la trace fine (une ligne par bloc PCM, avec `busy=`)
      // reste en mémoire et le log ne permet plus de savoir ce qui a tenu la
      // chaîne. Cf. RecitationNotifier.flushTraces.
      await ref.read(recitationProvider.notifier).flushTraces();
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
  // Plus appelé depuis le retrait de l'icône jeu de l'AppBar (2026-08-10,
  // cf. plus haut) ; gardé pour un futur appelant.
  // ignore: unused_element
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

                      // ── Moteur de jugement ────────────────────────────────
                      // Le choix gop/texte-diff était exposé ici depuis le
                      // 2026-07-20 (pour comparer les deux moteurs en
                      // conditions réelles avant de trancher). TRANCHÉ le
                      // 2026-08-01 : le gop reste le moteur, le toggle est
                      // retiré de l'IHM (demande utilisateur : "moteur
                      // alignement il sera toujours GOP, à supprimer ici").
                      // `useGopScoring` existe TOUJOURS côté modèle (défaut
                      // true, cf. judgement_options.dart) et le texte-diff
                      // reste le repli automatique quand l'alignement natif
                      // est indisponible -- ce n'est plus qu'un choix
                      // utilisateur qui disparaît, pas le mécanisme.

                      // ── LE REGLAGE DE CORRECTION EST RETIRE (2026-08-07) ──
                      //
                      // Le mode qu'il pilotait n'existe plus (cf.
                      // `_onWordFailed`) : une erreur isolee n'interrompt plus
                      // jamais, le verdict arrivant 4 a 8 s trop tard. Il ne
                      // restait donc qu'un interrupteur qui ne commande rien --
                      // pire qu'un reglage absent.
                      //
                      // `autoCorrectionEnabledProvider` est CONSERVE (d'autres
                      // ecrans le lisent, et le jour ou une correction en temps
                      // reel deviendra possible, c'est ici qu'elle reviendra) :
                      // seul le commutateur disparait de cette feuille.
                      // Ancien code, garde en trace :
                      //   _SheetSwitch(
                      //     icon: Icons.hearing_rounded,
                      //     title: t.karaokeAutoCorrectionTitle,
                      //     subtitle: t.karaokeAutoCorrectionSubtitle,
                      //     value: autoCorr,
                      //     onChanged: (v) => ref
                      //         .read(autoCorrectionEnabledProvider.notifier)
                      //         .set(v),
                      //   ),
                      // ── RIGUEUR DE LA CORRECTION RETIRÉE (2026-08-10) ──
                      //
                      // Demande utilisateur : « enlève rigueur de correction,
                      // ne sert à plus grand chose ». `strictCorrectionProvider`
                      // reste lu tel quel dans `_onWordFailed` (rouge ET orange
                      // déclenchent la correction par défaut, cf. sa doc) --
                      // seul ce commutateur disparaît, le comportement actuel
                      // (STRICT, valeur par défaut) ne change pas, il n'est
                      // simplement plus modifiable depuis cette feuille.
                      // Ancien code, gardé en trace :
                      //   _SheetSwitch(
                      //     icon: Icons.rule_rounded,
                      //     title: t.karaokeStrictnessTitle,
                      //     subtitle: strict
                      //         ? t.karaokeStrictnessStrictSubtitle
                      //         : t.karaokeStrictnessTolerantSubtitle,
                      //     value: strict,
                      //     onChanged: (v) => ref
                      //         .read(strictCorrectionProvider.notifier)
                      //         .set(v),
                      //   ),
                      // "Suivre sans bloquer" DÉPLACÉ vers l'écran Suivre
                      // prière le 2026-08-01 (demande utilisateur : "c'est je
                      // pense côté suivre prière, du coup mets-le dans page
                      // suivre prière"). Le provider et sa logique sont
                      // inchangés -- seul le point de réglage déménage, là où
                      // ce comportement a un sens (suivre un imam sans
                      // jamais l'interrompre).
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
  /// L'écran du Coach : le karaoké, figé.
  ///
  /// Volontairement pauvre en chrome (pas d'onde micro, pas de compteurs, pas
  /// de barre d'action) : on vient ici pour LIRE ses verdicts, pas pour
  /// piloter une récitation. Tout ce qui reste vient de la récitation
  /// elle-même -- `_verseArea` -- pour qu'il n'existe qu'un seul rendu du
  /// texte colorié dans l'application.
  Widget _ecranRelecture(BuildContext context) {
    final st = _etatRelecture;
    return Scaffold(
      backgroundColor: AppColors.green900,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(widget.titreRelecture ?? '',
            style: GoogleFonts.scheherazadeNew(
                fontSize: 20, color: AppColors.brassLight)),
      ),
      body: !_ready || st == null
          ? const SizedBox.expand()
          : SafeArea(child: _verseArea(st)),
    );
  }

  Widget build(BuildContext context) {
    // ── RELECTURE : même rendu, sans rien de vivant (2026-08-13) ───────────
    // Sortie AVANT toute lecture de `recitationProvider` : en relecture la
    // chaîne n'a jamais été démarrée, la lire ici ressusciterait un état de
    // récitation qui n'a pas lieu d'être. Le corps réutilise `_verseArea`,
    // c'est-à-dire EXACTEMENT le rendu et la palette de la récitation.
    if (widget.estRelecture) return _ecranRelecture(context);
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
        _cloturerArchive();
      }
      // Bilan écrit AU FIL DE L'EAU, au plus une fois toutes les 10 s : si le
      // processus meurt (Android, plantage), la session garde des chiffres
      // réels au lieu d'apparaître vide. Volontairement PAS à chaque mot --
      // c'est une écriture disque, elle n'a rien à faire dans le chemin de
      // jugement.
      _majBilanPeriodique();
      // Enchaînement sur la page suivante du Mushaf (demande utilisateur
      // 2026-07-11, "récitation en flux continu... enchaîner sur une autre
      // sourate", chargement borné page par page après revue le même jour) :
      // dès que la récitation approche de la fin du texte CONNU, va chercher
      // la suite en arrière-plan AVANT d'y arriver -- sinon la session se
      // termine normalement (pointer >= words.length -> finished) au lieu
      // d'enchaîner.
      //
      // PAS `next.pointer` (2026-08-05, même défaut que le souffleur cf.
      // _promptCurrentWord) : quand la v2 pilote, le pointeur reste bloqué
      // près de 0, donc `words.length - pointer` ne descend jamais sous
      // `_kExtendLookaheadWords` -- l'enchaînement ne se déclenchait JAMAIS,
      // et la session se figeait dès le dernier mot chargé (mesuré : bloqué
      // sur "ٱلْمُفْلِحُونَ", dernier mot de la plage 2:1→2:5, "je ne peux
      // plus réciter"). On suit le mot marqué `current`.
      // Repli sur le mot jugé le plus avancé quand `current` a disparu (cf.
      // `_indexASuivre`) : sans lui, l'enchaînement de page s'arrêtait pour
      // toujours et la récitation se figeait sur le dernier mot chargé.
      final pointerExtend = _indexASuivre(next);
      if (next.status == RecitationStatus.listening &&
          next.words.length - pointerExtend <= _kExtendLookaheadWords) {
        _maybeExtendNextPage();
      }
      _maybePrefetchCorrectionAudio(pointerExtend);
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
    _dernierEtatConnu = st;
    // Défilement automatique vers le mot en cours (demande utilisateur
    // 2026-07-05 : suivre la vitesse de lecture pendant la récitation).
    // Calculé directement depuis l'état affiché par CE build (plutôt que via
    // ref.listen(prev,next), peu fiable ici car le mot "current" peut changer
    // plusieurs fois entre deux frames) — plus robuste, et ne redéclenche
    // qu'au changement réel d'index (demande utilisateur 2026-07-06 : le
    // scroll automatique ne se déclenchait pas de façon fiable).
    // Même repli que pour l'enchaînement de page (cf. `_indexASuivre`) : le
    // défilement ne doit jamais s'arrêter parce que `current` a disparu.
    final currentIdx = st.words.isEmpty ? -1 : _indexASuivre(st);
    if (currentIdx != -1 && currentIdx != _lastAutoScrolledIndex) {
      _lastAutoScrolledIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // L'utilisateur vient de scroller manuellement -> on ne le contredit
        // pas tout de suite (demande utilisateur : le scroll manuel doit
        // rester utilisable pendant la récitation).
        final until = _manualScrollUntil;
        if (until != null && DateTime.now().isBefore(until)) return;
        // ── LA DÉSYNCHRONISATION DES CLÉS NE DOIT PLUS ÊTRE MORTELLE ────────
        // Avant : `if (currentIdx >= _wordKeys!.length) return;` -- si la
        // liste de clés de l'écran prenait du retard sur la liste de mots de
        // la chaîne (enchaînement de page à peine appliqué, une frame de
        // décalage), le défilement s'arrêtait SANS AUCUNE TRACE, et rien ne
        // le relançait. On suit alors le dernier mot dont on a une clé : on
        // avance moins loin, mais on continue d'avancer.
        final cles = _wordKeys;
        if (cles == null || cles.isEmpty) return;
        final idxCle = currentIdx >= cles.length ? cles.length - 1 : currentIdx;
        if (currentIdx >= cles.length) {
          DiagnosticLog.log('Karaoke',
              'defilement : mot=$currentIdx hors des ${cles.length} cles '
              '(ecran en retard sur la chaine) -> suivi du dernier mot connu');
        }
        final ctx = cles[idxCle].currentContext;
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
                  // ── ETOILES, EN MODE ENFANT SEULEMENT ────────────────────
                  //
                  // Demande utilisateur (2026-08-06) : « améliore l'aspect
                  // visuel quand c'est en mode enfant : des étoiles gagnées
                  // quand on réussit [...] de la gamification quand c'est mode
                  // enfant ».
                  //
                  // Une etoile par VERSET entierement vert. Le verset est
                  // l'unite naturelle -- un mot est trop fin (l'ecran
                  // clignoterait), la sourate trop grosse (l'enfant
                  // n'obtiendrait rien avant la fin).
                  //
                  // Strictement reserve au preset ENFANT : recompenser un
                  // adulte qui travaille son tajwid n'a pas le meme sens, et
                  // l'utilisateur a demande ca POUR le mode enfant.
                  if (ref.watch(judgementOptionsProvider).preset ==
                      JudgementPreset.enfant)
                    _BandeauEtoiles(etoiles: _etoilesGagnees(st)),
                  _referenceBanner(st),
                  Expanded(child: Center(child: _verseArea(st))),
                  _heardCaption(st),
                  _bottomHint(st),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            // ── MICRO COUPE : LE DIRE EN GRAND, AU MILIEU ───────────────
            //
            // Demande utilisateur (2026-08-06) : « je veux que le play/pause
            // soit explicite, style un play et pause qui s'affiche en
            // transparent au milieu de l'ecran, pour eviter qu'il continue de
            // reciter alors que le micro est coupe ».
            //
            // Le seul indice etait jusqu'ici l'icone de la barre du bas, hors
            // du champ de lecture : on recite en regardant le TEXTE, au centre.
            // Reciter dans le vide n'a aucun cout visible -- rien ne se colore,
            // ce qui ressemble a une chaine qui rame, pas a un micro coupe.
            if (_glypheEtatJusqua != null)
              Positioned.fill(child: _glypheEtat()),
            // PAS D'OVERLAY PENDANT loadingModel (demande utilisateur
            // 2026-08-09 : « toujours trois écrans » -- chargement modèle,
            // décompte, préparation micro -- « pas besoin de montrer que le
            // modèle charge, ça doit être en arrière-plan »). L'écran de
            // récitation normal reste donc visible pendant le chargement ;
            // l'isti'adha ne couvre l'écran qu'à partir du décompte, une fois
            // le modèle prêt. `RecitationStartOverlay` sait toujours peindre
            // `loadingModel` (cf. son commentaire) -- ce n'est simplement plus
            // demandé à cet écran-ci.
            if (_startStage case final stage?
                when stage != RecitationStartStage.loadingModel)
              Positioned.fill(child: RecitationStartOverlay(stage: stage)),
          ],
        ),
      ),
    );
  }

  /// Voile de PAUSE : glyphe transparent au centre, tap pour reprendre.
  ///
  /// Volontairement TRANSPARENT et non bloquant a la lecture : le texte
  /// coranique doit rester lisible dessous -- on ne masque pas le Coran pour
  /// afficher un bouton. Le tap sur le voile reprend la capture, ce qui evite
  /// d'avoir a viser l'icone de la barre du bas.
  Widget _glypheEtat() {
    // NI voile NI zone tactile : le texte coranique reste lisible et
    // cliquable dessous. Le glyphe dit l'ETAT qu'on vient d'atteindre (pause
    // ou lecture) et s'efface tout seul -- c'est un accuse de reception du
    // geste, pas un panneau.
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_glypheEtatJusqua),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 160),
          builder: (context, t, child) =>
              Opacity(opacity: t, child: Transform.scale(scale: 0.92 + t * 0.08, child: child)),
          child: Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.38),
              border: Border.all(
                  color: AppColors.brassLight.withOpacity(0.55), width: 2),
            ),
            child: Icon(
              _manuallyPaused ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 68,
              color: AppColors.brassLight,
            ),
          ),
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
  /// Nombre de versets ENTIEREMENT verts depuis le debut de la session.
  ///
  /// Recalcule a chaque rendu plutot que compte a l'evenement : un verdict peut
  /// etre revise (un `omis` redevient vert, mesure 12 fois sur 90 mots), et un
  /// compteur incremental garderait une etoile que la chaine vient de retirer.
  /// Le cout est negligeable -- on ne parcourt que les mots deja juges.
  int _etoilesGagnees(RecitationSessionState st) {
    var etoiles = 0;
    var tousVerts = true;
    var vuAuMoinsUn = false;
    for (var i = 0; i < st.words.length; i++) {
      final w = st.words[i];
      if (w.status == WordStatus.pending || w.status == WordStatus.current) {
        tousVerts = false;
      } else {
        vuAuMoinsUn = true;
        if (w.status != WordStatus.correct) tousVerts = false;
      }
      if (_isLastWordOfVerse(i)) {
        if (tousVerts && vuAuMoinsUn) etoiles++;
        tousVerts = true;
        vuAuMoinsUn = false;
      }
    }
    return etoiles;
  }

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
                // 20 -> 26 (demande utilisateur 2026-08-06 : « agrandis un peu
                // les icones pause, haut-parleur et reglages, c'est petit »).
                // La BOITE de l'IconButton ne bouge pas (48 dp, ou ~40 avec
                // `visualDensity.compact`) : la rangee ne peut donc pas
                // deborder comme en 2026-07-25, ou c'est l'AJOUT d'un cinquieme
                // bouton qui avait rogne le bouton pause hors de l'ecran.
                size: 26,
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
            icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 26),
            onPressed: () => _openVerificationSheet(context),
          ),
          // ── ACCÈS AU JEU RETIRÉ D'ICI (2026-08-10) ──────────────────────
          //
          // Demande utilisateur : « y'a en haut l'accès au jeu, y'a plus
          // intérêt d'être enlevé » -- Réciter/Enchaînement (ex-Jeu) ont
          // depuis reçu leur propre icône dans la barre du bas du Mushaf
          // (2026-08-09), rendant ce raccourci redondant ici.
          // `_openMemorizationGame` reste défini plus bas (marqué
          // unused_element) : seul cet appelant disparaît.
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
                size: 32,
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
    // ── LA FENÊTRE DE RENDU SUIT L'ANCRE, PLUS `pointer` (2026-08-13) ──────
    // Cause racine du figement, trouvee par l'utilisateur : « si elle est a la
    // taille de 20 versets, meme si tu defiles c'est ce qu'il y a de max ».
    //
    // Cette borne partait de `st.pointer` -- la variable dont ce meme fichier
    // dit ailleurs qu'elle « reste bloquee pres de 0 quand la v2 pilote »
    // (cf. le commentaire de l'enchainement de page, qui avait deja du cesser
    // de s'y fier). Resultat : la chaine jugeait jusqu'au mot 182 et 361 mots
    // etaient charges en memoire, mais l'ecran ne CONSTRUISAIT que les 150
    // premiers. Defiler ne servait a rien : il n'y avait rien de plus.
    //
    // On borne desormais sur le meme index que le defilement et
    // l'enchainement (`_indexASuivre` : le mot `current`, a defaut le mot juge
    // le plus avance). Les trois mecanismes regardent enfin le meme endroit.
    final renderEnd = math.min(
        st.words.length, _indexASuivre(st) + _kRenderLookaheadWords);
    // ── RENDU PARESSEUX (2026-07-27) ─────────────────────────────────────
    // On ne construit ici que les BORNES des blocs (quelques dizaines
    // d'entiers) ; les widgets eux-memes sont bâtis a la demande par le
    // ListView, donc uniquement pour ce qui est visible.
    //
    // AVANT : `blocks` contenait des widgets DEJA CONSTRUITS, et
    // SingleChildScrollView + Column les mettait TOUS en page, hors ecran
    // compris. Sur une page de 246 mots -- et l'enchainement va au-dela de 300
    // -- c'etait l'integralite du texte reconstruite a chaque payload
    // d'alignement, soit toutes les ~1,5 s.
    //
    // Pourquoi ca comptait pour l'ASR et pas seulement pour le confort : les
    // allers-retours MethodChannel qui alimentent le natif en PCM reviennent
    // par le THREAD PRINCIPAL, celui qui execute ce rendu. Constat utilisateur
    // (« l'ecran est lourd, le scroll ne repond pas ») sur un Galaxy S25 : le
    // MEILLEUR cas materiel, d'ou la demande explicite de privilegier l'ASR
    // quitte a appauvrir l'ecran.
    final ranges = <({int start, int end, int? banner})>[];
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
        if (i > blockStart) {
          ranges.add((start: blockStart, end: i, banner: null));
        }
        blockStart = i;
        if (i < renderEnd && surah != null && _surahMeta[surah] != null) {
          ranges.add((start: i, end: i, banner: surah));
        }
      }
      blockSurah = surah ?? blockSurah;
    }
    // ── TRACE DE LA COUTURE ENTRE DEUX SOURATES (2026-08-06) ─────────────
    //
    // Defaut signale PLUSIEURS FOIS par l'utilisateur et jamais elucide :
    // « quand j'ai recite la sourate 94, a la fin il y a le debut de la
    // sourate 95 avant le signe de la sourate, avant la Bismillah ».
    //
    // La lecture du code ne suffit pas : la pagination est propre (page 596
    // finit a 94:8, page 597 commence a 95:1) et `_buildChunk` insere bien la
    // Bismillah devant 95:1 -- sur le papier l'ordre est correct. Plutot que
    // d'inventer une explication, on ECRIT ce que le rendu construit vraiment.
    // Emis une seule fois par composition de bandeaux, jamais a chaque frame.
    final signature = ranges
        .map((r) => r.banner != null ? 'B${r.banner}@${r.start}' : '${r.start}-${r.end}')
        .join(' ');
    if (signature != _derniereSignatureRanges) {
      _derniereSignatureRanges = signature;
      final st0 = ref.read(recitationProvider);
      final couture = ranges.where((r) => r.banner != null).map((r) {
        final i = r.start;
        String mot(int k) => (k >= 0 && k < st0.words.length)
            ? st0.words[k].display
            : '(hors liste)';
        return 'bandeau=${r.banner} @mot=$i '
            'avant=[${mot(i - 2)} ${mot(i - 1)}] apres=[${mot(i)} ${mot(i + 1)} ${mot(i + 2)}] '
            'surahOwning(${i - 1})=${_surahOwning(i - 1)} surahOwning($i)=${_surahOwning(i)}';
      }).join(' | ');
      DiagnosticLog.log('Karaoke',
          '[COUTURE] blocs=$signature  meta=${_surahMeta.keys.toList()}  '
          'mots=${st0.words.length} tables=${_surahByWord.length}'
          '${couture.isEmpty ? "" : "  $couture"}');
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
      child: ListView.builder(
        // ── LE MOT SUIVI RESTE AU MILIEU, JAMAIS COLLÉ EN BAS (2026-08-13) ──
        // Demande utilisateur : « je ne veux pas que la coloration arrive au
        // bout en bas, il faut toujours qu'il y ait de la marge, je veux la
        // coloration toujours au milieu de l'écran ».
        //
        // L'auto-scroll demande déjà un centrage (`alignment: 0.5` dans
        // `Scrollable.ensureVisible`), mais un défilement ne peut pas aller
        // au-delà de la fin du contenu : arrivé aux derniers blocs, il n'y a
        // plus rien sous le texte, donc le mot courant DÉRIVE vers le bas de
        // l'écran et finit sur la dernière ligne. Le centrage n'était pas en
        // cause, la place manquait.
        //
        // On réserve donc une demi-hauteur d'écran sous le texte. C'est de
        // l'espace vide, jamais du contenu : rien à lire n'y est caché, et le
        // centrage redevient possible jusqu'au tout dernier mot.
        padding: EdgeInsets.only(
          left: 28,
          right: 28,
          bottom: MediaQuery.of(context).size.height * 0.5,
        ),
        itemCount: ranges.length,
        // Marge de construction hors ecran : l'auto-scroll utilise
        // Scrollable.ensureVisible sur la GlobalKey du mot courant, qui exige
        // que le widget SOIT construit. Une marge large garantit que le mot
        // courant l'est presque toujours -- et le code d'auto-scroll teste
        // deja `ctx != null`, donc le cas limite degrade proprement (pas de
        // defilement) au lieu de planter.
        cacheExtent: 1600,
        itemBuilder: (_, i) {
          final r = ranges[i];
          final b = r.banner;
          if (b != null) return _SurahTransitionBanner(_surahMeta[b]!);
          return _wordWrapBlock(st, r.start, r.end);
        },
      ),
    );
  }

  Widget _wordWrapBlock(RecitationSessionState st, int start, int end) {
    // ── OU EN EST LE RECITATEUR ─────────────────────────────────────────
    //
    // NI `st.pointer` NI `WordStatus.current` : quand la v2 pilote, `_onV2`
    // met a jour les STATUTS des mots et rien d'autre. `pointer` reste a 0
    // (piege deja documente dans `_promptCurrentWord`), et `current` n'est
    // pose qu'a l'index 0 au moment du reset -- il n'avance jamais non plus.
    //
    // DEFAUT MESURE (2026-08-06, retour utilisateur : « le fil de lumiere
    // n'est pas visible ») : le fil restait colle aux six premiers mots, dans
    // la Bismillah, pendant toute la recitation.
    //
    // Le FRONT reel est le plus grand index deja juge : la v2 ne rend un
    // statut que sur un mot qu'elle a vu.
    var curseur = -1;
    for (var i = st.words.length - 1; i >= 0; i--) {
      final s0 = st.words[i].status;
      if (s0 != WordStatus.pending && s0 != WordStatus.current) {
        curseur = i;
        break;
      }
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 18,
        children: [
          for (var i = start; i < end; i++) ...[
            _wordSpan(st.words[i], i, curseur),
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
    // O(1) depuis la table precalculee. L'ancien calcul faisait DEUX appels a
    // _verseContaining, chacun O(versets) avec un decoupage de chaine par
    // verset -- cf. _rebuildWordVerseMap pour l'ordre de grandeur.
    if (_verseByWord.isNotEmpty) return _lastWordOfVerse.contains(wordIndex);
    final verse = _verseContainingSlow(wordIndex);
    if (verse == null) return false;
    final words = ref.read(recitationProvider).words;
    if (wordIndex + 1 >= words.length) return true;
    return _verseContainingSlow(wordIndex + 1) != verse;
  }

  // Coloration tajwid lettre-par-lettre TOUJOURS visible (demande utilisateur
  // 2026-07-05, "partout où le texte apparaît") -- le jugement vert/orange/
  // rouge est porté par le FOND, jamais par la couleur du texte, pour que les
  // deux systèmes ne se disputent jamais le même pixel.
  Widget _wordSpan(RecitedWord w, int index, [int curseur = -1]) {
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
        // VIOLET quand l'écart vient d'une RÈGLE DE TAJWID non détectée, et
        // pas d'une prononciation douteuse. Ce cas manquait : le violet
        // n'existait que dans `case WordStatus.error` (2026-08-01), alors que
        // le contrôle tajwid produit un `unclear` (cf. _onV2) -- les deux
        // mécanismes n'avaient jamais été reliés, donc le violet ne pouvait
        // s'afficher pour la raison même qui l'a fait naître.
        //
        // La gravité reste `unclear` : les lettres et les harakat SONT justes,
        // seule la règle manque. C'est la lecture du cahier des charges du
        // 2026-07-30 -- la tête tajwid est là « juste pour préciser les mots où
        // le tajwid est absent », pas pour condamner une prononciation.
        final tajwidManquant =
            ref.read(recitationProvider.notifier).classifyError(index) ==
                RecitationErrorKind.tajwid;
        final cu = tajwidManquant
            ? AppColors.recitationTajwidError
            : const Color(0xFFffcc80);
        bgTint = cu.withOpacity(0.42);
        borderTint = cu;
        break;
      case WordStatus.error:
        // Rouge SEULEMENT si verrouillé (demande utilisateur 2026-07-09 :
        // "il se met en rouge puis en vert, c'est perturbant") -- un aperçu
        // pas encore figé peut sembler faux un instant avant de se stabiliser
        // correctement une fois plus d'audio reçu (mot encore incomplet).
        // Tant que ce n'est pas définitif, on n'affiche rien de spécial
        // plutôt que de faire clignoter rouge->vert.
        if (w.locked) {
          // VIOLET si l'écart vient d'une règle de TAJWID non réalisée
          // (2026-08-01, demande utilisateur) : lettres et harakat sont
          // justes, seule la règle manque -- ce n'est pas la même erreur
          // qu'un mot mal prononcé, et le récitateur doit pouvoir les
          // distinguer d'un coup d'œil. `classifyError` n'est appelé que sur
          // les mots déjà verrouillés en erreur (rares), pas sur chaque mot
          // à chaque frame.
          final estTajwid =
              ref.read(recitationProvider.notifier).classifyError(index) ==
                  RecitationErrorKind.tajwid;
          final c = estTajwid
              ? AppColors.recitationTajwidError
              : const Color(0xFFff8a80);
          bgTint = c.withOpacity(0.42);
          borderTint = c;
        }
        break;
      case WordStatus.skipped:
        underline = true;
        break;
      case WordStatus.current:
      case WordStatus.pending:
        // Texte non-encore-JUGÉ INVISIBLE (demande utilisateur 2026-07-06,
        // étendue le 2026-08-05 : "il ne faut afficher que les mots validés
        // ou erronés"). `current` marquait jusqu'ici le mot que le modèle
        // suit, avec un contour doré -- retiré : ce marqueur pouvait rester
        // affiché sur un mot jamais réellement prouvé (mesure sur device,
        // "ذَٰلِكَ" souligné en `current` alors que le journal natif n'avait
        // jugé AUCUN mot au-delà de la Bismillah dans toute la session,
        // `dernier definitif` bloqué à 3). Traiter les deux statuts pareil
        // retire cette fuite d'information : rien n'indique où l'app pense
        // que le récitateur en est tant que ce n'est pas prouvé.
        // SAUF en session de RÉFÉRENCE (demande utilisateur 2026-07-09) :
        // cette session sert à capturer le rythme naturel de lecture (pauses)
        // en suivant le texte des yeux -- masquer le texte n'a pas de sens
        // ici (pas un test de mémoire) et perturbe la lecture normale.
        opacity = _isReferenceSession ? 1.0 : 0.0;
        break;
    }

    // ── LA COULEUR APPARTIENT AU VERDICT PENDANT LA RECITATION (2026-08-05)
    //
    // Demande utilisateur : « les deux systemes de couleurs se disputent le
    // meme texte ». Constat en relisant le code : ce ne sont PAS deux systemes
    // empiles, ce sont deux canaux distincts -- le VERDICT peint le fond et le
    // contour, le TAJWID colore les lettres. Le conflit vient des TEINTES
    // COMMUNES : un mot correct a un fond vert et des lettres vertes, un mot
    // faux un fond rouge et parfois des lettres rouges. Impossible alors de
    // savoir si un rouge est une regle de tajwid ou une faute -- or c'est
    // exactement ce que l'application existe pour dire.
    //
    // LE CORRECTIF NE SUPPRIME PAS LE TAJWID, il lui retire la COULEUR le
    // temps de la recitation : le texte redevient creme, et la couleur ne veut
    // plus dire qu'une seule chose. Les regles restent lisibles autrement (la
    // feuille d'aide au tap sur un mot, et la lecture normale hors recitation
    // ou le tajwid garde toutes ses couleurs).
    //
    // ⚠️ ON NE TOUCHE PAS AUX SPANS D'ORIGINE. `_tajwidSpans` est construit une
    // fois par passage et relu a chaque rendu : le muter ici perdrait les
    // couleurs pour de bon, y compris apres la recitation. On recopie.
    final tajwidNeutre = tajwidWord
        ?.map((sp) => TextSpan(
              text: sp.text,
              children: sp.children,
              style: (sp.style ?? const TextStyle())
                  .copyWith(color: AppColors.cream),
            ))
        .toList();

    final textWidget = (tajwidNeutre != null && tajwidNeutre.isNotEmpty)
        ? RichText(text: TextSpan(children: tajwidNeutre))
        : Text(
            w.display,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 30, height: 2.1, color: AppColors.cream),
          );

    // ── FIL DE LUMIERE (demande utilisateur 2026-08-06) ──────────────────
    //
    // « les mots se valident aléatoirement ; je veux une ligne sous les mots
    // qui suit le curseur, pas de lien avec la validation, pour un aspect
    // visuel que tous les mots derrière sont en train d'être validés — style
    // un fil de lumière qui avance, petite animation légère ».
    //
    // POURQUOI CE N'EST PAS UN VERDICT, et pourquoi c'est important. Les
    // couleurs de jugement apparaissent dans le DESORDRE : un mot se fige dès
    // qu'il a ses preuves, et deux mots voisins ne les obtiennent pas au même
    // instant (cf. Decideur). Vu de l'écran, ça saute. Le fil dit une autre
    // chose, et une seule : « la chaîne est passée ici ». Il ne dépend
    // d'aucun statut et ne doit JAMAIS être lu comme un vert.
    //
    // Il ne s'affiche que là où aucune bordure de jugement n'existe : un
    // verdict prime toujours sur la décoration.
    //
    // COUT BORNE : seuls les [_kTraineeMots] mots derrière le curseur sont
    // animés. Sans cette borne, chaque mot de la page se reconstruirait 60
    // fois par seconde -- une page en porte plus de cent.
    // ── LE FIL ECLAIRE CE QUI EST EN COURS DE JUGEMENT, PAS CE QUI L'EST ──
    //
    // Correction du 2026-08-06, seconde passe. La premiere version eclairait
    // les mots DEJA juges, derriere le front -- ce qui ne dit rien d'utile :
    // ces mots portent deja leur couleur. Retour utilisateur : « un testeur ne
    // sait pas qu'il est en train d'ecouter ».
    //
    // Le jugement a plusieurs secondes de retard sur la voix (le temps que la
    // fenetre se ferme et que le modele reponde). Les mots interessants sont
    // donc ceux qui viennent APRES le dernier juge : le recitateur les a dits,
    // l'application les traite, et rien ne le montrait. Le fil les couvre.
    const traineeMax = _kTraineeMots;
    final distance = index - curseur;   // devant le front, pas derriere
    final dansLaTrainee =
        borderTint == null && distance > 0 && distance <= traineeMax;

    Widget chipAvec(double lueur) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bgTint,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          bottom: BorderSide(
            color: borderTint ??
                (lueur > 0
                    ? AppColors.brassLight.withOpacity(lueur)
                    : (underline
                        ? AppColors.brassLight.withOpacity(0.5)
                        : Colors.transparent)),
            width: 2,
          ),
        ),
      ),
      child: Opacity(opacity: opacity, child: textWidget),
    );

    final chip = dansLaTrainee
        ? AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              // Decroissance derriere le curseur : le mot courant est le plus
              // clair, la trainee s'eteint. Le battement (meme horloge que le
              // halo, 4 s) empeche l'effet de paraitre fige quand le
              // recitateur marque une pause.
              // Le plus clair est le mot JUSTE APRES le front -- le
              // prochain a etre juge -- et ca s'eteint vers l'avant.
              final fondu = 1.0 - (distance - 1) / traineeMax;
              final t = (math.sin(_breath.value * 2 * math.pi) + 1) / 2;
              return chipAvec((0.30 + t * 0.25) * fondu * fondu);
            },
          )
        : chipAvec(0);
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
    // En relecture, la chaîne n'a jamais tourné : lire `recitationProvider`
    // rendrait un état vide et la feuille s'ouvrirait sans le mot ni la voix.
    // C'est l'état reconstruit depuis la base qui fait foi (2026-08-13).
    final RecitationSessionState st =
        widget.estRelecture && _etatRelecture != null
            ? _etatRelecture!
            : ref.read(recitationProvider);

    // ── N'AFFICHER QUE LE MOT EN CAUSE, PAS TOUTE L'AYA (2026-08-05) ───────
    //
    // Demande utilisateur : « quand je clique sur le mot en erreur j'ai toute
    // l'aya qui s'affiche ; je veux que ça reste sur le mot en question. Si
    // deux ou trois mots en erreur sont côte à côte, on peut les fusionner
    // dans la même fenêtre. »
    //
    // On étend donc la plage aux mots CONTIGUS qui portent aussi un verdict
    // négatif. Deux fautes voisines forment presque toujours une seule et même
    // difficulté (une liaison, un enchaînement) : les présenter séparément
    // obligerait à ouvrir deux fois la fenêtre pour une seule cause.
    //
    // ⚠️ SEULS LES VERDICTS NÉGATIFS FUSIONNENT. Un mot `pending` ou `current`
    // n'a pas été jugé : l'inclure ferait grossir l'extrait au fil de la
    // récitation jusqu'à redonner le verset entier -- exactement ce qu'on
    // supprime ici.
    bool estEnErreur(int i) {
      if (i < 0 || i >= st.words.length) return false;
      final s = st.words[i].status;
      return s == WordStatus.error ||
          s == WordStatus.unclear ||
          s == WordStatus.skipped;
    }

    var debut = local;
    var fin = local;
    if (estEnErreur(wordIndex)) {
      // On borne l'extension au VERSET (indices locaux) : déborder sur le
      // verset voisin afficherait un texte que la feuille ne sait pas rendre,
      // puisqu'elle part de `verse.textUthmani`.
      while (debut > 0 && estEnErreur(wordIndex - (local - debut) - 1)) {
        debut--;
      }
      // ⚠️ BORNER AU VERSET (2026-08-06). `estEnErreur` teste des indices
      // GLOBAUX alors que `fin` est un indice LOCAL au verset : si les mots en
      // erreur se poursuivent dans le verset SUIVANT, `fin` sortait du verset
      // courant et la feuille faisait `sublist(debut, fin+1)` hors bornes ->
      // RangeError au tap sur un mot en erreur (constaté en production). Le
      // commentaire ci-dessus disait déjà « on borne l'extension au VERSET » ;
      // la boucle du haut le faisait (`debut > 0`), celle-ci l'avait oublié.
      final motsDuVerset =
          ArabicNormalizer.splitExpectedWords(verse.textUthmani).length;
      while (fin + 1 < motsDuVerset &&
          estEnErreur(wordIndex + (fin - local) + 1)) {
        fin++;
        if (fin - local > 12) break; // garde-fou : jamais un verset entier
      }
    }

    showTajwidHelpSheet(
      context,
      ref,
      verse: verse,
      playlist: _verses,
      focusWord: st.words[wordIndex].display,
      entendu: st.words[wordIndex].heard,
      wordIndex: wordIndex,
      localWordIndex: local,
      extraitDebut: debut,
      extraitFin: fin + 1, // borne haute exclusive, comme le mode Kindle
      // Contestation (pouce vers le bas) pendant une récitation EN DIRECT :
      // le mot peut appartenir à une portion suivie -- rafraîchir la liste
      // pour que son pourcentage en tienne compte au prochain passage sur
      // Coach (2026-08-11, constat utilisateur).
      onWordContested: () => ref.invalidate(portionsProvider),
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

// Plus appelé depuis le retrait de "Rigueur de la correction" (2026-08-10,
// dernier appelant), gardé : réutilisable pour un futur commutateur de
// cette feuille de réglages.
// ignore: unused_element
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

/// Bandeau d'etoiles du mode ENFANT (cf. `_etoilesGagnees`).
///
/// Discret par choix : il vit sous la barre du haut, jamais par-dessus le
/// texte coranique. Une etoile qui vient d'etre gagnee grossit brievement --
/// c'est le seul mouvement, pour que le regard revienne au texte.
class _BandeauEtoiles extends StatelessWidget {
  final int etoiles;
  const _BandeauEtoiles({required this.etoiles});

  @override
  Widget build(BuildContext context) {
    if (etoiles <= 0) return const SizedBox.shrink();
    // Au-dela de 5, on affiche « xN » plutot qu'une rangee qui deborde.
    final aDessiner = etoiles.clamp(0, 5);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < aDessiner; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey('etoile-$i'),
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.elasticOut,
              builder: (context, t, child) =>
                  Transform.scale(scale: t, child: child),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.star_rounded,
                    color: AppColors.brassLight, size: 26),
              ),
            ),
          if (etoiles > 5)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('x$etoiles',
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brassLight)),
            ),
        ],
      ),
    );
  }
}
