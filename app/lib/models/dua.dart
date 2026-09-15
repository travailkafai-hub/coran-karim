import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Une invocation (duʿāʾ / dhikr).
///
/// POURQUOI CE MODÈLE A CHANGÉ (2026-07-20) : la première version portait un
/// unique `category` (String) parmi 6 valeurs plates. Ça ne tient pas dès que
/// le catalogue grossit — une même invocation appartient légitimement à
/// plusieurs endroits : le tasbīḥ ×33 est *à la fois* « après la prière » et
/// « dhikr du matin » ; « Rabbanā ātinā » est *à la fois* coranique, dua du
/// ṭawāf et dua de clôture d'assemblée. Avec un seul champ il fallait
/// dupliquer l'entrée (c'était déjà le cas des Muʿawwidhāt, copiées à
/// l'identique en matin ET en soir).
///
/// D'où `tags` : une liste d'identifiants de collections. Une entrée, N points
/// d'entrée. La duplication disparaît, et ajouter un axe de navigation
/// (« ce qu'on dit à Ṣobḥ », « ce qui est recommandé à l'Aïd ») ne demande
/// plus de retoucher les données existantes, seulement d'ajouter un tag.
class Dua {
  final String id;
  final String titleFr;
  final String titleAr;
  final String textAr;
  final String translationFr;

  /// Translittération latine — pour qui ne lit pas encore l'arabe.
  /// Optionnelle : renseignée sur les formules courtes et très utilisées,
  /// pas sur les longs passages (illisible et contre-productif).
  final String? translit;

  final String? source;

  /// Le mérite / le « pourquoi on la dit » rapporté par la tradition.
  /// Affiché repliable : c'est ce qui transforme une liste de textes en
  /// quelque chose qu'on a envie de pratiquer.
  final String? virtue;

  /// Identifiants de collections auxquelles cette invocation appartient.
  final List<String> tags;

  /// Nombre de répétitions recommandé (1 = pas de compteur affiché).
  final int repeat;

  /// Renseignés uniquement pour les duas issues directement d'un verset —
  /// permet de rejouer l'audio réciteur déjà présent dans l'app (pas de
  /// source audio libre trouvée pour les invocations hadith, cf. recherche
  /// 2026-07-10 : aucune API gratuite équivalente à quran.com pour celles-ci).
  /// MISE À JOUR 2026-08-07 : cette conclusion était fausse — cf. `audioUrl`
  /// ci-dessous, trouvé via une recherche renouvelée sur demande utilisateur.
  final int? surahNumber;
  final int? ayahNumber;

  /// Plages de versets à jouer EN SÉQUENCE quand `textAr` couvre plusieurs
  /// versets -- éventuellement de PLUSIEURS sourates différentes (ex. les
  /// trois muʿawwidhāt : Al-Ikhlāṣ 112, Al-Falaq 113, An-Nās 114). Chaque
  /// triplet est `(sourate, premier verset, dernier verset)`, dans l'ordre de
  /// lecture. `surahNumber`/`ayahNumber` restent le point d'entrée affiché
  /// (premier verset de la première plage) ; c'est CE champ qui prévaut pour
  /// construire la playlist de lecture quand il est renseigné.
  ///
  /// BUG CORRIGÉ (2026-08-07, constat utilisateur : « il y a que Qul huwa
  /// Allahu ahad, pas la récitation de toutes les muʿawwidhāt ») : sans ce
  /// champ, `_playAudio` ne savait lire qu'UN SEUL verset (`surahNumber`/
  /// `ayahNumber`), donc uniquement Al-Ikhlāṣ 112:1 pour `muawwidhat` alors
  /// que le texte affiché contient les 15 versets des trois sourates.
  final List<(int, int, int)>? verseRanges;

  /// URL audio directe (MP3, hors Coran) pour les invocations issues des
  /// hadiths. Source : l'API publique de hisnmuslim.com (texte du livre
  /// « Hisn al-Muslim »), appariée au texte de cette entrée par similarité de
  /// mots après vérification manuelle un par un (2026-08-07) — un appariement
  /// automatique seul avait produit de faux positifs sur des formules courtes
  /// réutilisées dans plusieurs chapitres du livre (ex. « لا إله إلا الله »
  /// employé aussi bien comme dhikr complet que comme simple exclamation de
  /// frayeur) ; ces cas ambigus ont été laissés sans audio plutôt que
  /// d'attacher un enregistrement incertain à un texte religieux.
  final String? audioUrl;

