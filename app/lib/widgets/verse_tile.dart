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
  /// Appui long (2026-08-05) : raccourci « à partir d'ici » — réciter ou jouer
  /// en partant de CE verset, sans passer par la barre du bas ni sélectionner
  /// d'abord le verset.
  ///
  /// Pourquoi l'appui long et pas un bouton : la page est un Mushaf, chaque
  /// pixel ajouté y prend de la place au texte. Le geste porte l'action sans
  /// rien afficher tant qu'on ne le fait pas.
  final VoidCallback? onLongPress;
  final void Function(int wordIndex)? onWordTap;
  /// Appui long sur un mot (cf. TajweedText.onWordLongPress).
  final void Function(int wordIndex)? onWordLongPress;
  final double textScale;
  // Mode Kindle (2026-08-01) : le curseur de lecture ET le surlignage de
  // sélection utilisaient tous deux du bleu (readingCursorBg/Border,
  // green50/green100) -- couleurs héritées du thème normal, jamais pensées
  // pour un mode explicitement "sans lumière bleue". Signalé par
  // l'utilisateur après une 1ère version du mode Kindle qui ne touchait que
  // le fond de page, pas ces surlignages.
  final bool kindleMode;
  /// Lecture sur fond noir (cf. modeSombreProvider). Prioritaire sur le
  /// sepia du mode Kindle quand les deux sont actifs : c'est le FOND qui
  /// change, et il ne peut pas etre les deux a la fois.
  final bool modeSombre;
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
    this.onLongPress,
    this.onWordTap,
    this.onWordLongPress,
    this.textScale = 1.0,
    this.kindleMode = false,
    this.modeSombre = false,
    this.wordStart,
    this.wordEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Palette de lecture resolue une fois : sombre > kindle > clair.
    final fondProfond = modeSombre
        ? AppColors.sombreBgDeep
        : (kindleMode ? AppColors.kindleBgDeep : AppColors.readingCursorBg);
    final accent = modeSombre
        ? AppColors.sombreAccent
        : (kindleMode ? AppColors.kindleAccent : AppColors.readingCursorBorder);
    final encre = modeSombre
        ? AppColors.sombreInk
        : (kindleMode ? AppColors.kindleInk : AppColors.ink);
    final encreDouce = modeSombre
        ? AppColors.sombreInkSoft
        : (kindleMode ? AppColors.kindleInkSoft : AppColors.inkLight);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        // ── RENDRE LA LARGEUR AU TEXTE (2026-08-06) ──────────────────────
        //
        // Constat utilisateur, capture a l'appui : « pourquoi y a-t-il cet
        // espace entre وَأَنزَلَ et ٱلتَّوْرَىٰةَ ? je pense qu'on peut mettre
        // 3 mots ».
        //
        // Deux choses distinctes se voient sur cette ligne, il faut les
        // separer :
        //
        // 1. L'ESPACE ETIRE vient de `TextAlign.justify`
        //    (tajweed_text.dart, ajoute le 2026-08-01 pour corriger des lignes
        //    visiblement trop courtes). La justification etire les blancs des
        //    lignes NON finales jusqu'aux deux bords : quand la ligne ne porte
        //    que deux mots, tout l'espace restant tombe entre eux. Un Mushaf
        //    imprime etire les LETTRES (kashida), pas les blancs -- Flutter ne
        //    sait pas le faire. On ne retire donc pas `justify` (ce serait
        //    ramener le defaut de 2026-08-01), on lui donne moins d'espace a
        //    etirer.
        //
        // 2. LE NOMBRE DE MOTS PAR LIGNE depend de la largeur disponible. La
        //    tuile en consommait 48 dp (marge 8+8, padding 16+16) sur une
        //    largeur d'ecran de ~411 dp, soit ~12 % du texte -- pour un cadre
        //    decoratif. Ramene a 28 dp, le texte recupere 20 dp.
        //
        // Ce que ce changement NE garantit PAS : qu'un troisieme mot tienne
        // sur CETTE ligne-la. `وَٱلْإِنجِيلَ` est large ; le gain est de
        // l'ordre de sa marge d'echec. On rend la largeur perdue, on ne
        // promet pas le resultat mot a mot.
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          // ── AUCUN SURLIGNAGE SUR FOND NOIR (utilisateur, 2026-08-07) ──
          // « meme pas besoin du surligneur bleu ». Sur fond noir un pave
          // colore derriere le texte ne guide pas l'oeil, il l'agresse -- et
          // le verset en cours se repere deja par sa bordure.
          color: modeSombre
              ? Colors.transparent
              : isPlayingCursor
                  ? fondProfond
                  : isActive
                      ? (kindleMode
                          ? fondProfond.withAlpha(140)
                          : AppColors.green50)
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isPlayingCursor
              ? Border.all(
                  color: accent,
                  width: 1.5)
              : isActive
                  ? Border.all(
                      color: modeSombre || kindleMode
                          ? accent.withAlpha(120)
                          : AppColors.green100,
                      width: 1)
                  : null,
        ),
        child: Padding(
          // horizontal 16 -> 10 (cf. le commentaire de `margin` ci-dessus).
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                onWordLongPress: onWordLongPress,
                wordStart: wordStart,
                wordEnd: wordEnd,
                couleurTexte: encre,
                modeSombre: modeSombre,
                // Le badge ne doit apparaître qu'une fois, sur la portion qui
                // contient le tout 1er mot du verset (l'autre moitié, sur la
                // page suivante, n'en a pas -- ce n'est pas "un nouveau
                // verset qui commence").
                leading: (wordStart == null || wordStart == 0)
                    ? _VerseNumberBadge(verse.ayahNumber,
                        kindleMode: kindleMode, modeSombre: modeSombre)
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
                      // ── LA TRADUCTION SUIT L'ARABE, SANS LE COPIER ──
                      //
                      // Demande utilisateur (2026-08-06) : « je veux que la
                      // taille de la traduction suive un peu la taille de
                      // l'écriture en arabe ; je ne dis pas qu'elle soit
                      // pareille, mais qu'elle suive un peu l'évolution de la
                      // taille ».
                      //
                      // Elle etait FIXE a 13 : agrandir l'arabe la laissait
                      // minuscule a cote, et le rapport devenait absurde aux
                      // grandes tailles. La lier a `textScale` a l'identique
                      // (13 * textScale) la ferait grossir autant que l'arabe,
                      // ce que l'utilisateur ne veut pas non plus -- une
                      // traduction n'est pas le texte, elle doit rester
                      // secondaire.
                      //
                      // Elle suit donc a MOITIE : la moitie de l'ecart a 1.
                      // A textScale=1 elle vaut 13 (inchangee) ; a 1,6 elle
                      // vaut 15,9 au lieu de 20,8 -- l'arabe passe de 26 a
                      // 41,6, donc l'ecart se creuse mais la traduction ne
                      // reste plus figee.
                      fontSize: 13 * (1 + (textScale - 1) * 0.5),
                      color: encreDouce,
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
  final bool modeSombre;
  const _VerseNumberBadge(this.number,
      {this.kindleMode = false, this.modeSombre = false});

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
        painter: _OctagonBadgePainter(
            kindleMode: kindleMode, modeSombre: modeSombre),
        child: Center(
          child: Text(
            isArabic ? _toArabicIndic(number) : '$number',
            style: GoogleFonts.amiri(
              fontSize: 14,
              color: modeSombre
                  ? AppColors.sombreAccent
                  : (kindleMode ? AppColors.kindleAccent : AppColors.brass),
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
  final bool modeSombre;
  const _OctagonBadgePainter({this.kindleMode = false, this.modeSombre = false});

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
        path,
        Paint()
          ..color = modeSombre
              ? AppColors.sombreBgDeep
              : (kindleMode ? AppColors.kindleBgDeep : AppColors.cream200));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = modeSombre
            ? AppColors.sombreAccent
            : (kindleMode ? AppColors.kindleAccent : AppColors.brass),
    );
  }

  @override
  bool shouldRepaint(covariant _OctagonBadgePainter oldDelegate) =>
      oldDelegate.kindleMode != kindleMode ||
      oldDelegate.modeSombre != modeSombre;
}
