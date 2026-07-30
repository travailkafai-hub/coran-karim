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
  /// [fenetreSecondes] = pause minimale valant frontière d'énoncé,
  /// [pasSecondes] = longueur maximale d'un bloc (garde-fou de domaine).
  /// Mesuré sur le flux brut d'une récitation professionnelle : couper aux
  /// silences réels donne 14,86 % d'erreur mot contre 29 à 54 % pour tous les
  /// découpages à longueur imposée. Ce ne sont pas des réglages à retoucher
  /// sans refaire cette mesure.
  static Future<RapportV2?> analyserWav({
    required String wavPath,
    required List<String> mots,
    /// Silence minimal qui vaut frontière d'énoncé (mesuré : 0,5 s).
    double fenetreSecondes = 0.5,
    /// Garde-fou de domaine : les clips d'entraînement font ≤ 20 s.
    double pasSecondes = 18.0,
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

/// Une observation d'un mot par UNE fenêtre. La liste complète est
/// indispensable : sans elle on ne peut pas distinguer « la preuve n'existe
/// pas » de « la preuve existe et la règle de décision l'a ratée ». C'est
/// exactement le trou qui a rendu la piste « préfixe stable » invalidable hors
/// device le 2026-07-29 (58 à 70 aperçus ne laissaient que 0 à 10 verdicts).
class ObsV2 {
  ObsV2(this.fenetre, this.gop, this.free, this.interieur, this.sansCreneau,
      this.frames, this.entendu);
  final int fenetre;
  final double gop;
  final double free;
  final bool interieur;
  final bool sansCreneau;
  final int frames;
  final String entendu;

  bool estVert(double seuil) => gop >= seuil;

  @override
  String toString() => 'f$fenetre ${interieur ? "INT" : "bord"}'
      '${sansCreneau ? "/sansCreneau" : ""} gop=${gop.toStringAsFixed(2)} '
      'free=${free.toStringAsFixed(2)} fr=$frames "$entendu"';
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
    required this.obs,
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
  final List<ObsV2> obs;

  /// Le verdict que donnerait la DERNIÈRE observation intérieure — c'est-à-dire
  /// si l'on ne verrouillait jamais. Séparer ce chiffre du taux verrouillé
  /// répond à UNE question et une seule : la règle de verrouillage fige-t-elle
  /// des erreurs précoces, ou la preuve est-elle fausse de bout en bout ?
  ObsV2? get dernierAvis =>
      obs.where((o) => o.interieur).isEmpty ? null : obs.lastWhere((o) => o.interieur);

  /// Existe-t-il AU MOINS UNE fenêtre qui lit ce mot correctement ? C'est la
  /// borne haute de ce que la preuve acoustique permet : si elle est atteinte,
  /// tout écart restant est imputable à la règle de décision, pas au modèle.
  bool meilleurAvisVert(double seuil) =>
      obs.any((o) => o.interieur && o.gop >= seuil);

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
        obs: [
          for (final o in ((m['obs'] as List?) ?? const []).cast<Map>())
            ObsV2(
              (o['f'] as num).toInt(),
              (o['gop'] as num).toDouble(),
              (o['free'] as num).toDouble(),
              o['int'] as bool,
              (o['sc'] as bool?) ?? false,
              (o['fr'] as num).toInt(),
              (o['e'] as String?) ?? '',
            ),
        ],
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
    // LES TROIS TAUX, qui répondent à trois questions différentes. Les publier
    // ensemble est le seul moyen d'attribuer un écart à la bonne couche.
    final n = indexMaxVotant + 1;
    final sansVerrou = mots
        .where((m) => m.index <= indexMaxVotant)
        .where((m) {
          final d = m.dernierAvis;
          return d == null || d.gop < -0.45;
        })
        .length;
    final borneHaute = mots
        .where((m) => m.index <= indexMaxVotant)
        .where((m) => !m.meilleurAvisVert(-0.45))
        .length;
    b
      ..writeln('[v2] TAUX VERROUILLE   : ${nonVerts.length}/$n = '
          '${(100 * nonVerts.length / n).toStringAsFixed(2)} %  '
          '(la règle des K fenêtres concordantes)')
      ..writeln('[v2] TAUX DERNIER AVIS : $sansVerrou/$n = '
          '${(100 * sansVerrou / n).toStringAsFixed(2)} %  '
          '(si on ne verrouillait jamais)')
      ..writeln('[v2] BORNE HAUTE PREUVE: $borneHaute/$n = '
          '${(100 * borneHaute / n).toStringAsFixed(2)} %  '
          '(mots qu\'AUCUNE fenêtre ne lit juste — imputable au modèle/à '
          'l\'alignement, plus à la décision)');
    for (final m in nonVerts) {
      b.writeln(m.ligne);
      for (final o in m.obs) {
        b.writeln('        $o');
      }
    }
    return b.toString();
  }
}
