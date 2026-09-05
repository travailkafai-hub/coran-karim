import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../models/judgement_options.dart';
import 'recitation_verifier.dart' show ArabicNormalizer;

/// Symboles de règles tajwid (zone privée Unicode U+E000..U+E010) émis par le
/// modèle stage1b-260h. L'ordre est celui de
/// benchmark/data/quran_tajweed_rules/rules_map.json, qui est AUSSI l'ordre de
/// l'enum [TajwidRule] (judgement_options.dart) : U+E000+i correspond à
/// TajwidRule.values[i]. Ne jamais réordonner l'un sans l'autre (vérifié à la
/// main 2026-07-19). La correspondance est reconstruite ici par index plutôt
/// que recopiée en dur, pour qu'un ajout de règle reste cohérent des deux
/// côtés tant que l'ordre est préservé.
///
/// ⚠️ NE PAS CONFONDRE AVEC LES IDS DE LA TÊTE 2 (2026-08-22). Cet index-ci
/// traduit les symboles du TEXTE ANNOTÉ (`rules_map.json`, U+E000+i) et sa
/// correspondance avec l'enum est TOUJOURS VALIDE. Les ids que le MODÈLE émet
/// suivent un autre ordre (`rules.json` du paquet déployé : deux madd au lieu
/// de quatre, plus waqf_lazim/waqf_awla), décalé de 2 à partir de l'index 2 --
/// ceux-là se traduisent par le NOM, cf. FastConformerVerifier. Les deux
/// tables portent des noms proches et ne doivent surtout pas être alignées
/// l'une sur l'autre.
class RuleSymbols {
  RuleSymbols._();

  static const int _base = 0xE000;
  static const int _lastRule = 0xE010; // 17 règles : E000..E010 inclus

  static bool isSymbol(int codeUnit) =>
      codeUnit >= _base && codeUnit <= 0xF8FF;

  /// Règle associée à un caractère de symbole, ou null si hors plage règles.
  static TajwidRule? ruleOf(int codeUnit) {
    if (codeUnit < _base || codeUnit > _lastRule) return null;
    final idx = codeUnit - _base;
    if (idx >= TajwidRule.values.length) return null;
    return TajwidRule.values[idx];
  }

  /// Retire tous les symboles de règles d'une chaîne (pour comparer/afficher
  /// le texte "nu"). La normalisation arabe standard les retire déjà via son
  /// filtre `[^؀-ۿ]`, mais ce helper explicite sert aux endroits qui
  /// manipulent la sortie brute du modèle avant toute normalisation.
  static String strip(String s) {
    if (!s.codeUnits.any(isSymbol)) return s;
    final sb = StringBuffer();
    for (final cu in s.runes) {
      if (!isSymbol(cu)) sb.writeCharCode(cu);
    }
    return sb.toString();
  }

