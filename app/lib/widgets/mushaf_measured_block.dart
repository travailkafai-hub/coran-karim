import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_log.dart';
import '../services/mushaf_layout_scheduler.dart';

typedef MushafPageLayout = ({
  double taille,
  double interligne,
  List<double> hauteurs,
});
typedef MushafParagraphMeasure = Future<double> Function(double Function());

/// ChGPT: only completed layouts are cached. An obsolete calculation can
/// neither populate this cache nor publish its result into another page.
class MushafMeasuredBlock extends StatefulWidget {
  final String requestKey;
  final int page;
  final bool foreground;
  final Future<MushafPageLayout> Function(MushafParagraphMeasure) calculate;
  final Widget Function(MushafPageLayout) builder;

  const MushafMeasuredBlock({
    super.key,
    required this.requestKey,
    required this.page,
    required this.foreground,
    required this.calculate,
    required this.builder,
  });

  @override
  State<MushafMeasuredBlock> createState() => _MushafMeasuredBlockState();
}

class _MushafMeasuredBlockState extends State<MushafMeasuredBlock>
    with WidgetsBindingObserver {
  static final _cache = <String, MushafPageLayout>{};
  static const _maxEntries = 200;
  MushafPageLayout? _layout;
  bool _running = false;
  bool _failed = false;
  bool _visibleRoute = false;
  bool _resumed = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibleRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant MushafMeasuredBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestKey != oldWidget.requestKey) {
      _cancel();
      _layout = null;
      _failed = false;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _resumed = state == AppLifecycleState.resumed;
      _sync();
    });
  }

  void _cancel() {
    _generation++;
    _running = false;
  }

  void _sync() {
    if (!_visibleRoute || !_resumed) {
      _cancel();
      return;
    }
    _layout ??= _cache[widget.requestKey];
    if (_layout == null && !_running && !_failed) _calculate();
  }

  Future<void> _calculate() async {
    _running = true;
    final generation = ++_generation;
    final key = widget.requestKey;
    final page = widget.page;
    final calculate = widget.calculate;
    final wall = Stopwatch()..start();
    var cpuMicros = 0;
    var longestMicros = 0;
    var paragraphs = 0;
    bool current() =>
        mounted && generation == _generation && _visibleRoute && _resumed;
    try {
      final layout = await calculate(
        (work) => MushafLayoutScheduler.instance.measure(
          () {
            final timer = Stopwatch()..start();
            try {
              return work();
            } finally {
              timer.stop();
              cpuMicros += timer.elapsedMicroseconds;
              if (timer.elapsedMicroseconds > longestMicros) {
                longestMicros = timer.elapsedMicroseconds;
              }
              paragraphs++;
            }
          },
          isCurrent: current,
          isForeground: () => widget.foreground,
        ),
      );
      if (!current()) return;
      final frozen = (
        taille: layout.taille,
        interligne: layout.interligne,
        hauteurs: List<double>.unmodifiable(layout.hauteurs),
      );
      _cache[key] = frozen;
      if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
      setState(() {
        _layout = frozen;
        _running = false;
      });
      DiagnosticLog.log(
        'Perf',
        'ChGPT page=$page mesure cooperative '
            'attente=${wall.elapsedMilliseconds}ms calcul=${cpuMicros / 1000}ms '
            'trancheMax=${longestMicros / 1000}ms paragraphes=$paragraphs '
            'premierPlan=${widget.foreground} cache=${_cache.length}',
      );
    } on MushafLayoutCancelled {
      // Expected when leaving, rotating, or changing the writing/riwaya.
    } catch (error) {
      if (!current()) return;
      setState(() {
        _failed = true;
        _running = false;
      });
      DiagnosticLog.log('Perf', 'ChGPT mesure page=$page impossible : $error');
    }
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    if (layout != null) return widget.builder(layout);
    if (_failed) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: Text(AppLocalizations.of(context)!.commonRetry),
          onPressed: () => setState(() {
            _failed = false;
            _sync();
          }),
        ),
      );
    }
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
