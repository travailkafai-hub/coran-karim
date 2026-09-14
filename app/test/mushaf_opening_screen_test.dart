import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/l10n/app_localizations.dart';
import 'package:coran_karim/providers/app_settings_provider.dart';
import 'package:coran_karim/screens/mushaf_opening_screen.dart';
import 'package:coran_karim/services/mushaf_opening_position.dart';
import 'package:coran_karim/services/quran_api.dart';
import 'package:coran_karim/widgets/mushaf_cover_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── CE QUE CE TEST VERIFIE A CHANGE LE 2026-09-14 ─────────────────────────
  //
  // Demande utilisateur : « je veux que l'ouverture, la couverture, n'atterrisse
  // pas dans le mushaf papier mais dans la page principale [...] ou le menu
  // sera affiche ».
  //
  // AVANT, ce test exigeait `mushaf-body-<page>` : la couverture DEVAIT ouvrir
  // le mushaf papier. Ce n'est plus le contrat -- la couverture s'ouvre
  // desormais sur ce qu'il y a dessous (les onglets) et se referme d'elle-meme.
  // Le test suit donc le nouveau comportement, et ce qu'il verifie reste de
  // meme nature : ce que l'ecran fait vraiment.
  //
  // CE QUI N'A PAS CHANGE, et qu'on continue de verrouiller : le PRECHARGEMENT.
  // `_prepare()` restaure la riwaya et la position de lecture avant de rendre
  // la main ; le supprimer reporterait ce cout sur la premiere ouverture du
  // mushaf. Ces deux assertions-la sont conservees telles quelles.
  for (final riwaya in Riwaya.values) {
    for (final page in [1, 3]) {
      testWidgets(
        '${riwaya.name}: page $page — la couverture rend la main sans ouvrir le papier',
        (tester) async {
          SharedPreferences.setMockInitialValues({'riwaya': riwaya.name});
          QuranApi.riwaya = Riwaya.hafs;
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(
            () => MushafOpeningPosition.save(riwaya, page, null),
          );
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('Home'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<int>(
                          builder: (_) => const MushafOpeningScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('Home'));
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // La couverture s'est effacee, ET ELLE S'EST REFERMEE SEULE : plus
          // besoin d'un retour arriere pour revenir a la page principale.
          expect(find.byType(MushafClosedCover), findsNothing);
          expect(find.byType(MushafOpeningScreen), findsNothing);
          expect(find.text('Home'), findsOneWidget);
          // Le mushaf papier n'est PAS ouvert -- c'est tout l'objet du
          // changement demande.
          expect(find.byKey(ValueKey('mushaf-body-$page')), findsNothing);
          // Le prechargement, lui, a bien eu lieu : la riwaya est restauree.
          // Lu depuis l'arbre restant (l'ecran d'ouverture n'existe plus).
          final container = ProviderScope.containerOf(
            tester.element(find.text('Home')),
          );
          expect(container.read(riwayaProvider), riwaya);
          expect(QuranApi.riwaya, riwaya);
        },
      );
    }
  }
}
