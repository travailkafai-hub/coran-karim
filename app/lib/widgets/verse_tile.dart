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
  // Mode Kindle (2026-08-01) : le curseur de lecture ET le surlignage de
  // sélection utilisaient tous deux du bleu (readingCursorBg/Border,
  // green50/green100) -- couleurs héritées du thème normal, jamais pensées
  // pour un mode explicitement "sans lumière bleue". Signalé par
  // l'utilisateur après une 1ère version du mode Kindle qui ne touchait que
  // le fond de page, pas ces surlignages.
  final bool kindleMode;
  // Plage de mots (2026-08-01, mode Kindle : verset scindé entre deux pages,
  // cf. mushaf_screen.dart) -- null = verset entier (partout ailleurs). Le
  // badge de numéro ne s'affiche que sur la page qui contient le 1er mot.
  final int? wordStart;
  final int? wordEnd;

  const VerseTile({
    super.key,
    required this.verse,
    this.isActive = false,
    this.isPlayingCursor = false,
    this.showTranslation = false,
    this.onTap,
    this.onWordTap,
    this.textScale = 1.0,
    this.kindleMode = false,
    this.wordStart,
    this.wordEnd,
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
              ? (kindleMode ? AppColors.kindleBgDeep : AppColors.readingCursorBg)
              : isActive
                  ? (kindleMode
                      ? AppColors.kindleBgDeep.withAlpha(140)
                      : AppColors.green50)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isPlayingCursor
              ? Border.all(
                  color: kindleMode ? AppColors.kindleAccent : AppColors.readingCursorBorder,
                  width: 1.5)
              : isActive
                  ? Border.all(
                      color: kindleMode
                          ? AppColors.kindleAccent.withAlpha(120)
                          : AppColors.green100,
                      width: 1)
                  : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Arabic verse text + verse number badge -- le badge est
              // EMBARQUÉ dans le texte (TajweedText.leading), pas dans un Row
              // à côté (cf. commentaire du champ `leading` dans
              // tajweed_text.dart : un Row réservait sa colonne sur TOUTES
              // les lignes du paragraphe, pas seulement la 1ère -- signalé
              // par l'utilisateur, "la zone où y'a le chiffre verset n'est
              // pas utilisée quand y'a pas de chiffre, ça reste du vide").
              TajweedText(
                textUthmani: verse.textUthmani,
                textUthmaniTajweed: verse.textUthmaniTajweed,
                fontSize: 26 * textScale,
                lineHeight: 2.1,
                onWordTap: onWordTap,
                wordStart: wordStart,
                wordEnd: wordEnd,
                // Le badge ne doit apparaître qu'une fois, sur la portion qui
                // contient le tout 1er mot du verset (l'autre moitié, sur la
                // page suivante, n'en a pas -- ce n'est pas "un nouveau
                // verset qui commence").
                leading: (wordStart == null || wordStart == 0)
                    ? _VerseNumberBadge(verse.ayahNumber, kindleMode: kindleMode)
                    : null,
              ),
              // French translation (optional) -- jamais en mode arabe : la
              // règle du duo (REFONTE_IHM.md §7bis) interdit toute traduction
              // affichée à côté du Coran quand l'app est en arabe. Jamais non
              // plus sur un verset scindé (mode Kindle) -- éviter qu'elle
              // apparaisse sur la mauvaise moitié ou en double.
              if (showTranslation &&
                  wordStart == null &&
                  wordEnd == null &&
                  verse.translationFr != null &&
                  Localizations.localeOf(context).languageCode != 'ar')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _stripHtml(verse.translationFr!),
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: kindleMode ? AppColors.kindleInkSoft : AppColors.inkLight,
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
  final bool kindleMode;
  const _VerseNumberBadge(this.number, {this.kindleMode = false});

  // Convert to Arabic-Indic numerals (٠١٢٣٤٥٦٧٨٩)
  static String _toArabicIndic(int n) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((d) => digits[int.parse(d)]).join();
  }

  @override
  Widget build(BuildContext context) {
    // Chiffres arabo-indiens (٠١٢٣) seulement en locale arabe -- demande
    // utilisateur 2026-08-01 : chiffres occidentaux (1,2,3) en français/
    // anglais, garder les chiffres indiens seulement en mode arabe.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return SizedBox(
      width: 38,
      height: 38,
      child: CustomPaint(
        painter: _OctagonBadgePainter(kindleMode: kindleMode),
        child: Center(
          child: Text(
            isArabic ? _toArabicIndic(number) : '$number',
            style: GoogleFonts.amiri(
              fontSize: 14,
              color: kindleMode ? AppColors.kindleAccent : AppColors.brass,
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
  final bool kindleMode;
  const _OctagonBadgePainter({this.kindleMode = false});

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
    canvas.drawPath(
        path, Paint()..color = kindleMode ? AppColors.kindleBgDeep : AppColors.cream200);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = kindleMode ? AppColors.kindleAccent : AppColors.brass,
    );
  }

  @override
  bool shouldRepaint(covariant _OctagonBadgePainter oldDelegate) =>
      oldDelegate.kindleMode != kindleMode;
}
