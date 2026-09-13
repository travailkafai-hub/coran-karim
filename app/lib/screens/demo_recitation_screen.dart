// Démonstration de la récitation — SCRIPTÉE, et annoncée comme telle.
//
// ── CE QUE L'UTILISATEUR A DEMANDÉ (2026-09-13) ──────────────────────────────
//
// « Pour montrer la récitation, on pourrait afficher un exemple préparé :
//   progression des mots, validation, erreur, puis reprise et correction.
//   Important : ce serait une démonstration explicitement signalée, avec des
//   résultats prédéfinis. Elle ne lancerait pas le modèle, n'utiliserait pas le
//   micro et ne modifierait ni les statistiques ni la progression réelle. Le
//   texte coranique resterait intact. »
//
// Chacune de ces cinq garanties a une contrepartie VÉRIFIABLE dans ce fichier,
// et c'est volontairement listé ici pour qu'une modification future se heurte à
// la liste :
//
//   « explicitement signalée »  -> un bandeau permanent, non masquable, en haut
//                                  de l'écran. Pas un texte au lancement qu'on
//                                  oublie : il reste visible pendant toute la
//                                  démonstration.
//   « résultats prédéfinis »    -> [_scenario] ci-dessous. Le verdict de chaque
//                                  mot est écrit à la main.
//   « ne lance pas le modèle »  -> ce fichier n'importe NI
//                                  `fastconformer_verifier`, NI
//                                  `recitation_provider`, NI `record`. Il ne
//                                  peut donc pas les appeler.
//   « n'utilise pas le micro »  -> aucune permission n'est demandée, aucun
//                                  enregistreur n'est instancié.
//   « ne modifie ni les stats
//     ni la progression »       -> aucun import de `session_archive_service`,
//                                  `portion_word_archiver` ni d'un provider du
//                                  Coach. Rien n'est écrit, nulle part.
//
// ⚠️ SI QUELQU'UN AJOUTE UN IMPORT VERS L'UN DE CES SERVICES ICI, la promesse
// faite à l'utilisateur est rompue, et elle l'est en silence — une démo qui
// écrirait dans les statistiques ne se verrait qu'au moment où quelqu'un
// s'étonnerait d'une série qu'il n'a pas faite. L'absence d'import EST la
// garantie ; ne pas la remplacer par une condition `if (demo) return`, qu'un
// refactor peut déplacer.
//
// ── LE TEXTE CORANIQUE ───────────────────────────────────────────────────────
//
// Les mots viennent de `QuranApi` comme partout ailleurs — jamais tapés à la
// main. Règle du projet, payée une fois le 2026-07-09 : un « ي » persan saisi
// au clavier au lieu du « ي » arabe standard avait cassé la reconnaissance d'un
// mot, sans que rien ne se voie à l'écran.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/recitation_state.dart' show WordStatus;
import '../services/quran_api.dart';
import '../theme/app_theme.dart';

/// Le scénario : pour chaque mot, le verdict que la démonstration affichera.
///
/// Choisi pour montrer les quatre états que l'application sait produire, dans
/// un ordre qui raconte quelque chose : une série juste, un mot approximatif,
/// un mot faux, puis la reprise après correction. Une démonstration tout en
/// vert ne montrerait pas ce à quoi sert l'application.
const List<WordStatus> _scenario = [
  WordStatus.correct,
  WordStatus.correct,
  WordStatus.correct,
  WordStatus.correct,
  WordStatus.unclear, // articulation approximative
  WordStatus.correct,
  WordStatus.error, // écart entendu
  WordStatus.correct, // repris après la correction
  WordStatus.correct,
];

class DemoRecitationScreen extends StatefulWidget {
  const DemoRecitationScreen({super.key});

  @override
  State<DemoRecitationScreen> createState() => _DemoRecitationScreenState();
}

