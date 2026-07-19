import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'recitation_verifier.dart' show ArabicNormalizer;

/// Résultat d'une localisation réussie : sourate/verset identifiés, avec un
/// score de confiance (proportion de mots de la requête retrouvés dans
/// l'ordre, fenêtre autour du verset candidat).
class QuranMatch {
  final int surahNumber;
  final int ayahNumber;
  final double confidence;
  const QuranMatch({
    required this.surahNumber,
    required this.ayahNumber,
    required this.confidence,
  });
}

class _IndexedVerse {
  final int surah;
  final int ayah;
  final List<String> words;
  const _IndexedVerse(
      {required this.surah, required this.ayah, required this.words});
}

class _ScoredVerse {
  final _IndexedVerse verse;
  final double score;
  const _ScoredVerse(this.verse, this.score);
}

/// "Shazam coranique" (demande utilisateur 2026-07-18) : identifie à quel
/// passage du Coran correspond un extrait audio entendu en ambiance (pas une
/// récitation de l'utilisateur lui-même sur un texte déjà connu — ici le
/// texte est INCONNU au départ, tout l'enjeu est de le retrouver).
///
/// Index construit hors-ligne depuis l'API quran.com (`assets/data/quran_search_index.json`,
/// script `build_search_index.py`) : chaque mot du Coran entier, normalisé
/// EXACTEMENT comme `ArabicNormalizer.normalize()` (squelette sans harakat,
/// même correctif rasm وٰ->ا du 2026-07-10) -- indispensable puisque la
/// requête (sortie ASR) est comparée à ce même format. Chargé en asset
/// (offline, ~1 Mo) plutôt que fetché en ligne : le cas d'usage vise aussi
/// l'écoute pendant une prière/khutba, réseau pas garanti.
class QuranVerseLocatorService {
  QuranVerseLocatorService._();
  static final instance = QuranVerseLocatorService._();

  List<_IndexedVerse>? _verses;
  Map<String, List<int>>? _wordIndex;

