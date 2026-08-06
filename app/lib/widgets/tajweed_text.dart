import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';

/// Maps quran.com tajweed class names to display colors.
///
/// CORRECTION 2026-07-06 : les noms de classe ci-dessous ont été RE-VÉRIFIÉS
/// par appel réel à l'API (`GET /verses/by_chapter/1?fields=text_uthmani_tajweed`)
/// après que l'utilisateur a signalé "toujours pas de couleur" malgré le
/// déploiement précédent. Deux bugs distincts sont corrigés ici :
/// 1) la vraie balise est `<tajweed class=X>` (voir _parseNode), pas `<span>` ;
/// 2) plusieurs orthographes de classe étaient fausses par rapport aux
/// VRAIES données de l'API (ex. `ikhfa` -> en réalité `ikhafa`, `laam_shamsiyya`
/// -> en réalité `laam_shamsiyah`, `idgham_w_ghunnah` -> en réalité
/// `idgham_ghunnah`) — elles ne matchaient donc jamais rien.
///
/// Sources par groupe de règles :
/// - Madd (4 nuances), ham_wasl/laam_shamsiyah/slnt/idgham_wo_ghunnah (gris),
///   ghunnah/ikhafa/ikhafa_shafawi (vert) : couleurs extraites PIXEL PAR PIXEL
///   d'une capture d'écran de l'app de référence "Règles de Tajweed" fournie
///   par l'utilisateur le 2026-07-05 — non inventées.
/// - idgham_ghunnah/idgham_shafawi/iqlab (vert) : PAS visibles sur la capture
///   de l'utilisateur, mais ce sont tous des règles à ghunna (nasalisation) —
///   même famille que ghunnah/ikhafa déjà vérifiés en vert. Corroboré par le
///   dépôt officiel de l'organisation GitHub "quran" (github.com/quran/tajweed,
///   `ResultType.java` : GHUNNA/IDGHAM_WITH_GHUNNA/IQLAB partagent la même
///   couleur "43A047"). Extension raisonnée d'une donnée déjà vérifiée, pas
///   une invention libre — à remplacer si l'utilisateur retrouve ces 3 règles
///   précises sur sa propre capture.
/// - qalaqah (bleu) : qalqalah n'est PAS une règle de ghunna (c'est un "rebond"
///   de lettre sukoon), donc pas rattachable au groupe vert ci-dessus. Couleur
///   reprise du même dépôt officiel github.com/quran/tajweed (`QALQALAH`,
///   "0091EA") faute de capture utilisateur pour cette règle précise.
// AJUSTEMENT 2026-07-06 (retour utilisateur après capture d'écran réelle sur
// le téléphone) : les teintes pixel-vérifiées ci-dessus rendaient trop pâles/
// délavées une fois affichées sur du texte fin par-dessus le fond crème de
// l'app (le petit carré-témoin de la capture de référence était, lui, en
// aplat plein). Même famille de teinte et même regroupement de règles que
// la note de provenance ci-dessus (rien n'est reclassé), simplement plus
// saturé/contrasté pour rester lisible sur de vrais versets.
const _classColors = <String, Color?>{
  // Madd (prolongation) — 4 nuances distinctes selon la durée.
  'madda_necessary':    Color(0xFFA13420), // 6 temps, obligatoire
  'madda_obligatory':   Color(0xFFE8391F), // 4 ou 5 temps, obligatoire
  'madda_permissible':  Color(0xFFEB7A1E), // 2, 4 ou 6 temps, permis
  'madda_normal':       Color(0xFFEB7A1E), // meme famille que permissible
  // Ghunna (nasalisation) + Ikhfa (dissimulation) — regroupés sous la même
  // teinte dans l'app de référence ("إخفاء، ومواقع الغُنَّة").
  'ghunnah':            Color(0xFF2E9E4F),
  'ikhafa':             Color(0xFF2E9E4F),
  'ikhafa_shafawi':     Color(0xFF2E9E4F),
  // Idgham/iqlab À GHUNNA — même famille verte (voir note de provenance ci-dessus).
  'idgham_ghunnah':     Color(0xFF2E9E4F),
  'idgham_shafawi':     Color(0xFF2E9E4F),
  'iqlab':              Color(0xFF2E9E4F),
  // Idgham SANS ghunna + lettres muettes — gris, regroupé dans l'app de
  // référence ("ادغام، ومالا يُلفَظ" = idgham et ce qui ne se prononce pas).
  'idgham_wo_ghunnah':  Color(0xFF77766C),
  'idgham_mutajanisayn':Color(0xFF77766C),
  'idgham_mutaqaribayn':Color(0xFF77766C),
  'laam_shamsiyah':     Color(0xFF77766C),
  'ham_wasl':           Color(0xFF77766C),
  'slnt':               Color(0xFF77766C),
  // Qalqalah — pas une règle de ghunna, couleur distincte (voir provenance ci-dessus).
  'qalaqah':            Color(0xFF0091EA),
};

