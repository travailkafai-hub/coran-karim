import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/verse.dart';

/// Structure graphique d'une page de mushaf, dessinee uniquement par Flutter.
///
/// Les scans Warsh servent de reference de proportions et de vocabulaire
/// visuel. Aucun pixel de ces pages n'est embarque dans l'application.
enum MushafFrameStyle { opening, regular }

class MushafPageChrome extends StatelessWidget {
  final MushafFrameStyle style;
  final bool dark;
  final Widget child;

  const MushafPageChrome({
    super.key,
    required this.style,
    required this.dark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final opening = style == MushafFrameStyle.opening;
        final horizontal = opening
            ? (constraints.maxWidth * 0.075).clamp(24.0, 42.0)
            : (constraints.maxWidth * 0.032).clamp(10.0, 16.0);
        final vertical = opening
            ? (constraints.maxHeight * 0.045).clamp(28.0, 48.0)
            : (constraints.maxHeight * 0.018).clamp(11.0, 19.0);

        return ColoredBox(
          color: dark ? const Color(0xFF111B19) : const Color(0xFFFFFEF6),
          child: CustomPaint(
            painter: _MushafFramePainter(style: style, dark: dark),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                vertical,
                horizontal,
                opening ? vertical * 0.86 : vertical,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Cartouche de debut/separation de sourate inspire des deux pages d'ouverture.
class MushafSurahBanner extends StatelessWidget {
  static const double openingHeight = 76;
  static const double compactHeight = 62;

  final Surah surah;
  final bool compact;
  final bool dark;

  const MushafSurahBanner({
    super.key,
    required this.surah,
    required this.dark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? compactHeight : openingHeight;
    final ink = dark ? const Color(0xFFF3E7C3) : const Color(0xFF18140F);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sealSize = compact ? 34.0 : 42.0;
          final sideInset = (constraints.maxWidth * 0.105).clamp(25.0, 52.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SurahBannerPainter(dark: dark)),
              ),
              Positioned(
                left: sideInset - sealSize / 2,
                child: _Seal(
                  size: sealSize,
                  label: 'آياتها',
                  value: _arabicDigits(surah.versesCount),
                  dark: dark,
                ),
              ),
              Positioned(
                right: sideInset - sealSize / 2,
                child: _Seal(
                  size: sealSize,
                  label: 'ترتيبها',
                  value: _arabicDigits(surah.number),
                  dark: dark,
                ),
              ),
              Positioned(
                left: constraints.maxWidth * 0.22,
                right: constraints.maxWidth * 0.22,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'سُورَةُ ${surah.nameArabic}',
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    style: GoogleFonts.amiri(
                      fontSize: compact ? 23 : 28,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Seal extends StatelessWidget {
  final double size;
  final String label;
  final String value;
  final bool dark;

  const _Seal({
    required this.size,
    required this.label,
    required this.value,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF294B42) : const Color(0xFF416F5E),
        border: Border.all(color: const Color(0xFFB59A5A), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiri(
                color: const Color(0xFFFFF9E9),
                fontSize: 9,
                height: 0.95,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.amiri(
                color: Colors.white,
                fontSize: 13,
                height: 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahBannerPainter extends CustomPainter {
  final bool dark;

  const _SurahBannerPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(
      0,
      size.height * 0.18,
      size.width,
      size.height * 0.64,
    );
    final green = dark ? const Color(0xFF263D37) : const Color(0xFFDCE8DF);
    final deepGreen = dark ? const Color(0xFF89A99C) : const Color(0xFF416F5E);
    final gold = dark ? const Color(0xFF9B8551) : const Color(0xFFB59A5A);
    final paper = dark ? const Color(0xFF172421) : const Color(0xFFFFFEF6);

    canvas.drawRect(bar, Paint()..color = green);
    canvas.drawRect(
      bar.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gold,
    );

    final motifPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = gold.withValues(alpha: 0.9);
    for (double x = 8; x < size.width; x += 18) {
      final center = Offset(x, size.height / 2);
      final diamond = Path()
        ..moveTo(center.dx, center.dy - 8)
        ..lineTo(center.dx + 6, center.dy)
        ..lineTo(center.dx, center.dy + 8)
        ..lineTo(center.dx - 6, center.dy)
        ..close();
      canvas.drawPath(diamond, motifPaint);
      canvas.drawCircle(center, 1.7, Paint()..color = deepGreen);
    }

    final left = size.width * 0.18;
    final right = size.width * 0.82;
    final top = size.height * 0.08;
    final bottom = size.height * 0.92;
    final notch = size.height * 0.14;
    final panel = Path()
      ..moveTo(left + notch, top)
      ..lineTo(right - notch, top)
      ..quadraticBezierTo(right, top, right, top + notch)
      ..lineTo(right + notch, size.height / 2)
      ..lineTo(right, bottom - notch)
      ..quadraticBezierTo(right, bottom, right - notch, bottom)
      ..lineTo(left + notch, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - notch)
      ..lineTo(left - notch, size.height / 2)
      ..lineTo(left, top + notch)
      ..quadraticBezierTo(left, top, left + notch, top)
      ..close();
    canvas.drawPath(panel, Paint()..color = paper);
    canvas.drawPath(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = deepGreen,
    );
  }

  @override
  bool shouldRepaint(covariant _SurahBannerPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _MushafFramePainter extends CustomPainter {
  final MushafFrameStyle style;
  final bool dark;

  const _MushafFramePainter({required this.style, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    if (style == MushafFrameStyle.opening) {
      _paintOpening(canvas, size);
    } else {
      _paintRegular(canvas, size);
    }
  }

  void _paintRegular(Canvas canvas, Size size) {
    final green = dark ? const Color(0xFF7DB89F) : const Color(0xFF58A77E);
    final pale = dark ? const Color(0xFF315B4E) : const Color(0xFFA7D6BE);
    final outer = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = green,
    );
    canvas.drawRect(
      outer.deflate(6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = pale,
    );
    _paintEdgePattern(canvas, size, inset: 4.2, step: 11, color: pale);
  }

  void _paintOpening(Canvas canvas, Size size) {
    // CHGPT : les pages d'ouverture restent distinctes sans reprendre les
    // couleurs tres saturees du scan. Deux tons calmes et beaucoup de papier
    // remplacent le rouge, le cyan et la frise florale dense.
    final green = dark ? const Color(0xFF7F9F92) : const Color(0xFF416F5E);
    final pale = dark ? const Color(0xFF344D45) : const Color(0xFFC8D9CF);
    final gold = dark ? const Color(0xFF9B8551) : const Color(0xFFB59A5A);

    final outer = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final band = (size.width * 0.055).clamp(18.0, 34.0);
    final paints = <(double, Color, double)>[
      (0, gold, 1.2),
      (band * 0.22, pale, 2.0),
      (band * 0.46, green, 1.4),
      (band * 0.70, gold, 0.9),
    ];
    for (final (inset, color, width) in paints) {
      canvas.drawRect(
        outer.deflate(inset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color,
      );
    }

    final motifInset = band * 0.22;
    _paintEdgePattern(canvas, size, inset: motifInset, step: 24, color: pale);

    final cornerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = gold;
    for (final corner in [
      Offset(band * 0.55, band * 0.55),
      Offset(size.width - band * 0.55, band * 0.55),
      Offset(band * 0.55, size.height - band * 0.55),
      Offset(size.width - band * 0.55, size.height - band * 0.55),
    ]) {
      canvas.drawCircle(corner, 3.2, cornerPaint);
      canvas.drawCircle(
        corner,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = green,
      );
    }
  }

  void _paintEdgePattern(
    Canvas canvas,
    Size size, {
    required double inset,
    required double step,
    required Color color,
  }) {
    void horizontal(double y, bool flip) {
      for (double x = inset + step / 2; x < size.width - inset; x += step) {
        _motif(canvas, Offset(x, y), step * 0.42, flip ? math.pi : 0, color);
      }
    }

    void vertical(double x, bool flip) {
      for (double y = inset + step / 2; y < size.height - inset; y += step) {
        _motif(
          canvas,
          Offset(x, y),
          step * 0.42,
          flip ? -math.pi / 2 : math.pi / 2,
          color,
        );
      }
    }

    horizontal(inset, false);
    horizontal(size.height - inset, true);
    vertical(inset, false);
    vertical(size.width - inset, true);
  }

  void _motif(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final diamond = Path()
      ..moveTo(0, -radius)
      ..lineTo(radius * 0.62, 0)
      ..lineTo(0, radius)
      ..lineTo(-radius * 0.62, 0)
      ..close();
    canvas.drawPath(diamond, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MushafFramePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.dark != dark;
}

String _arabicDigits(int value) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return value.toString().split('').map((c) => digits[int.parse(c)]).join();
}
