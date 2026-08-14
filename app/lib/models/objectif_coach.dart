/// L'ENGAGEMENT DE MÉMORISATION — durée pour tout le Coran, niveau
/// d'accompagnement, et le rythme que l'app en DÉRIVE.
///
/// Cf. `PLAN_COACH.md`. Tout est exprimé en **quarts de Hizb** : c'est déjà
/// l'unité de `portions` et du palier de validation (décision utilisateur
/// 2026-08-13, « on ne peut pas partir sur le Hizb, il ne peut pas réciter
/// d'un coup un Hizb entier »). Aucune conversion nulle part.
///
/// ── L'OBJECTIF EST UNE DURÉE, PLUS UN VOLUME (2026-08-14) ──────────────────
///
/// AVANT : l'utilisateur saisissait « N quarts par jour / semaine / mois ».
/// Jugé illisible par l'utilisateur, capture d'écran à l'appui : « je trouve
/// que objectif par jour c'est beaucoup ». Le défaut est de fond, pas
/// cosmétique — un volume par période ne dit RIEN de ce vers quoi il mène :
/// « 4 quarts par semaine », c'est combien d'années de Coran ? Personne ne
/// fait ce calcul, et un engagement dont on ne voit pas le bout n'engage pas.
///
/// MAINTENANT : l'objectif est **mémoriser tout le Coran**, l'utilisateur
/// choisit en combien d'ANNÉES, et l'app affiche ce que ça donne par jour, par
/// semaine et par mois. Le sens est donné d'emblée, le rythme est dérivé.
library;

/// Horizon d'affichage du rythme. N'est PLUS un réglage utilisateur depuis le
/// 2026-08-14 (l'objectif se saisit en années, cf. [ObjectifCoach.annees]) --
/// conservé parce que les trois horizons restent affichés, et parce que les
/// libellés l10n correspondants sont toujours utilisés.
enum PeriodeObjectif { jour, semaine, mois }

/// Combien l'application relance l'utilisateur.
///
/// Nommés par ce que l'utilisateur REÇOIT, pas par l'agressivité de l'app :
/// « strict » décrivait une sévérité de jugement alors qu'il s'agit d'une
/// fréquence de rappel (arbitré avec l'utilisateur le 2026-08-13).
enum NiveauCoach {
  /// Aucun rappel. Les objectifs restent affichés, purement indicatifs.
  aMonRythme,

  /// Un rappel par jour, un bilan hebdomadaire. Silencieux si l'objectif du
  /// jour est déjà atteint.
  regulier,

  /// Relances multiples, rappel des versets souvent ratés, alerte quand la
  /// série ou la semaine est en danger.
  exigeant,
}

/// Le rythme requis pour tenir l'échéance, à un instant donné.
///
/// Tout y est DÉRIVÉ de deux choses : la durée choisie, et ce qui reste à
/// mémoriser. Rien n'y est saisi ni stocké — recalculé à chaque lecture, il ne
/// peut donc jamais se désynchroniser de la progression réelle.
class RythmeCoach {
  /// Quarts de Hizb qu'il reste à acquérir (0 à 240).
  final double quartsRestants;

  /// Volontairement fractionnaire : à 6 ans, la charge est de 0,11 quart par
  /// jour. Le dire honnêtement vaut mieux que d'arrondir à 1 (objectif
  /// intenable) ou à 0 (objectif vide).
  final double parJour;
  final double parSemaine;
  final double parMois;

  /// Cible mensuelle affichée, en quarts ENTIERS. La fenêtre du tableau de
  /// bord est le mois précisément pour ça : c'est le seul horizon où la cible
  /// tombe sur un entier lisible quelle que soit la durée choisie (20 quarts à
  /// 1 an, 3 à 6 ans). Sur la semaine, elle vaudrait 0,8 -- et l'app a déjà
  /// affiché « 0 sur 0.2 quart(s) » une fois, ce que l'utilisateur n'a pas
  /// compris (constat 2026-08-14).
  int get cibleDuMois {
    final c = parMois.round();
    return c < 1 ? 1 : c;
  }

  /// Cible annuelle affichée, en quarts entiers. Même raison que
  /// [cibleDuMois] : un entier, jamais une décimale.
  int get cibleDeLAnnee {
    final c = (parJour * 365).round();
    return c < 1 ? 1 : c;
  }

  /// Seuil quotidien qui décide si la journée compte pour la SÉRIE, en mots.
  ///
  /// Converti en mots parce qu'un quart entier est rarement récité d'un coup
  /// sur un objectif long : sans conversion, une échéance à 6 ans n'aurait
  /// presque aucun jour « atteint », et la série ne servirait plus à rien.
  ///
  /// PLANCHER (2026-08-14) : sans lui, une échéance lointaine rendrait la
  /// série automatique -- à 6 ans le seuil brut tombe à ~35 mots, soit
  /// An-Nasr (23 mots) plus une ligne. Une série qui ne peut pas se rompre ne
  /// mesure plus l'assiduité, elle la décore. 50 mots ≈ une courte sourate :
  /// c'est le minimum en dessous duquel « avoir récité aujourd'hui » ne veut
  /// plus rien dire.
  static const int plancherMotsParJour = 50;

  int get seuilMotsParJour {
    final brut = (parJour * ObjectifCoach.motsParQuart).ceil();
    return brut < plancherMotsParJour ? plancherMotsParJour : brut;
  }

  const RythmeCoach({
    required this.quartsRestants,
    required this.parJour,
    required this.parSemaine,
    required this.parMois,
  });

