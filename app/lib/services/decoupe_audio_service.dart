import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log.dart';

/// Frontières d'un mot dans l'audio d'un récitateur, en millisecondes absolues
/// dans le fichier de sourate. `debutMs = -1` : le mot n'a pas pu être localisé.
class BorneMot {
  final int index;
  final int debutMs;
  final int finMs;
  const BorneMot(this.index, this.debutMs, this.finMs);

  bool get localise => debutMs >= 0;

  Map<String, dynamic> toJson() => {'i': index, 'd': debutMs, 'f': finMs};
  factory BorneMot.fromJson(Map<String, dynamic> j) =>
      BorneMot(j['i'] as int, j['d'] as int, j['f'] as int);
}

/// Un silence assez long pour qu'on puisse s'y arrêter. [apres] est l'index du
/// dernier mot AVANT le silence.
class CoupeMesuree {
  final int apres;
  final int silenceMs;
  const CoupeMesuree(this.apres, this.silenceMs);

  Map<String, dynamic> toJson() => {'a': apres, 's': silenceMs};
  factory CoupeMesuree.fromJson(Map<String, dynamic> j) =>
      CoupeMesuree(j['a'] as int, j['s'] as int);
}

class DecoupeVerset {
  final List<BorneMot> mots;
  final List<CoupeMesuree> coupes;
  const DecoupeVerset(this.mots, this.coupes);

  /// Combien de mots ont été réellement localisés.
  int get localises => mots.where((m) => m.localise).length;

