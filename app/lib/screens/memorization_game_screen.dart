// Mode jeu — mémorisation par QCM séquentiel mot par mot.
//
// Mécanique (cf. `.claude/skills/jeux-memorisation/SKILL.md`, décision
// utilisateur 2026-07-22, corrigée une première fois après un essai erroné) :
// le premier mot d'un verset s'affiche seul ; chaque mot suivant se choisit
// parmi plusieurs options mélangées (mot correct + leurres pris plus loin
// dans la sourate). Taper le bon mot fait avancer ; un mauvais tap ne fait
// que trembler brièvement, sans pénalité.
//
// Design (décision utilisateur 2026-07-22) : cet écran cible un public
// enfant et tranche volontairement avec le reste de l'app, plus sobre --
// palette saturée type appli de jeu (`AppColors.game*`), gros boutons ronds,
// animations de rebond/tremblement, célébration à étoiles en fin de partie.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../providers/memorization_game_provider.dart';
import '../providers/memorization_game_records_provider.dart';
import '../theme/app_theme.dart';

class MemorizationGameScreen extends ConsumerWidget {
  final Surah surah;
  final List<Verse> verses;

  const MemorizationGameScreen({
    super.key,
    required this.surah,
    required this.verses,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final provider = memorizationGameProvider(verses);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(isArabic ? surah.nameArabic : surah.nameSimple,
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: t.memorizationGameRestartVerseTooltip,
            icon: const Icon(Icons.replay_rounded),
            onPressed: notifier.restartVerse,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.gameBgTop, AppColors.gameBgBottom],
          ),
        ),
        child: SafeArea(
          child: state.isGameComplete
              ? _CompletionView(
                  surah: surah,
                  isArabic: isArabic,
                  finalWords: state.totalWordsCompleted,
                  record: ref.watch(memorizationGameRecordProvider),
                )
              : Column(
                  children: [
                    const SizedBox(height: 60), // sous l'AppBar transparente
                    _ScoreBar(
                      words: state.totalWordsCompleted,
                      record: ref.watch(memorizationGameRecordProvider),
                      justBeatRecord: state.justBeatRecord,
                    ),
                    Expanded(
                      child: Center(
                        child: state.isLoadingNextPage
                            ? const _NextPageLoading()
                            : state.choices.isEmpty
                                ? _FirstWordBubble(
                                    word: state.currentWord,
                                    onTap: () =>
                                        notifier.submitWord(state.currentWord),
                                  )
                                : _ChoiceGrid(
                                    choices: state.choices,
                                    wrongFlash: state.wrongFlash,
                                    onChoiceTap: notifier.submitWord,
                                  ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Score courant + record personnel (remplace l'ancienne barre "verset X sur
/// Y", cf. décision utilisateur 2026-08-07 : la partie est désormais
/// illimitée -- charge la page suivante toute seule au lieu de s'arrêter en
/// fin de page -- donc "X sur Y" n'a plus de sens (Y grandit sans cesse).
///
/// Reste un indicateur de TAILLE FIXE (deux nombres), ce qui préserve la
/// leçon du 2026-07-22 sur les grandes sourates (cf. historique de cette
/// classe) : jamais un élément par verset, même sous une autre forme.
class _ScoreBar extends StatefulWidget {
  final int words;
  final int record;
  final bool justBeatRecord;
  const _ScoreBar(
      {required this.words, required this.record, required this.justBeatRecord});

  @override
  State<_ScoreBar> createState() => _ScoreBarState();
}

class _ScoreBarState extends State<_ScoreBar> {
  bool _showNewRecord = false;

  @override
  void didUpdateWidget(covariant _ScoreBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.justBeatRecord && !oldWidget.justBeatRecord) {
      setState(() => _showNewRecord = true);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showNewRecord = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.bolt_rounded,
              color: AppColors.gameChipColors[1],
              label: t.memorizationGameWordsCount(widget.words),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedScale(
              scale: _showNewRecord ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: _StatChip(
                icon: Icons.emoji_events_rounded,
                color: AppColors.gameStar,
                label: _showNewRecord
                    ? t.memorizationGameNewRecord
                    : t.memorizationGameRecordLabel(widget.record),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatChip({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.baloo2(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );
}

/// Court état d'attente pendant que la page suivante se charge (quasi
/// instantané -- les données du Coran sont 100% locales, cf.
/// `QuranApi` -- mais un état visuel évite un dernier mot qui semble figé).
class _NextPageLoading extends StatelessWidget {
  const _NextPageLoading();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.gameStar),
        const SizedBox(height: 14),
        Text(t.memorizationGameLoadingNextPage,
            style: GoogleFonts.baloo2(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkLight)),
      ],
    );
  }
}

/// Le tout premier mot d'un verset : une seule grosse bulle à taper pour
/// démarrer, pas de QCM (rien à deviner, juste "c'est parti").
class _FirstWordBubble extends StatefulWidget {
  final String word;
  final VoidCallback onTap;
  const _FirstWordBubble({required this.word, required this.onTap});

  @override
  State<_FirstWordBubble> createState() => _FirstWordBubbleState();
}

class _FirstWordBubbleState extends State<_FirstWordBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.04).animate(
          CurvedAnimation(parent: _bounce, curve: Curves.easeInOut)),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gameStar, width: 4),
            boxShadow: [
              BoxShadow(
                color: AppColors.gameStar.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            widget.word,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(fontSize: 34, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Grille de choix mélangés (mot correct + leurres), rendus en gros boutons
/// ronds colorés type appli de jeu enfant. Tremble brièvement (sans pénalité)
/// sur un mauvais tap -- `wrongFlash` piloté par le provider.
class _ChoiceGrid extends StatefulWidget {
  final List<String> choices;
  final bool wrongFlash;
  final void Function(String) onChoiceTap;

  const _ChoiceGrid({
    required this.choices,
    required this.wrongFlash,
    required this.onChoiceTap,
  });

  @override
  State<_ChoiceGrid> createState() => _ChoiceGridState();
}

class _ChoiceGridState extends State<_ChoiceGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void didUpdateWidget(covariant _ChoiceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wrongFlash && !oldWidget.wrongFlash) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final offset = sin(_shake.value * pi * 6) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < widget.choices.length; i++)
              _ChoiceChip(
                word: widget.choices[i],
                color: AppColors.gameChipColors[i % AppColors.gameChipColors.length],
                flashWrong: widget.wrongFlash,
                onTap: () => widget.onChoiceTap(widget.choices[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatefulWidget {
  final String word;
  final Color color;
  final bool flashWrong;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.word,
    required this.color,
    required this.flashWrong,
    required this.onTap,
  });

  @override
  State<_ChoiceChip> createState() => _ChoiceChipState();
}

class _ChoiceChipState extends State<_ChoiceChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.word,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 26, color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  final Surah surah;
  final bool isArabic;
  final int finalWords;
  final int record;
  const _CompletionView({
    required this.surah,
    required this.isArabic,
    required this.finalWords,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.star_rounded,
                        color: AppColors.gameStar, size: 52),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.memorizationGameCompleteTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              t.memorizationGameCompleteBody(
                  isArabic ? surah.nameArabic : surah.nameSimple),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.inkLight),
            ),
            const SizedBox(height: 10),
            Text(
              t.memorizationGameFinalScore(finalWords, max(finalWords, record)),
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gameStar),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gameCorrect,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(t.memorizationGameBackToHub,
                  style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
