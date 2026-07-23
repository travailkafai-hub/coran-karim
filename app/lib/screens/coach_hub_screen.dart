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

import '../l10n/app_localizations.dart';
import '../models/judgement_options.dart' show TajwidRule;
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
import '../widgets/tajwid_help_sheet.dart' show kTajwidRuleInfo;
import 'coach_screen.dart';
import 'karaoke_recitation_screen.dart';
import 'memorization_ayah_picker_screen.dart';
import 'memorization_game_screen.dart';
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
        title: Text(AppLocalizations.of(context)!.coachHubTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          _ResumeSection(),
          _MemorizeSection(),
          SizedBox(height: 22),
          _GameSection(),
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
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
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
                      Text(t.coachHubResumeLabel,
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brassLight)),
                      const SizedBox(height: 2),
                      // v.surahName vient de SharedPreferences, écrit lors
                      // d'une session passée dans la langue d'alors : ne
                      // jamais s'y fier pour l'affichage (bug corrigé
                      // 2026-07-22, "Sourate 94" affiché en mode arabe).
                      // On recalcule toujours depuis le numéro + la locale
                      // actuelle, via la vraie liste des sourates (nom
                      // complet, pas juste le repli générique "Sourate N").
                      FutureBuilder<List<Surah>>(
                        future: QuranApi.fetchSurahs(),
                        builder: (context, snap) {
                          final surahs = snap.data;
                          final name = surahs == null
                              ? t.coachSurahLabel(v.surahNumber)
                              : (isArabic
                                  ? surahs
                                      .firstWhere((s) => s.number == v.surahNumber,
                                          orElse: () => surahs.first)
                                      .nameArabic
                                  : surahs
                                      .firstWhere((s) => s.number == v.surahNumber,
                                          orElse: () => surahs.first)
                                      .nameSimple);
                          return Text(t.coachHubResumeVerse(name, v.ayahNumber),
                              style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.cream));
                        },
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openCoachForVerse(
                      context, v.surahNumber, v.ayahNumber),
                  child: Text(t.coachHubContinue,
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
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(t.coachHubMemorizeSectionTitle, t.coachHubMemorizeSectionSubtitle),
        _Card(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.school_rounded,
                title: t.coachHubMemorizeSurahTitle,
                subtitle: t.coachHubMemorizeSurahSubtitle,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurahPickerScreen(
                      title: t.coachHubPickerMemorizeTitle,
                      subtitle: t.coachHubPickerMemorizeSubtitle,
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

// ── Zone B bis — Jeu de mémorisation (rappel progressif par palier) ─────────

/// Mode ludique : révélation progressive mot par mot (paliers), en
/// complément de `CoachScreen` (3 étapes classiques). Décision utilisateur
/// 2026-07-22, mécanique détaillée dans
/// `.claude/skills/jeux-memorisation/SKILL.md`.
class _GameSection extends StatelessWidget {
  const _GameSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(t.coachHubGameSectionTitle, t.coachHubGameSectionSubtitle),
        _Card(
          child: _ActionRow(
            icon: Icons.videogame_asset_rounded,
            title: t.coachHubGameActionTitle,
            subtitle: t.coachHubGameActionSubtitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SurahPickerScreen(
                  title: t.coachHubPickerGameTitle,
                  subtitle: t.coachHubPickerGameSubtitle,
                  onPicked: (surah, verses) {
                    // Sourate tenant sur une seule page du Mushaf : jeu direct
                    // sur la sourate entière. Sourate étalée sur plusieurs
                    // pages : demander l'aya de départ et se limiter à cette
                    // page (décision utilisateur 2026-07-22 -- ne jamais
                    // lancer une session de plusieurs centaines de versets
                    // d'un coup, cf. bug d'overflow constaté sur Al-Baqarah).
                    final pages = verses.map((v) => v.pageNumber).whereType<int>().toSet();
                    if (pages.length <= 1) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MemorizationGameScreen(
                                surah: surah, verses: verses)),
                      );
                    } else {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MemorizationAyahPickerScreen(
                            surah: surah,
                            verses: verses,
                            onPicked: (pageVerses) => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MemorizationGameScreen(
                                      surah: surah, verses: pageVerses)),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
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
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SurahPickerScreen(
            title: t.coachHubPickerReciteTitle,
            subtitle: t.coachHubPickerReciteSubtitle,
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
                  Text(t.coachHubReciteSurahTitle,
                      style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 5),
                  Text(
                    t.coachHubReciteSurahSubtitle,
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
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(surahErrorSummariesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SectionTitle(t.coachHubErrorsSectionTitle,
                  t.coachHubErrorsSectionSubtitle),
            ),
            // Remise à zéro (demande utilisateur 2026-07-22) : IRRÉVERSIBLE
            // (efface tout l'historique, toutes sourates confondues) ->
            // toujours confirmer avant, jamais un simple tap direct.
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.inkLight),
              tooltip: t.coachHubResetErrorsTooltip,
              onPressed: () => _confirmAndResetErrors(context, ref, t),
            ),
          ],
        ),
        const _ErrorKindBreakdown(),
        const _TajwidRuleBreakdown(),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.green700)),
          ),
          error: (e, _) => _Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t.coachHubLoadErrorLog('$e'),
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
                      Text(t.coachHubNoErrorsTitle,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(
                        t.coachHubNoErrorsBody,
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

/// Boîte de dialogue de confirmation puis remise à zéro complète du journal
/// (demande utilisateur 2026-07-22). Invalide les 3 providers qui en
/// dépendent pour que l'UI reflète immédiatement le vide, sans attendre un
/// prochain rebuild déclenché ailleurs.
Future<void> _confirmAndResetErrors(
    BuildContext context, WidgetRef ref, AppLocalizations t) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.coachHubResetErrorsDialogTitle),
      content: Text(t.coachHubResetErrorsDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t.coachHubResetErrorsDialogCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(t.coachHubResetErrorsDialogConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await RecitationErrorLogService.instance.resetAll();
  ref.invalidate(errorKindBreakdownProvider);
  ref.invalidate(surahErrorSummariesProvider);
  ref.invalidate(tajwidRuleBreakdownProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.coachHubResetErrorsDone)),
    );
  }
}

