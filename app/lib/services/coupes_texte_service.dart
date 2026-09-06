import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'recitation_verifier.dart' show ArabicNormalizer;

/// ── LES ARRÊTS QUE LE TEXTE CONNAÎT (2026-09-06) ───────────────────────────
///
/// Demande de l'utilisateur, après avoir constaté que le silence seul ne suffit
/// pas : « on peut piloter la découpe par les signes de waqf regroupés depuis
/// les différents textes Hafs et Warsh, et également s'il y a des lettres de
/// liaison — exemple wa, fa, inna — pour bien couper malgré qu'il n'y ait
/// vraiment pas de silence long ».
///
/// LE CAS QUI L'A MOTIVÉ, 6:1. Il s'y arrête après `وَٱلْأَرْضَ` (mot 5),
/// `وَٱلنُّورَ` (8) et `يَعْدِلُونَ` (13). Or :
///   * le silence mesuré chez Al-Afasy ne donne QUE le mot 8 — il ne s'arrête
///     pas après `وَٱلْأَرْضَ` ;
///   * le waqf Hafs donne le mot 8, le waqf Warsh le mot 13.
/// Aucune source seule n'attrape les trois ; leur UNION en attrape deux.
///
/// ── CE QUE CHAQUE TEXTE APPORTE, MESURÉ ────────────────────────────────────
///
/// | source | positions | versets couverts |
/// |--------|-----------|------------------|
/// | Hafs   | 4 359     | 2 637            |
/// | Warsh  | 9 946     | 5 173            |
/// | union  | —         | **5 202**        |
///
/// Le Warsh DOUBLE la couverture. Sa contrepartie est connue et documentée
/// ailleurs dans le projet : sa typologie est écrasée — 9 946 marques, toutes
/// du même type — donc on n'y distingue pas un waqf recommandé d'un waqf
/// INTERDIT.
///
/// ⚠️ LE RISQUE EST CHIFFRÉ, ET IL EST PETIT : 14 positions seulement où le
/// Warsh marque là où le Hafs dit `mamnu` (لا). Quatorze — exactement le nombre
/// de coupes déjà retirées pour cette raison dans `coupes_palier_afasy.json`.
/// Le filtre est donc reconduit ici : une position `mamnu` en Hafs ne peut
/// jamais devenir une coupe, quelle que soit la source qui la propose.
///
/// ⚠️ LES INDEX DE MOTS COÏNCIDENT À 99,9 % (6 230 versets sur 6 236). Les six
/// exceptions — 15:7, 37:17, 40:26, 41:51, 57:24 et une autre — ont un nombre
/// de mots DIFFÉRENT entre les deux textes : y superposer des index décalerait
/// les coupes. Sur ces versets-là, le Warsh est ignoré et seul le Hafs compte.
class CoupesTexteService {
  CoupesTexteService._();
  static final instance = CoupesTexteService._();

  /// Marques de pause du script coranique.
  static const _waqfTous = {0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB};

  /// `لا` — le seul signe qui dit « ne t'arrête pas ». Il ne crée aucune
  /// coupe : il en SUPPRIME.
  static const _waqfMamnu = 0x06D9;

  /// ── LES PARTICULES QUI OUVRENT TOUJOURS UNE PROPOSITION ─────────────────
  ///
  /// Seconde moitié de la demande : couper avant une liaison, même sans
  /// silence. La règle générale exigerait de savoir si le mot est un verbe --
  /// sur 6:1, `وَجَعَلَ` (و + VERBE) ouvre une proposition tandis que
  /// `وَٱلنُّورَ` (و + NOM) prolonge la précédente. Couper avant chaque `و`
  /// donnerait des coupes après les mots 4, 5 et 7 au lieu des 5 et 8
  /// attendus : la sur-découpe est pire que l'absence de découpe.
  ///
  /// On s'en tient donc à une LISTE FERMÉE de mots qui ouvrent une proposition
  /// quoi qu'il suive, et le `و` seul n'en fait volontairement pas partie.
  /// C'est le sous-ensemble sûr de la règle, en attendant une source
  /// morphologique qui permettrait de la rendre exacte.
  ///
  /// Comparés sur la forme NORMALISÉE (sans harakat) : le même mot s'écrit
  /// avec des diacritiques différentes selon le contexte et la riwaya.
  static final _particules = <String>{
    for (final m in [
      'ثم',      // puis
      'فإن', 'فإذا', 'فأما', 'فلما',   // fa + subordonnant
      'إن', 'إنا', 'إنما', 'إنه',      // inna
      'أما', 'بل', 'لكن', 'حتى', 'إذا', 'لعل', 'كأن',
      'ألا', 'أفلا', 'أولئك',
    ])
      m,
  };