  /// Chemin d'un clip AUDIO EMBARQUÉ (asset Flutter, relatif à `assets/`),
  /// prioritaire sur `audioUrl` quand renseigné.
  ///
  /// POURQUOI (2026-08-07) : plusieurs clips de hisnmuslim.com ne sont pas de
  /// simples récitations de la formule — le lecteur y ANNONCE À VOIX HAUTE le
  /// nombre de répétitions (« ثلاث مرات », « سبع مرات »...) en fin
  /// d'enregistrement, une note du livre lue telle quelle. Combiné à la
  /// répétition CÔTÉ APP (`Dua.repeat`), l'utilisateur entendrait cette
  /// annonce répétée N fois — constat utilisateur direct : « il dit répété 3
  /// fois... on va répéter l'audio 3 fois ». Pour `tasbih_fatima`, le clip
  /// complet contenait en plus toute une prière de continuation après le
  /// tasbih (24 s), rejouée 33 fois aurait fait ~13 minutes.
  /// Correctif : ces clips précis ont été découpés (ffmpeg, coupe au silence
  /// qui précède l'annonce/la continuation, fondu de 80 ms pour éviter un
  /// clic) et embarqués dans `assets/audio/duas/` plutôt que retéléchargés à
  /// chaque lecture — seuls quelques clips sont concernés, la très grande
  /// majorité reste en streaming via `audioUrl`.
  final String? audioAsset;

  /// Arrêter la lecture à cette position (ms) au lieu d'aller au bout du
  /// fichier. `null` = lire en entier.
  ///
  /// Onze fichiers de hisnmuslim.com enchaînent la MÊME invocation quatre ou
  /// cinq fois (le tahlīl : 32 s pour cinq occurrences), alors que l'app gère
  /// déjà la répétition elle-même via [repeat].
  ///
  /// La version du 2026-08-09 embarquait des copies DÉCOUPÉES de leurs
  /// fichiers (`assets/audio/duas/*_cut.mp3`). Retirées le 2026-08-10 :
  /// redistribuer une œuvre dérivée d'un enregistrement sans licence était le
  /// risque juridique le plus net de l'app, et une publication en test fermé
  /// reste une distribution.
  ///
  /// Les valeurs ci-dessous ont été mesurées à `ffprobe` sur ces clips avant
  /// leur suppression, + 150 ms de marge pour ne pas avaler la dernière
  /// syllabe. On ne conserve donc qu'une DURÉE — une mesure, pas une œuvre.
  final int? audioCutMs;

  const Dua({
    required this.id,
    required this.titleFr,
    required this.titleAr,
    required this.textAr,
    required this.translationFr,
    this.translit,
    this.source,
    this.virtue,
    required this.tags,
    this.repeat = 1,
    this.surahNumber,
    this.ayahNumber,
    this.verseRanges,
    this.audioUrl,
    this.audioAsset,
    this.audioCutMs,
  });

  bool get isQuranic => surahNumber != null && ayahNumber != null;

  /// Identité stable de la source audio hadith (asset si présent, sinon URL)
  /// -- utilisée comme clé de comparaison par `DuaAudioService`.
  String? get audioKey => audioAsset ?? audioUrl;

  /// Vrai si une écoute est possible, coranique ou non.
  bool get hasAudio => isQuranic || audioUrl != null || audioAsset != null;

  /// Texte agrégé sur lequel porte la recherche (FR + AR + translittération
  /// + source). Le champ arabe est inclus tel quel : chercher « اللهم »
  /// doit marcher pour qui tape en arabe.
  String get searchBlob =>
      '$titleFr $titleAr $translationFr ${translit ?? ''} ${source ?? ''} $textAr'
          .toLowerCase();
}

// ── Taxonomie : univers → collections ────────────────────────────────────────

/// Une collection = une liste d'invocations qui se lisent ensemble.
/// `emoji` plutôt qu'une icône Material : le jeu d'icônes Material n'a rien
/// pour « Kaaba », « pluie », « voyage sacré »… et l'emoji porte le sens
/// instantanément, dans toutes les langues de l'app.
class DuaCollection {
  final String id;
  final String emoji;
  final String labelFr;
  final String labelAr;