  Map<String, dynamic> toJson() => {
        'mots': mots.map((m) => m.toJson()).toList(),
        'coupes': coupes.map((c) => c.toJson()).toList(),
      };
  factory DecoupeVerset.fromJson(Map<String, dynamic> j) => DecoupeVerset(
        (j['mots'] as List)
            .map((e) => BorneMot.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        (j['coupes'] as List)
            .map((e) => CoupeMesuree.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// ── L'AUDIO PILOTE, LE TEXTE SUIT (2026-09-06) ─────────────────────────────
///
/// Demande de l'utilisateur, après avoir entendu le décalage entre le texte
/// d'un palier et l'audio joué : « je suis plus pour l'audio car il s'arrête au
/// bon moment des waqf ou silence, alors que le texte non » — puis « il faut
/// juste partir d'un pour déduire l'autre au lieu d'avoir deux chemins ; en
/// premier l'audio qui pilote, on découpe l'audio puis on affiche le texte ».
///
/// CE QUE CE SERVICE REMPLACE. Trois mécaniques indépendantes coexistaient, et
/// aucune ne regardait l'audio qui joue vraiment :
///   * `coupes_palier_afasy.json` — des coupes d'énergie mesurées sur
///     l'enregistrement d'AL-AFASY. Le fichier le dit lui-même : « c'est la
///     lecture d'UN récitateur, mesurée sur SON enregistrement ; un autre
///     récitateur phraserait autrement ».
///   * en Warsh, des minutages mot à mot « ESTIMÉS — découpe pondérée, non
///     mesurée » (proportionnels à la longueur des mots).
///   * une mise à l'échelle par le rapport des durées de verset, ajoutée la
///     veille pour rattraper l'écart de débit.
///
/// Ici, une seule source : l'audio du récitateur, passé dans l'aligneur du
/// modèle. Les frontières de mots en sortent, et les coupes s'en DÉDUISENT —
/// un trou entre deux mots est un silence de cette voix-là.
///
/// COÛT ET CACHE. Un verset d'une quarantaine de secondes coûte quelques
/// secondes d'encodeur. C'est trop pour le refaire à chaque tour de palier, et
/// négligeable une fois par (récitateur, verset). Le résultat est donc écrit
/// sur disque ; seul le PREMIER passage sur un verset paie. L'audio, lui,
/// n'est jamais converti en entier : le natif ne décode que la plage demandée
/// (choix validé — convertir une sourate entière coûterait des centaines de Mo).
///
/// ⚠️ CE SERVICE NE JUGE RIEN. Il ne rend que des positions. La chaîne qu'il
/// fait tourner côté natif est LOCALE et ne touche pas la session en cours.
class DecoupeAudioService {
  DecoupeAudioService._();
  static final instance = DecoupeAudioService._();

  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');

  final Map<String, DecoupeVerset> _memoire = {};
  final Map<String, Future<DecoupeVerset?>> _enCours = {};
  Directory? _dossier;

  String _cle(int reciterId, int surah, int ayah) => '$reciterId-$surah-$ayah';

  Future<Directory> _dossierCache() async {
    if (_dossier != null) return _dossier!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/decoupes');
    if (!await d.exists()) await d.create(recursive: true);
    return _dossier = d;
  }

  /// La découpe mesurée de ce verset, ou `null` si elle n'a pas pu être faite.
  ///
  /// [chemin] : le fichier de sourate DÉJÀ téléchargé localement.
  /// [debutMs]/[finMs] : les bornes du verset dans ce fichier (elles viennent
  /// d'`ayatTiming`, mesurées pour ce récitateur — c'est la seule chose qu'on
  /// lui emprunte encore, et elle est juste).
  ///
  /// UN APPEL À LA FOIS PAR VERSET : deux écrans peuvent demander le même
  /// verset en même temps (le palier et sa lecture audio). Sans `_enCours`, on
  /// paierait deux passes d'encodeur pour le même résultat.
  Future<DecoupeVerset?> pour({
    required int reciterId,
    required int surah,
    required int ayah,
    required String chemin,
    required int debutMs,
    required int finMs,
    required List<String> mots,
  }) async {
    final cle = _cle(reciterId, surah, ayah);
    final enMemoire = _memoire[cle];
    if (enMemoire != null) return enMemoire;
    final dejaLance = _enCours[cle];
    if (dejaLance != null) return dejaLance;

    final futur = _calculer(cle, chemin, debutMs, finMs, mots);
    _enCours[cle] = futur;
    try {
      return await futur;
    } finally {
      _enCours.remove(cle);
    }
  }

  Future<DecoupeVerset?> _calculer(String cle, String chemin, int debutMs,
      int finMs, List<String> mots) async {
    // Cache disque d'abord : il survit au redémarrage, et c'est tout l'intérêt
    // de payer une passe d'encodeur une seule fois.
    try {
      final f = File('${(await _dossierCache()).path}/$cle.json');
      if (await f.exists()) {
        final d = DecoupeVerset.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        // Un cache écrit pour un texte plus court (verset re-découpé depuis)
        // est inutilisable : mieux vaut le recalculer que de décaler tout le
        // palier d'un mot.
        if (d.mots.length == mots.length) return _memoire[cle] = d;
      }
    } catch (e) {
      DiagnosticLog.log('Decoupe', 'cache illisible ($cle) : $e');
    }

    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'v2DecouperVerset', {
        'chemin': chemin,
        'debutMs': debutMs,
        'finMs': finMs,
        'mots': mots,
      });
      if (r == null) return null;
      final bornes = <BorneMot>[];
      for (final e in (r['mots'] as List)) {
        final m = (e as Map);
        bornes.add(BorneMot((m['i'] as num).toInt(),
            (m['debutMs'] as num).toInt(), (m['finMs'] as num).toInt()));
      }
      final coupes = <CoupeMesuree>[];
      for (final e in (r['coupes'] as List)) {
        final c = (e as Map);
        coupes.add(CoupeMesuree(
            (c['apres'] as num).toInt(), (c['silenceMs'] as num).toInt()));
      }
      final d = DecoupeVerset(bornes, coupes);
      DiagnosticLog.log('Decoupe',
          '$cle : ${d.localises}/${mots.length} mot(s) localise(s), '
          '${coupes.length} coupe(s) mesuree(s)');
      _memoire[cle] = d;
      unawaitedEcrire(cle, d);
      return d;
    } catch (e) {
      DiagnosticLog.log('Decoupe', 'ECHEC $cle : $e');
      return null;
    }
  }

  /// Écriture best-effort : une découpe non persistée sera simplement
  /// recalculée, elle ne doit jamais faire échouer l'appel.
  void unawaitedEcrire(String cle, DecoupeVerset d) {
    () async {
      try {
        final f = File('${(await _dossierCache()).path}/$cle.json');
        await f.writeAsString(jsonEncode(d.toJson()));
      } catch (e) {
        DiagnosticLog.log('Decoupe', 'cache non ecrit ($cle) : $e');
      }
    }();
  }
}
