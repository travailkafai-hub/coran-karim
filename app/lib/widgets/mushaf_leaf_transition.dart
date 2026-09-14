import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// ChGPT: these paper editions open on the pair 1 (right), 2 (left).
/// Page numbers, not gesture counts, keep jumps and backward reading aligned.
bool mushafTurnsLeafAfter(int paperPage) => paperPage > 0 && paperPage.isEven;

Duration mushafPageAdvanceDuration(
  int paperPage, {
  bool reduceMotion = false,
}) => reduceMotion
    ? Duration.zero
    : Duration(milliseconds: mushafTurnsLeafAfter(paperPage) ? 720 : 340);

/// Paint-only fold over the existing lazy PageView. No bitmap pages, mirrored
/// Quran text, repeated text layouts, or screen-wide opacity animation.
/// The owning PageView must advance physically left to right (AxisDirection.left).
class MushafLeafTransition extends SingleChildRenderObjectWidget {
  final PageController controller;
  final int index;
  final Color paperColor;
  final ValueListenable<double> foldOrigin;
  final bool reduceMotion;

  const MushafLeafTransition({
    super.key,
    required this.controller,
    required this.index,
    required this.paperColor,
    required this.foldOrigin,
    required this.reduceMotion,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeaf(controller, index, paperColor, foldOrigin, reduceMotion);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderLeaf).configure(
      controller,
      index,
      paperColor,
      foldOrigin,
      reduceMotion,
    );
  }
}

class _RenderLeaf extends RenderProxyBox {
  _RenderLeaf(
    this._controller,
    this._index,
    this._paper,
    this._origin,
    this._reduce,
  );

  PageController _controller;
  int _index;
  Color _paper;
  ValueListenable<double> _origin;
  bool _reduce;
  final _clip = LayerHandle<ClipPathLayer>();

  void configure(
    PageController controller,
    int index,
    Color paper,
    ValueListenable<double> origin,
    bool reduce,
  ) {
    if (attached) _unlisten();
    _controller = controller;
    _index = index;
    _paper = paper;
    _origin = origin;
    _reduce = reduce;
    if (attached) _listen();
    markNeedsPaint();
  }

  void _listen() {
    _controller.addListener(markNeedsPaint);
    _origin.addListener(markNeedsPaint);
  }

  void _unlisten() {
    _controller.removeListener(markNeedsPaint);
    _origin.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_reduce ||
        !_controller.hasClients ||
        !_controller.position.haveDimensions ||
        size.isEmpty) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    final page = _controller.page ?? _index.toDouble();
    final lower = page.floor();
    final progress = page - lower;
    if (progress < 0.00001 ||
        progress > 0.99999 ||
        !mushafTurnsLeafAfter(lower + 1)) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    if (_index != lower && _index != lower + 1) return;

    // The physical axis, never the UI locale, determines the compensation.
    // Reading right -> left and turning a leaf left -> right are distinct.
    assert(_controller.position.axisDirection == AxisDirection.left);
    final stationary = offset - Offset((page - _index) * size.width, 0);
    final fold = _Fold(size, progress, _origin.value);
    final lifted = _index == lower;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      stationary,
      Offset.zero & size,
      lifted ? fold.front : fold.revealed,
      (context, offset) => super.paint(context, offset),
      clipBehavior: Clip.antiAlias,
      oldLayer: _clip.layer,
    );

    // Both masks share the same curved edges: neither page covers the other
    // by accident when the sliver reverses its paint order during a return.
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(stationary.dx, stationary.dy);
    canvas.clipRect(Offset.zero & size);
    if (lifted) {
      final rect = Rect.fromLTRB(
        fold.x - fold.width,
        0,
        fold.x + fold.width,
        size.height,
      );
      canvas.drawPath(
        fold.back,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(_paper, const Color(0xFF000000), 0.17)!,
              Color.lerp(_paper, const Color(0xFFFFFFFF), 0.20)!,
              _paper,
              Color.lerp(_paper, const Color(0xFF000000), 0.09)!,
            ],
            stops: const [0, 0.28, 0.62, 1],
          ).createShader(rect),
      );
      canvas.drawPath(
        fold.frontEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..color = const Color(0xFF000000).withValues(alpha: 0.14 * fold.lift),
      );
    } else {
      canvas.clipPath(fold.revealed);
      canvas.drawPath(
        fold.backEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16 * fold.lift
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..color = const Color(0xFF000000).withValues(alpha: 0.20 * fold.lift),
      );
    }
    canvas.restore();
  }
}

/// Two cubic edges enclose a rolling paper back. The front stays typeset and
/// unmoved; only the exposed area changes. Endpoints are exactly flat pages.
class _Fold {
  final Size size;
  final double progress;
  final double origin;
  _Fold(this.size, this.progress, this.origin);

  double get lift => math.sin(math.pi * progress);
  double get x => size.width * progress;
  double get width => math.min(84.0, size.width * 0.22) * lift;
  double get tilt => (origin.clamp(0.0, 1.0) - 0.5) * size.width * 0.30 * lift;
  double get bow => size.width * 0.075 * lift;

  double _top(double shift) => x + tilt + shift;
  double _bottom(double shift) => x - tilt + shift;

  void _down(Path path, double shift) => path.cubicTo(
    _top(shift) - bow,
    size.height * 0.32,
    _bottom(shift) - bow,
    size.height * 0.68,
    _bottom(shift),
    size.height,
  );

  Path _edge(double shift) {
    final path = Path()..moveTo(_top(shift), 0);
    _down(path, shift);
    return path;
  }

  Path get frontEdge => _edge(width / 2);
  Path get backEdge => _edge(-width / 2);

  Path get front => frontEdge
    ..lineTo(size.width, size.height)
    ..lineTo(size.width, 0)
    ..close();

  Path get revealed => backEdge
    ..lineTo(0, size.height)
    ..lineTo(0, 0)
    ..close();

  Path get back {
    final path = backEdge..lineTo(_bottom(width / 2), size.height);
    path.cubicTo(
      _bottom(width / 2) - bow,
      size.height * 0.68,
      _top(width / 2) - bow,
      size.height * 0.32,
      _top(width / 2),
      0,
    );
    return path..close();
  }
}
