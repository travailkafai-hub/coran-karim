import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../data/rite_hajj.dart';
import '../data/rite_umra.dart';
import '../models/rite.dart';
import '../providers/dua_prefs_provider.dart';
import '../theme/app_theme.dart';
import 'dua_collection_screen.dart';

/// Guide pas à pas d'un rite (ʿUmra, Hajj).
///
/// L'écran est construit autour d'UNE question : « où en suis-je, et que
/// dois-je faire maintenant ? » D'où le parti pris d'afficher une seule
/// étape à la fois en grand, surmontée d'une frise d'emojis qui situe dans
/// l'ensemble — plutôt qu'une longue page à faire défiler où l'on perd sa
/// place dès qu'on range son téléphone.
///
/// La progression et les compteurs sont persistés (cf.
/// `dua_prefs_provider.dart`) : sur place, l'app sera fermée entre deux
/// étapes, et le Hajj s'étale sur six jours.
class RiteScreen extends ConsumerStatefulWidget {
  final String riteId;
  const RiteScreen({super.key, required this.riteId});

  @override
  ConsumerState<RiteScreen> createState() => _RiteScreenState();
}

class _RiteScreenState extends ConsumerState<RiteScreen> {
  final _timelineCtrl = ScrollController();
  final _bodyCtrl = ScrollController();

  Rite get _rite => widget.riteId == 'hajj' ? kRiteHajj : kRiteUmra;

