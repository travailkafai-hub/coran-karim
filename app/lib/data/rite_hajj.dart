import '../models/rite.dart';

/// Le Hajj, jour par jour — décrit selon le tamattuʿ.
///
/// POURQUOI LE TAMATTUʿ : c'est la forme qu'accomplit l'immense majorité des
/// pèlerins venus par avion (ʿUmra d'abord, sortie de l'iḥrām, puis reprise
/// de l'iḥrām le 8 Dhū l-Ḥijja), et celle que le Prophète ﷺ ordonna à ses
/// compagnons d'adopter. Décrire les trois formes en parallèle rendrait
/// l'écran illisible sur place — les deux autres (qirān, ifrād) sont donc
/// signalées dans `essentials` sans être déroulées.
///
/// Les `dayLabel` servent à grouper la timeline : le Hajj se vit comme une
/// succession de journées ayant chacune son lieu, pas comme une liste plate.
const kRiteHajj = Rite(
  id: 'hajj',
  emoji: '⛺',
  nameFr: 'Hajj',
  nameAr: 'الحج',
  subtitle: 'Du 8 au 13 Dhū l-Ḥijja — 11 étapes',
  intro:
      "Le Hajj se déroule sur six jours, à des lieux imposés et à des heures "
      "imposées. Son pilier absolu est la station de ʿArafa : « Le Hajj, c'est "
      "ʿArafa. » Ce guide suit le tamattuʿ, la forme la plus courante — celle "
      "où l'on accomplit d'abord une ʿUmra, puis où l'on reprend l'iḥrām le "
      "8 Dhū l-Ḥijja.",
  essentials: [
    "Quatre piliers : l'iḥrām, la station à ʿArafa, le ṭawāf al-ifāḍa et le saʿy.",
    "Manquer ʿArafa avant l'aube du 10 invalide le Hajj — aucune compensation n'est possible.",
    "Trois formes existent : tamattuʿ (ʿUmra puis Hajj, avec sacrifice), qirān (les deux ensemble, avec sacrifice), ifrād (Hajj seul, sans sacrifice). Ce guide suit le tamattuʿ.",
    "Une omission d'obligation secondaire (wājib) se répare par un sacrifice ; une omission de pilier (rukn), non.",
    "Emportez de quoi vous protéger du soleil et restez hydraté : la déshydratation est la première cause d'incident à ʿArafa.",
  ],
  steps: [
    // ── 8 Dhū l-Ḥijja ─────────────────────────────────────────────────
    RiteStep(
      id: 'hajj_1_ihram',
      emoji: '🤍',
      titleFr: "Reprendre l'iḥrām",
      titleAr: 'الإحرام بالحج',
      place: 'Depuis son logement à La Mecque',
      when: 'Matin du 8',
      summary:
          "En tamattuʿ, on est sorti de l'iḥrām après la ʿUmra. On le reprend "
          "ce matin, depuis là où l'on réside — pas besoin de retourner au mīqāt.",
      actions: [
        "Se laver, se parfumer le corps, revêtir les deux pièces d'iḥrām.",
        "Formuler l'intention : « Labbayka llāhumma ḥajjan » — me voici pour un Hajj.",
        "Reprendre la Talbiya et la maintenir jusqu'au premier jet de cailloux, le 10.",
      ],
      duaIds: ['talbiya'],
      counter: null,
      warning: null,
      dayLabel: '8 Dhū l-Ḥijja — Yawm at-Tarwiya',
    ),
    RiteStep(
      id: 'hajj_2_mina',
      emoji: '⛺',
      titleFr: 'Monter à Minā',
      titleAr: 'الخروج إلى منى',
      place: 'Minā',
      when: 'Du 8 au matin jusqu\'à l\'aube du 9',
      summary:
          "Journée d'attente et de préparation sous la tente. On y accomplit "
          "cinq prières : Ẓuhr, ʿAṣr, Maghrib, ʿIshāʾ et le Fajr du lendemain.",
      actions: [
        "Prier les prières à quatre unités raccourcies à deux, chacune à son heure — sans les regrouper.",
        "Multiplier la Talbiya, le dhikr et la lecture du Coran.",
        "Se reposer : la journée de ʿArafa qui suit est physiquement la plus dure.",
      ],
      duaIds: ['talbiya', 'rabbana_hasana'],
      counter: null,
      warning:
          "Séjourner à Minā cette nuit est une sunna, non une obligation : "
          "celui qui en est empêché par l'organisation de son groupe ne doit "
          "rien. Ne culpabilisez pas et n'improvisez pas un déplacement risqué.",
      dayLabel: '8 Dhū l-Ḥijja — Yawm at-Tarwiya',
    ),

    // ── 9 Dhū l-Ḥijja ─────────────────────────────────────────────────
    RiteStep(
      id: 'hajj_3_arafa',
      emoji: '🏔️',
      titleFr: 'La station à ʿArafa',
      titleAr: 'الوقوف بعرفة',
      place: 'Plaine de ʿArafa',
      when: 'Du midi du 9 jusqu\'au coucher du soleil',
      summary:
          "Le pilier du Hajj. On prie Ẓuhr et ʿAṣr regroupés et raccourcis à "
          "l'heure du Ẓuhr, puis on consacre tout l'après-midi à l'invocation, "
          "debout ou assis, face à la qibla, jusqu'au coucher du soleil.",
      actions: [
        "Vérifier être bien À L'INTÉRIEUR des limites de ʿArafa : les panneaux les indiquent, et le Jabal ar-Raḥma n'est pas obligatoire.",
        "Écouter le sermon, puis prier Ẓuhr et ʿAṣr regroupés au début du Ẓuhr, deux unités chacune, avec un seul adhān et deux iqāma.",
        "Invoquer sans relâche jusqu'au coucher : lever les mains, demander pour soi, pour ses proches, pour les morts.",
        "Ne pas quitter ʿArafa avant que le soleil soit entièrement couché.",
      ],
      duaIds: ['arafa', 'rabbana_hasana', 'dua_yunus', 'istighfar_100'],
      counter: RiteCounter(
        label: "Invocation de ʿArafa",
        unit: 'fois',
        target: 100,
        doneMessage: 'Cent fois — continuez tant que le soleil n\'est pas couché',
      ),
      warning:
          "Partir avant le coucher du soleil rend un sacrifice obligatoire. "
          "C'est l'erreur la plus coûteuse du Hajj, souvent commise pour "
          "éviter les embouteillages.",
      dayLabel: '9 Dhū l-Ḥijja — Yawm ʿArafa',
    ),
    RiteStep(
      id: 'hajj_4_muzdalifa',
      emoji: '🌌',
      titleFr: 'La nuit à Muzdalifa',
      titleAr: 'المبيت بمزدلفة',
      place: 'Muzdalifa',
      when: 'Du coucher du soleil du 9 à l\'aube du 10',
      summary:
          "On quitte ʿArafa après le coucher, dans le calme. À Muzdalifa on "
          "prie Maghrib et ʿIshāʾ regroupés à l'arrivée, on dort, puis on prie "
          "Fajr tôt et l'on invoque jusqu'aux premières lueurs.",
      actions: [
        "Prier Maghrib (3 unités) et ʿIshāʾ (2 unités) regroupées à l'arrivée, avec un seul adhān.",
        "Dormir : le Prophète ﷺ n'a pas veillé cette nuit-là.",
        "Ramasser sept cailloux pour le lendemain — ou davantage si l'on préfère tout ramasser ici. La taille d'un pois chiche suffit.",
        "Après Fajr, se tourner vers la qibla au Mashʿar al-Ḥarām et invoquer jusqu'au jour naissant.",
      ],
      duaIds: ['talbiya', 'istighfar_100', 'rabbana_hasana'],
      counter: RiteCounter(
        label: 'Cailloux ramassés',
        unit: 'caillou',
        target: 7,
        doneMessage: 'Sept cailloux — de quoi lapider demain matin',
      ),
      warning:
          "Les faibles, les femmes, les personnes âgées et ceux qui les "
          "accompagnent ont l'autorisation expresse de partir après la mi-nuit, "
          "avant la foule.",
      dayLabel: '9 Dhū l-Ḥijja — Nuit à Muzdalifa',
    ),

    // ── 10 Dhū l-Ḥijja ────────────────────────────────────────────────
    RiteStep(
      id: 'hajj_5_jamra_aqaba',
      emoji: '🪨',
      titleFr: 'Lapider la grande stèle',
      titleAr: 'رمي جمرة العقبة',
      place: 'Jamrat al-ʿAqaba, à Minā',
      when: 'Matin du 10',
      summary:
          "Sept cailloux sur la grande stèle uniquement — les deux autres ne "
          "se lapident pas aujourd'hui. On cesse la Talbiya au premier jet.",
      actions: [
        "Lancer les sept cailloux un par un, en disant « Allāhu akbar » à chaque jet.",
        "Cesser la Talbiya dès le premier caillou.",
        "Ne lapider aucune des deux petites stèles aujourd'hui.",
      ],
      duaIds: ['aid_takbir'],
      counter: RiteCounter(
        label: 'Cailloux — Jamrat al-ʿAqaba',
        unit: 'caillou',
        target: 7,
        doneMessage: 'Sept cailloux lancés',
      ),
      warning:
          "On lance les cailloux, on ne les jette pas en tas et l'on ne "
          "s'énerve pas contre la stèle : c'est un acte d'adoration, pas un "
          "combat. Les bousculades y ont fait des morts.",
      dayLabel: '10 Dhū l-Ḥijja — Yawm an-Naḥr',
    ),
    RiteStep(
      id: 'hajj_6_hady',
      emoji: '🐑',
      titleFr: 'Le sacrifice',
      titleAr: 'الهدي',
      place: 'Abattoirs de Minā',
      when: 'Après la lapidation du 10',
      summary:
          "Obligatoire pour le tamattuʿ. En pratique, presque tous les pèlerins "
          "passent aujourd'hui par un bon d'abattage remis à leur agence ou à "
          "une banque agréée.",
      actions: [
        "S'acquitter du sacrifice, directement ou par mandat.",
        "Qui n'en a pas les moyens jeûne trois jours pendant le Hajj et sept au retour.",
      ],
      duaIds: ['aid_sacrifice'],
      counter: null,
      warning: null,
      dayLabel: '10 Dhū l-Ḥijja — Yawm an-Naḥr',
    ),
    RiteStep(
      id: 'hajj_7_halq',
      emoji: '✂️',
      titleFr: 'Rasage — première sortie de sacralisation',
      titleAr: 'الحلق والتحلل الأصغر',
      place: 'Minā',
      when: 'Après le sacrifice',
      summary:
          "Rasage complet ou raccourcissement. Une fois fait, la plupart des "
          "interdits de l'iḥrām sont levés : on reprend ses vêtements, on peut "
          "se parfumer — sauf les rapports conjugaux.",
      actions: [
        "Homme : se raser entièrement, ce qui est nettement préférable ici.",
        "Femme : couper l'équivalent d'une phalange sur l'ensemble des cheveux.",
        "Reprendre ses vêtements ordinaires.",
      ],
      duaIds: [],
      counter: null,
      warning:
          "Les rapports conjugaux restent interdits jusqu'à la sortie COMPLÈTE, "
          "qui n'intervient qu'après le ṭawāf al-ifāḍa et le saʿy.",
      dayLabel: '10 Dhū l-Ḥijja — Yawm an-Naḥr',
    ),
    RiteStep(
      id: 'hajj_8_ifada',
      emoji: '🔄',
      titleFr: 'Ṭawāf al-ifāḍa et saʿy',
      titleAr: 'طواف الإفاضة والسعي',
      place: 'Masjid al-Ḥarām',
      when: 'Le 10, ou dans les jours suivants',
      summary:
          "Descente à La Mecque pour le ṭawāf pilier du Hajj — sept tours — "
          "suivi du saʿy, sept parcours entre Ṣafā et Marwa. Après cela, la "
          "sortie de sacralisation est totale.",
      actions: [
        "Accomplir sept tours autour de la Kaʿba, sans iḍṭibāʿ ni raml cette fois.",
        "Prier deux unités derrière le Maqām.",
        "Accomplir sept parcours entre Ṣafā et Marwa, en commençant à Ṣafā.",
        "Remonter ensuite à Minā pour y passer la nuit.",
      ],
      duaIds: ['rabbana_hasana', 'safa_marwa', 'zamzam'],
      counter: RiteCounter(
        label: 'Ṭawāf puis saʿy',
        unit: 'série',
        target: 7,
        laps: ['Ṭawāf — tours', 'Saʿy — parcours'],
        doneMessage: 'Ṭawāf al-ifāḍa et saʿy accomplis',
      ),
      warning:
          "Ce ṭawāf est un PILIER : il n'expire pas. Une femme empêchée par "
          "ses menstrues attend d'être pure et l'accomplit ensuite, même si "
          "son groupe est reparti.",
      dayLabel: '10 Dhū l-Ḥijja — Yawm an-Naḥr',
    ),

    // ── 11-13 Dhū l-Ḥijja ─────────────────────────────────────────────
    RiteStep(
      id: 'hajj_9_tashriq',
      emoji: '🪨',
      titleFr: 'Les trois stèles, chaque jour',
      titleAr: 'رمي الجمرات الثلاث',
      place: 'Minā',
      when: 'Après le zawāl, les 11, 12 et éventuellement 13',
      summary:
          "Chaque après-midi, on lapide les trois stèles dans l'ordre — la "
          "petite, la moyenne, puis la grande — sept cailloux chacune, soit "
          "21 par jour. Après la petite et la moyenne, on s'écarte et l'on "
          "invoque longuement.",
      actions: [
        "Attendre le passage du zénith (zawāl) : lapider avant ne compte pas.",
        "Petite stèle : sept cailloux, puis se décaler et invoquer face à la qibla, longuement.",
        "Stèle moyenne : sept cailloux, puis à nouveau s'écarter et invoquer.",
        "Grande stèle : sept cailloux, sans s'arrêter ensuite pour invoquer.",
      ],
      duaIds: ['aid_takbir', 'aid_takbir_muqayyad', 'rabbana_hasana'],
      counter: RiteCounter(
        label: 'Lapidation des trois stèles',
        unit: 'caillou',
        target: 7,
        laps: ['Petite stèle', 'Stèle moyenne', 'Grande stèle'],
        doneMessage: '21 cailloux — les trois stèles sont faites',
      ),
      warning:
          "L'ordre des trois stèles est obligatoire. En cas de foule extrême, "
          "il est permis de mandater quelqu'un — mais jamais de sauter une stèle.",
      dayLabel: '11–13 Dhū l-Ḥijja — Ayyām at-Tashrīq',
    ),
    RiteStep(
      id: 'hajj_10_nafr',
      emoji: '🎒',
      titleFr: 'Quitter Minā',
      titleAr: 'النفر',
      place: 'Minā',
      when: 'Le 12 avant le coucher, ou le 13',
      summary:
          "Deux options : partir le 12 après avoir lapidé, à condition d'avoir "
          "quitté Minā avant le coucher du soleil — ou rester le 13 et lapider "
          "une journée de plus, ce qui est préférable.",
      actions: [
        "Départ anticipé (nafr awwal) : lapider les trois stèles le 12 et quitter Minā avant le coucher.",
        "Si le soleil se couche alors qu'on est encore à Minā, on reste et l'on lapide le 13.",
        "Départ tardif (nafr thānī) : rester le 13, lapider après le zawāl, puis partir.",
      ],
      duaIds: ['aid_takbir_muqayyad'],
      counter: null,
      warning: null,
      dayLabel: '11–13 Dhū l-Ḥijja — Ayyām at-Tashrīq',
    ),
    RiteStep(
      id: 'hajj_11_wada',
      emoji: '👋',
      titleFr: "Le ṭawāf d'adieu",
      titleAr: 'طواف الوداع',
      place: 'Masjid al-Ḥarām',
      when: 'Juste avant de quitter La Mecque',
      summary:
          "Le dernier acte : sept tours autour de la Kaʿba, au tout dernier "
          "moment, pour que le dernier contact avec la Maison soit celui-là.",
      actions: [
        "Accomplir sept tours, sans saʿy.",
        "En faire réellement le dernier acte avant le départ.",
        "Invoquer une dernière fois — puis partir sans marcher à reculons, ce qui n'a aucun fondement.",
      ],
      duaIds: ['rabbana_hasana', 'kaffarat_majlis', 'voyage_depart'],
      counter: RiteCounter(
        label: "Tours du ṭawāf d'adieu",
        unit: 'tour',
        target: 7,
        doneMessage: 'Ṭawāf al-wadāʿ accompli — le Hajj est achevé',
      ),
      warning:
          "La femme en menstrues en est dispensée et part sans rien devoir. "
          "Le ṭawāf d'adieu est une obligation secondaire, pas un pilier.",
      dayLabel: 'Départ',
    ),
  ],
);
