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

  /// Ce recitateur a-t-il une recitation chez quran.com ?
  ///
  /// ── POURQUOI CE N'EST PLUS « EST-IL WARSH ? » (2026-09-05) ──────────────
  ///
  /// Deux choses avaient ete confondues parce qu'elles coincidaient : la
  /// riwaya, et le fait d'avoir des URL et des segments mot-a-mot chez
  /// quran.com. C'etait vrai tant que les SEULS recitateurs hors quran.com
  /// etaient les deux Warsh. Ayman Suwaid (Hafs, mais absent de quran.com)
  /// casse cette coincidence : teste sur la riwaya, il serait parti chercher
  /// des segments pour un identifiant que quran.com ne connait pas, et
  /// n'aurait produit aucun son du tout.
  ///
  /// `id` porte l'information depuis toujours : positif = identifiant de
  /// recitation quran.com, negatif = source everyayah seule.
  bool get aSegmentsQuranCom => id > 0;

  /// « Hafs » / « Warsh », pour l'afficher a cote du nom -- demande
  /// utilisateur 2026-09-05 : savoir de quelle riwaya on ecoute AVANT de
  /// choisir. Jusqu'ici la liste etait filtree par riwaya sans jamais le dire.
  String get libelleRiwaya => riwaya == Riwaya.warsh ? 'Warsh' : 'Hafs';

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
  // ── Hafs 'an 'Asim ──
  //
  // ── LA LISTE S'ROUVRE (2026-09-05) ────────────────────────────────────
  //
  // Demande utilisateur : « rajoute d'autres recitateurs, en proposant si
  // c'est du Warsh ou du Hafs, et si on a l'info tajwid ou tartil ».
  //
  // Elle avait ete reduite a un seul recitateur (cf. le bloc mono-recitateur
  // plus haut, dont l'argument reste valable : ne pas multiplier les sources).
  // Ce qui change n'est pas l'argument mais le perimetre : ces onze-la ne sont
  // PAS une source de plus. Ils sont les recitations que quran.com sert deja,
  // celles dont l'app sait deja tirer les URL ET les segments mot-a-mot --
  // exactement le chemin d'Al-Afasy, avec un identifiant different.
  //
  // Identifiants releves le 2026-09-05 sur
  // `api.quran.com/api/v4/resources/recitations` (12 recitations, toutes
  // Hafs) -- pas recopies de memoire.
  //
  // COUVERTURE VERIFIEE, meme protocole qu'en aout pour le Warsh : dernier
  // verset des sourates 1, 2, 3, 18, 36, 55, 78, 110 et 114 chez everyayah,
  // 9/9 present pour chacun des dossiers ci-dessous. C'est ce test qui avait
  // ecarte `warsh_Abdul_Basit_128kbps` (5/9) -- il est toujours a 5/9,
  // toujours ecarte.
  //
  // LE STYLE EST UNE INFORMATION, PAS UNE ETIQUETTE. `Murattal` est le tartil
  // -- la recitation mesuree, celle qu'on suit pour apprendre ; `Mujawwad` est
  // la recitation ornee, plus lente et plus melodique ; `Mu'allim` est
  // l'enseignement : le recitateur detache et repete pour faire entendre les
  // regles. Les trois ne servent pas au meme travail, d'ou l'affichage.
  Reciter(id: 7,  nameAr: 'مشاري العفاسي',      nameFr: 'Mishary Al-Afasy',       style: 'Murattal', everyayahDir: 'Alafasy_128kbps'),
  Reciter(id: 2,  nameAr: 'عبد الباسط عبد الصمد', nameFr: 'Abdul Basit Abdus-Samad', style: 'Murattal', everyayahDir: 'Abdul_Basit_Murattal_64kbps'),
  Reciter(id: 1,  nameAr: 'عبد الباسط عبد الصمد', nameFr: 'Abdul Basit Abdus-Samad', style: 'Mujawwad', everyayahDir: 'Abdul_Basit_Mujawwad_128kbps'),
  Reciter(id: 3,  nameAr: 'عبد الرحمن السديس',  nameFr: 'Abdur-Rahman As-Sudais', style: 'Murattal', everyayahDir: 'Abdurrahmaan_As-Sudais_192kbps'),
  Reciter(id: 4,  nameAr: 'أبو بكر الشاطري',     nameFr: 'Abu Bakr Ash-Shatri',    style: 'Murattal', everyayahDir: 'Abu_Bakr_Ash-Shaatree_128kbps'),
  Reciter(id: 5,  nameAr: 'هاني الرفاعي',        nameFr: 'Hani Ar-Rifai',          style: 'Murattal', everyayahDir: 'Hani_Rifai_192kbps'),
  Reciter(id: 6,  nameAr: 'محمود خليل الحصري',   nameFr: 'Mahmoud Khalil Al-Husary', style: 'Murattal', everyayahDir: 'Husary_128kbps'),
  // Le « Mu'allim » du Husary est la recitation d'enseignement : phrase par
  // phrase, articulee pour etre repetee apres lui.
  Reciter(id: 12, nameAr: 'محمود خليل الحصري',   nameFr: 'Mahmoud Khalil Al-Husary', style: "Mu'allim", everyayahDir: 'Husary_Muallim_128kbps'),
  Reciter(id: 9,  nameAr: 'محمد صديق المنشاوي',  nameFr: 'Mohamed Siddiq Al-Minshawi', style: 'Murattal', everyayahDir: 'Minshawy_Murattal_128kbps'),
  Reciter(id: 8,  nameAr: 'محمد صديق المنشاوي',  nameFr: 'Mohamed Siddiq Al-Minshawi', style: 'Mujawwad', everyayahDir: 'Minshawy_Mujawwad_192kbps'),
  Reciter(id: 10, nameAr: 'سعود الشريم',         nameFr: 'Saoud Ash-Shuraim',      style: 'Murattal', everyayahDir: 'Saood_ash-Shuraym_128kbps'),
  Reciter(id: 11, nameAr: 'محمد الطبلاوي',       nameFr: 'Mohamed Al-Tablawi',     style: 'Murattal', everyayahDir: 'Mohammad_al_Tablaway_128kbps'),

  // ── Hafs, mais HORS quran.com ──
  //
  // Ayman Suwaid est LA recitation d'enseignement du tajwid : il detache les
  // regles pour les faire entendre. C'est precisement ce que l'utilisateur
  // demandait (« si on a l'info tajwid ou tartil »), et aucune des douze
  // recitations quran.com ne l'offre.
  //
  // Identifiant NEGATIF : quran.com ne le sert pas. L'app prend donc pour lui
  // le chemin everyayah -- URL deduite, decoupe mot-a-mot ESTIMEE -- celui
  // ouvert pour le Warsh en aout. Consequence a connaitre : sur une
  // correction mot a mot, l'extrait est estime et non mesure, comme en Warsh.
  Reciter(id: -3, nameAr: 'أيمن سويد',           nameFr: 'Ayman Suwaid',           style: "Mu'allim", everyayahDir: 'Ayman_Sowaid_64kbps'),

  // ── TROIS MUJAWWAD DE PLUS (2026-09-05) ────────────────────────────────
  //
  // Constat utilisateur : « pour les recitateurs, il n'y a pas assez de
  // mujawwad ». C'est vrai, et c'etait une limite de la SOURCE : sur les douze
  // recitations que publie quran.com, deux seulement sont en mujawwad
  // (AbdulBaset et Minshawi). Rien a corriger de ce cote.
  //
  // Le chemin ouvert pour Ayman Suwaid leve la contrainte : un recitateur sans
  // identifiant quran.com est desormais servi par everyayah, avec une decoupe
  // mot-a-mot ESTIMEE au lieu de mesuree (meme regime que le Warsh depuis
  // aout). C'est le prix, et il ne se paie que sur la correction d'un mot --
  // l'ecoute, elle, est identique.
  //
  // Couverture verifiee au meme protocole (dernier verset des sourates 1, 2,
  // 3, 18, 36, 55, 78, 110, 114) : 9/9 pour les trois. Deux candidats ont ete
  // ECARTES par ce meme test, a 0/9 : `Mostafa_Ismaeel_128kbps` et
  // `Mohammad_Ayyoub_128kbps` -- les dossiers n'existent pas sous ces noms.
  Reciter(id: -4, nameAr: 'محمود خليل الحصري',   nameFr: 'Mahmoud Khalil Al-Husary', style: 'Mujawwad', everyayahDir: 'Husary_Mujawwad_64kbps'),
  Reciter(id: -5, nameAr: 'محمود علي البنا',     nameFr: 'Mahmoud Ali Al-Banna',   style: 'Mujawwad', everyayahDir: 'Mahmoud_Ali_Al_Banna_32kbps'),
  Reciter(id: -6, nameAr: 'علي حجاج السويسي',    nameFr: 'Ali Hajjaj Al-Suesy',    style: 'Mujawwad', everyayahDir: 'Ali_Hajjaj_AlSuesy_128kbps'),
  // Murattal, mais absent de quran.com -- il elargit la liste sans doublon.
  Reciter(id: -7, nameAr: 'عبد الله المطرود',    nameFr: 'Abdullah Al-Matroud',    style: 'Murattal', everyayahDir: 'Abdullah_Matroud_128kbps'),

  // ── CINQ MUJAWWAD SERVIS PAR MP3QURAN (2026-09-05) ─────────────────────
  //
  // Ceux-la ne passent NI par quran.com NI par everyayah : ils sont servis par
  // MP3Quran, sourate entiere plus minutage par verset -- le chemin d'Afasy,
  // deja eprouve depuis aout. Voir `Mp3QuranApi._servis` pour la table, le
  // protocole de verification en deux requetes, et pourquoi way2quran a ete
  // explore puis ecarte (aucun minutage publie).
  //
  // `everyayahDir` reste rempli : il ne sert pas pour ceux-ci (aucun de ces
  // dossiers n'existe chez everyayah) mais le champ est requis, et le laisser
  // vide ferait construire des URL `everyayah.com/data//001001.mp3` si un
  // futur chemin oubliait de tester la source. Un dossier nomme mais inutilise
  // est moins dangereux qu'une URL a moitie formee.
  Reciter(id: -8,  nameAr: 'ماهر المعيقلي',      nameFr: 'Maher Al-Muaiqly',       style: 'Mujawwad', everyayahDir: 'mp3quran/maher-mojawwad'),
  Reciter(id: -9,  nameAr: 'محمود خليل الحصري',  nameFr: 'Mahmoud Khalil Al-Husary', style: 'Mujawwad', everyayahDir: 'mp3quran/husr-mojawwad'),
  Reciter(id: -10, nameAr: 'محمود علي البنا',    nameFr: 'Mahmoud Ali Al-Banna',   style: 'Mujawwad', everyayahDir: 'mp3quran/bna-mojawwad'),
  Reciter(id: -11, nameAr: 'مصطفى إسماعيل',      nameFr: 'Mustafa Ismail',         style: 'Mujawwad', everyayahDir: 'mp3quran/mustafa-mojawwad'),
  Reciter(id: -12, nameAr: 'عبد الباسط عبد الصمد', nameFr: 'Abdul Basit Abdus-Samad', style: 'Mujawwad', everyayahDir: 'mp3quran/basit-mojawwad'),

  // ── Warsh 'an Nafi' (2026-08-12) ──
  // Les deux seuls récitateurs Warsh dont everyayah a le Coran COMPLET :
  // couverture vérifiée sur le dernier verset des sourates 1, 2, 3, 18, 36,
  // 55, 78, 110 et 114 (9/9 présents pour chacun). Le troisième que le site
  // liste, `warsh_Abdul_Basit_128kbps`, est incomplet (5/9) -- écarté tant
  // qu'un mot manquant sur une correction reste possible.
  Reciter(id: -1, nameAr: 'إبراهيم الدوسري',    nameFr: 'Ibrahim Al-Dosary',      style: 'Murattal', everyayahDir: 'warsh/warsh_ibrahim_aldosary_128kbps', riwaya: Riwaya.warsh),
  Reciter(id: -2, nameAr: 'ياسين الجزائري',     nameFr: 'Yassin Al-Jazaery',      style: 'Murattal', everyayahDir: 'warsh/warsh_yassin_al_jazaery_64kbps',  riwaya: Riwaya.warsh),
  // Warsh servi par MP3Quran, avec minutage -- le premier Warsh a en avoir un
  // (les deux ci-dessus passent par everyayah et une decoupe ESTIMEE).
  Reciter(id: -13, nameAr: 'محمود خليل الحصري',  nameFr: 'Mahmoud Khalil Al-Husary', style: 'Murattal', everyayahDir: 'mp3quran/husr-warsh', riwaya: Riwaya.warsh),
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
