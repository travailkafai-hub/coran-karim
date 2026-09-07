// Moteur de répétition incrémentale — étape "Répète" du mode Entraînement du
// Coach (demande utilisateur 2026-07-24, remplace l'ancien mode "répéter le
// texte entier N fois depuis le début").
//
// ── CORRECTIF DU 2026-08-09 : PLUS DE FENÊTRE GLISSANTE ────────────────────
// Bref aller-retour le même jour : j'avais d'abord retiré ce widget du flux
// en croyant que le palier lui-même devait disparaître. Correction de
// l'utilisateur : « le fonctionnement de l'entraînement c'est par palier » --
// c'est le mécanisme voulu. Ce qui devait vraiment changer : la fenêtre
// (`_currentWindow`) GLISSAIT (elle oubliait les premières unités une fois
// `repeatWindowSizeProvider` dépassé), donc le texte jugé/affiché se
// déplaçait au lieu de rester ancré au début -- cf. `_currentWindow`
// ci-dessous pour le correctif (toujours [0, fin de l'unité courante]) et
// pour le décalage texte/audio, probablement une piste distincte.
//
// Principe : le verset est découpé en UNITÉS (1 mot en mode Enfant, un
// nombre de mots configurable approximant une "ligne" sinon --
// `adultChunkWordCountProvider`, cf. app_settings_provider.dart). Une
// fenêtre de taille FIXE (le "curseur", `repeatWindowSizeProvider`) glisse
// au fil des unités introduites : curseur=2 -> on apprend l'unité 1 seule,
// puis il faut réciter {1,2} ensemble pour valider l'introduction de
// l'unité 2, puis {2,3} pour celle de l'unité 3, etc. (la fenêtre GLISSE,
// sa taille ne grandit jamais). Un échec ne fait pas avancer -- même
// fenêtre, retry manuel.
//
// Audio par palier : réutilise WordCorrectionAudio.playWordRange (déjà
// utilisé par la fiche d'aide tajwid pour rejouer l'audio réel du
// récitateur sur une plage de mots précise via les timings quran.com) --
// demande explicite de l'utilisateur de ne rien réinventer ici.
//
// Chargement du modèle ASR : jamais de "parler dans le vide" -- l'écoute
// auto-déclenchée attend explicitement `ensureModelLoaded()` (jamais le nom
// technique du modèle affiché, juste un état "Préparation…").

import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/judgement_options.dart' show JudgementPreset;
import '../models/recitation_state.dart';
import '../models/verse.dart';
import '../providers/app_settings_provider.dart';
import '../providers/coach_provider.dart';
import '../providers/judgement_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../providers/app_settings_provider.dart'
    show coachControleCumulatifProvider;
import '../services/coupes_palier_service.dart';
import '../services/decoupe_audio_service.dart';
import '../services/coupes_texte_service.dart';
import '../models/reciter.dart';
import '../models/riwaya.dart';
import '../services/mp3quran_api.dart' show Mp3QuranWordSegments, Mp3QuranApi, AyahTiming;
import '../services/diagnostic_log.dart';
import '../services/portion_word_archiver.dart'
    show etendreAuxMotsContigusEnErreur;
import '../widgets/tajwid_help_sheet.dart' show showTajwidHelpSheet;
import 'coach_sessions.dart' show portionsProvider;
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import 'coach_screen.dart' show InfoBanner, MicSection, VerseDisplay;

enum _RoundPhase { loadingModel, playingAudio, listening, processing, retryReady }

class IncrementalRepeatStep extends ConsumerStatefulWidget {
  final Verse verse;
  final bool isLastVerse;

  /// Appelé quand la DERNIÈRE unité du DERNIER verset vient d'être validée
  /// -- fait passer le Coach en mode Contrôle.
  final VoidCallback onAllVersesDone;

  const IncrementalRepeatStep({
    super.key,
    required this.verse,
    required this.isLastVerse,
    required this.onAllVersesDone,
  });

  @override
  ConsumerState<IncrementalRepeatStep> createState() => _IncrementalRepeatStepState();
}

