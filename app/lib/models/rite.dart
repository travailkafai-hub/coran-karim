/// Modèle d'un rite guidé pas à pas (ʿUmra, Hajj).
///
/// POURQUOI UN MODÈLE À PART, et pas juste une collection de duas
/// (demande utilisateur 2026-07-20 : « avec les étapes, des émoticônes qui
/// définissent les étapes, que ce soit dynamique, avec les invocations et le
/// comptage ») : un pèlerinage n'est PAS une liste de textes à faire défiler.
/// C'est une séquence ORDONNÉE, avec un endroit où l'on se trouve, des actes
/// à accomplir, des comptages contraignants (7 tours, 7 parcours, 7 cailloux
/// × 3 stèles), et surtout une position courante — « où en suis-je ? » — que
/// l'on perd si l'app ne la retient pas. D'où : `RiteStep` ordonnées,
/// `RiteCounter` optionnel par étape, et une progression persistée
/// (cf. `rite_progress_provider.dart`) puisqu'un Hajj s'étale sur six jours.
class Rite {
  final String id;
  final String emoji;
  final String nameFr;
  final String nameAr;
  final String subtitle;

  /// Présentation affichée avant de commencer.
  final String intro;

  /// Conditions/rappels à lire une fois, pas à chaque étape.
  final List<String> essentials;

  final List<RiteStep> steps;

  const Rite({
    required this.id,
    required this.emoji,
    required this.nameFr,
    required this.nameAr,
    required this.subtitle,
    required this.intro,
    required this.essentials,
    required this.steps,
  });

  /// Étiquettes de jour distinctes, dans l'ordre (Hajj). Vide pour la ʿUmra,
  /// qui se fait d'une traite et n'a pas de découpage en journées.
  List<String> get dayLabels {
    final out = <String>[];
    for (final s in steps) {
      final d = s.dayLabel;
      if (d != null && !out.contains(d)) out.add(d);
    }
    return out;
  }
}

class RiteStep {
  final String id;
  final String emoji;
  final String titleFr;
  final String titleAr;

  /// Où l'on se trouve physiquement — « Mīqāt », « Masjid al-Ḥarām »,
  /// « Plaine de ʿArafa ». C'est l'information la plus utile sur place.
  final String place;

  /// Quand — « 8 Dhū l-Ḥijja, matin », « après le coucher du soleil ».
  final String when;

  /// Ce qui se passe à cette étape, en deux ou trois phrases.
  final String summary;

  /// Les gestes concrets, dans l'ordre. C'est la checklist.
  final List<String> actions;

  /// Invocations propres à l'étape, référencées par id dans `kDuasById`.
  final List<String> duaIds;

  /// Compteur éventuel (ṭawāf, saʿy, jamarāt).
  final RiteCounter? counter;

  /// Erreur fréquente ou point de vigilance. Affiché en encadré distinct :
  /// c'est ce qu'un guide dit à voix haute au moment précis.
  final String? warning;

  /// Jour du pèlerinage (Hajj uniquement) — sert à grouper la timeline.
  final String? dayLabel;

  const RiteStep({
    required this.id,
    required this.emoji,
    required this.titleFr,
    required this.titleAr,
    required this.place,
    required this.when,
    required this.summary,
    required this.actions,
    this.duaIds = const [],
    this.counter,
    this.warning,
    this.dayLabel,
  });
}

/// Un comptage à effectuer pendant l'étape.
///
/// `laps` gère le cas des jamarāt : trois stèles, sept cailloux chacune —
/// soit un compteur de 7 remis à zéro trois fois, dont il faut retenir à
/// laquelle on en est. Un simple entier « 21 » ne marcherait pas : on ne
/// lance pas 21 cailloux d'affilée, et se tromper de stèle invalide le rite.
class RiteCounter {
  /// Ce qu'on compte : « Tours autour de la Kaʿba ».
  final String label;

  /// Nom d'une unité : « tour », « parcours », « caillou ».
  final String unit;

  /// Cible par série.
  final int target;

  /// Noms des séries successives. Une seule série ⇒ liste à un élément.
  final List<String> laps;

  /// Texte affiché quand tout est terminé.
  final String doneMessage;

  const RiteCounter({
    required this.label,
    required this.unit,
    required this.target,
    this.laps = const [''],
    required this.doneMessage,
  });

  int get totalTarget => target * laps.length;
  bool get hasLaps => laps.length > 1;
}
