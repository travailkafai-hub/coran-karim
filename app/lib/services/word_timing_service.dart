import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// Durées de référence mot-à-mot (médiane sur 9 récitateurs murattal,
/// benchmark/collect_word_timings.py), pour donner à l'aligneur natif un
/// plancher RÉALISTE au lieu du seul compte de tokens CTC (cf.
/// ForcedAligner.kt, WordResult.starved — plancher installé le 2026-07-27,
/// exact mais FAIBLE : il dit qu'un mot de 6 tokens tient dans 480 ms, alors
/// qu'en récitation réelle il en prend ~870).
///
/// Couverture PARTIELLE et volontaire : seuls les 3520/6236 versets où le
/// nombre de segments quran.com correspond EXACTEMENT au nombre de mots
/// canoniques sont présents (cf. `collect_word_timings.py`, découverte du
/// 2026-07-27 — le décalage vient du référentiel quran.com lui-même, qui
/// fusionne certains groupes de mots, pas d'un récitateur). Même règle déjà
/// appliquée par [RuleAnnotationService] pour les annotations tajwid : un
/// écart de comptage retombe en silence sur "pas de référence" plutôt que de
/// risquer un mauvais mappage mot-à-mot.
///
/// Aucune estimation de tempo utilisateur ici (cf. [minMsFor]) : le projet a
/// déjà mesuré qu'apprendre le débit depuis ses propres échecs d'alignement
/// fait diverger la mesure (cible dynamique `secPerWord`, retirée le
/// 2026-07-25 — un échec comptait comme un débit lent, ce qui allongeait la
/// cible, ce qui aggravait l'échec). La marge de sécurité fixe ci-dessous
/// évite ce piège en ne dépendant que de la référence externe.
class WordTimingService {
  WordTimingService._();
  static final instance = WordTimingService._();

  Map<String, List<int>>? _byVerse;
  bool _loading = false;

  Future<void> ensureLoaded() async {
    if (_byVerse != null || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle.loadString('assets/data/word_timings_ms.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _byVerse = data.map(
          (k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()));
      debugPrint('[WordTiming] durées de référence chargées : '
          '${_byVerse!.length} versets');
    } catch (e) {
      debugPrint('[WordTiming] échec chargement : $e');
      _byVerse = const {}; // asset absent -> repli silencieux (aucune reference)
    } finally {
      _loading = false;
    }
  }

  /// Durées de référence (ms) des mots du verset [surah]:[ayah], ou null si le
  /// verset n'est pas couvert. L'appelant DOIT vérifier que la longueur
  /// correspond à son propre découpage avant tout usage positionnel : l'asset
  /// est généré contre `text_uthmani.split()`, l'app découpe avec
  /// `ArabicNormalizer.splitExpectedWords` — même précaution que
  /// [RuleAnnotationService.annotatedWords], pour la même raison (un décalage
  /// silencieux attribuerait la durée d'un mot à son voisin).
  List<int>? msForVerse(int surah, int ayah) => _byVerse?['$surah:$ayah'];

  /// MARGE DE SÉCURITÉ (2026-07-27) : un récitateur peut légitimement aller
  /// jusqu'à ~2,5× plus vite que la médiane murattal de référence -- ce
  /// facteur borne donc le plancher par en-dessous plutôt que d'exiger la
  /// durée de référence entière. Volontairement conservateur : le coût d'une
  /// marge trop large est un plancher qui ne sert à rien sur un mot
  /// réellement rapide ; le coût d'une marge trop courte est de recondamner
  /// à tort un mot bien récité mais vite dit -- le second coût est celui que
  /// ce chantier existe pour supprimer, donc on ne le reprend pas.
  static const double _kSafetyFactor = 0.4;
  static const int _kMsPerFrame = 80; // subsampling 8 x stride 10ms

  /// Convertit une durée de référence en plancher de FRAMES (unité déjà
  /// utilisée côté Kotlin), à comparer à la place réellement disponible pour
  /// ce mot.
  static int minFramesFromMs(int ms) =>
      ((ms * _kSafetyFactor) / _kMsPerFrame).floor();
}
