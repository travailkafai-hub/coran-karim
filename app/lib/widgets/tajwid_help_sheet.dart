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
import '../screens/coach_screen.dart';
import '../screens/memorization_game_screen.dart';
import '../services/fastconformer_verifier.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/session_archive_service.dart';
import '../services/voice_lora_clip_service.dart';
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
  /// Chemin d'un extrait "Ma voix" DÉJÀ archivé (2026-08-09).
  ///
  /// Demande utilisateur : « cette même page, je veux l'utiliser dans
  /// l'affichage coach » -- le Coach regarde une session PASSÉE, il n'y a
  /// plus de flux brut v2 en mémoire pour en extraire quoi que ce soit
  /// (`_ListenRangeControl._playVoix` s'appuie sinon sur
  /// `recitationVerifierProvider().v2ExtraitVoix`, qui n'a de sens qu'en
  /// session vivante). Quand ce chemin est fourni, "Ma voix" le rejoue
  /// directement au lieu d'extraire -- même bouton, même feuille, deux
  /// sources d'audio selon le contexte d'ouverture.
  String? archivedAudioPath,
  /// Appelé quand "Réessayer ce mot" réussit DEPUIS L'ARCHIVE (pas de
  /// session live, donc pas de `markWordCorrected` possible) -- l'appelant
  /// décide quoi faire (ex. retirer l'erreur du journal cumulé). Cf.
  /// `_CorrectionLoop.onCorrectedArchived`.
  VoidCallback? onArchivedWordCorrected,
  /// Appelé quand le pouce vers le bas ("pas d'accord, je l'ai bien dit")
  /// aboutit (2026-08-11, constat utilisateur : le pourcentage de « Mes
  /// portions » ne bougeait pas après une contestation -- la ligne
  /// `portion_words` était bien mise à jour en base, `_onPouceBas` n'avait
  /// juste personne à prévenir pour rafraîchir l'écran déjà ouvert derrière
  /// la feuille). L'appelant décide quoi invalider (portionsProvider,
  /// motsDePortionProvider(portionId)...) -- cette feuille ne sait pas dans
  /// quel écran elle a été ouverte.
  VoidCallback? onWordContested,
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
                        focusWord: focusWord,
                        archivedAudioPath: archivedAudioPath,
                        onWordContested: onWordContested,
                      ),
                    ],
                    // ── DISPONIBLE AUSSI DEPUIS L'ARCHIVE (2026-08-10) ───────
                    // Demande utilisateur : « depuis Coach on n'a pas le
                    // moyen de refaire le nouvel enregistrement, il faut
                    // l'avoir même ici, pas que quand on fait la
                    // récitation ». Condition alignée sur `_ListenRangeControl`
                    // ci-dessus (`localWordIndex`, dispo dans les deux
                    // contextes) plutôt que sur `wordIndex` (global, LIVE
                    // seulement) -- `_CorrectionLoop` sait maintenant
                    // fonctionner sans session live, cf. sa doc.
                    if (localWordIndex != null && focusWord != null) ...[
                      const SizedBox(height: 18),
                      _CorrectionLoop(
                        wordIndex: wordIndex,
                        focusWord: focusWord,
                        verse: verse,
                        localWordIndex: localWordIndex,
                        onCorrectedArchived: onArchivedWordCorrected,
                      ),
                    ],
                    // ── S'ENTRAÎNER SUR CE VERSET (2026-08-09) ──────────────
                    //
                    // Demande utilisateur : « je veux rajouter dans cette
                    // page un lien pour lancer la mémorisation et le jeu sur
                    // ce verset ». Valable qu'on ouvre la feuille EN DIRECT
                    // (Karaoké/Contrôle) ou depuis l'archive Coach -- dans les
                    // deux cas on sait déjà quel verset et quel mot. Utilise
                    // le `context` EXTÉRIEUR (celui de l'écran appelant, pas
                    // celui du bottom sheet) pour la navigation, car la
                    // feuille se ferme avant de pousser le nouvel écran.
                    if (localWordIndex != null) ...[
                      const SizedBox(height: 18),
                      _EntrainementLauncher(
                        outerContext: context,
                        verse: verse,
                        localWordIndex: localWordIndex,
                      ),
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

  /// Mot attendu -- nécessaire pour archiver l'extrait contesté avec son
  /// texte (cf. `_onPouceBas`, demande utilisateur 2026-08-07).
  final String focusWord;

  /// Extrait "Ma voix" déjà archivé sur disque (session Coach passée) --
  /// voir la doc sur `showTajwidHelpSheet`. Quand fourni, "Ma voix" le
  /// rejoue directement au lieu d'extraire depuis le flux v2 en direct.
  final String? archivedAudioPath;

  /// Cf. `showTajwidHelpSheet.onWordContested`.
  final VoidCallback? onWordContested;
  const _ListenRangeControl({
    required this.verse,
    required this.localWordIndex,
    required this.focusWord,
    this.globalWordIndex,
    this.archivedAudioPath,
    this.onWordContested,
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

  // ── Pouces "d'accord" / "pas d'accord" (demande utilisateur 2026-08-07) ──
  // Chemin du dernier extrait "Ma voix" rejoué -- c'est LUI que le pouce vers
  // le bas archive (même fichier, pas une nouvelle extraction). Réinitialisé
  // à chaque nouvelle écoute : les pouces ne portent que sur le DERNIER
  // extrait entendu, jamais un précédent qu'on ne réentendrait pas.
  String? _cheminVoixActuel;
  bool _feedbackEnvoye = false;
  bool _feedbackEnCours = false;

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
    final archive = widget.archivedAudioPath;
    final g = widget.globalWordIndex;
    if (archive == null && g == null) return;
    setState(() {
      _playingVoix = true;
      _erreurVoix = null;
      // Nouvel extrait en cours : les pouces d'un extrait précédent ne
      // portent plus sur ce qui va être entendu maintenant.
      _cheminVoixActuel = null;
      _feedbackEnvoye = false;
    });
    try {
      // Session ARCHIVÉE (Coach) : l'extrait est déjà sur disque, rien à
      // extraire -- cf. doc sur `showTajwidHelpSheet.archivedAudioPath`.
      final chemin = archive ??
          await ref.read(recitationVerifierProvider).v2ExtraitVoix(
              g! - _bounds.$1, g + _bounds.$2);
      if (!mounted) return;
      if (chemin == null) {
        // Cas légitimes : audio sorti de l'anneau (session longue), ou mots
        // sans position connue. On le DIT plutôt que de rester muet — un
        // bouton qui ne fait rien est indiscernable d'un bug.
        setState(() => _erreurVoix = 'Audio plus disponible');
        return;
      }
      setState(() => _cheminVoixActuel = chemin);
      await WordCorrectionAudio.playFile(chemin);
    } catch (e) {
      if (mounted) setState(() => _erreurVoix = 'Lecture impossible');
    } finally {
      if (mounted) setState(() => _playingVoix = false);
    }
  }

  /// Pouce vers le HAUT : « d'accord, l'app a bien vu ». L'erreur est déjà
  /// enregistrée sans condition au moment du jugement
  /// (`RecitationErrorLogService.logError`, appelé par
  /// `karaoke_recitation_screen.dart` pour CHAQUE mot faux/incertain) --
  /// rien à écrire de plus, ce pouce n'est qu'un accusé de réception visuel
  /// (décision utilisateur 2026-08-07 : pas de nouvelle colonne en base pour
  /// l'instant).
  void _onPouceHaut() {
    if (_feedbackEnvoye || _feedbackEnCours) return;
    setState(() => _feedbackEnvoye = true);
  }

  /// Pouce vers le BAS : « pas d'accord, je l'ai bien dit ». Archive
  /// l'extrait exact déjà entendu (pas une nouvelle extraction) pour un
  /// export manuel ultérieur depuis Réglages, ET retire l'erreur du journal
  /// pour que les statistiques du Coach ne comptent pas un faux positif que
  /// l'utilisateur vient lui-même d'invalider (décision utilisateur
  /// 2026-08-07).
  Future<void> _onPouceBas() async {
    final chemin = _cheminVoixActuel;
    if (chemin == null || _feedbackEnvoye || _feedbackEnCours) return;
    setState(() => _feedbackEnCours = true);
    try {
      await VoiceLoraClipService().commitDisputedClip(
        sourcePath: chemin,
        text: widget.focusWord,
        verdict: 'conteste_par_utilisateur',
      );
      await RecitationErrorLogService.instance.removeLatestError(
        surahNumber: widget.verse.surahNumber,
        ayahNumber: widget.verse.ayahNumber,
        wordIndex: widget.localWordIndex,
      );
      // Suivi permanent par portion (Coach, 2026-08-10) : un mot contesté
      // compte comme correct pour le badge de réussite (cf.
      // PortionResume.badge) -- même geste, même instant, indépendant du
      // journal cumulé d'erreurs ci-dessus (deux services distincts, cf.
      // session_archive_service.dart pour pourquoi ils ne fusionnent pas).
      await SessionArchiveService.instance.contesterMotDePortion(
        surahNumber: widget.verse.surahNumber,
        ayahNumber: widget.verse.ayahNumber,
        wordInAyah: widget.localWordIndex,
      );
      // Prévient l'écran appelant (Coach) qu'il doit rafraîchir ses
      // pourcentages -- cf. `showTajwidHelpSheet.onWordContested`.
      widget.onWordContested?.call();
    } finally {
      if (mounted) {
        setState(() {
          _feedbackEnCours = false;
          _feedbackEnvoye = true;
        });
      }
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
          // ── MA VOIX (2026-08-06, étendu 2026-08-09) ─────────────────────
          // EN SESSION (`globalWordIndex`) ou depuis une archive Coach
          // (`archivedAudioPath`) : dans les deux cas un extrait existe déjà
          // quelque part. Hors des deux, il n'y a aucun flux brut à rejouer,
          // et un bouton qui ne peut pas marcher ne doit pas s'afficher.
          if (widget.globalWordIndex != null || widget.archivedAudioPath != null) ...[
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
            // ── D'ACCORD / PAS D'ACCORD (2026-08-07) ────────────────────────
            // TOUJOURS visible dès qu'on est en session (retour utilisateur :
            // « c'est mieux qu'il soit visible » -- une première version ne
            // l'affichait qu'après avoir écouté "Ma voix", ce qui la rendait
            // indécouvrable). Les boutons restent grisés/inactifs tant
            // qu'aucun extrait n'a encore été entendu (`_cheminVoixActuel`) :
            // voter sur un son qu'on n'a pas écouté n'a pas de sens, mais la
            // ligne elle-même ne doit plus se cacher.
            if (widget.globalWordIndex != null || widget.archivedAudioPath != null) ...[
              const SizedBox(height: 10),
              _PouceFeedbackRow(
                pret: _cheminVoixActuel != null,
                envoye: _feedbackEnvoye,
                enCours: _feedbackEnCours,
                onHaut: _onPouceHaut,
                onBas: _onPouceBas,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _ChoixEntrainement { jeu, paliers }

/// Lance le jeu de mémorisation ou l'entraînement par paliers sur le verset
/// du mot signalé (2026-08-09, demande utilisateur : « je veux rajouter dans
/// cette page un lien pour lancer la mémorisation et le jeu sur ce verset »,
/// puis, sur le réemploi dans Coach : « on ne sait jamais que l'utilisateur
/// ne fait rien [dans l'immédiat], il faut pouvoir revenir dessus via
/// coach »).
///
/// Reprend la logique qui vivait avant dans
/// `coach_sessions._LigneMot._entrainer` -- déplacée ici pour n'exister qu'à
/// UN seul endroit : la feuille est désormais ouverte aussi bien depuis la
/// récitation en direct que depuis l'archive Coach, les deux doivent pouvoir
/// lancer le même entraînement plutôt que d'avoir chacune sa copie.
///
/// [outerContext] est le `context` de l'ÉCRAN qui a ouvert la feuille (pas
/// celui, éphémère, du bottom sheet) : la feuille se ferme AVANT de pousser
/// le nouvel écran, donc la navigation doit partir d'un contexte qui survit
/// à cette fermeture.
class _EntrainementLauncher extends StatefulWidget {
  final BuildContext outerContext;
  final Verse verse;
  final int localWordIndex;
  const _EntrainementLauncher({
    required this.outerContext,
    required this.verse,
    required this.localWordIndex,
  });

  @override
  State<_EntrainementLauncher> createState() => _EntrainementLauncherState();
}

class _EntrainementLauncherState extends State<_EntrainementLauncher> {
  bool _busy = false;
  String? _erreur;

  Future<void> _choisir() async {
    final choix = await showModalBottomSheet<_ChoixEntrainement>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videogame_asset_rounded,
                  color: Colors.lightBlue),
              title: const Text('Jeu de mémorisation'),
              subtitle: const Text('En partant deux versets avant'),
              onTap: () => Navigator.pop(ctx, _ChoixEntrainement.jeu),
            ),
            ListTile(
              leading: const Icon(Icons.school_rounded,
                  color: AppColors.green700),
              title: const Text('Entraînement par paliers'),
              subtitle: const Text('Écoute, imite, contrôle -- sur ce verset'),
              onTap: () => Navigator.pop(ctx, _ChoixEntrainement.paliers),
            ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;
    setState(() {
      _busy = true;
      _erreur = null;
    });
    try {
      final verse = widget.verse;
      final tousVersets = await QuranApi.fetchVerses(verse.surahNumber);
      if (!mounted) return;
      final outer = widget.outerContext;
      if (choix == _ChoixEntrainement.paliers) {
        final verset = tousVersets.firstWhere(
            (v) => v.ayahNumber == verse.ayahNumber,
            orElse: () => tousVersets.first);
        // Ferme la feuille AVANT de pousser le nouvel écran -- sinon elle
        // reste ouverte par-dessus (même geste que le bouton "Fermer" plus
        // bas, juste déclenché par ce choix-ci).
        Navigator.of(context).pop();
        if (!outer.mounted) return;
        Navigator.push(outer,
            MaterialPageRoute(builder: (_) => CoachScreen(verses: [verset])));
        return;
      }
      final surahs = await QuranApi.fetchSurahs();
      final surah = surahs.firstWhere((s) => s.number == verse.surahNumber);
      final depart = (verse.ayahNumber - 2).clamp(1, verse.ayahNumber);
      final versets =
          tousVersets.where((v) => v.ayahNumber >= depart).toList();
      if (versets.isEmpty || !mounted) return;
      Navigator.of(context).pop();
      if (!outer.mounted) return;
      Navigator.push(
        outer,
        MaterialPageRoute(
          builder: (_) => MemorizationGameScreen(surah: surah, verses: versets),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Entraînement indisponible');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            'S\'ENTRAÎNER SUR CE VERSET',
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.brass,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.brass),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : _choisir,
              icon: Icon(
                _busy ? Icons.hourglass_top_rounded : Icons.school_outlined,
                color: AppColors.brass,
              ),
              label: Text(
                'Jeu ou entraînement par paliers',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: AppColors.brass),
              ),
            ),
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _erreur!,
                style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pouces "d'accord" / "pas d'accord" avec le verdict, sous l'extrait "Ma
/// voix" (demande utilisateur 2026-08-07). Une fois un choix envoyé, les deux
/// se figent sur le choix fait (pastille pleine + libellé de remerciement) --
/// pas de retour en arrière, cohérent avec le reste de l'app (un verdict
/// verrouillé ne se rejuge pas, cf. `_judge` dans `recitation_provider.dart`).
class _PouceFeedbackRow extends StatelessWidget {
  /// Un extrait "Ma voix" a déjà été entendu -- sinon les pouces restent
  /// visibles (retour utilisateur : « c'est mieux qu'il soit visible ») mais
  /// grisés, voter sur un son qu'on n'a pas écouté n'a pas de sens.
  final bool pret;
  final bool envoye;
  final bool enCours;
  final VoidCallback onHaut;
  final VoidCallback onBas;
  const _PouceFeedbackRow({
    required this.pret,
    required this.envoye,
    required this.enCours,
    required this.onHaut,
    required this.onBas,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (envoye) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.green700.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 16, color: AppColors.green700),
            const SizedBox(width: 8),
            Text(
              t.tajwidHelpVoiceFeedbackThanks,
              style: GoogleFonts.manrope(
                  fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.green700),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            pret
                ? t.tajwidHelpVoiceFeedbackPrompt
                : t.tajwidHelpVoiceFeedbackNeedsListen,
            style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
          ),
        ),
        const SizedBox(width: 8),
        _PouceButton(
          icon: Icons.thumb_up_alt_rounded,
          color: AppColors.green700,
          tooltip: t.tajwidHelpVoiceThumbsUp,
          active: pret,
          onTap: (pret && !enCours) ? onHaut : null,
        ),
        const SizedBox(width: 8),
        _PouceButton(
          icon: Icons.thumb_down_alt_rounded,
          color: _kPouceBasColor,
          tooltip: t.tajwidHelpVoiceThumbsDown,
          active: pret,
          onTap: (pret && !enCours) ? onBas : null,
        ),
      ],
    );
  }
}

// Rouge chaud, cohérent avec la palette terre/vert/laiton du reste de l'app
// -- ne réutilise pas `recitationTajwidError` (violet, sens différent : écart
// de règle tajwid, pas un désaccord utilisateur).
const _kPouceBasColor = Color(0xFFC0392B);

class _PouceButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;
  const _PouceButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? color : AppColors.inkLight;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.withAlpha(active ? 24 : 14),
            shape: BoxShape.circle,
            border: Border.all(color: c.withAlpha(active ? 90 : 50)),
          ),
          child: Icon(icon, size: 17, color: c),
        ),
      ),
    );
  }
}

