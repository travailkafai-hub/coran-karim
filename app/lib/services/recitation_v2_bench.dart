import 'package:flutter/services.dart';

/// Banc de la chaîne de récitation **v2** (package Kotlin `recitation2`).
///
/// Rejoue un WAV complet dans la chaîne v2, bloc de 80 ms par bloc de 80 ms,
/// avec le vrai modèle causal — et rend, pour chaque mot attendu, son statut et
/// ses preuves.
///
/// **Pourquoi le banc vit ici et pas en Python** : deux jours de suite, une
/// ré-implémentation Python de la politique de découpage a produit des
/// prédictions confiantes et fausses (« le banc mesurait mon découpage, pas
/// l'app »). La chaîne v2 est écrite en couches pures pour que le banc puisse
/// **appeler le code de l'app** au lieu de l'imiter. Ce fichier n'est que le
/// déclencheur ; toute la logique mesurée est celle qui tournera sur device.
///
/// Ne touche à **rien** du chemin v1 : aucun état partagé, aucune instance
/// commune. Les deux chaînes coexistent le temps de la comparaison à WAV
/// identique (banc 4 de `CONCEPTION_RECITATION_V2.md`).
class RecitationV2Bench {
  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');

  /// [mots] : le texte attendu, déjà normalisé comme le corpus d'entraînement
  /// (`ArabicNormalizer.normalizeTraining`, jamais `normalizeStrict`).
  ///
  /// [fenetreSecondes] / [pasSecondes] : les **deux seuls** paramètres de
  /// segmentation de la v2. Ils se fixent par le balayage du banc 1
  /// (couverture intérieure), pas par un réglage en cours de session.
  static Future<RapportV2?> analyserWav({
    required String wavPath,
    required List<String> mots,
    double fenetreSecondes = 6.0,
    double pasSecondes = 1.5,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'v2AnalyserWav',
      {
        'wavPath': wavPath,
        'mots': mots,
        'fenetreSecondes': fenetreSecondes,
        'pasSecondes': pasSecondes,
      },
    );
    if (res == null) return null;
    return RapportV2.depuisPayload(res);
  }
}

class MotV2 {
  MotV2({
    required this.index,
    required this.mot,
    required this.statut,
    required this.observations,
    required this.interieures,
    required this.gop,
    required this.free,
    required this.forced,
    required this.entendu,
  });

  final int index;
  final String mot;

  /// `inconnu` | `provisoire:vert|orange|rouge` | `definitif:...` | `omis`.
  ///
  /// `omis` **n'est pas une couleur** : c'est « le récitateur est passé outre,
  /// et on peut le prouver ». Sans ce statut un mot sauté redevient invisible —
  /// le vrai défaut de la version v22, où les mots enjambés quittaient
  /// silencieusement le dénominateur.
  final String statut;

  final int observations;
  final int interieures;
  final double? gop;
  final double? free;
  final double? forced;
  final String entendu;

  bool get estVert => statut.endsWith(':vert');
  bool get estDefinitif => statut.startsWith('definitif:');

  /// Ligne du tableau imposé pour l'analyse de session : un mot non vert par
  /// ligne, avec `gop` ET `free`. Un `gop` effondré avec un `free` proche de 0
  /// veut dire **mauvaise position**, pas mauvaise prononciation — les
  /// confondre a déjà fait chercher au mauvais endroit plusieurs fois.
  String get ligne =>
      '${index.toString().padLeft(3)}  ${mot.padRight(14)} $statut  '
      'gop=${gop?.toStringAsFixed(2) ?? "-"}  '
      'free=${free?.toStringAsFixed(2) ?? "-"}  '
      'obs=$observations (int=$interieures)  entendu="$entendu"';
}

class RapportV2 {
  RapportV2({
    required this.dureeAudioMs,
    required this.dureeCalculMs,
    required this.indexMaxVotant,
    required this.observations,
    required this.mots,
    required this.journal,
  });

  final int dureeAudioMs;
  final int dureeCalculMs;

  /// Dernier mot ayant reçu une preuve **votante**. C'est le dénominateur
  /// honnête d'un taux : compter sur les mots *jugés* fait sortir du calcul
  /// tout mot jamais observé — erreur de méthode déjà commise.
  final int indexMaxVotant;

  final int observations;
  final List<MotV2> mots;
  final List<String> journal;

  static RapportV2 depuisPayload(Map<String, dynamic> p) {
    final mots = <MotV2>[];
    for (final m in (p['mots'] as List).cast<Map>()) {
      mots.add(MotV2(
        index: m['i'] as int,
        mot: m['mot'] as String,
        statut: m['statut'] as String,
        observations: m['observations'] as int,
        interieures: m['interieures'] as int,
        gop: (m['gop'] as num?)?.toDouble(),
        free: (m['free'] as num?)?.toDouble(),
        forced: (m['forced'] as num?)?.toDouble(),
        entendu: (m['entendu'] as String?) ?? '',
      ));
    }
    return RapportV2(
      dureeAudioMs: (p['dureeAudioMs'] as num).toInt(),
      dureeCalculMs: (p['dureeCalculMs'] as num).toInt(),
      indexMaxVotant: (p['indexMaxVotant'] as num).toInt(),
      observations: (p['observations'] as num).toInt(),
      mots: mots,
      journal: (p['journal'] as List).cast<String>(),
    );
  }

  /// Part du temps réel consommée par l'inférence. C'est une **propriété de
  /// conception** de la v2 (durée de fenêtre × cadence), pas une conséquence à
  /// constater : elle doit rester constante quelle que soit la longueur de la
  /// session.
  double get chargeTempsReel =>
      dureeAudioMs == 0 ? 0 : dureeCalculMs / dureeAudioMs;

  List<MotV2> get nonVerts =>
      mots.where((m) => m.index <= indexMaxVotant && !m.estVert).toList();

  /// Compte rendu au format imposé : le tableau ligne par ligne des non-verts,
  /// jamais une statistique agrégée à sa place.
  String get compteRendu {
    final b = StringBuffer()
      ..writeln('[v2] audio ${(dureeAudioMs / 1000).toStringAsFixed(1)}s  '
          'calcul ${dureeCalculMs}ms  '
          'charge ${(chargeTempsReel * 100).toStringAsFixed(0)}% du temps réel')
      ..writeln('[v2] ancre max $indexMaxVotant / ${mots.length} mots  '
          '$observations observations')
      ..writeln('[v2] non verts : ${nonVerts.length} / ${indexMaxVotant + 1} '
          '(${(100 * nonVerts.length / (indexMaxVotant + 1)).toStringAsFixed(2)} %)');
    for (final m in nonVerts) {
      b.writeln(m.ligne);
    }
    return b.toString();
  }
}
