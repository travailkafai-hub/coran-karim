import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// Où un palier de mémorisation s'arrête, d'après la RÉCITATION de référence.
///
/// ── POURQUOI CET ASSET EXISTE (2026-08-17) ──────────────────────────────────
/// Le palier découpait le verset tous les N mots (réglage « mots par ligne »,
/// 6 par défaut). Constat utilisateur : sur 22:32, le texte s'arrêtait à
/// `شَعَـٰٓئِرَ` pendant que l'audio allait jusqu'à `ٱللَّهِ` -- « je veux la
/// concordance ». Un compte fixe de mots ignore la phrase : il tombe au milieu
/// d'une proposition, et le texte demandé ne correspond plus à ce qu'on
/// entend.
///
/// ── TROIS CRITÈRES ESSAYÉS, DEUX ÉCARTÉS PAR LA MESURE ─────────────────────
///  1. SILENCE du récitateur -- écarté : sur 22:32 l'énergie ne descend jamais
///     sous 0,26 × la moyenne, Al-Afasy récite le verset d'un seul souffle
///     (13,7 s). Découper sur le silence donnait UN palier par verset.
///  2. Marques de WAQF -- écarté : `quran_waqf.json` ne couvre que 2 640
///     versets sur 6 236, et 22:32 n'en porte aucune.
///  3. SOUKOUN écrit -- écarté, mesuré sur les 75 775 frontières du Coran :
///     un soukoun final coïncide avec un waqf licite dans 3,6 % des cas, et
///     88 % des waqf n'ont pas de soukoun. Les deux sont quasi indépendants
///     (le soukoun est morphologique, l'arrêt est syntaxique).
///
/// Retenu : l'ÉNERGIE. Explication du mécanisme donnée par l'utilisateur, et
/// c'est elle qui rend le critère fondé plutôt qu'empirique : quand un
/// récitateur s'arrête, il applique le soukoun à la finale -- il dit `ٱللَّهْ`
/// et non `ٱللَّهِ`. La voyelle casuelle tombe, le son s'éteint. L'énergie
/// basse n'est donc pas un silence, c'est **la trace du waqf dans la voix**.
///
/// Généré par `benchmark/generer_pauses_reciteur.py` : 6 236 versets,
/// 9 241 coupes (1,5 par verset).
///
/// ── CE QUE ÇA N'EST PAS ─────────────────────────────────────────────────────
/// Pas une autorité religieuse sur les arrêts licites. C'est la lecture d'UN
/// récitateur (Al-Afasy), mesurée sur SON enregistrement. Un autre récitateur
/// phraserait autrement -- d'où le nom du fichier, qui le dit.
class CoupesPalierService {
  CoupesPalierService._();
  static final instance = CoupesPalierService._();

  Map<String, List<int>>? _parVerset;
  Future<void>? _chargement;

  /// ⚠️ L'appel CONCURRENT doit attendre, pas repartir (corrigé 2026-08-18).
  /// La forme précédente (`if (_x != null || _chargement) return;`) rendait la
  /// main IMMÉDIATEMENT au second appelant pendant que le premier chargeait
  /// encore -- il lisait alors une donnée vide sans le savoir. Mesuré :
  /// `ABANDON (MP3Quran) verset=80:1 : minutage local absent (segments=null)`
  /// alors que 80:1 EST dans l'asset : `prefetch()` amorçait le chargement,
  /// `_startRound` rappelait 100 ms plus tard et n'attendait rien -- le palier
  /// démarrait donc SANS faire entendre le récitateur.
  /// On mémorise le Future en cours : tout le monde attend le même.
  Future<void> ensureLoaded() {
    if (_parVerset != null) return Future.value();
    return _chargement ??= _charger();
  }

  Future<void> _charger() async {
    try {
      final brut = await rootBundle
          .loadString('assets/data/coupes_palier_afasy.json');
      final data = jsonDecode(brut) as Map<String, dynamic>;
      _parVerset = data.map(
          (k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()));
    } catch (e) {
      // Asset absent : on ne bloque pas le Coach. `coupes()` rendra une liste
      // vide, et l'appelant retombe sur le verset entier -- dégradé mais
      // jamais cassé, même règle que les autres assets optionnels du projet.
      debugPrint('[CoupesPalier] chargement impossible : $e');
      _parVerset = const {};
    } finally {
      _chargement = null;
    }
  }

  /// Index des mots APRÈS lesquels un palier s'arrête, pour ce verset.
  ///
  /// Liste vide = aucune coupe : le verset est plus court que l'unité visée,
  /// il constitue un palier à lui seul. `null` jamais rendu -- l'appelant n'a
  /// pas à distinguer « pas chargé » de « pas de coupe », les deux se
  /// traitent pareil (un seul palier).
  List<int> coupes(int surah, int ayah) =>
      _parVerset?['$surah:$ayah'] ?? const [];
}
