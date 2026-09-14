import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';

class MushafLayoutCancelled implements Exception {
  const MushafLayoutCancelled();
}

/// ChGPT: at most one paragraph measurement after each frame, across all pages.
/// TextPainter stays on the UI isolate; a Future alone would not prevent jank.
class MushafLayoutScheduler {
  MushafLayoutScheduler._();
  static final instance = MushafLayoutScheduler._();

  final _pending = Queue<_Measurement>();
  bool _scheduled = false;

  Future<double> measure(
    double Function() calculate, {
    required bool Function() isCurrent,
    required bool Function() isForeground,
  }) {
    final work = _Measurement(calculate, isCurrent, isForeground);
    _pending.add(work);
    _schedule();
    return work.result.future;
  }

  void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      // Remove obsolete work before choosing a visible page over prefetch.
      for (final work in _pending.toList()) {
        if (!work.isCurrent()) {
          _pending.remove(work);
          work.result.completeError(const MushafLayoutCancelled());
        }
      }
      if (_pending.isEmpty) return;
      final work = _pending.firstWhere(
        (entry) => entry.isForeground(),
        orElse: () => _pending.first,
      );
      _pending.remove(work);
      try {
        work.result.complete(work.calculate());
      } catch (error, stack) {
        work.result.completeError(error, stack);
      }
      _schedule();
    });
    // Unlike scheduleFrame during postFrameCallbacks, this also guarantees
    // a following frame after the current frame's scheduling flag is reset.
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

class _Measurement {
  final double Function() calculate;
  final bool Function() isCurrent;
  final bool Function() isForeground;
  final result = Completer<double>();
  _Measurement(this.calculate, this.isCurrent, this.isForeground);
}
