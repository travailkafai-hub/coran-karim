// Le jeu ENCHAÎNEMENT : ce qui se passe APRÈS une erreur.
//
// Écrit le 2026-08-15 sur constat utilisateur : « quand on en revient en cas
// d'erreur au verset d'avant, que soit proposé le premier mot, on ne commence
// pas un mot ». Le retour en arrière existait déjà et se calait bien sur le
// mot 0 du verset précédent — mais ce mot était présenté en QCM, donc à
// deviner, alors que le recul existe pour « donner un petit élan de mots déjà
// sûrs avant de rattaquer le passage qui a fait échouer ».
//
// Ces tests verrouillent les DEUX moitiés de la règle, parce qu'elles se
// contredisent en apparence et qu'un futur correctif pourrait sacrifier l'une
// pour l'autre :
//   - en PROGRESSION, le premier mot d'un verset reste TESTÉ (décision du
//     2026-08-09 : « c'est là qu'il y a l'oubli ») ;
//   - en REPRISE après erreur, il est MONTRÉ.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:coran_karim/models/verse.dart';
import 'package:coran_karim/providers/memorization_game_provider.dart';

Verse _v(int ayah, String texte) => Verse(
      surahNumber: 1,
      ayahNumber: ayah,
      textUthmani: texte,
      pageNumber: 1,
    );

void main() {
  // Binding requis : le notifier résout la portion courante de façon
  // asynchrone (`_refreshCurrentPortionInfo`), ce qui touche aux services.
  TestWidgetsFlutterBinding.ensureInitialized();
  // Le record par portion est lu depuis les préférences : sans ce faux
  // magasin, `getInstance()` lève `MissingPluginException` hors device.
  SharedPreferences.setMockInitialValues({});

  // Trois versets de trois mots. TEXTE ARABE obligatoire : `GameVerse` écarte
  // tout token sans lettre arabe (signes de pause, décorations) — un verset
  // en latin donnerait une liste de mots VIDE et le test échouerait sur un
  // RangeError sans rapport avec ce qu'il vérifie.
  final versets = [
    _v(1, 'الحمد لله رب'),
    _v(2, 'الرحمن الرحيم مالك'),
    _v(3, 'إياك نعبد وإياك'),
  ];

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  /// Amène le jeu au premier mot du verset [cible] en jouant juste.
  MemorizationGameNotifier _avancerJusquAuVerset(
      ProviderContainer c, int cible) {
    final n = c.read(memorizationGameProvider(versets).notifier);
    while (c.read(memorizationGameProvider(versets)).currentVerseIndex < cible) {
      n.submitWord(c.read(memorizationGameProvider(versets)).currentWord);
    }
    return n;
  }

  test('en progression normale, le premier mot d un verset est TESTÉ', () {
    final c = container();
    _avancerJusquAuVerset(c, 1);
    final s = c.read(memorizationGameProvider(versets));
    expect(s.currentWordIndex, 0);
    expect(s.choices, isNotEmpty,
        reason: 'décision 2026-08-09 : la transition entre versets est '
            'précisément là où la mémoire lâche, elle doit être vérifiée');
  });

  test('après une erreur, le premier mot du verset de reprise est MONTRÉ', () async {
    final c = container();
    final n = _avancerJusquAuVerset(c, 2);
    // Erreur sur le premier mot du verset 2.
    n.submitWord('mot-qui-nexiste-pas');
    // Le recul est DIFFÉRÉ de 1400 ms (`_restartVerseAfterReveal`), le temps
    // que le joueur voie la bonne réponse. `restartVerse()` est un autre
    // geste — le bouton manuel « recommencer », qui ne recule PAS.
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    final s = c.read(memorizationGameProvider(versets));
    expect(s.currentVerseIndex, 1, reason: 'on revient au verset précédent');
    expect(s.currentWordIndex, 0, reason: 'et à son premier mot');
    expect(s.choices, isEmpty,
        reason: 'le premier mot de la reprise doit être PROPOSÉ, pas deviné');
  });

  test('la reprise se consomme : le mot suivant redevient un QCM', () async {
    final c = container();
    final n = _avancerJusquAuVerset(c, 2);
    n.submitWord('mot-qui-nexiste-pas');
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    final s1 = c.read(memorizationGameProvider(versets));
    expect(s1.repriseApresErreur, isTrue);
    n.submitWord(s1.currentWord); // le joueur valide le mot montré

    final s2 = c.read(memorizationGameProvider(versets));
    expect(s2.repriseApresErreur, isFalse,
        reason: 'le coup de pouce ne vaut que pour le mot de reprise');
    expect(s2.choices, isNotEmpty,
        reason: 'le jeu reprend son cours normal dès le mot suivant');
  });

  test('erreur au tout premier verset : reste sur place, mot montré', () async {
    final c = container();
    final n = c.read(memorizationGameProvider(versets).notifier);
    n.submitWord(c.read(memorizationGameProvider(versets)).currentWord);
    n.submitWord('faux');
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    final s = c.read(memorizationGameProvider(versets));
    expect(s.currentVerseIndex, 0, reason: 'rien avant le verset 0');
    expect(s.currentWordIndex, 0);
    expect(s.choices, isEmpty);
  });
}
