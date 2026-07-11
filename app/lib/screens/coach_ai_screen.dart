import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_explanation_sheet.dart';

/// Onglet "Coach IA" — les erreurs de récitation journalisées, verset par
/// verset ; taper sur un verset demande à Gemma (tutor-v6, on-device)
/// d'expliquer pourquoi ces mots sont difficiles.
class CoachAiScreen extends StatefulWidget {
  const CoachAiScreen({super.key});

  @override
  State<CoachAiScreen> createState() => _CoachAiScreenState();
}

class _CoachAiScreenState extends State<CoachAiScreen> {
  List<AyahErrorCount>? _counts;
  Map<int, Surah> _surahsByNumber = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        RecitationErrorLogService.instance.errorCountsByAyah(),
        QuranApi.fetchSurahs(),
      ]);
      final counts = results[0] as List<AyahErrorCount>;
      final surahs = results[1] as List<Surah>;
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _surahsByNumber = {for (final s in surahs) s.number: s};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text('مدرّبي',
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Tester le Coach IA',
            onPressed: () => showCoachExplanation(
              context,
              surahNumber: 1,
              ayahNumber: 5,
              title: 'Test — Al-Fatihah, verset 5',
              testMistakenWord: 'نَسْتَعِينُ',
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Impossible de charger le journal : $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.green700)),
        ),
      );
    }
    final counts = _counts;
    if (counts == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.green700));
    }
    if (counts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 48, color: AppColors.green700),
              const SizedBox(height: 16),
              Text('Aucune erreur journalisée pour l\'instant',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.scheherazadeNew(
                      fontSize: 18, color: AppColors.green900)),
              const SizedBox(height: 8),
              const Text(
                'Les mots à corriger pendant tes récitations apparaîtront ici, '
                'classés par verset.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.green700, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: counts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _AyahErrorTile(
        count: counts[i],
        surah: _surahsByNumber[counts[i].surahNumber],
      ),
    );
  }
}

class _AyahErrorTile extends StatelessWidget {
  final AyahErrorCount count;
  final Surah? surah;
  const _AyahErrorTile({required this.count, required this.surah});

  @override
  Widget build(BuildContext context) {
    final surahLabel = surah?.nameSimple ?? 'Sourate ${count.surahNumber}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green700.withAlpha(40)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.brass.withAlpha(40),
          child: Text('${count.count}',
              style: const TextStyle(
                  color: AppColors.green900, fontWeight: FontWeight.bold)),
        ),
        title: Text('$surahLabel — verset ${count.ayahNumber}',
            style: const TextStyle(color: AppColors.green900)),
        trailing: Text(surah?.nameArabic ?? '',
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 16, color: AppColors.green700)),
        onTap: () => _showExplanation(context, count, surahLabel),
      ),
    );
  }

  void _showExplanation(BuildContext context, AyahErrorCount count, String surahLabel) {
    showCoachExplanation(
      context,
      surahNumber: count.surahNumber,
      ayahNumber: count.ayahNumber,
      title: '$surahLabel — verset ${count.ayahNumber}',
    );
  }
}
