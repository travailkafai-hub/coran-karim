import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/quran_shazam_sheet.dart';
import 'mushaf_screen.dart';
import 'prayer_follow_screen.dart';

class SurahListScreen extends ConsumerStatefulWidget {
  const SurahListScreen({super.key});

  @override
  ConsumerState<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends ConsumerState<SurahListScreen> {
  List<Surah> _surahs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final surahs = await QuranApi.fetchSurahs();
      setState(() { _surahs = surahs; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Identification (Shazam coranique) déclenchée depuis la page principale --
  // REFONTE_IHM.md §5. Ouvre directement le Mushaf au passage identifié (même
  // logique que mushaf_screen.dart::_openShazam, mais on part toujours d'un
  // écran neuf ici puisqu'aucune sourate n'est encore chargée en scroll continu).
  Future<void> _openShazamFromHome() async {
    final match = await showQuranShazamSheet(context, ref);
    if (match == null || !mounted) return;
    _openMushafAt(match.surahNumber, match.ayahNumber);
  }

  Future<void> _openMushafAt(int surahNumber, int ayahNumber) async {
    final surahs = _surahs.isNotEmpty ? _surahs : await QuranApi.fetchSurahs();
    final target = surahs.firstWhere((s) => s.number == surahNumber,
        orElse: () => surahs.first);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafScreen(surah: target, initialAyahNumber: ayahNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.green900,
            // "Suivre une prière" + "Identifier" (Shazam coranique) cote a
            // cote -- retour utilisateur 2026-07-19 : la version en grandes
            // cartes (§5 du plan) etait moins bien que les simples icones
            // d'origine, garder ce style, juste ajouter Identifier a cote de
            // Suivre une priere plutot que de le laisser seul dans la barre
            // du bas de l'ecran de lecture.
            actions: [
              IconButton(
                icon: const Icon(Icons.hearing_rounded, color: AppColors.cream),
                tooltip: 'Identifier une récitation',
                onPressed: _openShazamFromHome,
              ),
              IconButton(
                icon: const Icon(Icons.mosque_rounded, color: AppColors.cream),
                tooltip: 'Suivre une prière',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrayerFollowScreen())),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.green900, AppColors.green800],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'القرآن الكريم',
                        style: GoogleFonts.scheherazadeNew(
                          fontSize: 32, color: AppColors.cream,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'CORAN KARIM',
                        style: GoogleFonts.fraunces(
                          fontSize: 13, color: AppColors.brassLight,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.green800)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: AppColors.green700),
                    const SizedBox(height: 12),
                    Text('Connexion requise', style: GoogleFonts.manrope(
                      color: AppColors.inkLight, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _SurahTile(surah: _surahs[i]),
                  childCount: _surahs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// "Suivre une prière" / "Identifier" en grandes cartes (§5 du plan) --
// ESSAYE puis RETIRE (2026-07-19, retour utilisateur : "avant c'était
// mieux") : revenu aux simples icônes d'app bar (voir SliverAppBar.actions
// plus haut), Identifier ajoutée à côté de Suivre une prière plutôt que
// laissée seule dans la barre du bas de l'écran de lecture. Implémentation
// des cartes conservée dans l'historique git si on veut la reprendre un jour
// avec un design différent.

class _SurahTile extends StatelessWidget {
  final Surah surah;
  const _SurahTile({required this.surah});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => MushafScreen(surah: surah))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.cream300, width: 0.8),
          ),
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brass, width: 1.5),
                color: AppColors.cream200,
              ),
              child: Center(
                child: Text(
                  '${surah.number}',
                  style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.brass,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Name + metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(surah.nameSimple,
                    style: GoogleFonts.manrope(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    )),
                  const SizedBox(height: 2),
                  Text(
                    '${surah.versesCount} versets • ${surah.revelationPlace == "makkah" ? "Mecquoise" : "Médinoise"}',
                    style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight),
                  ),
                ],
              ),
            ),
            // Arabic name
            Text(
              surah.nameArabic,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.scheherazadeNew(
                fontSize: 20, color: AppColors.green800,
              ),
            ),
            // Icône « carte mentale » par sourate RETIRÉE le 2026-07-20
            // (demande utilisateur : « la carte mentale, je veux que tu
            // l'enlèves de la première page »). La page principale redevient
            // une simple liste de sourates. La carte mentale reste accessible
            // depuis l'en-tête de lecture et depuis le volet erreurs du hub
            // Coach (REFONTE_IHM.md §11.3/§11.5).
          ],
        ),
      ),
    );
  }
}
