/// L'ENGAGEMENT DE MÉMORISATION — objectif, période, niveau d'accompagnement.
///
/// Cf. `PLAN_COACH.md`. Tout est exprimé en **quarts de Hizb** : c'est déjà
/// l'unité de `portions` et du palier de validation (décision utilisateur
/// 2026-08-13, « on ne peut pas partir sur le Hizb, il ne peut pas réciter
/// d'un coup un Hizb entier »). Aucune conversion nulle part.
library;

/// Sur quelle durée l'utilisateur exprime son objectif. L'app en DÉRIVE les
/// autres horizons (cf. [ObjectifCoach.parJour] / [ObjectifCoach.parSemaine]).
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

/// L'objectif tel que l'utilisateur l'a saisi, et ce qu'on en déduit.
class ObjectifCoach {
  /// Nombre de quarts de Hizb visés sur [periode]. 0 = aucun objectif fixé.
  final int quarts;
  final PeriodeObjectif periode;
  final NiveauCoach niveau;

  const ObjectifCoach({
    this.quarts = 0,
    this.periode = PeriodeObjectif.semaine,
    this.niveau = NiveauCoach.regulier,
  });

  bool get actif => quarts > 0;

  /// Nombre de jours que couvre la période saisie. Le mois est pris à 30 jours
  /// — approximation assumée : l'objectif est un engagement, pas une
  /// comptabilité, et un mois « civil » ferait varier la charge quotidienne
  /// d'un mois à l'autre sans que l'utilisateur comprenne pourquoi.
  int get joursDeLaPeriode => switch (periode) {
        PeriodeObjectif.jour => 1,
        PeriodeObjectif.semaine => 7,
        PeriodeObjectif.mois => 30,
      };

  /// Charge quotidienne théorique, en quarts. Volontairement fractionnaire :
  /// « un Hizb par mois » fait 4 quarts / 30 jours, soit 0,13 par jour — le
  /// dire honnêtement vaut mieux que d'arrondir à 1 et de rendre l'objectif
  /// intenable, ou à 0 et de le rendre vide.
  double get parJour => quarts / joursDeLaPeriode;

  double get parSemaine => parJour * 7;

  /// Quarts attendus depuis le début de la semaine jusqu'à [jour] inclus.
  /// C'est ce qui permet de dire « il t'en reste 2 d'ici dimanche » plutôt que
  /// d'afficher un échec quotidien (cf. PLAN_COACH.md §2 : le jour n'est
  /// qu'une répartition, la semaine fait foi).
  double attenduDansLaSemaineAu(DateTime jour) {
    // Lundi = 1 … dimanche = 7 (DateTime.weekday).
    return parJour * jour.weekday;
  }

  ObjectifCoach copyWith({
    int? quarts,
    PeriodeObjectif? periode,
    NiveauCoach? niveau,
  }) =>
      ObjectifCoach(
        quarts: quarts ?? this.quarts,
        periode: periode ?? this.periode,
        niveau: niveau ?? this.niveau,
      );
}
