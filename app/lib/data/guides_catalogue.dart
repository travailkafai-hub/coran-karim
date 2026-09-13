// Catalogue des visites guidées : un tour d'ensemble, puis un chapitre par
// fonction, jusqu'au sous-détail.
//
// ── POURQUOI UN CATALOGUE ET PAS UNE VISITE UNIQUE ───────────────────────────
//
// Deux demandes de l'utilisateur, à première vue contradictoires, qui se
// concilient exactement ici :
//
//   « Je privilégierais un démarrage court, puis des guides par fonction :
//     lecture, récitation, mémorisation, prières. Tout parcourir
//     automatiquement dès l'installation serait long. »
//   « Je veux un globale et de taillé même sous détaillé. »
//
// La réponse n'est donc PAS une visite de quarante étapes au premier
// lancement : c'est un tour d'ensemble court qui se joue tout seul, et des
// chapitres détaillés qu'on ouvre quand on en a besoin, depuis les réglages.
// Personne n'apprend une application entière en une fois ; on y revient.
//
// ── CE QU'UN CHAPITRE COÛTE ──────────────────────────────────────────────────
//
// Mesuré (`flutter build apk --release --analyze-size`, 2026-09-13) : tout le
// moteur de visite pèse 15,7 Ko de code AOT, et l'écran de préparation 16,0 Ko
// — 0,17 % du code Dart de l'application, 0,012 % de l'APK. Un seul MP3
// d'adhan pèse 3 Mo, soit cent fois le tutoriel entier. AUCUN asset n'est
// ajouté : la main est un emoji rendu par la police du système, le voile et le
// halo sont dessinés au `Canvas`.
//
// Conséquence pratique, et c'est le point : ajouter un chapitre coûte une
// dizaine de lignes ici et deux chaînes traduites. Il n'y a aucune raison de
// se rationner.
//
// ── LA RÈGLE QUI NE SE NÉGOCIE PAS ───────────────────────────────────────────
//
// ⚠️ AUCUNE `action` de ce fichier ne doit déclencher une demande de
// permission (micro, position, notifications). Consigne utilisateur : « les
// autorisations du téléphone resteraient à accepter par l'utilisateur, jamais
// par la main simulée ». La visite AMÈNE devant la fonction ; c'est
// l'utilisateur qui accepte. Cf. l'en-tête de `widgets/guide_interactif.dart`,
// où l'incapacité est garantie par construction (aucun événement tactile n'est
// synthétisé).

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/about_screen.dart';
import '../screens/prayer_times_settings_screen.dart';
import '../screens/demo_recitation_screen.dart';
import '../screens/mushaf_opening_screen.dart';
import '../screens/qibla_screen.dart';
import '../widgets/guide_interactif.dart';

// ── ACCROCHES POSÉES PAR `main.dart` ────────────────────────────────────────
//
// Variables de premier niveau, et non des membres statiques d'une classe
// d'écran : `_CoranKarimAppState` est privé, donc ses statiques sont
// invisibles depuis ce fichier (erreur commise d'abord, signalée par
// `flutter analyze` en « unused_field »).
//
// Toutes remises à `null` dans le `dispose` de l'écran d'accueil : un chapitre
// lancé après démontage appellerait sinon un `setState` sur un State mort.

/// Change d'onglet dans la barre du bas.
void Function(int)? allerAOngletGuide;

/// Positions réelles des onglets, pour les mettre en lumière.
GlobalKey? cleOngletCoran;
GlobalKey? cleOngletDuas;
GlobalKey? cleOngletCoach;

// ── CIBLES À L'INTÉRIEUR DE L'ACCUEIL (2026-09-13) ──────────────────────────
//
// Sans elles, les étapes qui parlent d'un détail d'écran se contentaient de le
// DÉCRIRE : la main se posait au centre et rien n'était mis en lumière. C'était
// la faiblesse annoncée du premier jet, et c'est ce que ces clés corrigent.
//
// Elles sont posées par `surah_list_screen.dart` à la construction, et remises
// à `null` quand il est démonté. Un `GlobalKey` gardé sur un widget disparu
// ferait pointer la main sur une position périmée -- pire qu'aucune cible,
// parce que ça DÉSIGNE quelque chose, et donc ça enseigne un mensonge.

