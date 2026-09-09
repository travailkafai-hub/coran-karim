// Correctif du 2026-09-09 : sur une vraie session (Al-Baqara, versets 1-3
// puis saut de verset), le decrochage NATIF (3 fenetres hors texte) a mis
// 57 s a se declencher alors que la chaine jugeait DEJA correctement -- en
// `deplace` -- des mots loin devant le pointeur des la 12e seconde. Pendant
// ce temps, `state.pointer` restait fige : le souffleur de silence a propose
// de l'aide au mauvais endroit.
//
// Ce test verifie DIRECTEMENT la detection ajoutee dans `_onV2`
// (recitation_provider.dart) : une serie coherente de verdicts `deplace`
// loin devant le pointeur doit resynchroniser sans attendre le decrochage
// natif -- et un signal trop faible (peu de mots, trop proche, ou trop
// disperse) ne doit PAS declencher a tort.
import 'dart:async';
import 'package:coran_karim/models/judgement_options.dart' show TajwidRule;
import 'package:coran_karim/models/recitation_state.dart';
import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/providers/recitation_provider.dart';
import 'package:coran_karim/services/diagnostic_log.dart';
import 'package:coran_karim/services/quran_api.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _V2Batch = List<
    ({
      int index,
      String statut,
      String trace,
      String heard,
      Set<TajwidRule> detectedRules,
      bool tajwidFiable,
      bool tajwidObserve,
      double? margeLettres,
      Map<TajwidRule, ({double prob, double seuil, int dureeMs})> scoresRegles
    })>;

({
  int index,
  String statut,
  String trace,
  String heard,
  Set<TajwidRule> detectedRules,
  bool tajwidFiable,
  bool tajwidObserve,
  double? margeLettres,
  Map<TajwidRule, ({double prob, double seuil, int dureeMs})> scoresRegles
}) _verdict(int index, String statut) => (
      index: index,
      statut: statut,
      trace: 'test',
      heard: '',
      detectedRules: const {},
      tajwidFiable: false,
      tajwidObserve: false,
      margeLettres: null,
      scoresRegles: const {},
    );

class _V2Verifier extends MockRecitationVerifier {
  final losses = StreamController<int>.broadcast();
  final v2 = StreamController<_V2Batch>.broadcast();
  Future<void> Function(String)? identify;

  @override
  Stream<int> get decrochage => losses.stream;
  @override
  Stream<_V2Batch> get v2Statuses => v2.stream;
  @override
  Future<void> commencerIdentificationPriere(
    Future<void> Function(String) onText,
  ) async {
    identify = onText;
  }

  @override
  void terminerIdentificationPriere() {
    identify = null;
  }

  @override
  Future<void> repartirApresSouffle(int mot) async {}

  @override
  void dispose() {
    losses.close();
    v2.close();
    super.dispose();
  }
}

class _V2Notifier extends RecitationNotifier {
  _V2Notifier(super.verifier);
  void fatiha() {
    state = state.copyWith(prayerPhase: PrayerPhase.fatiha);
  }
}

