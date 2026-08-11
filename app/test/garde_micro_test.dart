// Le micro retenu hors récitation a été corrigé TROIS fois et est revenu à
// chaque fois (4a09848, aa67adf, 05240c2) : les correctifs durcissaient un
// écran, pendant que deux autres écrans démarrant une récitation restaient
// ouverts. `GardeMicro` remplace ces points d'appel par une règle unique.
//
// Ce test existe pour que la règle ne se re-casse pas en silence. Il couvre
// les quatre scénarios qui décident de sa justesse -- dont celui qui a fait
// échouer ma première version (sortie sans navigation intermédiaire), trouvé
// en revue et non sur device.

import 'package:coran_karim/services/garde_micro.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vérificateur d'essai : on ne pilote que ce dont le garde se sert -- « le
/// micro est-il détenu ? » -- et on compte les libérations.
class _FauxVerifier extends MockRecitationVerifier {
  bool capture = false;
  int arrets = 0;

  @override
  bool get captureEnCours => capture;

  @override
  Future<void> stop() async {
    arrets++;
    capture = false;
  }
}

void main() {
  late _FauxVerifier verifier;
  late GardeMicro garde;
  late GlobalKey<NavigatorState> nav;

  setUp(() {
    verifier = _FauxVerifier();
    garde = GardeMicro(() => verifier);
    nav = GlobalKey<NavigatorState>();
  });

  tearDown(() => garde.dispose());

  Future<void> ouvrirApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [garde],
        home: const Scaffold(body: Text('accueil')),
      ));

  // Déclarée AVANT ses appelants : en Dart une fonction locale ne peut pas
  // être référencée avant sa déclaration.
  void pousser(Route<void> route) => nav.currentState!.push(route);

  Future<void> pousserEcran(WidgetTester tester, String titre) async {
    pousser(MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: Text(titre))));
    await tester.pumpAndSettle();
  }

  Future<void> revenir(WidgetTester tester) async {
    nav.currentState!.pop();
    await tester.pumpAndSettle();
  }

  testWidgets('quitter l\'ecran qui recitait relache le micro',
      (tester) async {
    await ouvrirApp(tester);
    // L'écran de récitation est ouvert AVANT que la capture démarre -- c'est
    // l'ordre réel, et c'est ce qui piégeait la version à profondeur de pile :
    // aucune navigation ne survient entre le début de la capture et la sortie.
    await pousserEcran(tester, 'recitation');
    verifier.capture = true;

    await revenir(tester);
    await tester.pump();

    expect(verifier.arrets, 1);
  });

  testWidgets('revenir d\'une sous-page NE coupe PAS la recitation',
      (tester) async {
    await ouvrirApp(tester);
    await pousserEcran(tester, 'recitation');
    verifier.capture = true;

    // Sous-page ouverte PENDANT la récitation, puis refermée : on revient à la
    // récitation, le micro doit rester.
    await pousserEcran(tester, 'sous-page');
    await revenir(tester);
    await tester.pump();
    expect(verifier.arrets, 0,
        reason: 'refermer une sous-page, c\'est revenir a la recitation');

    // ... et la sortie réelle, elle, relâche bien.
    await revenir(tester);
    await tester.pump();
    expect(verifier.arrets, 1);
  });

  testWidgets('fermer une feuille modale NE coupe PAS la recitation',
      (tester) async {
    await ouvrirApp(tester);
    await pousserEcran(tester, 'recitation');
    verifier.capture = true;

    // Aide tajwid, réglages de lecture... : ce sont des PopupRoute. Les
    // compter ferait couper le micro en pleine récitation.
    pousser(DialogRoute<void>(
      context: nav.currentContext!,
      builder: (_) => const AlertDialog(content: Text('aide')),
    ));
    await tester.pumpAndSettle();
    await revenir(tester);
    await tester.pump();

    expect(verifier.arrets, 0);
  });

  testWidgets('le passage en arriere-plan relache le micro', (tester) async {
    await ouvrirApp(tester);
    await pousserEcran(tester, 'recitation');
    verifier.capture = true;

    // Aucun `dispose()` d'écran ne pouvait couvrir ce chemin : l'app n'avait
    // aucun observateur de cycle de vie (vérifié : zéro occurrence dans lib/).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(verifier.arrets, 1);
  });

  testWidgets('rien ne se passe si aucune recitation ne tourne',
      (tester) async {
    await ouvrirApp(tester);
    await pousserEcran(tester, 'un ecran quelconque');
    await revenir(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(verifier.arrets, 0,
        reason: 'le garde ne doit jamais appeler stop() a vide -- '
            'stop() hors capture peut lever cote plugin');
  });
}
