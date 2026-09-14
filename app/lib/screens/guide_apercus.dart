// ChGPT: display-only tutorial surfaces; no microphone, verdict or archive.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/recitation_state.dart' show WordStatus;
import '../models/verse.dart';
import '../models/reciter.dart';
import '../providers/player_provider.dart';
import '../providers/prayer_settings_provider.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/verse_tile.dart';
import '../widgets/dua_card.dart';
import '../data/duas_data.dart';
import '../widgets/guide_interactif.dart';
import 'mushaf_screen.dart' show ActionsVersetGuide;
import 'prayer_times_settings_screen.dart';
import 'reciter_select_screen.dart';
import 'reciter_downloads_screen.dart';

class GuideLecture extends StatefulWidget {
  final bool menu;
  final bool traduction;
  const GuideLecture({super.key, this.menu = false, this.traduction = false});
  @override
  State<GuideLecture> createState() => _GuideLectureState();
}

class _GuideLectureState extends State<GuideLecture> {
  late Future<List<Verse>> _verses = QuranApi.fetchVerses(1);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.mushafPapier,
    appBar: AppBar(
      title: Text(
        widget.menu
            ? AppLocalizations.of(context)!.mushafFromHere
            : AppLocalizations.of(context)!.navQuran,
      ),
    ),
    body: FutureBuilder<List<Verse>>(
      future: _verses,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: IconButton(
              tooltip: guideTexte(
                context,
                'Réessayer',
                'Retry',
                'إعادة المحاولة',
              ),
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  setState(() => _verses = QuranApi.fetchVerses(1)),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final verses = s.data!;
        return ListView(
          children: [
            for (
              var i = 0;
              i < (widget.menu ? verses.take(1).length : verses.length);
              i++
            )
              GuideCible(
                'verse.$i',
                child: VerseTile(
                  verse: verses[i],
                  isActive: widget.menu,
                  showTranslation: widget.traduction,
                ),
              ),
            if (widget.menu) const ActionsVersetGuide(),
            const SizedBox(height: 280),
          ],
        );
      },
    ),
  );
}

class GuideReciteurs extends ConsumerWidget {
  final bool telechargements;
  const GuideReciteurs({super.key, this.telechargements = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerProvider).reciter;
    final disponibles = Reciter.pour(QuranApi.riwaya);
    final reciter = disponibles.firstWhere(
      (r) => r.id == current.id,
      orElse: () => disponibles.first,
    );
    return GuideCible(
      telechargements ? 'audio.downloads' : 'audio.reciters',
      child: telechargements
          ? ReciterDownloadsScreen(reciter: reciter)
          : ReciterSelectScreen(currentId: reciter.id),
    );
  }
}

class GuideInvocation extends StatelessWidget {
  const GuideInvocation({super.key});
  @override
  Widget build(BuildContext context) {
    final dua = kAllDuas.firstWhere((d) => d.repeat > 1 && d.hasAudio);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.navDuas)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DuaCard(dua: dua, initiallyExpanded: true),
          const SizedBox(height: 280),
        ],
      ),
    );
  }
}

// Reuse current cached prayer data without invoking the provider bootstrap.
// No location request, notification scheduling, or sample hours presented as real.
class _LecturePriere extends PrayerSettingsNotifier {
  _LecturePriere(PrayerState snapshot) {
    state = snapshot;
  }
}

class GuidePrieres extends ConsumerStatefulWidget {
  const GuidePrieres({super.key});
  @override
  ConsumerState<GuidePrieres> createState() => _GuidePrieresState();
}

class _GuidePrieresState extends ConsumerState<GuidePrieres> {
  PrayerState? _snapshot;
  @override
  Widget build(BuildContext context) {
    _snapshot ??= ref.read(prayerSettingsProvider);
    return ProviderScope(
      overrides: [
        prayerSettingsProvider.overrideWith((_) => _LecturePriere(_snapshot!)),
      ],
      child: const PrayerTimesSettingsScreen(),
    );
  }
}

