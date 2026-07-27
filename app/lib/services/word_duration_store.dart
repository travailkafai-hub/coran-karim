import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log.dart';

/// Durées d'articulation mesurées dans la VOIX DE L'UTILISATEUR, apprises au
/// fil des récitations, et qui REMPLACENT les durées de référence importées de
/// quran.com dès qu'elles existent pour un mot (demande utilisateur
/// 2026-07-27).
///
/// ── POURQUOI CE MAGASIN EXISTE ─────────────────────────────────────────────
/// Les durées quran.com se sont révélées un cul-de-sac sur les cas durs
/// (mesuré le 2026-07-27, détail dans `FONCTIONNALITES_FUTURES.md` §10) :
///  - leur découpage en mots ne correspond pas toujours au découpage canonique,
///    donc 44 % des versets sont exclus — et la couverture s'effondre avec la
///    longueur du verset (98 % des versets de 1-5 mots, mais **1 %** de ceux de
///    41+ mots), c'est-à-dire exactement là où l'alignement casse. Sur une
///    session réelle, 82 % des incidents étaient dans un verset non couvert ;
///  - leurs segments sont des bornes `[start_ms, end_ms]` qui INCLUENT le
///    silence jusqu'au mot suivant (mesure : le mot « هُمُ » y dure 3030 ms),
///    ce qui avait imposé un facteur de sécurité ×0,4 arbitraire.
///
/// Ici les deux problèmes disparaissent : la durée vient de
/// `ForcedAligner.WordResult.frames`, qui compte les frames ARTICULÉES (frames
/// blank exclues) — il n'y a plus de silence à compenser, donc plus de facteur
/// arbitraire — et la couverture est celle de ce que l'utilisateur récite
/// réellement, sans aucune correspondance de découpage à établir.
///
/// ── CLÉ = LA FORME DU MOT, PAS SA POSITION ─────────────────────────────────
/// La durée d'articulation est une propriété du MOT. Indexer par forme
/// (`RecitedWord.alignTarget`, la forme envoyée au tokenizer) plutôt que par
/// (verset, position) évite toute logique de mappage — donc toute possibilité
/// de décalage silencieux, le risque que la règle positionnelle du projet
/// existe pour écarter — couvre immédiatement les versets absents de l'asset,
/// et mutualise les échantillons entre occurrences (un mot fréquent converge
/// beaucoup plus vite).
///
/// ── ON GARDE LE MINIMUM, PAS LA MÉDIANE ────────────────────────────────────
/// Un plancher est une borne INFÉRIEURE : la bonne statistique est donc le
/// minimum observé, pas une moyenne amputée d'un facteur de sécurité. C'est
/// aussi ce qui rend le regroupement par forme (ci-dessus) sûr malgré les
/// variations de contexte — waqf, madd de fin de verset : le minimum sur
/// PLUSIEURS contextes reste une borne inférieure valide, et il ne peut que
/// descendre avec le temps, donc ne peut pas devenir trop permissif.
///
/// Conséquence assumée : c'est CONSERVATEUR. Un plancher au minimum observé
/// excuse moins qu'un plancher à la durée typique. C'est le sens sûr — le
/// plancher ne sert qu'à excuser un mot dont RIEN n'a été décodé (cf.
/// `ForcedAligner` « DEUX PLANCHERS, DEUX USAGES »), jamais à en condamner un,
/// et sous-estimer revient simplement au comportement d'avant.
///
/// ── ON N'APPREND QUE DES MOTS VALIDÉS ──────────────────────────────────────
/// Une durée n'est retenue que si le mot a été jugé `correct` ET verrouillé :
/// la durée d'un mot mal récité (ou tronqué par une coupe de segment) n'a
/// aucune raison d'être un plancher. Garde-fou soulevé par l'utilisateur
/// lui-même (« en plus on a également la validation »).
class WordDurationStore {
  WordDurationStore._();
  static final instance = WordDurationStore._();

  static const _kFileName = 'word_durations.json';

  /// forme du mot -> minimum de frames articulées observé (80 ms/frame).
  Map<String, int> _minFrames = {};
  bool _loaded = false;
  bool _loading = false;
  File? _file;

  /// Écritures groupées : `record()` est appelé sur chaque mot validé (des
  /// dizaines par session), on ne veut pas un accès disque par mot.
  bool _dirty = false;

  /// Remet le singleton à l'état "jamais chargé" — réservé aux tests, pour
  /// pouvoir vérifier qu'une durée apprise survit bien à un rechargement.
  static void debugReset() {
    instance
      .._minFrames = {}
      .._loaded = false
      .._loading = false
      .._file = null
      .._dirty = false;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_kFileName');
      _file = f;
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _minFrames = {
          for (final e in data.entries)
            if (e.value is int) e.key: e.value as int,
        };
      }
      DiagnosticLog.log('WordDuration',
          'durées apprises chargées : ${_minFrames.length} mots');
    } catch (e) {
      // Fichier absent/corrompu : on repart d'un magasin vide (le plancher
      // quran.com reprend la main). Jamais bloquant.
      debugPrint('[WordDuration] échec chargement : $e');
      _minFrames = {};
    } finally {
      _loaded = true;
      _loading = false;
    }
  }

  /// Plancher appris pour [wordForm], ou null si ce mot n'a jamais été validé.
  int? minFramesFor(String wordForm) => _minFrames[wordForm];

  int get learnedWordCount => _minFrames.length;

  /// Enregistre la durée articulée observée sur un mot VALIDÉ. Ne garde que le
  /// minimum (cf. l'en-tête de classe). Ignore silencieusement les durées
  /// nulles : un mot sans frame n'a pas été prononcé dans cet audio.
  void record(String wordForm, int frames) {
    if (!_loaded || wordForm.isEmpty || frames <= 0) return;
    final previous = _minFrames[wordForm];
    if (previous != null && previous <= frames) return;
    _minFrames[wordForm] = frames;
    _dirty = true;
  }

  /// À appeler en fin de session (pas à chaque mot). Sans effet si rien n'a
  /// changé.
  Future<void> flush() async {
    if (!_dirty) return;
    final f = _file;
    if (f == null) return;
    _dirty = false;
    try {
      await f.writeAsString(jsonEncode(_minFrames));
      DiagnosticLog.log('WordDuration',
          'durées apprises enregistrées : ${_minFrames.length} mots');
    } catch (e) {
      debugPrint('[WordDuration] échec enregistrement : $e');
      _dirty = true; // réessaie à la prochaine fin de session
    }
  }
}
