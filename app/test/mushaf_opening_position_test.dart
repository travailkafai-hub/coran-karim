import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/services/mushaf_opening_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('A fresh installation has no saved paper page', () async {
    expect(await MushafOpeningPosition.read(Riwaya.hafs, null), isNull);
  });

  test('Hafs and Warsh paper positions remain separate', () async {
    await MushafOpeningPosition.save(Riwaya.hafs, 22, (2, 142));
    await MushafOpeningPosition.save(Riwaya.warsh, 37, (2, 142));
    expect(await MushafOpeningPosition.read(Riwaya.hafs, (2, 142)), 22);
    expect(await MushafOpeningPosition.read(Riwaya.warsh, (2, 142)), 37);
  });

  test('A later normal-reader position supersedes the paper page', () async {
    await MushafOpeningPosition.save(Riwaya.hafs, 604, (1, 1));
    expect(await MushafOpeningPosition.read(Riwaya.hafs, (2, 10)), isNull);
  });

  test('Paper reading works before any normal-reader visit', () async {
    await MushafOpeningPosition.save(Riwaya.warsh, 3, null);
    expect(await MushafOpeningPosition.read(Riwaya.warsh, null), 3);
    expect(await MushafOpeningPosition.read(Riwaya.hafs, null), isNull);
  });

  test('Last page and first page both persist', () async {
    for (final page in [604, 1]) {
      await MushafOpeningPosition.save(Riwaya.hafs, page, null);
      expect(await MushafOpeningPosition.read(Riwaya.hafs, null), page);
    }
  });

  test('Saving an invalid page leaves the last valid page intact', () async {
    await MushafOpeningPosition.save(Riwaya.hafs, 100, null);
    await MushafOpeningPosition.save(Riwaya.hafs, 0, null);
    await MushafOpeningPosition.save(Riwaya.hafs, 605, null);
    expect(await MushafOpeningPosition.read(Riwaya.hafs, null), 100);
  });

  test(
    'Corrupt, wrong-type and future-version preferences are ignored',
    () async {
      for (final raw in [
        3,
        'not json',
        'null',
        '[]',
        '{"version":2,"page":3}',
        '{"version":1,"page":0}',
        '{"version":1,"page":605}',
        '{"version":1,"page":3.5}',
        '{"version":1,"page":"3"}',
      ]) {
        SharedPreferences.setMockInitialValues({
          'mushaf_opening_page_hafs': raw,
        });
        expect(await MushafOpeningPosition.read(Riwaya.hafs, null), isNull);
      }
    },
  );

  test(
    'Saving paper page does not alter legacy position or manual bookmark',
    () async {
      SharedPreferences.setMockInitialValues({
        'derniere_lecture_sourate': 2,
        'derniere_lecture_verset': 12,
        'marque_pages': ['2:12'],
        'riwaya': 'warsh',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      await MushafOpeningPosition.save(Riwaya.warsh, 603, (2, 12));
      for (final entry in before.entries) {
        expect(prefs.get(entry.key), entry.value);
      }
    },
  );
}
