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
///
/// ── LE CALCUL A DÉMÉNAGÉ HORS DE L'APP (2026-09-06, même jour) ─────────────
///
/// Décision de l'utilisateur : « sinon on analyse le texte nous-mêmes au lieu
/// de laisser cette décision dans l'app ; travaille sur le texte entier ; tu
/// peux déduire les vrais endroits pour s'arrêter, avoir une cohérence
/// structurelle ».
///
/// Il avait raison, et pour une raison que le calcul à l'exécution ne pouvait
/// pas atteindre : ce service ne voyait qu'UN verset à la fois. Hors app, on
/// lit les 6 236 d'un coup, et cela ouvre la seule chose qui donne vraiment de
/// la cohérence — **le Coran se répète**. 7 474 groupes de 2 à 5 mots y
/// reviennent au moins trois fois (`ٱلسموت وٱلأرض` 133 fois, `يأيها ٱلذين
/// ءامنوا` 89, `على كل شىء قدير` 33). Ces groupes sont désormais traités comme
/// des unités qu'on ne coupe jamais — donc coupées de la même façon PARTOUT.
///
/// Résultat mesuré sur tout le Coran : 15 883 paliers, médiane de 5 mots,
/// et 1,04 % seulement au-delà de 10 mots.
///
/// Ce fichier ne calcule donc plus rien : il LIT `coupes_paliers.json`. Le
/// calcul, ses cinq sources et ses chiffres vivent dans
/// `benchmark/build_coupes_paliers.py`. La méthode est conservée ci-dessous
/// en commentaire parce qu'elle documente ce que l'asset contient — mais c'est
/// le script qui fait foi.
///
/// ⚠️ REGÉNÉRER L'ASSET après toute modification du script :
///     python benchmark/build_coupes_paliers.py
class CoupesTexteService {
  CoupesTexteService._();
  static final instance = CoupesTexteService._();

  /// Marques de pause du script coranique.
  static const _waqfTous = {0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB};

  /// `لا` — le seul signe qui dit « ne t'arrête pas ». Il ne crée aucune
  /// coupe : il en SUPPRIME.
  static const _waqfMamnu = 0x06D9;

  /// ── LES MOTS QUI OUVRENT UNE PROPOSITION (2026-09-06) ───────────────────
  ///
  /// Seconde moitié de la demande : couper avant une liaison, même sans
  /// silence. La difficulté était de distinguer les deux emplois de `و` --
  /// sur 6:1, `وَجَعَلَ` (و + verbe) ouvre une proposition tandis que
  /// `وَٱلنُّورَ` (و + nom) prolonge la précédente. Couper avant chaque `و`
  /// donnait des coupes après les mots 4, 5 et 7 au lieu des 5 et 8 attendus.
  ///
  /// LA RÈGLE N'EST PAS GRAMMATICALE, ELLE EST ORTHOGRAPHIQUE : `و`/`ف` suivi
  /// de l'ARTICLE DÉFINI `ال` coordonne un NOM, donc prolonge la phrase. Sans
  /// article, la liaison ouvre. Deux caractères suffisent à trancher, aucune
  /// morphologie n'est nécessaire.
  ///
  ///     وَٱلْأَرْضَ   → و + ال   → coordination      → pas de coupe avant
  ///     وَجَعَلَ      → و + verbe → nouvelle prop.   → coupe avant
  ///     وَٱلنُّورَ    → و + ال   → coordination      → pas de coupe avant
  ///     ثُمَّ         → particule                    → coupe avant
  ///
  /// Vérifié sur 6:1 : la règle rend exactement `[5, 8]`, les arrêts que
  /// l'utilisateur fait à voix haute. Ampleur : 15 080 mots du Coran
  /// commencent par `و` ou `ف`, dont 13 636 (90 %) sans article défini.
  ///
  /// ⚠️ CE N'EST PAS EXACT, C'EST SUFFISANT. Un `و` + nom SANS article
  /// (`وَرَبُّكَ`) sera pris pour une ouverture ; c'est le prix de ne pas
  /// dépendre d'un asset morphologique. La règle de distance ci-dessous
  /// rattrape l'essentiel de ces cas.
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