  /// Règles détectées dans une chaîne annotée, dans l'ordre d'apparition
  /// (doublons possibles si la même règle apparaît plusieurs fois).
  static List<TajwidRule> rulesIn(String s) {
    final out = <TajwidRule>[];
    for (final cu in s.runes) {
      final r = ruleOf(cu);
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// Fournit, pour un verset donné, ses mots ANNOTÉS de règles tajwid (forme
/// que le modèle stage1b-260h a apprise : lettres + harakat + symboles PUA).
///
/// POURQUOI par verset et pas par mot : l'application d'une règle dépend du
/// CONTEXTE (lettre suivante, position dans le verset). Mesuré le 2026-07-19 :
/// 39,4 % des occurrences de mots portent une annotation qui varie selon le
/// contexte -- un dictionnaire mot->annotation serait faux 4 fois sur 10. La
/// clé est donc "surah:ayah" et le mapping est positionnel (le nombre de mots
/// annotés == nombre de mots canoniques, garanti à la génération de l'asset,
/// cf. build_app_rules_assets.py).
///
/// Asset : assets/data/quran_rules_annotated.json  {"s:a": ["mot1", ...]}
/// (mots au format Uthmani avec harakat ET symboles ; ~1,8 Mo, chargé une
/// fois puis gardé en mémoire).
class RuleAnnotationService {
  RuleAnnotationService._();
  static final instance = RuleAnnotationService._();

  Map<String, List<String>>? _byVerse;
  Map<String, Set<int>>? _boundaryByVerse;
  bool _loading = false;

  Future<void> ensureLoaded() async {
    if (_byVerse != null || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle
          .loadString('assets/data/quran_rules_annotated.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _byVerse = data.map(
          (k, v) => MapEntry(k, (v as List).cast<String>()));
      debugPrint('[Rules] annotations chargées : ${_byVerse!.length} versets');
    } catch (e) {
      debugPrint('[Rules] échec chargement annotations : $e');
      _byVerse = const {}; // asset absent -> repli silencieux (aligne sur canonique)
    }
    // Mots "frontiere" (2026-07-22, demande utilisateur : afficher la paire
    // de mots pour les regles a cheval sur deux mots -- ikhafa/iqlab/idgham
    // dont le declencheur est la fin d'un mot + le debut du suivant).
    // Genere par build_app_rules_assets.py depuis boundary_words.jsonl.
    try {
      final raw = await rootBundle
          .loadString('assets/data/quran_rules_boundary.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _boundaryByVerse = data.map((k, v) =>
          MapEntry(k, (v as List).map((e) => e as int).toSet()));
    } catch (e) {
      debugPrint('[Rules] échec chargement frontieres : $e');
      _boundaryByVerse = const {};
    } finally {
      _recollerMarquesIsolees();
      _loading = false;
    }
  }

  /// ── LES MARQUES DE WAQF FAISAIENT TOMBER LE TAJWID SUR 42 % DU CORAN ────
  /// (2026-09-05, cause trouvee en analysant une lecture d'An-Nisa sans un
  /// seul violet.)
  ///
  /// CE QUI SE PASSAIT. L'asset annote garde les marques de waqf isolees
  /// (ۖ ۚ ۛ) comme des MOTS a part entiere ; `splitExpectedWords`, cote app,
  /// les elimine (leur normalisation est vide). Les deux decoupages divergent
  /// donc des qu'un verset porte une marque, et
  /// `RecitationNotifier._wordsFromSegments` retombe alors « sur le canonique »
  /// -- un repli volontaire et sain (ne jamais attribuer une regle au mauvais
  /// mot) qui a pour effet d'eteindre TOUT le tajwid du verset, en silence.
  ///
  /// Mesure sur les assets embarques : 2 652 versets sur 6 236 (42,5 %) etaient
  /// dans ce cas, et avec eux 64 % des mots du Coran n'avaient AUCUNE regle
  /// attendue. Al-Baqara (210 versets), An-Nisa (132), Al-An'am (129),
  /// Al-Imran (123) en tete. Sur la session qui a servi au diagnostic, 8 des
  /// 11 versets traverses etaient decales et les 3 alignes n'ont jamais ete
  /// atteints : il n'y avait litteralement rien a juger.
  ///
  /// MEME CLASSE DE BUG que le rub el hizb « ۞ » corrige le 2026-07-11 dans
  /// `tajweedSpansPerWord` -- deux decoupages du meme texte qui ne s'accordent
  /// pas sur ce qui compte comme un mot. Le generateur
  /// (`build_app_rules_assets.py`) ne retire que « ۞ », et il verifie son
  /// comptage contre SON PROPRE `uthmani.jsonl`, jamais contre le texte que
  /// l'app decoupe : sa garantie « meme nombre de mots » est vraie chez lui et
  /// fausse ici. Le corriger a la source demanderait `data/quran_tajweed_rules/`,
  /// absent de cette machine ; ce recollage-ci rend l'asset utilisable tel
  /// qu'il est livre, et resterait juste meme si l'asset etait regenere.
  ///
  /// CE QU'ON FAIT DES REGLES PORTEES PAR LA MARQUE ELLE-MEME. 1 048 symboles
  /// sont annotes SUR un token de waqf isole (405 idgham_ghunnah, 256 ikhafa,
  /// 181 madda_obligatory, 114 slnt...). Les jeter serait une perte seche ;
  /// on les rattache au mot PRECEDENT, arbitrage valide par l'utilisateur.
  /// C'est le bon mot : un idgham ou un ikhafa sur un signe d'arret est la
  /// jonction avec le mot d'avant (celui qui porte le noun ou le tanwin) --
  /// exactement la logique des « mots frontiere » deja portee par
  /// `isBoundaryWord`.
  ///
  /// APRES CE RECOLLAGE : 6 236 / 6 236 versets alignes, chaque mot annote
  /// egal a son canonique une fois les symboles retires (verifie hors app sur
  /// les deux assets), et les mots porteurs d'une regle attendue passent de
  /// 15 974 a 44 331.
  ///
  /// ⚠️ LES INDEX DE FRONTIERE SUIVENT. `quran_rules_boundary.json` indexe les
  /// mots dans le decoupage NON filtre : sans le remappage ci-dessous, chaque
  /// marque retiree decalerait d'un cran toutes les paires suivantes du verset
  /// -- l'app montrerait le mauvais couple de mots.
  void _recollerMarquesIsolees() {
    final src = _byVerse;
    if (src == null || src.isEmpty) return;
    final bornes = _boundaryByVerse ?? const <String, Set<int>>{};
    final recolles = <String, List<String>>{};
    final nouvellesBornes = <String, Set<int>>{};
    var versetsTouches = 0;
    var symbolesRecolles = 0;
    for (final e in src.entries) {
      // COPIE : la liste vient d'un `cast<String>()` sur le JSON decode, et le
      // cas « marque en tete de verset » ecrit dans `mots[i + 1]`. Muter la
      // vue castee est au mieux fragile, au pire une exception a l'execution.
      final mots = List<String>.of(e.value);
      // Rien a faire sur l'immense majorite des versets : on ne reconstruit
      // que ceux qui portent au moins une marque isolee.
      if (!mots.any(_estMarqueIsolee)) {
        recolles[e.key] = mots;
        final b = bornes[e.key];
        if (b != null) nouvellesBornes[e.key] = b;
        continue;
      }
      versetsTouches++;
      final sortie = <String>[];
      // `ancien -> nouveau` pour les mots CONSERVES ; une marque n'a pas
      // d'image, ses symboles partent dans le mot precedent.
      final remap = <int, int>{};
      for (var i = 0; i < mots.length; i++) {
        final m = mots[i];
        if (!_estMarqueIsolee(m)) {
          remap[i] = sortie.length;
          sortie.add(m);
          continue;
        }
        final symboles = RuleSymbols.rulesIn(m);
        if (symboles.isEmpty) continue;
        symbolesRecolles += symboles.length;
        // Les caracteres PUA tels quels, colles au mot precedent :
        // `rulesIn` les lit ou qu'ils soient dans la chaine. A defaut de
        // precedent (marque en tete de verset), au suivant -- il sera ecrit
        // quand on l'atteindra, donc on le met en attente.
        final pua = m.runes.where(RuleSymbols.isSymbol).map(String.fromCharCode).join();
        if (sortie.isNotEmpty) {
          sortie[sortie.length - 1] = sortie.last + pua;
        } else if (i + 1 < mots.length) {
          mots[i + 1] = pua + mots[i + 1];
        }
      }
      recolles[e.key] = sortie;
      final b = bornes[e.key];
      if (b != null) {
        nouvellesBornes[e.key] = {
          for (final i in b)
            if (remap[i] != null) remap[i]!,
        };
      }
    }
    _byVerse = recolles;
    _boundaryByVerse = nouvellesBornes;
    debugPrint('[Rules] marques de waqf recollees : $versetsTouches verset(s) '
        'realigne(s), $symbolesRecolles symbole(s) rattache(s) au mot precedent');
  }

  /// Un token qui n'est PAS un mot pour l'app : une fois ses symboles de regle
  /// retires, sa normalisation arabe est vide (marque de waqf, rub el hizb).
  /// Exactement le critere de `ArabicNormalizer.splitExpectedWords`, applique
  /// APRES `RuleSymbols.strip` -- sans ce retrait prealable, une marque
  /// PORTANT un symbole passerait pour un mot (c'est ce detail qui separe un
  /// realignement a 86 % d'un realignement a 100 %).
  static bool _estMarqueIsolee(String t) =>
      ArabicNormalizer.normalize(RuleSymbols.strip(t)).trim().isEmpty;

  bool get isReady => _byVerse != null;

  /// Mots annotés du verset (surah, ayah), ou null si l'asset n'est pas chargé
  /// ou si le verset est absent (ex. texte hors-Coran) -- l'appelant retombe
  /// alors sur la forme canonique (comportement de l'ancien modèle, sûr).
  List<String>? annotatedWords(int surah, int ayah) =>
      _byVerse?['$surah:$ayah'];

  /// Vrai si le mot [wordIndex] (0-based dans le verset) porte un symbole de
  /// règle dont le déclencheur acoustique est partagé avec le mot SUIVANT
  /// (wordIndex+1) -- ex. iqlab/ikhafa/idgham à cheval sur deux mots. Sert à
  /// décider si l'affichage d'une erreur doit montrer la paire de mots plutôt
  /// qu'un seul mot isolé.
  bool isBoundaryWord(int surah, int ayah, int wordIndex) =>
      _boundaryByVerse?['$surah:$ayah']?.contains(wordIndex) ?? false;
}