/// Répartition GLOBALE des erreurs tajwid PAR RÈGLE PRÉCISE (demande
/// utilisateur 2026-07-22) — même présentation que [_ErrorKindBreakdown]
/// (barre empilée + légende), mais un cran plus fin : à l'intérieur du seau
/// "Tajwid", QUELLE règle revient le plus souvent. Couleurs réutilisées de
/// `kTajwidRuleInfo` (tajwid_help_sheet.dart) -- source de vérité unique déjà
/// utilisée pour colorer le texte coranique, pas une nouvelle palette.
class _TajwidRuleBreakdown extends ConsumerWidget {
  const _TajwidRuleBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(tajwidRuleBreakdownProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        if (counts.isEmpty) return const SizedBox.shrink();
        final present = [...counts.keys]
          ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.coachHubRuleBreakdownTitle,
                      style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (final r in present)
                            Expanded(
                              flex: counts[r]!,
                              child: ColoredBox(
                                  color: kTajwidRuleInfo[r.key]?.color ??
                                      AppColors.inkLight),
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
                      for (final r in present)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: kTajwidRuleInfo[r.key]?.color ??
                                      AppColors.inkLight,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${kTajwidRuleInfo[r.key]?.name(t) ?? r.key} · ${counts[r]}',
                              style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ],
                        ),
                    ],
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

class _SurahErrorTile extends ConsumerWidget {
  final SurahErrorSummary summary;
  const _SurahErrorTile({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
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
        title: Text(
            isArabic ? '${s.number}. ${s.nameArabic}' : '${s.number}. ${s.nameSimple}',
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: isArabic
                ? GoogleFonts.scheherazadeNew(fontSize: 16, color: AppColors.ink)
                : GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.coachHubVersesTouched(summary.versesTouched, s.versesCount),
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
        trailing: isArabic
            ? null
            : Text(s.nameArabic,
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
                  label: Text(t.coachHubGoToMindMap),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.green700),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MindMapScreen(surah: s))),
                ),
              ),
            ),
          _SurahTajwidRuleChips(surahNumber: s.number),
          for (final a in summary.ayahs)
            _AyahErrorRow(surah: s, count: a),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Puces compactes "règle · nombre" pour LES erreurs tajwid de CETTE sourate
