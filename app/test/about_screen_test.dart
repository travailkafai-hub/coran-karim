// L'écran « À propos » porte des mentions LÉGALES (avertissement sur le texte
// généré, notice Gemma imposée par sa licence, attributions). Un écran qui
// plante ou qui perd une de ces mentions dans une langue est un défaut de
// conformité, pas un défaut d'esthétique — d'où un test qui le construit dans
// les TROIS langues et vérifie la présence des mentions non négociables.

import 'package:coran_karim/l10n/app_localizations.dart';
import 'package:coran_karim/screens/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Sans ça, google_fonts tente d'aller chercher les polices sur le réseau
    // pendant le test (et l'échec HTTP pollue la sortie).
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> ouvrir(WidgetTester tester, String langue) => tester.pumpWidget(
        MaterialApp(
          locale: Locale(langue),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AboutScreen(),
        ),
      );

  // La page est un ListView : ce qui est sous la ligne de flottaison n'est PAS
  // construit tant qu'on n'a pas fait défiler. Chercher une mention sans
  // dérouler la page rend « absente » une mention pourtant présente — d'où ce
  // défilement explicite avant chaque vérification de bas de page.
  Future<void> derouler(WidgetTester tester, Finder cible) =>
      tester.scrollUntilVisible(cible, 200,
          scrollable: find.byType(Scrollable).first);

  for (final langue in ['fr', 'en', 'ar']) {
    testWidgets('se construit en $langue avec ses mentions obligatoires',
        (tester) async {
      await ouvrir(tester, langue);
      await tester.pumpAndSettle();

      // La version, sinon un utilisateur ne peut pas dire ce qu'il utilise.
      expect(find.textContaining(kAppVersion), findsOneWidget);

      // Les attributions des sources externes.
      await derouler(tester, find.textContaining('Quran.com'));
      expect(find.textContaining('Quran.com'), findsOneWidget);
      expect(find.textContaining('hisnmuslim.com'), findsOneWidget);

      // Le crédit COURT du modèle ASR sur la page : créateur + licence. Le
      // détail (nom du checkpoint, lien, exclusion de garantie) vit dans la
      // page des licences — cf. le test unitaire sur kNoticeAsr plus bas.
      final credit = find.textContaining('CC BY 4.0');
      await derouler(tester, credit);
      expect(credit, findsOneWidget,
          reason: 'le crédit du modèle ASR doit rester visible, en $langue');
      expect(find.textContaining('NVIDIA'), findsWidgets);
    });
  }

  // Test PUR (pas de widget) : la notice complète part au registre des
  // licences, où la vérifier à travers l'IHM coûterait trois navigations pour
  // le même contrôle. Ce qui compte est qu'aucun des éléments exigés par
  // CC BY 4.0 ne disparaisse le jour où quelqu'un réécrit ce texte.
  test('la notice complète porte les éléments exigés par CC BY 4.0', () {
    expect(kNoticeAsr, contains('NVIDIA'));
    expect(kNoticeAsr, contains('stt_ar_fastconformer_hybrid_large_pcd_v1'));
    expect(kNoticeAsr, contains('CC BY 4.0'));
    expect(kNoticeAsr, contains('creativecommons.org/licenses/by/4.0'));
    expect(kNoticeAsr, contains('MODIFICATIONS'),
        reason: 'CC BY 4.0 impose de signaler que le modèle a été modifié');
  });

  testWidgets('la notice Gemma suit le drapeau kTuteurIaEmbarque',
      (tester) async {
    await ouvrir(tester, 'fr');
    await tester.pumpAndSettle();
    final gemma = find.textContaining('ai.google.dev/gemma/terms');
    if (kTuteurIaEmbarque) {
      await derouler(tester, gemma);
      expect(gemma, findsOneWidget);
    } else {
      // Le modèle n'est pas distribué : afficher ses conditions laisserait
      // croire qu'il tourne dans l'app.
      expect(gemma, findsNothing);
    }
  });

  testWidgets('le bloc de signalement suit la présence d\'une adresse',
      (tester) async {
    await ouvrir(tester, 'fr');
    await tester.pumpAndSettle();
    // Le bloc de signalement dépend de DEUX conditions, pas d'une seule :
    //   - `kTuteurIaEmbarque` : signaler un contenu généré n'a de sens que si
    //     un modèle en produit. Depuis le retrait de Gemma (2026-08-10) il est
    //     à `false`, donc le bloc ne s'affiche pas ;
    //   - `kContactEmail` : renseigné, sinon on afficherait une adresse vide.
    //
    // Ce test ne vérifiait que la seconde. Il est passé au vert tant que
    // l'adresse était vide, puis a échoué dès qu'elle a été renseignée —
    // en signalant un défaut du TEST, pas de l'écran. Corrigé le 2026-08-10.
    final attendu = kTuteurIaEmbarque && kContactEmail.isNotEmpty;
    expect(
      find.byIcon(Icons.copy_rounded),
      attendu ? findsOneWidget : findsNothing,
      reason: 'tuteur embarque=$kTuteurIaEmbarque, '
          'adresse renseignee=${kContactEmail.isNotEmpty}',
    );
  });

  testWidgets('la page des licences tierces s\'ouvre', (tester) async {
    await ouvrir(tester, 'fr');
    await tester.pumpAndSettle();
    final bouton = find.byIcon(Icons.description_outlined);
    await derouler(tester, bouton);
    // `scrollUntilVisible` s'arrête dès que la cible est CONSTRUITE, ce qui ne
    // veut pas dire qu'elle est dans la fenêtre : le bouton se retrouvait à
    // y=769 dans un viewport de 600 et le tap ne touchait rien.
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