  /// ── L'ANGLAIS MANQUAIT, ET L'APP RETOMBAIT SUR LE FRANÇAIS (2026-09-13) ──
  ///
  /// Constat utilisateur, capture à l'appui : *« oui alors que je suis en
  /// anglais »*. L'interface affichait « Duas & Adhkar », « Search an
  /// invocation… », « NOW », « EXPLORE » — et juste en dessous « Le fil du
  /// jour », « Du réveil au sommeil », « Cœur & épreuves ».
  ///
  /// La cause n'était pas un oubli de traduction : c'était un choix BINAIRE
  /// dans les écrans, `isArabic ? labelAr : labelFr`. Toute langue qui n'est
  /// pas l'arabe recevait donc le français, et l'anglais n'avait aucun endroit
  /// où exister. Ajouter des chaînes n'aurait rien changé tant que le modèle
  /// ne portait que deux langues.
  ///
  /// ⚠️ Même famille de défaut que les libellés de portion du Coach, corrigés
  /// le même jour — et pour la même raison de fond : une bascule à deux
  /// branches dans une application qui en a trois. Quand on ajoute une langue,
  /// chercher les `isArabic ? … : …` avant de chercher les chaînes.
  final String labelEn;

  /// Une ligne de contexte affichée sous le titre — quand la dire, à qui elle
  /// s'adresse. Sans ça une liste de collections reste opaque.
  final String hint;

  /// Version anglaise de [hint]. Cf. [labelEn].
  final String hintEn;

  const DuaCollection({
    required this.id,
    required this.emoji,
    required this.labelFr,
    required this.labelAr,
    required this.labelEn,
    required this.hint,
    required this.hintEn,
  });

  /// Libellé dans la langue de l'interface.
  ///
  /// Le repli est le FRANÇAIS et non une chaîne vide : une carte sans titre
  /// serait un défaut pire que celui qu'on corrige. Il n'est plus censé servir
  /// (les 35 collections sont traduites), mais il garantit qu'une collection
  /// ajoutée demain sans `labelEn` reste lisible au lieu de disparaître.
  String label(String langue) => switch (langue) {
        'ar' => labelAr,
        'en' => labelEn.isEmpty ? labelFr : labelEn,
        _ => labelFr,
      };

  /// Ligne de contexte dans la langue de l'interface.
  ///
  /// ⚠️ L'ARABE N'EN A PAS, et c'est assumé pour l'instant : `hint` n'a jamais
  /// eu de variante arabe (cf. le commentaire de `duas_screen.dart` : « hint
  /// n'existe qu'en français -- omis en arabe »). On rend donc une chaîne vide
  /// en arabe, ce que les écrans savent déjà ne pas afficher — plutôt que d'y
  /// laisser tomber du français, qui serait le défaut qu'on corrige ici.
  String contexte(String langue) => switch (langue) {
        'ar' => '',
        'en' => hintEn.isEmpty ? hint : hintEn,
        _ => hint,
      };
}

/// Un univers = un grand domaine de la vie du croyant, qui regroupe des
/// collections. C'est le premier niveau de navigation (6 cartes sur le hub).
class DuaUnivers {
  final String id;
  final String emoji;
  final String labelFr;
  final String labelAr;

  /// Cf. [DuaCollection.labelEn] pour le pourquoi.
  final String labelEn;
  final String tagline;

  /// Version anglaise de [tagline]. Cf. [DuaCollection.labelEn].
  final String taglineEn;

  /// Version arabe de [tagline] — AJOUTÉE en même temps que l'anglais, parce
  /// que le défaut ne touchait pas que l'anglais : `tagline` était affiché tel
  /// quel (« Du réveil au sommeil ») y compris en arabe, où il est la seule
  /// ligne sous un titre pourtant traduit.
  final String taglineAr;
  final Color color;
  final List<DuaCollection> collections;

  const DuaUnivers({
    required this.id,
    required this.emoji,
    required this.labelFr,
    required this.labelAr,
    required this.labelEn,
    required this.tagline,
    required this.taglineEn,
    required this.taglineAr,
    required this.color,
    required this.collections,
  });

  String label(String langue) => switch (langue) {
        'ar' => labelAr,
        'en' => labelEn.isEmpty ? labelFr : labelEn,
        _ => labelFr,
      };