  @override
  void dispose() {
    _timelineCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// Recentre la frise sur l'étape courante et remonte le corps de page.
  /// Sans ça, passer à l'étape 7 laisse la frise bloquée sur les premières
  /// pastilles et le lecteur au milieu du texte de l'étape précédente.
  void _focusStep(int index) {
    if (_timelineCtrl.hasClients) {
      const chipExtent = 60.0;
      final target = (index * chipExtent - 100).clamp(
        0.0,
        _timelineCtrl.position.maxScrollExtent,
      );
      _timelineCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (_bodyCtrl.hasClients) {
      _bodyCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rite = _rite;

    // La progression est relue depuis SharedPreferences de façon ASYNCHRONE :
    // au premier build elle vaut encore l'état initial (étape 0), et la
    // vraie valeur arrive après. Un simple recentrage en initState se ferait
    // donc toujours sur l'étape 0. On écoute le provider à la place : quand
    // l'étape reprise arrive, la frise se recentre dessus. Sans ça, rouvrir
    // un Hajj repris à l'étape 9 affiche une frise calée sur l'étape 1 —
    // la pastille active est hors écran et l'on croit avoir tout perdu.
    ref.listen(riteProgressProvider(rite.id), (previous, next) {
      if (previous?.currentStep != next.currentStep) {
        _focusStep(next.currentStep);
      }
    });

    final progress = ref.watch(riteProgressProvider(rite.id));
    final notifier = ref.read(riteProgressProvider(rite.id).notifier);
    final index = progress.currentStep.clamp(0, rite.steps.length - 1);
    final step = rite.steps[index];
    final accent = AppColors.green900;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: AppColors.cream,
        title: Row(
          children: [
            Text(rite.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              rite.nameFr,
              style: GoogleFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              rite.nameAr,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.scheherazadeNew(
                fontSize: 17,
                color: AppColors.brassLight,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.riteBeforeStartTooltip,
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            onPressed: () => _showEssentials(context, rite),
          ),
          IconButton(
            tooltip: t.riteRestartTooltip,
            icon: const Icon(Icons.restart_alt_rounded, size: 20),
            onPressed: () => _confirmReset(context, notifier),
          ),
        ],
      ),
      body: Column(
        children: [
          _Timeline(
            rite: rite,
            controller: _timelineCtrl,
            currentIndex: index,
            doneSteps: progress.doneSteps,
            onSelect: (i) {
              notifier.goToStep(i);
              _focusStep(i);
            },
          ),
          _OverallProgress(
            done: progress.doneSteps.length,
            total: rite.steps.length,
          ),
          Expanded(
            child: ListView(
              controller: _bodyCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (step.dayLabel != null) _DayBadge(label: step.dayLabel!),
                _StepHeader(step: step, index: index, total: rite.steps.length),
                const SizedBox(height: 14),
                _StepSummary(text: step.summary),
                const SizedBox(height: 16),
                _ActionsList(actions: step.actions),
                if (step.counter != null) ...[
                  const SizedBox(height: 18),
                  _RiteCounterCard(
                    counter: step.counter!,
                    value: progress.counters[step.id] ?? 0,
                    onTap: () =>
                        notifier.increment(step.id, step.counter!.totalTarget),
                    onReset: () => notifier.resetCounter(step.id),
                  ),
                ],
                if (step.warning != null) ...[
                  const SizedBox(height: 18),
                  _WarningCard(text: step.warning!),
                ],
                if (step.duaIds.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    t.riteWhatWeSayLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DuaIdList(duaIds: step.duaIds, accent: accent),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _StepNav(
        index: index,
        total: rite.steps.length,
        isDone: progress.doneSteps.contains(step.id),
        onPrevious: index == 0
            ? null
            : () {
                notifier.goToStep(index - 1);
                _focusStep(index - 1);
              },
        onToggleDone: () => notifier.toggleDone(step.id),
        onNext: index >= rite.steps.length - 1
            ? null
            : () {
                // Valider l'étape en passant à la suivante : sur place on
                // avance, on ne pense pas à cocher.
                if (!progress.doneSteps.contains(step.id)) {
                  notifier.toggleDone(step.id);
                }
                notifier.goToStep(index + 1);
                _focusStep(index + 1);
              },
      ),
    );
  }

  void _showEssentials(BuildContext context, Rite rite) {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cream300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              t.riteBeforeStartTitle,
              style: GoogleFonts.fraunces(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              rite.intro,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.inkLight,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 20),
            for (final e in rite.essentials)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.check_circle_outline_rounded,
                          size: 15, color: AppColors.green700),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          color: AppColors.ink,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brass.withAlpha(24),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                t.riteDisclaimer,
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
                  color: AppColors.inkLight,
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, RiteProgressNotifier notifier) {
    final t = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: Text(t.riteResetConfirmTitle,
            style: GoogleFonts.fraunces(fontSize: 17, color: AppColors.ink)),
        content: Text(
          t.riteResetConfirmBody,
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.commonCancel),
          ),
          TextButton(
            onPressed: () {
              notifier.resetAll();
              Navigator.of(ctx).pop();
            },
            child: Text(t.riteResetConfirmAction),
          ),
        ],
      ),
    );
  }
}

/// Frise des étapes en emojis — la vue d'ensemble tient en une ligne.
class _Timeline extends StatelessWidget {
  final Rite rite;
  final ScrollController controller;
  final int currentIndex;
  final Set<String> doneSteps;
  final ValueChanged<int> onSelect;

  const _Timeline({
    required this.rite,
    required this.controller,
    required this.currentIndex,
    required this.doneSteps,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.green900,
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 62,
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: rite.steps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final step = rite.steps[i];
              final isCurrent = i == currentIndex;
              final isDone = doneSteps.contains(step.id);
              return GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.brass
                        : isDone
                            ? AppColors.green600
                            : AppColors.green800,
                    borderRadius: BorderRadius.circular(16),
                    border: isCurrent
                        ? Border.all(color: AppColors.brassLight, width: 2)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(step.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 2),
                      // Le numéro laisse la place à une coche dès que
                      // l'étape est validée : d'un coup d'œil sur la frise
                      // on voit ce qui reste à faire.
                      isDone && !isCurrent
                          ? const Icon(Icons.check_rounded,
                              size: 11, color: AppColors.cream)
                          : Text(
                              '${i + 1}',
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isCurrent
                                    ? AppColors.green900
                                    : AppColors.cream,
                              ),
                            ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _OverallProgress extends StatelessWidget {
  final int done;
  final int total;
  const _OverallProgress({required this.done, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.green900,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 5,
                  backgroundColor: AppColors.green800,
                  color: AppColors.brassLight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$done/$total',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brassLight,
              ),
            ),
          ],
        ),
      );
}

class _DayBadge extends StatelessWidget {
  final String label;
  const _DayBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.green900,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_rounded, size: 13, color: AppColors.brassLight),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brassLight,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StepHeader extends StatelessWidget {
  final RiteStep step;
  final int index;
  final int total;

  const _StepHeader({
    required this.step,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.green50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cream300),
            ),
            child: Text(step.emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.riteStepOfTotal(index + 1, total),
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brass,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.titleFr,
                  style: GoogleFonts.fraunces(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                Text(
                  step.titleAr,
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.scheherazadeNew(
                    fontSize: 18,
                    color: AppColors.green700,
                  ),
                ),
                const SizedBox(height: 8),
                _MetaLine(icon: Icons.place_outlined, text: step.place),
                const SizedBox(height: 3),
                _MetaLine(icon: Icons.schedule_rounded, text: step.when),
              ],
            ),
          ),
        ],
      );
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 12, color: AppColors.inkLight),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.inkLight,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
}

