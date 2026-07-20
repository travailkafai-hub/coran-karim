// Provider du système de vérification unifié -- REFONTE_IHM.md §1.
// Persistance SharedPreferences, même pattern que app_settings_provider.dart.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/judgement_options.dart';

// Clé passée en _v2 le 2026-07-20 : les valeurs par défaut du preset « adulte »
// ont changé (strictHarakat true -> false, cf. judgement_options.dart). Sans ce
// changement de clé, un réglage DÉJÀ ENREGISTRÉ aurait été restauré tel quel et
// aurait masqué la nouvelle valeur -- l'utilisateur aurait testé l'ancien
// comportement en croyant tester le nouveau, et la recette n'aurait rien voulu
// dire. Effet de bord assumé et signalé : la sélection de règles personnalisée
// repart à vide (elles ne faisaient de toute façon que plafonner des verts en
// orange, sans rien vérifier -- cf. audit du même jour).
const _kPrefJudgement = 'judgement_options_v2';

final judgementOptionsProvider =
    StateNotifierProvider<JudgementOptionsNotifier, JudgementOptions>((ref) {
  return JudgementOptionsNotifier();
});

class JudgementOptionsNotifier extends StateNotifier<JudgementOptions> {
  JudgementOptionsNotifier() : super(JudgementOptions.adulteDefault) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefJudgement);
    if (raw != null && mounted) {
      try {
        state = JudgementOptions.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // JSON corrompu (ex. après une migration de version) -> retombe sur
        // le défaut plutôt que de crasher l'app au démarrage.
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefJudgement, jsonEncode(state.toJson()));
  }

  /// Applique un preset complet -- écrase toutes les options actuelles.
  Future<void> applyPreset(JudgementPreset preset) async {
    state = switch (preset) {
      JudgementPreset.tajwid => JudgementOptions.tajwidDefault
          .copyWith(activeRules: state.activeRules),
      JudgementPreset.adulte => JudgementOptions.adulteDefault,
      JudgementPreset.enfant => JudgementOptions.enfantDefault,
      JudgementPreset.custom => state.copyWith(preset: JudgementPreset.custom),
    };
    await _persist();
  }

  /// Modifier une option individuelle bascule automatiquement le preset sur
  /// "custom" (sauf si on est déjà en train de construire un preset) --
  /// REFONTE_IHM.md §1.1 : "même adulte il y aura des options".
  Future<void> setActiveRules(Set<TajwidRule> rules) async {
    state = state.copyWith(activeRules: rules, preset: JudgementPreset.custom);
    await _persist();
  }

  Future<void> toggleRule(TajwidRule rule, bool active) async {
    final next = Set<TajwidRule>.from(state.activeRules);
    if (active) {
      next.add(rule);
    } else {
      next.remove(rule);
    }
    await setActiveRules(next);
  }

  Future<void> setStrictHarakat(bool value) async {
    state = state.copyWith(strictHarakat: value, preset: JudgementPreset.custom);
    await _persist();
  }

  Future<void> setTolerateConfusables(bool value) async {
    state = state.copyWith(
        tolerateConfusables: value, preset: JudgementPreset.custom);
    await _persist();
  }
}

/// Fiabilité par règle -- chargée une fois depuis l'asset embarqué avec le
/// modèle (jamais codée en dur, cf. REFONTE_IHM.md §1.4).
final ruleReliabilityProvider =
    FutureProvider<Map<TajwidRule, RuleReliability>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/rule_reliability.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final rules = json['rules'] as Map<String, dynamic>;
  final result = <TajwidRule, RuleReliability>{};
  for (final entry in rules.entries) {
    final rule = TajwidRule.fromKey(entry.key);
    if (rule == null) continue;
    final data = entry.value as Map<String, dynamic>;
    final status = switch (data['status']) {
      'ready' => RuleStatus.ready,
      'not_ready' => RuleStatus.notReady,
      _ => RuleStatus.insufficientData,
    };
    result[rule] = RuleReliability(
      status: status,
      recall: (data['recall'] as num?)?.toDouble(),
    );
  }
  return result;
});