  String accroche(String langue) => switch (langue) {
        'ar' => taglineAr.isEmpty ? '' : taglineAr,
        'en' => taglineEn.isEmpty ? tagline : taglineEn,
        _ => tagline,
      };
}

/// L'arborescence complète.
///
/// Ordre voulu : on descend du plus quotidien (le jour qui passe, la prière)
/// vers le plus exceptionnel (le pèlerinage). Quelqu'un qui ouvre l'onglet
/// sans intention précise tombe d'abord sur ce qu'il utilisera aujourd'hui.
const kDuaUnivers = <DuaUnivers>[
  DuaUnivers(
    id: 'jour',
    emoji: '🌅',
    labelFr: 'Le fil du jour',
    labelEn: 'Through the day',
    labelAr: 'أذكار اليوم',
    tagline: 'Du réveil au sommeil',
    taglineEn: 'From waking to sleep',
    taglineAr: 'من الاستيقاظ إلى النوم',
    color: Color(0xFFb85000),
    collections: [
      DuaCollection(
        id: 'reveil',
        emoji: '🌄',
        labelFr: 'Au réveil',
        labelEn: 'On waking',
        labelAr: 'أذكار الاستيقاظ',
        hint: 'Les premiers mots en ouvrant les yeux',
        hintEn: 'The first words on opening your eyes',
      ),
      DuaCollection(
        id: 'matin',
        emoji: '☀️',
        labelFr: 'Adhkār du matin',
        labelEn: 'Morning adhkār',
        labelAr: 'أذكار الصباح',
        hint: 'Après Ṣobḥ, jusqu\'au lever du soleil',
        hintEn: 'After Ṣobḥ, until sunrise',
      ),
      DuaCollection(
        id: 'soir',
        emoji: '🌙',
        labelFr: 'Adhkār du soir',
        labelEn: 'Evening adhkār',
        labelAr: 'أذكار المساء',
        hint: 'Après ʿAṣr, jusqu\'à la nuit tombée',
        hintEn: 'After ʿAṣr, until nightfall',
      ),
      DuaCollection(
        id: 'sommeil',
        emoji: '🛏️',
        labelFr: 'Avant de dormir',
        labelEn: 'Before sleep',
        labelAr: 'أذكار النوم',
        hint: 'Le dernier dhikr de la journée',
        hintEn: 'The last dhikr of the day',
      ),
      DuaCollection(
        id: 'nuit',
        emoji: '🌌',
        labelFr: 'Veille de nuit',
        labelEn: 'Night vigil',
        labelAr: 'قيام الليل',
        hint: 'Tahajjud, insomnie, dernier tiers de la nuit',
        hintEn: 'Tahajjud, sleeplessness, the last third of the night',
      ),
    ],
  ),
  DuaUnivers(
    id: 'priere',
    emoji: '🕌',
    labelFr: 'La prière',
    labelEn: 'The prayer',
    labelAr: 'الصلاة',
    tagline: 'Avant, pendant, après',
    taglineEn: 'Before, during, after',
    taglineAr: 'قبل الصلاة وأثناءها وبعدها',
    color: AppColors.green700,
    collections: [
      DuaCollection(
        id: 'avant_priere',
        emoji: '🚿',
        labelFr: 'Ablutions & adhān',
        labelEn: 'Ablutions & adhān',
        labelAr: 'الوضوء والأذان',
        hint: 'Se préparer, répondre à l\'appel, entrer à la mosquée',
        hintEn: 'Preparing, answering the call, entering the mosque',
      ),
      DuaCollection(
        id: 'dans_priere',
        emoji: '🤲',
        labelFr: 'Pendant la prière',
        labelEn: 'During the prayer',
        labelAr: 'أذكار الصلاة',
        hint: 'Istiftāḥ, rukūʿ, sujūd, tashahhud',
        hintEn: 'Istiftāḥ, rukūʿ, sujūd, tashahhud',
      ),
      DuaCollection(
        id: 'sobh',
        emoji: '🌤️',
        labelFr: 'Ṣalāt as-Ṣobḥ',
        labelEn: 'Ṣalāt as-Ṣobḥ',
        labelAr: 'صلاة الصبح',
        hint: 'Ce qui est propre à la prière de l\'aube',
        hintEn: 'What belongs to the dawn prayer alone',
      ),
      DuaCollection(
        id: 'apres_priere',
        emoji: '📿',
        labelFr: 'Après la prière',
        labelEn: 'After the prayer',
        labelAr: 'أذكار بعد الصلاة',
        hint: 'Le chapelet qui suit chaque prière obligatoire',
        hintEn: 'The dhikr that follows every obligatory prayer',
      ),
      DuaCollection(
        id: 'witr',
        emoji: '🌃',
        labelFr: 'Witr & Qunūt',
        labelEn: 'Witr & Qunūt',
        labelAr: 'الوتر والقنوت',
        hint: 'La dernière prière de la nuit',
        hintEn: 'The last prayer of the night',
      ),
      DuaCollection(
        id: 'joumoua',
        emoji: '🕋',
        labelFr: 'Vendredi',
        labelEn: 'Friday',
        labelAr: 'الجمعة',
        hint: 'Joumouʿa, l\'heure exaucée, la Sourate Al-Kahf',
        hintEn: 'Jumuʿa, the answered hour, Sūrat al-Kahf',
      ),
      DuaCollection(
        id: 'aid',
        emoji: '🎉',
        labelFr: 'Prière de l\'ʿAïd',
        labelEn: 'ʿĪd prayer',
        labelAr: 'صلاة العيد',
        hint: 'Takbīrāt, ʿAïd al-Fiṭr et ʿAïd al-Aḍḥā',
        hintEn: 'Takbīrāt, ʿĪd al-Fiṭr and ʿĪd al-Aḍḥā',
      ),
      DuaCollection(
        id: 'istikhara',
        emoji: '🧭',
        labelFr: 'Istikhāra',
        labelEn: 'Istikhāra',
        labelAr: 'الاستخارة',
        hint: 'Demander à Allah de choisir pour soi',
        hintEn: 'Asking Allah to choose on your behalf',
      ),
    ],
  ),
  DuaUnivers(
    id: 'coran',
    emoji: '📖',
    labelFr: 'Le Coran',
    labelEn: 'The Qur\'an',
    labelAr: 'القرآن',
    tagline: 'Invoquer avec Sa parole',
    taglineEn: 'Supplicating with His own words',
    taglineAr: 'أدعية من القرآن الكريم',
    color: AppColors.brass,
    collections: [
      DuaCollection(
        id: 'rabbana',
        emoji: '💫',
        labelFr: 'Les « Rabbanā »',
        labelEn: 'The "Rabbanā" verses',
        labelAr: 'أدعية تبدأ بربنا',
        hint: 'Les invocations que le Coran met dans nos bouches',
        hintEn: 'The supplications the Qur\'an places in our mouths',
      ),
      DuaCollection(
        id: 'prophetes',
        emoji: '🕊️',
        labelFr: 'Invocations des prophètes',
        labelEn: 'The prophets\' supplications',
        labelAr: 'أدعية الأنبياء',
        hint: 'Ce qu\'ils ont dit dans l\'épreuve — et qui fut exaucé',
        hintEn: 'What they said in hardship — and was answered',
      ),
      DuaCollection(
        id: 'lecture_coran',
        emoji: '📿',
        labelFr: 'Autour de la lecture',
        labelEn: 'Around the reading',
        labelAr: 'آداب التلاوة',
        hint: 'Avant d\'ouvrir le Muṣḥaf, en le refermant',
        hintEn: 'Before opening the Muṣḥaf, and on closing it',
      ),
      DuaCollection(
        id: 'khatm',
        emoji: '🏁',
        labelFr: 'Khatm — fin du Coran',
        labelEn: 'Khatm — completing the Qur\'an',
        labelAr: 'دعاء ختم القرآن',
        hint: 'Quand on achève une lecture complète',
        hintEn: 'On completing a full reading',
      ),
      DuaCollection(
        id: 'protection_coran',
        emoji: '🛡️',
        labelFr: 'Versets de protection',
        labelEn: 'Verses of protection',
        labelAr: 'آيات الحفظ',
        hint: 'Āyat al-Kursī, les Muʿawwidhāt, fin d\'Al-Baqara',
        hintEn: 'Āyat al-Kursī, the Muʿawwidhāt, the end of al-Baqara',
      ),
    ],
  ),
  DuaUnivers(
    id: 'vie',
    emoji: '🏡',
    labelFr: 'La vie quotidienne',
    labelEn: 'Daily life',
    labelAr: 'أذكار يومية',
    tagline: 'Manger, sortir, voyager',
    taglineEn: 'Eating, going out, travelling',
    taglineAr: 'الأكل والخروج والسفر',
    color: Color(0xFF0f766e),
    collections: [
      DuaCollection(
        id: 'repas',
        emoji: '🍽️',
        labelFr: 'Le repas',
        labelEn: 'Meals',
        labelAr: 'أذكار الطعام',
        hint: 'Avant, après, chez un hôte, en rompant le jeûne',
        hintEn: 'Before, after, as a guest, breaking the fast',
      ),
      DuaCollection(
        id: 'maison',
        emoji: '🚪',
        labelFr: 'La maison',
        labelEn: 'The home',
        labelAr: 'أذكار المنزل',
        hint: 'Entrer, sortir, les toilettes, s\'habiller',
        hintEn: 'Entering, leaving, the bathroom, getting dressed',
      ),
      DuaCollection(
        id: 'sortie',
        emoji: '🚶',
        labelFr: 'Dehors',
        labelEn: 'Outside',
        labelAr: 'الخروج',
        hint: 'La rue, le marché, le transport',
        hintEn: 'The street, the market, transport',
      ),
      DuaCollection(
        id: 'voyage',
        emoji: '✈️',
        labelFr: 'Le voyage',
        labelEn: 'Travel',
        labelAr: 'أذكار السفر',
        hint: 'Partir, monter en véhicule, arriver, rentrer',
        hintEn: 'Setting out, boarding, arriving, coming home',
      ),
      DuaCollection(
        id: 'meteo',
        emoji: '🌧️',
        labelFr: 'Ciel & météo',
        labelEn: 'Sky & weather',
        labelAr: 'أذكار المطر والريح',
        hint: 'La pluie, le vent, le tonnerre, la lune',
        hintEn: 'Rain, wind, thunder, the moon',
      ),
      DuaCollection(
        id: 'autrui',
        emoji: '🤝',
        labelFr: 'Avec les autres',
        labelEn: 'With others',
        labelAr: 'مع الناس',
        hint: 'Remercier, saluer, féliciter, se quitter',
        hintEn: 'Thanking, greeting, congratulating, parting',
      ),
    ],
  ),
  DuaUnivers(
    id: 'coeur',
    emoji: '💚',
    labelFr: 'Cœur & épreuves',
    labelEn: 'Heart & hardship',
    labelAr: 'الهم والكرب',
    tagline: 'Quand c\'est lourd',
    taglineEn: 'When the heart is heavy',
    taglineAr: 'عند الشدة',
    color: Color(0xFF7c3aed),
    collections: [
      DuaCollection(
        id: 'angoisse',
        emoji: '😔',
        labelFr: 'Angoisse & tristesse',
        labelEn: 'Anxiety & sorrow',
        labelAr: 'الهم والحزن',
        hint: 'Quand la poitrine se serre',
        hintEn: 'When the chest tightens',
      ),
      DuaCollection(
        id: 'maladie',
        emoji: '🩺',
        labelFr: 'Maladie & douleur',
        labelEn: 'Illness & pain',
        labelAr: 'المرض',
        hint: 'Pour soi, pour un malade qu\'on visite',
        hintEn: 'For yourself, and for the sick you visit',
      ),
      DuaCollection(
        id: 'peur',
        emoji: '🛡️',
        labelFr: 'Peur & protection',
        labelEn: 'Fear & protection',
        labelAr: 'الخوف والحفظ',
        hint: 'Ennemi, mauvais œil, waswās, cauchemar',
        hintEn: 'Enemies, the evil eye, waswās, nightmares',
      ),
      DuaCollection(
        id: 'dette',
        emoji: '💰',
        labelFr: 'Dette & subsistance',
        labelEn: 'Debt & provision',
        labelAr: 'الدَّيْن والرزق',
        hint: 'Quand l\'argent manque ou étouffe',
        hintEn: 'When money is short, or suffocating',
      ),
      DuaCollection(
        id: 'colere',
        emoji: '🔥',
        labelFr: 'Colère & discorde',
        labelEn: 'Anger & discord',
        labelAr: 'الغضب',
        hint: 'Se retenir, réparer, pardonner',
        hintEn: 'Holding back, making amends, forgiving',
      ),
      DuaCollection(
        id: 'deuil',
        emoji: '🕯️',
        labelFr: 'Deuil',
        labelEn: 'Mourning',
        labelAr: 'الجنائز',
        hint: 'Le défunt, la famille, la visite des tombes',
        hintEn: 'The deceased, the family, visiting the graves',
      ),
      DuaCollection(
        id: 'istighfar',
        emoji: '🤍',
        labelFr: 'Repentir & istighfār',
        labelEn: 'Repentance & istighfār',
        labelAr: 'الاستغفار والتوبة',
        hint: 'Revenir, quel que soit le nombre de fois',
        hintEn: 'Turning back, however many times it takes',
      ),
    ],
  ),
  DuaUnivers(
    id: 'sacre',
    emoji: '🕋',
    labelFr: 'Le voyage sacré',
    labelEn: 'The sacred journey',
    labelAr: 'الحج والعمرة',
    tagline: 'ʿUmra & Hajj, pas à pas',
    taglineEn: 'ʿUmra & Hajj, step by step',
    taglineAr: 'العمرة والحج خطوة بخطوة',
    color: Color(0xFF0c3b2c),
    collections: [
      DuaCollection(
        id: 'rite:umra',
        emoji: '🕋',
        labelFr: 'ʿUmra — guide pas à pas',
        labelEn: 'ʿUmra — step by step',
        labelAr: 'مناسك العمرة',
        hint: '9 étapes, du mīqāt au taqṣīr · compteurs intégrés',
        hintEn: '9 steps, from the mīqāt to the taqṣīr · built-in counters',
      ),
      DuaCollection(
        id: 'rite:hajj',
        emoji: '⛺',
        labelFr: 'Hajj — jour par jour',
        labelEn: 'Hajj — day by day',
        labelAr: 'مناسك الحج',
        hint: 'Du 8 au 13 Dhū l-Ḥijja · ʿArafa, Muzdalifa, Minā',
        hintEn: 'From 8 to 13 Dhū l-Ḥijja · ʿArafa, Muzdalifa, Minā',
      ),
      DuaCollection(
        id: 'pelerin',
        emoji: '🧳',
        labelFr: 'Duas du pèlerin',
        labelEn: 'The pilgrim\'s duas',
        labelAr: 'أدعية الحاج',
        hint: 'Talbiya, Kaʿba, Zamzam, Rawḍa',
        hintEn: 'Talbiya, Kaʿba, Zamzam, Rawḍa',
      ),
    ],
  ),
];

