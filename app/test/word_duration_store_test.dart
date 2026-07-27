import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:coran_karim/services/word_duration_store.dart';

/// Redirige getApplicationSupportDirectory() vers un dossier temporaire.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  late Directory tmp;
  late File store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('word_durations_test');
    store = File('${tmp.path}/word_durations.json');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    // Le magasin est un singleton : on remet son état à zéro entre les tests
    // en rechargeant depuis un dossier neuf.
    WordDurationStore.debugReset();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('garde le MINIMUM observé, pas la dernière valeur', () async {
    final s = WordDurationStore.instance;
    await s.ensureLoaded();

    s.record('مَـٰلِكِ', 12);
    expect(s.minFramesFor('مَـٰلِكِ'), 12);

    // Une durée PLUS LONGUE ne doit pas remplacer le minimum : un plancher est
    // une borne inférieure.
    s.record('مَـٰلِكِ', 20);
    expect(s.minFramesFor('مَـٰلِكِ'), 12);

    // Une durée plus courte, elle, abaisse le plancher.
    s.record('مَـٰلِكِ', 7);
    expect(s.minFramesFor('مَـٰلِكِ'), 7);
  });

  test('ignore les durées nulles ou négatives', () async {
    final s = WordDurationStore.instance;
    await s.ensureLoaded();

    // Un mot sans frame n'a pas été prononcé dans cet audio : ne rien apprendre.
    s.record('يَوْمِ', 0);
    expect(s.minFramesFor('يَوْمِ'), isNull);
    s.record('يَوْمِ', -3);
    expect(s.minFramesFor('يَوْمِ'), isNull);
  });

  test('un mot jamais vu ne renvoie aucun plancher (repli sur quran.com)',
      () async {
    final s = WordDurationStore.instance;
    await s.ensureLoaded();
    expect(s.minFramesFor('ٱلرَّحِيمِ'), isNull);
  });

  test('n apprend rien avant ensureLoaded (evite d ecraser le fichier)',
      () async {
    final s = WordDurationStore.instance;
    s.record('نَعْبُدُ', 9);
    expect(s.minFramesFor('نَعْبُدُ'), isNull);
  });

  test('flush écrit sur disque et le contenu est relu au chargement suivant',
      () async {
    final s = WordDurationStore.instance;
    await s.ensureLoaded();
    s.record('ٱلصِّرَٰطَ', 15);
    await s.flush();

    expect(await store.exists(), isTrue);
    final data = jsonDecode(await store.readAsString()) as Map<String, dynamic>;
    expect(data['ٱلصِّرَٰطَ'], 15);

    // Rechargement : la durée apprise survit à la session.
    WordDurationStore.debugReset();
    await WordDurationStore.instance.ensureLoaded();
    expect(WordDurationStore.instance.minFramesFor('ٱلصِّرَٰطَ'), 15);
  });

  test('flush sans modification n écrit pas de fichier', () async {
    final s = WordDurationStore.instance;
    await s.ensureLoaded();
    await s.flush();
    expect(await store.exists(), isFalse);
  });

  test('un fichier corrompu ne bloque pas : magasin vide', () async {
    await store.writeAsString('{ ceci n est pas du json');
    WordDurationStore.debugReset();
    final s = WordDurationStore.instance;
    await s.ensureLoaded();
    expect(s.learnedWordCount, 0);
    expect(s.minFramesFor('مَـٰلِكِ'), isNull);
  });
}
