import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefBestWords = 'memorization_game.best_words';

/// Record personnel du jeu de mémorisation : le plus grand nombre de mots
/// enchaînés sans quitter la partie, TOUTES sourates/sessions confondues
/// (décision utilisateur 2026-08-07 -- un seul high-score global, pas un
/// record par sourate, pour rester simple et comparable d'une session à
/// l'autre). Persisté comme les favoris de duas (`dua_prefs_provider.dart`) :
/// un jeu qui redémarre à zéro à chaque lancement de l'app perdrait
/// justement ce qui rend un record motivant.
class MemorizationGameRecord extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getInt(_kPrefBestWords) ?? 0;
    } catch (_) {
      // Le record est un confort ludique : jamais un motif d'échec au démarrage.
    }
  }

  /// Signale le score courant d'une partie en cours. Ne persiste QUE si c'est
  /// un nouveau record -- éviter une écriture disque à chaque mot tapé.
  /// Retourne vrai si ce score vient de battre le record affiché.
  bool reportScore(int words) {
    if (words <= state) return false;
    state = words;
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kPrefBestWords, words))
        .catchError((_) => false);
    return true;
  }
}

final memorizationGameRecordProvider =
    NotifierProvider<MemorizationGameRecord, int>(MemorizationGameRecord.new);
