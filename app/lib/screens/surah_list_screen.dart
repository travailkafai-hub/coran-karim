import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import 'mushaf_screen.dart';
import 'prayer_follow_screen.dart';

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
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
            // "Suivre une prière" (demande utilisateur 2026-07-18) : point
            // d'entrée dédié pour un imam, SANS choisir de sourate au
            // préalable (contrairement au karaoké classique, ouvert depuis
            // une sourate précise) -- accessible directement depuis l'accueil.
            actions: [
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
          ],
        ),
      ),
    );
  }
}
