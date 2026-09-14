import 'package:flutter/widgets.dart' show Locale;

import '../l10n/app_localizations.dart';
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

  /// Reconstruit le libellé localisé à partir du SEUL `unitKey` -- utilisé à
  /// la fois par [resolve] (ci-dessous) et par la re-localisation des
  /// libellés déjà enregistrés en base (cf. `relabelFromStored`).
  ///
  /// ── POURQUOI CETTE FONCTION EXISTE À PART (2026-09-13) ──────────────────
  ///
  /// Constat utilisateur : « la liste dans مدرّبي [Coach] reste en français
  /// alors que c'est [réglé sur] arabe ». Cause : `SessionArchiveService`
  /// ENREGISTRE `label` en base au moment où la portion est touchée (colonne
  /// `portions.label`, cf. `PortionResume.fromMap`) -- un libellé figé au
  /// jour de l'écriture, jamais recalculé. Corriger `resolve()` seul ne
  /// change donc RIEN aux lignes déjà en base, seulement aux futures.
  ///
  /// `unitKey` porte déjà toute l'information structurelle nécessaire pour
  /// reconstruire le libellé SANS red-router par `resolve()` (qui exigerait
  /// un `Verse` et pourrait, avec le réglage de granularité ACTUEL, découper
  /// différemment de ce qui a été enregistré -- un risque qu'on ne veut pas
  /// prendre juste pour rafraîchir un texte) :
  ///   s{N}          -> sourate entière
  ///   s{N}h{H}      -> Hizb entier
  ///   s{N}r{R}      -> quart de Hizb (R = rub_el_hizb_number GLOBAL, 1-240 ;
  ///                    Hizb = ((R-1)~/4)+1, rang dans le Hizb = ((R-1)%4)+1 --
  ///                    pure arithmétique, 4 quarts par Hizb, 60 Hizb au total)
  ///   s{N}h{H}d{D}  -> demi-Hizb (D = 1 ou 2)
  static String labelForUnitKey({
    required String unitKey,
    required String surahName,
    required AppLocalizations t,
  }) {
    final reste = unitKey.replaceFirst(RegExp(r'^s\d+'), '');
    if (reste.isEmpty) return surahName;
    final quart = RegExp(r'^r(\d+)$').firstMatch(reste);
    if (quart != null) {
      final rub = int.parse(quart.group(1)!);
      final hizb = ((rub - 1) ~/ 4) + 1;
      final rang = ((rub - 1) % 4) + 1;
      return t.portionSurahHizbQuarter(surahName, hizb, rang);
    }
    final demiHizb = RegExp(r'^h(\d+)d(\d+)$').firstMatch(reste);
    if (demiHizb != null) {
      final hizb = int.parse(demiHizb.group(1)!);
      final demi = int.parse(demiHizb.group(2)!);
      return t.portionSurahHizbHalf(
          surahName, hizb, demi == 1 ? t.portionHalfFirst : t.portionHalfSecond);
    }
    final hizbSeul = RegExp(r'^h(\d+)$').firstMatch(reste);
    if (hizbSeul != null) {
      return t.portionSurahHizb(surahName, int.parse(hizbSeul.group(1)!));
    }
    // Forme inconnue (ne devrait pas arriver) : repli prudent, jamais de
    // texte tronqué ou d'exception pour un simple affichage.
    return surahName;
  }

  /// Recalcule le libellé localisé d'une portion DÉJÀ ENREGISTRÉE, à partir
  /// des seules données stables qu'elle porte (`surahNumber`, `unitKey`) --
  /// jamais depuis le libellé figé lui-même. Cf. la doc de [labelForUnitKey]
  /// pour le pourquoi. Un seul appel réseau/cache (`QuranApi.fetchSurahs`,
  /// déjà mis en cache par ailleurs), aucune re-résolution de portion.
  static Future<String> relabelFromStored({
    required int surahNumber,
    required String unitKey,
    required Locale locale,
  }) async {
    final t = lookupAppLocalizations(locale);
    final isArabic = locale.languageCode == 'ar';
    final surahs = await QuranApi.fetchSurahs();
    final surah = surahs
        .cast<Surah?>()
        .firstWhere((s) => s!.number == surahNumber, orElse: () => null);
    final surahName = surah == null
        ? t.portionUnknownSurah(surahNumber)
        : (isArabic ? surah.nameArabic : surah.nameSimple);
    return labelForUnitKey(unitKey: unitKey, surahName: surahName, t: t);
  }

  static Future<PortionInfo> resolve({
    required Verse verse,
    required PortionGranularity granularity,
    // ── LIBELLE LOCALISE (2026-09-13) ────────────────────────────────────
    //
    // Constat utilisateur, capture a l'appui (ecran Coach, locale arabe) :
    // « texte en francais alors que je suis en arabe ». Ce libelle etait
    // construit ICI, en dur, en francais (« Hizb », « quart », « moitie »),
    // quelle que soit la locale de l'app -- et le nom de sourate venait
    // TOUJOURS de `nameSimple` (la translitteration latine), jamais de
    // `nameArabic`, contrairement a `_SurahTile` (surah_list_screen.dart)
    // qui applique deja cette distinction correctement.
    //
    // `PortionService` est un service STATIQUE sans `BuildContext` (appele
    // depuis des providers et un service d'archivage qui n'en ont pas) --
    // `AppLocalizations.of(context)` est donc hors de portee ici. La
    // locale seule suffit : `lookupAppLocalizations(locale)` (fonction
    // generee par l10n, cf. app_localizations.dart) construit la meme
    // instance a partir d'une simple `Locale`, sans widget. Chaque appelant
    // (un ecran a un BuildContext, un provider a `appLocaleProvider`) peut
    // fournir cette valeur facilement.
    required Locale locale,
  }) async {
    final t = lookupAppLocalizations(locale);
    final isArabic = locale.languageCode == 'ar';
    final tousLesVersets = await QuranApi.fetchVerses(verse.surahNumber);
    final surahs = await QuranApi.fetchSurahs();
    final surah = surahs
        .cast<Surah?>()
        .firstWhere((s) => s!.number == verse.surahNumber, orElse: () => null);
    final surahName = surah == null
        ? t.portionUnknownSurah(verse.surahNumber)
        : (isArabic ? surah.nameArabic : surah.nameSimple);

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
          ? t.portionSurahHizb(surahName, h ?? 0)
          : t.portionSurahHizbQuarter(surahName, h ?? 0, rangDansHizb);
    } else if (granularity == PortionGranularity.hizb) {
      final h = verse.hizbNumber;
      versetsDeLaPortion =
          tousLesVersets.where((v) => v.hizbNumber == h).toList();
      unitKey = 's${verse.surahNumber}h$h';
      label = t.portionSurahHizb(surahName, h ?? 0);
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
      label = t.portionSurahHizbHalf(surahName, h ?? 0,
          demi == 1 ? t.portionHalfFirst : t.portionHalfSecond);
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