  Map<String, String>? _hafs;
  Map<String, String>? _warsh;
  bool _chargement = false;

  bool get pret => _hafs != null;

  Future<void> ensureLoaded() async {
    if (_hafs != null || _chargement) return;
    _chargement = true;
    try {
      _hafs = await _lire('assets/data/quran_verses.json');
      _warsh = await _lire('assets/data/quran_verses_warsh.json');
      debugPrint('[CoupesTexte] ${_hafs!.length} versets Hafs, '
          '${_warsh!.length} Warsh');
    } catch (e) {
      debugPrint('[CoupesTexte] chargement impossible : $e');
      _hafs = const {};
      _warsh = const {};
    } finally {
      _chargement = false;
    }
  }

  Future<Map<String, String>> _lire(String chemin) async {
    final brut = jsonDecode(await rootBundle.loadString(chemin)) as List;
    return {
      for (final v in brut)
        (v as Map)['verse_key'] as String: v['text_uthmani'] as String,
    };
  }

  /// Index des mots APRÈS lesquels le texte autorise un arrêt.
  ///
  /// [motsAttendus] : le nombre de mots tel que l'app le découpe. Sert de
  /// garde-fou -- une position au-delà est le signe d'un désaccord de
  /// découpage, on la jette plutôt que de couper au mauvais endroit.
  List<int> coupes(int surah, int ayah, int motsAttendus) {
    final h = _hafs?['$surah:$ayah'];
    if (h == null) return const [];
    final motsHafs = ArabicNormalizer.splitExpectedWords(h);
    if (motsHafs.length != motsAttendus) return const [];

    final interdites = _positions(h, {_waqfMamnu}).toSet();
    final out = <int>{..._positions(h, _waqfTous)};

    // Le Warsh n'est superposé que si les deux textes découpent pareil.
    final w = _warsh?['$surah:$ayah'];
    if (w != null &&
        ArabicNormalizer.splitExpectedWords(w).length == motsAttendus) {
      out.addAll(_positions(w, _waqfTous));
    }

    // Une particule ouvre une proposition : la coupe se pose AVANT elle, donc
    // après le mot qui la précède.
    for (var i = 1; i < motsHafs.length; i++) {
      if (_particules.contains(ArabicNormalizer.normalize(motsHafs[i]))) {
        out.add(i - 1);
      }
    }

    // `mamnu` retire, toujours en dernier : quelle que soit la source qui l'a
    // proposée, une position où le tajwid interdit l'arrêt n'en est pas une.
    out.removeAll(interdites);
    final r = out.where((i) => i >= 0 && i < motsAttendus - 1).toList()..sort();
    return r;
  }

  /// Index du mot après lequel tombe chaque marque de [codes].
  ///
  /// Une marque peut être COLLÉE à un mot ou former un token isolé (`ۖ` seul
  /// entre deux mots) -- les deux cas se rencontrent dans les assets, et un
  /// token isolé appartient au mot qui le PRÉCÈDE.
  List<int> _positions(String texte, Set<int> codes) {
    final out = <int>[];
    var idx = -1;
    for (final mot in texte.split(RegExp(r'\s+'))) {
      if (mot.isEmpty) continue;
      final estMot = ArabicNormalizer.normalize(mot).isNotEmpty;
      if (estMot) idx++;
      for (final c in mot.runes) {
        if (codes.contains(c) && idx >= 0) out.add(idx);
      }
    }
    return out;
  }
}
