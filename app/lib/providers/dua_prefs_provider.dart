import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Favoris ─────────────────────────────────────────────────────────────────

const _kPrefFavorites = 'duas.favorites';

/// Invocations mises de côté par l'utilisateur.
///
/// POURQUOI PERSISTÉ, contrairement au compteur de répétitions d'une carte
/// (volontairement en mémoire seule, cf. `duas_screen.dart`) : un favori est
/// une intention durable — « celles que je dis tous les jours » — alors qu'un
/// compteur est un état de séance. Les deux n'ont pas la même durée de vie.
class FavoriteDuas extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_kPrefFavorites) ?? const []).toSet();
    } catch (_) {
      // Les favoris sont un confort : jamais un motif d'échec au démarrage.
    }
  }

  Future<void> toggle(String duaId) async {
    final next = Set<String>.from(state);
    if (!next.remove(duaId)) next.add(duaId);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPrefFavorites, next.toList());
    } catch (_) {}
  }

  bool isFavorite(String duaId) => state.contains(duaId);
}

final favoriteDuasProvider =
    NotifierProvider<FavoriteDuas, Set<String>>(FavoriteDuas.new);

// ── Progression dans un rite ────────────────────────────────────────────────

/// État d'avancement d'un rite : l'étape courante, les étapes validées, et
/// l'état des compteurs.
class RiteProgress {
  /// Index de l'étape affichée.
  final int currentStep;

  /// Identifiants d'étapes marquées comme faites.
  final Set<String> doneSteps;

  /// Compteurs : clé `stepId` → nombre d'unités comptées, TOUTES séries
  /// confondues. Pour un compteur à séries (jamarāt : 3 × 7), la valeur va
  /// de 0 à 21 et l'écran en déduit la série courante — un seul entier
  /// suffit et reste cohérent après redémarrage.
  final Map<String, int> counters;

  const RiteProgress({
    this.currentStep = 0,
    this.doneSteps = const {},
    this.counters = const {},
  });

  RiteProgress copyWith({
    int? currentStep,
    Set<String>? doneSteps,
    Map<String, int>? counters,
  }) =>
      RiteProgress(
        currentStep: currentStep ?? this.currentStep,
        doneSteps: doneSteps ?? this.doneSteps,
        counters: counters ?? this.counters,
      );
}

/// POURQUOI LA PROGRESSION EST PERSISTÉE : un Hajj s'étale sur six jours, et
/// l'app sera fermée, le téléphone rechargé, l'écran éteint entre deux
/// étapes. Un état en mémoire seule ferait perdre « où j'en suis » à chaque
/// fois — exactement l'information que le pèlerin vient chercher. Idem pour
/// les compteurs : perdre le décompte au 5ᵉ tour de ṭawāf oblige à
/// recommencer ou à douter, et en cas de doute la règle est de repartir du
/// chiffre le plus bas.
class RiteProgressNotifier extends FamilyNotifier<RiteProgress, String> {
  String get _keyStep => 'rite.$arg.step';
  String get _keyDone => 'rite.$arg.done';
  String get _keyCounters => 'rite.$arg.counters';

  @override
  RiteProgress build(String riteId) {
    _load();
    return const RiteProgress();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final counters = <String, int>{};
      // Sérialisation « stepId=valeur » dans une StringList : évite d'ajouter
      // une dépendance JSON pour trois entiers, et reste lisible en debug.
      for (final entry in prefs.getStringList(_keyCounters) ?? const []) {
        final parts = entry.split('=');
        if (parts.length == 2) {
          final v = int.tryParse(parts[1]);
          if (v != null) counters[parts[0]] = v;
        }
      }
      state = RiteProgress(
        currentStep: prefs.getInt(_keyStep) ?? 0,
        doneSteps: (prefs.getStringList(_keyDone) ?? const []).toSet(),
        counters: counters,
      );
    } catch (_) {}
  }

  Future<void> _persist(RiteProgress p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyStep, p.currentStep);
      await prefs.setStringList(_keyDone, p.doneSteps.toList());
      await prefs.setStringList(
        _keyCounters,
        p.counters.entries.map((e) => '${e.key}=${e.value}').toList(),
      );
    } catch (_) {}
  }

  void goToStep(int index) {
    final next = state.copyWith(currentStep: index);
    state = next;
    _persist(next);
  }

  void toggleDone(String stepId) {
    final done = Set<String>.from(state.doneSteps);
    if (!done.remove(stepId)) done.add(stepId);
    final next = state.copyWith(doneSteps: done);
    state = next;
    _persist(next);
  }

  void increment(String stepId, int max) {
    final current = state.counters[stepId] ?? 0;
    if (current >= max) return;
    final counters = Map<String, int>.from(state.counters)
      ..[stepId] = current + 1;
    final next = state.copyWith(counters: counters);
    state = next;
    _persist(next);
  }

  void resetCounter(String stepId) {
    final counters = Map<String, int>.from(state.counters)..[stepId] = 0;
    final next = state.copyWith(counters: counters);
    state = next;
    _persist(next);
  }

  /// Remet le rite à zéro — une même personne peut enchaîner plusieurs ʿUmra
  /// pendant un séjour.
  void resetAll() {
    const next = RiteProgress();
    state = next;
    _persist(next);
  }
}

final riteProgressProvider =
    NotifierProvider.family<RiteProgressNotifier, RiteProgress, String>(
        RiteProgressNotifier.new);