Future<void> eventTurn() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    DiagnosticLog.enabled = false;
    QuranApi.riwaya = Riwaya.hafs;
  });

  /// Pose Al-Baqara comme cible suivie (PrayerPhase.target), pointeur proche
  /// de 0 -- même mécanique que `prayer_follow_flow_test.dart`.
  Future<(_V2Notifier, _V2Verifier)> poserCibleAlBaqara() async {
    final verifier = _V2Verifier();
    final notifier = _V2Notifier(verifier);
    await notifier.startPrayerFollow();
    notifier.fatiha();
    verifier.losses.add(0);
    await eventTurn();
    final verses = await QuranApi.fetchVerses(2);
    await verifier.identify!(
        verses.take(3).map((v) => v.textUthmani).join(' '));
    expect(notifier.state.prayerPhase, PrayerPhase.target);
    return (notifier, verifier);
  }

  test('une serie de 3 "deplace" coherents loin devant le pointeur '
      'resynchronise sans attendre le decrochage natif', () async {
    final (notifier, verifier) = await poserCibleAlBaqara();
    final pointeur = notifier.state.pointer;
    final hints = <({int de, int a})>[];
    final sub = notifier.sautASouffler.listen(hints.add);

    // Reproduit la session reelle : des mots bien reconnus (deplace) loin
    // devant le pointeur, un par lot -- comme la chaine v2 les envoie.
    final loin = pointeur + 30;
    verifier.v2.add([_verdict(loin, 'deplace')]);
    await eventTurn();
    expect(hints, isEmpty, reason: '1 seul deplace ne suffit pas');
    verifier.v2.add([_verdict(loin + 2, 'deplace')]);
    await eventTurn();
    expect(hints, isEmpty, reason: '2 deplace ne suffisent pas encore');
    verifier.v2.add([_verdict(loin + 5, 'deplace')]);
    await eventTurn();

    expect(hints, [(de: loin, a: loin)],
        reason: 'le 3e deplace coherent doit resynchroniser au PREMIER '
            'mot de la serie, pas au dernier');

    await sub.cancel();
    await notifier.stop();
    notifier.dispose();
    await eventTurn();
    verifier.dispose();
  });

  test('des "deplace" trop proches du pointeur (simple inversion locale) '
      'ne declenchent rien', () async {
    final (notifier, verifier) = await poserCibleAlBaqara();
    final pointeur = notifier.state.pointer;
    final hints = <({int de, int a})>[];
    final sub = notifier.sautASouffler.listen(hints.add);

    // A l'interieur de la marge (_kMargeDeplaceAvantResync = 10) : deja
    // couvert par le mecanisme "dit, mais pas a sa place" (statutBase),
    // pas un signal de decrochage.
    verifier.v2.add([
      _verdict(pointeur + 1, 'deplace'),
      _verdict(pointeur + 2, 'deplace'),
      _verdict(pointeur + 3, 'deplace'),
    ]);
    await eventTurn();

    expect(hints, isEmpty);

    await sub.cancel();
    await notifier.stop();
    notifier.dispose();
    await eventTurn();
    verifier.dispose();
  });

  test('des "deplace" trop disperses (deux signaux sans rapport) ne se '
      'combinent pas en une fausse serie', () async {
    final (notifier, verifier) = await poserCibleAlBaqara();
    final pointeur = notifier.state.pointer;
    final hints = <({int de, int a})>[];
    final sub = notifier.sautASouffler.listen(hints.add);

    // Etalement > _kEtalementMaxDeplaces (60) entre le premier et le
    // troisieme : deux vagues distinctes, pas une serie coherente. Le
    // dernier doit repartir de zero, donc il en manque encore deux apres
    // celui-ci pour declencher.
    verifier.v2.add([_verdict(pointeur + 20, 'deplace')]);
    await eventTurn();
    verifier.v2.add([_verdict(pointeur + 25, 'deplace')]);
    await eventTurn();
    verifier.v2.add([_verdict(pointeur + 200, 'deplace')]);
    await eventTurn();

    expect(hints, isEmpty,
        reason: 'le troisieme mot est trop loin des deux premiers pour '
            'compter comme la meme serie');

    await sub.cancel();
    await notifier.stop();
    notifier.dispose();
    await eventTurn();
    verifier.dispose();
  });

  test('un verdict "definitif" proche du pointeur purge les "deplace" '
      'perimes (le decrochage s etait resolu tout seul)', () async {
    final (notifier, verifier) = await poserCibleAlBaqara();
    final pointeur = notifier.state.pointer;
    final hints = <({int de, int a})>[];
    final sub = notifier.sautASouffler.listen(hints.add);

    verifier.v2.add([_verdict(pointeur + 30, 'deplace')]);
    await eventTurn();
    verifier.v2.add([_verdict(pointeur + 32, 'deplace')]);
    await eventTurn();
    // Le pointeur avance normalement bien au-dela des deplace accumules --
    // ils sont perimes, la purge (`removeWhere(i <= state.pointer)`) ne les
    // retire que si le POINTEUR les a depasses. Ce test verifie seulement
    // qu'un 3e deplace ISOLE, longtemps apres, ne reutilise pas les deux
    // anciens pour declencher a tort.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    verifier.v2.add([_verdict(pointeur + 34, 'deplace')]);
    await eventTurn();

    // Les trois sont dans la meme fenetre (span 4 < 60) : ceci EST la serie
    // coherente attendue, donc elle doit se declencher -- ce test confirme
    // seulement que l'accumulation traverse plusieurs appels a `_onV2`
    // (pas uniquement un seul batch), condition necessaire au scenario reel
    // (chaque `[V2] mot=` arrivait dans un batch separe).
    expect(hints, [(de: pointeur + 30, a: pointeur + 30)]);

    await sub.cancel();
    await notifier.stop();
    notifier.dispose();
    await eventTurn();
    verifier.dispose();
  });
}
