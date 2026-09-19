import 'package:coran_karim/widgets/mise_a_jour_obligatoire.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';

// Seuls le Store et son ouverture sont simulés. Le comparateur de versions,
// les préférences persistantes et le dialogue sont ceux du package déployé.
class _Store extends UpgraderStore {
  _Store(this.version);

  String? version;
  int lectures = 0;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required installedVersion,
    required String? country,
    required String? language,
  }) async {
    lectures++;
    return UpgraderVersionInfo(
      installedVersion: installedVersion,
      appStoreVersion: Upgrader.parseVersion(version, 'test', false),
      appStoreListingURL:
          'https://play.google.com/store/apps/details?id=com.corankarim.coran_karim',
    );
  }
}

class _Controle extends ControleMiseAJourObligatoire {
  _Controle(_Store store)
    : super(
        storeController: UpgraderStoreController(
          onAndroid: () => store,
          oniOS: () => store,
          onWindows: () => store,
          onLinux: () => store,
          onMacOS: () => store,
        ),
      );

  int ouverturesStore = 0;

  @override
  Future<void> sendUserToAppStore() async => ouverturesStore++;
}

void main() {
  final dialogue = find.byKey(const Key('upgrader_alert_dialog'));
  final mettreAJour = find.descendant(
    of: dialogue,
    matching: find.byType(TextButton),
  );
  late _Store store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store('1.0.10');
  });

  Future<_Controle> ouvrir(
    WidgetTester tester, {
    String versionInstallee = '1.0.9',
  }) async {
    final controle = _Controle(store)
      ..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'Coran Karim',
          packageName: 'com.corankarim.coran_karim',
          version: versionInstallee,
          buildNumber: '12',
        ),
      );
    await tester.runAsync(controle.initialize);
    await tester.pumpWidget(
      MaterialApp(
        home: MiseAJourObligatoire(
          controle: controle,
          child: const Scaffold(body: Text('Accueil')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controle;
  }

  Future<void> fermer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('le retour et le toucher extérieur ne ferment pas le dialogue', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(dialogue, findsOneWidget);
    expect(mettreAJour, findsOneWidget); // aucun bouton Ignorer / Plus tard
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(dialogue, findsOneWidget);
    await fermer(tester);
  });

  testWidgets('aller au Store et revenir sans installer reste bloquant', (
    tester,
  ) async {
    final controle = await ouvrir(tester);
    await tester.tap(mettreAJour);
    await tester.pumpAndSettle();
    expect(controle.ouverturesStore, 1);
    expect(dialogue, findsOneWidget);
    final lecturesAvantReprise = store.lectures;
    await controle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(store.lectures, lecturesAvantReprise + 1);
    expect(dialogue, findsOneWidget);
    // Le bouton reste utilisable si la première ouverture a échoué.
    await tester.tap(mettreAJour);
    expect(controle.ouverturesStore, 2);
    await fermer(tester);
  });

  testWidgets(
    'relancer immédiatement ne bénéficie pas du délai de trois jours',
    (tester) async {
      final premier = await ouvrir(tester);
      await tester.runAsync(premier.saveLastAlerted);
      await fermer(tester);
      final second = await ouvrir(tester);
      expect(second.isTooSoon(), isTrue); // préférence réellement restaurée
      expect(dialogue, findsOneWidget);
      await fermer(tester);
    },
  );

  testWidgets('une ancienne préférence Ignorer ne désactive pas le blocage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'userIgnoredVersion': '1.0.10'});
    final controle = await ouvrir(tester);
    expect(controle.alreadyIgnoredThisVersion(), isTrue);
    expect(dialogue, findsOneWidget);
    await fermer(tester);
  });

  testWidgets('après installation la nouvelle version ouvre normalement', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(dialogue, findsOneWidget);
    await fermer(tester);
    await ouvrir(tester, versionInstallee: '1.0.10');
    expect(dialogue, findsNothing);
    expect(find.text('Accueil').hitTestable(), findsOneWidget);
    await fermer(tester);
  });

  testWidgets(
    'une version installée plus récente ne demande pas un retour arrière',
    (tester) async {
      await ouvrir(tester, versionInstallee: '1.0.11');
      expect(dialogue, findsNothing);
      await fermer(tester);
    },
  );

  testWidgets(
    'une version Store inconnue ne bloque pas le démarrage hors ligne',
    (tester) async {
      store.version = null;
      await ouvrir(tester);
      expect(dialogue, findsNothing);
      await fermer(tester);
    },
  );

  testWidgets(
    'une nouvelle version détectée à la reprise déclenche le blocage',
    (tester) async {
      store.version = '1.0.9';
      final controle = await ouvrir(tester);
      expect(dialogue, findsNothing);
      store.version = '1.0.10';
      await controle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(dialogue, findsOneWidget);
      await fermer(tester);
    },
  );
}
