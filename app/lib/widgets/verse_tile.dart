import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';
import 'tajweed_text.dart';

class VerseTile extends StatelessWidget {
  final Verse verse;
  final bool isActive;
  final bool isPlayingCursor;
  final bool showTranslation;
  final VoidCallback? onTap;
  final void Function(int wordIndex)? onWordTap;
  final double textScale;

  const VerseTile({
    super.key,
    required this.verse,
    this.isActive = false,
    this.isPlayingCursor = false,
    this.showTranslation = false,
    this.onTap,
    this.onWordTap,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isPlayingCursor
              ? AppColors.readingCursorBg
              : isActive
                  ? AppColors.green50
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isPlayingCursor
              ? Border.all(color: AppColors.readingCursorBorder, width: 1.5)
              : isActive
                  ? Border.all(color: AppColors.green100, width: 1)
                  : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Arabic verse text + verse number badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _VerseNumberBadge(verse.ayahNumber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TajweedText(
                      textUthmani: verse.textUthmani,
                      textUthmaniTajweed: verse.textUthmaniTajweed,
                      fontSize: 26 * textScale,
                      lineHeight: 2.1,
                      onWordTap: onWordTap,
                    ),
                  ),
                ],
              ),
              // French translation (optional) -- jamais en mode arabe : la
              // règle du duo (REFONTE_IHM.md §7bis) interdit toute traduction
              // affichée à côté du Coran quand l'app est en arabe.
              if (showTranslation &&
                  verse.translationFr != null &&
                  Localizations.localeOf(context).languageCode != 'ar')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _stripHtml(verse.translationFr!),
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkLight,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _stripHtml(String t) =>
      t.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _VerseNumberBadge extends StatelessWidget {
  final int number;
  const _VerseNumberBadge(this.number);

  // Convert to Arabic-Indic numerals (٠١٢٣٤٥٦٧٨٩)
  static String _toArabicIndic(int n) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((d) => digits[int.parse(d)]).join();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: CustomPaint(
        painter: const _OctagonBadgePainter(),
        child: Center(
          child: Text(
            _toArabicIndic(number),
            style: GoogleFonts.amiri(
              fontSize: 14,
              color: AppColors.brass,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// Repère de fin de verset -- octogone plutôt qu'un simple cercle, pour
// reprendre le même motif que le filigrane de fond (widgets/
// quran_pattern_background.dart, formule identique : sommets tous les 45°,
// décalés de 22.5°) plutôt que d'inventer une seconde forme. Séparation
// visuelle entre versets minimale et volontairement sobre -- pas de nouvel
// élément ajouté entre chaque verset, juste ce repère existant qui devient
// cohérent avec le reste de l'habillage graphique.
class _OctagonBadgePainter extends CustomPainter {
  const _OctagonBadgePainter();

  static Path _octagonPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rad = (22.5 + i * 45 - 90) * math.pi / 180;
      final x = cx + r * math.cos(rad);
      final y = cy + r * math.sin(rad);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _octagonPath(size);
    canvas.drawPath(path, Paint()..color = AppColors.cream200);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.brass,
    );
  }

  @override
  bool shouldRepaint(covariant _OctagonBadgePainter oldDelegate) => false;
}