/// La carte « prochaine prière + boussole Qibla », en haut de l'accueil.
GlobalKey? cleCartePriere;

/// Le bouton d'écoute de la PREMIÈRE sourate de la liste.
GlobalKey? cleBoutonEcoute;

/// Le signet de la barre du haut. `null` tant qu'aucun signet n'est posé --
/// le bouton n'existe alors pas (`SizedBox.shrink`), et l'étape qui le vise
/// s'affichera sans trou plutôt que d'éclairer le vide.
GlobalKey? cleSignet;

/// Un chapitre de découverte.
class ChapitreGuide {
  final String id;
  final String emoji;

  /// Fonctions et non chaînes : le titre doit suivre la langue courante, et ce
  /// catalogue est construit une fois pour toutes.
  final String Function(AppLocalizations) titre;
  final String Function(AppLocalizations) resume;

  /// Construit les étapes. Reçoit le `BuildContext` parce que plusieurs
  /// chapitres poussent de vrais écrans.
  final List<EtapeGuide> Function(BuildContext, AppLocalizations) etapes;

  const ChapitreGuide({
    required this.id,
    required this.emoji,
    required this.titre,
    required this.resume,
    required this.etapes,
  });
}

/// Ouvre un écran par-dessus l'application.
///
/// `rootNavigator: true` : la visite vit dans l'`Overlay` RACINE (cf.
/// `GuideHote`). Pousser sur un navigateur imbriqué placerait l'écran sous
/// elle dans un cas et au-dessus dans l'autre, selon l'onglet courant — le
/// genre de comportement qui ne se voit qu'une fois sur deux.
Future<void> _ouvrir(BuildContext context, Widget ecran) async {
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(builder: (_) => ecran));
}

Future<void> _onglet(int i) async {
  allerAOngletGuide?.call(i);
  // Laisser l'onglet se construire avant que l'étape suivante ne mesure sa
  // cible : mesurer trop tôt rendrait `null` et la main se poserait au centre.
  await Future<void>.delayed(const Duration(milliseconds: 260));
}

