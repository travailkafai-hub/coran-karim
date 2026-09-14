import 'package:coran_karim/l10n/app_localizations.dart';
import 'package:coran_karim/l10n/app_localizations_fr.dart';
import 'package:coran_karim/models/prayer_settings.dart';
import 'package:coran_karim/providers/prayer_settings_provider.dart';
import 'package:coran_karim/widgets/home_prayer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('countdown preserves hours and minutes order', () {
    final t = AppLocalizationsFr();
    expect(
      prayerCountdown(t, const Duration(hours: 1, minutes: 33)),
      'dans 1 h 33',
    );
    expect(prayerCountdown(t, const Duration(hours: 2)), 'dans 2 h');
    expect(prayerCountdown(t, const Duration(minutes: 33)), 'dans 33 min');
    expect(prayerCountdown(t, Duration.zero), t.prayerInNow);
    expect(prayerCountdown(t, const Duration(minutes: -1)), t.prayerInNow);
  });

  for (final locale in ['fr', 'ar', 'en']) {
    for (final width in [320.0, 390.0, 768.0]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('$locale width=$width scale=$scale has no overflow', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final now = DateTime.now();
          final date = DateTime(now.year, now.month, now.day);
          final today = {
            for (final p in PrayerName.values)
              p: date.add(Duration(hours: 5 + p.index * 4)),
          };
          var timesTapped = 0;
          var qiblaTapped = 0;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: PrayerOverview(
                      state: PrayerState(
                        settings: PrayerSettings.defaultValues,
                        locationStatus: PrayerLocationStatus.ready,
                        today: today,
                        tomorrow: {
                          for (final p in PrayerName.values)
                            p: today[p]!.add(const Duration(days: 1)),
                        },
                      ),
                      now: now,
                      onTimes: () => timesTapped++,
                      qibla: QiblaMiniature(
                        bearing: 119,
                        heading: 110,
                        accuracy: 15,
                        onTap: () => qiblaTapped++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byIcon(Icons.tune_rounded));
          await tester.tap(find.byType(QiblaMiniature));
          expect(timesTapped, 1);
          expect(qiblaTapped, 1);
          expect(find.text('05:00'), findsOneWidget);
          expect(find.text('21:00'), findsWidgets);
        });
      }
    }
  }

  for (final accuracy in <double?>[null, -1, 30, 15]) {
    testWidgets('Qibla accuracy $accuracy does not falsely claim alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 104,
                child: QiblaMiniature(
                  bearing: 119,
                  heading: 119,
                  accuracy: accuracy,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.check_circle_outline_rounded),
        accuracy == 15 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing position keeps Qibla access without fake arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PrayerOverview(
            state: PrayerState.initial(),
            now: DateTime.now(),
            onTimes: () {},
            qibla: QiblaMiniature(onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.navigation_rounded), findsNothing);
    expect(find.byIcon(Icons.explore_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
