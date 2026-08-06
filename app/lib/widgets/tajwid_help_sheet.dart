import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/fastconformer_verifier.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import 'tajweed_text.dart';

/// Règles tajwid affichables : classe quran.com -> (couleur, nom/explication
/// localisés via ARB). Les couleurs répliquent celles de tajweed_text.dart
/// (source de vérité visuelle : le texte coloré au-dessus de la légende).
/// [name]/[explanation] prennent `AppLocalizations` -- pas de texte en dur,
/// les 3 langues (dont l'arabe, cf. REFONTE_IHM.md §7bis) sont dans les ARB.
class TajwidRuleInfo {
  final Color color;
  final String Function(AppLocalizations) name;
  final String Function(AppLocalizations) explanation;
  const TajwidRuleInfo(this.color, this.name, this.explanation);
}

// Couleurs et noms de classe IDENTIQUES à tajweed_text.dart (source de vérité
// unique — voir _classColors là-bas pour la provenance exacte et la note de
// correction 2026-07-06 : orthographes de classe réelles + teintes plus
// vives). Gris de référence défini une seule fois pour le tri ci-dessous.
const _kGray = Color(0xFF77766C);

final kTajwidRuleInfo = <String, TajwidRuleInfo>{
  'madda_necessary': TajwidRuleInfo(Color(0xFFA13420),
      _n(TajwidRuleName.maddaNecessary), _e(TajwidRuleName.maddaNecessary)),
  'madda_obligatory': TajwidRuleInfo(Color(0xFFE8391F),
      _n(TajwidRuleName.maddaObligatory), _e(TajwidRuleName.maddaObligatory)),
  'madda_permissible': TajwidRuleInfo(Color(0xFFEB7A1E),
      _n(TajwidRuleName.maddaPermissible), _e(TajwidRuleName.maddaPermissible)),
  'madda_normal': TajwidRuleInfo(Color(0xFFEB7A1E),
      _n(TajwidRuleName.maddaPermissible), _e(TajwidRuleName.maddaPermissible)),
  'ghunnah': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.ghunnah), _e(TajwidRuleName.ghunnah)),
  'ikhafa': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.ikhafa), _e(TajwidRuleName.ikhafa)),
  'ikhafa_shafawi': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.ikhafaShafawi), _e(TajwidRuleName.ikhafaShafawi)),
  'idgham_ghunnah': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.idghamGhunnah), _e(TajwidRuleName.idghamGhunnah)),
  'idgham_shafawi': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.idghamShafawi), _e(TajwidRuleName.idghamShafawi)),
  'iqlab': TajwidRuleInfo(Color(0xFF2E9E4F),
      _n(TajwidRuleName.iqlab), _e(TajwidRuleName.iqlab)),
  'idgham_wo_ghunnah': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.idghamWoGhunnah), _e(TajwidRuleName.idghamWoGhunnah)),
  'idgham_mutajanisayn': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.idghamMutajanisayn), _e(TajwidRuleName.idghamMutajanisayn)),
  'idgham_mutaqaribayn': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.idghamMutaqaribayn), _e(TajwidRuleName.idghamMutaqaribayn)),
  'qalaqah': TajwidRuleInfo(Color(0xFF0091EA),
      _n(TajwidRuleName.qalaqah), _e(TajwidRuleName.qalaqah)),
  'ham_wasl': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.hamWasl), _e(TajwidRuleName.hamWasl)),
  'laam_shamsiyah': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.laamShamsiyah), _e(TajwidRuleName.laamShamsiyah)),
  'slnt': TajwidRuleInfo(_kGray,
      _n(TajwidRuleName.slnt), _e(TajwidRuleName.slnt)),
};

/// Une entrée par règle tajwid -- évite un switch dupliqué (nom + explication)
/// et une string libre qui pourrait diverger des clés ARB réelles.
enum TajwidRuleName {
  maddaNecessary, maddaObligatory, maddaPermissible, ghunnah, ikhafa,
  ikhafaShafawi, idghamGhunnah, idghamShafawi, iqlab, idghamWoGhunnah,
  idghamMutajanisayn, idghamMutaqaribayn, qalaqah, hamWasl, laamShamsiyah, slnt,
}