/// Les chapitres, dans l'ordre où on les propose.
///
/// Le tour d'ensemble d'abord : c'est lui qui se joue au premier lancement.
List<ChapitreGuide> get kChapitresGuide => [
      ChapitreGuide(
        id: 'global',
        emoji: '🗺️',
        titre: (t) => t.guideChapitreGlobalTitre,
        resume: (t) => t.guideChapitreGlobalResume,
        etapes: (context, t) => [
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.navQuran,
            texte: t.visiteCoranTexte,
            action: () => _onglet(0),
          ),
          EtapeGuide(
            cible: cleOngletDuas,
            titre: t.navDuas,
            texte: t.visiteDuasTexte,
            action: () => _onglet(1),
          ),
          EtapeGuide(
            cible: cleOngletCoach,
            titre: t.navCoach,
            texte: t.visiteCoachTexte,
            action: () => _onglet(2),
          ),
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.visiteFinTitre,
            texte: t.visiteFinTexte,
            action: () => _onglet(0),
          ),
        ],
      ),
      ChapitreGuide(
        id: 'prieres',
        emoji: '🕌',
        titre: (t) => t.guideChapitrePrieresTitre,
        resume: (t) => t.guideChapitrePrieresResume,
        etapes: (context, t) => [
          EtapeGuide(
            // Désormais la CARTE elle-même, plus l'onglet : l'étape parle de
            // l'heure de prière et de la boussole, elle doit donc les montrer.
            cible: cleCartePriere,
            titre: t.guideChapitrePrieresTitre,
            texte: t.guidePriereAccueilTexte,
            action: () => _onglet(0),
          ),
          EtapeGuide(
            titre: t.settingsQiblaTitle,
            texte: t.guideQiblaTexte,
            geste: GesteGuide.regarder,
            action: () => _ouvrir(context, const QiblaScreen()),
            pause: const Duration(milliseconds: 3400),
          ),
          EtapeGuide(
            titre: t.settingsPrayerTimesTitle,
            texte: t.guideHorairesTexte,
            geste: GesteGuide.regarder,
            action: () async {
              // On revient de la Qibla AVANT d'ouvrir les horaires : sans ça
              // les écrans s'empilent et le bouton retour en demande trois.
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              await _ouvrir(context, const PrayerTimesSettingsScreen());
            },
            pause: const Duration(milliseconds: 3400),
          ),
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.visiteFinTitre,
            texte: t.guidePriereFinTexte,
            action: () async {
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              await _onglet(0);
            },
          ),
        ],
      ),
      ChapitreGuide(
        id: 'invocations',
        emoji: '🤲',
        titre: (t) => t.navDuas,
        resume: (t) => t.guideChapitreDuasResume,
        etapes: (context, t) => [
          EtapeGuide(
            cible: cleOngletDuas,
            titre: t.navDuas,
            texte: t.guideDuasUniversTexte,
            action: () => _onglet(1),
          ),
          EtapeGuide(
            titre: t.guideDuasCollectionsTitre,
            texte: t.guideDuasCollectionsTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3200),
          ),
          EtapeGuide(
            titre: t.guideDuasAudioTitre,
            texte: t.guideDuasAudioTexte,
            geste: GesteGuide.regarder,
          ),
        ],
      ),
      ChapitreGuide(
        id: 'reglages',
        emoji: '⚙️',
        titre: (t) => t.settingsTitle,
        resume: (t) => t.guideChapitreReglagesResume,
        etapes: (context, t) => [
          EtapeGuide(
            titre: t.settingsLocaleTitle,
            texte: t.guideReglagesLangueTexte,
            geste: GesteGuide.regarder,
            action: () => _onglet(4),
          ),
          EtapeGuide(
            titre: t.settingsRiwayaTitle,
            texte: t.guideReglagesRiwayaTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            titre: t.settingsMushafScriptTitle,
            texte: t.guideReglagesEcritureTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            titre: t.guideReglagesViePriveeTitre,
            texte: t.guideReglagesViePriveeTexte,
            geste: GesteGuide.regarder,
            action: () => _ouvrir(context, const AboutScreen()),
            pause: const Duration(milliseconds: 3600),
          ),
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.visiteFinTitre,
            texte: t.guidePriereFinTexte,
            action: () async {
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              await _onglet(0);
            },
          ),
        ],
      ),
      ChapitreGuide(
        id: 'lecture',
        emoji: '📖',
        titre: (t) => t.guideChapitreLectureTitre,
        resume: (t) => t.guideChapitreLectureResume,
        etapes: (context, t) => [
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.guideChapitreLectureTitre,
            texte: t.guideLectureListeTexte,
            action: () => _onglet(0),
          ),
          EtapeGuide(
            cible: cleBoutonEcoute,
            titre: t.guideLectureEcouteTitre,
            texte: t.guideLectureEcouteTexte,
          ),
          EtapeGuide(
            titre: t.guideLectureDefilementTitre,
            texte: t.guideLectureDefilementTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            // `cleSignet` vaut `null` tant qu'aucun signet n'est posé : le
            // bouton n'existe alors pas dans l'arbre. L'étape s'affiche sans
            // trou de lumière, ce qui est le bon comportement -- montrer un
            // bouton absent serait pire que de l'expliquer.
            cible: cleSignet,
            titre: t.guideLectureSignetTitre,
            texte: t.guideLectureSignetTexte,
          ),
        ],
      ),
      ChapitreGuide(
        id: 'mushaf',
        emoji: '📜',
        titre: (t) => t.guideChapitreMushafTitre,
        resume: (t) => t.guideChapitreMushafResume,
        etapes: (context, t) => [
          EtapeGuide(
            titre: t.guideChapitreMushafTitre,
            texte: t.guideMushafOuvrirTexte,
            geste: GesteGuide.regarder,
            action: () => _ouvrir(context, const MushafOpeningScreen()),
            pause: const Duration(milliseconds: 3200),
          ),
          EtapeGuide(
            titre: t.guideMushafTournerTitre,
            texte: t.guideMushafTournerTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3400),
          ),
          EtapeGuide(
            titre: t.guideMushafEcritureTitre,
            texte: t.guideMushafEcritureTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3400),
          ),
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.visiteFinTitre,
            texte: t.guidePriereFinTexte,
            action: () async {
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              await _onglet(0);
            },
          ),
        ],
      ),
      ChapitreGuide(
        id: 'recitation',
        emoji: '🎙️',
        titre: (t) => t.guideChapitreRecitationTitre,
        resume: (t) => t.guideChapitreRecitationResume,
        etapes: (context, t) => [
          EtapeGuide(
            cible: cleOngletCoran,
            titre: t.guideChapitreRecitationTitre,
            texte: t.guideRecitationDepartTexte,
            action: () => _onglet(0),
          ),
          EtapeGuide(
            titre: t.guideRecitationCouleursTitre,
            texte: t.guideRecitationCouleursTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3600),
          ),
          EtapeGuide(
            titre: t.guideRecitationCorrectionTitre,
            texte: t.guideRecitationCorrectionTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3600),
          ),
          EtapeGuide(
            titre: t.guideRecitationMicroTitre,
            texte: t.guideRecitationMicroTexte,
            geste: GesteGuide.regarder,
            pause: const Duration(milliseconds: 3600),
          ),
        ],
      ),
      ChapitreGuide(
        id: 'demo',
        emoji: '▶️',
        titre: (t) => t.guideChapitreDemoTitre,
        resume: (t) => t.guideChapitreDemoResume,
        etapes: (context, t) => [
          EtapeGuide(
            titre: t.guideChapitreDemoTitre,
            texte: t.guideDemoTexte,
            geste: GesteGuide.regarder,
            // ⚠️ La demonstration est SCRIPTEE et le dit : elle n'ouvre ni le
            // micro ni le modele, et n'ecrit rien. Cf. l'en-tete de
            // `demo_recitation_screen.dart`, ou l'absence d'import EST la
            // garantie. C'est le seul chapitre qui montre la recitation sans
            // en declencher une -- et donc sans demander de permission.
            action: () => _ouvrir(context, const DemoRecitationScreen()),
            pause: const Duration(milliseconds: 3000),
          ),
        ],
      ),
      ChapitreGuide(
        id: 'coach',
        emoji: '🎓',
        titre: (t) => t.navCoach,
        resume: (t) => t.guideChapitreCoachResume,
        etapes: (context, t) => [
          EtapeGuide(
            cible: cleOngletCoach,
            titre: t.navCoach,
            texte: t.guideCoachPortionsTexte,
            action: () => _onglet(2),
          ),
          EtapeGuide(
            titre: t.guideCoachSerieTitre,
            texte: t.guideCoachSerieTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            titre: t.guideCoachMemoTitre,
            texte: t.guideCoachMemoTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            titre: t.guideCoachSessionsTitre,
            texte: t.guideCoachSessionsTexte,
            geste: GesteGuide.regarder,
          ),
        ],
      ),
      ChapitreGuide(
        id: 'audio',
        emoji: '🔊',
        titre: (t) => t.guideChapitreAudioTitre,
        resume: (t) => t.guideChapitreAudioResume,
        etapes: (context, t) => [
          EtapeGuide(
            titre: t.guideAudioReciteurTitre,
            texte: t.guideAudioReciteurTexte,
            geste: GesteGuide.regarder,
            action: () => _onglet(4),
          ),
          EtapeGuide(
            titre: t.guideAudioHorsLigneTitre,
            texte: t.guideAudioHorsLigneTexte,
            geste: GesteGuide.regarder,
          ),
          EtapeGuide(
            titre: t.guideAudioNotifTitre,
            texte: t.guideAudioNotifTexte,
            geste: GesteGuide.regarder,
          ),
        ],
      ),
    ];
