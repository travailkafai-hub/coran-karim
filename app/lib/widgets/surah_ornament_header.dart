// Bandeau de séparation entre sourates façon mushaf imprimé traditionnel
// (cartouche calligraphique dans un cadre à motifs géométriques + étoiles à
// 8 branches aux coins, vert/or) -- demande utilisateur 2026-07-19, en
// remplacement de l'ancien `_SurahBanner` (simple pilule arrondie, sans
// caractère "design arabe"). Photos de référence fournies par l'utilisateur :
// couverture de mushaf (cadre doré sur fond vert, cartouche en ogive) et
// bandeau de titre de sourate (cadre noir/or à motifs, cartouche horizontale).
//
// Tout est dessiné en CustomPainter (pas d'asset image) pour rester léger et
// re-colorable via AppColors -- aucune dépendance externe.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../models/verse.dart';

class SurahOrnamentHeader extends StatelessWidget {
  final Surah surah;
  const SurahOrnamentHeader({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    final isMeccan = surah.revelationPlace.toLowerCase().startsWith('makk');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
      child: SizedBox(
        height: 152,
        child: CustomPaint(
          painter: _OrnamentFramePainter(
            frameColor: AppColors.brass,
            fillColor: AppColors.green800,
            fillColorDark: AppColors.green900,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cartouche centrale (forme "vesica" pointue à gauche/droite,
              // motif classique des en-têtes de sourate des mushafs imprimés).
              SizedBox(
                height: 56,
                child: CustomPaint(
                  painter: _CartouchePainter(fillColor: AppColors.brass),
                  child: Center(
                    child: Text(
                      'سُورَةُ ${surah.nameArabic}',
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.amiri(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.green900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Métadonnées : n° sourate, lieu de révélation, nb de versets --
              // sous la cartouche, jamais dans la cartouche (garde le
              // cartouche pur calligraphique, comme le modèle imprimé).
              Text(
                '${surah.number} · ${isMeccan ? 'مكية' : 'مدنية'} · ${surah.versesCount} آية',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.amiri(
                  fontSize: 13,
                  color: AppColors.brassLight,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cadre décoratif : fond vert (dégradé subtil), double filet doré, et un
/// motif répété de petits losanges le long des bords + une étoile à 8
/// branches (rub-el-hizb) à chaque coin -- vocabulaire ornemental déjà
/// présent dans le texte coranique lui-même (marque ۞), réutilisé ici comme
/// motif de cadre plutôt qu'inventé de toutes pièces.
class _OrnamentFramePainter extends CustomPainter {
  final Color frameColor;
  final Color fillColor;
  final Color fillColorDark;

  _OrnamentFramePainter({
    required this.frameColor,
    required this.fillColor,
    required this.fillColorDark,
  });

  static const double _margin = 6;
  static const double _cornerStar = 16;
  static const double _diamondSpacing = 18;
  static const double _diamondSize = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrectOuter = RRect.fromRectAndRadius(outer, const Radius.circular(14));

    // Fond en dégradé vertical (vert foncé haut/bas -> vert un peu plus clair
    // au centre), pour donner un peu de profondeur au bandeau.
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [fillColorDark, fillColor, fillColorDark],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(outer);
    canvas.drawRRect(rrectOuter, fillPaint);

    // Filet extérieur.
    final borderOuter = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = frameColor;
    final rOuter = RRect.fromRectAndRadius(
      outer.deflate(_margin), const Radius.circular(10));
    canvas.drawRRect(rOuter, borderOuter);

    // Filet intérieur, plus fin, légèrement en retrait -- le "double filet"
    // caractéristique des cadres de mushaf.
    final borderInner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = frameColor.withValues(alpha: 0.75);
    final rInner = RRect.fromRectAndRadius(
      outer.deflate(_margin + 5), const Radius.circular(8));
    canvas.drawRRect(rInner, borderInner);

    // Losanges répétés le long des bords haut/bas, entre les deux filets.
    final diamondPaint = Paint()..color = frameColor.withValues(alpha: 0.9);
    final midY = _margin + 2.5;
    final bottomY = size.height - _margin - 2.5;
    for (double x = _margin + _diamondSpacing;
        x < size.width - _margin - _diamondSpacing / 2;
        x += _diamondSpacing) {
      _drawDiamond(canvas, Offset(x, midY), _diamondSize, diamondPaint);
      _drawDiamond(canvas, Offset(x, bottomY), _diamondSize, diamondPaint);
    }

    // Étoiles à 8 branches aux 4 coins (motif rub-el-hizb).
    final starPaint = Paint()..color = frameColor;
    final inset = _margin + 8;
    _drawEightPointStar(canvas, Offset(inset, inset), _cornerStar, starPaint);
    _drawEightPointStar(
        canvas, Offset(size.width - inset, inset), _cornerStar, starPaint);
    _drawEightPointStar(
        canvas, Offset(inset, size.height - inset), _cornerStar, starPaint);
    _drawEightPointStar(canvas, Offset(size.width - inset, size.height - inset),
        _cornerStar, starPaint);
  }

  void _drawDiamond(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size / 2)
      ..lineTo(center.dx + size / 2, center.dy)
      ..lineTo(center.dx, center.dy + size / 2)
      ..lineTo(center.dx - size / 2, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawEightPointStar(
      Canvas canvas, Offset center, double outerRadius, Paint paint) {
    final innerRadius = outerRadius * 0.45;
    final path = Path();
    for (int i = 0; i < 16; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final angle = (i * 22.5) * math.pi / 180;
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrnamentFramePainter oldDelegate) => false;
}

/// Cartouche centrale : forme "vesica" (pointue à gauche et à droite, bombée
/// en haut et en bas) -- le motif classique des cartouches d'en-tête de
/// sourate dans les mushafs imprimés (ex. mushaf al-Madinah).
class _CartouchePainter extends CustomPainter {
  final Color fillColor;
  _CartouchePainter({required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pointInset = w * 0.06; // pointes gauche/droite
    final bulge = h * 0.22; // bombement haut/bas

    final path = Path()
      ..moveTo(pointInset, h / 2)
      ..quadraticBezierTo(w * 0.28, -bulge * 0.3, w / 2, bulge * 0.15)
      ..quadraticBezierTo(w * 0.72, -bulge * 0.3, w - pointInset, h / 2)
      ..quadraticBezierTo(
          w * 0.72, h + bulge * 0.3, w / 2, h - bulge * 0.15)
      ..quadraticBezierTo(w * 0.28, h + bulge * 0.3, pointInset, h / 2)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          fillColor.withValues(alpha: 0.95),
          fillColor.withValues(alpha: 0.75),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = fillColor.withValues(alpha: 0.6);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CartouchePainter oldDelegate) => false;
}
