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

import 'dart:async' show unawaited;
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

  List<String> get _words => ArabicNormalizer.splitExpectedWords(widget.verse.textUthmani);

  int get _unitSize {
    final preset = ref.read(judgementOptionsProvider).preset;
    return preset == JudgementPreset.enfant
        ? 1
        : ref.read(adultChunkWordCountProvider);
  }

  int get _totalUnits => (_words.length / _unitSize).ceil();

  /// Bornes (index de mot, inclusifs) de l'unité [unitIndex].
  (int, int) _unitWordRange(int unitIndex) {
    final start = unitIndex * _unitSize;
    final end = math.min((unitIndex + 1) * _unitSize, _words.length) - 1;
    return (start, end);
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
    final reciter = ref.read(playerProvider).reciter;
    unawaited(WordCorrectionAudio.prefetch(widget.verse, reciter));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startRound(playAudio: true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shake.dispose();
    ref.read(recitationProvider.notifier).stop();
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
      setState(() => _phase = _RoundPhase.playingAudio);
      final reciter = ref.read(playerProvider).reciter;
      await WordCorrectionAudio.playWordWindow(widget.verse, reciter,
          startWordIdx: start, endWordIdx: end);
      if (!mounted) return;
    }

    _handledThisSession = false;
    setState(() => _phase = _RoundPhase.listening);
    ref.read(recitationProvider.notifier).start();
  }

  void _onRoundFinished(RecitationSessionState rst) {
    if (_handledThisSession) return;
    _handledThisSession = true;
    final success = rst.words.isNotEmpty &&
        rst.words.every((w) =>
            w.status == WordStatus.correct || w.status == WordStatus.unclear);
    if (success) {
      _onRoundSuccess();
    } else {
      _onRoundFailure();
    }
  }

  Future<void> _onRoundSuccess() async {
    if (_unitsIntroduced >= _totalUnits) {
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
    _shake.forward(from: 0);
    setState(() => _phase = _RoundPhase.retryReady);
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
          VerseDisplay(words: rst.words, verses: [widget.verse]),
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
                    n.stop();
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
