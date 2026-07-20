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
  final n = JudgementOptionsNotifier();
  // Fiabilité mesurée par règle : sert à choisir quelles règles le mode tajwid
  // active d'office (cf. applyPreset). Poussée dès que l'asset est chargé.
  final r0 = ref.read(ruleReliabilityProvider).asData?.value;
  if (r0 != null) n.setReliability(r0);
  ref.listen<AsyncValue<Map<TajwidRule, RuleReliability>>>(
      ruleReliabilityProvider, (_, next) {
    final v = next.asData?.value;
    if (v != null) n.setReliability(v);
  });
  return n;
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
      // MODE TAJWID = le tajwid EST contrôlé (décision utilisateur 2026-07-20 :
      // « en mode adulte, ne pas faire l'idgham ou la qalqala, ça ne fait pas
      // une erreur ; en mode tajwid, oui »). On active donc les règles d'office
      // -- sinon « mode tajwid » avec zéro règle ne vérifierait rien, ce qui
      // était exactement l'état incohérent d'avant.
      //
      // Seules les règles FIABLES sont activées par défaut (statut `ready` et
      // recall >= 0.90) : une règle mal détectée produirait de FAUSSES erreurs
      // (« ghunnah non réalisée » alors qu'elle l'était), le pire retour
      // possible pour apprendre. L'utilisateur reste libre d'ajouter les autres
      // à la main dans l'écran des règles, en connaissance de cause (badge de
      // fiabilité affiché).
      JudgementPreset.tajwid => JudgementOptions.tajwidDefault
          .copyWith(activeRules: _reliableRules),
      // ADULTE / ENFANT : aucune règle -> le tajwid n'est PAS contrôlé. Ne pas
      // réaliser une ghunnah n'est pas une erreur pour eux.
      JudgementPreset.adulte => JudgementOptions.adulteDefault,
      JudgementPreset.enfant => JudgementOptions.enfantDefault,
      JudgementPreset.custom => state.copyWith(preset: JudgementPreset.custom),
    };
    await _persist();
  }

  /// Règles jugées assez fiables pour être contrôlées d'office en mode tajwid.
  /// Alimenté depuis `rule_reliability.json` (asset versionné avec le modèle)
  /// par le provider ci-dessous -- pas codé en dur : quand un nouveau modèle
  /// améliore une règle, le fichier suffit à la faire entrer dans le mode.
  Set<TajwidRule> _reliableRules = const {};

  void setReliability(Map<TajwidRule, RuleReliability> reliability) {
    _reliableRules = {
      for (final e in reliability.entries)
        if (!e.value.capsToUnclear) e.key,
    };
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