// L'API ajoute à la fin de CHAQUE verset un marqueur ornemental
// `<span class=end>١</span>` (le chiffre de l'aya, en chiffres arabo-indiens)
// qui fait partie du texte Uthmani traditionnel. L'app dessine déjà son
// propre badge circulaire numéroté (_VerseNumberBadge dans verse_tile.dart)
// -> sans ce retrait, le numéro s'affichait EN DOUBLE (constaté par
// l'utilisateur le 2026-07-06). Ce marqueur cassait aussi silencieusement
// l'alignement mot-par-mot en karaoké/coach sur les passages multi-versets :
// `tajweedSpansPerWord` y voyait un mot supplémentaire par verset (le
// chiffre), décalant d'autant tous les index de `_tajwidSpans` par rapport à
// `RecitedWord` (qui, lui, vient de `text_uthmani` SANS ce marqueur) dès le
// 2e verset d'un passage.
final _endMarkerRe = RegExp(r'\s*<span class=end>.*?</span>');

/// Parses quran.com tajweed HTML into a list of colored TextSpans.
/// Handles nested spans (2 levels).
List<TextSpan> parseTajweedHtml(String html, TextStyle base) {
  return _parseNode(html.replaceAll(_endMarkerRe, ''), null, base);
}

/// Regroupe les spans tajwid PAR MOT (un groupe de TextSpans par mot,
/// préservant la coloration lettre par lettre À L'INTÉRIEUR du mot — un même
/// mot peut porter deux couleurs différentes, ex. un ikhfa en bleu sur une
/// lettre et un madd en or sur une autre, le reste du mot restant noir).
/// Convention vérifiée sur l'app de référence Quran.com (capture 2026-07-05) :
/// la coloration est fine/éparse par lettre, PAS un mot entier d'une seule
/// couleur — d'où cette fonction plutôt qu'un simple mapping mot→couleur.
List<List<TextSpan>> _tajweedSpansPerWordRaw(String html, TextStyle base) {
  final spans = parseTajweedHtml(html, base);
  final words = <List<TextSpan>>[];
  var current = <TextSpan>[];
  for (final span in spans) {
    final text = span.text ?? '';
    final parts = text.split(' ');
    for (var p = 0; p < parts.length; p++) {
      if (parts[p].isNotEmpty) {
        current.add(TextSpan(text: parts[p], style: span.style ?? base));
      }
      if (p < parts.length - 1) {
        if (current.isNotEmpty) {
          words.add(current);
          current = [];
        }
      }
    }
  }
  if (current.isNotEmpty) words.add(current);
  return words;
}

/// Reconstruit UN mot en gardant le texte de [plainWord] CARACTÈRE PAR
/// CARACTÈRE, en reportant uniquement la couleur depuis [tajweedWordSpans] --
/// jamais son propre texte. Alignement direct si les deux ont la même
/// longueur (l'immense majorité des cas : les écarts mesurés sont des
/// substitutions 1 caractère pour 1, jamais des insertions/suppressions,
/// cf. commentaire de [tajweedSpansPerWord]) ; sinon, report proportionnel
/// de la couleur -- approximatif mais jamais faux sur le TEXTE lui-même.
List<TextSpan> _remapWordColors(
    String plainWord, List<TextSpan> tajweedWordSpans, TextStyle base) {
  final colorsByIndex = <Color?>[];
  for (final span in tajweedWordSpans) {
    final len = span.text?.length ?? 0;
    final c = span.style?.color;
    for (var k = 0; k < len; k++) {
      colorsByIndex.add(c);
    }
  }
  if (colorsByIndex.isEmpty) {
    return [TextSpan(text: plainWord, style: base)];
  }
  final sameLength = colorsByIndex.length == plainWord.length;
  return [
    for (var i = 0; i < plainWord.length; i++)
      TextSpan(
        text: plainWord[i],
        style: () {
          final srcIdx = sameLength
              ? i
              : (i * colorsByIndex.length / plainWord.length).floor();
          final color = srcIdx < colorsByIndex.length ? colorsByIndex[srcIdx] : null;
          return color != null ? base.copyWith(color: color) : base;
        }(),
      ),
  ];
}

