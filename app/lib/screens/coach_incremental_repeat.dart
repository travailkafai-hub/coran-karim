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
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../providers/app_settings_provider.dart'
    show coachControleCumulatifProvider;
import '../services/coupes_palier_service.dart';
import '../services/mp3quran_api.dart' show Mp3QuranWordSegments;
import '../services/diagnostic_log.dart';
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
  /// Le mode ENFANT garde un mot par unité : le but y est d'ancrer chaque mot
  /// séparément, pas de respecter le phrasé.
  ///
  /// Repli si l'asset manque ou ne couvre pas ce verset : le verset entier
  /// forme une seule unité. Dégradé, jamais cassé -- et jamais un découpage
  /// arbitraire qui recréerait le défaut qu'on vient de supprimer.
  List<int> get _finsUnite {
    final preset = ref.read(judgementOptionsProvider).preset;
    final dernier = _words.length - 1;
    if (dernier < 0) return const [];
    if (preset == JudgementPreset.enfant) {
      return [for (var i = 0; i <= dernier; i++) i];
    }
    final coupes = CoupesPalierService.instance
        .coupes(widget.verse.surahNumber, widget.verse.ayahNumber)
        .where((i) => i >= 0 && i < dernier)
        .toList();
    return [...coupes, dernier];
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
    Future.microtask(() => ref.read(recitationProvider.notifier).setup(''));
    // Coupes de palier mesurées sur la récitation (cf. `_finsUnite`).
    // Idempotent, et sans conséquence si l'asset manque : `coupes()` rend
    // alors une liste vide et le verset forme un seul palier.
    CoupesPalierService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    final reciter = ref.read(playerProvider).reciter;
    unawaited(WordCorrectionAudio.prefetch(widget.verse, reciter));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startRound(playAudio: true);
    });
  }

  @override
  void dispose() {
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
    ref.read(recitationProvider.notifier).setup(windowText);

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
      final reciter = ref.read(playerProvider).reciter;
      var joue = await WordCorrectionAudio.playWordWindow(widget.verse, reciter,
          startWordIdx: start, endWordIdx: end);
      if (!mounted) return;
      if (!joue) {
        await Mp3QuranWordSegments.instance.ensureLoaded();
        if (!mounted) return;
        joue = await WordCorrectionAudio.playWordWindow(widget.verse, reciter,
            startWordIdx: start, endWordIdx: end);
        if (!mounted) return;
      }
      DiagnosticLog.log('Palier',
          'audio du palier ${_unitsIntroduced}/$_totalUnits mots=$start..$end : '
          '${joue ? "joue" : "ABSENT -- l utilisateur n a rien entendu"}');
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
    final juges = rst.words
        .where((w) =>
            w.status != WordStatus.pending && w.status != WordStatus.current)
        .toList();
    final acceptables = juges
        .where((w) =>
            w.status == WordStatus.correct || w.status == WordStatus.unclear)
        .length;
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
    final acceptablesNeufs = jugesNeufs
        .where((w) =>
            w.status == WordStatus.correct || w.status == WordStatus.unclear)
        .length;
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
                words: _phase == _RoundPhase.playingAudio
                    ? _motsAvecEssaiPrecedent(rst.words)
                    : rst.words,
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
