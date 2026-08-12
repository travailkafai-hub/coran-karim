import 'riwaya.dart';

class Reciter {
  final int id;          // quran.com recitation ID
  final String nameAr;
  final String nameFr;
  final String style;    // Murattal / Mujawwad

  /// Riwāya récitée. Les récitateurs historiques de l'app sont tous en Hafs ;
  /// les récitateurs Warsh (2026-08-12) portent `Riwaya.warsh` et ne sont
  /// proposés qu'en mode Warsh (cf. [pour]).
  final Riwaya riwaya;

  /// Dossier everyayah (`everyayah.com/data/<dossier>/SSSAAA.mp3`).
  ///
  /// SEULE source d'audio verset par verset pour le Warsh (vérifié le
  /// 2026-08-12 : l'API quran.com ne sert que du Hafs, aucune de ses éditions
  /// n'est en Warsh), et elle nomme ses fichiers avec les mêmes numéros de
  /// verset que le reste de l'app -- `002286.mp3` existe et dure 75,8 s. Les
  /// récitateurs Hafs en ont un aussi : décision utilisateur 2026-08-12
  /// « ça sert à rien de multiplier les sources », everyayah devient LA
  /// source audio des deux riwāyāt.
  final String everyayahDir;

  const Reciter({
    required this.id,
    required this.nameAr,
    required this.nameFr,
    required this.style,
    required this.everyayahDir,
    this.riwaya = Riwaya.hafs,
  });

  /// URL du verset chez everyayah. `surah`/`ayah` sont les numéros déjà
  /// utilisés partout dans l'app -- rien à convertir.
  String urlVerset(int surah, int ayah) =>
      'https://everyayah.com/data/$everyayahDir/'
      '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';

  /// Les récitateurs proposés pour une riwāya donnée. Jamais de mélange : un
  /// récitateur Hafs sur du texte Warsh ferait entendre autre chose que ce qui
  /// est affiché, et en correction d'erreur ferait apprendre la mauvaise
  /// prononciation.
  static List<Reciter> pour(Riwaya r) =>
      kReciters.where((x) => x.riwaya == r).toList();

  static Reciter defautPour(Riwaya r) =>
      r == Riwaya.warsh ? kDefaultReciterWarsh : kDefaultReciter;

  @override
  bool operator ==(Object other) => other is Reciter && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

// ── RECITATEURS ────────────────────────────────────────────────────────────
// `id` = identifiant de récitation quran.com, conservé tel quel pour le Hafs
// (il sert encore aux timings mot-à-mot, `QuranApi.fetchAyahSegments`, que
// everyayah ne fournit pas). Les récitateurs Warsh n'existent pas chez
// quran.com : ils reçoivent des id négatifs, jamais envoyés à cette API.
//
// ⚠️ Les noms Hafs ci-dessous sont ceux d'origine de l'app. Un contrôle du
// 2026-08-12 (URL audio réellement renvoyée par quran.com pour chaque id)
// montre que six de ces associations id -> nom sont fausses (id=5 est Hani
// ar-Rifai et non Ash-Shaatree, id=9 Minshawi et non Al-Husary, etc.).
// Défaut préexistant, volontairement NON corrigé ici pour ne pas mêler deux
// sujets : le corriger changerait la voix entendue par les utilisateurs
// actuels. Cf. ANALYSE_WARSH.md §6.
const kReciters = [
  // ── Hafs 'an 'Asim ──
  Reciter(id: 7,  nameAr: 'مشاري العفاسي',      nameFr: 'Mishary Al-Afasy',       style: 'Murattal', everyayahDir: 'Alafasy_128kbps'),
  Reciter(id: 1,  nameAr: 'عبد الباسط — مرتّل', nameFr: 'Abdul Basit (Murattal)', style: 'Murattal', everyayahDir: 'Abdul_Basit_Murattal_192kbps'),
  Reciter(id: 2,  nameAr: 'عبد الباسط — مجوّد', nameFr: 'Abdul Basit (Mujawwad)', style: 'Mujawwad', everyayahDir: 'Abdul_Basit_Mujawwad_128kbps'),
  Reciter(id: 9,  nameAr: 'محمود خليل الحصري',  nameFr: 'Al-Husary',              style: 'Murattal', everyayahDir: 'Husary_128kbps'),
  Reciter(id: 5,  nameAr: 'أبو بكر الشاطري',    nameFr: 'Abu Bakr Ash-Shaatree',  style: 'Murattal', everyayahDir: 'Abu_Bakr_Ash-Shaatree_128kbps'),
  Reciter(id: 10, nameAr: 'ناصر القطامي',        nameFr: 'Nasser Al-Qatami',       style: 'Murattal', everyayahDir: 'Nasser_Alqatami_128kbps'),
  Reciter(id: 12, nameAr: 'محمد أيوب',          nameFr: 'Muhammad Ayyoub',        style: 'Murattal', everyayahDir: 'Muhammad_Ayyoub_128kbps'),
  Reciter(id: 11, nameAr: 'عبدالرحمن السديس',   nameFr: 'Al-Sudais',              style: 'Murattal', everyayahDir: 'Abdurrahmaan_As-Sudais_192kbps'),

  // ── Warsh 'an Nafi' (2026-08-12) ──
  // Les deux seuls récitateurs Warsh dont everyayah a le Coran COMPLET :
  // couverture vérifiée sur le dernier verset des sourates 1, 2, 3, 18, 36,
  // 55, 78, 110 et 114 (9/9 présents pour chacun). Le troisième que le site
  // liste, `warsh_Abdul_Basit_128kbps`, est incomplet (5/9) -- écarté tant
  // qu'un mot manquant sur une correction reste possible.
  Reciter(id: -1, nameAr: 'إبراهيم الدوسري',    nameFr: 'Ibrahim Al-Dosary',      style: 'Murattal', everyayahDir: 'warsh/warsh_ibrahim_aldosary_128kbps', riwaya: Riwaya.warsh),
  Reciter(id: -2, nameAr: 'ياسين الجزائري',     nameFr: 'Yassin Al-Jazaery',      style: 'Murattal', everyayahDir: 'warsh/warsh_yassin_al_jazaery_64kbps',  riwaya: Riwaya.warsh),
];

const kDefaultReciter = Reciter(
    id: 7,
    nameAr: 'مشاري العفاسي',
    nameFr: 'Mishary Al-Afasy',
    style: 'Murattal',
    everyayahDir: 'Alafasy_128kbps');

const kDefaultReciterWarsh = Reciter(
    id: -1,
    nameAr: 'إبراهيم الدوسري',
    nameFr: 'Ibrahim Al-Dosary',
    style: 'Murattal',
    everyayahDir: 'warsh/warsh_ibrahim_aldosary_128kbps',
    riwaya: Riwaya.warsh);
