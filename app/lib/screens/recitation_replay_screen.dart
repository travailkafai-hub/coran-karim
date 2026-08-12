import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';

/// REVOIR SA RÉCITATION TELLE QU'ELLE ÉTAIT À L'ÉCRAN (2026-08-12).
///
/// Demande utilisateur : « quand je clique sur ma récitation, qu'elle
/// m'affiche le même écran vert avec tous les mots et les couleurs [...]
/// reconstituer depuis un enregistrement en base ; du coup également mes
/// portions, même configuration mais en mode MAJ et cumul sur de nouveaux
/// versets ».
///
/// Ce que ça remplace : deux listes qui ne montraient QUE les mots fautifs,
/// hors de leur texte. On ne voyait donc jamais ce qu'on avait bien récité,
/// ni où se situait la faute dans le verset.
///
/// ── D'OÙ VIENNENT LES COULEURS, ET POURQUOI LES DEUX SOURCES DIFFÈRENT ────
///
/// Les deux tables ne stockent pas la même chose, et c'est volontaire :
///
///  - `session_words` ne garde que les **exceptions** (mots non verts d'UNE
///    tentative datée). Un mot absent de cette table et situé avant l'ancre
///    max a donc été récité JUSTE — c'est ce qui permet de repeindre l'écran
///    entier sans avoir stocké les milliers de mots corrects ;
///  - `portion_words` garde **chaque mot touché**, avec son dernier verdict
///    connu, cumulé sur toutes les récitations de la portion. C'est le « mode
///    MAJ » demandé : un mot re-récité juste repasse au vert, il ne
///    s'accumule pas en double.
///
/// D'où le seul paramètre qui distingue les deux usages : [motsNonVertsSeuls].
class RecitationReplayScreen extends ConsumerStatefulWidget {
  /// Titre affiché (nom de sourate, ou libellé de portion).
  final String titre;

  /// Sourate à reconstituer, et plage de versets à afficher.
  final int surahNumber;
  final int? premierVerset;
  final int? dernierVerset;

  /// Verdicts connus, indexés par `(verset, mot dans le verset)`.
  final Map<(int, int), String> verdicts;

  /// Nombre de mots réellement atteints par l'ancre (session), ou `null` pour
  /// une portion — où « atteint » se lit dans [verdicts] lui-même, puisque
  /// chaque mot touché y figure.
  final int? motsAtteints;

  /// `true` pour une session (la table ne contient que les non-verts, donc
  /// tout mot atteint et absent est VERT) ; `false` pour une portion (un mot
  /// absent n'a simplement jamais été récité).
  final bool motsNonVertsSeuls;

  const RecitationReplayScreen({
    super.key,
    required this.titre,
    required this.surahNumber,
    required this.verdicts,
    required this.motsNonVertsSeuls,
    this.premierVerset,
    this.dernierVerset,
    this.motsAtteints,
  });

  @override
  ConsumerState<RecitationReplayScreen> createState() =>
      _RecitationReplayScreenState();
}

class _RecitationReplayScreenState
    extends ConsumerState<RecitationReplayScreen> {
  late final Future<List<Verse>> _versets = _charger();

  Future<List<Verse>> _charger() async {
    final tous = await QuranApi.fetchVerses(widget.surahNumber);
    final a = widget.premierVerset ?? 1;
    final b = widget.dernierVerset ?? 9999;
    return tous.where((v) => v.ayahNumber >= a && v.ayahNumber <= b).toList();
  }

  /// Couleur d'un mot d'après son verdict. Le vert n'est PAS un défaut
  /// silencieux : il n'est attribué qu'à un mot dont on sait qu'il a été
  /// atteint (cf. l'en-tête de la classe), jamais à un mot jamais récité —
  /// sans quoi l'écran afficherait une réussite qui n'a pas eu lieu.
  ({Color fond, Color encre})? _couleur(String? verdict, bool atteint) {
    switch (verdict) {
      case 'error':
      case 'oubli':
        return (fond: Colors.redAccent.shade100, encre: AppColors.ink);
      case 'unclear':
        return (fond: AppColors.brass.withValues(alpha: 0.45), encre: AppColors.ink);
      case 'skipped':
        // Non jugé par la chaîne : ni succès ni faute (règle utilisateur
        // 2026-08-11). Neutre, jamais rouge.
        return (fond: AppColors.cream300, encre: AppColors.inkLight);
      case 'conteste':
      case 'correct':
        return (fond: AppColors.green700.withValues(alpha: 0.28), encre: AppColors.ink);
      default:
        if (widget.motsNonVertsSeuls && atteint) {
          return (fond: AppColors.green700.withValues(alpha: 0.28), encre: AppColors.ink);
        }
        return null; // jamais atteint -> pas de fond, texte grisé
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text(widget.titre,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 20, color: AppColors.brassLight)),
      ),
      body: FutureBuilder<List<Verse>>(
        future: _versets,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final versets = snap.data!;
          // Compteur de mots depuis le début de la plage : c'est lui qu'on
          // compare à `motsAtteints` (l'ancre max de la session).
          var rang = 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Legende(),
              const SizedBox(height: 12),
              for (final v in versets) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(v.key,
                      style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkLight)),
                ),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    spacing: 6,
                    runSpacing: 8,
                    children: [
                      for (final (i, mot) in ArabicNormalizer
                          .splitExpectedWords(v.textUthmani)
                          .indexed)
                        Builder(builder: (_) {
                          final atteint = widget.motsAtteints == null ||
                              rang < widget.motsAtteints!;
                          rang++;
                          final c = _couleur(
                              widget.verdicts[(v.ayahNumber, i)], atteint);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: c == null
                                ? null
                                : BoxDecoration(
                                    color: c.fond,
                                    borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              mot,
                              style: GoogleFonts.scheherazadeNew(
                                fontSize: 24,
                                color: c?.encre ??
                                    AppColors.inkLight.withValues(alpha: 0.45),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 24),
              Text(t.commonClose,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.inkLight)),
            ],
          );
        },
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget puce(Color c, String texte) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(texte,
                style: GoogleFonts.manrope(
                    fontSize: 11, color: AppColors.inkLight)),
          ],
        );
    return Wrap(spacing: 14, runSpacing: 8, children: [
      puce(AppColors.green700.withValues(alpha: 0.28), 'juste'),
      puce(Colors.redAccent.shade100, 'erreur'),
      puce(AppColors.brass.withValues(alpha: 0.45), 'douteux'),
      puce(AppColors.cream300, 'non jugé'),
    ]);
  }
}
