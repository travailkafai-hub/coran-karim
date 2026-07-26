import 'package:coran_karim/l10n/app_localizations.dart';
import 'package:coran_karim/services/recitation_start_sequence.dart';
import 'package:coran_karim/widgets/recitation_start_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows accessible countdown and Go cues', (tester) async {
    Future<void> pumpStage(RecitationStartStage stage) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RecitationStartOverlay(stage: stage)),
        ),
      );
    }

    await pumpStage(RecitationStartStage.countdown3);
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Get ready — 3'), findsOneWidget);

    await pumpStage(RecitationStartStage.go);
    expect(find.text('GO!'), findsOneWidget);
    expect(find.bySemanticsLabel('GO!'), findsOneWidget);
  });
}
