import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Profil de pauses personnel, PAR PASSAGE (idée utilisateur 2026-07-05,
/// prolongement de [[voice-personalization-idea]]) : la récitation validée
/// d'un passage révèle où et combien de temps CET utilisateur s'arrête entre
/// les versets/groupes de mots — sa "manière de réciter" ce passage. Une fois
/// validée (bon score), elle est mémorisée définitivement et sert à
/// personnaliser le seuil de gel des segments (BufferedTranscriber Kotlin) à
/// chaque nouvelle récitation du même passage : un récitant fluide obtient un
/// seuil court (segments figés à ses vraies pauses), un récitant posé un seuil
/// long (pas de gel intempestif en plein verset).
///
/// Motivé par le test réel du 2026-07-05 : avec le seuil universel (700ms puis
/// 450ms par défaut), une récitation fluide ne déclenchait jamais le gel sur
/// pause — seule la borne dure (12s, déjà trop long pour le modèle) agissait,
/// figeant du texte dégradé.
///
/// Stockage : `ApplicationDocumentsDirectory/pause_profiles.json`, un objet
/// `{passageKey: {commitMs, medianPauseMs, nPauses, updatedAt}}`. Donnée
/// on-device uniquement.
class PauseProfileService {
  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');

  // Le seuil retenu = 70% de la pause médiane observée (déclenche sur les
  // pauses typiques sans attendre les plus longues), borné pour rester sain.
  static const _kMedianFactor = 0.7;
  static const _kMinCommitMs = 300;
  static const _kMaxCommitMs = 1500;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pause_profiles.json');
  }

  Future<Map<String, dynamic>> _readAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[PauseProfile] Lecture impossible : $e');
      return {};
    }
  }

  /// Une référence a-t-elle déjà été mémorisée pour ce passage ?
  Future<bool> hasProfileFor(String passageKey) async {
    final all = await _readAll();
    return all.containsKey(passageKey);
  }

  /// Applique le profil mémorisé pour [passageKey] (s'il existe) au moteur
  /// Kotlin — à appeler AVANT de démarrer la récitation. Sans profil, le
  /// moteur garde son seuil par défaut.
  Future<void> applyFor(String passageKey) async {
    final all = await _readAll();
    final profile = all[passageKey] as Map<String, dynamic>?;
    if (profile == null) {
      debugPrint('[PauseProfile] Pas de profil pour "$passageKey" — seuil par défaut');
      return;
    }
    final ms = profile['commitMs'] as int;
    try {
      await _channel.invokeMethod('setCommitSilenceMs', {'ms': ms});
      debugPrint('[PauseProfile] Profil "$passageKey" appliqué : gel à ${ms}ms '
          '(médiane ${profile['medianPauseMs']}ms, n=${profile['nPauses']})');
    } catch (e) {
      debugPrint('[PauseProfile] Échec application : $e');
    }
  }

  /// Récupère les pauses de la session Kotlin en cours. À appeler à la fin de
  /// la récitation, AVANT resetBuffered() (qui efface la liste).
  Future<List<int>> fetchSessionPauses() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getSessionPauses');
      return raw?.cast<int>() ?? const [];
    } catch (e) {
      debugPrint('[PauseProfile] Échec récupération pauses : $e');
      return const [];
    }
  }

  /// Mémorise (définitivement) le profil de [passageKey] à partir des pauses
  /// d'une session VALIDÉE — c'est à l'appelant de vérifier que le score de la
  /// récitation était bon avant d'appeler (même contrat que l'empreinte
  /// vocale : une récitation ratée n'est pas une référence).
  Future<void> saveFor(String passageKey, List<int> pausesMs) async {
    // En dessous de 3 pauses observées, la médiane ne veut rien dire.
    if (pausesMs.length < 3) {
      debugPrint('[PauseProfile] ${pausesMs.length} pause(s) seulement — profil non enregistré');
      return;
    }
    final sorted = [...pausesMs]..sort();
    final median = sorted[sorted.length ~/ 2];
    final commitMs =
        (median * _kMedianFactor).round().clamp(_kMinCommitMs, _kMaxCommitMs);
    final all = await _readAll();
    all[passageKey] = {
      'commitMs': commitMs,
      'medianPauseMs': median,
      'nPauses': pausesMs.length,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(all));
      debugPrint('[PauseProfile] Profil "$passageKey" mémorisé : '
          'gel à ${commitMs}ms (médiane ${median}ms, ${pausesMs.length} pauses)');
    } catch (e) {
      debugPrint('[PauseProfile] Échec sauvegarde : $e');
    }
  }
}