/// Index plat id → collection (résolution rapide depuis un tag de dua).
final Map<String, DuaCollection> kCollectionsById = {
  for (final u in kDuaUnivers)
    for (final c in u.collections) c.id: c,
};

/// Index plat id de collection → univers parent (pour la couleur d'accent).
final Map<String, DuaUnivers> kUniversByCollectionId = {
  for (final u in kDuaUnivers)
    for (final c in u.collections) c.id: u,
};

// ── Suggestion contextuelle « Maintenant » ──────────────────────────────────

/// Ce qui est proposé en haut du hub, selon l'heure et le jour.
class DuaMoment {
  final String emoji;
  final String titleFr;
  final String subtitle;

  /// Cf. [DuaCollection.labelEn]. La carte « NOW » du haut du hub affichait
  /// « Avant de dormir / Les derniers mots de la journée » en anglais.
  final String titleEn;
  final String subtitleEn;
  final String titleAr;
  final String subtitleAr;

  /// Collection à ouvrir en un tap.
  final String collectionId;

  const DuaMoment({
    required this.emoji,
    required this.titleFr,
    required this.subtitle,
    required this.titleEn,
    required this.subtitleEn,
    required this.titleAr,
    required this.subtitleAr,
    required this.collectionId,
  });

  String titre(String langue) => switch (langue) {
        'ar' => titleAr.isEmpty ? titleFr : titleAr,
        'en' => titleEn.isEmpty ? titleFr : titleEn,
        _ => titleFr,
      };

