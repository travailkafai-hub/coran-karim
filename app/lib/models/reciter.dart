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

// ── DEUX RAISONNEMENTS QUI SE COMPLETENT (fusion du 2026-08-21) ────────────
//
// Cette liste a ete reduite d'un cote et etendue de l'autre, sur deux
// branches, pour deux raisons TOUTES LES DEUX valables. Le detail de chacune
// est conserve ci-dessous : les effacer ferait perdre pourquoi la liste a
// cette forme, et un futur agent la « simplifierait » dans un sens ou dans
// l'autre.
//
//  - Cote Hafs : l'app est passee MONO-RECITATEUR parce que seul Al-Afasy a
//    un chemin de correction audio SANS Quran Foundation.
//  - Cote Warsh : deux recitateurs ont ete ajoutes parce que le Warsh
//    n'existe pas chez quran.com et se sert depuis everyayah.
//
// Les deux tiennent ensemble : le Hafs passe par MP3Quran, le Warsh par
// everyayah. Aucun des deux ne depend de Quran Foundation, qui est ce que
// les deux chantiers cherchaient a supprimer.

// ── CE QUI JUSTIFIE LE MONO-RECITATEUR EN HAFS (2026-08-16) ────────────────
// Seul Al-Afasy dispose d'un chemin de lecture et de correction audio SANS
// dépendance à Quran Foundation (audio MP3Quran + `word_segments_mp3quran_afasy.json`
// précalculé, cf. AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md §3bis). Les 7
// autres récitateurs Hafs retomberaient sur l'ancien chemin quran.com/QF pour
// `WordCorrectionAudio` -- exactement la dépendance que ce chantier existe à
// supprimer -- donc retirés de la sélection tant que leur propre jeu de
// données n'est pas généré.
//
// IDs MP3Quran déjà vérifiés (reciter/moshaf, empiriquement via
// /ayat_timing, PAS supposés -- cf. §3ter de l'audit) pour la suite quand la
// demande se présentera : Al-Husary 118, Muhammad Ayyoub 109, Ash-Shaatree
// 4, Abdul Basit Murattal 53 (PIÈGE : != son reciter_id 51, qui pointe le
// Mujawwad 51), Al-Sudais 54, Nasser Al-Qatami 86. Remettre l'entrée
// correspondante ci-dessous une fois `preparer_corpus_mp3quran.py` +
// `generer_predictions_mp3quran.py` rejoués pour ce récitateur et son JSON
// embarqué/hébergé.
//
// ⚠️ MP3Quran sert AUSSI le Warsh (riwaya 2 de son API, verifie le
// 2026-08-21 : 13 recitateurs, dont Abdul Basit id=51 moshaf=52 avec les 114
// sourates). Y passer donnerait au Warsh le meme chemin qu'au Hafs -- mais
// exige un `word_segments` Warsh, qui n'existe pas : celui d'aujourd'hui est
// cale sur Al-Afasy ET sur le texte Hafs. Tant qu'il manque, le Warsh reste
// sur everyayah ci-dessous, ou la correction mot-a-mot n'est pas disponible
// mais l'ecoute l'est.

// ── RECITATEURS ────────────────────────────────────────────────────────────
// `id` = identifiant de récitation quran.com, conservé tel quel pour le Hafs
// (il sert encore aux timings mot-à-mot, `QuranApi.fetchAyahSegments`, que
// everyayah ne fournit pas). Les récitateurs Warsh n'existent pas chez
// quran.com : ils reçoivent des id négatifs, jamais envoyés à cette API.
//
// ⚠️ Les noms Hafs sont ceux d'origine de l'app. Un contrôle du 2026-08-12
// (URL audio réellement renvoyée par quran.com pour chaque id) montre que six
// de ces associations id -> nom sont fausses (id=5 est Hani ar-Rifai et non
// Ash-Shaatree, id=9 Minshawi et non Al-Husary, etc.). Défaut préexistant,
// volontairement NON corrigé ici pour ne pas mêler deux sujets : le corriger
// changerait la voix entendue par les utilisateurs actuels. Cf.
// ANALYSE_WARSH.md §6.
const kReciters = [
  // ── Hafs 'an 'Asim ── (un seul, cf. le bloc mono-recitateur ci-dessus)
  Reciter(id: 7,  nameAr: 'مشاري العفاسي',      nameFr: 'Mishary Al-Afasy',       style: 'Murattal', everyayahDir: 'Alafasy_128kbps'),

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
