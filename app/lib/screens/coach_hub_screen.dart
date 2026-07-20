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

import '../models/recitation_state.dart'
    show RecitationErrorKind, recitationErrorKindLabel;
import '../models/verse.dart';
import '../providers/error_review_provider.dart';
import '../providers/last_coach_verse_provider.dart';
import '../providers/mind_map_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_explanation_sheet.dart';
import 'coach_screen.dart';
import 'karaoke_recitation_screen.dart';
import 'mind_map_screen.dart';
import 'surah_picker_screen.dart';

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

// ── Zone C — Réciter : LE MOTEUR DE L'APP, mis en valeur ─────────────────────

/// Récitation continue. Volontairement présentée comme une GRANDE CARTE
/// D'ACTION et non comme une ligne de liste parmi d'autres (retour utilisateur
/// 2026-07-20 : « réciter une sourate c'est le moteur de l'app, il n'est pas
/// mis en valeur ») : c'est la fonction centrale du produit, elle doit se voir
/// et s'atteindre en un geste.
///
/// Les PARAMÈTRES DE VÉRIFICATION ne sont plus ici : ils vivent sur l'écran de
/// récitation lui-même, derrière une icône (karaoke_recitation_screen.dart,
/// `_openVerificationSheet`) -- ils ne servent que là, et souvent EN COURS de
/// récitation. Le RÉCITATEUR est retourné dans les Réglages généraux (choix
/// transverse : écoute, souffleur, corrections audio).
class _ReciteSection extends StatelessWidget {
  const _ReciteSection();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SurahPickerScreen(
            title: 'Réciter',
            subtitle: 'Choisis la sourate à réciter',
            onPicked: (surah, verses) => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => KaraokeRecitationScreen(verses: verses)),
            ),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.green800, AppColors.green900],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brass, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: AppColors.green900.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brass,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brass.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.green900, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Réciter une sourate',
                      style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 5),
                  Text(
                    'Suivi mot à mot, correction en direct',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, color: AppColors.brassLight),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.brassLight, size: 26),
          ],
        ),
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
            'MES ERREURS', 'Par type, puis par sourate'),
        const _ErrorKindBreakdown(),
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


/// Répartition des erreurs par TYPE (demande utilisateur 2026-07-20 :
/// « catégoriser par type : tajwid ou prononciation »).
///
/// Placée AVANT la liste par sourate : elle répond à une question différente
/// et plus générale — « sur quoi je bute, des lettres, des voyelles, ou du
/// tajwid ? » — alors que la liste par sourate répond à « où travailler ? ».
class _ErrorKindBreakdown extends ConsumerWidget {
  const _ErrorKindBreakdown();

  static const _order = [
    RecitationErrorKind.lettre,
    RecitationErrorKind.harakat,
    RecitationErrorKind.tajwid,
    RecitationErrorKind.saute,
    RecitationErrorKind.inconnu,
  ];

  Color _color(RecitationErrorKind k) => switch (k) {
        RecitationErrorKind.lettre => AppColors.tajwidIkhfaa,
        RecitationErrorKind.harakat => AppColors.mindmapEthique,
        RecitationErrorKind.tajwid => AppColors.green700,
        RecitationErrorKind.saute => AppColors.inkLight,
        RecitationErrorKind.inconnu => AppColors.cream300,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(errorKindBreakdownProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        final total = counts.values.fold(0, (a, b) => a + b);
        if (total == 0) return const SizedBox.shrink();
        final present = [
          for (final k in _order)
            if ((counts[k] ?? 0) > 0) k,
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barre empilée : proportions d'un coup d'œil.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (final k in present)
                            Expanded(
                              flex: counts[k]!,
                              child: ColoredBox(color: _color(k)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (final k in present)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: _color(k), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${recitationErrorKindLabel(k)} · ${counts[k]}',
                              style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Ne pas laisser croire que « Tajwid » est une preuve : c'est
                  // une déduction par élimination (cf. classifyError).
                  Text(
                    'Lettre et Harakat = prononciation. « Tajwid » signifie '
                    'que ni les lettres ni les voyelles n\'expliquent l\'écart '
                    'sur un mot porteur d\'une règle — c\'est une déduction, '
                    'pas une preuve que la règle a été ratée.',
                    style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        height: 1.35,
                        color: AppColors.inkLight),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