/// Coloration tajwid mot par mot, À PARTIR DU TEXTE CANONIQUE [plainText]
/// (`text_uthmani`) — [tajweedHtml] (`text_uthmani_tajweed`) ne sert QUE de
/// source de couleur, jamais de source de caractères à afficher.
///
/// Correctif du 2026-07-10 (audit du Coran entier, 6236 versets comparés) :
/// `text_uthmani_tajweed` ne contient pas toujours EXACTEMENT les mêmes
/// caractères que `text_uthmani` une fois les balises retirées -- 4278/6236
/// versets diffèrent, le plus souvent par une substitution de caractère
/// isolée (le dagger alif "ٰ" U+0670 est remplacé par "ٲ" *alif à hamza
/// ondulée* U+0672 dans 1161 cas, y compris sur des mots ordinaires comme
/// "ذلك"/"الصراط", pas seulement les mots à rasm particulier type
/// "الصلاة"/"الزكاة"). Rendu tel quel, ce dernier caractère s'affichait very
/// différemment de l'écriture attendue (constat utilisateur direct sur
/// "صَلَوٰتَكَ" à l'écran). On respecte donc désormais le texte canonique À LA
/// LETTRE et on se contente d'y superposer la couleur.
List<List<TextSpan>> tajweedSpansPerWord(
    String plainText, String? tajweedHtml, TextStyle base) {
  // MÊME filtre que ArabicNormalizer.splitExpectedWords (source de la liste
  // récitable RecitedWord, indexée en parallèle de celle-ci par _wordSpan) —
  // bug corrigé 2026-07-11 : ce filtre ne retirait avant que les mots
  // totalement vides, pas les marques décoratives isolées (ex. "۞" rub el
  // hizb, présent comme token à part entière séparé par un espace dans
  // text_uthmani du verset 100:9). Une telle marque restait ici comme "mot"
  // à part entière alors que splitExpectedWords l'exclut déjà (normalize("۞")
  // est vide) -- décalait de 1 TOUS les index de coloration tajwid par
  // rapport à RecitedWord à partir de ce verset, pour le reste du passage
  // (la marque elle-même s'affichait comme "mot", et chaque mot réel suivant
  // affichait le texte/la couleur du mot précédent). Même classe de bug que
  // le marqueur de fin de verset `<span class=end>` (cf. `_endMarkerRe`
  // ci-dessus) et la marque de waqf de la sourate 110 (cf. commentaire de
  // `ArabicNormalizer.splitExpectedWords`) -- laquelle "۞" avait échappé.
  final plainWords = plainText
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && ArabicNormalizer.normalize(w).isNotEmpty)
      .toList();
  if (tajweedHtml == null || tajweedHtml.isEmpty) {
    return [
      for (final w in plainWords) [TextSpan(text: w, style: base)],
    ];
  }
  final tajweedWords = _tajweedSpansPerWordRaw(tajweedHtml, base);
  return [
    for (var i = 0; i < plainWords.length; i++)
      i < tajweedWords.length
          ? _remapWordColors(plainWords[i], tajweedWords[i], base)
          : [TextSpan(text: plainWords[i], style: base)],
  ];
}

// La vraie balise de coloration renvoyée par l'API n'est PAS <span> mais
// <tajweed class=X> (attribut SANS guillemets) ; le marqueur de fin de
// verset utilise, lui, <span class=end> (guillemets absents aussi). Vérifié
// par appel réel à l'API le 2026-07-06 (voir commentaire de _classColors) —
// d'où un nom de balise générique plutôt qu'un "span" en dur.
final _tagNameRe = RegExp(r'^([a-zA-Z][a-zA-Z0-9]*)');
final _classAttrRe = RegExp(r'class=(?:"([^"]*)"|([^\s">]+))');