enum _LoopState { idle, recording, analyzing, success, retry }

/// Boucle "réessaie ce mot" : enregistre un court passage, le transcrit
/// isolément (moteur FastConformer déjà chargé, mono-shot — pas le flux
/// bufferisé continu), compare au mot attendu, et si ça correspond, marque le
/// mot corrigé dans l'état de la récitation (verrouillé vert définitivement).
///
/// ── LE MOT EST DIT AVEC SON CONTEXTE, PAS SEUL (2026-08-10) ─────────────
///
/// Diagnostic utilisateur, confirmé par le code : le clip envoyé au modèle
/// ne contenait QUE le mot retenté, sans rien avant -- exactement la
/// condition où le skill `solution-de-fond` documente que le modèle décode
/// mal (« il lit correctement chaque mot dès qu'on lui donne une fenêtre de
/// 2 à 4 s où le mot n'est pas au bord »). Deux pistes écartées : coller de
/// l'audio RÉCITATEUR devant (impossible sans décodeur MP3->PCM, absent du
/// projet -- ajouter FFmpeg ou du code natif MediaCodec est un chantier en
/// soi) ; coller le PCM déjà capté de la session live (faisable mais c'est
/// alors la propre voix -- potentiellement fautive -- de l'utilisateur qui
/// sert de contexte, pas un modèle de bonne prononciation).
///
/// Solution retenue (proposée par l'utilisateur) : ne plus fabriquer un
/// clip isolé du tout -- demander de redire aussi le(s) mot(s) qui
/// précèdent, dans LE MÊME enregistrement. Le mot à juger n'est alors plus
/// au bord de la fenêtre, sans toucher à un seul octet du pipeline audio.
/// Le critère de validation porte sur le DERNIER mot transcrit (la fin de
/// la phrase dite), pas sur la transcription entière.
class _CorrectionLoop extends ConsumerStatefulWidget {
  /// Position GLOBALE dans la session EN DIRECT -- `null` quand la feuille
  /// est ouverte depuis l'archive Coach (2026-08-10, demande utilisateur :
  /// « depuis Coach on n'a pas le moyen de refaire le nouvel enregistrement,
  /// il faut l'avoir même ici, pas que quand on fait la récitation »). Ne
  /// sert plus qu'à `markWordCorrected` sur la session live -- la
  /// comparaison et le contexte affiché reposent désormais sur [verse] +
  /// [localWordIndex], disponibles dans les deux contextes.
  final int? wordIndex;
  final String focusWord;
  final Verse verse;
  final int localWordIndex;
  /// Appelé à la place de `markWordCorrected` quand [wordIndex] est `null`
  /// (archive) -- l'appelant décide ce que "corrigé" veut dire hors session
  /// live (ex. retirer l'erreur du journal cumulé).
  final VoidCallback? onCorrectedArchived;
  const _CorrectionLoop({
    required this.wordIndex,
    required this.focusWord,
    required this.verse,
    required this.localWordIndex,
    this.onCorrectedArchived,
  });

