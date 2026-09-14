// ChGPT: cancellable navigation, route-owned previews, no synthetic taps.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

String guideTexte(BuildContext c, String fr, String en, String ar) =>
    switch (Localizations.localeOf(c).languageCode) {
      'ar' => ar,
      'en' => en,
      _ => fr,
    };

enum GesteGuide { appui, balayage, regarder }

class EtapeGuide {
  final GlobalKey? cible;
  final String? cibleId;
  final String titre, texte, chapitre;
  final GesteGuide geste;
  final Future<void> Function()? action;
  final WidgetBuilder? apercu;
  final String? ecranId;
  final Alignment depart, arrivee;
  final double rayon, marge;
  final Duration pause;
  const EtapeGuide({
    required this.titre,
    required this.texte,
    this.chapitre = '',
    this.cible,
    this.cibleId,
    this.apercu,
    this.ecranId,
    this.geste = GesteGuide.regarder,
    this.action,
    this.depart = Alignment.bottomCenter,
    this.arrivee = Alignment.topCenter,
    this.rayon = 8,
    this.marge = 6,
    this.pause = const Duration(seconds: 6),
  });
}

class GuideCible extends StatelessWidget {
  final String id;
  final Widget child;
  const GuideCible(this.id, {super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

class VisiteGuidee extends StatefulWidget {
  final List<EtapeGuide> etapes;
  final VoidCallback onTermine;
  final String libellePasser, libelleSuivant, libelleFin;
  final int indexInitial;
  final ValueChanged<int>? onIndex;
  final GlobalKey? scope;
  final ValueChanged<EtapeGuide>? onApercu;
  const VisiteGuidee({
    super.key,
    required this.etapes,
    required this.onTermine,
    required this.libellePasser,
    required this.libelleSuivant,
    required this.libelleFin,
    this.indexInitial = 0,
    this.onIndex,
    this.scope,
    this.onApercu,
  });
  @override
  State<VisiteGuidee> createState() => _VisiteGuideeState();
}

class _VisiteGuideeState extends State<VisiteGuidee>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late int _index = widget.indexInitial.clamp(
    0,
    math.max(0, widget.etapes.length - 1),
  );
  int _generation = 0;
  bool _fini = false,
      _auto = false,
      _occupe = false,
      _erreur = false,
      _absent = false,
      _menu = false;
  bool _appui = false;
  Rect? _zone;
  Offset _de = Offset.zero, _vers = Offset.zero;
  Timer? _timer;
  ScrollPosition? _defilement;
  final _calque = GlobalKey();
  late final _mouvement = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _valide(int g) => mounted && !_fini && g == _generation;
  bool get _reduit => MediaQuery.disableAnimationsOf(context);
  String _tr(String fr, String en, String ar) =>
      guideTexte(context, fr, en, ar);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jouer(_index);
    });
  }

  @override
  void dispose() {
    _fini = true;
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _mouvement.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _annuler();
      if (mounted) {
        setState(() {
          _auto = false;
          _occupe = false;
        });
      }
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_fini && !_menu) _jouer(_index);
    });
  }

  void _annuler() {
    _generation++;
    _timer?.cancel();
    _mouvement.stop();
    final p = _defilement;
    _defilement = null;
    if (p != null && p.hasPixels) {
      try {
        p.jumpTo(p.pixels);
      } catch (_) {
        /* The preview may already be gone. */
      }
    }
  }

  Element? _chercher(String id) {
    final root = widget.scope?.currentContext;
    if (root is! Element) return null;
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if ((w is GuideCible && w.id == id) || w.key == ValueKey('guide.$id')) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  ScrollableState? _scroll() {
    final root = widget.scope?.currentContext;
    if (root is! Element) return null;
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (axisDirectionToAxis(s.axisDirection) == Axis.vertical &&
            s.position.hasContentDimensions) {
          found = s;
          return;
        }
      }
      e.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  Future<void> _frame() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<BuildContext?> _reveler(EtapeGuide e, int g) async {
    BuildContext? target() =>
        e.cibleId == null ? e.cible?.currentContext : _chercher(e.cibleId!);
    var c = target();
    // Local data/font loading may outlast the first two frames.
    if (c == null && e.cibleId != null && _scroll() == null) {
      for (var i = 0; i < 50 && _valide(g) && c == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!_valide(g)) return null;
        c = target();
        if (_scroll() != null) break;
      }
    }
    // Bounded scanning discovers children of lazy lists without fixed coordinates.
    if (c == null && e.cibleId != null) {
      final scroll = _scroll();
      if (scroll != null) {
        _defilement = scroll.position;
        scroll.position.jumpTo(scroll.position.minScrollExtent);
        await _frame();
        for (var i = 0; i < 24 && _valide(g) && scroll.mounted; i++) {
          c = target();
          if (c != null) break;
          final p = scroll.position;
          if (p.pixels >= p.maxScrollExtent) break;
          await p.animateTo(
            math.min(p.maxScrollExtent, p.pixels + p.viewportDimension * .65),
            duration: Duration(milliseconds: _reduit ? 1 : 140),
            curve: Curves.easeOut,
          );
          await _frame();
        }
      }
    }
    if (!_valide(g)) return null;
    if (c != null && c.mounted) {
      final scroll = Scrollable.maybeOf(c);
      if (scroll != null) _defilement = scroll.position;
      await Scrollable.ensureVisible(
        c,
        alignment: .18,
        duration: Duration(milliseconds: _reduit ? 0 : 450),
        curve: Curves.easeInOut,
      );
      await _frame();
    }
    if (_valide(g)) _defilement = null;
    return c;
  }

  Rect? _mesurer(BuildContext? c) {
    if (c == null || !c.mounted) return null;
    final r = c.findRenderObject(),
        local = _calque.currentContext?.findRenderObject();
    if (r is! RenderBox ||
        !r.hasSize ||
        local is! RenderBox ||
        !local.hasSize) {
      return null;
    }
    final p = local.globalToLocal(r.localToGlobal(Offset.zero));
    final rect = (p & r.size)
        .inflate(widget.etapes[_index].marge)
        .intersect(Offset.zero & local.size);
    return rect.isEmpty ? null : rect;
  }

  Future<void> _jouer(int index) async {
    if (_fini || widget.etapes.isEmpty) return;
    _annuler();
    final g = _generation;
    setState(() {
      _index = index;
      _occupe = true;
      _erreur = false;
      _absent = false;
      _zone = null;
      _appui = false;
    });
    widget.onIndex?.call(index);
    final e = widget.etapes[index];
    try {
      widget.onApercu?.call(e);
      await e.action?.call();
      if (!_valide(g)) return;
      await _frame();
      await _frame();
      if (!_valide(g)) return;
      final target = await _reveler(e, g);
      if (!_valide(g)) return;
      if (target != null && !target.mounted) return;
      final zone = _mesurer(target);
      setState(() {
        _zone = zone;
        _absent = (e.cibleId != null || e.cible != null) && zone == null;
        if (zone != null) {
          _de = _vers == Offset.zero
              ? Offset(zone.center.dx, MediaQuery.sizeOf(context).height)
              : _vers;
          _vers = zone.center;
        }
      });
      if (zone != null && !_reduit) {
        await _mouvement.forward(from: 0).orCancel;
        if (!_valide(g)) return;
        if (e.geste == GesteGuide.balayage) {
          setState(() {
            _de = e.depart.withinRect(zone);
            _vers = e.arrivee.withinRect(zone);
          });
          await _mouvement.forward(from: 0).orCancel;
        } else if (e.geste == GesteGuide.appui) {
          setState(() {
            _de = _vers;
            _appui = true;
          });
          await _mouvement.forward(from: 0).orCancel;
        }
      }
      if (!_valide(g)) return;
      setState(() => _occupe = false);
      _programmer();
    } on TickerCanceled {
      // New step/pause/disposal now owns the screen.
    } catch (_) {
      if (_valide(g)) {
        setState(() {
          _erreur = true;
          _occupe = false;
          _auto = false;
        });
      }
    }
  }

  void _programmer() {
    _timer?.cancel();
    if (!_auto || _occupe || _menu || _erreur || _absent) return;
    final g = _generation, e = widget.etapes[_index];
    final ms = math
        .max(e.pause.inMilliseconds, e.texte.runes.length * 45)
        .clamp(5000, 20000);
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!_valide(g) || !_auto) return;
      if (_index + 1 == widget.etapes.length) {
        setState(() => _auto = false);
      } else {
        _jouer(_index + 1);
      }
    });
  }

  void _terminer() {
    if (_fini) return;
    _annuler();
    _fini = true;
    widget.onTermine();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.etapes.isEmpty) return const SizedBox.shrink();
    final e = widget.etapes[_index];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _terminer();
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final low = _zone != null && _zone!.center.dy > h * .6;
          return Stack(
            key: _calque,
            fit: StackFit.expand,
            children: [
              const ModalBarrier(dismissible: false, color: Colors.transparent),
              IgnorePointer(child: CustomPaint(painter: _Voile(_zone))),
              if (_zone != null && !_reduit && !_menu)
                AnimatedBuilder(
                  animation: _mouvement,
                  builder: (context, _) {
                    final p = Offset.lerp(
                      _de,
                      _vers,
                      Curves.easeInOutCubic.transform(_mouvement.value),
                    )!;
                    return Positioned(
                      left: (p.dx - 18).clamp(
                        0.0,
                        math.max(0.0, c.maxWidth - 50),
                      ),
                      top: (p.dy + 2).clamp(0.0, math.max(0.0, h - 58)),
                      child: Transform.scale(
                        scale: _appui
                            ? 1 - .14 * math.sin(_mouvement.value * math.pi)
                            : 1,
                        alignment: Alignment.topCenter,
                        child: const IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              '👆',
                              style: TextStyle(
                                fontSize: 40,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Positioned(
                left: 12,
                right: 12,
                top: low ? MediaQuery.paddingOf(context).top + 12 : null,
                bottom: low ? null : MediaQuery.paddingOf(context).bottom + 12,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: h * .48),
                  child: _panneau(e),
                ),
              ),
              if (_menu)
                Positioned.fill(
                  child: SafeArea(
                    child: Material(
                      color: AppColors.cream,
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(
                              _tr(
                                'Étapes du parcours',
                                'Tour steps',
                                'خطوات الجولة',
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() => _menu = false);
                                _programmer();
                              },
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: widget.etapes.length,
                              itemBuilder: (context, i) => ListTile(
                                selected: i == _index,
                                leading: Text('${i + 1}'),
                                title: Text(widget.etapes[i].titre),
                                subtitle: Text(widget.etapes[i].chapitre),
                                trailing: i == _index
                                    ? const Icon(Icons.play_arrow)
                                    : null,
                                onTap: () {
                                  setState(() => _menu = false);
                                  _jouer(i);
                                },
                              ),
                            ),
                          ),
                        ],
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

  Widget _panneau(EtapeGuide e) => Material(
    color: const Color(0xFFFCFDFC),
    elevation: 8,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: DefaultTextStyle(
      style: GoogleFonts.manrope(
        fontSize: 13,
        color: AppColors.ink,
        height: 1.45,
        letterSpacing: 0,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_index + 1) / widget.etapes.length,
              minHeight: 3,
              color: AppColors.green700,
              backgroundColor: const Color(0xFFE4ECE8),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.chapitre.isEmpty
                          ? _tr('Découverte', 'Discover', 'اكتشاف')
                          : e.chapitre,
                      style: const TextStyle(
                        color: AppColors.green700,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_index + 1} / ${widget.etapes.length}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.titre,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(e.texte),
                    if (_erreur || _absent)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _erreur
                              ? _tr(
                                  'Impossible d’ouvrir cette étape. Réessaie ou passe à la suivante.',
                                  'Cannot open this step. Retry or continue.',
                                  'تعذر فتح الخطوة. أعد المحاولة أو تابع.',
                                )
                              : _tr(
                                  'Cette zone n’est pas disponible dans cet état de l’écran.',
                                  'This area is unavailable in the current screen state.',
                                  'هذه المنطقة غير متاحة في حالة الشاشة الحالية.',
                                ),
                          style: const TextStyle(
                            color: Color(0xFF9C4B22),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: _tr('Sommaire', 'Contents', 'الفهرس'),
                    icon: const Icon(Icons.list_alt),
                    onPressed: () {
                      _annuler();
                      setState(() {
                        _menu = true;
                        _occupe = false;
                      });
                    },
                  ),
                  IconButton(
                    tooltip: _tr('Précédent', 'Previous', 'السابق'),
                    icon: const BackButtonIcon(),
                    onPressed: _index == 0 ? null : () => _jouer(_index - 1),
                  ),
                  IconButton(
                    tooltip: _auto
                        ? _tr('Pause', 'Pause', 'إيقاف مؤقت')
                        : _tr(
                            'Lecture automatique',
                            'Autoplay',
                            'تشغيل تلقائي',
                          ),
                    icon: Icon(_auto ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      setState(() => _auto = !_auto);
                      if (_auto) {
                        _jouer(_index);
                      } else {
                        _annuler();
                        setState(() => _occupe = false);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: _tr(
                      'Rejouer cette étape',
                      'Replay step',
                      'إعادة الخطوة',
                    ),
                    icon: const Icon(Icons.replay),
                    onPressed: () => _jouer(_index),
                  ),
                  IconButton(
                    tooltip: _index + 1 == widget.etapes.length
                        ? widget.libelleFin
                        : widget.libelleSuivant,
                    icon: Icon(
                      _index + 1 == widget.etapes.length
                          ? Icons.check
                          : (Directionality.of(context) == TextDirection.rtl
                                ? Icons.arrow_back
                                : Icons.arrow_forward),
                    ),
                    onPressed: () => _index + 1 == widget.etapes.length
                        ? _terminer()
                        : _jouer(_index + 1),
                  ),
                  IconButton(
                    tooltip: widget.libellePasser,
                    icon: const Icon(Icons.close),
                    onPressed: _terminer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Voile extends CustomPainter {
  final Rect? zone;
  const _Voile(this.zone);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (zone != null) {
      path.addRRect(RRect.fromRectAndRadius(zone!, const Radius.circular(8)));
    }
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(145));
    if (zone != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone!, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.brassLight,
      );
    }
  }

  @override
  bool shouldRepaint(_Voile old) => old.zone != zone;
}

/// One owned route instead of a global overlay that can outlive its screen.
class GuideHote {
  static bool _actif = false;
  static bool get enCours => _actif;
  static Future<void> lancer(
    BuildContext context, {
    required List<EtapeGuide> etapes,
    required String libellePasser,
    required String libelleSuivant,
    required String libelleFin,
    int indexInitial = 0,
    ValueChanged<int>? onIndex,
    VoidCallback? auRetour,
  }) async {
    if (_actif || etapes.isEmpty || !context.mounted) return;
    _actif = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => _GuideParcours(
            etapes: etapes,
            passer: libellePasser,
            suivant: libelleSuivant,
            fin: libelleFin,
            indexInitial: indexInitial,
            onIndex: onIndex,
          ),
        ),
      );
    } finally {
      _actif = false;
      auRetour?.call();
    }
  }
}

class _GuideParcours extends StatefulWidget {
  final List<EtapeGuide> etapes;
  final String passer, suivant, fin;
  final int indexInitial;
  final ValueChanged<int>? onIndex;
  const _GuideParcours({
    required this.etapes,
    required this.passer,
    required this.suivant,
    required this.fin,
    required this.indexInitial,
    this.onIndex,
  });
  @override
  State<_GuideParcours> createState() => _GuideParcoursState();
}

class _GuideParcoursState extends State<_GuideParcours> {
  final _scope = GlobalKey();
  EtapeGuide? _etape;
  bool _quitter = false;
  void _terminer() {
    setState(() => _quitter = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.cream,
    body: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: AbsorbPointer(
            child: KeyedSubtree(
              key: _scope,
              child: KeyedSubtree(
                key: ValueKey(_etape?.ecranId),
                child: _etape?.apercu?.call(context) ?? const SizedBox.expand(),
              ),
            ),
          ),
        ),
        if (!_quitter)
          VisiteGuidee(
            etapes: widget.etapes,
            indexInitial: widget.indexInitial,
            scope: _scope,
            onIndex: widget.onIndex,
            onApercu: (e) => setState(() => _etape = e),
            onTermine: _terminer,
            libellePasser: widget.passer,
            libelleSuivant: widget.suivant,
            libelleFin: widget.fin,
          ),
      ],
    ),
  );
}
