import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MushafFrameTone { light, sepia, dark }

/// ChGPT: a paint-only border, shared by paper and scrolling readers.
/// The empty center never paints over text or changes its layout.
class MushafOrnamentalFramePainter extends CustomPainter {
  final MushafFrameTone tone;
  final EdgeInsets band;
  final bool opening;

  const MushafOrnamentalFramePainter({
    required this.tone,
    this.band = const EdgeInsets.all(8),
    this.opening = false,
  });

  static (Color, Color, Color) colorsFor(MushafFrameTone tone) =>
      switch (tone) {
        MushafFrameTone.light => (
          const Color(0xFF174C3A),
          const Color(0xFFBCA064),
          const Color(0xFFE1D3A5),
        ),
        MushafFrameTone.sepia => (
          const Color(0xFF5A6046),
          const Color(0xFFB39C6B),
          const Color(0xFFD7C69E),
        ),
        MushafFrameTone.dark => (
          const Color(0xFF162A23),
          const Color(0xFF9F8A55),
          const Color(0xFFC1AE7A),
        ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) return;
    final (ground, gold, detail) = colorsFor(tone);
    final outer = Offset.zero & size;
    final left = band.left.clamp(1.5, size.width / 4).toDouble();
    final right = band.right.clamp(1.5, size.width / 4).toDouble();
    final top = band.top.clamp(1.5, size.height / 4).toDouble();
    final bottom = band.bottom.clamp(1.5, size.height / 4).toDouble();
    final inner = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRect(inner);
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawPath(ring, Paint()..color = ground);
    final rule = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRect(outer.deflate(0.5), rule);
    canvas.drawRect(inner.inflate(0.5), rule);

    // Each frieze uses its own depth: narrow top margins stay narrow.
    _edge(
      canvas,
      Offset(left, 0),
      0,
      size.width - left - right,
      top,
      gold,
      detail,
    );
    _edge(
      canvas,
      Offset(size.width, top),
      math.pi / 2,
      size.height - top - bottom,
      right,
      gold,
      detail,
    );
    _edge(
      canvas,
      Offset(size.width - right, size.height),
      math.pi,
      size.width - left - right,
      bottom,
      gold,
      detail,
    );
    _edge(
      canvas,
      Offset(0, size.height - bottom),
      -math.pi / 2,
      size.height - top - bottom,
      left,
      gold,
      detail,
    );

    for (final corner in <(Offset, double, double, double)>[
      (Offset.zero, 0, left, top),
      (Offset(size.width, 0), math.pi / 2, top, right),
      (Offset(size.width, size.height), math.pi, right, bottom),
      (Offset(0, size.height), -math.pi / 2, bottom, left),
    ]) {
      canvas.save();
      canvas.translate(corner.$1.dx, corner.$1.dy);
      canvas.rotate(corner.$2);
      canvas.translate(corner.$3 / 2, corner.$4 / 2);
      final radius = math.min(corner.$3, corner.$4) * 0.32;
      final petals = Path();
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2;
        final tip = Offset(math.cos(angle), math.sin(angle)) * radius;
        final side = Offset(-math.sin(angle), math.cos(angle)) * radius * 0.48;
        petals.moveTo(0, 0);
        petals.quadraticBezierTo(
          tip.dx + side.dx,
          tip.dy + side.dy,
          tip.dx,
          tip.dy,
        );
        petals.quadraticBezierTo(tip.dx - side.dx, tip.dy - side.dy, 0, 0);
      }
      canvas.drawPath(petals, Paint()..color = gold);
      canvas.drawCircle(Offset.zero, radius * 0.18, Paint()..color = detail);
      canvas.restore();
    }
    canvas.restore();
  }

  void _edge(
    Canvas canvas,
    Offset origin,
    double angle,
    double length,
    double depth,
    Color gold,
    Color detail,
  ) {
    if (length <= 0 || depth < 3) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    final count = math.max(1, (length / (opening ? 25 : 18)).round());
    final step = length / count;
    final stroke = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = opening ? 0.75 : 0.55;
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate((i + 0.5) * step, depth / 2);
      final w = step * 0.44;
      final h = (depth - 2) * 0.38;
      final stem = Path()
        ..moveTo(-w, 0)
        ..cubicTo(-w * 0.5, -h, -w * 0.25, h, 0, 0)
        ..cubicTo(w * 0.25, -h, w * 0.5, h, w, 0);
      canvas.drawPath(stem, stroke);
      for (final sign in [-1.0, 1.0]) {
        final leaf = Path()
          ..moveTo(0, 0)
          ..cubicTo(
            -w * 0.48,
            sign * h * 0.3,
            -w * 0.28,
            sign * h * 0.9,
            0,
            sign * h,
          )
          ..cubicTo(w * 0.28, sign * h * 0.9, w * 0.48, sign * h * 0.3, 0, 0);
        canvas.drawPath(leaf, stroke);
      }
      canvas.drawCircle(
        Offset.zero,
        opening ? 0.9 : 0.6,
        Paint()..color = detail,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MushafOrnamentalFramePainter oldDelegate) =>
      oldDelegate.tone != tone ||
      oldDelegate.band != band ||
      oldDelegate.opening != opening;
}
