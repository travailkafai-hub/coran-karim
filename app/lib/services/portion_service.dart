import '../models/verse.dart';
import '../providers/app_settings_provider.dart' show PortionGranularity;
import 'quran_api.dart';
import 'recitation_verifier.dart' show ArabicNormalizer;

/// Calcule à quelle PORTION de suivi permanent (Coach) appartient un verset --
/// une sourate entière si elle tient dans un seul Hizb, sinon une tranche de
/// Hizb ou demi-Hizb selon [PortionGranularity] (réglage utilisateur, cf.
/// `app_settings_provider.dart`). Jamais deux sourates dans la même portion
/// (décision utilisateur 2026-08-08).
///
/// Entièrement dérivé de données LOCALES déjà chargées par `QuranApi`
/// (`hizb_number`/`rub_el_hizb_number` de `assets/data/quran_verses.json`) --
/// aucun appel réseau, aucun état à maintenir ici.
class PortionInfo {
  final String unitKey;
  final String label;
  final int firstAyah;
  final int lastAyah;
  final int wordsTotal;

  const PortionInfo({
    required this.unitKey,
    required this.label,
    required this.firstAyah,
    required this.lastAyah,
    required this.wordsTotal,
  });
}

class PortionService {
  PortionService._();

  /// Indice du demi-Hizb (1 ou 2) À L'INTÉRIEUR d'un Hizb -- `rub_el_hizb_number`
  /// est numéroté globalement (1-240, 4 par Hizb) : les rub' 1-2 d'un Hizb
  /// forment sa première moitié, 3-4 la seconde.
  static int _demiHizbDansHizb(int rubElHizbNumber) {
    final rubDansHizb = ((rubElHizbNumber - 1) % 4) + 1; // 1..4
    return rubDansHizb <= 2 ? 1 : 2;
  }

  static Future<PortionInfo> resolve({
    required Verse verse,
    required PortionGranularity granularity,
  }) async {
    final tousLesVersets = await QuranApi.fetchVerses(verse.surahNumber);
    final surahs = await QuranApi.fetchSurahs();
    final surahName = surahs
        .cast<Surah?>()
        .firstWhere((s) => s!.number == verse.surahNumber, orElse: () => null)
        ?.nameSimple ??
        'Sourate ${verse.surahNumber}';

    // Une sourate tient dans un seul Hizb si son premier et son dernier
    // verset partagent le même hizb_number -- pas de découpe possible ni
    // nécessaire dans ce cas, quel que soit le réglage de granularité.
    final premierHizb =
        tousLesVersets.isEmpty ? null : tousLesVersets.first.hizbNumber;
    final dernierHizb =
        tousLesVersets.isEmpty ? null : tousLesVersets.last.hizbNumber;
    final uneSeuleTranche = premierHizb == null ||
        dernierHizb == null ||
        premierHizb == dernierHizb;

    List<Verse> versetsDeLaPortion;
    String unitKey;
    String label;
    if (uneSeuleTranche) {
      versetsDeLaPortion = tousLesVersets;
      unitKey = 's${verse.surahNumber}';
      label = surahName;
    } else if (granularity == PortionGranularity.rubElHizb) {
      // ── LE QUART DE HIZB (2026-08-13) ──────────────────────────────────
      // « C'est ce qui est souvent utilisé pour la mémorisation »
      // (utilisateur). `rub_el_hizb_number` est numéroté GLOBALEMENT sur tout
      // le Coran (1-240, quatre par Hizb) : il identifie donc déjà le quart à
      // lui seul, sans avoir à le croiser avec le Hizb.
      final rub = verse.rubElHizbNumber;
      final h = verse.hizbNumber;
      versetsDeLaPortion = rub == null
          ? tousLesVersets.where((v) => v.hizbNumber == h).toList()
          : tousLesVersets.where((v) => v.rubElHizbNumber == rub).toList();
      unitKey = rub == null ? 's${verse.surahNumber}h$h'
                            : 's${verse.surahNumber}r$rub';
      // Rang du quart DANS son Hizb (1 à 4) : c'est ainsi qu'on le nomme en
      // pratique, pas par son numéro global qui ne parle à personne.
      final rangDansHizb = rub == null ? null : ((rub - 1) % 4) + 1;
      label = rangDansHizb == null
          ? '$surahName · Hizb $h'
          : '$surahName · Hizb $h — quart $rangDansHizb/4';
    } else if (granularity == PortionGranularity.hizb) {
      final h = verse.hizbNumber;
      versetsDeLaPortion =
          tousLesVersets.where((v) => v.hizbNumber == h).toList();
      unitKey = 's${verse.surahNumber}h$h';
      label = '$surahName · Hizb $h';
    } else {
      final h = verse.hizbNumber;
      final demi = verse.rubElHizbNumber == null
          ? 1
          : _demiHizbDansHizb(verse.rubElHizbNumber!);
      versetsDeLaPortion = tousLesVersets
          .where((v) =>
              v.hizbNumber == h &&
              (v.rubElHizbNumber == null
                  ? true
                  : _demiHizbDansHizb(v.rubElHizbNumber!) == demi))
          .toList();
      unitKey = 's${verse.surahNumber}h${h}d$demi';
      label =
          '$surahName · Hizb $h (${demi == 1 ? "1re" : "2e"} moitié)';
    }

    if (versetsDeLaPortion.isEmpty) versetsDeLaPortion = [verse];
    // ── LA BISMILLAH SORT DU TOTAL (2026-08-11, décision utilisateur : « les
    // mots Bismillah exclus carrément du comptage ») ──────────────────────
    //
    // Elle n'est JAMAIS jugée (décision 2026-07-20) : la compter au
    // dénominateur rendait 100 % inatteignable sur Al-Fatiha -- 4 mots sur 29
    // impossibles à valider quoi que fasse le récitateur, soit 83 % maximum
    // avec zéro faute (constat utilisateur, mesuré sur sa session du
    // 2026-08-11). Même principe que `_compterMots` côté session : « un mot
    // que le produit a explicitement choisi de ne jamais juger n'est ni un
    // succès ni un échec ».
    //
    // SEULE AL-FATIHA est concernée : ailleurs la Bismillah n'appartient pas
    // au texte du verset (elle est insérée à l'affichage par `_buildChunk`,
    // cf. karaoke_recitation_screen), donc elle n'a jamais été dans ce total.
    // Ici elle EST le verset 1:1, d'où ce cas particulier explicite.
    final wordsTotal = versetsDeLaPortion.fold<int>(0, (sum, v) {
      if (v.surahNumber == 1 && v.ayahNumber == 1) return sum;
      return sum + ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
    });

    return PortionInfo(
      unitKey: unitKey,
      label: label,
      firstAyah: versetsDeLaPortion.first.ayahNumber,
      lastAyah: versetsDeLaPortion.last.ayahNumber,
      wordsTotal: wordsTotal,
    );
  }
}
