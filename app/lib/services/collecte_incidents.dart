// Ce que la collecte retient pendant une récitation : les endroits où l'app a
// signalé quelque chose — rien d'autre.
//
// ── POURQUOI CE SERVICE NE TOUCHE À AUCUN VERDICT ───────────────────────
//
// Il s'abonne à `alignedWords`, un flux que RIEN d'autre ne consomme dans
// l'application (vérifié : aucun autre `listen` dessus). La chaîne qui peint
// l'écran passe par un autre canal. Écouter ici ne peut donc ni retarder ni
// modifier un jugement — c'est une dérivation, pas une interception.
//
// ── UN INCIDENT, PAS UNE SÉANCE ─────────────────────────────────────────
//
// Demande utilisateur : « c'est pas toute la récitation, seulement où le
// model/app a raté la séquence ». Un incident = un mot signalé, avec ses deux
// voisins entiers pour le contexte (cf. `CollecteExtrait`), le verdict de
// l'app, et — c'est le point capital — la place pour LA RÉPONSE DE LA
// PERSONNE.
//
// Cette réponse est ce qui donne sa valeur au corpus. Un enregistrement brut
// ne dit pas si le modèle avait tort ; un « c'était juste » transforme le clip
// en exemple dont la transcription est CERTAINE, et c'est précisément ce qui
// manque à un corpus collecté en vrac.

import '../services/fastconformer_verifier.dart' show AlignPayload;

/// Ce que la personne pense du verdict de l'application.
enum AvisSurVerdict {
  /// « C'était juste » — le modèle s'est trompé. Le texte attendu EST la
  /// vérité de ce qui a été prononcé : exemple d'entraînement sûr.
  appSeTrompe,

  /// « Oui, je me suis trompé » — le signalement était bon. L'audio reste
  /// utile, mais sa transcription réelle est INCONNUE (on ignore ce qui a été
  /// prononcé à la place) : à annoter à la main avant tout entraînement.
  fauteReelle,
}

class Incident {
  /// Clip du segment que la chaîne a analysé — c'est dans ce fichier que se
  /// découpe l'extrait.
  final String clipPath;
  final int samplesParFrame;

  /// Bornes de l'extrait : premier voisin → dernier voisin.
  final int debutFrame;
  final int finFrame;

  /// Index absolu du mot signalé dans le texte attendu.
  final int indexMot;

  /// Le mot signalé, et le texte COMPLET de l'extrait (les trois mots) — c'est
  /// ce second champ qui sert de transcription au manifeste d'entraînement.
  final String motAttendu;
  final String texteExtrait;

  /// Ce que le modèle a lu à cet endroit, et son écart.
  final String entendu;
  final double gop;

  AvisSurVerdict? avis;

  Incident({
    required this.clipPath,
    required this.samplesParFrame,
    required this.debutFrame,
    required this.finFrame,
    required this.indexMot,
    required this.motAttendu,
    required this.texteExtrait,
    required this.entendu,
    required this.gop,
    this.avis,
  });
}

class CollecteIncidents {
  /// Au-delà, on cesse de retenir : une séance où tout est signalé est le
  /// signe d'un problème de chaîne, pas un corpus à collecter — et on ne va
  /// pas demander cinquante fois son avis à quelqu'un.
  static const int kMaxParSeance = 12;

  static final List<Incident> _courants = [];

  static List<Incident> get courants => List.unmodifiable(_courants);

  static void vider() => _courants.clear();

  /// Retient les mots signalés d'un segment figé.
  ///
  /// [estSignale] dit, pour un index absolu, si l'application a affiché autre
  /// chose que du vert — le provider le sait, ce service non.
  /// [motAttendu] rend le texte attendu d'un index, ou `null` hors cible.
  static void observer(
    AlignPayload payload, {
    required bool Function(int index) estSignale,
    required String? Function(int index) motAttendu,
  }) {
    // Sans clip, pas d'audio à envoyer : un incident sans son n'apprend rien.
    final clip = payload.clipPath;
    if (clip == null || !payload.isFinal || payload.samplesParFrame <= 0) return;
    if (_courants.length >= kMaxParSeance) return;

    for (final mot in payload.words) {
      if (_courants.length >= kMaxParSeance) return;
      if (!estSignale(mot.index)) continue;
      // `-1` = la DP n'a rien placé : on ne saurait pas où découper, et
      // extraire au hasard serait pire que ne rien envoyer.
      if (mot.firstFrame < 0 || mot.lastFrame < mot.firstFrame) continue;
      if (_courants.any((i) => i.indexMot == mot.index)) continue;

      // UN MOT DE CHAQUE CÔTÉ. On cherche les voisins DANS CE SEGMENT : un
      // voisin qui n'y est pas n'a pas d'audio ici, et l'extrait s'arrête donc
      // au bord du segment plutôt que de déborder sur un clip qu'on n'a pas.
      final avant = payload.words
          .where((w) => w.index == mot.index - 1 && w.firstFrame >= 0);
      final apres = payload.words
          .where((w) => w.index == mot.index + 1 && w.lastFrame >= 0);
      final debut =
          avant.isEmpty ? mot.firstFrame : avant.first.firstFrame;
      final fin = apres.isEmpty ? mot.lastFrame : apres.first.lastFrame;

      final texte = [
        if (avant.isNotEmpty) motAttendu(mot.index - 1),
        motAttendu(mot.index),
        if (apres.isNotEmpty) motAttendu(mot.index + 1),
      ].whereType<String>().where((t) => t.isNotEmpty).join(' ');
      if (texte.isEmpty) continue; // sans transcription, l'extrait est inutile

      _courants.add(Incident(
        clipPath: clip,
        samplesParFrame: payload.samplesParFrame,
        debutFrame: debut,
        finFrame: fin,
        indexMot: mot.index,
        motAttendu: motAttendu(mot.index) ?? '',
        texteExtrait: texte,
        entendu: mot.actual,
        gop: mot.gop,
      ));
    }
  }
}
