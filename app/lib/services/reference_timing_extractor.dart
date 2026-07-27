import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/recitation_state.dart';
import 'diagnostic_log.dart';
import 'recitation_verifier.dart';
import 'word_duration_store.dart';

/// Un segment figé pendant la session : son clip audio et la plage de mots
/// qu'il couvrait. C'est la correspondance que l'app connaît DÉJÀ en direct et
/// qu'une analyse hors ligne devrait, elle, deviner.
typedef ReferenceSegment = ({String clipPath, int anchor, int wordCount});

/// Déduit les durées réelles par mot À LA FIN d'une session de référence, sur
/// le téléphone, sans PC (exigence utilisateur 2026-07-27 : « la moulinette
/// soit dans le tel »).
///
/// ── LE PROBLÈME QUE ÇA RÈGLE ───────────────────────────────────────────────
/// En direct, la segmentation coupe en plein mot : mesuré le 2026-07-27,
/// 12 des 18 erreurs d'une session (67 %) tombaient sur un bord de segment,
/// dont deux avec `gop=0,00` et `free≈0` -- le modèle était CERTAIN de ce qu'il
/// entendait, il n'avait reçu qu'un fragment. Une durée mesurée sur un mot
/// tronqué ne vaut rien, et le magasin [WordDurationStore] n'apprend que des
/// mots validés : il apprend donc exactement les mots qui n'ont PAS le
/// problème, et jamais ceux qui l'ont.
///
/// ── POURQUOI C'EST POSSIBLE APRÈS COUP ─────────────────────────────────────
/// Les clips sont CONTIGUS ET SANS RECOUVREMENT dans le flux consommé (côté
/// natif, `consomme` part dans le clip, `conserve` reste dans le buffer).
/// Recoller deux clips consécutifs reconstitue donc l'audio du mot coupé au
/// joint. Vérifié le 2026-07-27 : le décodage libre lit correctement le flux
/// concaténé de bout en bout, à travers les jointures.
///
/// Et le retard de validation n'y change rien : c'est un problème de LIVRAISON
/// en temps réel, pas de contenu. L'audio est intact.
///
/// ── POURQUOI SUR LE TÉLÉPHONE C'EST PLUS SIMPLE QUE SUR PC ─────────────────
/// Une analyse hors ligne doit deviner quel mot correspond à quel morceau
/// d'audio (tentative du 2026-07-27 : appariement par décodage libre, fragile,
/// 47 mots retrouvés sur 239). Le téléphone n'a rien à deviner : pendant la
/// session il a ENREGISTRÉ la correspondance -- chaque segment figé connaît son
/// ancre et son nombre de mots. La plage de mots d'une paire de clips est donc
/// connue exactement, sans appariement ni dérive possible.
///
/// Rien de neuf côté modèle : `alignFile` fait déjà une inférence + un
/// alignement forcé one-shot sur un WAV complet (`isFinal=true`, ni streaming
/// ni segmentation), avec le VRAI aligneur de production. Et comme ça tourne
/// après la récitation, le coût n'a aucune importance.
class ReferenceTimingExtractor {
  ReferenceTimingExtractor(this._verifier);
  final RecitationVerifier _verifier;

  static const _kWavHeaderBytes = 44;

