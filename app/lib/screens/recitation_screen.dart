import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/recitation_state.dart';
import '../providers/recitation_provider.dart';
import '../theme/app_theme.dart';
// Couleurs : AppColors (défini dans app_theme.dart)

/// Écran de récitation continue : l'utilisateur récite plusieurs versets (ou
/// une sourate entière) sans interaction manuelle entre chaque verset — la
/// segmentation est automatique (silence détecté), et chaque mot se colorie
/// en temps réel (vert = correct, rouge = erreur, orange = sauté) au fil de
/// la transcription des segments, avec un léger décalage (file d'attente).
class RecitationScreen extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const RecitationScreen({super.key, required this.verses});

  @override
  ConsumerState<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends ConsumerState<RecitationScreen> {
  @override
  void initState() {
    super.initState();
    final text = widget.verses.map((v) => v.textUthmani).join(' ');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recitationProvider.notifier).setup(text);
    });
  }

  Color _colorFor(WordStatus s) {
    switch (s) {
      case WordStatus.correct:
        return AppColors.green600;
      case WordStatus.error:
        return const Color(0xFFb00020);
      case WordStatus.unclear:
        return AppColors.tajwidMadd; // orange : bon mot, articulation imprecise
      case WordStatus.skipped:
        return AppColors.inkLight; // gris (l'orange est reserve a unclear)
      case WordStatus.current:
        return AppColors.ink;
      case WordStatus.pending:
        return AppColors.inkLight.withOpacity(0.45);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final st = ref.watch(recitationProvider);
    final notifier = ref.read(recitationProvider.notifier);
    final ref0 = widget.verses.first;
    final title = widget.verses.length == 1
        ? t.recitationVerseTitle(ref0.key)
        : t.recitationRangeTitle(
            ref0.key, widget.verses.last.key, widget.verses.length);

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            _header(title),
            Expanded(child: _verseArea(st)),
            _pendingSegmentsBadge(st),
            _rawTranscriptBox(st),
            _scoreBar(st),
            _controls(st, notifier),
          ],
        ),
      ),
    );
  }

  // ── En-tête ──────────────────────────────────────────────────────────────
  Widget _header(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.green900, AppColors.green700],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.recitationModeLabel,
                    style: GoogleFonts.inter(
                        color: AppColors.brassLight,
                        fontSize: 12,
                        letterSpacing: 1.2)),
                Text(title,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.auto_awesome, color: AppColors.brassLight, size: 20),
        ],
      ),
    );
  }

  // ── Zone du verset (coloration en direct) ────────────────────────────────
  Widget _verseArea(RecitationSessionState st) {
    if (st.words.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 14,
          children: [
            for (final w in st.words)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: w.status == WordStatus.current
                      ? AppColors.brass.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: w.status == WordStatus.current
                      ? Border.all(color: AppColors.brass.withOpacity(0.5))
                      : null,
                ),
                child: Text(
                  w.display,
                  style: GoogleFonts.amiri(
                    fontSize: 30,
                    height: 1.9,
                    color: _colorFor(w.status),
                    fontWeight: w.status == WordStatus.correct ||
                            w.status == WordStatus.current
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Badge segments en attente d'analyse (mode continu) ───────────────────
  Widget _pendingSegmentsBadge(RecitationSessionState st) {
    if (st.pendingSegments == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brass.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brass),
          ),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.recitationSegmentAnalyzing(st.pendingSegments),
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.brass, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Transcript brut du modèle (debug/visualisation) ──────────────────────
  Widget _rawTranscriptBox(RecitationSessionState st) {
    if (st.rawTranscript.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream300.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inkLight.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.recitationTranscriptLabel,
              style: GoogleFonts.inter(
                  fontSize: 10,
                  letterSpacing: 1.0,
                  color: AppColors.inkLight)),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              st.rawTranscript,
              style: GoogleFonts.amiri(fontSize: 18, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  // ── Barre de score live ──────────────────────────────────────────────────
  Widget _scoreBar(RecitationSessionState st) {
    final t = AppLocalizations.of(context)!;
    final progress = st.total == 0 ? 0.0 : st.pointer / st.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.cream300,
              valueColor: const AlwaysStoppedAnimation(AppColors.green600),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(t.recitationStatCorrect, '${st.correctCount}', AppColors.green600),
              _stat(t.recitationStatErrors, '${st.errorCount}', const Color(0xFFb00020)),
              _stat(t.recitationStatAccuracy, '${st.accuracy.toStringAsFixed(0)}%',
                  AppColors.brass),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.inkLight)),
        ],
      );

  // ── Contrôles (micro animé) ──────────────────────────────────────────────
  Widget _controls(RecitationSessionState st, RecitationNotifier n) {
    final listening = st.status == RecitationStatus.listening;
    final finalizing = st.status == RecitationStatus.processing;
    final finished = st.status == RecitationStatus.finished;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        children: [
          if (finished) _resultBanner(st),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              if (listening) {
                n.stopContinuous();
              } else if (!finalizing) {
                n.startContinuous();
              }
            },
            child: _MicButton(level: st.soundLevel, listening: listening),
          ),
          const SizedBox(height: 12),
          Text(
            listening
                ? AppLocalizations.of(context)!.recitationListeningContinuous
                : finalizing
                    ? AppLocalizations.of(context)!.recitationFinalizing
                    : finished
                        ? AppLocalizations.of(context)!.recitationFinishedRestart
                        : AppLocalizations.of(context)!.recitationTapToStart,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.inkLight),
          ),
        ],
      ),
    );
  }

  Widget _resultBanner(RecitationSessionState st) {
    final good = st.accuracy >= 80;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: good ? AppColors.green50 : const Color(0xFFfdecec),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: good ? AppColors.green600 : const Color(0xFFb00020),
            width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(good ? Icons.check_circle : Icons.refresh,
              color: good ? AppColors.green600 : const Color(0xFFb00020)),
          const SizedBox(width: 10),
          Text(
            good
                ? AppLocalizations.of(context)!
                    .recitationMashallahAccuracy(st.accuracy.toStringAsFixed(0))
                : AppLocalizations.of(context)!
                    .recitationContinueAccuracy(st.accuracy.toStringAsFixed(0)),
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// Bouton micro avec onde sonore animée (pilotée par le niveau micro).
class _MicButton extends StatelessWidget {
  final double level;
  final bool listening;
  const _MicButton({required this.level, required this.listening});

  @override
  Widget build(BuildContext context) {
    final ring = listening ? 1.0 + level * 0.5 : 1.0;
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Onde externe
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 86 * ring,
            height: 86 * ring,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (listening ? const Color(0xFFb00020) : AppColors.green600)
                  .withOpacity(0.15),
            ),
          ),
          // Bouton central
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: listening
                    ? const [Color(0xFFd32f2f), Color(0xFFb00020)]
                    : const [AppColors.green600, AppColors.green800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: (listening
                          ? const Color(0xFFb00020)
                          : AppColors.green700)
                      .withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(listening ? Icons.stop : Icons.mic,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }
}