  @override
  ConsumerState<_CorrectionLoop> createState() => _CorrectionLoopState();
}

class _CorrectionLoopState extends ConsumerState<_CorrectionLoop> {
  final _recorder = AudioRecorder();
  final _engine = FastConformerVerifier();
  _LoopState _state = _LoopState.idle;
  String? _heardText;

  /// Jusqu'à 2 mots avant [focusWord], pour donner du contexte au modèle --
  /// moins près du début du verset s'il y en a moins. Lu depuis le TEXTE du
  /// verset ([Verse.textUthmani]), pas depuis `recitationProvider` : ce
  /// dernier n'existe qu'en session live, alors que cette boucle doit aussi
  /// fonctionner depuis l'archive Coach (2026-08-10).
  List<String> _motsDeContexte() {
    final mots = ArabicNormalizer.splitExpectedWords(widget.verse.textUthmani);
    final debut = (widget.localWordIndex - 2).clamp(0, widget.localWordIndex);
    return [
      for (var i = debut; i < widget.localWordIndex && i < mots.length; i++)
        mots[i]
    ];
  }

  /// Le mot qui suit [focusWord], s'il y en a un (2026-08-10, demande
  /// utilisateur : « il faut aussi dire un mot en plus après, pour bien
  /// cibler le mot entier »). Avoir un mot après, pas seulement avant, sort
  /// le mot ciblé du BORD de la fenêtre -- exactement la condition que le
  /// skill `solution-de-fond` documente comme celle où le modèle décode
  /// fiablement (« une fenêtre de 2 à 4 s où le mot n'est pas au bord »).
  /// `null` si [focusWord] est le tout dernier mot du verset -- rien à dire
  /// après lui.
  String? _motApres() {
    final mots = ArabicNormalizer.splitExpectedWords(widget.verse.textUthmani);
    final apres = widget.localWordIndex + 1;
    return apres < mots.length ? mots[apres] : null;
  }

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