  /// Extrait les durées et les enregistre dans [WordDurationStore].
  /// Retourne le nombre de mots mesurés. Ne lève jamais : un échec d'extraction
  /// ne doit pas faire perdre la session (le profil de pauses, lui, est déjà
  /// enregistré à ce stade).
  Future<int> run(
      List<ReferenceSegment> segments, List<RecitedWord> words) async {
    if (segments.length < 2) {
      DiagnosticLog.log('RefTiming',
          'moins de 2 segments (${segments.length}) -- rien a recoller');
      return 0;
    }
    await WordDurationStore.instance.ensureLoaded();
    final sw = Stopwatch()..start();
    // mot -> (marge au bord de la fenetre, frames). On garde la mesure ou le
    // mot est le plus INTERIEUR : un mot au bord d'une paire est au milieu de
    // la paire suivante, c'est tout l'interet du recouvrement.
    final best = <int, (int, int)>{};
    var pairs = 0;

    for (var i = 0; i + 1 < segments.length; i++) {
      final a = segments[i], b = segments[i + 1];
      final path = await _concat(a.clipPath, b.clipPath, i);
      if (path == null) continue;
      try {
        // Cible = la plage REELLEMENT couverte par la paire, connue depuis la
        // session. `alignFile` aligne depuis l'ancre jusqu'a la fin de la
        // cible ; la regle de fin partielle s'arrete d'elle-meme quand l'audio
        // est epuise, exactement comme en production.
        final end = (b.anchor + b.wordCount).clamp(0, words.length);
        if (a.anchor >= end) continue;
        final ok = await _verifier.replaceAlignmentTarget(
            words.sublist(a.anchor, end).map((w) => w.alignTarget).toList(),
            0);
        if (!ok) continue;
        final payload = await _verifier.alignFile(path);
        if (payload == null) continue;
        pairs++;
        // Distance au bord, en mots : l'index dans la fenetre pour le bord
        // gauche, le nombre de mots restants pour le bord droit.
        final n = payload.words.length;
        for (var k = 0; k < n; k++) {
          final w = payload.words[k];
          if (w.frames <= 0) continue;
          final global = a.anchor + w.index;
          if (global < 0 || global >= words.length) continue;
          final marge = k < n - 1 - k ? k : n - 1 - k;
          final prev = best[global];
          if (prev == null || marge > prev.$1) best[global] = (marge, w.frames);
        }
      } finally {
        _deleteQuiet(path);
      }
    }

    var learned = 0;
    for (final e in best.entries) {
      final w = words[e.key];
      // Meme garde-fou que l'apprentissage en direct : la Bismillah n'est pas
      // representative (recitee ~44 % plus vite, cf. RecitedWord.isBasmala).
      if (w.isBasmala) continue;
      WordDurationStore.instance.record(w.alignTarget, e.value.$2);
      learned++;
    }
    await WordDurationStore.instance.flush();
    DiagnosticLog.log('RefTiming',
        'durees extraites : $learned mots depuis $pairs paires de clips '
        '(${segments.length} segments) en ${sw.elapsedMilliseconds}ms');
    return learned;
  }

  /// Concatène deux clips en un WAV temporaire. Les deux sont du PCM 16 kHz
  /// mono écrit par le natif, donc l'en-tête du premier est réutilisable tel
  /// quel une fois sa taille corrigée.
  Future<String?> _concat(String p1, String p2, int idx) async {
    try {
      final f1 = File(p1), f2 = File(p2);
      if (!await f1.exists() || !await f2.exists()) {
        DiagnosticLog.log('RefTiming', 'clip absent : $p1 ou $p2');
        return null;
      }
      final b1 = await f1.readAsBytes(), b2 = await f2.readAsBytes();
      if (b1.length <= _kWavHeaderBytes || b2.length <= _kWavHeaderBytes) {
        return null;
      }
      final d1 = b1.sublist(_kWavHeaderBytes), d2 = b2.sublist(_kWavHeaderBytes);
      final data = Uint8List(d1.length + d2.length)
        ..setAll(0, d1)
        ..setAll(d1.length, d2);
      final head = Uint8List.fromList(b1.sublist(0, _kWavHeaderBytes));
      final bd = ByteData.sublistView(head);
      bd.setUint32(4, 36 + data.length, Endian.little);   // RIFF chunk size
      bd.setUint32(40, data.length, Endian.little);        // data chunk size
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/ref_pair_$idx.wav');
      await out.writeAsBytes(Uint8List.fromList([...head, ...data]), flush: true);
      return out.path;
    } catch (e) {
      DiagnosticLog.log('RefTiming', 'echec concatenation : $e');
      return null;
    }
  }

  void _deleteQuiet(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