  String sousTitre(String langue) => switch (langue) {
        'ar' => subtitleAr.isEmpty ? subtitle : subtitleAr,
        'en' => subtitleEn.isEmpty ? subtitle : subtitleEn,
        _ => subtitle,
      };
}

/// POURQUOI : l'usage réel d'un recueil d'invocations est massivement
/// « c'est le matin, qu'est-ce que je dis ? ». Obliger à traverser deux
/// niveaux de navigation pour ça, tous les jours, est une friction inutile —
/// même logique que `lastCoachVerseProvider` pour la mémorisation.
///
/// Volontairement basé sur l'HEURE LOCALE et non sur les horaires de prière
/// calculés : l'app n'a pas (encore) de moteur d'horaires, et une approximation
/// honnête vaut mieux qu'une fausse précision. Les libellés restent donc
/// prudents (« autour de Ṣobḥ », pas « il est l'heure de Ṣobḥ »).
DuaMoment currentDuaMoment([DateTime? now]) {
  final t = now ?? DateTime.now();
  final h = t.hour;

  // Le vendredi prime sur le créneau horaire pendant la matinée et
  // l'après-midi : c'est le marqueur le plus fort de la journée.
  if (t.weekday == DateTime.friday && h >= 6 && h < 19) {
    return const DuaMoment(
      emoji: '🕌',
      titleFr: 'C\'est vendredi',
      titleEn: 'It\'s Friday',
      titleAr: 'اليوم الجمعة',
      subtitle: 'Sourate Al-Kahf, ṣalāt sur le Prophète, l\'heure exaucée',
      subtitleEn: 'Sūrat al-Kahf, ṣalāt upon the Prophet, the answered hour',
      subtitleAr: 'سورة الكهف، الصلاة على النبي، ساعة الإجابة',
      collectionId: 'joumoua',
    );
  }

  if (h >= 4 && h < 7) {
    return const DuaMoment(
      emoji: '🌤️',
      titleFr: 'Autour de Ṣobḥ',
      titleEn: 'Around Ṣobḥ',
      titleAr: 'صلاة الفجر',
      subtitle: 'Ce qu\'on dit à la prière de l\'aube',
      subtitleEn: 'What is said at the dawn prayer',
      subtitleAr: 'ما يقال في صلاة الفجر',
      collectionId: 'sobh',
    );
  }
  if (h >= 7 && h < 11) {
    return const DuaMoment(
      emoji: '☀️',
      titleFr: 'Adhkār du matin',
      titleEn: 'Morning adhkār',
      titleAr: 'أذكار الصباح',
      subtitle: 'La protection de la journée qui commence',
      subtitleEn: 'Protection for the day ahead',
      subtitleAr: 'ابدأ يومك بذكر الله',
      collectionId: 'matin',
    );
  }
  if (h >= 11 && h < 15) {
    return const DuaMoment(
      emoji: '📿',
      titleFr: 'Après la prière',
      titleEn: 'After the prayer',
      titleAr: 'بعد الصلاة',
      subtitle: 'Le chapelet qui suit chaque obligatoire',
      subtitleEn: 'The dhikr that follows every obligatory prayer',
      subtitleAr: 'الأذكار بعد كل صلاة مفروضة',
      collectionId: 'apres_priere',
    );
  }
  if (h >= 15 && h < 20) {
    return const DuaMoment(
      emoji: '🌙',
      titleFr: 'Adhkār du soir',
      titleEn: 'Evening adhkār',
      titleAr: 'أذكار المساء',
      subtitle: 'À dire après ʿAṣr, avant la nuit',
      subtitleEn: 'To say after ʿAṣr, before nightfall',
      subtitleAr: 'تقال بعد العصر قبل الليل',
      collectionId: 'soir',
    );
  }
  if (h >= 20 && h < 23) {
    return const DuaMoment(
      emoji: '🛏️',
      titleFr: 'Avant de dormir',
      titleEn: 'Before sleep',
      titleAr: 'أذكار النوم',
      subtitle: 'Les derniers mots de la journée',
      subtitleEn: 'The last words of the day',
      subtitleAr: 'آخر كلمات اليوم',
      collectionId: 'sommeil',
    );
  }
  return const DuaMoment(
    emoji: '🌌',
    titleFr: 'Le cœur de la nuit',
    titleEn: 'The heart of the night',
    titleAr: 'جوف الليل',
    subtitle: 'Tahajjud, istighfār, l\'heure où Il descend',
    subtitleEn: 'Tahajjud, istighfār, the hour of His descent',
    subtitleAr: 'التهجد والاستغفار وساعة النزول',
    collectionId: 'nuit',
  );
}
