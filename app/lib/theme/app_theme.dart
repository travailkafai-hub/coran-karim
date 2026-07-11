import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const green900 = Color(0xFF0c3b2c);
  static const green800 = Color(0xFF114d39);
  static const green700 = Color(0xFF16604a);
  static const green600 = Color(0xFF1a7a5e);
  static const green100 = Color(0xFFd4ede6);
  static const green50  = Color(0xFFebf7f3);

  static const brass    = Color(0xFFc8a23c);
  static const brassLight = Color(0xFFe6cf8f);

  static const cream    = Color(0xFFfbf7ee);
  static const cream200 = Color(0xFFf3ead6);
  static const cream300 = Color(0xFFe8dfc4);

  static const ink      = Color(0xFF1a1209);
  static const inkLight = Color(0xFF4a3f2f);

  // Curseur de lecture audio (verset en cours de récitation par le réciteur,
  // distinct du surlignage vert "verset sélectionné au tap")
  static const readingCursorBg     = Color(0xFFe3f0fb);
  static const readingCursorBorder = Color(0xFF4a90d9);

  // Tajwid colors
  static const tajwidGhunna   = Color(0xFF1a7a5e);  // green — nasal
  static const tajwidQalqala  = Color(0xFF0055aa);  // blue — echo
  static const tajwidMadd     = Color(0xFFb85000);  // orange — elongation
  static const tajwidIkhfaa   = Color(0xFF8b0000);  // red — hidden
}

class AppTheme {
  static TextTheme _arabicTextTheme() {
    return TextTheme(
      // Verse text — Scheherazade New for Uthmanic look
      displayLarge: GoogleFonts.scheherazadeNew(
        fontSize: 28, height: 2.2, color: AppColors.ink,
      ),
      // Verse text compact
      displayMedium: GoogleFonts.scheherazadeNew(
        fontSize: 22, height: 2.0, color: AppColors.ink,
      ),
      // UI labels Arabic
      bodyLarge: GoogleFonts.amiri(
        fontSize: 16, color: AppColors.inkLight,
      ),
      // Titles Latin
      headlineLarge: GoogleFonts.fraunces(
        fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.cream,
      ),
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.cream,
      ),
      // UI text Latin
      labelLarge: GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.cream,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: 11, color: AppColors.cream,
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.light(
        primary: AppColors.green800,
        secondary: AppColors.brass,
        surface: AppColors.cream,
        onPrimary: AppColors.cream,
        onSurface: AppColors.ink,
      ),
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: _arabicTextTheme(),
      useMaterial3: true,
    );
  }
}