  /// ── LES CANDIDATS DE SECOURS (2026-09-06) ───────────────────────────────
  ///
  /// Constat de l'utilisateur sur 33:6 : « le deuxième palier est grand, il ne
  /// faut pas abuser -- là on peut s'arrêter avant `مِن` », puis « `كِتَٰبِ
  /// ٱللَّهِ` on s'arrête, ou bien jusqu'à `ٱلْمُهَٰجِرِينَ` ».
  ///
  /// Le verset n'a que deux waqf et aucune liaison entre les mots 7 et 22 :
  /// le palier faisait 19 mots. Ce n'est pas une erreur de l'algorithme --
  /// le texte ne propose rien -- mais 19 mots ne font travailler personne.
  ///
  /// Ces mots-ci ne créent JAMAIS de coupe par eux-mêmes : ce sont des
  /// prépositions et des particules faibles, elles ouvrent un complément, pas
  /// une proposition. Les suivre partout hacherait le texte. Elles ne servent
  /// que de PLAN DE SECOURS, et uniquement là où un palier dépasse
  /// [_paliersMotsMax].
  static const _secours = <String>{
    'من', 'في', 'إلى', 'على', 'عن', 'إلا',
    'لما', 'كما', 'حين', 'بين', 'عند', 'لدى', 'قد', 'لقد',
  };

  /// Au-delà, un palier se refend. DIX mots, fixés par l'utilisateur
  /// (« un palier ne doit pas dépasser 10 mots ») après avoir vu le palier de
  /// 19 mots que 33:6 produisait.
  ///
  /// Mesuré sur tout le Coran avec cette valeur : 17 271 paliers, médiane de
  /// 4 mots, et 19 seulement (0,1 %) dépassent encore -- ceux où le texte
  /// n'offre aucun point de coupe acceptable. Les trois versets de référence
  /// tombent juste : 6:1 en 6/3/5, 13:2 en 6/5/3/4/8, 33:6 en 5/10/9/5.
  static const _paliersMotsMax = 10;

  /// Les coupes PRÉCALCULÉES, par clé de verset.
  Map<String, List<int>>? _asset;
  Map<String, String>? _hafs;
  Map<String, String>? _warsh;
  bool _chargement = false;

  bool get pret => _asset != null;