List<TextSpan> _parseNode(String html, Color? parentColor, TextStyle base) {
  final spans = <TextSpan>[];
  int i = 0;

  while (i < html.length) {
    if (i < html.length && html[i] == '<') {
      // Find tag end
      final gt = html.indexOf('>', i);
      if (gt == -1) break;
      final tag = html.substring(i + 1, gt);

      if (tag.startsWith('/')) {
        // Balise fermante isolée (ne devrait pas arriver au niveau racine,
        // mais on ignore plutôt que de planter sur du HTML inattendu).
        i = gt + 1;
        continue;
      }

      final tagName = _tagNameRe.firstMatch(tag)?.group(1);
      if (tagName == null) {
        i = gt + 1;
        continue;
      }

      final cm = _classAttrRe.firstMatch(tag);
      final cls = cm?.group(1) ?? cm?.group(2) ?? '';
      final color = _classColors.containsKey(cls)
          ? _classColors[cls]
          : (cls.contains(' ')
              ? _classColors[cls.split(' ').first]
              : parentColor);

      // Find matching closing tag for THIS tag name (peut être <tajweed> ou <span>).
      final close = _findClose(html, gt + 1, tagName);
      final inner = html.substring(gt + 1, close.contentEnd);
      final innerSpans = _parseNode(inner, color ?? parentColor, base);
      spans.addAll(innerSpans.map((s) => TextSpan(
        text: s.text,
        children: s.children,
        style: (color != null)
            ? base.copyWith(color: color)
            : s.style ?? base,
        recognizer: s.recognizer,
      )));
      i = close.afterCloseTag;
    } else {
      // Plain text
      final next = html.indexOf('<', i);
      final end = next == -1 ? html.length : next;
      final text = html.substring(i, end);
      if (text.isNotEmpty) {
        spans.add(TextSpan(
          text: text,
          style: parentColor != null ? base.copyWith(color: parentColor) : base,
        ));
      }
      i = end;
    }
  }
  return spans;
}

({int contentEnd, int afterCloseTag}) _findClose(
    String html, int from, String tagName) {
  final openPrefix = '<$tagName';
  final closeTag = '</$tagName>';
  var depth = 1;
  var i = from;
  while (i < html.length && depth > 0) {
    if (html.startsWith(openPrefix, i)) {
      depth++;
      i += openPrefix.length;
      continue;
    }
    if (html.startsWith(closeTag, i)) {
      depth--;
      if (depth == 0) {
        return (contentEnd: i, afterCloseTag: i + closeTag.length);
      }
      i += closeTag.length;
      continue;
    }
    i++;
  }
  return (contentEnd: i, afterCloseTag: i);
}

/// A verse displayed word-by-word with tajweed coloring.
/// Tapping any word calls [onWordTap] with the word index.
class TajweedText extends StatelessWidget {
  final String textUthmani;
  final String? textUthmaniTajweed;
  final double fontSize;
  final double lineHeight;
  final void Function(int wordIndex)? onWordTap;
  // Badge de numéro de verset (2026-08-01) : EMBARQUÉ dans le flux du texte
  // via WidgetSpan plutôt que placé à côté dans un Row -- un Row réserve sa
  // colonne sur TOUTES les lignes du paragraphe, pas seulement la 1ère
  // (signalé par l'utilisateur : la colonne du badge reste vide sur chaque
  // ligne de continuation, et le texte n'en profite jamais). En WidgetSpan,
  // le badge ne prend de la place QUE sur sa propre ligne -- les lignes
  // suivantes utilisent toute la largeur, comme un vrai paragraphe imprimé.
  final Widget? leading;
  // Plage de mots à afficher (2026-08-01, mode Kindle : un verset trop long
  // pour une page est scindé au niveau du MOT, pas visuellement -- cf.
  // mushaf_screen.dart `_kindleWordLineBreaks`). null = tout le verset
  // (comportement historique, utilisé partout ailleurs dans l'app).
  final int? wordStart;
  final int? wordEnd;

  const TajweedText({
    super.key,
    required this.textUthmani,
    this.textUthmaniTajweed,
    this.fontSize = 26,
    this.lineHeight = 2.1,
    this.onWordTap,
    this.leading,
    this.wordStart,
    this.wordEnd,
  });

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.scheherazadeNew(
      fontSize: fontSize,
      height: lineHeight,
      color: AppColors.ink,
    );

    if (textUthmaniTajweed == null || textUthmaniTajweed!.isEmpty) {
      return _plainTappable(base);
    }