class _DemoRecitationScreenState extends State<DemoRecitationScreen> {
  List<String> _mots = const [];
  int _avance = 0;
  bool _enCours = false;
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Les mots de la Fātiḥa, versets 2 à 4 — lus depuis l'asset, pas saisis.
  Future<void> _charger() async {
    try {
      final versets = await QuranApi.fetchVerses(1);
      final mots = <String>[];
      for (final v in versets.where((v) => v.ayahNumber >= 2)) {
        mots.addAll(v.textUthmani.split(RegExp(r'\s+')).where((m) => m.isNotEmpty));
        if (mots.length >= _scenario.length) break;
      }
      if (!mounted) return;
      setState(() => _mots = mots.take(_scenario.length).toList());
    } catch (_) {
      // Une démonstration qui n'a pas pu charger le texte ne montre rien, mais
      // ne doit surtout pas planter : l'écran reste avec son bandeau et son
      // bouton, et l'utilisateur peut sortir.
    }
  }

  Future<void> _jouer() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _termine = false;
      _avance = 0;
    });
    for (var i = 0; i < _mots.length; i++) {
      // Une cadence proche d'une récitation posée. Pas de hasard : une
      // démonstration doit être identique à chaque fois, sinon on ne peut pas
      // la commenter.
      await Future<void>.delayed(const Duration(milliseconds: 620));
      if (!mounted || !_enCours) return;
      setState(() => _avance = i + 1);
      // Sur l'erreur, on marque un temps : c'est là que l'application
      // rejouerait le passage au récitateur.
      if (_scenario[i] == WordStatus.error) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _termine = true;
    });
  }

  Color _couleur(WordStatus s) => switch (s) {
        WordStatus.correct => AppColors.green600,
        WordStatus.unclear => const Color(0xFF9A6410),
        WordStatus.error => const Color(0xFFA63B2A),
        _ => AppColors.inkLight,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(t.demoRecitationTitre),
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
      ),
      body: Column(
        children: [
          _bandeau(t),
          Expanded(child: _texte()),
          _legende(t),
          _bouton(t),
        ],
      ),
    );
  }

  /// Le bandeau « ceci est une démonstration ». Permanent, non masquable.
  Widget _bandeau(AppLocalizations t) => Container(
        width: double.infinity,
        color: const Color(0xFF9A6410),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.demoRecitationBandeau,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _texte() {
    if (_mots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 14,
          children: [
            for (var i = 0; i < _mots.length; i++)
              _mot(i, i < _avance ? _scenario[i] : WordStatus.pending,
                  enCours: i == _avance && _enCours),
          ],
        ),
      ),
    );
  }

  Widget _mot(int i, WordStatus statut, {required bool enCours}) {
    final juge = statut != WordStatus.pending;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: enCours ? AppColors.readingCursorBg : Colors.transparent,
        border: Border.all(
          color: juge ? _couleur(statut).withAlpha(120) : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Text(
        _mots[i],
        style: GoogleFonts.amiri(
          fontSize: 27,
          height: 1.9,
          color: juge ? _couleur(statut) : AppColors.ink.withAlpha(90),
        ),
      ),
    );
  }

  Widget _legende(AppLocalizations t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _pastille(AppColors.green600, t.demoLegendeVert),
            _pastille(const Color(0xFF9A6410), t.demoLegendeOrange),
            _pastille(const Color(0xFFA63B2A), t.demoLegendeRouge),
          ],
        ),
      );

  Widget _pastille(Color c, String texte) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(texte,
              style: GoogleFonts.manrope(
                  fontSize: 11.5, color: AppColors.inkLight)),
        ],
      );

  Widget _bouton(AppLocalizations t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green800,
              foregroundColor: AppColors.cream,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _mots.isEmpty || _enCours ? null : _jouer,
            icon: Icon(_termine
                ? Icons.replay_rounded
                : Icons.play_arrow_rounded),
            label: Text(_enCours
                ? t.demoRecitationEnCours
                : (_termine ? t.demoRecitationRejouer : t.demoRecitationLancer)),
          ),
        ),
      );
}