String Function(AppLocalizations) _n(TajwidRuleName r) => (t) => switch (r) {
      TajwidRuleName.maddaNecessary => t.tajwidRuleMaddaNecessaryName,
      TajwidRuleName.maddaObligatory => t.tajwidRuleMaddaObligatoryName,
      TajwidRuleName.maddaPermissible => t.tajwidRuleMaddaPermissibleName,
      TajwidRuleName.ghunnah => t.tajwidRuleGhunnahName,
      TajwidRuleName.ikhafa => t.tajwidRuleIkhafaName,
      TajwidRuleName.ikhafaShafawi => t.tajwidRuleIkhafaShafawiName,
      TajwidRuleName.idghamGhunnah => t.tajwidRuleIdghamGhunnahName,
      TajwidRuleName.idghamShafawi => t.tajwidRuleIdghamShafawiName,
      TajwidRuleName.iqlab => t.tajwidRuleIqlabName,
      TajwidRuleName.idghamWoGhunnah => t.tajwidRuleIdghamWoGhunnahName,
      TajwidRuleName.idghamMutajanisayn => t.tajwidRuleIdghamMutajanisaynName,
      TajwidRuleName.idghamMutaqaribayn => t.tajwidRuleIdghamMutaqaribaynName,
      TajwidRuleName.qalaqah => t.tajwidRuleQalaqahName,
      TajwidRuleName.hamWasl => t.tajwidRuleHamWaslName,
      TajwidRuleName.laamShamsiyah => t.tajwidRuleLaamShamsiyahName,
      TajwidRuleName.slnt => t.tajwidRuleSlntName,
    };

String Function(AppLocalizations) _e(TajwidRuleName r) => (t) => switch (r) {
      TajwidRuleName.maddaNecessary => t.tajwidRuleMaddaNecessaryExplanation,
      TajwidRuleName.maddaObligatory => t.tajwidRuleMaddaObligatoryExplanation,
      TajwidRuleName.maddaPermissible => t.tajwidRuleMaddaPermissibleExplanation,
      TajwidRuleName.ghunnah => t.tajwidRuleGhunnahExplanation,
      TajwidRuleName.ikhafa => t.tajwidRuleIkhafaExplanation,
      TajwidRuleName.ikhafaShafawi => t.tajwidRuleIkhafaShafawiExplanation,
      TajwidRuleName.idghamGhunnah => t.tajwidRuleIdghamGhunnahExplanation,
      TajwidRuleName.idghamShafawi => t.tajwidRuleIdghamShafawiExplanation,
      TajwidRuleName.iqlab => t.tajwidRuleIqlabExplanation,
      TajwidRuleName.idghamWoGhunnah => t.tajwidRuleIdghamWoGhunnahExplanation,
      TajwidRuleName.idghamMutajanisayn => t.tajwidRuleIdghamMutajanisaynExplanation,
      TajwidRuleName.idghamMutaqaribayn => t.tajwidRuleIdghamMutaqaribaynExplanation,
      TajwidRuleName.qalaqah => t.tajwidRuleQalaqahExplanation,
      TajwidRuleName.hamWasl => t.tajwidRuleHamWaslExplanation,
      TajwidRuleName.laamShamsiyah => t.tajwidRuleLaamShamsiyahExplanation,
      TajwidRuleName.slnt => t.tajwidRuleSlntExplanation,
    };

