// Signalement utilisateur (2026-09-09) : « le jeu enchainement ne fait que
// 6 versets [...] ca doit continuer a charger les prochains a chaque fois,
// ne pas se contenter des 6 premiers ». Le mecanisme "PARTIE ILLIMITEE"
// (cf. la doc de MemorizationGameState) promet de charger la page suivante
// du Mushaf des que le dernier mot du dernier verset CHARGE est valide.
// Ce test verifie CE mecanisme sur de vraies pages du Coran (pas un mock),
// en simulant une partie complete jusqu'a plusieurs pages plus loin.
import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/providers/memorization_game_provider.dart';
import 'package:coran_karim/services/quran_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Le record par portion est lu depuis les préférences : sans ce faux
  // magasin, getInstance() lève MissingPluginException hors device (même
  // piège déjà documenté dans memorization_game_reprise_test.dart).
  SharedPreferences.setMockInitialValues({});
  setUp(() => QuranApi.riwaya = Riwaya.hafs);

  /// Joue tous les mots de l'etat courant jusqu'a ce que la page charge un
  /// nouveau lot de versets, ou jusqu'a une borne de securite -- jamais de
  /// pari sur "ca marche forcement en moins de N coups".
  Future<void> joueJusquaChangementDePage(
      MemorizationGameNotifier notifier) async {
    final versesAvant = notifier.state.verses.length;
    for (var coups = 0; coups < 2000; coups++) {
      if (notifier.state.verses.length > versesAvant) return; // page suivante chargee
      if (notifier.state.isGameComplete) return; // le jeu s'est arrete -- a l'appelant de juger si c'est normal
      if (notifier.state.isLoadingNextPage) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      notifier.submitWord(notifier.state.currentWord);
      await Future<void>.delayed(Duration.zero);
    }
    fail('2000 coups sans changement de page ni fin de partie -- boucle suspecte');
  }

  test('une page du Coran chargee seule continue automatiquement sur la '
      'page suivante, pas seulement sur ses propres versets', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Page 5 : au milieu d'Al-Baqara, loin d'Al-Fatiha (page 1) et de la fin
    // du Coran (page 604) -- garantit une page suivante qui existe vraiment.
    final page5 = await QuranApi.fetchVersesByPage(5);
    expect(page5, isNotEmpty, reason: 'la page 5 doit exister dans l\'asset');
    final versesInitiaux = page5.length;

    final provider = memorizationGameProvider(page5);
    final notifier = container.read(provider.notifier);

    expect(notifier.state.verses.length, versesInitiaux);

    await joueJusquaChangementDePage(notifier);

    expect(notifier.state.isGameComplete, isFalse,
        reason: 'la page 5 n\'est pas la fin du Coran : le jeu ne doit PAS '
            's\'arreter, il doit charger la page 6 tout seul');
    expect(notifier.state.verses.length, greaterThan(versesInitiaux),
        reason: 'de nouveaux versets (page suivante) doivent avoir ete '
            'ajoutes a la liste');
  });

  test('la continuite tient sur PLUSIEURS pages d\'affilee, pas seulement '
      'la toute premiere transition', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final page5 = await QuranApi.fetchVersesByPage(5);
    final provider = memorizationGameProvider(page5);
    final notifier = container.read(provider.notifier);

    var dernierCompte = notifier.state.verses.length;
    for (var transition = 0; transition < 3; transition++) {
      await joueJusquaChangementDePage(notifier);
      expect(notifier.state.isGameComplete, isFalse,
          reason: 'arret premature a la transition ${transition + 1} '
              '(verses=${notifier.state.verses.length})');
      expect(notifier.state.verses.length, greaterThan(dernierCompte),
          reason: 'transition ${transition + 1} n\'a rien ajoute');
      dernierCompte = notifier.state.verses.length;
    }
  });
}
