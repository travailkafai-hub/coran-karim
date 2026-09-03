// Choisir le micro qui capte la récitation : téléphone ou casque Bluetooth.
//
// ── CE QUI MARCHAIT DÉJÀ, ET CE QUI NE MARCHAIT PAS ─────────────────────────
//
// Question utilisateur (2026-09-03) : « est-ce que "Lire" et "Réciter"
// fonctionnent avec mes micros d'oreillettes et casque ? ». Vérifié dans le
// code avant d'écrire quoi que ce soit :
//
//   ÉCOUTER, Bluetooth ou filaire   → marchait déjà (route média A2DP)
//   RÉCITER, casque FILAIRE         → marchait déjà (Android route seul)
//   RÉCITER, casque BLUETOOTH       → ne marchait PAS
//
// Le dernier cas ne relevait d'aucun bug : l'application n'avait tout
// simplement aucun code de routage — ni `startBluetoothSco`, ni
// `setCommunicationDevice`, ni `MODE_IN_COMMUNICATION`. Sans cela Android ne
// bascule pas seul et garde le micro du téléphone.
//
// ── POURQUOI C'EST UN RÉGLAGE, ÉTEINT PAR DÉFAUT ────────────────────────────
//
// Le micro d'un casque Bluetooth passe par le profil HFP/SCO, qui compresse la
// voix en bande étroite et fait basculer toute la sortie en mono téléphonie.
// Le modèle ASR de l'app est entraîné sur du 16 kHz propre : la reconnaissance
// s'en trouve dégradée, dans une mesure qui n'a pas encore été chiffrée ici.
//
// Basculer automatiquement dès qu'un casque est connecté aurait donc dégradé
// le jugement de la récitation sans que personne ne le sache — exactement le
// genre de perte silencieuse que ce projet refuse. Le réglage rend le choix
// visible ; la mesure du WER en SCO reste à faire avant d'en recommander
// l'usage.

import 'package:flutter/services.dart';

import 'diagnostic_log.dart';

/// Pont vers `RoutageMicro.kt`.
class RoutageMicro {
  static const _canal = MethodChannel('coran_karim/routage_micro');

  /// Bascule la capture sur le micro d'un casque Bluetooth.
  ///
  /// Rend `false` quand aucun casque avec micro n'est connecté — ce n'est pas
  /// une erreur : on garde alors le micro du téléphone, comportement d'avant.
  /// Une exception non plus n'est fatale : mieux vaut réciter avec le micro du
  /// téléphone que ne pas pouvoir réciter du tout.
  static Future<bool> activer() async {
    try {
      final ok = await _canal.invokeMethod<bool>('activer') ?? false;
      DiagnosticLog.log('Micro',
          ok ? 'capture routée vers le casque Bluetooth'
             : 'aucun micro Bluetooth disponible — micro du téléphone');
      return ok;
    } catch (e) {
      DiagnosticLog.log('Micro', 'routage Bluetooth impossible : $e');
      return false;
    }
  }

  /// Rend le micro du téléphone et restaure le mode audio du système.
  ///
  /// À appeler MÊME si [activer] a rendu `false` : le mode audio a pu être
  /// changé avant l'échec, et le laisser sur `IN_COMMUNICATION` rendrait toute
  /// l'application muette sur le haut-parleur bien après la récitation.
  static Future<void> desactiver() async {
    try {
      await _canal.invokeMethod('desactiver');
    } catch (e) {
      DiagnosticLog.log('Micro', 'restauration du routage : $e');
    }
  }

  /// Les entrées audio que le système voit, pour l'écran de réglage.
  static Future<List<Map<String, dynamic>>> entrees() async {
    try {
      final brut = await _canal.invokeMethod<List<dynamic>>('entrees') ?? [];
      return brut
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (e) {
      DiagnosticLog.log('Micro', 'liste des entrées indisponible : $e');
      return const [];
    }
  }
}
