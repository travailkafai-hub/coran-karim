import 'package:coran_karim/widgets/mushaf_cover_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReaderProbe extends StatefulWidget {
  final VoidCallback onInit;
  final VoidCallback onTap;
  const _ReaderProbe({required this.onInit, required this.onTap});
  @override
  State<_ReaderProbe> createState() => _ReaderProbeState();
}

class _ReaderProbeState extends State<_ReaderProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    child: const ColoredBox(
      color: Colors.white,
      child: Center(child: Text('Page')),
    ),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('Approved artwork has no duplicate title and fills the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MushafClosedCover()));
    await tester.pumpAndSettle();
    final artwork = tester.widget<Image>(find.byType(Image));
    expect((artwork.image as AssetImage).assetName, mushafCoverAsset);
    expect(artwork.fit, BoxFit.fill);
    expect(find.byType(Text), findsNothing);
    expect(mushafCoverColor, const Color(0xFF0C3B2C));
    expect(tester.takeException(), isNull);
  });

  Widget app({
    required bool ready,
    bool reducedMotion = false,
    Widget? reader,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MushafCoverReveal(
        ready: ready,
        child: reader ?? const ColoredBox(color: Colors.white),
      ),
    ),
  );

  testWidgets('Cover stays closed until actual reader is ready', (
    tester,
  ) async {
    await tester.pumpWidget(app(ready: false));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MushafClosedCover), findsOneWidget);
    await tester.pumpWidget(app(ready: true));
    await tester.pumpAndSettle();
    expect(find.byType(MushafClosedCover), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Opening rotates right-hinged cover and never remounts reader', (
    tester,
  ) async {
    var mounts = 0;
    var taps = 0;
    final reader = _ReaderProbe(onInit: () => mounts++, onTap: () => taps++);
    await tester.pumpWidget(app(ready: true, reader: reader));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    final transform = tester.widget<Transform>(find.byType(Transform).first);
    expect(transform.alignment, Alignment.centerRight);
    expect(transform.transform.entry(0, 0), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(find.byType(MushafClosedCover), findsNothing);
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    await tester.pumpWidget(app(ready: true, reader: reader));
    expect(mounts, 1);
    expect(find.byType(MushafClosedCover), findsNothing);
  });

  testWidgets('Skipping never sends the same tap to the page underneath', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        ready: true,
        reader: _ReaderProbe(onInit: () {}, onTap: () => taps++),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(find.byType(MushafClosedCover), findsNothing);
    expect(taps, 0);
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
  });

  testWidgets('An early skip waits for data then reveals without animation', (
    tester,
  ) async {
    await tester.pumpWidget(app(ready: false));
    await tester.tapAt(const Offset(100, 100));
    expect(find.byType(MushafClosedCover), findsOneWidget);
    await tester.pumpWidget(app(ready: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MushafClosedCover), findsNothing);
  });

  testWidgets('System reduced motion goes directly to reading', (tester) async {
    await tester.pumpWidget(app(ready: true, reducedMotion: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MushafClosedCover), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('Leaving during preparation or animation is safe', (
    tester,
  ) async {
    await tester.pumpWidget(app(ready: false));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(ready: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(800, 1280),
    const Size(844, 390),
  ]) {
    testWidgets('Cover fits $size at 200 percent text scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: MushafClosedCover(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(MushafClosedCover)), size);
    });
  }
}