    // Attendu tiré de `focusWord` (pas de `recitationProvider.words`) : ce
    // dernier n'existe qu'en session live, cette boucle doit aussi marcher
    // depuis l'archive Coach (2026-08-10) -- même normalisation que celle
    // qui construit `RecitedWord.normalized` ailleurs dans l'app, donc
    // équivalente pour ce mot précis.
    final expectedNorm = ArabicNormalizer.normalize(widget.focusWord);

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
    //
    // ── ON JUGE LE MOT À SA POSITION DANS LA PHRASE, PAS TOUTE LA PHRASE
    // (2026-08-10) ── Le clip contient maintenant le(s) mot(s) de contexte
    // AVANT, le mot ciblé, ET un mot après quand il y en a un (cf. doc de la
    // classe et `_motApres` : le mot ciblé sort ainsi du BORD de la fenêtre,
    // condition où le modèle décode le mieux). Comparer `text` en entier à
    // `expected.normalized` échouerait dès qu'un mot de contexte est
    // prononcé -- on isole donc le mot à la position attendue, PAS forcément
    // le dernier ni le premier.
    //
    // Limite acceptée : cette position suppose que la transcription segmente
    // le contexte AVANT en autant de mots qu'attendu. Une fusion/coupure de
    // segmentation sur le contexte décale l'index et peut faire échouer un
    // mot pourtant bien dit -- un faux négatif (redemande), jamais un faux
    // positif (jamais moins strict), donc acceptable pour cette boucle dont
    // le rôle est justement de ne jamais valider à tort.
    final heardTokens = ArabicNormalizer.splitExpectedWords(text ?? '')
        .map((w) => ArabicNormalizer.normalize(w))
        .where((w) => w.isNotEmpty)
        .toList();
    final positionCible = _motsDeContexte().length;
    final heardNorm =
        positionCible < heardTokens.length ? heardTokens[positionCible] : '';
    final matches = heardNorm.isNotEmpty && heardNorm == expectedNorm;

