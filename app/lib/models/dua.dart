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
  final int? surahNumber;
  final int? ayahNumber;

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
  });

  bool get isQuranic => surahNumber != null && ayahNumber != null;

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

  /// Une ligne de contexte affichée sous le titre — quand la dire, à qui elle
  /// s'adresse. Sans ça une liste de collections reste opaque.
  final String hint;

  const DuaCollection({
    required this.id,
    required this.emoji,
    required this.labelFr,
    required this.labelAr,
    required this.hint,
  });
}

/// Un univers = un grand domaine de la vie du croyant, qui regroupe des
/// collections. C'est le premier niveau de navigation (6 cartes sur le hub).
class DuaUnivers {
  final String id;
  final String emoji;
  final String labelFr;
  final String labelAr;
  final String tagline;
  final Color color;
  final List<DuaCollection> collections;

  const DuaUnivers({
    required this.id,
    required this.emoji,
    required this.labelFr,
    required this.labelAr,
    required this.tagline,
    required this.color,
    required this.collections,
  });
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
    labelAr: 'أذكار اليوم',
    tagline: 'Du réveil au sommeil',
    color: Color(0xFFb85000),
    collections: [
      DuaCollection(
        id: 'reveil',
        emoji: '🌄',
        labelFr: 'Au réveil',
        labelAr: 'أذكار الاستيقاظ',
        hint: 'Les premiers mots en ouvrant les yeux',
      ),
      DuaCollection(
        id: 'matin',
        emoji: '☀️',
        labelFr: 'Adhkār du matin',
        labelAr: 'أذكار الصباح',
        hint: 'Après Ṣobḥ, jusqu\'au lever du soleil',
      ),
      DuaCollection(
        id: 'soir',
        emoji: '🌙',
        labelFr: 'Adhkār du soir',
        labelAr: 'أذكار المساء',
        hint: 'Après ʿAṣr, jusqu\'à la nuit tombée',
      ),
      DuaCollection(
        id: 'sommeil',
        emoji: '🛏️',
        labelFr: 'Avant de dormir',
        labelAr: 'أذكار النوم',
        hint: 'Le dernier dhikr de la journée',
      ),
      DuaCollection(
        id: 'nuit',
        emoji: '🌌',
        labelFr: 'Veille de nuit',
        labelAr: 'قيام الليل',
        hint: 'Tahajjud, insomnie, dernier tiers de la nuit',
      ),
    ],
  ),
  DuaUnivers(
    id: 'priere',
    emoji: '🕌',
    labelFr: 'La prière',
    labelAr: 'الصلاة',
    tagline: 'Avant, pendant, après',
    color: AppColors.green700,
    collections: [
      DuaCollection(
        id: 'avant_priere',
        emoji: '🚿',
        labelFr: 'Ablutions & adhān',
        labelAr: 'الوضوء والأذان',
        hint: 'Se préparer, répondre à l\'appel, entrer à la mosquée',
      ),
      DuaCollection(
        id: 'dans_priere',
        emoji: '🤲',
        labelFr: 'Pendant la prière',
        labelAr: 'أذكار الصلاة',
        hint: 'Istiftāḥ, rukūʿ, sujūd, tashahhud',
      ),
      DuaCollection(
        id: 'sobh',
        emoji: '🌤️',
        labelFr: 'Ṣalāt as-Ṣobḥ',
        labelAr: 'صلاة الصبح',
        hint: 'Ce qui est propre à la prière de l\'aube',
      ),
      DuaCollection(
        id: 'apres_priere',
        emoji: '📿',
        labelFr: 'Après la prière',
        labelAr: 'أذكار بعد الصلاة',
        hint: 'Le chapelet qui suit chaque prière obligatoire',
      ),
      DuaCollection(
        id: 'witr',
        emoji: '🌃',
        labelFr: 'Witr & Qunūt',
        labelAr: 'الوتر والقنوت',
        hint: 'La dernière prière de la nuit',
      ),
      DuaCollection(
        id: 'joumoua',
        emoji: '🕋',
        labelFr: 'Vendredi',
        labelAr: 'الجمعة',
        hint: 'Joumouʿa, l\'heure exaucée, la Sourate Al-Kahf',
      ),
      DuaCollection(
        id: 'aid',
        emoji: '🎉',
        labelFr: 'Prière de l\'ʿAïd',
        labelAr: 'صلاة العيد',
        hint: 'Takbīrāt, ʿAïd al-Fiṭr et ʿAïd al-Aḍḥā',
      ),
      DuaCollection(
        id: 'istikhara',
        emoji: '🧭',
        labelFr: 'Istikhāra',
        labelAr: 'الاستخارة',
        hint: 'Demander à Allah de choisir pour soi',
      ),
    ],
  ),
  DuaUnivers(
    id: 'coran',
    emoji: '📖',
    labelFr: 'Le Coran',
    labelAr: 'القرآن',
    tagline: 'Invoquer avec Sa parole',
    color: AppColors.brass,
    collections: [
      DuaCollection(
        id: 'rabbana',
        emoji: '💫',
        labelFr: 'Les « Rabbanā »',
        labelAr: 'دعاء ربنا',
        hint: 'Les invocations que le Coran met dans nos bouches',
      ),
      DuaCollection(
        id: 'prophetes',
        emoji: '🕊️',
        labelFr: 'Invocations des prophètes',
        labelAr: 'أدعية الأنبياء',
        hint: 'Ce qu\'ils ont dit dans l\'épreuve — et qui fut exaucé',
      ),
      DuaCollection(
        id: 'lecture_coran',
        emoji: '📿',
        labelFr: 'Autour de la lecture',
        labelAr: 'آداب التلاوة',
        hint: 'Avant d\'ouvrir le Muṣḥaf, en le refermant',
      ),
      DuaCollection(
        id: 'khatm',
        emoji: '🏁',
        labelFr: 'Khatm — fin du Coran',
        labelAr: 'دعاء ختم القرآن',
        hint: 'Quand on achève une lecture complète',
      ),
      DuaCollection(
        id: 'protection_coran',
        emoji: '🛡️',
        labelFr: 'Versets de protection',
        labelAr: 'آيات الحفظ',
        hint: 'Āyat al-Kursī, les Muʿawwidhāt, fin d\'Al-Baqara',
      ),
    ],
  ),
  DuaUnivers(
    id: 'vie',
    emoji: '🏡',
    labelFr: 'La vie quotidienne',
    labelAr: 'أذكار يومية',
    tagline: 'Manger, sortir, voyager',
    color: Color(0xFF0f766e),
    collections: [
      DuaCollection(
        id: 'repas',
        emoji: '🍽️',
        labelFr: 'Le repas',
        labelAr: 'أذكار الطعام',
        hint: 'Avant, après, chez un hôte, en rompant le jeûne',
      ),
      DuaCollection(
        id: 'maison',
        emoji: '🚪',
        labelFr: 'La maison',
        labelAr: 'أذكار المنزل',
        hint: 'Entrer, sortir, les toilettes, s\'habiller',
      ),
      DuaCollection(
        id: 'sortie',
        emoji: '🚶',
        labelFr: 'Dehors',
        labelAr: 'الخروج',
        hint: 'La rue, le marché, le transport',
      ),
      DuaCollection(
        id: 'voyage',
        emoji: '✈️',
        labelFr: 'Le voyage',
        labelAr: 'أذكار السفر',
        hint: 'Partir, monter en véhicule, arriver, rentrer',
      ),
      DuaCollection(
        id: 'meteo',
        emoji: '🌧️',
        labelFr: 'Ciel & météo',
        labelAr: 'أذكار المطر والريح',
        hint: 'La pluie, le vent, le tonnerre, la lune',
      ),
      DuaCollection(
        id: 'autrui',
        emoji: '🤝',
        labelFr: 'Avec les autres',
        labelAr: 'مع الناس',
        hint: 'Remercier, saluer, féliciter, se quitter',
      ),
    ],
  ),
  DuaUnivers(
    id: 'coeur',
    emoji: '💚',
    labelFr: 'Cœur & épreuves',
    labelAr: 'الهم والكرب',
    tagline: 'Quand c\'est lourd',
    color: Color(0xFF7c3aed),
    collections: [
      DuaCollection(
        id: 'angoisse',
        emoji: '😔',
        labelFr: 'Angoisse & tristesse',
        labelAr: 'الهم والحزن',
        hint: 'Quand la poitrine se serre',
      ),
      DuaCollection(
        id: 'maladie',
        emoji: '🩺',
        labelFr: 'Maladie & douleur',
        labelAr: 'المرض',
        hint: 'Pour soi, pour un malade qu\'on visite',
      ),
      DuaCollection(
        id: 'peur',
        emoji: '🛡️',
        labelFr: 'Peur & protection',
        labelAr: 'الخوف والحفظ',
        hint: 'Ennemi, mauvais œil, waswās, cauchemar',
      ),
      DuaCollection(
        id: 'dette',
        emoji: '💰',
        labelFr: 'Dette & subsistance',
        labelAr: 'الدين والرزق',
        hint: 'Quand l\'argent manque ou étouffe',
      ),
      DuaCollection(
        id: 'colere',
        emoji: '🔥',
        labelFr: 'Colère & discorde',
        labelAr: 'الغضب',
        hint: 'Se retenir, réparer, pardonner',
      ),
      DuaCollection(
        id: 'deuil',
        emoji: '🕯️',
        labelFr: 'Deuil',
        labelAr: 'الجنائز',
        hint: 'Le défunt, la famille, la visite des tombes',
      ),
      DuaCollection(
        id: 'istighfar',
        emoji: '🤍',
        labelFr: 'Repentir & istighfār',
        labelAr: 'الاستغفار والتوبة',
        hint: 'Revenir, quel que soit le nombre de fois',
      ),
    ],
  ),
  DuaUnivers(
    id: 'sacre',
    emoji: '🕋',
    labelFr: 'Le voyage sacré',
    labelAr: 'الحج والعمرة',
    tagline: 'ʿUmra & Hajj, pas à pas',
    color: Color(0xFF0c3b2c),
    collections: [
      DuaCollection(
        id: 'rite:umra',
        emoji: '🕋',
        labelFr: 'ʿUmra — guide pas à pas',
        labelAr: 'مناسك العمرة',
        hint: '9 étapes, du mīqāt au taqṣīr · compteurs intégrés',
      ),
      DuaCollection(
        id: 'rite:hajj',
        emoji: '⛺',
        labelFr: 'Hajj — jour par jour',
        labelAr: 'مناسك الحج',
        hint: 'Du 8 au 13 Dhū l-Ḥijja · ʿArafa, Muzdalifa, Minā',
      ),
      DuaCollection(
        id: 'pelerin',
        emoji: '🧳',
        labelFr: 'Duas du pèlerin',
        labelAr: 'أدعية الحاج',
        hint: 'Talbiya, Kaʿba, Zamzam, Rawḍa',
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

  /// Collection à ouvrir en un tap.
  final String collectionId;

  const DuaMoment({
    required this.emoji,
    required this.titleFr,
    required this.subtitle,
    required this.collectionId,
  });
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
      subtitle: 'Sourate Al-Kahf, ṣalāt sur le Prophète, l\'heure exaucée',
      collectionId: 'joumoua',
    );
  }

  if (h >= 4 && h < 7) {
    return const DuaMoment(
      emoji: '🌤️',
      titleFr: 'Autour de Ṣobḥ',
      subtitle: 'Ce qu\'on dit à la prière de l\'aube',
      collectionId: 'sobh',
    );
  }
  if (h >= 7 && h < 11) {
    return const DuaMoment(
      emoji: '☀️',
      titleFr: 'Adhkār du matin',
      subtitle: 'La protection de la journée qui commence',
      collectionId: 'matin',
    );
  }
  if (h >= 11 && h < 15) {
    return const DuaMoment(
      emoji: '📿',
      titleFr: 'Après la prière',
      subtitle: 'Le chapelet qui suit chaque obligatoire',
      collectionId: 'apres_priere',
    );
  }
  if (h >= 15 && h < 20) {
    return const DuaMoment(
      emoji: '🌙',
      titleFr: 'Adhkār du soir',
      subtitle: 'À dire après ʿAṣr, avant la nuit',
      collectionId: 'soir',
    );
  }
  if (h >= 20 && h < 23) {
    return const DuaMoment(
      emoji: '🛏️',
      titleFr: 'Avant de dormir',
      subtitle: 'Les derniers mots de la journée',
      collectionId: 'sommeil',
    );
  }
  return const DuaMoment(
    emoji: '🌌',
    titleFr: 'Le cœur de la nuit',
    subtitle: 'Tahajjud, istighfār, l\'heure où Il descend',
    collectionId: 'nuit',
  );
}
