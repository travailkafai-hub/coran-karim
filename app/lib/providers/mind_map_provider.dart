import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mind_map_data.dart';

/// Charge la carte mentale d'une sourate depuis assets/mindmaps/{lang}/{NNN}.json.
/// Langue fixée à "fr" pour l'instant (pas encore de réglage "Langue de
/// l'application", cf. REFONTE_IHM.md §7bis -- le dossier est déjà structuré
/// par langue pour ne pas avoir à redéplacer les fichiers plus tard).
/// Retourne null si le contenu n'est pas encore rédigé pour cette sourate
/// (l'écran affiche alors le stub "Bientôt disponible").
final mindMapProvider =
    FutureProvider.family<MindMapData?, int>((ref, surahNumber) async {
  final path =
      'assets/mindmaps/fr/${surahNumber.toString().padLeft(3, '0')}.json';
  try {
    final raw = await rootBundle.loadString(path);
    return MindMapData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});
