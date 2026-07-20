// Onglet COACH — hub de la mémorisation (REFONTE_IHM.md §11).
//
// Remplace l'ancien `coach_ai_screen.dart`, qui n'était qu'un journal
// d'erreurs à plat (liste toutes sourates mélangées). Demande utilisateur
// 2026-07-20 : « tout ce qui est en lien avec la mémorisation il faut le
// mettre dans coach [...] il ne faut pas faire juste une copie-coller ».
//
// 4 zones, dans l'ordre de priorité d'usage réel (pas esthétique) :
//   A. Reprendre        — relancer la dernière session (action n°1 au quotidien)
//   B. Mémoriser        — ayah par ayah, lance CoachScreen (3 étapes existantes)
//   C. Réciter          — récitation globale + TOUS les réglages, modifiables ici
//   D. Mes erreurs      — par sourate, avec lien vers la carte mentale
//
// Principe : ce hub ORCHESTRE des écrans existants (CoachScreen,
// KaraokeRecitationScreen, TajwidRulesScreen...), il ne les réimplémente pas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/reciter.dart';
import '../models/verse.dart';
import '../providers/app_settings_provider.dart';
import '../providers/error_review_provider.dart';
import '../providers/last_coach_verse_provider.dart';
import '../providers/mind_map_provider.dart';
import '../providers/player_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_explanation_sheet.dart';
import 'coach_screen.dart';
import 'karaoke_recitation_screen.dart';
import 'mind_map_screen.dart';
import 'reciter_select_screen.dart';
import 'surah_picker_screen.dart';
import 'tajwid_rules_screen.dart';

class CoachHubScreen extends ConsumerWidget {
  const CoachHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Text('مدرّبي',
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          _ResumeSection(),
          _MemorizeSection(),
          SizedBox(height: 22),
          _ReciteSection(),
          SizedBox(height: 22),
          _ErrorsSection(),
        ],
      ),
    );
  }
}

// ── Zone A — Reprendre ───────────────────────────────────────────────────────

/// Dernier verset travaillé, persisté par [CoachScreen]. Affiché en tête pour
/// que l'action la plus fréquente (« je continue là où j'en étais ») ne demande
/// jamais de re-naviguer.
class _ResumeSection extends ConsumerWidget {
  const _ResumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastCoachVerseProvider);
    return last.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) {
        if (v == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: _Card(
            accent: true,
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.brass, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reprendre',
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brassLight)),
                      const SizedBox(height: 2),
                      Text('${v.surahName} — verset ${v.ayahNumber}',
                          style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cream)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openCoachForVerse(
                      context, v.surahNumber, v.ayahNumber),
                  child: Text('Continuer',
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: AppColors.brassLight)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openCoachForVerse(
    BuildContext context, int surahNumber, int ayahNumber) async {
  final verses = await QuranApi.fetchVerses(surahNumber);
  final verse = verses.firstWhere(
    (v) => v.ayahNumber == ayahNumber,
    orElse: () => verses.first,
  );
  if (!context.mounted) return;
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => CoachScreen(verses: [verse])));
}

// ── Zone B — Mémoriser (ayah par ayah) ───────────────────────────────────────