/// Fiche d'aide affichée au tap sur un mot orange/rouge (Contrôle ou Karaoké) :
/// le verset complet coloré selon les règles de tajwid, la légende des règles
/// présentes, un bouton pour écouter le verset par le réciteur, et — si
/// [wordIndex] est fourni — une boucle de correction interactive (demande
/// utilisateur 2026-07-05) : écouter, se réenregistrer sur CE mot, valider.
/// Classes tajwid ACTIVES pour chaque mot du verset.
///
/// Parcourt le HTML `text_uthmani_tajweed` en suivant la pile de balises
/// ouvertes et en comptant les mots dans le TEXTE (separateur : espace). Rend
/// une liste parallele aux mots affiches -- meme decoupage que
/// `tajweedSpansPerWord`, qui coupe lui aussi sur l'espace.
///
/// La vraie balise est `<tajweed class=X>` (attribut SANS guillemets, cf.
/// tajweed_text.dart) : la regex accepte les deux formes. Le marqueur de fin
/// de verset `<span class=end>` est ignore -- ce n'est pas une regle.
List<Set<String>> _classesParMot(String html) {
  if (html.isEmpty) return const [];
  final mots = <Set<String>>[];
  var courant = <String>{};
  final pile = <String>[];
  var vuDuTexte = false;
  var i = 0;
  while (i < html.length) {
    final c = html[i];
    if (c == '<') {
      final fin = html.indexOf('>', i);
      if (fin < 0) break;
      final balise = html.substring(i + 1, fin);
      if (balise.startsWith('/')) {
        if (pile.isNotEmpty) pile.removeLast();
      } else if (!balise.endsWith('/')) {
        final m = RegExp(r'class=(?:"([^"]*)"|([^\s">]+))').firstMatch(balise);
        pile.add(m == null ? '' : (m.group(1) ?? m.group(2) ?? ''));
      }
      i = fin + 1;
      continue;
    }
    if (c == ' ' || c == '\n' || c == '\t') {
      if (vuDuTexte) {
        mots.add(courant);
        courant = <String>{};
        vuDuTexte = false;
      }
      i++;
      continue;
    }
    vuDuTexte = true;
    for (final cl in pile) {
      if (cl.isNotEmpty && cl != 'end') courant.add(cl);
    }
    i++;
  }
  if (vuDuTexte) mots.add(courant);
  return mots;
}