class _StepSummary extends StatelessWidget {
  final String text;
  const _StepSummary({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.green50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.ink,
            height: 1.7,
          ),
        ),
      );
}

class _ActionsList extends StatelessWidget {
  final List<String> actions;
  const _ActionsList({required this.actions});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.riteWhatWeDoLabel,
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: AppColors.inkLight,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < actions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brass.withAlpha(34),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brass,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      actions[i],
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: AppColors.ink,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

/// Compteur du rite — gère les séries (jamarāt : 3 stèles × 7 cailloux).
///
/// Le total est stocké en un seul entier (0..21) et la série courante s'en
/// déduit : impossible d'être « à la stèle 2 avec un compteur de stèle 1 »
/// après un redémarrage.
class _RiteCounterCard extends StatelessWidget {
  final RiteCounter counter;
  final int value;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _RiteCounterCard({
    required this.counter,
    required this.value,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final total = counter.totalTarget;
    final complete = value >= total;
    final lapIndex =
        counter.hasLaps ? (value ~/ counter.target).clamp(0, counter.laps.length - 1) : 0;
    final inLap = complete ? counter.target : value % counter.target;
    final lapLabel = counter.laps[lapIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: complete ? AppColors.green700.withAlpha(24) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: complete ? AppColors.green700 : AppColors.brass,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                size: 16,
                color: complete ? AppColors.green700 : AppColors.brass,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  counter.label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (value > 0)
                InkWell(
                  onTap: onReset,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh_rounded,
                        size: 16, color: AppColors.inkLight),
                  ),
                ),
            ],
          ),
          if (counter.hasLaps && !complete) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < counter.laps.length; i++) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: i < lapIndex
                            ? AppColors.green600
                            : i == lapIndex
                                ? AppColors.brass
                                : AppColors.cream300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        counter.laps[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: i <= lapIndex
                              ? Colors.white
                              : AppColors.inkLight,
                        ),
                      ),
                    ),
                  ),
                  if (i < counter.laps.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          InkWell(
            onTap: complete ? null : onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: complete
                    ? AppColors.green700.withAlpha(30)
                    : AppColors.brass.withAlpha(26),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    complete ? counter.doneMessage : '$inLap / ${counter.target}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: complete ? 14 : 30,
                      fontWeight: FontWeight.w700,
                      color: complete ? AppColors.green700 : AppColors.ink,
                    ),
                  ),
                  if (!complete) ...[
                    const SizedBox(height: 2),
                    Text(
                      counter.hasLaps
                          ? '$lapLabel · appuyez à chaque ${counter.unit}'
                          : 'Appuyez à chaque ${counter.unit}',
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        color: AppColors.inkLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : value / total,
              minHeight: 5,
              backgroundColor: AppColors.cream300,
              color: complete ? AppColors.green700 : AppColors.brass,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String text;
  const _WarningCard({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFfdf3e7),
          borderRadius: BorderRadius.circular(14),
          border: const Border(
            left: BorderSide(color: AppColors.tajwidMadd, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: AppColors.tajwidMadd),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.ink,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StepNav extends StatelessWidget {
  final int index;
  final int total;
  final bool isDone;
  final VoidCallback? onPrevious;
  final VoidCallback onToggleDone;
  final VoidCallback? onNext;

  const _StepNav({
    required this.index,
    required this.total,
    required this.isDone,
    required this.onPrevious,
    required this.onToggleDone,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.cream300)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.green900,
                  tooltip: AppLocalizations.of(context)!.ritePreviousStepTooltip,
                ),
                Expanded(
                  child: InkWell(
                    onTap: onToggleDone,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.green700.withAlpha(28)
                            : AppColors.cream200,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              isDone ? AppColors.green700 : AppColors.cream300,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isDone
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: isDone
                                ? AppColors.green700
                                : AppColors.inkLight,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDone
                                ? AppLocalizations.of(context)!.riteStepDone
                                : AppLocalizations.of(context)!.riteMarkAsDone,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDone
                                  ? AppColors.green700
                                  : AppColors.inkLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.green900,
                    foregroundColor: AppColors.cream,
                    disabledBackgroundColor: AppColors.cream300,
                  ),
                  tooltip: AppLocalizations.of(context)!.riteNextStepTooltip,
                ),
              ],
            ),
          ),
        ),
      );
}