class _IncrementalRepeatStepState extends ConsumerState<IncrementalRepeatStep>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  int _unitsIntroduced = 1;
  _RoundPhase _phase = _RoundPhase.loadingModel;
  bool _modelReady = false;
  bool _handledThisSession = false;

  /// Statuts du DERNIER essai, pour les remontrer pendant l'audio du tour
  /// suivant.
  ///
  /// ── POURQUOI UNE COPIE, ET PAS `rst.words` (2026-08-18) ──────────────────
  /// Demande utilisateur : « quand le récitateur fait l'audio on affiche le
  /// texte, et surtout si c'est après une tentative -- il y a déjà de l'orange
  /// ou du rouge -- qu'on l'affiche, comme ça visuellement il regarde où il a
  /// raté ».
  ///
  /// Impossible de le lire dans l'état courant : `_startRound` appelle
  /// `setup(windowText)` AVANT l'audio (correctif du 2026-08-11 contre le
  /// décalage texte/audio), et `setup` remet tous les mots à `pending`. Les
  /// couleurs de l'essai précédent sont donc déjà effacées au moment où on
  /// voudrait les montrer. On en garde une copie au verdict.
  List<RecitedWord> _dernierEssai = const [];

  /// Arrêt AUTOMATIQUE du tour : tous les mots jugés, puis un bref silence.
  ///
  /// ── POURQUOI (2026-08-18) ────────────────────────────────────────────────
  /// Constat utilisateur : « il récite plus que l'aya, il ne s'arrête pas à
  /// l'aya ». Mesuré sur 80:1 (aya de 2,34 s) : le micro est resté ouvert
  /// 7,2 s et n'a été relâché que sur demande. Le tour ne se terminait pas
  /// quand l'unité était récitée, mais quand l'utilisateur l'arrêtait.
  ///
  /// Pourquoi un SILENCE et pas « tous les mots jugés » seul (choix
  /// utilisateur) : couper à l'instant du dernier verdict tomberait sur une
  /// fin de mot encore en train de sonner -- le madd final d'une aya dure
  /// facilement une seconde après que le mot est reconnu. On attend donc que
  /// la voix retombe.
  ///
  /// Dégradé, jamais cassé : si le niveau ne redescend jamais (pièce bruyante),
  /// le minuteur ne se déclenche pas et l'arrêt manuel reste disponible,
  /// exactement comme avant.
  Timer? _finAuto;

  /// Sous ce niveau, on considère que le récitateur s'est tu. `soundLevel` est
  /// déjà normalisé 0..1 (cf. `_estimatePcmLevel`). Repère mesuré : une
  /// session où le micro ne captait rien plafonnait à 0,025.
  static const double _seuilSilence = 0.10;
  static const Duration _delaiSilence = Duration(milliseconds: 800);

  List<String> get _words => ArabicNormalizer.splitExpectedWords(widget.verse.textUthmani);

  /// Fins d'unité (index de mot INCLUSIF), lues dans la RÉCITATION plutôt que
  /// comptées en mots.
  ///
  /// ── POURQUOI CE N'EST PLUS UN NOMBRE DE MOTS (2026-08-17) ────────────────
  /// Constat utilisateur sur 22:32 : le texte s'arrêtait à `شَعَـٰٓئِرَ` alors
  /// que l'audio allait jusqu'à `ٱللَّهِ` -- « je veux la concordance ». Un
  /// compte fixe de mots ne connaît pas la phrase : il coupe au milieu d'une
  /// proposition, et ce qu'on demande de réciter ne correspond plus à ce
  /// qu'on fait entendre.
  ///
  /// `CoupesPalierService` porte les coupes mesurées sur l'enregistrement de
  /// référence -- là où le récitateur applique le soukoun de waqf et laisse
  /// l'énergie retomber (cf. sa doc pour les trois critères essayés et les
  /// deux écartés par la mesure). Sur 22:32, la coupe tombe bien après
  /// `ٱللَّهِ`, et la suite démarre sur `فَإِنَّهَا`.
  ///
  /// Le mode ENFANT ne suit pas ces coupes : le but y est d'ancrer le texte
  /// morceau par morceau, pas de respecter le phrasé du récitateur.
  ///
  /// ── UN MOT -> DEUX MOTS (2026-09-01) ──────────────────────────────────
  /// Il découpait UN mot par unité. Demande utilisateur : « pour le mode
  /// enfant c'est mieux de faire 2 mots par 2, si impair garder le dernier
  /// impair ». Le commentaire d'origine ci-dessus reste vrai sur l'INTENTION
  /// (ancrer, ne pas suivre le phrasé) ; c'est la granularité qui change.
  ///
  /// Un mot isolé porte rarement un sens complet en arabe coranique -- un
  /// nom sans son article, un verbe sans son pronom -- et l'enfant répétait
  /// donc des fragments qu'il ne pouvait pas rattacher. Deux mots donnent
  /// presque toujours un groupe qui tient debout, sans pour autant approcher
  /// la longueur d'une proposition entière.
  ///
  /// Nombre de mots IMPAIR : le dernier mot forme une unité à lui seul,
  /// jamais un groupe de trois. C'est explicitement ce qui a été demandé, et
  /// c'est aussi le seul choix qui garde toutes les unités à leur taille
  /// annoncée -- un groupe de trois en fin de verset serait le plus long
  /// alors que c'est là que l'enfant fatigue.
  ///
  /// Repli si l'asset manque ou ne couvre pas ce verset : le verset entier
  /// forme une seule unité. Dégradé, jamais cassé -- et jamais un découpage
  /// arbitraire qui recréerait le défaut qu'on vient de supprimer.
  /// ── LES COUPES MESUREES SUR LA VOIX QUI JOUE (2026-09-06) ──────────────
  ///
  /// Defaut entendu par l'utilisateur : « le texte ne correspond pas a l'audio,
  /// l'audio dit un peu plus ; je suis plus pour l'audio car il s'arrete au bon
  /// moment des waqf ou silence, alors que le texte non ».
  ///
  /// Il avait raison, et le journal le disait : le TEXTE se coupait sur
  /// `coupes_palier_afasy.json` -- des coupes mesurees sur l'enregistrement
  /// d'AL-AFASY -- tandis que l'AUDIO, en Warsh, se coupait sur des minutages
  /// « ESTIMES -- decoupe ponderee, non mesuree ». Deux mecaniques
  /// independantes, aucune ne regardant l'audio qui joue.
  ///
  /// Sa proposition, retenue : « en premier l'audio qui pilote, on decoupe
  /// l'audio puis on affiche le texte ». `DecoupeAudioService` fait passer
  /// l'audio du recitateur dans l'aligneur du modele : les frontieres de mots
  /// en sortent, et les silences s'en deduisent.
  ///
  /// `null` tant que le calcul n'a pas abouti -- et il peut ne jamais aboutir
  /// (recitateur sans fichier local, audio illisible). Le repli est alors le
  /// comportement d'avant, inchange : les coupes d'Afasy. Degrade, jamais
  /// casse -- meme discipline que le reste de ce fichier.
  List<int>? _coupesMesurees;

  /// La decoupe complete -- les bornes en MILLISECONDES de chaque mot.
  ///
  /// ── POURQUOI ON GARDE LES MILLISECONDES (2026-09-06) ───────────────────
  ///
  /// `_coupesMesurees` ne porte que des INDEX, et un index ne suffit pas :
  /// pour jouer l'audio, il faudrait alors ressortir chercher « ou finit le
  /// mot 6 » dans une autre source -- les segments d'Al-Afasy, ou l'estimation
  /// ponderee. C'est exactement la ou naissait l'ecart signale depuis le
  /// 2026-08-27 (« il y a toujours un ecart entre l'audio qui recite et le
  /// texte »), et que le commentaire de `_jouerAudioUnite` disait ne pas
  /// pouvoir trancher depuis le code seul.
  ///
  /// Diagnostic de l'utilisateur : « ta methode genere des ecarts entre texte
  /// et audio, oublie les 6 mots ». En gardant les millisecondes issues du
  /// MEME alignement que les coupes, l'ecart devient structurellement
  /// impossible : le texte s'arrete apres le mot 6 et l'audio s'arrete a la
  /// fin du mot 6, la meme valeur, jamais recalculee.
  DecoupeVerset? _decoupe;

  /// Chemin local du fichier de sourate, retenu avec la decoupe : les bornes
  /// en ms ne valent que pour CE fichier.
  String? _cheminAudio;

  List<int> get _finsUnite {
    final preset = ref.read(judgementOptionsProvider).preset;
    final dernier = _words.length - 1;
    if (dernier < 0) return const [];
    if (preset == JudgementPreset.enfant) {
      // Fins d'unité aux index impairs (1, 3, 5 …) = des paires 0-1, 2-3 …
      final fins = [for (var i = 1; i <= dernier; i += 2) i];
      // Total impair : `dernier` est pair, il n'est donc pas dans la liste.
      // On l'ajoute pour que le mot restant forme sa propre unité (et non
      // pour l'agréger à la paire précédente). Couvre aussi le verset d'UN
      // seul mot, où la boucle ci-dessus ne produit rien.
      if (fins.isEmpty || fins.last != dernier) fins.add(dernier);
      return fins;
    }
    // ── TROIS SOURCES, UNE UNION (2026-09-06) ─────────────────────────
    //
    // Aucune ne suffit seule, et 6:1 le montre : l'utilisateur s'y arrete
    // apres `وَٱلْأَرْضَ` (5), `وَٱلنُّورَ` (8) et `يَعْدِلُونَ` (13). Or le
    // silence mesure chez Al-Afasy ne donne que le 8 -- il ne s'arrete pas
    // apres `وَٱلْأَرْضَ` -- le waqf Hafs donne le 8, le waqf Warsh le 13.
    //
    //   1. LA VOIX (`_coupesMesurees`) : ou CE recitateur se tait vraiment.
    //      La plus fidele quand elle existe, mais muette sur les arrets que
    //      le recitateur ne marque pas.
    //   2. LE TEXTE (`CoupesTexteService`) : waqf Hafs UNION Warsh, moins les
    //      `mamnu`, plus les particules qui ouvrent une proposition. Couvre
    //      5 202 versets contre 2 637 pour le Hafs seul.
    //   3. LES COUPES DE REFERENCE (`CoupesPalierService`) : l'asset mesure
    //      sur Al-Afasy. Conserve en dernier ressort -- il a l'avantage
    //      d'exister partout, y compris quand les deux autres se taisent.
    //
    // ON UNIT PLUTOT QU'ON CHOISIT. Une coupe de trop fait un palier plus
    // court : c'est un desagrement. Une coupe manquante fait reciter au-dela
    // de ce qui est affiche : c'est le defaut qu'on corrige. Les deux
    // n'ont pas le meme poids.
    final t1 = _coupesMesurees ?? const <int>[];
    // La riwaya de la SESSION, pas le reglage global : l'asset est calcule sur
    // le Hafs et ne s'applique en Warsh que si les deux textes s'accordent
    // (cf. `CoupesTexteService.coupes`).
    final t2 = CoupesTexteService.instance.coupes(
        widget.verse.surahNumber, widget.verse.ayahNumber, _words.length,
        estWarsh: ref.read(recitationProvider).riwaya == Riwaya.warsh);
    final t3 = (t1.isEmpty && t2.isEmpty)
        ? CoupesPalierService.instance
            .coupes(widget.verse.surahNumber, widget.verse.ayahNumber)
        : const <int>[];
    final coupes = {...t1, ...t2, ...t3}
        .where((i) => i >= 0 && i < dernier)
        .toList()
      ..sort();
    // Un palier trop long se refend sur une preposition -- cf.
    // `CoupesTexteService.refendreLongs`. En dernier, sur l'union : c'est la
    // LONGUEUR FINALE qui decide, pas celle d'une source prise a part.
    final ajustees = CoupesTexteService.instance
        .refendreLongs(coupes, widget.verse.surahNumber,
            widget.verse.ayahNumber, _words.length)
        .where((i) => i >= 0 && i < dernier)
        .toList();
    return [...ajustees, dernier];
  }

  int get _totalUnits => math.max(1, _finsUnite.length);

  /// Bornes (index de mot, inclusifs) de l'unité [unitIndex].
  (int, int) _unitWordRange(int unitIndex) {
    final fins = _finsUnite;
    if (fins.isEmpty) return (0, math.max(0, _words.length - 1));
    final i = unitIndex.clamp(0, fins.length - 1);
    final start = i == 0 ? 0 : fins[i - 1] + 1;
    return (start, fins[i]);
  }

  /// Bornes de la fenêtre courante -- CUMULATIVE depuis l'unité 0, jamais
  /// glissante (corrigé le 2026-08-09, demande utilisateur : « en répétant
  /// tout le temps depuis le début du verset »).
  ///
  /// AVANT : `firstUnit = max(0, _unitsIntroduced - windowSize)` faisait
  /// GLISSER le début de la fenêtre -- une fois `windowSize` unités
  /// introduites, les premières sortaient de la plage jugée/affichée. Le
  /// texte visible et vérifié se déplaçait donc au fil des tours au lieu de
  /// rester ancré au premier mot du verset -- symptôme décrit par
  /// l'utilisateur comme un « décalage ».
  ///
  /// `repeatWindowSizeProvider` n'est plus lu ici : le réglage qu'il pilotait
  /// (taille du curseur glissant) n'a plus d'objet sans glissement. Laissé
  /// intact côté provider/réglages (convention projet), simplement plus
  /// consulté par ce point d'usage.
  (int, int) _currentWindow() {
    final lastUnit = _unitsIntroduced - 1;
    final (_, end) = _unitWordRange(lastUnit);
    return (0, end);
  }

  @override
  void initState() {
    super.initState();
    // ── ÉVITER LE FLASH D'UN AUTRE VERSET (2026-08-09) ──────────────────────
    //
    // Constat utilisateur : « depuis Mushaf la mémorisation s'arrête bien au
    // verset, mais depuis la page erreur non » -- capture d'écran à l'appui,
    // le palier 1 affichait plusieurs versets de suite au lieu du seul
    // verset attendu.
    //
    // Cause : `recitationProvider` est un état PARTAGÉ entre écrans. En
    // arrivant depuis la fiche d'un mot en erreur (juste après une
    // récitation CTR), il porte encore les mots de TOUTE la récitation
    // précédente (plusieurs versets). `VerseDisplay` (plus bas) affiche
    // `rst.words` par priorité sur `verses: [widget.verse]` -- et
    // `setup(windowText)` (dans `_startRound`) ne remplace cet état
    // qu'APRÈS le chargement du modèle et la lecture de l'audio de
    // référence, deux `await`. Pendant cette attente, l'écran montre donc
    // les mots PÉRIMÉS de l'écran précédent, pas le verset qu'on est censé
    // travailler ici. Depuis Mushaf le défaut ne se voyait pas : l'état y
    // était déjà vide avant d'arriver (pas de récitation multi-versets
    // juste avant).
    //
    // Correctif à la RACINE, pas un rattrapage sur l'affichage : vider
    // l'état tout de suite, avant la première image, plutôt que d'ajouter
    // une condition à `VerseDisplay` pour ignorer un état qu'il n'aurait
    // jamais dû recevoir. `VerseDisplay` retombe alors sur son repli
    // (`verses: [widget.verse]`, toujours correctement borné à CE verset)
    // tant que le vrai `setup()` de ce palier n'a pas encore eu lieu.
    //
    // `Future.microtask` -- PAS un appel synchrone ici (2026-08-10, crash
    // observé : « Tried to modify a provider while the widget tree was
    // building », `RecitationNotifier.setup` appelé depuis `initState`).
    // Riverpod interdit de modifier un provider pendant TOUTE la phase de
    // construction, `initState` inclus. Le microtask s'exécute juste après
    // cette phase mais AVANT que le premier visuel ne soit peint (contrairement
    // à `addPostFrameCallback`, qui attendrait ce premier rendu et laisserait
    // passer le flash que ce correctif visait justement à éviter).
    Future.microtask(() {
      final n = ref.read(recitationProvider.notifier);
      n.setup('');
      // Dans le Coach, une regle attendue et non constatee compte comme
      // faute meme sur une seule observation -- cf. la doc du drapeau. Sans
      // lui, le controle tajwid ne s'executait jamais sur un palier court.
      n.tajwidSansDoubleObservation = true;
    });
    // `QuranApi.riwaya` ICI (pas `recitationProvider.riwaya`) : `setup()`
    // vient d'être planifié en microtask juste au-dessus et n'a pas encore
    // tourné -- l'état de session n'a donc pas encore figé sa riwaya. C'est
    // un simple prefetch (best-effort) ; la lecture réelle plus bas
    // (`_startRound`) tourne, elle, après `setup()` et lit `recitationProvider.riwaya`.
    final reciter =
        ref.read(playerProvider.notifier).reciterPour(QuranApi.riwaya);
    unawaited(WordCorrectionAudio.prefetch(widget.verse, reciter));
    // ── LES COUPES AVANT LE PREMIER PALIER (2026-08-27) ────────────────────
    //
    // DÉFAUT TROUVÉ EN LISANT CE CODE, constat utilisateur : « il y a toujours
    // un écart dans la mémorisation par palier entre l'audio qui récite et le
    // texte », persistant malgré les correctifs du 2026-08-09 (glissement de
    // fenêtre) et du 2026-08-11 (ordre setup/audio).
    //
    // C'ÉTAIT UNE COURSE. L'ancienne forme lançait DEUX choses en parallèle :
    //   CoupesPalierService.ensureLoaded().then((_) => setState(...));   // A
    //   addPostFrameCallback((_) => _startRound(playAudio: true));       // B
    // Si B gagne (asset pas encore chargé), `coupes()` rend une liste VIDE,
    // donc `_finsUnite = [dernier]`, donc `_totalUnits = 1` : la fenêtre du
    // premier palier vaut TOUT LE VERSET. L'audio part sur cette fenêtre-là.
    // Puis A arrive, `setState` rebâtit l'écran avec les VRAIES coupes -- le
    // texte affiché devient le premier palier, court -- pendant que l'audio
    // déjà lancé, lui, récite le verset entier. Exactement l'écart décrit,
    // et intermittent par nature puisqu'il dépend de qui gagne la course.
    //
    // Les correctifs précédents ne pouvaient pas l'attraper : ils portaient
    // sur le CONTENU de la fenêtre, pas sur le fait qu'elle change sous
    // l'audio après coup.
    //
    // On attend donc les coupes AVANT de calculer la première fenêtre. Le
    // `setState` n'a plus lieu d'être : les coupes sont là avant le premier
    // `_startRound`, il n'y a plus rien à rafraîchir après coup.
    unawaited(_mesurerCoupes());
    // Les waqf du texte : sans reseau, sans modele, disponibles aussitot.
    CoupesTexteService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    CoupesPalierService.instance.ensureLoaded().then((_) {
      if (mounted) _startRound(playAudio: true);
    });
  }

  @override
  void dispose() {
    // Le drapeau ne doit pas survivre a cet ecran : la recitation garde
    // l'exigence de double observation.
    ref.read(recitationProvider.notifier).tajwidSansDoubleObservation = false;
    _finAuto?.cancel();
    _pulse.dispose();
    _shake.dispose();
    // `stopContinuous` et non `stop` : le tour est démarré par
    // `startControle()` (mode continu). `stop()` sort d'ailleurs sans rien
    // faire sur une session continue -- cf. la note au second point d'arrêt.
    ref.read(recitationProvider.notifier).stopContinuous();
    WordCorrectionAudio.stop();
    super.dispose();
  }

  Future<void> _startRound({required bool playAudio}) async {
    if (!mounted) return;
    if (!_modelReady) {
      setState(() => _phase = _RoundPhase.loadingModel);
      _modelReady = await ref.read(recitationVerifierProvider).ensureModelLoaded();
      if (!mounted) return;
    }

    final (start, end) = _currentWindow();

    // `setup()` AVANT l'audio, pas après (correctif 2026-08-11 : décalage
    // audio/texte signalé par l'utilisateur, déjà pressenti comme "piste
    // distincte" par le correctif du 2026-08-09 sur `_currentWindow`).
    // `VerseDisplay` lit `rst.words`, qui ne venait à jour qu'APRÈS la
    // lecture de l'audio de ce palier -- pendant toute sa durée, l'écran
    // montrait donc encore le texte (plus court) du palier PRÉCÉDENT,
    // pendant que l'audio couvrait déjà le nouveau palier (plus long,
    // cumulatif depuis le mot 0). `setup()` est un simple reset d'état (tous
    // les mots en attente, aucun effet sur le micro/modèle -- `start()` s'en
    // charge séparément) : rien n'empêche de l'appeler avant l'audio.
    final windowText = _words.sublist(start, end + 1).join(' ');
    // `setupDepuisVerset` et non `setup` (2026-09-02) : ce dernier ne recoit
    // qu'un texte, donc AUCUNE regle attendue n'etait chargee et le mode
    // tajwid ne verifiait rien ici -- defaut signale par l'utilisateur, cf.
    // la doc de la methode. `start` est bien un index DANS LE VERSET
    // (`_words` vient de `widget.verse`), ce que la methode attend.
    ref.read(recitationProvider.notifier).setupDepuisVerset(
          windowText,
          surah: widget.verse.surahNumber,
          ayah: widget.verse.ayahNumber,
          premierMot: start,
        );

    if (playAudio) {
      // ── TOUJOURS LE RÉCITATEUR AVANT L'UTILISATEUR (2026-08-18) ─────────
      //
      // Demande utilisateur : « après chaque essai il y a un audio qui se
      // lance -- soit une répétition parce qu'il a échoué le palier, soit le
      // nouveau palier ; donc toujours un récitateur, un user ».
      //
      // Les deux chemins appelaient déjà `_startRound(playAudio: true)`, mais
      // la lecture pouvait ABANDONNER en silence : minutage pas encore
      // chargé, index hors bornes, fichier absent. Mesuré :
      //     ABANDON (MP3Quran) verset=80:1 : minutage local absent
      //     (fromIdx=0 toIdx=1 segments=null)
      // alors que 80:1 EST dans l'asset -- `ensureLoaded()` rendait la main
      // sans attendre le chargement déjà en cours (corrigé le même jour, cf.
      // `Mp3QuranWordSegments.ensureLoaded`). Le palier démarrait donc son
      // écoute sans que l'utilisateur ait rien entendu.
      //
      // `playWordWindow` rend désormais `false` dans ce cas : on retente UNE
      // fois après avoir réellement attendu le chargement, et l'échec
      // définitif est journalisé au lieu de passer inaperçu.
      setState(() => _phase = _RoundPhase.playingAudio);
      // riwaya de LA SESSION (pas du réglage global vivant) -- `setup()` a
      // déjà tourné à ce stade (appelé plus haut dans `_startRound`), donc
      // `recitationProvider.riwaya` est fiable ici.
      final reciter = ref
          .read(playerProvider.notifier)
          .reciterPour(ref.read(recitationProvider).riwaya);
      var joue = await WordCorrectionAudio.playWordWindow(widget.verse, reciter,
          startWordIdx: start, endWordIdx: end);
      if (!mounted) return;
      if (!joue) {
        await Mp3QuranWordSegments.instance.ensureLoaded();
        if (!mounted) return;
        // ── LES MEMES BORNES QUE LE TEXTE (2026-09-06) ─────────────────
        //
        // Quand la decoupe mesuree existe, on joue les millisecondes qu'elle a
        // produites -- pas un index que `playWordWindow` irait retraduire en
        // temps depuis une AUTRE source. Cf. `_decoupe` pour l'ecart que cela
        // supprime, et `WordCorrectionAudio.playRangeMs` qui ne consulte aucun
        // minutage.
        //
        // Repli inchange si la mesure manque : `playWordWindow`, comme avant.
        final d = _decoupe;
        final chemin = _cheminAudio;
        final bd = (d != null && start < d.mots.length) ? d.mots[start] : null;
        final bf = (d != null && end < d.mots.length) ? d.mots[end] : null;
        if (chemin != null && bd != null && bf != null &&
            bd.localise && bf.localise) {
          // ── LE DERNIER MOT GARDE SA QUEUE (2026-09-06) ───────────────
          //
          // Constat utilisateur : « la coupe audio est plutot bien, c'est la
          // coupe texte qui ne suit pas bien -- parfois en palier c'est un mot
          // de plus ». Le texte a un mot de plus que ce qu'on ENTEND.
          //
          // L'alignement pose la fin d'un mot sur sa derniere frame
          // ACOUSTIQUE -- 80 ms de resolution -- pas sur la fin de sa
          // resonance : la queue d'un madd final, le souffle d'un ha. Couper
          // pile la tronque le dernier mot, qui s'entend alors a moitie et
          // semble absent.
          //
          // On va donc jusqu'au MILIEU du silence qui suit, quand le mot
          // suivant est connu. C'est exactement la regle que
          // `ConstructeurDeFenetres` applique deja a ses blocs : « un bloc va
          // d'un milieu de silence au milieu du silence suivant ; ses deux
          // bords sont dans du silence, jamais en plein mot ». Bornee a 400 ms
          // pour ne pas mordre sur le mot d'apres quand le silence est long.
          final apres = (d != null && end + 1 < d.mots.length)
              ? d.mots[end + 1]
              : null;
          var finMs = bf.finMs;
          if (apres != null && apres.localise && apres.debutMs > bf.finMs) {
            final moitie = (apres.debutMs - bf.finMs) ~/ 2;
            finMs = bf.finMs + (moitie > 400 ? 400 : moitie);
          } else {
            // Fin de verset : rien apres, on ajoute une marge fixe modeste.
            finMs = bf.finMs + 250;
          }
          joue = await WordCorrectionAudio.playRangeMs(
              chemin, bd.debutMs, finMs,
              etiquette: '${widget.verse.key} palier mots $start..$end');
        } else {
          joue = await WordCorrectionAudio.playWordWindow(widget.verse, reciter,
              startWordIdx: start, endWordIdx: end);
        }
        if (!mounted) return;
      }
      // ── TEXTE ET AUDIO DANS LA MÊME LIGNE (2026-08-27) ──────────────────
      //
      // Constat utilisateur, persistant : « il y a toujours un écart dans la
      // mémorisation par palier entre l'audio qui récite et le texte ».
      // Deux causes déjà traitées et écartées ici : le glissement de fenêtre
      // (2026-08-09) et l'ordre setup/audio (2026-08-11) ; l'indexation des
      // mots a été vérifiée le 2026-08-27 -- `splitExpectedWords` et
      // `word_segments_mp3quran_afasy.json` donnent le MÊME nombre de mots
      // sur les 6 236 versets, sans une seule exception. La cause restante
      // n'est donc pas décidable depuis le code seul.
      //
      // On journalise donc les deux côtés CÔTE À CÔTE : le texte réellement
      // affiché et les bornes réellement jouées. La prochaine occurrence dira
      // lequel des deux a raison, au lieu d'avoir à le deviner.
      DiagnosticLog.log('Palier',
          'audio du palier ${_unitsIntroduced}/$_totalUnits mots=$start..$end '
          '(total mots verset=${_words.length}) : '
          '${joue ? "joue" : "ABSENT -- l utilisateur n a rien entendu"} '
          '| texte affiche="$windowText"');
    }

    _handledThisSession = false;
    _finAuto?.cancel();
    _finAuto = null;
    setState(() => _phase = _RoundPhase.listening);
    // ── LE MODE CONTINU, SINON RIEN N'EST JUGÉ (2026-08-17) ────────────────
    //
    // DÉFAUT MESURÉ, constat utilisateur : « j'ai effectué un test coach
    // mémorisation par palier, ça ne passe pas ». Journal de la session, après
    // le passage au palier (`[v2] cible = 6 mots`) :
    //     verdicts `[V2] mot=`      : 0
    //     fenêtres `[v2] f=` traitées : 0
    //     lignes `[TEXTDIFF]`        : 24, toutes `sim=1.00 isExact=true`
    // La récitation était donc JUSTE, et pourtant le palier échouait.
    //
    // CAUSE : `start()` est le chemin NON CONTINU. L'alimentation de la
    // chaîne v2 en PCM passe uniquement par `_processContinuousChunk` (cf.
    // `RecitationVerifier`) -- son nom le dit. En mode non continu, la v2 est
    // bien ACTIVÉE (`chaine parallele ACTIVE` au journal) mais ne reçoit
    // jamais d'audio : aucune fenêtre, aucun verdict, tous les mots restent
    // `pending`. Or `_onRoundFinished` exige que TOUS soient `correct` ou
    // `unclear` -- l'échec était donc systématique, quelle que soit la
    // qualité de la récitation.
    //
    // Les `TEXTDIFF` ne peignent rien et ne décident rien : leur propre ligne
    // le rappelle (« gop pilote l'affichage »). Ils ne pouvaient donc pas
    // sauver ce chemin.
    //
    // `startControle()` est le point d'entrée continu, celui qu'utilise
    // l'écran de récitation. Même famille de défaut que le contrôle tajwid et
    // la Bismillah : un chemin écrit pour la v1, resté en place, qui a cessé
    // d'agir le jour où la v2 a pris l'affichage sans que personne le décide.
    ref.read(recitationProvider.notifier).startControle();
  }

  /// Les mots du tour COURANT, repeints avec les statuts du dernier essai.
  ///
  /// Sur un rejeu après échec, les deux fenêtres ont la même longueur et
  /// l'utilisateur revoit exactement ses fautes. Sur un palier NEUF, la
  /// fenêtre s'est allongée : les mots déjà tentés gardent leur couleur, les
  /// mots neufs restent neutres -- ce qui distingue visuellement, et sans un
  /// mot d'explication, ce qu'il connaît de ce qu'il découvre.
  /// Fiche du mot : ce que le modele a entendu, et surtout QUELLE regle de
  /// tajwid a manque (2026-09-05).
  ///
  /// Meme feuille que le Coach et le karaoke -- pas une copie. Deux
  /// differences avec l'appel du Coach, et ce sont elles que l'utilisateur
  /// demandait :
  ///
  ///   [reglesManquantes] : ce que le mot n'a PAS realise. Vient de
  ///     `unrealizedRulesFor`, la meme source que le journal et le violet de
  ///     l'ecran -- la fiche ne peut donc pas reprocher autre chose que ce qui
  ///     a ete reproche. Le garde `motsDegradesTajwid.contains` evite de
  ///     lister des regles sur un mot rate pour une lettre ou une haraka : la
  ///     regle ne se juge qu'une fois les lettres bonnes.
  ///
  ///   [scoresRegles] : de COMBIEN la regle a ete ratee -- la barre de
  ///     progression posee le meme jour. Vide si le mot n'a pas ete observe :
  ///     aucune barre vaut mieux qu'une barre a zero, qui se lirait « rien
  ///     fait » alors qu'on n'a rien mesure.
  ///
  /// Un seul verset dans le palier : l'index global du mot EST son index
  /// local, contrairement au Coach qui concatene une portion entiere.
  void _ouvrirDetailMot(List<RecitedWord> mots, int i) {
    if (i < 0 || i >= mots.length) return;
    final n = ref.read(recitationProvider.notifier);
    // Meme extrait « Ma voix » qu'ailleurs : le mot en cause et ses voisins
    // en erreur, jamais l'aya entiere (defaut corrige le 2026-08-24 sur les
    // deux autres ecrans -- ne pas le reintroduire ici).
    final (debut, finExclusif) = etendreAuxMotsContigusEnErreur(
      words: mots,
      wordIndexGlobal: i,
      wordIndexLocal: i,
      motsDuVerset: _words.length,
    );
    showTajwidHelpSheet(
      context,
      ref,
      verse: widget.verse,
      playlist: [widget.verse],
      focusWord: mots[i].display,
      entendu: mots[i].heard,
      reglesManquantes: n.motsDegradesTajwid.contains(i)
          ? n.unrealizedRulesFor(i, mots[i].detectedRules)
          : const [],
      scoresRegles: n.scoresReglesPour(i),
      reglesAVerifier: n.shownRulesFor(i),
      wordIndex: i,
      localWordIndex: i,
      extraitDebut: debut,
      extraitFin: finExclusif,
      riwaya: ref.read(recitationProvider).riwaya,
      onWordContested: () => ref.invalidate(portionsProvider),
    );
  }

  /// Demande la decoupe mesuree de ce verset et l'installe si elle aboutit.
  ///
  /// BORNEE AUX RECITATEURS SERVIS PAR MP3QURAN, et c'est voulu : eux seuls ont
  /// a la fois un fichier de sourate local et des bornes de verset MESUREES
  /// (`ayatTiming`). Pour les autres -- everyayah, un fichier par verset -- il
  /// faudrait un autre chemin d'acces a l'audio ; tant qu'il n'existe pas, ils
  /// gardent le comportement d'avant plutot qu'une demi-mesure.
  ///
  /// Best-effort de bout en bout : tout echec laisse `_coupesMesurees` a `null`,
  /// donc le palier retombe sur les coupes d'Afasy. Rien ne doit empecher un
  /// palier de demarrer.
  Future<void> _mesurerCoupes() async {
    try {
      final r = ref.read(playerProvider).reciter;
      if (!Mp3QuranApi.sertCeReciter(r.id)) {
        // ── UN REPLI SILENCIEUX EST UN TROU DE DIAGNOSTIC (2026-09-06) ────
        //
        // Cette sortie etait MUETTE. Sur une session Warsh -- ou le
        // recitateur passe par everyayah, donc hors MP3Quran -- rien
        // n'apparaissait au journal : ni « la mesure a echoue », ni « la
        // mesure ne s'applique pas ici ». Impossible de distinguer les deux
        // en relisant le log, et c'est exactement la question qu'on se pose
        // devant un palier qui coupe mal.
        DiagnosticLog.log('Decoupe',
            'palier ${widget.verse.key} : recitateur ${r.nameFr} (id=${r.id}) '
            'non servi par MP3Quran -> pas de decoupe mesuree, '
            'repli sur les waqf du texte et les coupes de reference');
        return;
      }
      final s = widget.verse.surahNumber;
      final a = widget.verse.ayahNumber;
      final timing = await Mp3QuranApi.ayatTiming(s,
          read: Mp3QuranApi.readPour(r.id) ?? 123);
      AyahTiming? t;
      for (final e in timing) {
        if (e.ayah == a) { t = e; break; }
      }
      if (t == null) return;
      final chemin = await Mp3QuranApi.fichierLocalSourate(r.id, s);
      final d = await DecoupeAudioService.instance.pour(
        reciterId: r.id, surah: s, ayah: a,
        chemin: chemin, debutMs: t.startMs, finMs: t.endMs,
        mots: _words,
      );
      if (d == null || !mounted) return;
      // ── UN SEUL MOT NON LOCALISE INVALIDE LA DECOUPE ────────────────────
      //
      // Les coupes sont des INDEX DE MOTS : si un mot n'a pas ete place, tous
      // ceux qui suivent peuvent l'etre de travers, et un palier coupe au
      // mauvais endroit est pire que l'approximation qu'on remplace. On exige
      // donc que TOUS les mots soient localises -- sinon on ne prend rien.
      if (d.localises != _words.length) {
        DiagnosticLog.log('Decoupe',
            'palier $s:$a : ${d.localises}/${_words.length} mot(s) localise(s) '
            '-> decoupe mesuree ECARTEE, repli sur les coupes de reference');
        return;
      }
      final fins = d.coupes.map((c) => c.apres).toList()..sort();
      setState(() {
        _coupesMesurees = fins;
        _decoupe = d;
        _cheminAudio = chemin;
      });
      DiagnosticLog.log('Decoupe',
          'palier $s:$a : ${fins.length} coupe(s) MESUREE(S) sur la voix de '
          '${r.nameFr} -> fins=$fins');
    } catch (e) {
      DiagnosticLog.log('Decoupe', 'mesure des coupes ignoree : $e');
    }
  }

  List<RecitedWord> _motsAvecEssaiPrecedent(List<RecitedWord> courants) {
    if (_dernierEssai.isEmpty) return courants;
    return [
      for (var i = 0; i < courants.length; i++)
        i < _dernierEssai.length
            ? courants[i].copyWith(status: _dernierEssai[i].status)
            : courants[i],
    ];
  }

  void _onRoundFinished(RecitationSessionState rst) {
    if (_handledThisSession) return;
    _handledThisSession = true;
    _dernierEssai = List.of(rst.words);
    // ── ICI ON POUSSE A LA REPETITION, PAS AU CONTROLE (2026-08-17) ───────
    //
    // Demande utilisateur : « comme il y aura de la repetition, que le mode
    // soit plus tolerant que le vrai controle de recitation -- ici on pousse
    // a la repetition, si on bloque trop ils vont arreter ».
    //
    // C'est un choix de PRODUIT, et il ne contamine pas le jugement : la
    // recitation de controle garde ses seuils, seule la condition de PASSAGE
    // au palier suivant est assouplie ici.
    //
    // Deux assouplissements, chacun pour une raison distincte :
    //
    //  1. UN MOT JAMAIS JUGE NE COMPTE PLUS CONTRE L'UTILISATEUR. L'ancienne
    //     regle exigeait que TOUS les mots soient `correct` ou `unclear` ; un
    //     seul mot reste `pending` (la chaine ne l'a pas tranche) et le tour
    //     echouait. C'est la regle du projet appliquee au palier : « pas de
    //     rouge sans preuve » -- sans verdict, il n'y a rien a reprocher. On
    //     exige seulement qu'AU MOINS LA MOITIE des mots aient ete juges,
    //     faute de quoi rien n'a vraiment ete dit et valider serait faux.
    //
    //  2. UNE FAUTE SUR TROIS EST TOLEREE parmi les mots juges. En controle,
    //     un mot faux est un mot faux ; en memorisation, s'arreter au premier
    //     ecart casse l'elan que l'exercice cherche justement a creer.
    //
    // ── LE PALIER SE GAGNE SUR SES MOTS NEUFS (2026-08-18) ────────────────
    //
    // DÉFAUT MESURÉ, constat utilisateur : « je récite que le palier 2 et ça
    // passe au palier 4 ». Verset 5:1, `finsUnite=[4, 11, 16, 22]` :
    //
    //   unité | mots neufs   | jugés | verdict
    //     1/4 | 0..4   (5)   |   5   | réussi, à juste titre
    //     2/4 | 5..11  (7)   |   4   | réussi
    //     3/4 | 12..16 (5)   |   0   | RÉUSSI QUAND MÊME
    //
    // L'unité 3 passait avec AUCUN de ses mots neufs récité : ses cinq mots
    // étaient tous `pending`. Cause : la condition portait sur la fenêtre
    // CUMULATIVE (0..16), dont les 10 mots jugés appartenaient tous à la
    // partie déjà connue. Redire ce qu'on savait déjà suffisait donc à
    // franchir le palier suivant -- et comme la fenêtre est cumulative par
    // conception, le défaut s'aggravait à chaque unité.
    //
    // Les SEUILS ne changent pas (moitié des mots dits, une faute sur trois
    // tolérée) : le mode reste celui qui a été validé, « on pousse à la
    // répétition ». Ce qui change est l'ENSEMBLE sur lequel on les applique.
    // Ce n'est donc pas un durcissement de la tolérance, c'est la fin d'un
    // comptage qui mesurait autre chose que ce qu'il prétendait mesurer.
    //
    // La qualité GLOBALE reste vérifiée en plus : s'effondrer sur le début
    // déjà acquis doit continuer à faire échouer le tour.
    // ── LE TAJWID ENTRE DANS LA DECISION (2026-09-02) ────────────────────
    // Cf. l'en-tete de ce correctif : en mode tajwid, un mot dont une regle
    // ATTENDUE n'a pas ete constatee ne compte pas comme reussi, meme si ses
    // lettres sont bonnes. Hors mode tajwid, `unrealizedRulesFor` rend
    // toujours vide (aucune regle active) : ce test est alors inerte et le
    // comportement historique est conserve au caractere pres.
    final notifierRecitation = ref.read(recitationProvider.notifier);
    bool acceptable(int index, RecitedWord w) {
      if (w.status != WordStatus.correct && w.status != WordStatus.unclear) {
        return false;
      }
      return notifierRecitation
          .unrealizedRulesFor(index, w.detectedRules)
          .isEmpty;
    }

    final juges = rst.words
        .where((w) =>
            w.status != WordStatus.pending && w.status != WordStatus.current)
        .toList();
    final acceptables = [
      for (var i = 0; i < rst.words.length; i++)
        if (rst.words[i].status != WordStatus.pending &&
            rst.words[i].status != WordStatus.current &&
            acceptable(i, rst.words[i]))
          i
    ].length;
    final (debutNeufs, finNeufs) = _unitWordRange(_unitsIntroduced - 1);
    final neufs = (debutNeufs < rst.words.length)
        ? rst.words.sublist(
            debutNeufs, math.min(finNeufs + 1, rst.words.length))
        : const <RecitedWord>[];
    // Conservés pour le JOURNAL seulement (ils ne décident plus rien, cf.
    // le bloc « CUMULATIF » ci-dessous) : savoir combien de mots neufs ont
    // réellement été dits est ce qui a permis de trouver ce défaut.
    final jugesNeufs = neufs
        .where((w) =>
            w.status != WordStatus.pending && w.status != WordStatus.current)
        .toList();
    final acceptablesNeufs = [
      for (var i = debutNeufs;
          i <= finNeufs && i < rst.words.length;
          i++)
        if (rst.words[i].status != WordStatus.pending &&
            rst.words[i].status != WordStatus.current &&
            acceptable(i, rst.words[i]))
          i
    ].length;
    // ── CUMULATIF, ET C'EST LA COUVERTURE QUI ÉTAIT FAUSSE (2026-08-18) ───
    //
    // Correction de la correction ci-dessus, sur reprise directe de
    // l'utilisateur : « non, le palier se gagne sur P1+P2, c'est cumulatif ».
    // Faire porter la condition sur les seuls mots NEUFS était donc une
    // mauvaise lecture du besoin -- réciter le palier 2, c'est réciter P1 ET
    // P2, pas seulement le fragment ajouté.
    //
    // Le vrai défaut n'était pas l'ENSEMBLE mais le SEUIL : exiger la MOITIÉ
    // de la fenêtre laissait passer un tour où seule la partie déjà connue
    // avait été dite -- et cette partie grossit à chaque unité, donc le défaut
    // s'aggravait tout seul. Sur 5:1 (`finsUnite=[4, 11, 16, 22]`) :
    //
    //   unité | mots fenetre | jugés | 1/2 (avant) | 3/4 (ici)
    //     1/4 |       5      |   5   |   passe     |  passe
    //     2/4 |      12      |   9   |   passe     |  passe (tout juste)
    //     3/4 |      17      |  10   |   PASSE     |  ECHOUE  <- le defaut
    //     4/4 |      23      |   0   |   echoue    |  echoue
    //
    // Trois quarts, pas la totalité : le dernier mot d'une fenêtre reste
    // souvent sans verdict, et exiger 100 % ferait échouer des tours corrects.
    // La tolérance de QUALITÉ (une faute sur trois) ne bouge pas -- le mode
    // « on pousse à la répétition » est inchangé, c'est bien la couverture,
    // et elle seule, qui se resserre.
    // ── CHAQUE PALIER DOIT ÊTRE VALIDÉ, COUVERTURE COMPRISE ──────────────
    //
    // Troisième et dernière forme de cette condition (2026-08-18). Les deux
    // précédentes sont conservées en tête de méthode parce qu'elles disent
    // POURQUOI celle-ci a cette forme :
    //   1. seuil à la moitié sur la fenêtre entière -> l'unité 3 passait avec
    //      ZÉRO mot neuf récité ;
    //   2. seuil aux trois quarts, toujours sur la fenêtre entière -> mesuré
    //      le 2026-08-18 à 19:58 : `juges=13/17`, donc `13x4=52 >= 51`,
    //      franchi d'un point avec 2 mots neufs sur 6. Constat utilisateur :
    //      « j'ai l'impression d'être passé au palier 4 sans pouvoir valider
    //      P1+P2+P3 ».
    //
    // La leçon des deux est la même : TOUT seuil calculé sur la fenêtre
    // entière est moyennable, et la partie déjà acquise grossit à chaque
    // palier -- elle finit toujours par payer pour la partie manquante.
    //
    // La condition est donc évaluée UNITÉ PAR UNITÉ, sur les deux plans :
    //   - couverture : au moins 3/4 des mots de l'unité ont un verdict
    //     (pas 100 % : le dernier mot d'une fenêtre reste souvent sans
    //     verdict, l'exiger ferait échouer des tours corrects) ;
    //   - qualité : au plus une faute sur trois parmi ces mots jugés.
    //
    // Les SEUILS n'ont pas bougé depuis le mode tolérant validé le
    // 2026-08-17 (« on pousse à la répétition »). Ce qui change, et c'est
    // tout, c'est qu'ils cessent d'être moyennables entre paliers : réussir
    // le palier 3, c'est avoir validé P1 ET P2 ET P3.
    var uniteFautive = -1;
    var motifFautif = '';
    for (var u = 0; u < _unitsIntroduced; u++) {
      final (a, b) = _unitWordRange(u);
      if (a >= rst.words.length) break;
      final motsU = rst.words.sublist(a, math.min(b + 1, rst.words.length));
      if (motsU.isEmpty) continue;
      final jU = motsU
          .where((w) =>
              w.status != WordStatus.pending && w.status != WordStatus.current)
          .toList();
      final okU = jU
          .where((w) =>
              w.status == WordStatus.correct || w.status == WordStatus.unclear)
          .length;
      if (jU.length * 4 < motsU.length * 3) {
        uniteFautive = u + 1;
        motifFautif = 'pas assez dit (${jU.length}/${motsU.length})';
        break;
      }
      if (okU * 3 < jU.length * 2) {
        uniteFautive = u + 1;
        motifFautif = 'trop de fautes ($okU/${jU.length})';
        break;
      }
      // ── LE TAJWID NE SE MOYENNE PAS (2026-09-03) ──────────────────────
      //
      // Constat utilisateur, palier franchi sous ses yeux : « j'ai eu un
      // violet mais il est passé au palier suivant ». Puis la consigne :
      // « obligé de valider la règle quand c'est mode règle de tajwid, ça
      // devient obligatoire ».
      //
      // POURQUOI ÇA PASSAIT. `acceptable()` teste bien le tajwid -- mais
      // elle ne servait qu'à COMPTER (`acceptables`, journalisé). La
      // décision, elle, se prenait sur `okU`, qui accepte `correct` ET
      // `unclear` : le violet y comptait comme un mot réussi. Un palier de
      // quatre mots dont un violet donnait 4/4, et passait.
      //
      // LES DEUX TOLÉRANCES SONT DIFFÉRENTES, et c'est voulu :
      //   PRONONCIATION -- 2/3 suffisent (tolérance du mode adulte,
      //     inchangée au caractère près ci-dessus) ;
      //   TAJWID -- aucune tolérance. Une seule règle attendue et non
      //     constatée fait échouer le palier.
      //
      // Hors mode tajwid, `unrealizedRulesFor` rend toujours vide (aucune
      // règle active) : `tajwidRates` est alors vide et ce test est inerte,
      // le comportement historique est conservé exactement.
      final tajwidRates = [
        for (var k = 0; k < motsU.length; k++)
          if (motsU[k].status != WordStatus.pending &&
              motsU[k].status != WordStatus.current &&
              !acceptable(a + k, motsU[k]) &&
              (motsU[k].status == WordStatus.correct ||
                  motsU[k].status == WordStatus.unclear))
            a + k
      ];
      if (tajwidRates.isNotEmpty) {
        uniteFautive = u + 1;
        motifFautif =
            'règle de tajwid non validée (mots ${tajwidRates.join(",")})';
        break;
      }
    }
    final assezDit = uniteFautive < 0;
    final success = assezDit;
    // DIAGNOSTIC (2026-08-17) : « tout est vert mais je reste sur palier 1 ».
    // Le journal montre le verdict des mots, jamais la DECISION de l'ecran :
    // impossible de dire si le tour conclut a l'echec, ou s'il conclut au
    // succes sans faire avancer le palier. On ecrit donc les deux.
    DiagnosticLog.log('Palier',
        'fin de tour : success=$success unite=$_unitsIntroduced/$_totalUnits '
        'mots=${rst.words.length} juges=${juges.length} acceptables=$acceptables '
        'NEUFS=$debutNeufs..$finNeufs (${neufs.length} mots, '
        '${jugesNeufs.length} juge(s), $acceptablesNeufs acceptable(s)) '
        'assezDit=$assezDit '
        '${uniteFautive > 0 ? "PALIER FAUTIF=P$uniteFautive ($motifFautif) " : ""}'
        'statuts=[${rst.words.map((w) => w.status.name).join(",")}] '
        'finsUnite=$_finsUnite');
    if (success) {
      _onRoundSuccess();
    } else {
      _onRoundFailure();
    }
  }

  Future<void> _onRoundSuccess() async {
    if (_unitsIntroduced >= _totalUnits) {
      // ── LE CONTROLE EST UNE PORTE, PAS UN BILAN DE FIN (2026-08-18) ─────
      //
      // Demande utilisateur : « pour passer au verset 3 on réussit 1 et 2 ;
      // si on a commencé au verset 5, pour passer au 7 on doit réussir 5 et
      // 6 ». Le contrôle cesse donc d'attendre le DERNIER verset : il tombe
      // après CHAQUE verset entraîné, sur le cumul depuis le départ, et c'est
      // sa réussite qui ouvre le suivant.
      //
      // Effet de bord voulu, signalé le même jour : « entre le passage de
      // entraînement à contrôle enlève le clic, on passe direct ». C'est
      // exactement ce que ça fait -- l'ancien chemin appelait `nextVerse()`,
      // qui REPART en Lecture (`withVerseIndex` réinitialise le mode), donc
      // l'utilisateur devait re-traverser Lecture à la main. En allant au
      // contrôle, puis au verset suivant par `advanceAfterPerfectControl()`
      // (qui vise `apprentissage`), plus aucune étape ne se traverse au tap.
      //
      // Bascule désactivée : comportement d'avant, mot pour mot.
      // Trace posee le 2026-08-19 : le journal disait `fin de tour
      // success=true` sans jamais dire QUELLE branche suivait, ni si le
      // drapeau cumul avait ete lu. Constat utilisateur : « il se contente de
      // valider l'en-cours ». Sans cette ligne, impossible de distinguer
      // « la branche cumul n'a pas ete prise » de « elle a ete prise et le
      // controle n'a pas suivi ».
      final cumul = ref.read(coachControleCumulatifProvider);
      DiagnosticLog.log('Palier',
          'verset termine : unites=$_unitsIntroduced/$_totalUnits '
          'cumul=$cumul isLastVerse=${widget.isLastVerse} '
          '-> ${cumul ? "CONTROLE" : (widget.isLastVerse ? "fin" : "verset suivant")}');
      if (cumul) {
        widget.onAllVersesDone();
        return;
      }
      // Verset entièrement validé.
      if (!widget.isLastVerse) {
        final t = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.coachIncrementalVerseAdvance),
            duration: const Duration(seconds: 2),
          ),
        );
        ref.read(coachProvider.notifier).nextVerse();
        // Le changement de currentVerseIndex recrée cet écran avec une
        // nouvelle clé (cf. coach_screen.dart) -- l'état local repart de
        // zéro naturellement, rien à réinitialiser ici.
      } else {
        widget.onAllVersesDone();
      }
      return;
    }
    setState(() => _unitsIntroduced++);
    await _startRound(playAudio: true);
  }

  void _onRoundFailure() {
    // ── ÉCHEC : MÊME PALIER, ET ON REJOUE L'AUDIO (2026-08-17) ────────────
    //
    // Demande utilisateur : « si le user ne réussit pas, on reste sur le même
    // palier et l'audio est rejoué ».
    //
    // `_unitsIntroduced` n'est PAS incrémenté ici (il ne l'était déjà pas) :
    // le palier ne bouge donc pas. Ce qui change, c'est qu'on relance
    // l'exercice avec l'audio -- entendre à nouveau le modèle est
    // précisément ce dont on a besoin après un échec, alors qu'avant il
    // fallait le redemander à la main.
    _shake.forward(from: 0);
    setState(() => _phase = _RoundPhase.retryReady);
    // Laisse la secousse se voir avant de relancer : enchaîner l'audio dans
    // la même frame donnerait l'impression que rien n'a été signalé.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_phase != _RoundPhase.retryReady) return; // l'utilisateur a agi
      _startRound(playAudio: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rst = ref.watch(recitationProvider);

    ref.listen<RecitationSessionState>(recitationProvider, (prev, next) {
      // _phase peut déjà valoir `processing` ici : le bloc juste en dessous le
      // fait passer de `listening` à `processing` dès que rst.status devient
      // `processing`, AVANT que ce listener ne voie le `finished` qui suit.
      // Se limiter à `listening` laissait alors ce `finished` sans effet --
      // le tour restait bloqué sur le spinner "Analyse en cours" pour
      // toujours (constaté sur device 2026-08-01). `_handledThisSession`
      // reste la seule garde nécessaire contre un double déclenchement.
      if (next.status == RecitationStatus.finished &&
          prev?.status != RecitationStatus.finished &&
          (_phase == _RoundPhase.listening || _phase == _RoundPhase.processing)) {
        _onRoundFinished(next);
      }
      // Arrêt automatique : le dernier mot de la fenêtre a été ATTEINT et la
      // voix est retombée depuis [_delaiSilence]. Cf. la doc de `_finAuto`.
      if (_phase == _RoundPhase.listening) {
        // ⚠️ « TOUS JUGÉS » NE MARCHE PAS ICI (corrigé le 2026-08-18, mesuré :
        // 0 déclenchement sur 4 tours). Le DERNIER mot n'obtient son verdict
        // qu'à la fermeture de session -- c'est-à-dire à l'instant même qu'on
        // cherche à provoquer. La condition était donc vraie trop tard, ou
        // jamais.
        //
        // Le bon signal est que le récitateur a ATTEINT le dernier mot de la
        // fenêtre : son statut quitte `pending` (il passe `current`) dès que
        // l'ancre arrive dessus, sans attendre de verdict.
        final dernier = next.words.isEmpty ? null : next.words.last;
        final finAtteinte =
            dernier != null && dernier.status != WordStatus.pending;
        if (finAtteinte && next.soundLevel < _seuilSilence) {
          // `??=` : ne pas ré-armer à chaque bloc PCM, sinon le minuteur
          // repart de zéro en permanence et n'échoit jamais.
          _finAuto ??= Timer(_delaiSilence, () {
            _finAuto = null;
            if (!mounted || _phase != _RoundPhase.listening) return;
            DiagnosticLog.log('Palier',
                'arret auto : dernier mot atteint + silence '
                '${_delaiSilence.inMilliseconds} ms');
            ref.read(recitationProvider.notifier).stopContinuous();
          });
        } else {
          // Il reparle, ou un mot vient de repasser en cours de jugement :
          // on désarme, la fin n'est plus acquise.
          _finAuto?.cancel();
          _finAuto = null;
        }
      }
    });

    if (_phase == _RoundPhase.listening &&
        rst.status == RecitationStatus.processing) {
      _phase = _RoundPhase.processing;
    }

    final listening = _phase == _RoundPhase.listening &&
        rst.status == RecitationStatus.listening;
    final processing = _phase == _RoundPhase.processing;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          InfoBanner(
            icon: Icons.mic_outlined,
            text: t.coachIncrementalInstruction,
          ),
          const SizedBox(height: 14),
          _UnitProgressBar(done: _unitsIntroduced, target: _totalUnits),
          const SizedBox(height: 14),
          // ── LE TEXTE NE S'AFFICHE QU'APRÈS (2026-08-17) ──────────────────
          //
          // Demande utilisateur : « dans cette page je ne veux pas
          // d'affichage, il se fait après la répétition ».
          //
          // C'est le sens même de l'exercice : on écoute, on répète DE
          // MÉMOIRE, et le texte ne vient qu'ensuite -- pour vérifier. Le
          // montrer pendant l'écoute transforme la mémorisation en lecture,
          // et le verdict ne mesure alors plus rien.
          //
          // Masqué pendant `playingAudio` et `listening` ; visible en
          // `processing` (le verdict arrive) et `retryReady` (on montre ce
          // qu'il fallait dire), ainsi que pendant `loadingModel` où rien
          // n'est encore demandé.
          // ── RÉVISION 2026-08-18 : VISIBLE PENDANT L'AUDIO DU RÉCITATEUR ──
          //
          // Le partage se déplace d'un cran, sur demande utilisateur. Le
          // principe ci-dessus n'est pas abandonné, il est PRÉCISÉ : ce qui
          // transforme la mémorisation en lecture, c'est de voir le texte
          // pendant qu'on récite SOI-MÊME. Le voir pendant que le RÉCITATEUR
          // récite, c'est suivre le modèle -- et après un échec, c'est
          // regarder où on s'est trompé, avec l'orange et le rouge de l'essai
          // qu'on vient de rater.
          //
          // Donc : visible en `playingAudio`, masqué en `listening` (c'est là
          // que la mémoire travaille), visible ensuite comme avant.
          if (_phase != _RoundPhase.listening)
            VerseDisplay(
                // ── LE VIOLET DU TAJWID MANQUAIT ICI (2026-09-03) ────────
                //
                // Constat utilisateur : « je ne vois aucun violet alors que je
                // fais exprès de ne pas faire de règle ». Le moteur faisait
                // pourtant son travail -- le journal porte bien les lignes
                // `[V2tajwid] mot=N règle(s) ATTENDUE(S) et NON DÉTECTÉE(S)`,
                // et le statut passait bien à `unclear`.
                //
                // C'était l'AFFICHAGE : `motsTajwidRates` n'était pas passé,
                // donc il valait `const {}` et `VerseDisplay` peignait le mot
                // en ORANGE (imprécis) au lieu de VIOLET (règle manquante).
                // Les deux n'appellent pas le même geste : l'orange dit
                // « redis-le mieux », le violet dit « les lettres étaient
                // justes, c'est la règle qui manque ».
                //
                // ── ET POURQUOI CE N'EST PAS `classifyError` ────────────
                //
                // Première version : `classifyError(i) == tajwid`. Elle ne
                // peignait toujours rien, et la cause n'est pas dans le tajwid.
                // `classifyError` REDEVINE la cause après coup en recomparant
                // attendu et entendu, et il teste les harakat AVANT le tajwid
                // -- à juste titre, une règle ne se juge que si les lettres et
                // les voyelles sont bonnes. Mais la transcription porte presque
                // toujours une diacritique de plus ou de moins : il sortait sur
                // `harakat`, et n'atteignait jamais la branche `tajwid`.
                //
                // Le provider, lui, SAIT : il vient de constater la règle
                // manquante au moment où il a dégradé le mot. On lui demande ce
                // qu'il a enregistré, au lieu de le redériver depuis le texte.
                motsTajwidRates:
                    ref.read(recitationProvider.notifier).motsDegradesTajwid,
                words: _phase == _RoundPhase.playingAudio
                    ? _motsAvecEssaiPrecedent(rst.words)
                    : rst.words,
                // ── LE DETAIL DE LA FAUTE, AU CLIC (2026-09-05) ───────────
                //
                // Demande utilisateur : « dans l'entrainement par palier, la
                // possibilite de cliquer sur le mot pour avoir le detail de ce
                // qu'on rate -- inclus les regles de tajwid ». Constat qui
                // l'accompagne, et qui etait exact : « actuellement on ne peut
                // pas savoir le detail des fautes dans l'entrainement par
                // palier ».
                //
                // Le palier montrait la COULEUR d'un verdict sans jamais
                // pouvoir dire ce qu'elle reproche. C'est le seul des trois
                // ecrans de recitation ou le mot n'etait pas cliquable :
                // `VerseDisplay` porte `onProblemWordTap` depuis longtemps, le
                // Coach le branche -- le palier, non. Rien a construire donc,
                // seulement a relier.
                onProblemWordTap: (i) => _ouvrirDetailMot(rst.words, i),
                verses: [widget.verse])
          else
            _TexteMasque(hint: t.coachIncrementalListening),
          const SizedBox(height: 28),
          if (_phase == _RoundPhase.loadingModel)
            _PreparingIndicator(text: t.coachIncrementalPreparing)
          else if (_phase == _RoundPhase.playingAudio)
            _PlayingAudioIndicator(text: t.coachIncrementalListening)
          else
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final offset =
                    math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value);
                return Transform.translate(offset: Offset(offset, 0), child: child);
              },
              child: MicSection(
                listening: listening,
                processing: processing,
                finished: false,
                pulse: _pulse,
                statusText: listening
                    ? t.coachIncrementalListening
                    : t.coachIncrementalTapToStart,
                onTap: () {
                  final n = ref.read(recitationProvider.notifier);
                  if (listening) {
                    // ── L'ARRÊT DOIT ÊTRE CELUI DU MODE CONTINU (2026-08-17)
                    //
                    // Le tour démarre par `startControle()` : son pendant est
                    // `stopContinuous()`, pas `stop()`. Deux raisons, et la
                    // seconde décide du verdict :
                    //  1. `stop()` commence par `if (!state.isActive) return`
                    //     et ne connaît pas la session continue ;
                    //  2. `stopContinuous()` appelle `v2Terminer()`, la
                    //     dernière analyse de la queue d'audio HORS grille.
                    //     Sans elle, « les derniers mots prononcés restent
                    //     provisoire -- donc NON VERTS -- à jamais » (défaut
                    //     déjà mesuré, cf. sa doc). Sur un palier de quelques
                    //     mots, ce sont précisément eux qui décident du
                    //     succès : l'oublier aurait remplacé un échec
                    //     systématique par un autre.
                    n.stopContinuous();
                  } else {
                    _startRound(playAudio: false);
                  }
                },
                onReset: () => _startRound(playAudio: false),
              ),
            ),
          // PAS de RawTranscriptBox (retiré 2026-08-09, demande utilisateur :
          // « n'affiche pas entendu, on fait juste colorié »).
        ],
      ),
    );
  }
}