void showTajwidHelpSheet(
  BuildContext context,
  WidgetRef ref, {
  required Verse verse,
  required List<Verse> playlist,
  String? focusWord,
  /// Ce que le MODELE a reellement entendu sur ce mot (decodage libre).
  ///
  /// Demande utilisateur (2026-08-06) : « dans les erreurs il y a le mot
  /// erroné, je veux rajouter l'entendu dans cet écran ». C'est la seule
  /// information qui permet de comprendre un verdict sans lire le journal :
  /// un `entendu` vide ne dit pas la meme chose qu'un `entendu` qui differe
  /// d'une lettre, et un `entendu` IDENTIQUE a l'attendu dit que le defaut
  /// n'est pas dans la prononciation.
  String? entendu,
  int? wordIndex,
  int? localWordIndex,
  /// Plage de mots à AFFICHER, en indices locaux au verset (2026-08-05).
  ///
  /// Demande utilisateur : « quand je clique sur le mot en erreur j'ai toute
  /// l'aya qui s'affiche, je veux que ça reste sur le mot en question ; si
  /// deux ou trois mots en erreur sont côte à côte on peut les fusionner dans
  /// la même fenêtre ».
  ///
  /// null = verset entier (comportement d'origine, conservé pour les appels
  /// qui ne visent pas une erreur précise). La fusion des mots contigus est
  /// calculée par l'APPELANT, qui seul connaît les verdicts.
  int? extraitDebut,
  int? extraitFin,
}) {
  // ── LES REGLES DU MOT, PAS CELLES DU VERSET (2026-08-06) ────────────────
  //
  // Demande utilisateur : « pour les règles tajweed il ne faut pas mettre les
  // règles du verset mais plutôt les règles du mot en question ».
  //
  // La feuille s'ouvre sur UN mot signale : lister les regles de toute l'aya
  // noyait celle qui concerne ce mot au milieu de dix autres, et laissait
  // croire qu'elles s'y appliquaient toutes.
  //
  // POURQUOI UN EXTRACTEUR DEDIE ET PAS LES SPANS DEJA CALCULES : les spans de
  // `tajweed_text.dart` ne portent que des COULEURS, et plusieurs regles
  // partagent la meme (toutes les grises). Remonter d'une couleur a une regle
  // rendrait des regles fausses. On relit donc le HTML en suivant la pile de
  // classes et en comptant les mots dans le TEXTE.
  final classesParMot = _classesParMot(verse.textUthmaniTajweed ?? '');
  // Règles réellement présentes dans CE verset (via les classes du HTML).
  // La vraie balise est `<tajweed class=X>` (attribut SANS guillemets, voir
  // tajweed_text.dart) — pas `<span class="X">` comme supposé initialement,
  // ce qui faisait que cette légende ne détectait jamais rien.
  // Repli sur le VERSET entier quand l'appelant ne dit pas quel mot il vise
  // (ouverture depuis la lecture, pas depuis une erreur) -- comportement
  // d'avant, inchange dans ce cas.
  final Set<String> classes;
  if (extraitDebut != null && classesParMot.isNotEmpty) {
    final d = extraitDebut.clamp(0, classesParMot.length);
    final f = (extraitFin ?? (d + 1)).clamp(d, classesParMot.length);
    classes = <String>{for (var i = d; i < f; i++) ...classesParMot[i]};
  } else {
    classes = RegExp(r'class=(?:"([^"]*)"|([^\s">]+))')
        .allMatches(verse.textUthmaniTajweed ?? '')
        .map((m) => m.group(1) ?? m.group(2) ?? '')
        .toSet();
  }
  final rules = [
    for (final c in classes)
      if (kTajwidRuleInfo.containsKey(c) && kTajwidRuleInfo[c]!.color != _kGray)
        kTajwidRuleInfo[c]!,
    // Règles "grises" (wasl, lâm solaire, muettes) en fin de liste.
    for (final c in classes)
      if (kTajwidRuleInfo.containsKey(c) && kTajwidRuleInfo[c]!.color == _kGray)
        kTajwidRuleInfo[c]!,
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final t = AppLocalizations.of(ctx)!;
      return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  t.tajwidHelpVerseLabel(verse.key),
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.inkLight),
                ),
                if (focusWord != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.tajwidMadd.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      focusWord,
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.scheherazadeNew(
                          fontSize: 18, color: AppColors.ink),
                    ),
                  ),
                  // CE QUI A ETE ENTENDU, a cote de ce qui etait attendu.
                  // Teinte differente et fleche : les deux pastilles ne
                  // doivent pas pouvoir etre confondues.
                  if (entendu != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 14, color: AppColors.inkLight),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.inkLight.withAlpha(28),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entendu.trim().isEmpty ? '—' : entendu,
                        textDirection: TextDirection.rtl,
                        style: GoogleFonts.scheherazadeNew(
                            fontSize: 18, color: AppColors.inkLight),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: TajweedText(
                        textUthmani: verse.textUthmani,
                        textUthmaniTajweed: verse.textUthmaniTajweed,
                        fontSize: 26,
                        // Réutilise le découpage par mots déjà écrit pour le
                        // mode Kindle plutôt qu'un second rendu : un extrait
                        // affiché autrement que le verset serait une deuxième
                        // façon de dessiner le même texte, donc deux endroits
                        // à corriger le jour où la coloration change.
                        wordStart: extraitDebut,
                        wordEnd: extraitFin,
                      ),
                    ),
                    if (rules.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        t.tajwidHelpRulesInVerse,
                        style: GoogleFonts.manrope(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkLight),
                      ),
                      const SizedBox(height: 8),
                      for (final r in rules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: r.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.manrope(
                                        fontSize: 12.5,
                                        height: 1.45,
                                        color: AppColors.ink),
                                    children: [
                                      TextSpan(
                                        text: '${r.name(t)} — ',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      TextSpan(text: r.explanation(t)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (localWordIndex != null && focusWord != null) ...[
                      const SizedBox(height: 18),
                      _ListenRangeControl(
                        verse: verse,
                        localWordIndex: localWordIndex,
                        globalWordIndex: wordIndex,
                      ),
                    ],
                    if (wordIndex != null && focusWord != null) ...[
                      const SizedBox(height: 18),
                      _CorrectionLoop(wordIndex: wordIndex, focusWord: focusWord),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── FERMER, PAS UN SECOND BOUTON D'ECOUTE (2026-08-06) ──────────
            //
            // Demande utilisateur : « enlève le bouton tout en bas, c'est
            // pareil, c'est un doublon de la prononciation ; remplace-le par
            // un bouton fermer cette fenêtre ».
            //
            // Il lancait le verset chez le RECITATEUR de reference, ce que le
            // bloc « ecouter la prononciation » fait deja juste au-dessus, et
            // sur la bonne PLAGE (mot precedent + ce mot) au lieu de l'aya
            // entiere. Deux boutons verts pour la meme intention, dont le plus
            // gros faisait le moins bien.
            //
            // La feuille se fermait jusqu'ici par un glissement vers le bas --
            // geste que rien n'indique, sur un ecran ouvert au milieu d'une
            // recitation.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  t.tajwidHelpClose,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
      );
    },
  );
}

/// Choix de la portée (nombre de mots autour du mot tapé) pour l'écoute
/// manuelle du réciteur (demande utilisateur 2026-07-06) : quand la
/// correction automatique est désactivée, taper sur un mot rouge/orange doit
/// permettre de déclencher soi-même l'audio, avec un choix de portée — juste
/// ce mot, +le mot précédent (comportement par défaut de la correction
/// automatique), ou +le mot précédent ET le suivant.
class _ListenRangeControl extends ConsumerStatefulWidget {
  final Verse verse;
  final int localWordIndex;

  /// Index GLOBAL du mot dans la session — nécessaire pour retrouver la voix
  /// du récitateur, que la chaîne v2 indexe globalement (pas par verset).
  /// `null` hors session (feuille ouverte depuis la lecture normale).
  final int? globalWordIndex;
  const _ListenRangeControl({
    required this.verse,
    required this.localWordIndex,
    this.globalWordIndex,
  });

  @override
  ConsumerState<_ListenRangeControl> createState() => _ListenRangeControlState();
}

enum _Range { wordOnly, withPrevious, withBoth }

class _ListenRangeControlState extends ConsumerState<_ListenRangeControl> {
  // TROIS MOTS PAR DÉFAUT (demande utilisateur 2026-08-06 : « élargis la page
  // un peu pour qu'il puisse écouter 3 mots, un mot avant et un mot après »).
  // Un mot isolé s'écoute mal : l'attaque et la liaison portent une bonne
  // partie de ce qu'on cherche à entendre.
  // FIGE a « mot precedent + ce mot » (cf. le bloc d'explication dans build).
  // Le champ reste un _Range plutot qu'une paire de constantes : la plage est
  // relue a trois endroits, et l'enum documente ce qu'elle vaut.
  final _Range _range = _Range.withPrevious;
  bool _playing = false;
  bool _playingVoix = false;
  String? _erreurVoix;

  (int, int) get _bounds => switch (_range) {
        _Range.wordOnly => (0, 0),
        _Range.withPrevious => (1, 0),
        _Range.withBoth => (1, 1),
      };

  Future<void> _play() async {
    setState(() => _playing = true);
    final reciter = ref.read(playerProvider).reciter;
    final (before, after) = _bounds;
    try {
      await WordCorrectionAudio.playWordRange(
        widget.verse,
        reciter,
        errorWordIndex: widget.localWordIndex,
        wordsBefore: before,
        wordsAfter: after,
      );
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  /// MA VOIX — rejoue l'audio EXACT qui a servi à juger ces mots (2026-08-06).
  ///
  /// Ce n'est pas une reconstitution : la chaîne v2 garde le flux brut en
  /// mémoire (300 s) et chaque mot jugé porte ses bornes absolues dedans, donc
  /// on redonne à entendre l'échantillon qui a produit le verdict. C'est la
  /// seule façon de trancher « j'ai mal dit » contre « le modèle a mal
  /// entendu » — question posée en boucle pendant les analyses de session.
  Future<void> _playVoix() async {
    final g = widget.globalWordIndex;
    if (g == null) return;
    setState(() {
      _playingVoix = true;
      _erreurVoix = null;
    });
    try {
      final (before, after) = _bounds;
      final chemin = await ref
          .read(recitationVerifierProvider)
          .v2ExtraitVoix(g - before, g + after);
      if (!mounted) return;
      if (chemin == null) {
        // Cas légitimes : audio sorti de l'anneau (session longue), ou mots
        // sans position connue. On le DIT plutôt que de rester muet — un
        // bouton qui ne fait rien est indiscernable d'un bug.
        setState(() => _erreurVoix = 'Audio plus disponible');
        return;
      }
      await WordCorrectionAudio.playFile(chemin);
    } catch (e) {
      if (mounted) setState(() => _erreurVoix = 'Lecture impossible');
    } finally {
      if (mounted) setState(() => _playingVoix = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream200,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.tajwidHelpListenPronunciation,
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.green700,
            ),
          ),
          // ── PLUS DE CHOIX DE PLAGE (demande utilisateur 2026-08-06) ─────
          //
          // « pour épurer cet écran, enlève dans "écouter la prononciation"
          // "ce mot" / "mot précédent"... garde toujours par défaut le mot
          // d'avant et le mot en question ».
          //
          // Les trois puces demandaient un choix a chaque ouverture pour un
          // reglage dont la bonne valeur est toujours la meme : un mot seul
          // sort de son contexte (liaison, madd de la fin du mot precedent),
          // et le mot SUIVANT n'apporte rien pour juger celui-ci. Les
          // libelles `tajwidHelpThisWord` / `PlusPrevious` / `PlusBoth`
          // restent dans les traductions : ils redeviendront utiles si le
          // choix revient un jour.
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.green700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _playing ? null : _play,
              icon: Icon(
                _playing ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
                color: AppColors.green700,
              ),
              label: Text(
                _playing ? t.tajwidHelpPlaying : t.coachExplanationListen,
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: AppColors.green700),
              ),
            ),
          ),
          // ── MA VOIX (2026-08-06) ──────────────────────────────────────────
          // Seulement EN SESSION : hors récitation il n'y a aucun flux brut à
          // rejouer, et un bouton qui ne peut pas marcher ne doit pas
          // s'afficher.
          if (widget.globalWordIndex != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.brass),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _playingVoix ? null : _playVoix,
                icon: Icon(
                  _playingVoix
                      ? Icons.graphic_eq_rounded
                      : Icons.record_voice_over_outlined,
                  color: AppColors.brass,
                ),
                label: Text(
                  _playingVoix ? 'Lecture…' : 'Ma voix',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, color: AppColors.brass),
                ),
              ),
            ),
            if (_erreurVoix != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _erreurVoix!,
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.green700.withOpacity(0.7)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

enum _LoopState { idle, recording, analyzing, success, retry }

/// Boucle "réessaie ce mot" : enregistre un court passage, le transcrit
/// isolément (moteur FastConformer déjà chargé, mono-shot — pas le flux
/// bufferisé continu), compare au mot attendu, et si ça correspond, marque le
/// mot corrigé dans l'état de la récitation (verrouillé vert définitivement).
class _CorrectionLoop extends ConsumerStatefulWidget {
  final int wordIndex;
  final String focusWord;
  const _CorrectionLoop({required this.wordIndex, required this.focusWord});

  @override
  ConsumerState<_CorrectionLoop> createState() => _CorrectionLoopState();
}

class _CorrectionLoopState extends ConsumerState<_CorrectionLoop> {
  final _recorder = AudioRecorder();
  final _engine = FastConformerVerifier();
  _LoopState _state = _LoopState.idle;
  String? _heardText;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return;
    final ok = await _engine.ensureLoaded();
    if (!ok) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/word_retry_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    setState(() => _state = _LoopState.recording);
  }

  Future<void> _stopAndValidate() async {
    final path = await _recorder.stop();
    setState(() => _state = _LoopState.analyzing);
    if (path == null) {
      setState(() => _state = _LoopState.idle);
      return;
    }
    final text = await _engine.transcribe(path);
    try {
      await File(path).delete();
    } catch (_) {}

    final words = ref.read(recitationProvider).words;
    if (widget.wordIndex >= words.length) return;
    final expected = words[widget.wordIndex];

    // ── LE MOT REDIT DOIT ÊTRE LE MOT ATTENDU, PAS « À 75 % » ───────────
    //
    // Défaut signalé par l'utilisateur (2026-08-06) : « dans réessayer le mot,
    // là il m'affiche autre chose et il dit c'est ok ».
    //
    // Le critère était `similarity(...) >= 0.75` sur le squelette : un mot avec
    // une lettre fausse le franchissait. L'écran affichait alors le mot
    // RÉELLEMENT entendu -- donc un autre mot -- et annonçait « corrigé ». Deux
    // fautes en une : on valide ce qui ne l'est pas, et on le montre à
    // l'utilisateur en le félicitant.
    //
    // C'est précisément ce que le projet a déjà refusé une fois (2026-07-25,
    // règle « pas de correctif palliatif ») : « un récitateur qui ne dit que la
    // moitié d'un mot était alors validé -- précisément ce que l'app existe
    // pour détecter ».
    //
    // Le squelette doit donc être ÉGAL. On reste sur `normalized` (sans
    // harakat) et non `strict` : la boucle de correction sert à redire le MOT,
    // et une harakat approximative se juge dans la chaîne, pas ici -- durcir
    // jusque-là serait un second changement, non demandé et non mesuré.
    final heardNorm = ArabicNormalizer.normalize(text ?? '');
    final matches = heardNorm.isNotEmpty && heardNorm == expected.normalized;

    setState(() {
      _heardText = (text == null || text.trim().isEmpty)
          ? AppLocalizations.of(context)!.tajwidHelpNothingHeard
          : text.trim();
      _state = matches ? _LoopState.success : _LoopState.retry;
    });

    if (matches) {
      ref.read(recitationProvider.notifier).markWordCorrected(widget.wordIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.tajwidHelpRetryThisWord,
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.green700,
            ),
          ),
          const SizedBox(height: 8),
          if (_state == _LoopState.success)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t.tajwidHelpCorrectedHeard(_heardText ?? ''),
                      style: GoogleFonts.manrope(fontSize: 13, color: AppColors.green700)),
                ),
              ],
            )
          else ...[
            if (_state == _LoopState.retry)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t.tajwidHelpNotYetHeard(_heardText ?? ''),
                  style: GoogleFonts.manrope(fontSize: 12.5, color: const Color(0xFFb00020)),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                      color: _state == _LoopState.recording
                          ? const Color(0xFFb00020)
                          : AppColors.green700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _state == _LoopState.analyzing
                    ? null
                    : (_state == _LoopState.recording ? _stopAndValidate : _startRecording),
                icon: Icon(
                  _state == _LoopState.recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                  color: _state == _LoopState.recording ? const Color(0xFFb00020) : AppColors.green700,
                ),
                label: Text(
                  _state == _LoopState.analyzing
                      ? t.tajwidHelpAnalyzing
                      : (_state == _LoopState.recording
                          ? t.tajwidHelpFinishRecording
                          : t.tajwidHelpRecordThisWord),
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: _state == _LoopState.recording
                          ? const Color(0xFFb00020)
                          : AppColors.green700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
