import 'dart:async';
import 'package:coran_karim/models/recitation_state.dart';
import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/providers/recitation_provider.dart';
import 'package:coran_karim/services/diagnostic_log.dart';
import 'package:coran_karim/services/quran_api.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

class PrayerVerifier extends MockRecitationVerifier {
  final losses = StreamController<int>.broadcast();
  Future<void> Function(String)? identify;
  int starts = 0;
  int stops = 0;
  int rewinds = 0;
  int pauses = 0;
  int resumes = 0;
  int resets = 0;
  bool? warsh;
  final hintResumePositions = <int>[];
  final targets = <({String mode, int depart, List<int> nonJugeables})>[];

  @override
  Stream<int> get decrochage => losses.stream;
  @override
  int get sessionGeneration => starts;
  @override
  bool get captureEnCours => starts > stops;
  @override
  Future<void> pauseCapture() async { pauses++; }
  @override
  Future<void> resumeCapture() async { resumes++; }
  @override
  Future<void> resetBuffer() async { resets++; }
  @override
  Future<void> start(
    List<String> expectedWords, {
    bool continuous = false,
    List<int?>? refMinFrames,
  }) async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> setRiwaya(bool value) async {
    warsh = value;
  }

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
  Future<void> v2Activer(
    bool actif,
    List<String> mots, {
    String mode = 'CTL',
    List<int> nonJugeables = const [],
    int depart = -1,
  }) async {
    targets.add((mode: mode, depart: depart, nonJugeables: nonJugeables));
  }

  @override
  Future<bool> v2ReculerAncre(int mot) async {
    rewinds++;
    return true;
  }

  @override
  Future<void> repartirApresSouffle(int mot) async {
    hintResumePositions.add(mot);
  }

  @override
  void dispose() {
    losses.close();
    super.dispose();
  }
}

class PrayerNotifier extends RecitationNotifier {
  PrayerNotifier(super.verifier);
  void fatiha() {
    state = state.copyWith(prayerPhase: PrayerPhase.fatiha);
  }
}