/// précisément (demande utilisateur 2026-07-22 : stats par sourate ET par
/// règle, pas seulement l'une ou l'autre séparément). Masqué si la sourate
/// n'a aucune erreur de type tajwid -- ne pas afficher une rangée vide.
class _SurahTajwidRuleChips extends ConsumerWidget {
  final int surahNumber;
  const _SurahTajwidRuleChips({required this.surahNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(surahTajwidRuleBreakdownProvider(surahNumber));
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        if (counts.isEmpty) return const SizedBox.shrink();
        final present = [...counts.keys]
          ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in present)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (kTajwidRuleInfo[r.key]?.color ?? AppColors.inkLight)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${kTajwidRuleInfo[r.key]?.name(t) ?? r.key} · ${counts[r]}',
                    style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AyahErrorRow extends StatefulWidget {
  final Surah surah;
  final AyahErrorCount count;
  const _AyahErrorRow({required this.surah, required this.count});

  @override
  State<_AyahErrorRow> createState() => _AyahErrorRowState();
}

class _AyahErrorRowState extends State<_AyahErrorRow> {
  // Détail mot par mot replié par défaut (demande utilisateur 2026-07-22 :
  // « en détaille le mot ou il ya erreur et type d'erreur ») -- un tap sur la
  // ligne déplie/replie, pour ne pas alourdir la liste par sourate qui peut
  // déjà compter des dizaines de versets.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final surah = widget.surah;
    final count = widget.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18, color: AppColors.inkLight),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                              t.coachHubAyahErrorCount(
                                  count.ayahNumber, count.count),
                              style: GoogleFonts.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.coachHubExplanationTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.psychology_alt_outlined,
                      size: 19, color: AppColors.green700),
                  onPressed: () => showCoachExplanation(
                    context,
                    surahNumber: surah.number,
                    ayahNumber: count.ayahNumber,
                    title: isArabic
                        ? '${surah.nameArabic} — ${count.ayahNumber}'
                        : '${surah.nameSimple} — verset ${count.ayahNumber}',
                  ),
                ),
                IconButton(
                  tooltip: t.coachHubReviewVerseTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.school_outlined,
                      size: 19, color: AppColors.green700),
                  onPressed: () => _openCoachForVerse(
                      context, surah.number, count.ayahNumber),
                ),
              ],
            ),
            if (_expanded)
              _AyahErrorDetails(surahNumber: surah.number, ayahNumber: count.ayahNumber),
          ],
        ),
      ),
    );
  }
}

/// Liste mot par mot des erreurs d'un verset, avec le type et -- pour les
/// règles "frontière" (ikhafa/iqlab/idgham à cheval sur deux mots) -- la
/// PAIRE de mots plutôt qu'un seul mot isolé (demande utilisateur 2026-07-22).
class _AyahErrorDetails extends ConsumerWidget {
  final int surahNumber;
  final int ayahNumber;
  const _AyahErrorDetails({required this.surahNumber, required this.ayahNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(ayahErrorDetailsProvider(
        (surahNumber: surahNumber, ayahNumber: ayahNumber)));
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 24, right: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.pairWord != null
                              ? '${e.expectedWord}  ${e.pairWord}'
                              : e.expectedWord,
                          style: GoogleFonts.amiri(
                              fontSize: 16, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (e.rules.isEmpty)
                              Text(recitationErrorKindLabel(t, e.kind),
                                  style: GoogleFonts.manrope(
                                      fontSize: 10.5,
                                      color: AppColors.inkLight))
                            else
                              for (final r in e.rules)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (kTajwidRuleInfo[r.key]?.color ??
                                            AppColors.inkLight)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    kTajwidRuleInfo[r.key]?.name(t) ?? r.key,
                                    style: GoogleFonts.manrope(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
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
    final t = AppLocalizations.of(context)!;
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
                              '${recitationErrorKindLabel(t, k)} · ${counts[k]}',
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
                    t.coachHubErrorNoteExplainer,
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
