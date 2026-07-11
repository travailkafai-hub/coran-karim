import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/tutor_llm_service.dart';
import '../theme/app_theme.dart';

/// Ouvre la feuille d'explication Coach IA pour un verset (ou un mot précis
/// dedans) — point d'entrée partagé (onglet "مدرّبي", barre d'action du
/// Mushaf, et tap sur un mot dans le Mushaf — demande utilisateur
/// 2026-07-10).
///
/// [focusWord] : mot précis à expliquer (registre SENS, ex. tap sur un mot
/// pendant la lecture) — prioritaire sur le journal d'erreurs.
/// [useErrorLog] : si true (défaut, onglet Coach IA), le journal d'erreurs
/// de récitation pour cette aya oriente l'explication vers le registre
/// MÉMORISATION. Le Mushaf passe `false` : lire un verset n'est pas une
/// session de révision d'erreur, même si ce verset a été raté par ailleurs.
void showCoachExplanation(
  BuildContext context, {
  required int surahNumber,
  required int ayahNumber,
  required String title,
  String? focusWord,
  String? testMistakenWord,
  bool useErrorLog = true,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => CoachExplanationSheet(
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      title: title,
      focusWord: focusWord,
      testMistakenWord: testMistakenWord,
      useErrorLog: useErrorLog,
    ),
  );
}

class CoachExplanationSheet extends StatefulWidget {
  final int surahNumber;
  final int ayahNumber;
  final String title;
  final String? focusWord;
  // Mot fixe utilisé uniquement par le bouton "Tester le Coach IA" (pas
  // d'erreur réelle journalisée pour ce verset de démo).
  final String? testMistakenWord;
  final bool useErrorLog;
  const CoachExplanationSheet({
    super.key,
    required this.surahNumber,
    required this.ayahNumber,
    required this.title,
    this.focusWord,
    this.testMistakenWord,
    this.useErrorLog = true,
  });

  @override
  State<CoachExplanationSheet> createState() => _CoachExplanationSheetState();
}

class _CoachExplanationSheetState extends State<CoachExplanationSheet> {
  String? _explanation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        QuranApi.fetchVerses(widget.surahNumber),
        widget.useErrorLog
            ? RecitationErrorLogService.instance
                .errorsForAyah(widget.surahNumber, widget.ayahNumber)
            : Future.value(const <RecitationErrorEntry>[]),
      ]);
      final verses = results[0] as List<Verse>;
      final errors = results[1] as List<RecitationErrorEntry>;
      final verse = verses.firstWhere((v) => v.ayahNumber == widget.ayahNumber);
      final mistakenWords = errors.isNotEmpty
          ? errors.map((e) => e.expectedWord).toList()
          : (widget.testMistakenWord != null ? [widget.testMistakenWord!] : null);
      final explanation = await TutorLlmService.instance.explainVerse(
        surahNumber: widget.surahNumber,
        ayahNumber: widget.ayahNumber,
        verseText: verse.textUthmani,
        mistakenWords: mistakenWords,
        focusWord: widget.focusWord,
      );
      if (!mounted) return;
      setState(() {
        _explanation = explanation ??
            "Le Coach IA n'est pas encore disponible sur cet appareil.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: GoogleFonts.scheherazadeNew(
                      fontSize: 20, color: AppColors.green900)),
              const SizedBox(height: 16),
              if (_error != null)
                Text('Erreur : $_error',
                    style: const TextStyle(color: AppColors.green700))
              else if (_explanation == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.green700)),
                )
              else
                Text(_explanation!,
                    style:
                        const TextStyle(color: AppColors.green900, height: 1.4)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
