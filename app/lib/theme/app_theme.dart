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

  // Mode Kindle (demande utilisateur 2026-08-01) -- thème repos-yeux,
  // volontairement SANS AUCUNE composante bleue dominante (contrairement à
  // readingCursorBg/readingCursorBorder ci-dessus, réservés au mode normal) :
  // fond chaud sépia proche du "warm light" des liseuses e-ink, texte brun
  // foncé plutôt que noir pur -- moins de contraste dur, plus reposant en
  // lecture longue.
  static const kindleBg      = Color(0xFFf2e8d5);
  static const kindleBgDeep  = Color(0xFFe9dcbf);
  static const kindleInk     = Color(0xFF3a2b1a);
  static const kindleInkSoft = Color(0xFF6b5636);
  static const kindleAccent  = Color(0xFF8a6a3a);

  // Erreur de TAJWID pendant la récitation (2026-08-01, demande utilisateur :
  // "une coloration spécifique violet en cas d'erreur liée au tajweed").
  // Distincte du rouge (lettre/harakat mal prononcée) : ici les lettres ET
  // les harakat sont justes, seule une règle attendue n'a pas été réalisée
  // (cf. RecitationErrorKind.tajwid). Violet choisi pour ne collisionner ni
  // avec le rouge/orange/vert du jugement, ni avec les 4 couleurs de
  // coloration tajwid du TEXTE juste en dessous (vert/bleu/orange/rouge) --
  // celles-ci indiquent QUELLE règle s'applique, celle-ci indique qu'une
  // règle a été RATÉE, ce sont deux informations différentes.
  static const recitationTajwidError = Color(0xFFb47bd6);

  // Tajwid colors
  static const tajwidGhunna   = Color(0xFF1a7a5e);  // green — nasal
  static const tajwidQalqala  = Color(0xFF0055aa);  // blue — echo
  static const tajwidMadd     = Color(0xFFb85000);  // orange — elongation
  static const tajwidIkhfaa   = Color(0xFF8b0000);  // red — hidden

  // Carte mentale (REFONTE_IHM.md §7) — 8 categories REELLES, relevees sur
  // les 114 fichiers fournis (921 passages) : recits, croyance, eschatologie,
  // argumentation, ethique, legislation, signes, adoration.
  // (Les 6 categories precedentes -- promesse/avertissement/louange... --
  // etaient celles de ma maquette ; elles ne correspondaient PAS aux donnees
  // reelles. Conservees nulle part ailleurs, ce commentaire est la trace.)
  //
  // Palette manuscrite définitive (2026-07-20), inspirée des enluminures de
  // Coran anciens (lapis-lazuli, malachite, safran, turquoise, aubergine) --
  // validée par le script de sécurité daltonien du skill dataviz (6 checks :
  // bande de luminosité, plancher de chroma, séparation CVD, plancher vision
  // normale, contraste) sur le fond crème de l'app (#fbf7ee), ordre figé.
  // Choisie aussi pour NE PAS entrer en collision avec les couleurs tajwid
  // ci-dessus : l'ancien placeholder reprenait par erreur les mêmes hex que
  // tajwidQalqala/tajwidMadd/tajwidIkhfaa, ce qui aurait pu laisser croire à
  // un lien entre les deux systèmes de couleur alors qu'ils sont indépendants.
  static const mindmapCroyance      = Color(0xFF2B4C9B);  // lapis-lazuli
  static const mindmapSignes        = Color(0xFF0E9C63);  // malachite
  static const mindmapRecits        = Color(0xFFB5651D);  // terracotta
  static const mindmapEschatologie  = Color(0xFF7A3A6E);  // aubergine
  static const mindmapAdoration     = Color(0xFF0AA79E);  // turquoise persan
  static const mindmapLegislation   = Color(0xFFB8860B);  // safran
  static const mindmapEthique       = Color(0xFFC05A82);  // rose poudré
  static const mindmapArgumentation = Color(0xFF4A4A9C);  // indigo
  static const mindmapAutre         = Color(0xFF4a3f2f);  // inkLight (neutre)

  // Jeu de mémorisation (`memorization_game_screen.dart`) — décision
  // utilisateur 2026-07-22 : cet écran vise un public enfant et doit
  // trancher visuellement avec le reste de l'app (sobre, crème/vert/laiton
  // façon manuscrit ancien) via une palette "appli de jeu" saturée et
  // ludique. Volontairement AUCUN hex partagé avec les palettes tajwid/
  // mindmap ci-dessus (même règle que pour éviter la collision mindmap ⟷
  // tajwid) : ces couleurs ne doivent laisser croire à aucun lien avec les
  // autres systèmes de couleur de l'app.
  static const gameBgTop    = Color(0xFFE8F4FF); // ciel très clair
  static const gameBgBottom = Color(0xFFFFF3E0); // pêche très clair
  static const gameCorrect  = Color(0xFF4CAF50); // vert pomme (feedback bon mot)
  static const gameWrong    = Color(0xFFFF5252); // rouge corail (feedback mauvais mot)
  static const gameStar     = Color(0xFFFFC107); // or (étoiles de progression/fin)
  // Rotation de "bonbons" pour les puces de choix de mots -- assez de
  // contraste entre elles pour rester ludique sans dépendre de la couleur
  // seule (les puces restent lisibles par leur texte, jamais par la teinte).
  static const List<Color> gameChipColors = [
    Color(0xFFFF6FA6), // rose bubblegum
    Color(0xFF4FC3F7), // bleu ciel
    Color(0xFFFFD54F), // jaune soleil
    Color(0xFF7CB342), // vert prairie
    Color(0xFFFF8A65), // corail
    Color(0xFFBA68C8), // violet
  ];
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
