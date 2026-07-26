import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/coach_session.dart';
import '../models/recitation_state.dart';
import '../models/verse.dart';
import '../providers/coach_provider.dart';
import '../providers/last_coach_verse_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/recitation_verifier.dart';
import '../services/voice_fingerprint_service.dart';
import '../theme/app_theme.dart';
import 'coach_incremental_repeat.dart';
import 'tajwid_rules_screen.dart';
import '../widgets/tajwid_help_sheet.dart';
import '../widgets/tajweed_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class CoachScreen extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const CoachScreen({super.key, required this.verses});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(coachProvider.notifier).setup(widget.verses);
      // Mémorise le verset travaillé pour la carte « Reprendre » du hub Coach
      // (REFONTE_IHM.md §11.2 zone A). Silencieux : un échec d'écriture ne doit
      // jamais empêcher la session de démarrer.
      //
      // ⚠️ DANS le post-frame, pas directement dans initState : lire
      // AppLocalizations (donc `context`) pendant initState lève
      // « dependOnInheritedWidgetOfExactType<_LocalizationsScope>() was called
      // before _CoachScreenState.initState() completed » et l'écran entier
      // s'affiche en rouge d'erreur (constaté sur device 2026-07-22). Le
      // contexte n'est utilisable qu'une fois le premier frame construit.
      final v = widget.verses.first;
      unawaited(recordLastCoachVerse(
        surahNumber: v.surahNumber,
        ayahNumber: v.ayahNumber,
        surahName: AppLocalizations.of(context)!.coachSurahLabel(v.surahNumber),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(coachProvider);
    // Ayah par ayah même sur une sourate entière (demande utilisateur
    // 2026-07-24) : les 3 modes ne travaillent QUE sur le verset courant
    // (session.currentVerse), jamais sur widget.verses entier concaténé.
    final currentVerse = session.verses.isEmpty ? widget.verses.first : session.currentVerse;
    final multiVerse = widget.verses.length > 1;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: currentVerse.key),
            if (multiVerse)
              _VerseNavBar(
                current: session.currentVerseIndex,
                total: widget.verses.length,
                onPrevious: session.hasPreviousVerse
                    ? () => ref.read(coachProvider.notifier).previousVerse()
                    : null,
                onNext: session.hasNextVerse
                    ? () => ref.read(coachProvider.notifier).nextVerse()
                    : null,
              ),
            _StepBar(
              session: session,
              onSelect: (m) => ref.read(coachProvider.notifier).setMode(m),
            ),
            Expanded(
              child: GestureDetector(
                // Glisser pour passer au verset suivant/précédent SANS
                // quitter l'écran (demande utilisateur 2026-07-24, "un
                // scrolling par exemple pour passer à l'ayah suivante") --
                // seuil de vitesse pour ne pas confondre avec un simple
                // scroll vertical du contenu (SingleChildScrollView à
                // l'intérieur de chaque mode).
                onHorizontalDragEnd: !multiVerse
                    ? null
                    : (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v < -250) {
                          ref.read(coachProvider.notifier).nextVerse();
                        } else if (v > 250) {
                          ref.read(coachProvider.notifier).previousVerse();
                        }
                      },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  // Clé incluant l'index du verset : sans ça, rester dans le
                  // même mode (ex. Lecture) en glissant vers l'ayah suivante
                  // réutiliserait le même State et n'appellerait jamais
                  // initState -- l'écran resterait bloqué sur l'ancien
                  // verset "terminé" au lieu de redémarrer proprement.
                  child: switch (session.mode) {
                    CoachMode.lecture => _LectureMode(
                        key: ValueKey('lecture-${session.currentVerseIndex}'),
                        verses: [currentVerse],
                      ),
                    CoachMode.apprentissage => _ApprentissageMode(
                        key: ValueKey(
                            'apprentissage-${session.currentVerseIndex}'),
                        verses: [currentVerse],
                      ),
                    CoachMode.controle => _ControleMode(
                        key:
                            ValueKey('controle-${session.currentVerseIndex}'),
                        verses: [currentVerse],
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseNavBar extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  const _VerseNavBar({
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      color: AppColors.green900,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: onPrevious != null ? AppColors.brassLight : Colors.white24,
            onPressed: onPrevious,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            t.memorizationGameVerseProgress(current + 1, total),
            style: GoogleFonts.manrope(
                fontSize: 12, color: AppColors.brassLight, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: onNext != null ? AppColors.brassLight : Colors.white24,
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.green900, AppColors.green800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.coachHeaderLabel,
                style: GoogleFonts.manrope(
                  color: AppColors.brassLight,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                title,
                style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          const Spacer(),
          // Réglages de vérification (tajwid/adulte/enfant, règles activées)
          // -- retour utilisateur 2026-07-19 : "alléger les paramètres
          // globaux", ce reglage vit ici (le Coach est l'ecran de
          // verification de recitation) plutot que dans Reglages global.
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.brassLight),
            tooltip: t.coachVerificationModeTooltip,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TajwidRulesScreen())),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-Step Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final CoachSessionState session;
  final void Function(CoachMode) onSelect;
  const _StepBar({required this.session, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      color: AppColors.green900,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          _StepChip(
            label: t.coachStepLecture,
            icon: Icons.auto_stories_outlined,
            active: session.mode == CoachMode.lecture,
            done: session.mode1Done,
            onTap: () => onSelect(CoachMode.lecture),
          ),
          _StepLine(done: session.mode1Done),
          _StepChip(
            label: t.coachStepTrain,
            icon: Icons.headphones_outlined,
            active: session.mode == CoachMode.apprentissage,
            done: false,
            onTap: () => onSelect(CoachMode.apprentissage),
          ),
          _StepLine(done: session.mode3Done),
          _StepChip(
            label: t.coachStepControl,
            icon: Icons.visibility_off_outlined,
            active: session.mode == CoachMode.controle,
            done: session.mode3Done,
            onTap: () => onSelect(CoachMode.controle),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool done;
  final VoidCallback onTap;
  const _StepChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.brass
        : done
            ? AppColors.green100
            : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.brass.withAlpha(30)
                  : done
                      ? AppColors.green700.withAlpha(60)
                      : Colors.white10,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(
              done && !active ? Icons.check_rounded : icon,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({required this.done});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 22, left: 6, right: 6),
          decoration: BoxDecoration(
            color: done ? AppColors.green600 : Colors.white12,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 1 — Lecture Guidée
// ─────────────────────────────────────────────────────────────────────────────

class _LectureMode extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const _LectureMode({super.key, required this.verses});

  @override
  ConsumerState<_LectureMode> createState() => _LectureModeState();
}

class _LectureModeState extends ConsumerState<_LectureMode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  final _fingerprint = VoiceFingerprintService();

  String get _text => widget.verses.map((v) => v.textUthmani).join(' ');
  String get _passageKey => widget.verses.map((v) => v.key).join('-');

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recitationProvider.notifier).setup(_text);
    });
    _fingerprint.ensureLoaded();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rst = ref.watch(recitationProvider);
    final coach = ref.watch(coachProvider);
    final listening = rst.status == RecitationStatus.listening;
    final finished = rst.status == RecitationStatus.finished && rst.total > 0;

    if (finished && coach.baselineAccuracy == null) {
      final difficult = rst.words
          .where((w) =>
              w.status == WordStatus.error ||
              w.status == WordStatus.unclear ||
              w.status == WordStatus.skipped)
          .map((w) => w.display)
          .toList();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(coachProvider.notifier).saveBaseline(rst.accuracy, difficult);

        // Empreinte vocale (niveau 1, voir SKILL.md "Vérification par
        // embeddings audio-à-audio") : on ne garde CETTE lecture comme
        // référence QUE si elle est déjà jugée raisonnablement correcte —
        // piège identifié dès l'idée de départ (une 1ère lecture peut
        // contenir des erreurs, ce n'est pas une vérité en soi).
        final audioPath = ref.read(recitationVerifierProvider).lastAudioPath;
        if (audioPath != null && rst.accuracy >= 60) {
          final ok = await _fingerprint.saveReference(audioPath, _passageKey);
          debugPrint('[VoiceFingerprint] Référence "$_passageKey" sauvegardée : $ok');
        }
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          InfoBanner(
            icon: Icons.auto_stories_outlined,
            text: t.coachReadAloudInstruction,
          ),
          const SizedBox(height: 20),
          VerseDisplay(words: rst.words, verses: widget.verses),
          const SizedBox(height: 28),
          MicSection(
            listening: listening,
            processing: rst.status == RecitationStatus.processing,
            finished: finished,
            pulse: _pulse,
            statusText: listening
                ? t.coachListeningLecture
                : finished
                    ? t.coachDoneLecture
                    : t.coachTapToRead,
            onTap: () {
              final n = ref.read(recitationProvider.notifier);
              if (listening) {
                n.stop();
              } else {
                n.setup(_text);
                n.start();
              }
            },
            onReset: () {
              ref.read(recitationProvider.notifier).setup(_text);
              ref.read(recitationProvider.notifier).reset();
            },
          ),
          RawTranscriptBox(text: rst.rawTranscript),
          if (finished) ...[
            const SizedBox(height: 20),
            _ScoreRow(accuracy: rst.accuracy),
            const SizedBox(height: 12),
            _CoachBubble(
              accuracy: rst.accuracy,
              difficultWords: rst.words
                  .where((w) =>
                      w.status == WordStatus.error ||
                      w.status == WordStatus.unclear ||
                      w.status == WordStatus.skipped)
                  .map((w) => w.display)
                  .toList(),
              mode: CoachMode.lecture,
              baseline: null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: t.coachAlreadyKnow,
                    icon: Icons.fast_forward_rounded,
                    primary: false,
                    onTap: () => ref
                        .read(coachProvider.notifier)
                        .setMode(CoachMode.controle),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ActionButton(
                    label: t.coachTrainButton,
                    icon: Icons.arrow_forward_rounded,
                    primary: true,
                    onTap: () => ref
                        .read(coachProvider.notifier)
                        .setMode(CoachMode.apprentissage),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 2 — Apprentissage (3 sous-étapes)
// ─────────────────────────────────────────────────────────────────────────────

List<String> _appStepLabels(AppLocalizations t) =>
    [t.coachSubStepListen, t.coachSubStepImitate, t.coachSubStepRepeat];

class _ApprentissageMode extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const _ApprentissageMode({super.key, required this.verses});

  @override
  ConsumerState<_ApprentissageMode> createState() => _ApprentissageModeState();
}

class _ApprentissageModeState extends ConsumerState<_ApprentissageMode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _audioStarted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final session = ref.watch(coachProvider);
    final step = session.appStep;
    final player = ref.watch(playerProvider);
    final coach = ref.read(coachProvider.notifier);

    return Column(
      children: [
        _AppSubStepBar(currentStep: step, onTap: (i) {
          if (i <= step) coach.setAppStep(i);
        }),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              children: [
                // ── Étape 0 : Écoute ──────────────────────────────────────
                if (step == 0) ...[
                  InfoBanner(
                    icon: Icons.headphones_outlined,
                    text: t.coachListenInstruction,
                  ),
                  const SizedBox(height: 16),
                  VerseDisplay(words: const [], verses: widget.verses),
                  const SizedBox(height: 28),
                  _PlayButton(
                    isPlaying: player.isPlaying,
                    onTap: () {
                      setState(() => _audioStarted = true);
                      if (player.isPlaying) {
                        ref.read(playerProvider.notifier).pause();
                      } else if (player.isPaused) {
                        ref.read(playerProvider.notifier).resume();
                      } else {
                        ref.read(playerProvider.notifier).play(
                              widget.verses.first,
                              widget.verses,
                            );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    player.isPlaying
                        ? t.coachListeningAudio
                        : t.coachTapToListen,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.inkLight),
                  ),
                  if (_audioStarted) ...[
                    const SizedBox(height: 28),
                    ActionButton(
                      label: t.coachMoveToImitation,
                      icon: Icons.arrow_forward_rounded,
                      primary: true,
                      onTap: () {
                        ref.read(playerProvider.notifier).stop();
                        coach.nextAppStep();
                      },
                    ),
                  ],
                ],

                // ── Étape 1 : Imite ───────────────────────────────────────
                if (step == 1) ...[
                  InfoBanner(
                    icon: Icons.record_voice_over_outlined,
                    text: t.coachImitateInstruction,
                  ),
                  const SizedBox(height: 16),
                  VerseDisplay(words: const [], verses: widget.verses),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PlayButton(
                        isPlaying: player.isPlaying,
                        onTap: () {
                          setState(() => _audioStarted = true);
                          if (player.isPlaying) {
                            ref.read(playerProvider.notifier).pause();
                          } else if (player.isPaused) {
                            ref.read(playerProvider.notifier).resume();
                          } else {
                            ref.read(playerProvider.notifier).play(
                                  widget.verses.first,
                                  widget.verses,
                                );
                          }
                        },
                      ),
                      const SizedBox(width: 24),
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context2, child2) => Transform.scale(
                          scale: player.isPlaying
                              ? (0.94 + _pulse.value * 0.12)
                              : 1.0,
                          child: Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: player.isPlaying
                                  ? AppColors.brass.withAlpha(25)
                                  : Colors.grey.withAlpha(18),
                              border: Border.all(
                                color: player.isPlaying
                                    ? AppColors.brass
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.mic,
                              color: player.isPlaying
                                  ? AppColors.brass
                                  : Colors.grey,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    player.isPlaying
                        ? t.coachSpeakAlong
                        : t.coachLaunchAndImitate,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.inkLight),
                  ),
                  const SizedBox(height: 28),
                  ActionButton(
                    label: t.coachImitatedNext,
                    icon: Icons.arrow_forward_rounded,
                    primary: true,
                    onTap: () {
                      ref.read(playerProvider.notifier).stop();
                      coach.nextAppStep();
                    },
                  ),
                ],

                // ── Étape 2 : Répète (moteur incrémental) ──────────────────
                if (step == 2)
                  IncrementalRepeatStep(
                    key: ValueKey('incremental-${widget.verses.first.key}'),
                    verse: widget.verses.first,
                    isLastVerse: session.isLastVerse,
                    onAllVersesDone: () =>
                        coach.setMode(CoachMode.controle),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppSubStepBar extends StatelessWidget {
  final int currentStep;
  final void Function(int) onTap;
  const _AppSubStepBar({required this.currentStep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final labels = _appStepLabels(AppLocalizations.of(context)!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: AppColors.green50,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.only(bottom: 14),
                  color: i <= currentStep
                      ? AppColors.green600
                      : AppColors.green100,
                ),
              ),
            GestureDetector(
              onTap: () => onTap(i),
              child: _SubStepDot(
                index: i,
                label: labels[i],
                currentStep: currentStep,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubStepDot extends StatelessWidget {
  final int index;
  final String label;
  final int currentStep;
  const _SubStepDot(
      {required this.index,
      required this.label,
      required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final done = index < currentStep;
    final active = index == currentStep;
    final bg = active
        ? AppColors.green800
        : done
            ? AppColors.green600
            : AppColors.green100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : Text(
                    '${index + 1}',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: active || done ? Colors.white : AppColors.inkLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            color: active ? AppColors.green800 : AppColors.inkLight,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 3 — Contrôle (récitation aveugle)
// ─────────────────────────────────────────────────────────────────────────────

class _ControleMode extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const _ControleMode({super.key, required this.verses});

  @override
  ConsumerState<_ControleMode> createState() => _ControleModeState();
}

class _ControleModeState extends ConsumerState<_ControleMode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  final _fingerprint = VoiceFingerprintService();
  double? _fingerprintScore;
  bool _fingerprintChecked = false;

  String get _text => widget.verses.map((v) => v.textUthmani).join(' ');
  String get _passageKey => widget.verses.map((v) => v.key).join('-');

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recitationProvider.notifier).setup(_text);
    });
    _fingerprint.ensureLoaded();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  /// Tap sur un mot orange/rouge du résultat : retrouve le verset contenant ce
  /// mot (les mots affichés sont la concaténation des versets, découpés avec
  /// la même règle `\s+` que setup()) et ouvre la fiche tajwid + réciteur.
  void _openWordHelp(List<RecitedWord> words, int wordIndex) {
    var offset = 0;
    for (final v in widget.verses) {
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) {
        showTajwidHelpSheet(
          context,
          ref,
          verse: v,
          playlist: widget.verses,
          focusWord: words[wordIndex].display,
          wordIndex: wordIndex,
          localWordIndex: wordIndex - offset,
        );
        return;
      }
      offset += count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rst = ref.watch(recitationProvider);
    final session = ref.watch(coachProvider);
    final listening = rst.status == RecitationStatus.listening;
    final finished = rst.status == RecitationStatus.finished && rst.total > 0;

    if (finished && session.controlAccuracy == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(coachProvider.notifier).saveControlScore(rst.accuracy);
      });
    }

    if (finished && !_fingerprintChecked) {
      _fingerprintChecked = true;
      final audioPath = ref.read(recitationVerifierProvider).lastAudioPath;
      if (audioPath != null) {
        _fingerprint.compareToReference(audioPath, _passageKey).then((score) {
          if (!mounted) return;
          setState(() => _fingerprintScore = score);
          debugPrint('[VoiceFingerprint] Comparaison "$_passageKey" : $score');
        });
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          InfoBanner(
            icon: Icons.visibility_off_outlined,
            text: t.coachRecallInstruction,
            dark: true,
          ),
          const SizedBox(height: 20),
          // Before finish: blurred card. After: colored words revealed.
          finished
              ? VerseDisplay(
                  words: rst.words,
                  verses: widget.verses,
                  onProblemWordTap: (i) => _openWordHelp(rst.words, i),
                )
              : _BlurredVerse(verses: widget.verses),
          const SizedBox(height: 28),
          MicSection(
            listening: listening,
            processing: rst.status == RecitationStatus.processing,
            finished: finished,
            pulse: _pulse,
            statusText: listening
                ? t.coachListeningControl
                : finished
                    ? t.coachControlDone
                    : t.coachTapToRecall,
            onTap: () {
              final n = ref.read(recitationProvider.notifier);
              if (listening) {
                n.stop();
              } else {
                n.setup(_text);
                ref.read(coachProvider.notifier).resetControl();
                setState(() {
                  _fingerprintChecked = false;
                  _fingerprintScore = null;
                });
                n.start();
              }
            },
            onReset: () {
              ref.read(recitationProvider.notifier).setup(_text);
              ref.read(coachProvider.notifier).resetControl();
              setState(() {
                _fingerprintChecked = false;
                _fingerprintScore = null;
              });
            },
          ),
          RawTranscriptBox(text: rst.rawTranscript),
          if (finished) ...[
            const SizedBox(height: 20),
            _ScoreRow(accuracy: rst.accuracy),
            if (_fingerprintScore != null) ...[
              const SizedBox(height: 8),
              _FingerprintBadge(score: _fingerprintScore!),
            ],
            if (session.baselineAccuracy != null) ...[
              const SizedBox(height: 8),
              _GapCard(
                baseline: session.baselineAccuracy!,
                control: rst.accuracy,
              ),
            ],
            const SizedBox(height: 12),
            _CoachBubble(
              accuracy: rst.accuracy,
              difficultWords: rst.words
                  .where((w) =>
                      w.status == WordStatus.error ||
                      w.status == WordStatus.unclear ||
                      w.status == WordStatus.skipped)
                  .map((w) => w.display)
                  .toList(),
              mode: CoachMode.controle,
              baseline: session.baselineAccuracy,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: t.commonRetry,
                    icon: Icons.replay_rounded,
                    primary: false,
                    onTap: () {
                      ref.read(recitationProvider.notifier).setup(_text);
                      ref.read(coachProvider.notifier).resetControl();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ActionButton(
                    label: t.coachBackToTraining,
                    icon: Icons.headphones_outlined,
                    primary: true,
                    onTap: () => ref
                        .read(coachProvider.notifier)
                        .setMode(CoachMode.apprentissage),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class RawTranscriptBox extends StatelessWidget {
  final String text;
  const RawTranscriptBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cream300.withAlpha(150),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inkLight.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.coachTranscriptLabel,
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkLight),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.scheherazadeNew(
                  fontSize: 20, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool dark;
  const InfoBanner({super.key, required this.icon, required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? AppColors.green900 : AppColors.green50;
    final fg = dark ? AppColors.brassLight : AppColors.green700;
    final tx = dark ? AppColors.cream : AppColors.inkLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: dark ? Colors.transparent : AppColors.green100),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: tx, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class VerseDisplay extends StatelessWidget {
  final List<RecitedWord> words;
  final List<Verse> verses;

  /// Tap sur un mot jugé orange (unclear) ou rouge (error) — ouvre l'aide
  /// tajwid + lecture réciteur en mode Contrôle. Null ailleurs (pas de tap).
  final void Function(int wordIndex)? onProblemWordTap;

  const VerseDisplay({
    super.key,
    required this.words,
    required this.verses,
    this.onProblemWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = words.isNotEmpty
        ? words
        : verses
            .expand((v) => ArabicNormalizer.splitExpectedWords(v.textUthmani)
                .map((w) => RecitedWord(
                      display: w,
                      normalized: ArabicNormalizer.normalize(w),
                      strict: ArabicNormalizer.normalizeStrict(w),
                      training: ArabicNormalizer.normalizeTraining(w),
                    )))
            .toList();

    // Coloration tajwid lettre-par-lettre "partout où le texte apparaît"
    // (demande utilisateur 2026-07-05) — même approche que karaoke_recitation_screen :
    // le texte porte la couleur tajwid, le jugement vert/orange/rouge passe par
    // le fond du chip pour ne jamais se disputer la même couleur.
    final tajwidSpans = [
      for (final v in verses)
        ...tajweedSpansPerWord(
          v.textUthmani,
          v.textUthmaniTajweed,
          GoogleFonts.scheherazadeNew(fontSize: 28, height: 1.9, color: AppColors.ink),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 10,
          children: [
            for (var i = 0; i < display.length; i++)
              _wordChip(display[i], i, tajwidSpans),
          ],
        ),
      ),
    );
  }

  Widget _wordChip(
      RecitedWord w, int index, List<List<TextSpan>> tajwidSpans) {
    final tappable = onProblemWordTap != null &&
        (w.status == WordStatus.unclear ||
            w.status == WordStatus.error ||
            w.status == WordStatus.skipped);

    Color? bgTint;
    Color? borderTint;
    var opacity = 1.0;
    // Fonds plus vifs (retour utilisateur 2026-07-06 : "il y a plus le
    // rouge, le vrai rouge et l'orange" — trop discrets depuis l'intégration
    // du tajwid). Le texte reste coloré tajwid ; le jugement se voit
    // maintenant au fond ET au contour, plus franchement.
    switch (w.status) {
      case WordStatus.correct:
        bgTint = AppColors.green600.withOpacity(0.32);
        borderTint = AppColors.green600;
        break;
      case WordStatus.unclear:
        bgTint = AppColors.tajwidMadd.withOpacity(0.36);
        borderTint = AppColors.tajwidMadd;
        break;
      case WordStatus.error:
        // Rouge SEULEMENT si verrouillé (demande utilisateur 2026-07-09,
        // même souci que karaoke_recitation_screen.dart : un aperçu pas
        // encore figé peut sembler faux un instant avant de se stabiliser).
        if (w.locked) {
          bgTint = const Color(0xFFb00020).withOpacity(0.30);
          borderTint = const Color(0xFFb00020);
        }
        break;
      case WordStatus.skipped:
      case WordStatus.current:
        break;
      case WordStatus.pending:
        opacity = 0.45;
        break;
    }

    final base = GoogleFonts.scheherazadeNew(
        fontSize: 28, height: 1.9, color: AppColors.ink);
    final tajwidWord = index < tajwidSpans.length ? tajwidSpans[index] : null;
    // Mot sauté : gris + souligné pointillé, préservé lettre par lettre pour
    // ne pas perdre la coloration tajwid pendant qu'on signale le saut.
    final decoStyle = TextStyle(
      decoration:
          w.status == WordStatus.skipped ? TextDecoration.underline : null,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: AppColors.inkLight,
    );
    final textWidget = (tajwidWord != null && tajwidWord.isNotEmpty)
        ? RichText(
            text: TextSpan(
              children: [
                for (final s in tajwidWord)
                  TextSpan(
                    text: s.text,
                    children: s.children,
                    recognizer: s.recognizer,
                    style: (s.style ?? base).merge(decoStyle),
                  ),
              ],
            ),
          )
        : Text(w.display, style: base.merge(decoStyle));

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: w.status == WordStatus.current
            ? AppColors.brass.withAlpha(25)
            : bgTint,
        borderRadius: BorderRadius.circular(6),
        border: w.status == WordStatus.current
            ? Border.all(color: AppColors.brass.withAlpha(60))
            : (borderTint != null ? Border.all(color: borderTint, width: 1.5) : null),
      ),
      child: Opacity(opacity: opacity, child: textWidget),
    );
    if (!tappable) return chip;
    return GestureDetector(
      onTap: () => onProblemWordTap!(index),
      child: chip,
    );
  }
}

class _BlurredVerse extends StatelessWidget {
  final List<Verse> verses;
  const _BlurredVerse({required this.verses});

  @override
  Widget build(BuildContext context) {
    final text = verses.map((v) => v.textUthmani).join(' ');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 28, height: 1.9, color: AppColors.ink),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.green900.withAlpha(200),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.visibility_off_rounded,
                        color: AppColors.brassLight, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.green900.withAlpha(180),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.coachRecallBadge,
                      style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MicSection extends StatelessWidget {
  final bool listening;
  final bool processing; // ASR en cours dans compute() — UI doit rester réactive
  final bool finished;
  final AnimationController pulse;
  final String statusText;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const MicSection({
    super.key,
    required this.listening,
    required this.processing,
    required this.finished,
    required this.pulse,
    required this.statusText,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // ── État "processing" : spinner doré pendant l'inférence Whisper ──────────
    if (processing) {
      return Column(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.brass,
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green900.withAlpha(200),
                    border: Border.all(color: AppColors.brass.withAlpha(80)),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.brass, size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.coachAnalyzingAudio,
            style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.brass,
                fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    // ── État normal : mic button ──────────────────────────────────────────────
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AnimatedMicButton(
                listening: listening, pulse: pulse, onTap: onTap),
            if (finished) ...[
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cream300,
                    border: Border.all(color: AppColors.cream300),
                  ),
                  child: const Icon(Icons.replay_rounded,
                      color: AppColors.inkLight, size: 22),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          statusText,
          style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.inkLight,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _AnimatedMicButton extends StatelessWidget {
  final bool listening;
  final AnimationController pulse;
  final VoidCallback onTap;
  const _AnimatedMicButton(
      {required this.listening,
      required this.pulse,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Transform.scale(
          scale: listening ? (1.0 + pulse.value * 0.14) : 1.0,
          child: child,
        ),
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (listening)
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFb00020).withAlpha(25),
                  ),
                ),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: listening
                        ? const [Color(0xFFd32f2f), Color(0xFFb00020)]
                        : [AppColors.green700, AppColors.green900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (listening
                              ? const Color(0xFFb00020)
                              : AppColors.green800)
                          .withAlpha(80),
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green800,
            boxShadow: [
              BoxShadow(
                  color: AppColors.green900.withAlpha(80),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      );
}

class _ScoreRow extends StatelessWidget {
  final double accuracy;
  const _ScoreRow({required this.accuracy});

  @override
  Widget build(BuildContext context) {
    final pct = accuracy.round();
    final color = pct >= 90
        ? AppColors.green600
        : pct >= 70
            ? AppColors.brass
            : const Color(0xFFb00020);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Row(
            children: [
              Icon(
                pct >= 70
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.coachAccuracyPercent(pct),
                style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Score de l'empreinte vocale (niveau 1 "personnalisation voix", comparaison
/// audio-à-audio DTW contre la lecture de référence vérifiée) — voir SKILL.md.
/// Affiché séparément du score ASR classique (_ScoreRow) : source différente,
/// pas encore assez de recul pour les fusionner en un seul chiffre.
class _FingerprintBadge extends StatelessWidget {
  final double score; // [0,1]
  const _FingerprintBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score >= 0.9
        ? AppColors.green600
        : score >= 0.85
            ? AppColors.brass
            : const Color(0xFFb00020);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.coachFingerprintScore(pct),
                style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GapCard extends StatelessWidget {
  final double baseline;
  final double control;
  const _GapCard({required this.baseline, required this.control});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final gap = control - baseline;
    final memorized = gap >= 5;
    final color = memorized ? AppColors.green700 : AppColors.brass;
    final sign = gap >= 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(
            memorized
                ? Icons.trending_up_rounded
                : Icons.trending_flat_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memorized
                      ? t.coachMemorizedConfirmed
                      : t.coachKeepTraining,
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
                Text(
                  t.coachGapSummary(
                      baseline.round(), control.round(), '$sign${gap.round()}'),
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.inkLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachBubble extends StatelessWidget {
  final double accuracy;
  final List<String> difficultWords;
  final CoachMode mode;
  final double? baseline;
  const _CoachBubble({
    required this.accuracy,
    required this.difficultWords,
    required this.mode,
    required this.baseline,
  });

  String _message(AppLocalizations t) {
    final pct = accuracy.round();
    switch (mode) {
      case CoachMode.lecture:
        if (pct >= 90) {
          return t.coachMsgLectureExcellent;
        }
        if (difficultWords.isNotEmpty) {
          final preview = difficultWords.take(3).join('  ');
          return t.coachMsgLectureDifficultWords(preview);
        }
        return t.coachMsgLectureHesitant;

      case CoachMode.apprentissage:
        if (pct >= 85) {
          return t.coachMsgTrainGreat;
        }
        if (pct >= 65) {
          return t.coachMsgTrainGoodStart;
        }
        return t.coachMsgTrainRestart;

      case CoachMode.controle:
        final b = baseline;
        if (b != null && accuracy > b + 5) {
          return t.coachMsgControlMashallah;
        }
        if (pct >= 85) {
          return t.coachMsgControlVeryGood;
        }
        if (pct >= 65) {
          return t.coachMsgControlGoodPath;
        }
        return t.coachMsgControlKeepTraining;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.green900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.brass),
              child: const Icon(Icons.auto_awesome,
                  color: AppColors.green900, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _message(AppLocalizations.of(context)!),
                style: GoogleFonts.manrope(
                    fontSize: 13, color: AppColors.cream, height: 1.5),
              ),
            ),
          ],
        ),
      );
}

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green800,
          foregroundColor: AppColors.cream,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(double.infinity, 50),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.green700,
        side: const BorderSide(color: AppColors.green700),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }
}