  Future<void> _ensureLoaded() async {
    if (_verses != null) return;
    final raw =
        await rootBundle.loadString('assets/data/quran_search_index.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final list = data['verses'] as List;
    final verses = <_IndexedVerse>[
      for (final v in list)
        _IndexedVerse(
          surah: v['s'] as int,
          ayah: v['a'] as int,
          words: (v['w'] as List).cast<String>(),
        ),
    ];
    final idx = <String, List<int>>{};
    for (var i = 0; i < verses.length; i++) {
      for (final w in verses[i].words.toSet()) {
        idx.putIfAbsent(w, () => []).add(i);
      }
    }
    _verses = verses;
    _wordIndex = idx;
  }

  /// Cœur commun de [locate]/[locateTopMatches] : classe TOUS les candidats
  /// par score décroissant (pas seulement le meilleur) -- extrait en méthode
  /// séparée (demande utilisateur 2026-07-19, constat réel : une requête de
  /// 3 mots courts "ما جعل الله" matchait à tort "50:26" avec un score
  /// élevé, faisant échouer toute identification alors que le VRAI verset
  /// (33:4) était probablement aussi parmi les candidats, juste pas en
  /// première position -- [locate] seul n'exposait aucun moyen d'essayer le
  /// suivant).
  Future<List<_ScoredVerse>> _rankCandidates(String heardText) async {
    await _ensureLoaded();
    final queryWords = ArabicNormalizer.normalize(heardText)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    debugPrint('[Shazam] entendu="$heardText" -> mots normalisés=$queryWords');
    // Seuil abaissé de 4 à 2 (demande utilisateur 2026-07-18 : "même avec
    // deux mots c'était suffisant pour moi") -- la protection contre les faux
    // positifs vient du filtre de rareté (mots >400 occurrences ignorés,
    // ci-dessous) et de l'exigence d'ordre dans la fenêtre, pas d'un nombre
    // minimal arbitraire de mots.
    if (queryWords.length < 2) {
      debugPrint('[Shazam] abandon -- moins de 2 mots utilisables');
      return const [];
    }

    final verses = _verses!;
    final wordIndex = _wordIndex!;

    // 1. Mots-candidats : on ignore les mots trop fréquents (plus de 400
    // occurrences dans tout le Coran, ex. "من"/"في"/"الله") -- ils
    // n'aident pas à localiser, juste à faire du bruit dans le score.
    final hits = <int, int>{};
    for (final qw in queryWords.toSet()) {
      final positions = wordIndex[qw];
      if (positions == null || positions.length > 400) continue;
      for (final vi in positions) {
        hits[vi] = (hits[vi] ?? 0) + 1;
      }
    }
    debugPrint('[Shazam] mots-candidats retenus (fréquence <= 400) : '
        '${hits.length} versets touchés');
    if (hits.isEmpty) {
      debugPrint('[Shazam] abandon -- aucun mot de la requête ne matche '
          'un mot du Coran (tous absents ou trop fréquents)');
      return const [];
    }

    final ranked = hits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCandidates = ranked.take(40).map((e) => e.key);

    final scored = <_ScoredVerse>[];
    for (final vi in topCandidates) {
      // Remonte jusqu'à 3 versets en arrière (même sourate) pour couvrir le
      // cas où le mot-candidat trouvé n'est pas le tout premier mot entendu.
      var start = vi;
      var back = 0;
      while (back < 3 && start > 0 && verses[start - 1].surah == verses[vi].surah) {
        start--;
        back++;
      }
      final window = <String>[];
      for (var k = start;
          k < verses.length && window.length < queryWords.length + 15;
          k++) {
        if (verses[k].surah != verses[vi].surah) break;
        window.addAll(verses[k].words);
      }
      if (!_hasBigramSupport(queryWords, window)) {
        // Aucun appui bigramme : mots isolés éventuellement bien placés dans
        // l'ordre, mais jamais réellement côte à côte -- signature d'une
        // coïncidence (cf. commentaire _hasBigramSupport), pas d'un vrai
        // passage récité. Écarté avant même de calculer un score qui
        // pourrait sembler haut à tort.
        continue;
      }
      final score = _orderedOverlap(queryWords, window);
      scored.add(_ScoredVerse(verses[vi], score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Cherche le passage du Coran qui correspond le mieux à [heardText] (texte
  /// libre transcrit par l'ASR, PAS un texte propre -- bruit de
  /// reconnaissance attendu). Retourne `null` si rien d'assez confiant n'est
  /// trouvé (texte trop court, ou aucune zone du Coran ne recoupe assez de
  /// mots dans l'ordre).
  Future<QuranMatch?> locate(String heardText) async {
    final ranked = await _rankCandidates(heardText);
    if (ranked.isEmpty) return null;
    final best = ranked.first;
    debugPrint('[Shazam] meilleur candidat : '
        '${best.verse.surah}:${best.verse.ayah} '
        'score=${best.score.toStringAsFixed(3)} (seuil requis 0.45)');
    // En dessous, trop peu de recoupement pour être sûr -- mieux vaut dire
    // "non trouvé" que rediriger vers le mauvais verset (texte sacré).
    if (best.score < 0.45) {
      debugPrint('[Shazam] abandon -- score sous le seuil');
      return null;
    }
    return QuranMatch(
      surahNumber: best.verse.surah,
      ayahNumber: best.verse.ayah,
      confidence: best.score,
    );
  }

  /// Comme [locate], mais renvoie jusqu'à [k] candidats classés par score
  /// décroissant (au-dessus de [minScore]) au lieu du seul meilleur --
  /// permet à l'appelant d'essayer le candidat suivant si le premier est
  /// rejeté par ses propres garde-fous (ex. plausibilité temporelle, cf.
  /// RecitationNotifier._tryIdentifyTarget) plutôt que d'abandonner tout le
  /// tour de recherche sur un match coïncidentiel.
  Future<List<QuranMatch>> locateTopMatches(
    String heardText, {
    int k = 5,
    double minScore = 0.45,
  }) async {
    final ranked = await _rankCandidates(heardText);
    final result = <QuranMatch>[];
    for (final r in ranked) {
      if (r.score < minScore) break;
      result.add(QuranMatch(
        surahNumber: r.verse.surah,
        ayahNumber: r.verse.ayah,
        confidence: r.score,
      ));
      if (result.length >= k) break;
    }
    if (result.isNotEmpty) {
      debugPrint('[Shazam] ${result.length} candidat(s) au-dessus du seuil '
          '($minScore) : ${result.map((m) => "${m.surahNumber}:${m.ayahNumber}="
              "${m.confidence.toStringAsFixed(2)}").join(", ")}');
    }
    return result;
  }

  /// Proportion de mots de [query] retrouvés dans [window], dans l'ordre
  /// (tolère un léger désordre/bruit ASR : cherche chaque mot de la requête
  /// en avant de la position courante, jamais en arrière).
  ///
  /// BUG corrigé 2026-07-18 (constat réel : requête "مرج البحرين يلتقيان
  /// بينهما برزخ" -> 33 versets candidats trouvés, mais score=0.000 partout).
  /// La fenêtre remonte jusqu'à 3 versets AVANT le mot-candidat (pour couvrir
  /// le cas où ce mot n'est pas le tout premier entendu) -- ce qui pousse le
  /// vrai contenu recherché LOIN dans la fenêtre (souvent >6 positions) si
  /// ces versets précédents sont courts mais nombreux. Chercher seulement
  /// 6 positions en avant du curseur ratait alors le tout premier mot de la
  /// requête, qui ne pouvait donc plus jamais avancer le curseur -- chaque
  /// mot suivant repartait de zéro avec la même fenêtre trop courte. Cherche
  /// maintenant dans TOUTE la fenêtre restante (elle reste petite, ~query+15
  /// mots, donc sans coût réel), toujours en avant seulement.
  double _orderedOverlap(List<String> query, List<String> window) {
    var matched = 0;
    var cursor = 0;
    for (final qw in query) {
      var found = false;
      for (var j = cursor; j < window.length; j++) {
        if (window[j] == qw) {
          matched++;
          cursor = j + 1;
          found = true;
          break;
        }
      }
      if (!found) continue; // mot manqué (bruit ASR) -- on continue sans avancer le curseur
    }
    return matched / query.length;
  }

  /// Version PUBLIQUE de [_orderedOverlap], mots déjà normalisés des DEUX
  /// côtés par l'appelant (2026-07-19, cf. confirmation en deux temps dans
  /// `RecitationNotifier._tryIdentifyTarget`) : compare une petite fenêtre de
  /// mots ENTENDUS à une petite fenêtre de mots ATTENDUS (continuation d'un
  /// candidat déjà trouvé), sans repasser par l'index mot->versets ni par
  /// [_ensureLoaded] -- l'appelant fournit déjà les deux listes de mots.
  double scoreWordWindows(List<String> heardWords, List<String> expectedWords) {
    if (heardWords.isEmpty || expectedWords.isEmpty) return 0.0;
    final heardNorm = heardWords.map(ArabicNormalizer.normalize).toList();
    final expectedNorm = expectedWords.map(ArabicNormalizer.normalize).toList();
    return _orderedOverlap(heardNorm, expectedNorm);
  }

  /// Mots du Coran qui suivent immédiatement (surah, ayah) -- jusqu'à [count]
  /// mots, en poursuivant sur les versets suivants de la MÊME sourate si
  /// besoin (2026-07-19, cf. confirmation en deux temps ci-dessus) : permet
  /// de vérifier qu'une fenêtre de mots entendus JUSTE APRÈS un candidat
  /// provisoire colle bien à la VRAIE continuation du texte, plutôt que de
  /// re-scorer une requête qui grossit sans cesse (dilution du score par le
  /// bruit ASR accumulé -- constat utilisateur réel 2026-07-19). Approximatif
  /// par nature (part du DÉBUT du verset [ayah], pas de l'offset exact du mot
  /// où le candidat a matché à l'intérieur du verset -- ce niveau de détail
  /// n'est pas exposé par [QuranMatch]) ; suffisant ici car la fenêtre de
  /// confirmation reste courte et tolérante (cf. seuil dédié côté appelant).
  Future<List<String>> continuationWords(
      int surah, int ayah, int count) async {
    await _ensureLoaded();
    final verses = _verses!;
    final idx = verses.indexWhere((v) => v.surah == surah && v.ayah == ayah);
    if (idx < 0) return const [];
    final words = <String>[];
    for (var k = idx; k < verses.length && words.length < count; k++) {
      if (k > idx && verses[k].surah != surah) break; // pas au-delà de la sourate
      words.addAll(verses[k].words);
    }
    return words.take(count).toList();
  }

  /// Garde-fou complémentaire à [_orderedOverlap] (2026-07-19, cf. §3.19 du
  /// journal SUIVI_PRIERE.md) : [_orderedOverlap] est volontairement
  /// TOLÉRANT (sous-séquence, les mots n'ont pas besoin d'être collés) --
  /// exactement ce qui a laissé passer "ما جعل الله" (3 mots communs mais
  /// épars) scorer haut sur 50:26 alors que le vrai verset était 33:4. Un
  /// vrai passage réellement récité doit contenir au moins DEUX mots de la
  /// requête D'AFFILÉE quelque part dans le candidat -- une coïncidence de
  /// mots isolés dispersés dans l'ordre ne le garantit presque jamais. Ne
  /// remplace PAS le score (les seuils 0.45/0.70 restent calibrés dessus),
  /// filtre juste les candidats qui n'ont AUCUN appui bigramme.
  bool _hasBigramSupport(List<String> query, List<String> window) {
    for (var i = 0; i < query.length - 1; i++) {
      final a = query[i], b = query[i + 1];
      for (var j = 0; j < window.length - 1; j++) {
        if (window[j] == a && window[j + 1] == b) return true;
      }
    }
    return false;
  }
}
