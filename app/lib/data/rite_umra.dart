import '../models/rite.dart';

/// La ʿUmra, en neuf étapes.
///
/// Ordre et contenu conformes au hadith de Jābir (Mouslim) et à la pratique
/// enseignée dans les manuels de manāsik. Les divergences d'écoles sur les
/// détails secondaires (formule exacte au Coin yéménite, nombre de prières
/// surérogatoires) ne sont pas arbitrées ici : l'app présente la pratique
/// la plus largement admise et le rappelle dans `essentials`.
const kRiteUmra = Rite(
  id: 'umra',
  emoji: '🕋',
  nameFr: 'ʿUmra',
  nameAr: 'العمرة',
  subtitle: 'Le petit pèlerinage — 9 étapes',
  intro:
      "La ʿUmra peut s'accomplir à n'importe quel moment de l'année et se fait "
      "d'une traite, en quelques heures. Elle tient en quatre actes : entrer en "
      "sacralisation au mīqāt, tourner sept fois autour de la Kaʿba, parcourir "
      "sept fois Ṣafā–Marwa, puis se couper les cheveux. Tout le reste est "
      "recommandation.",
  essentials: [
    "Quatre piliers : l'iḥrām (avec l'intention), le ṭawāf, le saʿy, puis le rasage ou la coupe.",
    "En état d'iḥrām, on s'abstient : de parfum, de couper cheveux et ongles, de chasser, de rapports conjugaux et de tout langage grossier ou dispute.",
    "L'homme porte deux pièces de tissu non cousues et laisse la tête découverte ; la femme garde ses vêtements ordinaires et se découvre le visage et les mains.",
    "La pureté rituelle est requise pour le ṭawāf. Une femme en menstrues accomplit tout le reste et attend d'être pure pour tourner.",
    "En cas de doute sur un nombre de tours, on retient le chiffre le plus BAS et l'on complète.",
  ],
  steps: [
    RiteStep(
      id: 'umra_1_ihram',
      emoji: '🤍',
      titleFr: "Entrer en sacralisation",
      titleAr: 'الإحرام',
      place: 'Au mīqāt — ou à bord, en le survolant',
      when: 'Avant de franchir la limite sacrée',
      summary:
          "L'iḥrām n'est pas le tissu : c'est l'intention. On se purifie, on "
          "revêt les deux pièces blanches, puis on formule l'intention d'entrer "
          "en ʿUmra — et à partir de cet instant les interdits s'appliquent.",
      actions: [
        "Se laver (ghusl), se peigner, se parfumer le corps — jamais le tissu — AVANT d'entrer en iḥrām.",
        "Revêtir l'izār et le ridāʾ pour l'homme ; tenue ordinaire et pudique pour la femme.",
        "Prier deux unités si l'on se trouve à l'heure d'une prière obligatoire ou surérogatoire.",
        "Formuler l'intention : « Labbayka llāhumma ʿumratan » — me voici pour une ʿUmra.",
        "Commencer la Talbiya et la répéter sans cesse à partir de là.",
      ],
      duaIds: ['talbiya'],
      counter: null,
      warning:
          "Franchir le mīqāt sans iḥrām oblige à revenir le reprendre, ou à "
          "compenser par un sacrifice. En avion, l'iḥrām se prend AVANT le "
          "survol : préparez-vous à l'escale ou à l'annonce de l'équipage.",
    ),
    RiteStep(
      id: 'umra_2_route',
      emoji: '🚌',
      titleFr: 'Sur la route de La Mecque',
      titleAr: 'الطريق إلى مكة',
      place: 'Entre le mīqāt et Masjid al-Ḥarām',
      when: 'Durant tout le trajet',
      summary:
          "Le trajet fait partie du rite. La Talbiya se prononce en montant, "
          "en descendant, à chaque changement d'état — les hommes à voix haute, "
          "les femmes à voix basse.",
      actions: [
        "Répéter la Talbiya abondamment.",
        "Multiplier l'invocation libre : le voyageur est de ceux dont l'invocation n'est pas repoussée.",
        "Se préparer intérieurement : c'est le moment de régler ses intentions.",
      ],
      duaIds: ['talbiya', 'voyage_depart', 'voyage_exauce'],
      counter: null,
      warning: null,
    ),
    RiteStep(
      id: 'umra_3_entree',
      emoji: '🕌',
      titleFr: 'Entrer à la Mosquée sacrée',
      titleAr: 'دخول المسجد الحرام',
      place: 'Masjid al-Ḥarām',
      when: 'À l\'arrivée',
      summary:
          "On entre du pied droit avec l'invocation d'entrée à la mosquée. "
          "À la vue de la Kaʿba, on s'arrête : ce moment est réputé de ceux où "
          "l'invocation est exaucée.",
      actions: [
        "Entrer du pied droit en disant l'invocation d'entrée à la mosquée.",
        "En apercevant la Kaʿba, s'arrêter et invoquer librement pour ce qui compte le plus.",
        "Cesser la Talbiya au moment de commencer le ṭawāf.",
      ],
      duaIds: ['mosquee_entree', 'vue_kaaba'],
      counter: null,
      warning:
          "Ici, pas de prière de salutation de la mosquée : à Masjid al-Ḥarām, "
          "elle est remplacée par le ṭawāf lui-même.",
    ),
    RiteStep(
      id: 'umra_4_tawaf',
      emoji: '🔄',
      titleFr: 'Le ṭawāf — sept tours',
      titleAr: 'الطواف',
      place: 'Autour de la Kaʿba',
      when: 'Dès l\'arrivée',
      summary:
          "Sept tours, la Kaʿba à sa gauche, en partant de la Pierre noire et "
          "en y revenant. Chaque tour commence et s'achève au même point.",
      actions: [
        "Se placer face à la Pierre noire, la toucher ou l'embrasser si possible ; sinon la désigner de la main droite en disant « Allāhu akbar » — sans bousculer personne.",
        "Tourner dans le sens inverse des aiguilles d'une montre, la Kaʿba à gauche.",
        "Hommes : découvrir l'épaule droite (iḍṭibāʿ) pendant tout le ṭawāf, et presser le pas (raml) sur les trois premiers tours seulement.",
        "Toucher le Coin yéménite si possible, sans le saluer ni l'embrasser.",
        "Entre le Coin yéménite et la Pierre noire, dire « Rabbanā ātinā… ».",
        "Le reste du tour : invoquer librement, dans sa langue. Aucune formule imposée par tour.",
      ],
      duaIds: ['rabbana_hasana', 'talbiya'],
      counter: RiteCounter(
        label: 'Tours autour de la Kaʿba',
        unit: 'tour',
        target: 7,
        doneMessage: 'Ṭawāf accompli — sept tours',
      ),
      warning:
          "Les formules « spécifiques à chaque tour » que l'on trouve sur "
          "certaines fiches n'ont aucun fondement établi. Invoquez librement : "
          "c'est la pratique rapportée du Prophète ﷺ.",
    ),
    RiteStep(
      id: 'umra_5_maqam',
      emoji: '🙏',
      titleFr: 'Deux unités derrière le Maqām',
      titleAr: 'ركعتا الطواف',
      place: "Derrière la station d'Ibrāhīm",
      when: 'Juste après les sept tours',
      summary:
          "On prie deux unités derrière la station d'Ibrāhīm si l'espace le "
          "permet, sinon n'importe où dans la mosquée. La foule ne doit jamais "
          "servir de prétexte à gêner les autres.",
      actions: [
        "Réciter le verset : « Et faites de la station d'Ibrāhīm un lieu de prière. »",
        "Prier deux unités : Al-Kāfirūn dans la première, Al-Ikhlāṣ dans la seconde.",
        "Remettre l'épaule droite couverte avant de prier.",
      ],
      duaIds: ['sobh_sunna'],
      counter: null,
      warning:
          "Si la zone est saturée, priez plus loin. Prier collé au Maqām en "
          "bloquant le flux des pèlerins n'est pas une vertu.",
    ),
    RiteStep(
      id: 'umra_6_zamzam',
      emoji: '💧',
      titleFr: "Boire l'eau de Zamzam",
      titleAr: 'شرب ماء زمزم',
      place: 'Fontaines de Zamzam',
      when: 'Après les deux unités',
      summary:
          "On boit à satiété, en formulant son intention : « l'eau de Zamzam "
          "est pour ce pour quoi on la boit ».",
      actions: [
        "Boire en trois gorgées, face à la qibla.",
        "Formuler intérieurement ce que l'on demande — science, guérison, subsistance.",
        "S'en verser sur la tête si on le souhaite.",
      ],
      duaIds: ['zamzam'],
      counter: null,
      warning: null,
    ),
    RiteStep(
      id: 'umra_7_say',
      emoji: '🏃',
      titleFr: 'Le saʿy — sept parcours',
      titleAr: 'السعي بين الصفا والمروة',
      place: 'Entre Ṣafā et Marwa',
      when: 'Après le ṭawāf',
      summary:
          "Sept parcours entre les deux collines. Attention au décompte : "
          "Ṣafā → Marwa vaut UN parcours, Marwa → Ṣafā en vaut un second. "
          "On commence à Ṣafā et l'on termine à Marwa.",
      actions: [
        "Monter sur Ṣafā, se tourner vers la Kaʿba, lever les mains et dire le dhikr de Ṣafā, puis invoquer librement — trois fois.",
        "Marcher vers Marwa ; les hommes pressent le pas entre les deux repères verts.",
        "Sur Marwa, faire de même que sur Ṣafā.",
        "Enchaîner jusqu'au septième parcours, qui s'achève à Marwa.",
      ],
      duaIds: ['safa_marwa', 'rabbana_hasana'],
      counter: RiteCounter(
        label: 'Parcours Ṣafā ⇄ Marwa',
        unit: 'parcours',
        target: 7,
        doneMessage: 'Saʿy accompli — sept parcours, fin à Marwa',
      ),
      warning:
          "L'erreur classique est de compter un aller-retour comme un seul "
          "parcours : on finirait alors à Ṣafā après quatorze traversées. "
          "Le compte impair garantit une fin à Marwa.",
    ),
    RiteStep(
      id: 'umra_8_halq',
      emoji: '✂️',
      titleFr: 'Se raser ou se couper les cheveux',
      titleAr: 'الحلق أو التقصير',
      place: 'À Marwa ou aux alentours',
      when: 'Immédiatement après le saʿy',
      summary:
          "Le dernier pilier. L'homme se rase entièrement (préférable) ou se "
          "raccourcit uniformément ; la femme coupe l'équivalent d'une phalange "
          "sur l'ensemble de ses mèches.",
      actions: [
        "Homme : rasage complet — « Allah a fait miséricorde à ceux qui se rasent » — ou raccourcissement sur TOUTE la tête.",
        "Femme : rassembler ses cheveux et couper environ la longueur d'une phalange.",
        "Ne jamais raccourcir seulement quelques mèches : la coupe doit couvrir toute la tête.",
      ],
      duaIds: [],
      counter: null,
      warning:
          "Celui qui se rase la tête pour une ʿUmra faite peu avant le Hajj "
          "de tamattuʿ n'aura peut-être pas repoussé d'ici le 10 Dhū l-Ḥijja : "
          "un simple raccourcissement suffit alors, pour pouvoir se raser au Hajj.",
    ),
    RiteStep(
      id: 'umra_9_tahallul',
      emoji: '🎊',
      titleFr: "Sortie de l'état de sacralisation",
      titleAr: 'التحلل',
      place: 'La Mecque',
      when: 'Dès la coupe achevée',
      summary:
          "La ʿUmra est terminée. Tous les interdits de l'iḥrām sont levés : "
          "vêtements ordinaires, parfum, vie conjugale.",
      actions: [
        "Reprendre ses vêtements habituels.",
        "Remercier Allah pour ce qui vient d'être accompli.",
        "Profiter du séjour pour multiplier les ṭawāf surérogatoires — une prière à Masjid al-Ḥarām vaut cent mille prières ailleurs.",
      ],
      duaIds: ['kaffarat_majlis', 'rabbana_hasana'],
      counter: null,
      warning: null,
    ),
  ],
);
