import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefBestWordsByPortion = 'memorization_game.best_words_by_portion';
// ── RECORD PAR PORTION, PAS GLOBAL (2026-08-12) ─────────────────────────────
// Remplace l'ancienne clé unique `memorization_game.best_words` (décision
// utilisateur 2026-08-07 : « un seul high-score global »), retournée par la
// demande utilisateur suivante : « je veux que le record soit par sourate/
// Hizb, rattaché au coach avec mes portions ». Pas de migration de l'ancienne
// valeur : un score global ne peut pas être attribué rétroactivement à UNE
// portion précise (à quelle sourate appartenait-il ?) -- l'ancienne clé reste
// simplement non relue, les joueurs repartent à 0 par portion.

/// Record personnel du jeu de mémorisation, PAR PORTION (sourate entière, ou
/// tranche de Hizb/demi-Hizb pour une sourate qui s'étale sur plusieurs Hizb
/// -- même découpe que `PortionService`, cf. `unitKey`). Persisté comme les
/// favoris de duas (`dua_prefs_provider.dart`) : un jeu qui redémarre à zéro à
/// chaque lancement de l'app perdrait justement ce qui rend un record
/// motivant.
class MemorizationGameRecords extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefBestWordsByPortion);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      // Le record est un confort ludique : jamais un motif d'échec au démarrage.
    }
  }

  int bestFor(String unitKey) => state[unitKey] ?? 0;

  /// Signale le score courant d'une portion, pour une partie en cours. Ne
  /// persiste QUE si c'est un nouveau record de CETTE portion -- éviter une
  /// écriture disque à chaque mot tapé. Retourne vrai si ce score vient de
  /// battre le record affiché.
  bool reportScore(String unitKey, int words) {
    final current = state[unitKey] ?? 0;
    if (words <= current) return false;
    state = {...state, unitKey: words};
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kPrefBestWordsByPortion, jsonEncode(state)))
        .catchError((_) => false);
    return true;
  }
}

final memorizationGameRecordsProvider =
    NotifierProvider<MemorizationGameRecords, Map<String, int>>(
        MemorizationGameRecords.new);