  Future<void> ensureLoaded() async {
    if (_asset != null || _chargement) return;
    _chargement = true;
    try {
      final brut = jsonDecode(
              await rootBundle.loadString('assets/data/coupes_paliers.json'))
          as Map<String, dynamic>;
      _asset = {
        for (final e in brut.entries)
          e.key: (e.value as List).map((x) => x as int).toList(),
      };
      debugPrint('[CoupesTexte] ${_asset!.length} versets avec coupes');
    } catch (e) {
      // Asset absent : on ne bloque pas le Coach, `coupes()` rendra une liste
      // vide et l'appelant retombe sur ses autres sources. Même discipline que
      // les autres assets optionnels du projet.
      debugPrint('[CoupesTexte] asset illisible : $e');
      _asset = const {};
    }
    // Les textes restent chargés : `refendreLongs` en a besoin pour compter
    // les mots et vérifier que le découpage de l'app coïncide.
    try {
      _hafs = await _lire('assets/data/quran_verses.json');
      _warsh = await _lire('assets/data/quran_verses_warsh.json');
    } catch (e) {
      debugPrint('[CoupesTexte] textes indisponibles : $e');
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

  /// Alefs sous toutes leurs formes -- l'article défini s'écrit `ال`, `أل`,
  /// `ٱل`… selon la vocalisation et la riwaya.
  static const _alefs = 'اأإآٱ';

  /// Le mot [n] (déjà normalisé) ouvre-t-il une proposition ?
  ///
  /// Cf. la doc de [_particules] pour la règle de l'article défini, qui est
  /// tout l'intérêt de cette fonction.
  static bool _ouvreUneProposition(String n) {
    if (_particules.contains(n)) return true;
    if (n.isEmpty) return false;
    final c = n[0];
    if (c != 'و' && c != 'ف') return false;
    final reste = n.substring(1);
    // Une liaison seule (`و` isolé) n'ouvre rien : il faut un mot derrière.
    if (reste.length < 2) return false;
    // و/ف + ARTICLE DÉFINI : coordination d'un nom, la phrase continue.
    if (_alefs.contains(reste[0]) && reste[1] == 'ل') return false;
    return true;
  }

  /// ── DISTANCE MINIMALE ENTRE DEUX COUPES (2026-09-06) ────────────────────
  ///
  /// Règle de l'utilisateur : « on coupe, puis si une autre de cette liste est
  /// à moins de 4 mots, on ne coupe pas ». Elle protège de la fragmentation --
  /// une liaison peut en suivre une autre de très près, et un palier de deux
  /// mots ne fait travailler personne.
  ///
  /// On garde la PREMIÈRE de chaque groupe rapproché, telle que la règle est
  /// formulée : on coupe, PUIS on ignore ce qui suit de trop près.
  ///
  /// ── TROIS, ET C'EST SON PROPRE EXEMPLE QUI LE FIXE (2026-09-06) ─────────
  ///
  /// La règle a été énoncée avec 4. Mesuré sur les deux versets qu'il a
  /// donnés, 4 est trop grand : ses arrêts de 6:1 sont les mots **5 et 8**,
  /// soit exactement 3 mots d'écart -- un seuil de 4 supprimerait le second.
  ///
  ///     seuil | 6:1              | 13:2
  ///       2   | [5, 8]  ✓        | laisse un palier de 2 mots
  ///       3   | [5, 8]  ✓        | paliers de 6, 5, 3, 4, 8 mots
  ///       4   | [5]     ✗        | 6, 5, 7, 8
  ///
  /// ── ET ELLE S'APPLIQUE À TOUTES LES COUPES, PAS QU'AUX LIAISONS ─────────
  ///
  /// Première version : les waqf en étaient exemptés, au motif qu'« un waqf du
  /// texte est une autorité ». 13:2 l'a réfuté -- le Warsh y marque après le
  /// mot 5 et le Hafs après le 6, à UN mot d'écart, ce qui produisait un
  /// palier d'un seul mot (`تَرَوْنَهَا`). Deux autorités qui se suivent de
  /// trop près ne font pas deux arrêts : elles en font un.
  static const _distanceMin = 3;

  /// Index des mots APRÈS lesquels le texte autorise un arrêt.
  ///
  /// [motsAttendus] : le nombre de mots tel que l'app le découpe. Sert de
  /// garde-fou -- une position au-delà est le signe d'un désaccord de
  /// découpage, on la jette plutôt que de couper au mauvais endroit.
  /// ── L'ASSET EST CALCULE SUR LE HAFS (2026-09-06) ────────────────────────
  ///
  /// Signale par l'audit (QUAL-02) : `coupes()` ne recevait pas la riwaya, donc
  /// des index calcules sur le texte Hafs pouvaient servir en Warsh.
  ///
  /// MESURE, avant de decider quoi que ce soit. Les deux textes decoupent le
  /// meme nombre de mots sur 6 230 versets sur 6 236. Sur les six autres,
  /// QUATRE sont dans l'asset, et sur ces quatre, DEUX coupes seulement
  /// tombent sur un mot different :
  ///
  ///     15:7   coupe apres le mot 3 : Hafs `بِٱلْمَلَـٰٓئِكَةِ` / Warsh `إِن`
  ///     41:51  coupe apres le mot 9 : Hafs `ٱلشَّرُّ`         / Warsh `فَذُو`
  ///
  /// Deux coupes fausses sur 4 497 versets. Le constat est donc JUSTE dans son
  /// principe -- rien ne garantissait la correspondance -- et tres petit dans
  /// son ampleur. On le ferme quand meme : deux coupes fausses restent deux
  /// endroits ou le texte affiche ne correspond pas a ce qu'on demande de
  /// reciter, et c'est exactement le defaut qu'on vient de passer la journee a
  /// supprimer.
  ///
  /// COMMENT : l'appelant passe sa riwaya. En Warsh, l'asset n'est utilise que
  /// si les deux textes s'accordent sur le nombre de mots -- sinon on rend une
  /// liste vide et le palier retombe sur ses autres sources. Un asset Warsh
  /// dedie serait plus juste ; il demanderait de refaire l'analyse globale sur
  /// ce texte, ce qui n'est pas justifie par deux coupes.
  ///
  /// [estWarsh] : `false` par defaut, pour que les appelants historiques ne
  /// changent pas de comportement.
  List<int> coupes(int surah, int ayah, int motsAttendus,
      {bool estWarsh = false}) {
    // ── L'ASSET D'ABORD (2026-09-06) ────────────────────────────────────
    //
    // Il porte le résultat de l'analyse GLOBALE -- groupes figés compris, ce
    // que ce service ne peut pas voir depuis un seul verset. Le calcul local
    // ci-dessous n'est plus qu'un repli, pour un asset absent ou un verset
    // qu'il ne couvre pas.
    final precalcule = _asset?['$surah:$ayah'];
    if (precalcule != null) {
      // En Warsh, l'asset (calcule sur le Hafs) n'est applicable que si les
      // deux textes decoupent le meme nombre de mots -- cf. la doc ci-dessus.
      if (estWarsh) {
        final h = _hafs?['$surah:$ayah'];
        final w = _warsh?['$surah:$ayah'];
        if (h == null ||
            w == null ||
            ArabicNormalizer.splitExpectedWords(h).length !=
                ArabicNormalizer.splitExpectedWords(w).length) {
          return const [];
        }
      }
      // Garde-fou identique au calcul local : une position hors bornes est le
      // signe d'un désaccord de découpage, on la jette.
      return precalcule
          .where((i) => i >= 0 && i < motsAttendus - 1)
          .toList();
    }

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

    // Une liaison ouvre une proposition : la coupe se pose AVANT elle, donc
    // après le mot qui la précède.
    for (var i = 1; i < motsHafs.length; i++) {
      if (_ouvreUneProposition(ArabicNormalizer.normalize(motsHafs[i]))) {
        out.add(i - 1);
      }
    }

    // `mamnu` retire, toujours en dernier : quelle que soit la source qui l'a
    // proposée, une position où le tajwid interdit l'arrêt n'en est pas une.
    out.removeAll(interdites);
    // La distance minimale s'applique EN DERNIER, sur l'ensemble : waqf et
    // liaisons confondus (cf. `_distanceMin`).
    final tries = out.where((i) => i >= 0 && i < motsAttendus - 1).toList()
      ..sort();
    final r = <int>[];
    var derniere = -_distanceMin;
    for (final i in tries) {
      if (i - derniere < _distanceMin) continue;
      r.add(i);
      derniere = i;
    }
    return r;
  }

  /// Refend les paliers de plus de [_paliersMotsMax] mots, en coupant au
  /// candidat de secours le plus proche du MILIEU.
  ///
  /// Le milieu plutôt que le premier venu : une refente près d'un bord
  /// laisserait un palier presque aussi long qu'avant, et on recommencerait.
  ///
  /// [coupes] est la liste déjà unie (voix + texte), [motsAttendus] le nombre
  /// total de mots. Rend la liste enrichie, toujours triée.
  ///
  /// Sur 33:6 : le palier 5..23 (19 mots) est coupé après `ٱللَّهِ` (14),
  /// c'est-à-dire avant `مِنَ` -- l'arrêt que l'utilisateur nomme lui-même.
  List<int> refendreLongs(
      List<int> coupes, int surah, int ayah, int motsAttendus) {
    final h = _hafs?['$surah:$ayah'];
    if (h == null) return coupes;
    final mots = ArabicNormalizer.splitExpectedWords(h);
    if (mots.length != motsAttendus) return coupes;

    final out = <int>[...coupes]..sort();
    var debut = 0;
    for (final fin in [...out, motsAttendus - 1]) {
      var d = debut;
      // `while` et non `if` : un palier très long peut demander deux refentes.
      while (fin - d + 1 > _paliersMotsMax) {
        final milieu = (d + fin) ~/ 2;
        int? best;
        for (var i = d + _distanceMin - 1; i <= fin - _distanceMin; i++) {
          if (i + 1 >= mots.length) break;
          if (!_secours.contains(ArabicNormalizer.normalize(mots[i + 1]))) {
            continue;
          }
          if (best == null || (i - milieu).abs() < (best - milieu).abs()) {
            best = i;
          }
        }
        // Aucune préposition dans la plage : plutôt que de laisser un palier
        // hors limite, on coupe au milieu. C'est le dernier recours et il est
        // assumé -- la consigne « pas plus de 10 mots » prime, une coupe
        // neutre au milieu vaut mieux qu'une liste qu'on ne mémorise pas.
        best ??= milieu;
        if (best <= d - 1 || best >= fin) break;
        out.add(best);
        d = best + 1;
      }
      debut = fin + 1;
    }
    return out..sort();
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