    setState(() {
      _heardText = (text == null || text.trim().isEmpty)
          ? AppLocalizations.of(context)!.tajwidHelpNothingHeard
          : text.trim();
      _state = matches ? _LoopState.success : _LoopState.retry;
    });

    if (matches) {
      final wi = widget.wordIndex;
      if (wi != null) {
        ref.read(recitationProvider.notifier).markWordCorrected(wi);
      } else {
        widget.onCorrectedArchived?.call();
      }
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
          const SizedBox(height: 6),
          // ── LA PHRASE À DIRE, PAS SEULEMENT LE MOT (2026-08-10) ─────────
          // Sans ce rappel, rien ne dit à l'utilisateur qu'il doit redire
          // aussi ce qui précède -- il redirait naturellement le seul mot
          // affiché en haut de la feuille (`focusWord`), reproduisant
          // exactement le clip isolé qu'on cherche à éviter.
          //
          // ── + UN MOT APRÈS (2026-08-10) ─────────────────────────────────
          // Demande utilisateur : « pour réessayer le mot, il faut aussi
          // dire un mot en plus après, pour bien cibler le mot entier » --
          // cf. `_motApres`.
          Builder(builder: (context) {
            final contexte = _motsDeContexte();
            final apres = _motApres();
            final aUnePhrase = contexte.isNotEmpty || apres != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aUnePhrase
                      ? t.tajwidHelpRecordWithContext
                      : t.tajwidHelpRecordWithContextNone,
                  style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
                ),
                if (aUnePhrase) ...[
                  const SizedBox(height: 4),
                  Text(
                    [...contexte, widget.focusWord, ?apres].join(' '),
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.scheherazadeNew(fontSize: 18, color: AppColors.ink),
                  ),
                ],
              ],
            );
          }),
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