Future<void> eventTurn() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    DiagnosticLog.enabled = false;
  });
  tearDown(() {
    QuranApi.riwaya = Riwaya.hafs;
  });

  for (final riwaya in Riwaya.values) {
    test('prayer ${riwaya.name}: An-Nisa gap prompts verse 4, not verse 5', () async {
      QuranApi.riwaya = riwaya;
      final verifier = PrayerVerifier();
      final notifier = PrayerNotifier(verifier);
      await notifier.startPrayerFollow();
      notifier.fatiha();
      verifier.losses.add(0);
      await eventTurn();
      final verses = await QuranApi.fetchVerses(4);
      await verifier.identify!(verses.take(2).map((v) => v.textUthmani).join(' '));
      expect(notifier.state.prayerPhase, PrayerPhase.target);
      final start = Iterable<int>.generate(notifier.state.words.length).firstWhere(
        (i) => notifier.verseAndLocalIndexFor(i)?.$1.ayahNumber == 4,
      );
      if (riwaya == Riwaya.hafs) expect(start, 72);
      final hints = <({int de, int a})>[];
      final sub = notifier.sautASouffler.listen(hints.add);
      // ChGPT: the native event means "resume AFTER this index", not
      // "furthest word heard" when an earlier prayer gap remains unresolved.
      verifier.losses.add(start - 1);
      await eventTurn();
      expect(hints, [(de: start, a: start)]);
      final (verse, local) = notifier.verseAndLocalIndexFor(hints.single.de)!;
      expect(verse.surahNumber, 4);
      expect(verse.ayahNumber, 4);
      expect(local, 0);
      await notifier.soufflerPriere(hints.single.de, () async {});
      expect(verifier.hintResumePositions, [start]);
      expect(notifier.state.pointer, start);
      expect(notifier.state.riwaya, riwaya);
      expect(verifier.warsh, riwaya == Riwaya.warsh);
      expect(verifier.resumes, 1);
      expect(verifier.rewinds, 0);
      await sub.cancel();
      await notifier.stop();
      notifier.dispose();
      await eventTurn();
      verifier.dispose();
    });

    test(
      'prayer ${riwaya.name}: continuous identification, hint without rewind',
      () async {
        QuranApi.riwaya = riwaya;
        final verifier = PrayerVerifier();
        final notifier = PrayerNotifier(verifier);
        await notifier.startPrayerFollow();
        expect(notifier.state.riwaya, riwaya);
        expect(verifier.warsh, riwaya == Riwaya.warsh);
        notifier.fatiha();
        verifier.losses.add(0);
        await eventTurn();
        expect(notifier.state.prayerPhase, PrayerPhase.detectingTarget);
        expect(verifier.identify, isNotNull);
        expect(verifier.starts, 1);
        expect(verifier.stops, 0);

        final verses = await QuranApi.fetchVerses(112);
        await verifier.identify!(verses.map((v) => v.textUthmani).join(' '));
        expect(notifier.state.prayerPhase, PrayerPhase.target);
        expect(notifier.state.riwaya, riwaya);
        expect(verifier.identify, isNull);
        expect(verifier.targets.last.mode, 'PRIERE');
        expect(verifier.starts, 1);
        expect(verifier.stops, 0);
        expect(
          notifier.state.correctCount,
          0,
          reason: 'identification is not a verdict',
        );

        final pointer = notifier.state.pointer;
        final hints = <({int de, int a})>[];
        final sub = notifier.sautASouffler.listen(hints.add);
        verifier.losses.add(-1);
        await eventTurn();
        expect(hints, [
          (de: 0, a: 0),
        ], reason: 'help is offered even without a judged first word');
        expect(notifier.state.pointer, pointer);
        expect(verifier.rewinds, 0);
        final targetsBefore = verifier.targets.length;
        // ── APRES UN SOUFFLE, L'ANCRE REVIENT AU MOT SOUFFLE (2026-09-07) ──
        //
        // Ce test attendait `notifier.state.pointer == pointer` : il encodait
        // la specification du 2026-08-07, « aucun recul d'ancre ». Elle a ete
        // REVOQUEE par l'utilisateur sur ce seul chemin :
        //
        //   « L'ancre arrive au mot 40, l'aligneur place ce que je dis au mot
        //   60, ils se colorient alors qu'il y a un gap. Le souffleur dit mot
        //   40, 41, 42. Mais a ce stade-la, l'ancre DOIT RECULER [...] sinon
        //   le souffleur commence par me dire le mot 66, 67, 68. Non. »
        //
        // On verifie donc l'inverse de ce qui etait verifie ici : le pointeur
        // suit le passage souffle. Le reste du contrat ne bouge pas -- une
        // pause, une reprise, aucune recreation de cible.
        await notifier.soufflerPriere(3, () async {});
        expect(verifier.pauses, 1);
        expect(verifier.resumes, 1);
        expect(verifier.resets, 0);
        expect(verifier.targets.length, targetsBefore);
        expect(notifier.state.pointer, 3,
            reason: 'apres un souffle, l ancre revient au mot souffle');
        await expectLater(notifier.soufflerPriere(3, () async {
          throw StateError('audio unavailable');
        }), throwsStateError);
        expect(verifier.resumes, 2, reason: 'failed hint still releases its pause');
        await notifier.soufflerPriere(3, () async { await notifier.stop(); });
        expect(verifier.resumes, 2, reason: 'stop during playback must not reopen capture');
        await sub.cancel();
        await notifier.stop();
        notifier.dispose();
        await eventTurn();
        verifier.dispose();
      },
    );
  }

  test(
    'a late identification cannot restart the microphone after stop',
    () async {
      final verifier = PrayerVerifier();
      final notifier = PrayerNotifier(verifier);
      await notifier.startPrayerFollow();
      notifier.fatiha();
      verifier.losses.add(0);
      await eventTurn();
      final late = verifier.identify!;
      await notifier.stop();
      final stops = verifier.stops;
      final verses = await QuranApi.fetchVerses(112);
      await late(verses.map((v) => v.textUthmani).join(' '));
      expect(notifier.state.status, RecitationStatus.finished);
      expect(verifier.starts, 1);
      expect(verifier.stops, stops);
      expect(verifier.identify, isNull);
      notifier.dispose();
      await eventTurn();
      verifier.dispose();
    },
  );
}