// ── MONTRER LA RÉCITATION SANS EN LANCER UNE (2026-09-14) ────────────────────
//
// Demande utilisateur : « je veux que tu montres réciter avec un exemple de
// récitation (juste la coloration des textes) », et « également tu montres
// mémoriser et chaîne ».
//
// ⚠️ POURQUOI UN EXEMPLE PRÉPARÉ ICI, ET SEULEMENT ICI : tous les autres
// aperçus de ce fichier réutilisent l'écran RÉEL en lecture seule
// (`ReciterSelectScreen`, `PrayerTimesSettingsScreen`, `DuaCard`…), et c'est la
// bonne façon de faire. Elle est impossible pour la récitation : les couleurs
// des mots n'existent QUE comme sortie du modèle sur du son capté au micro.
// Afficher le vrai écran ne montrerait donc rien du tout -- ou exigerait
// d'ouvrir le micro, ce que l'utilisateur a explicitement exclu (« elle ne
// lancerait pas le modèle, n'utiliserait pas le micro »).
//
// Les garanties, toutes vérifiables dans les imports de ce fichier :
//   * aucun import de `recitation_provider`, `fastconformer_verifier`, `record`
//     ni `session_archive_service` -- l'ABSENCE D'IMPORT EST LA GARANTIE. Ne
//     pas la remplacer par un `if (apercu) return`, qu'un refactor peut
//     déplacer sans qu'on s'en aperçoive ;
//   * le texte vient de `QuranApi`, jamais saisi à la main (règle projet, payée
//     le 2026-07-09 : un « ي » persan tapé au clavier au lieu du « ي » arabe
//     standard avait cassé la reconnaissance d'un mot, sans que rien ne se voie
//     à l'écran) ;
//   * les couleurs sont celles de `recitation_screen._colorFor`, reprises à
//     l'identique pour que ce qu'on montre soit ce qu'on verra. C'est le seul
//     endroit de ce fichier qui duplique une décision visuelle : la fonction
//     source est privée à un `State`, donc non importable. Si elle change
//     là-bas, elle doit changer ici.
class GuideRecitationCouleurs extends StatefulWidget {
  const GuideRecitationCouleurs({super.key});
  @override
  State<GuideRecitationCouleurs> createState() =>
      _GuideRecitationCouleursState();
}

class _GuideRecitationCouleursState extends State<GuideRecitationCouleurs> {
  /// Le verdict de chaque mot, écrit à la main, dans un ordre qui RACONTE :
  /// une série juste, un mot approximatif, un écart, puis la reprise. Une
  /// démonstration tout en vert ne montrerait pas à quoi sert l'application.
  static const _scenario = <WordStatus>[
    WordStatus.correct,
    WordStatus.correct,
    WordStatus.correct,
    WordStatus.correct,
    WordStatus.unclear,
    WordStatus.correct,
    WordStatus.error,
    WordStatus.correct,
    WordStatus.correct,
  ];

  final Future<List<Verse>> _versets = QuranApi.fetchVerses(1);
  List<String> _mots = const [];
  int _avance = 0;
  Timer? _minuterie;

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  void _demarrer() {
    _minuterie?.cancel();
    _avance = 0;
    // Cadence FIXE, jamais aléatoire : une démonstration doit être identique à
    // chaque passage, sinon on ne peut pas la commenter.
    _minuterie = Timer.periodic(const Duration(milliseconds: 640), (t) {
      if (!mounted || _avance >= _mots.length) {
        t.cancel();
        return;
      }
      setState(() => _avance++);
    });
  }

  Color _couleur(WordStatus s) => switch (s) {
        WordStatus.correct => AppColors.green600,
        WordStatus.error => const Color(0xFFb00020),
        WordStatus.unclear => AppColors.tajwidMadd,
        _ => AppColors.inkLight,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(t.guideChapitreRecitationTitre),
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
      ),
      body: FutureBuilder<List<Verse>>(
        future: _versets,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_mots.isEmpty) {
            final mots = <String>[];
            for (final v in snap.data!.where((v) => v.ayahNumber >= 2)) {
              mots.addAll(v.textUthmani
                  .split(RegExp(r'\s+'))
                  .where((m) => m.isNotEmpty));
              if (mots.length >= _scenario.length) break;
            }
            _mots = mots.take(_scenario.length).toList();
            WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
          }
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < _mots.length; i++)
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            style: GoogleFonts.amiri(
                              fontSize: 28,
                              height: 1.9,
                              color: i < _avance
                                  ? _couleur(_scenario[i])
                                  : AppColors.inkLight.withValues(alpha: 0.45),
                              fontWeight: i < _avance &&
                                      _scenario[i] == WordStatus.correct
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            child: Text(_mots[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _pastille(AppColors.green600, t.demoLegendeVert),
                    _pastille(AppColors.tajwidMadd, t.demoLegendeOrange),
                    _pastille(const Color(0xFFb00020), t.demoLegendeRouge),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pastille(Color c, String texte) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(texte,
              style: GoogleFonts.manrope(
                  fontSize: 11.5, color: AppColors.inkLight)),
        ],
      );
}
