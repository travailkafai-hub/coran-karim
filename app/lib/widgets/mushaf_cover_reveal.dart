import 'dart:math' as math;

import 'package:flutter/material.dart';

const mushafCoverColor = Color(0xFF0C3B2C);
const mushafCoverAsset = 'assets/illumination/mushaf_cover.webp';

/// A static, local cover also serves as the first Flutter frame.
class MushafClosedCover extends StatelessWidget {
  const MushafClosedCover({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: mushafCoverColor,
    child: SizedBox.expand(
      // ChGPT: the approved artwork already includes the Arabic calligraphy.
      // Contain preserves the medallion and the complete ornamental frame.
      child: Semantics(
        label:
            '\u0627\u0644\u0642\u0631\u0622\u0646 \u0627\u0644\u0643\u0631\u064a\u0645',
        image: true,
        child: Image.asset(
          mushafCoverAsset,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

/// ChGPT: only the cover animates; the real reader keeps its own layout.
class MushafCoverReveal extends StatefulWidget {
  final bool ready;
  final Widget child;

  const MushafCoverReveal({
    super.key,
    required this.ready,
    required this.child,
  });

  @override
  State<MushafCoverReveal> createState() => _MushafCoverRevealState();
}

class _MushafCoverRevealState extends State<MushafCoverReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _finished = true);
        }
      });
  bool _scheduled = false;
  bool _finished = false;
  bool _skipRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant MushafCoverReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (!widget.ready || _scheduled || _finished) return;
    _scheduled = true;
    // Allow the immersive reader to settle its insets before revealing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_skipRequested || MediaQuery.disableAnimationsOf(context)) {
          _controller.value = 1;
        } else {
          _controller.forward();
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  void _skip() {
    _skipRequested = true;
    if (widget.ready) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: !_finished,
          child: IgnorePointer(ignoring: !_finished, child: widget.child),
        ),
        if (!_finished)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _controller,
                child: const RepaintBoundary(child: MushafClosedCover()),
                builder: (context, cover) {
                  final turn = const Interval(
                    0.12,
                    1,
                    curve: Curves.easeInOutCubic,
                  ).transform(_controller.value);
                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: 0.16 * (1 - turn),
                            ),
                          ),
                        ),
                        // An Arabic binding hinges on the right, regardless of
                        // the app's UI language. Stop edge-on, no mirrored text.
                        Transform(
                          alignment: Alignment.centerRight,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.00065)
                            ..rotateY(-math.pi / 2 * turn),
                          child: cover,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
