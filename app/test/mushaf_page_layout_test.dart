import 'dart:convert';

import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/models/verse.dart';
import 'package:coran_karim/screens/mushaf_maquette_screen.dart';
import 'package:coran_karim/services/quran_api.dart';
import 'package:coran_karim/widgets/mushaf_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ChGPT: a ClipRect can hide the last verse without a Flutter overflow error.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final font = FontLoader('Bouazzi Maghribi')
      ..addFont(rootBundle.load('fonts/BouazziMaghribi-Regular.ttf'));
    await font.load();
  });

  String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

  Future<void> ouvrir(
    WidgetTester tester,
    int page,
    Riwaya riwaya, {
    Size size = const Size(1080, 2340),
    String font = 'Amiri',
    bool tajwid = true,
    bool dark = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'riwaya': riwaya.name,
      'police_mushaf_page': font,
      'tajwid_mushaf_page': tajwid,
      'mushaf_mode_sombre': dark,
    });
    QuranApi.riwaya = riwaya;
    tester.view.devicePixelRatio = 510 / 160;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await verses(page, riwaya);
      GoogleFonts.amiri(fontWeight: FontWeight.w600);
      GoogleFonts.amiri(fontWeight: FontWeight.w700);
      GoogleFonts.amiri();
      await GoogleFonts.pendingFonts();
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          // Material's inherited tracking must not alter a measured paragraph.
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(letterSpacing: 0.25),
            ),
          ),
          home: MushafMaquetteScreen(pageInitiale: page),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> verifierPage(
    WidgetTester tester,
    int page,
    Riwaya riwaya,
  ) async {
    expect(tester.takeException(), isNull);
    final body = find.byKey(ValueKey('mushaf-body-$page'));
    expect(body, findsOneWidget);
    final bodyRect = tester.getRect(body);
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: body, matching: find.byType(RichText)),
        )
        .toList();
    expect(paragraphs, isNotEmpty);
    final rendered = compact(
      paragraphs.map((p) => p.text.toPlainText()).join(),
    );
    var offset = 0;
    for (final verse in await verses(page, riwaya)) {
      final expected = compact(verse.textUthmani);
      final found = rendered.indexOf(expected, offset);
      expect(
        found,
        greaterThanOrEqualTo(offset),
        reason: 'Page $page ${riwaya.name}: entire ${verse.key} in order',
      );
      offset = found + expected.length;
    }
    for (final paragraph in paragraphs) {
      expect(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        lessThanOrEqualTo(paragraph.size.height + 0.01),
        reason: 'No truncated paragraph on page $page',
      );
      final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
      expect(
        rect.bottom,
        lessThanOrEqualTo(bodyRect.bottom + 0.01),
        reason: 'Text must remain above the footer on page $page',
      );
      expect(rect.top, greaterThanOrEqualTo(bodyRect.top - 0.01));
      RenderObject? ancestor = paragraph.parent;
      while (ancestor != null) {
        if (ancestor is RenderClipRect) {
          final clip = ancestor.localToGlobal(Offset.zero) & ancestor.size;
          expect(
            rect.bottom,
            lessThanOrEqualTo(clip.bottom + 0.01),
            reason: 'Last line hidden by a clip on page $page',
          );
        }
        ancestor = ancestor.parent;
      }
    }
  }

  for (final riwaya in Riwaya.values) {
    for (final page in [1, 2, 3, 77, 106, 562, 573, 574, 586, 590, 604]) {
      testWidgets('paper page $page ${riwaya.name} is entirely visible', (
        tester,
      ) async {
        await ouvrir(tester, page, riwaya);
        await verifierPage(tester, page, riwaya);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
    testWidgets('landscape ${riwaya.name}: complete page after resize', (
      tester,
    ) async {
      await ouvrir(tester, 574, riwaya);
      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pumpAndSettle();
      await verifierPage(tester, 574, riwaya);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    testWidgets('small display ${riwaya.name}: monochrome Maghribi page', (
      tester,
    ) async {
      await ouvrir(
        tester,
        573,
        riwaya,
        size: const Size(960, 1704),
        font: 'Bouazzi Maghribi',
        tajwid: false,
        dark: true,
      );
      await verifierPage(tester, 573, riwaya);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    testWidgets('tap ${riwaya.name} advances exactly one paper page', (
      tester,
    ) async {
      await ouvrir(tester, 573, riwaya);
      await tester.tap(find.byKey(const ValueKey('mushaf-body-573')));
      await tester.pumpAndSettle();
      await verifierPage(tester, 574, riwaya);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  test('all 604 page boundaries use the asset of their riwaya', () async {
    for (final riwaya in Riwaya.values) {
      QuranApi.riwaya = riwaya;
      final asset = riwaya == Riwaya.warsh
          ? 'assets/data/quran_mushaf_warsh.json'
          : 'assets/data/quran_verses.json';
      final source = jsonDecode(await rootBundle.loadString(asset)) as List;
      final pages = <int, List<String>>{};
      for (final item in source.cast<Map<String, dynamic>>()) {
        pages
            .putIfAbsent(item['page_number'] as int, () => [])
            .add(item['text_uthmani'] as String);
      }
      expect(pages.length, 604);
      for (var page = 1; page <= 604; page++) {
        final actual = await verses(page, riwaya);
        expect(
          actual.map((v) => v.textUthmani).toList(),
          pages[page],
          reason: 'Exact page $page ${riwaya.name}, no repagination',
        );
      }
    }
  });

  for (final mode in [SystemUiMode.edgeToEdge, SystemUiMode.immersiveSticky]) {
    testWidgets('paper back restores $mode after repeated visits', (
      tester,
    ) async {
      // Load the real paper assets/fonts before exercising route disposal.
      await ouvrir(tester, 573, Riwaya.hafs);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      int? returnedPage;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returnedPage = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => mode == SystemUiMode.edgeToEdge
                            ? const MushafMaquetteScreen(pageInitiale: 573)
                            : MushafMaquetteScreen(
                                pageInitiale: 573,
                                modeSystemeAuRetour: mode,
                              ),
                      ),
                    );
                  },
                  child: const Text('Open paper'),
                ),
              ),
            ),
          ),
        ),
      );
      for (var visit = 0; visit < 3; visit++) {
        calls.clear();
        await tester.tap(find.text('Open paper'));
        await tester.pumpAndSettle();
        expect(
          calls
              .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
              .last
              .arguments,
          SystemUiMode.immersiveSticky.toString(),
        );
        if (visit == 1) {
          await tester.tap(find.byKey(const ValueKey('mushaf-body-573')));
          await tester.pumpAndSettle();
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(returnedPage, visit == 1 ? 574 : 573);
        expect(find.byType(MushafMaquetteScreen), findsNothing);
        expect(
          calls
              .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
              .last
              .arguments,
          mode.toString(),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('header reserves top inset, never Android navigation inset', (
    tester,
  ) async {
    const header = MushafHeader(
      surah: Surah(
        number: 109,
        nameArabic: 'Test',
        nameSimple: 'Test',
        nameTranslationFr: 'Test',
        versesCount: 6,
        revelationPlace: 'makkah',
      ),
    );
    // Inspect the real header's SafeArea contract without loading its prayer
    // services or downloadable UI fonts. Full rendering is checked on device.
    for (final padding in [
      EdgeInsets.zero,
      const EdgeInsets.only(top: 24, bottom: 48),
      const EdgeInsets.only(bottom: 48),
      const EdgeInsets.only(top: 48),
    ]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(padding: padding),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                final root = header.build(context) as Container;
                final safeArea = root.child! as SafeArea;
                expect(safeArea.top, isTrue);
                expect(safeArea.bottom, isFalse);
                expect(
                  MushafHeader.hauteurPour(context),
                  header.preferredSize.height + padding.top,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

// Warsh's paper numbering must never use the audio/ASR-aligned Hafs index.
Future<List<Verse>> verses(int page, Riwaya riwaya) => riwaya == Riwaya.warsh
    ? QuranApi.fetchWarshMushafVersesByPage(page)
    : QuranApi.fetchVersesByPage(page);