class _MemorizeSection extends StatelessWidget {
  const _MemorizeSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('MÉMORISER', 'Verset par verset, avec le micro'),
        _Card(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.school_rounded,
                title: 'Mémoriser une sourate',
                subtitle: 'Lecture → Apprentissage → Contrôle',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurahPickerScreen(
                      title: 'Mémoriser',
                      subtitle: 'Choisis la sourate à travailler',
                      onPicked: (surah, verses) => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CoachScreen(verses: verses)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Zone C — Réciter + tous les réglages ─────────────────────────────────────

/// Récitation globale ET tous ses paramètres, modifiables ici (exigence
/// explicite : « tous les paramètres de récitation globale doivent être
/// accessibles pour une modification »). Ces réglages ont QUITTÉ l'écran
/// Réglages global (décision verrouillée §11.6.3 : déplacés, pas dupliqués).
class _ReciteSection extends ConsumerWidget {
  const _ReciteSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strict = ref.watch(strictCorrectionProvider);
    final autoCorr = ref.watch(autoCorrectionEnabledProvider);
    final followFree = ref.watch(followWithoutBlockingProvider);
    final drill = ref.watch(repeatDrillCountProvider);
    final sensitivity = ref.watch(correctionSensitivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
            'RÉCITER', 'Récitation continue et ses réglages'),
        _Card(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.mic_rounded,
                title: 'Réciter une sourate',
                subtitle: 'Suivi mot à mot en continu',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurahPickerScreen(
                      title: 'Réciter',
                      subtitle: 'Choisis la sourate à réciter',
                      onPicked: (surah, verses) => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                KaraokeRecitationScreen(verses: verses)),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.auto_awesome,
                title: 'Mode de vérification',
                subtitle: 'Presets tajwid / adulte / enfant, 17 règles',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TajwidRulesScreen())),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.record_voice_over_rounded,
                title: 'Récitateur',
                subtitle: '${ref.watch(playerProvider).reciter.nameFr} · ${ref.watch(playerProvider).reciter.style}',
                onTap: () async {
                  final picked = await Navigator.push<Reciter>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReciterSelectScreen(
                            currentId: ref.read(playerProvider).reciter.id)),
                  );
                  if (picked != null) {
                    ref.read(playerProvider.notifier).setReciter(picked);
                  }
                },
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.repeat_rounded,
                title: 'Répétitions de mémorisation',
                subtitle: 'Répéter le verset × $drill avant de tester',
                onTap: () => _pickDrillCount(context, ref, drill),
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.hearing_rounded,
                title: 'Correction automatique',
                subtitle: 'Mot rouge → pause, le récitateur corrige',
                value: autoCorr,
                onChanged: (v) =>
                    ref.read(autoCorrectionEnabledProvider.notifier).set(v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.rule_rounded,
                title: 'Rigueur de la correction',
                subtitle: strict
                    ? 'Strict — orange (imprécis) aussi repris'
                    : 'Tolérant — seul le rouge (mot faux) est repris',
                value: strict,
                onChanged: (v) =>
                    ref.read(strictCorrectionProvider.notifier).set(v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.fast_forward_rounded,
                title: 'Suivre sans bloquer',
                subtitle:
                    'Avance même sans reprise exacte du mot corrigé',
                value: followFree,
                onChanged: (v) =>
                    ref.read(followWithoutBlockingProvider.notifier).set(v),
              ),
              const Divider(height: 1),
              _SensitivityRow(value: sensitivity, ref: ref),
            ],
          ),
        ),
      ],
    );
  }

  void _pickDrillCount(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Répétitions avant le test',
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 16),
            for (final n in const [1, 3, 5, 7, 10])
              ListTile(
                dense: true,
                title: Text('Verset × $n',
                    style: GoogleFonts.manrope(
                        color: AppColors.cream,
                        fontWeight:
                            n == current ? FontWeight.w700 : FontWeight.normal)),
                trailing: n == current
                    ? const Icon(Icons.check_rounded, color: AppColors.brass)
                    : null,
                onTap: () {
                  ref.read(repeatDrillCountProvider.notifier).set(n);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Sensibilité du jugement. NON persistée entre sessions (chaque récitation
/// repart de 0.5) -- décision antérieure conservée, cf. commentaire de
/// `correctionSensitivityProvider`. Exposée ici pour rester modifiable.
class _SensitivityRow extends StatelessWidget {
  final double value;
  final WidgetRef ref;
  const _SensitivityRow({required this.value, required this.ref});

  @override
  Widget build(BuildContext context) {
    String label;
    if (value < 0.34) {
      label = 'Tolérant';
    } else if (value < 0.67) {
      label = 'Équilibré';
    } else {
      label = 'Strict';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  color: AppColors.green700, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Sensibilité du jugement — $label',
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
              ),
            ],
          ),
          Slider(
            value: value,
            activeColor: AppColors.green700,
            onChanged: (v) =>
                ref.read(correctionSensitivityProvider.notifier).state = v,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 6),
            child: Text(
              'Repart à « Équilibré » à chaque nouvelle récitation.',
              style: GoogleFonts.manrope(
                  fontSize: 11, color: AppColors.inkLight),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zone D — Mes erreurs, par sourate ────────────────────────────────────────

class _ErrorsSection extends ConsumerWidget {
  const _ErrorsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(surahErrorSummariesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
            'MES ERREURS', 'Regroupées par sourate, les plus fragiles en tête'),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.green700)),
          ),
          error: (e, _) => _Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Impossible de charger le journal : $e',
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.inkLight)),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return _Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 36, color: AppColors.green600),
                      const SizedBox(height: 10),
                      Text('Aucune erreur journalisée',
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(
                        'Récite depuis « Réciter » ou « Mémoriser » : les mots '
                        'repris apparaîtront ici, regroupés par sourate.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.inkLight),
                      ),
                    ],
                  ),
                ),
              );
            }
            return _Card(
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SurahErrorTile(summary: list[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SurahErrorTile extends ConsumerWidget {
  final SurahErrorSummary summary;
  const _SurahErrorTile({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary.surah;
    // Le bouton « carte mentale » n'apparaît que si le contenu existe pour
    // cette sourate (12 sourates rédigées à ce jour) -- jamais un bouton mort.
    final mindMap = ref.watch(mindMapProvider(s.number));
    final hasMindMap = mindMap.asData?.value != null;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.green50,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text('${summary.totalErrors}',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
        ),
        title: Text('${s.number}. ${s.nameSimple}',
            style: GoogleFonts.manrope(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${summary.versesTouched} verset'
                '${summary.versesTouched > 1 ? 's' : ''} sur ${s.versesCount}',
                style: GoogleFonts.manrope(
                    fontSize: 11.5, color: AppColors.inkLight),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: summary.touchedRatio.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.cream300,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.brass),
                ),
              ),
            ],
          ),
        ),
        trailing: Text(s.nameArabic,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 18, color: AppColors.green800)),
        children: [
          if (hasMindMap)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('Situer dans la carte mentale'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.green700),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MindMapScreen(surah: s))),
                ),
              ),
            ),
          for (final a in summary.ayahs)
            _AyahErrorRow(surah: s, count: a),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _AyahErrorRow extends StatelessWidget {
  final Surah surah;
  final AyahErrorCount count;
  const _AyahErrorRow({required this.surah, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text('Verset ${count.ayahNumber}  ·  ${count.count} erreur'
                  '${count.count > 1 ? 's' : ''}',
                  style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ),
            IconButton(
              tooltip: 'Explication',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.psychology_alt_outlined,
                  size: 19, color: AppColors.green700),
              onPressed: () => showCoachExplanation(
                context,
                surahNumber: surah.number,
                ayahNumber: count.ayahNumber,
                title: '${surah.nameSimple} — verset ${count.ayahNumber}',
              ),
            ),
            IconButton(
              tooltip: 'Revoir ce verset',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.school_outlined,
                  size: 19, color: AppColors.green700),
              onPressed: () => _openCoachForVerse(
                  context, surah.number, count.ayahNumber),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Briques communes ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.manrope(
                    fontSize: 11.5, color: AppColors.inkLight)),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool accent;
  final bool padded;
  const _Card({required this.child, this.accent = false, this.padded = true});

  @override
  Widget build(BuildContext context) => Container(
        padding: padded ? const EdgeInsets.all(4) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: accent ? AppColors.green800 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: accent ? AppColors.green700 : AppColors.cream300),
        ),
        child: accent
            ? Padding(padding: const EdgeInsets.all(12), child: child)
            : child,
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.green50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.green700, size: 20),
        ),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(
                fontSize: 11.5, color: AppColors.inkLight)),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.inkLight),
        onTap: onTap,
      );
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.green50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.green700, size: 20),
        ),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(
                fontSize: 11.5, color: AppColors.inkLight)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.green700,
        ),
        onTap: () => onChanged(!value),
      );
}
