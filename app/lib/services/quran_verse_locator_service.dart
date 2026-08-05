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
  // Position du premier mot de ce verset dans la séquence aplatie de TOUT le
  // Coran (`_flatWords`) -- permet de retrouver le verset qui contient une
  // position donnée par recherche dichotomique (cf. `_verseAtPos`).
  final int startPos;
  const _IndexedVerse(
      {required this.surah,
      required this.ayah,
      required this.words,
      required this.startPos});
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
  // Séquence aplatie de tous les mots du Coran, dans l'ordre -- support de
  // l'index combinatoire ci-dessous et de `_verseAtPos`.
  List<String>? _flatWords;
  // Index combinatoire (2026-08-02, principe repris de l'algo Shazam --
  // constellation de landmarks + hash de PAIRES, cf. discussion utilisateur) :
  // clé = paire de mots (mot_i, mot_i+k) pour k=1..[_kMaxPairGap], valeur =
  // positions (dans `_flatWords`) où cette paire apparaît. Remplace l'ancien
  // index mot-isolé (`_wordIndex`) -- une paire porte déjà une preuve
  // d'adjacence approchée, ce que le mot isolé ne donnait pas (d'où le veto
  // séparé `_hasBigramSupport`, devenu inutile, cf. plus bas).
  Map<String, List<int>>? _pairIndex;

  // Écart maximal entre les deux mots d'une paire indexée -- assez grand pour
  // survivre à 1-3 mots perdus/mal transcrits par l'ASR entre deux mots
  // effectivement reconnus, assez petit pour que la paire reste une preuve
  // d'adjacence réelle (pas juste "les deux mots existent quelque part").
  //   ⚠️ CE COMMENTAIRE ÉTAIT FAUX JUSQU'AU 2026-08-05, et il l'était depuis
  //   l'écriture de cet index. Tant que l'écart faisait partie de la CLÉ
  //   (`'$a$b$k'`), agrandir `_kMaxPairGap` n'apportait AUCUNE tolérance aux
  //   mots perdus : une paire ne correspondait que si l'écart était identique
  //   des deux côtés, or un mot avalé par l'ASR le raccourcit forcément.
  //   Question de l'utilisateur qui l'a mis au jour : « si je dis A B C D E F G
  //   et que l'algo retrouve A D F G, est-ce qu'il gère que A et D sont séparés
  //   par 1 mot et non par 4 ? » -- non, il ne le gérait pas. Le commentaire
  //   est conservé pour que l'intention d'origine reste lisible ; c'est
  //   `_pairKey` qui a changé, cf. ci-dessous.
  static const _kMaxPairGap = 4;

  // Tolérance du vote de décalage, en nombre de mots (2026-08-05).
  //
  // Le décalage voté est `p - i`, où `i` est l'index dans la REQUÊTE. Chaque
  // mot avalé par l'ASR décale d'une unité tous les `i` suivants : les votes
  // d'avant et d'après le trou tombent alors sur DEUX décalages différents, et
  // le pic se divise au lieu de s'additionner. On additionne donc les votes sur
  // une petite plage de décalages consécutifs pour recoller ces morceaux.
  //
  // 4 : absorbe jusqu'à quatre mots perdus sur l'extrait, sans laisser deux
  // zones éloignées du Coran voter ensemble -- ce serait rendre à l'algorithme
  // le défaut qu'il a été écrit pour supprimer.
  static const _kOffsetWindow = 4;
  // Filtre de rareté (équivalent du seuil >400 occurrences mot-isolé
  // d'origine, mais sur des paires -- donc un seuil bien plus bas) : une
  // paire qui apparaît dans trop d'endroits différents du Coran n'aide pas à
  // localiser, elle ajoute seulement du bruit au vote de décalage ci-dessous.
  static const _kMaxPairOccurrences = 60;

  // L'ÉCART N'EST PLUS DANS LA CLÉ (2026-08-05). Une paire signifie désormais
  // « ces deux mots apparaissent à moins de `_kMaxPairGap` l'un de l'autre »,
  // sans exiger la même distance dans la requête et dans le texte.
  //
  // MESURE qui a motivé le changement (benchmark/shazam_tolerance_trous.py,
  // 200 versets tirés au sort, seuil 0,45 du code) -- part des passages
  // effectivement retrouvés :
  //
  //     ce que fait l'ASR          avant   écart libre   + fenêtre de vote
  //     transcription parfaite      98 %       98 %            98 %
  //     1 mot sur 10 avalé          74 %       84 %            98 %
  //     1 mot sur 5 avalé           50 %       68 %            96 %
  //     1 mot sur 10 mal transcrit  96 %       96 %            96 %
  //     avalé + mal transcrit       60 %       67 %            89 %
  //
  // Les SUBSTITUTIONS ne gênaient déjà presque pas (96 %) : une paire dont un
  // mot est faux ne vote simplement pas. Ce sont les SUPPRESSIONS qui tuaient
  // l'algorithme, et elles sont le mode d'erreur dominant d'un ASR sur de la
  // récitation en ambiance. Aucun scénario ne régresse.
  //
  // Le séparateur reste un caractère de contrôle : il ne peut apparaître dans
  // aucun mot arabe, donc deux paires distinctes ne peuvent pas produire la
  // même clé par concaténation.
  String _pairKey(String a, String b) => '$a$b';

  Future<void> _ensureLoaded() async {
    if (_verses != null) return;
    final raw =
        await rootBundle.loadString('assets/data/quran_search_index.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final list = data['verses'] as List;
    final verses = <_IndexedVerse>[];
    final flat = <String>[];
    for (final v in list) {
      final words = (v['w'] as List).cast<String>();
      verses.add(_IndexedVerse(
        surah: v['s'] as int,
        ayah: v['a'] as int,
        words: words,
        startPos: flat.length,
      ));
      flat.addAll(words);
    }
    final pairIndex = <String, List<int>>{};
    for (var i = 0; i < flat.length; i++) {
      final maxK = (flat.length - 1 - i).clamp(0, _kMaxPairGap);
      for (var k = 1; k <= maxK; k++) {
        final key = _pairKey(flat[i], flat[i + k]);
        pairIndex.putIfAbsent(key, () => []).add(i);
      }
    }
    pairIndex.removeWhere((_, positions) => positions.length > _kMaxPairOccurrences);
    _verses = verses;
    _flatWords = flat;
    _pairIndex = pairIndex;
  }

  /// Verset qui contient la position [pos] de `_flatWords` (recherche
  /// dichotomique sur `startPos`, croissant par construction).
  _IndexedVerse _verseAtPos(int pos) {
    final verses = _verses!;
    var lo = 0, hi = verses.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (verses[mid].startPos <= pos) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return verses[lo];
  }

  /// Cœur commun de [locate]/[locateTopMatches] : classe TOUS les candidats
  /// par score décroissant (pas seulement le meilleur) -- extrait en méthode
  /// séparée (demande utilisateur 2026-07-19, constat réel : une requête de
  /// 3 mots courts "ما جعل الله" matchait à tort "50:26" avec un score
  /// élevé, faisant échouer toute identification alors que le VRAI verset
  /// (33:4) était probablement aussi parmi les candidats, juste pas en
  /// première position -- [locate] seul n'exposait aucun moyen d'essayer le
  /// suivant).
  /// Classe TOUS les candidats par score décroissant -- réécrit le 2026-08-02
  /// autour du principe de l'algo Shazam (Avery Wang, 2003) : hachage
  /// combinatoire de PAIRES + vote de décalage, à la place du comptage de
  /// mots isolés + fraction de recouvrement ordonné (`_orderedOverlap`,
  /// gardée plus bas en commentaire) + veto bigramme séparé
  /// (`_hasBigramSupport`, idem).
  ///
  /// Principe : pour chaque paire `(mot_i, mot_i+k)` de la requête retrouvée
  /// dans l'index à la position `p`, le décalage `p - i` est un VOTE pour "la
  /// requête s'aligne sur le Coran à partir de la position `p - 0`". Un vrai
  /// passage récité fait converger un grand nombre de votes sur EXACTEMENT le
  /// même décalage (les positions sont des index de texte, pas des timestamps
  /// audio -- pas besoin de tolérance, l'égalité stricte suffit et c'est plus
  /// fort que Shazam sur ce point précis). Une coïncidence de mots épars (ex.
  /// "ما جعل الله" trouvé à tort dans 50:26, cf. SUIVI_PRIERE.md §3.19) ne
  /// peut pas produire ce pic : ses quelques paires matchées, quand il y en a,
  /// tombent sur des décalages différents. Ça supprime par construction le
  /// besoin d'un veto bigramme séparé (une paire non trouvée dans l'index ne
  /// vote simplement pas) et le filtre de fréquence se fait sur les PAIRES
  /// (au chargement, `_kMaxPairOccurrences`) plutôt que sur les mots isolés.
  Future<List<_ScoredVerse>> _rankCandidates(String heardText) async {
    await _ensureLoaded();
    final queryWords = ArabicNormalizer.normalize(heardText)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    debugPrint('[Shazam] entendu="$heardText" -> mots normalisés=$queryWords');
    // Seuil abaissé de 4 à 2 (demande utilisateur 2026-07-18 : "même avec
    // deux mots c'était suffisant pour moi") -- la protection contre les faux
    // positifs vient maintenant du vote de décalage lui-même, pas d'un
    // nombre minimal arbitraire de mots.
    if (queryWords.length < 2) {
      debugPrint('[Shazam] abandon -- moins de 2 mots utilisables');
      return const [];
    }

    final pairIndex = _pairIndex!;
    final flatWords = _flatWords!;

    final offsetVotes = <int, int>{};
    var pairsTried = 0;
    for (var i = 0; i < queryWords.length; i++) {
      final maxK = (queryWords.length - 1 - i).clamp(0, _kMaxPairGap);
      for (var k = 1; k <= maxK; k++) {
        pairsTried++;
        final key = _pairKey(queryWords[i], queryWords[i + k]);
        final positions = pairIndex[key];
        if (positions == null) continue;
        for (final p in positions) {
          final offset = p - i;
          offsetVotes[offset] = (offsetVotes[offset] ?? 0) + 1;
        }
      }
    }
    debugPrint('[Shazam] $pairsTried paire(s) testée(s), '
        '${offsetVotes.length} décalage(s) distinct(s) trouvé(s)');
    if (offsetVotes.isEmpty) {
      debugPrint('[Shazam] abandon -- aucune paire de la requête ne matche '
          'une paire du Coran (toutes absentes ou trop fréquentes)');
      return const [];
    }

    // VOTE PAR FENÊTRE (2026-08-05) -- cf. [_kOffsetWindow].
    //
    // On additionne les votes de `d` à `d + _kOffsetWindow` : chaque mot avalé
    // par l'ASR décale d'une unité les votes qui suivent, et sans cette somme
    // le pic se retrouve éparpillé sur autant de décalages qu'il y a de trous.
    final cumul = <int, int>{};
    for (final d in offsetVotes.keys) {
      var somme = 0;
      for (var j = 0; j <= _kOffsetWindow; j++) {
        somme += offsetVotes[d + j] ?? 0;
      }
      cumul[d] = somme;
    }
    final rankedOffsets = cumul.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Un seul candidat par verset (le décalage gagnant de ce verset) -- parmi
    // les meilleurs décalages, pas la peine d'en explorer plus qu'une
    // dizaine, le signal est déjà trié par force de vote décroissante.
    final scored = <_ScoredVerse>[];
    final seenVerse = <String>{};
    for (final e in rankedOffsets.take(10)) {
      // ⚠️ LA FENÊTRE SERT À TROUVER LE PIC, PAS À LE SITUER. Rapporter `e.key`
      // ferait tomber jusqu'à `_kOffsetWindow` mots AVANT le vrai début, donc
      // parfois sur le verset précédent -- mesuré : 98 % -> 92 % sur
      // transcription parfaite, une perte gratuite. On rapporte donc le
      // décalage qui porte le plus de votes À L'INTÉRIEUR de la fenêtre.
      var offset = e.key;
      var meilleur = offsetVotes[offset] ?? 0;
      for (var j = 1; j <= _kOffsetWindow; j++) {
        final v = offsetVotes[e.key + j] ?? 0;
        if (v > meilleur) {
          meilleur = v;
          offset = e.key + j;
        }
      }
      if (offset < 0 || offset >= flatWords.length) continue;
      final verse = _verseAtPos(offset);
      final verseKey = '${verse.surah}:${verse.ayah}';
      if (!seenVerse.add(verseKey)) continue;
      final score = e.value / pairsTried;
      scored.add(_ScoredVerse(verse, score));
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

  // ANCIEN garde-fou (2026-07-19, cf. §3.19 du journal SUIVI_PRIERE.md),
  // devenu inutile depuis le passage au hachage combinatoire de paires +
  // vote de décalage (`_rankCandidates`, 2026-08-02) : une paire qui ne
  // matche aucune entrée de `_pairIndex` ne vote simplement pas, ce qui
  // filtre déjà les mots isolés dispersés sans veto séparé. Gardé en
  // commentaire, pas supprimé (convention projet) :
  //
  // bool _hasBigramSupport(List<String> query, List<String> window) {
  //   for (var i = 0; i < query.length - 1; i++) {
  //     final a = query[i], b = query[i + 1];
  //     for (var j = 0; j < window.length - 1; j++) {
  //       if (window[j] == a && window[j + 1] == b) return true;
  //     }
  //   }
  //   return false;
  // }
}
