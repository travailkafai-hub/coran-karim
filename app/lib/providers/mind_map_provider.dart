import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mind_map_data.dart';
import 'app_settings_provider.dart';

/// Charge la carte mentale d'une sourate depuis
/// assets/mindmaps/{locale}/{NNN}.json.
///
/// PRÉFIXE DE LANGUE ajouté le 2026-07-20 (contenu EN/AR fourni) : le dossier
/// `fr/` contient désormais les 114 sourates françaises (déplacées depuis la
/// racine `assets/mindmaps/`, où elles vivaient seules jusqu'ici), `en/` et
/// `ar/` leurs pendants. La locale vient de `appLocaleProvider` (Réglages ->
/// Langue de l'application) : ce provider en dépend explicitement via
/// `ref.watch`, donc la carte se recharge automatiquement si l'utilisateur
/// change de langue en cours de route.
///
/// Repli sur `fr` si le fichier de la locale demandée est absent ou
/// illisible (contenu incomplet plutôt qu'écran cassé), puis seulement
/// `null` si même le français échoue -> l'écran affiche son état « bientôt
/// disponible ».
final mindMapProvider =
    FutureProvider.family<MindMapData?, int>((ref, surahNumber) async {
  final locale = ref.watch(appLocaleProvider);
  final number = surahNumber.toString().padLeft(3, '0');

  Future<MindMapData?> load(String lang) async {
    try {
      final raw = await rootBundle.loadString('assets/mindmaps/$lang/$number.json');
      return MindMapData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  return await load(locale) ?? (locale == 'fr' ? null : await load('fr'));
});