  static const RythmeCoach aucun = RythmeCoach(
    quartsRestants: 0,
    parJour: 0,
    parSemaine: 0,
    parMois: 0,
  );
}

/// Où en est le récitant PAR RAPPORT à ce qui était attendu de lui à cette
/// date — ce que la couleur de la barre traduit à l'écran.
///
/// Demande utilisateur (2026-08-14) : « je veux que la couleur ait un sens :
/// vert c'est que je suis dans le rythme, orange ça dérape un peu, rouge il
/// faut que je progresse pour rattraper l'objectif du mois ».
///
/// ── POURQUOI CE N'EST PAS LE POURCENTAGE DE LA BARRE ────────────────────
///
/// La barre montre l'avancement vers la cible de la fenêtre (mois, année).
/// L'ÉTAT, lui, compare cet avancement à ce qui était attendu COMPTE TENU DU
/// TEMPS DÉJÀ SUIVI : quelqu'un qui utilise l'app depuis trois jours est à 10 %
/// de sa cible mensuelle, et c'est parfaitement dans le rythme. Sans cette
/// pondération, tout nouvel utilisateur verrait rouge dès le premier jour --
/// exactement la culpabilisation que le §2 du plan refuse.
enum EtatRythme {
  /// Au moins ce qui était attendu à cette date.
  tenu,

  /// Entre 70 % et 100 % de l'attendu : ça dérape, rien n'est perdu.
  derape,

  /// Moins de 70 % : il faut progresser pour rattraper la fenêtre.
  aRattraper;

  /// [attendu] à 0 (aucun jour suivi encore) vaut [tenu] : on ne peut pas être
  /// en retard sur une période qui n'a pas commencé.
  static EtatRythme depuis({required double fait, required double attendu}) {
    if (attendu <= 0) return EtatRythme.tenu;
    final tenue = fait / attendu;
    if (tenue >= 1.0) return EtatRythme.tenu;
    if (tenue >= 0.7) return EtatRythme.derape;
    return EtatRythme.aRattraper;
  }
}

/// L'objectif tel que l'utilisateur l'a saisi, et ce qu'on en déduit.
class ObjectifCoach {
  /// Le Coran entier : 60 Hizb × 4 quarts.
  static const int quartsDuCoran = 240;

  /// ~77 430 mots de Coran pour 240 quarts. Sert UNIQUEMENT à convertir un
  /// rythme en quarts vers un seuil quotidien en mots (cf.
  /// [RythmeCoach.seuilMotsParJour]) et à mesurer les quarts acquis à partir
  /// des mots acquis. Jamais à afficher un nombre de mots.
  static const double motsDuCoran = 77430;
  static const double motsParQuart = motsDuCoran / quartsDuCoran;

  /// Bornes du curseur de la feuille de réglage (décision utilisateur
  /// 2026-08-14 : « curseur de 1 an à 6 ans »).
  static const int anneesMin = 1;
  static const int anneesMax = 6;

  /// En combien d'années mémoriser tout le Coran. 0 = aucun objectif fixé.
  final int annees;
  final NiveauCoach niveau;

  const ObjectifCoach({
    this.annees = 0,
    this.niveau = NiveauCoach.regulier,
  });

  bool get actif => annees > 0;

  /// Nombre de jours que couvre l'échéance. 365 jours pleins par année —
  /// approximation assumée : l'objectif est un engagement, pas une
  /// comptabilité, et compter les bissextiles ferait bouger le rythme affiché
  /// sans que l'utilisateur comprenne pourquoi.
  int get joursDeLEcheance => annees * 365;

  /// Le rythme requis compte tenu de ce qui est DÉJÀ ACQUIS (décision
  /// utilisateur 2026-08-14 : l'échéance porte sur le reste à mémoriser).
  ///
  /// Conséquence voulue : le rythme se détend au fur et à mesure, et un
  /// utilisateur qui connaît déjà 10 Hizb ne se voit pas imposer un rythme
  /// calculé sur ce qu'il sait déjà. Conséquence assumée : le chiffre affiché
  /// baisse tout seul quand un quart est acquis — c'est une bonne nouvelle,
  /// pas une instabilité.
  RythmeCoach rythmePour(double quartsAcquis) {
    if (!actif) return RythmeCoach.aucun;
    final restant =
        (quartsDuCoran - quartsAcquis).clamp(0.0, quartsDuCoran.toDouble());
    final parJour = restant / joursDeLEcheance;
    return RythmeCoach(
      quartsRestants: restant,
      parJour: parJour,
      parSemaine: parJour * 7,
      parMois: parJour * 30,
    );
  }

  // ── RETIRÉ LE 2026-08-14 AVEC LA REFONTE, GARDER LA TRACE ────────────────
  //   double attenduDansLaSemaineAu(DateTime jour) => parJour * jour.weekday;
  // Elle disait « où devrais-je en être ce mercredi », pour afficher la dette
  // de la semaine (« il t'en reste 2 d'ici dimanche », PLAN_COACH.md §2)
  // plutôt qu'un échec quotidien. Elle n'a JAMAIS été appelée : le tableau de
  // bord a toujours comparé un cumul de période à une cible, sans passer par
  // un attendu au prorata du jour. Retirée parce que la fenêtre est désormais
  // le MOIS, où un prorata par jour de semaine n'a plus de sens. Si la dette
  // intra-période revient un jour, c'est sur le mois qu'il faut la calculer.

  ObjectifCoach copyWith({
    int? annees,
    NiveauCoach? niveau,
  }) =>
      ObjectifCoach(
        annees: annees ?? this.annees,
        niveau: niveau ?? this.niveau,
      );
}
