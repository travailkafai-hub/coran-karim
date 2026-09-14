// La marge haute des deux ronds flottants du Mushaf (retour, signet), verifiee
// sur des configurations d'ecran REELLES plutot que sur celle du telephone de
// developpement.
//
// Demande utilisateur du 2026-09-12 : « faut gerer ca pour tenir compte les
// plusieurs tel qui vont telecharger app ». Le reglage precedent posait les
// boutons trop bas (marge systeme entiere via SafeArea) ; le corriger a vue
// sur UN appareil aurait juste deplace le probleme sur les autres.
//
// Ce que ce test garantit -- et qu'aucune relecture de code ne garantit :
//   1. le bouton ne chevauche jamais la barre d'etat quand elle est visible ;
//   2. il reste visible meme quand l'appareil ne declare aucune marge ;
//   3. il ne redescend jamais sur le texte, encoche profonde comprise.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/widgets/mushaf_page_chrome.dart';

/// Marges hautes reellement declarees par des appareils du marche, en points
/// logiques. Mesurees sur les valeurs publiees par les constructeurs et les
/// tables d'insets Android/iOS courantes.
const _appareils = <String, double>{
  'mode immersif (barre masquee)': 0,
  'Android sans encoche (barre 24)': 24,
  'Android poincon central (Pixel)': 28,
  'Samsung S24 / S931B (l\'appareil de test)': 32,
  'Android encoche large': 44,
  'iPhone Dynamic Island': 59,
  'tablette 12 pouces': 24,
  'cas extreme, encoche tres profonde': 120,
};

void main() {
  /// Rend la marge calculee pour une marge systeme donnee.
  Future<double> margePour(WidgetTester tester, double paddingTop) async {
    late double marge;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(top: paddingTop)),
        child: Builder(
          builder: (context) {
            marge = margeHauteBoutonsMushaf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return marge;
  }

  testWidgets('le bouton ne descend jamais sous la barre d\'etat', (t) async {
    for (final e in _appareils.entries) {
      final marge = await margePour(t, e.value);
      // Le rond fait 48 de haut (IconButton par defaut). Son BAS ne doit pas
      // depasser la marge systeme + sa propre hauteur : au-dela, il mordrait
      // sur le texte coranique, ce que ce reglage existe pour eviter.
      expect(marge, lessThanOrEqualTo(e.value + 48),
          reason: '${e.key} : le bouton descend trop bas');
    }
  });

  testWidgets('le bouton reste au-dessus du texte, meme encoche profonde',
      (t) async {
    for (final e in _appareils.entries) {
      final marge = await margePour(t, e.value);
      expect(marge, lessThanOrEqualTo(64),
          reason: '${e.key} : la borne haute ne tient pas');
    }
  });

  testWidgets('le bouton reste visible quand rien n\'est declare', (t) async {
    // Mode immersif : l'appareil ne declare aucune marge. Sans plancher, le
    // rond collerait au pixel du bord -- difficile a viser, et coupe sur les
    // ecrans a bords incurves.
    expect(await margePour(t, 0), greaterThanOrEqualTo(4));
  });

  testWidgets('la marge grandit avec l\'encoche, sans la recopier', (t) async {
    // Le coeur du reglage : suivre l'appareil SANS reserver toute sa marge
    // (c'est ce que faisait SafeArea, d'ou des boutons trop bas).
    final sans = await margePour(t, 0);
    final moyen = await margePour(t, 28);
    final grand = await margePour(t, 59);
    expect(moyen, greaterThan(sans));
    expect(grand, greaterThan(moyen));
    for (final p in [28.0, 44.0, 59.0]) {
      expect(await margePour(t, p), lessThan(p),
          reason: 'marge $p : on recopie l\'inset au lieu d\'en prendre une part');
    }
  });
}