    // Split the tajweed HTML roughly by word boundaries while preserving spans
    // We build a single RichText with word-level tap recognizers
    return _buildTajweedRichText(base);
  }

  // Cf. commentaire du champ `leading` : embarqué en tête du flux de texte
  // (donc à droite en RTL) via WidgetSpan, pas dans un Row à côté -- ne
  // réserve de la place que sur SA propre ligne.
  List<InlineSpan> _leadingSpans() => leading == null
      ? const []
      : [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: leading!),
          const TextSpan(text: '  '),
        ];

  Widget _buildTajweedRichText(TextStyle base) {
    // tajweedSpansPerWord() reconstruit chaque mot depuis textUthmani (le
    // texte canonique) et n'emprunte que la couleur au champ tajwid --
    // jamais ses propres caractères (cf. commentaire de la fonction).
    final allWordSpans = tajweedSpansPerWord(textUthmani, textUthmaniTajweed, base);
    // BORNES CLAMPÉES (2026-08-06) : `sublist` lève un RangeError dès que la
    // plage sort du verset. L'appelant calcule `extraitDebut`/`extraitFin` sur
    // des indices de MOTS qui peuvent déborder -- notamment depuis que la
    // fenêtre d'écoute s'étend d'un mot avant ET après (demande utilisateur
    // « 3 mots »), ce qui rend le débordement atteignable en fin de verset.
    // Constaté en production : « j'ai cliqué sur un mot en erreur, j'ai
    // RangeError ». On CLAMPE ici plutôt qu'au seul appelant : ce widget est
    // partagé (feuille d'aide, mode Kindle, coach) et chacun calcule ses
    // bornes de son côté.
    final start = (wordStart ?? 0).clamp(0, allWordSpans.length);
    final end = (wordEnd ?? allWordSpans.length).clamp(start, allWordSpans.length);
    final wordSpans = allWordSpans.sublist(start, end);
    final children = <InlineSpan>[..._leadingSpans()];
    for (var i = 0; i < wordSpans.length; i++) {
      final wordIndex = start + i; // index RÉEL dans le verset, pas dans la plage
      final recognizer = onWordTap != null
          ? (TapGestureRecognizer()..onTap = () => onWordTap!(wordIndex))
          : null;
      for (final s in wordSpans[i]) {
        children.add(TextSpan(text: s.text, style: s.style, recognizer: recognizer));
      }
      if (i < wordSpans.length - 1) {
        children.add(TextSpan(text: ' ', style: base));
      }
    }
    return RichText(
      textDirection: TextDirection.rtl,
      // Sans ça (défaut = start), chaque ligne s'arrête dès que le mot
      // suivant ne rentre plus, sans étirer l'espacement pour rejoindre le
      // bord opposé -- ça donnait des lignes visiblement courtes malgré une
      // largeur disponible bien plus grande (signalé par l'utilisateur
      // 2026-08-01, vérifié par un cadre de debug : le conteneur occupait
      // déjà toute la largeur, seul le texte ne la remplissait pas). justify
      // étire l'espacement inter-mots des lignes non-finales pour toucher
      // les deux bords, comme un vrai Mushaf imprimé.
      textAlign: TextAlign.justify,
      text: TextSpan(children: children, style: base),
    );
  }

  Widget _plainTappable(TextStyle base) {
    if (onWordTap == null) {
      return Text(
        textUthmani,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        style: base,
      );
    }
    // Même filtre que tajweedSpansPerWord/ArabicNormalizer.splitExpectedWords
    // (cf. commentaire ci-dessus) : sans lui, une marque décorative isolée
    // (ex. "۞") décale l'index passé à onWordTap par rapport à RecitedWord.
    final allWords = textUthmani
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && ArabicNormalizer.normalize(w).isNotEmpty)
        .toList();
    // Mêmes bornes clampées que dans le rendu tajwid ci-dessus, et pour la
    // même raison (RangeError sur `sublist` quand la plage sort du verset).
    final start = (wordStart ?? 0).clamp(0, allWords.length);
    final end = (wordEnd ?? allWords.length).clamp(start, allWords.length);
    final words = allWords.sublist(start, end);
    return RichText(
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.justify, // cf. commentaire dans _buildTajweedRichText
      text: TextSpan(
        children: [
          ..._leadingSpans(),
          for (int i = 0; i < words.length; i++)
            TextSpan(
              text: i < words.length - 1 ? '${words[i]} ' : words[i],
              style: base,
              recognizer: TapGestureRecognizer()
                ..onTap = () => onWordTap!(start + i),
            ),
        ],
      ),
    );
  }
}