class _UnitProgressBar extends StatelessWidget {
  final int done;
  final int target;
  const _UnitProgressBar({required this.done, required this.target});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reached = done >= target;
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.green100,
              valueColor: AlwaysStoppedAnimation(
                  reached ? AppColors.brass : AppColors.green600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          t.coachIncrementalUnitProgress(done, target),
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: reached ? AppColors.brass : AppColors.inkLight,
          ),
        ),
      ],
    );
  }
}

/// État "Préparation…" pendant `ensureModelLoaded()` -- JAMAIS le nom
/// technique du modèle (demande explicite utilisateur 2026-07-24).
class _PreparingIndicator extends StatelessWidget {
  final String text;
  const _PreparingIndicator({required this.text});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.brass),
          ),
          const SizedBox(height: 10),
          Text(text,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.brass, fontWeight: FontWeight.w600)),
        ],
      );
}

class _PlayingAudioIndicator extends StatelessWidget {
  final String text;
  const _PlayingAudioIndicator({required this.text});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Icon(Icons.volume_up_rounded, color: AppColors.brass, size: 44),
          const SizedBox(height: 10),
          Text(text,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight, fontWeight: FontWeight.w500)),
        ],
      );
}


/// Ce qu'on montre à la place du texte pendant l'écoute et la répétition.
///
/// Un bloc VIDE aurait fait sauter la mise en page à chaque tour (le texte
/// apparaît puis disparaît) et laissé croire à un écran cassé. On garde donc
/// la place, avec une consigne : l'utilisateur sait qu'il doit réciter de
/// mémoire, pas qu'il manque quelque chose.
class _TexteMasque extends StatelessWidget {
  final String hint;
  const _TexteMasque({required this.hint});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.green900.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cream300),
        ),
        child: Column(
          children: [
            Icon(Icons.visibility_off_outlined,
                size: 26, color: AppColors.inkLight.withValues(alpha: 0.7)),
            const SizedBox(height: 10),
            Text(hint,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkLight)),
          ],
        ),
      );
}
