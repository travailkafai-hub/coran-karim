// Onglet COACH — hub de la mémorisation (REFONTE_IHM.md §11).
//
// Remplace l'ancien `coach_ai_screen.dart`, qui n'était qu'un journal
// d'erreurs à plat (liste toutes sourates mélangées). Demande utilisateur
// 2026-07-20 : « tout ce qui est en lien avec la mémorisation il faut le
// mettre dans coach [...] il ne faut pas faire juste une copie-coller ».
//
// 4 zones, dans l'ordre de priorité d'usage réel (pas esthétique) :
//   A. Reprendre        — relancer la dernière session (action n°1 au quotidien)
//   B. Mémoriser        — ayah par ayah, lance CoachScreen (3 étapes existantes)
//   C. Réciter          — récitation globale + TOUS les réglages, modifiables ici
//   D. Mes erreurs      — par sourate, avec lien vers la carte mentale
//
// Principe : ce hub ORCHESTRE des écrans existants (CoachScreen,
// KaraokeRecitationScreen, TajwidRulesScreen...), il ne les réimplémente pas.

// `dart:math` retiré le 2026-08-14 : son seul usage était le plancher
// `math.max(quartsFaits, avancement)` de la barre de progression, supprimé
// avec le compteur biaisé qu'il protégeait (cf. le bloc d'avancement).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// `show NumberFormat` et pas l'import complet : `package:intl` exporte aussi
// un `TextDirection`, qui masquerait celui de Flutter et casserait les
// `TextDirection.rtl/ltr` déjà utilisés plus bas dans ce fichier.
import 'package:intl/intl.dart' show NumberFormat;

import '../l10n/app_localizations.dart';
import '../models/recitation_state.dart'
    show RecitationErrorKind, recitationErrorKindLabel;
import '../models/verse.dart';
import '../models/objectif_coach.dart';
import '../providers/app_settings_provider.dart' show objectifCoachProvider;
import '../providers/error_review_provider.dart';
import '../providers/last_coach_verse_provider.dart';
import '../providers/mind_map_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart' show JourActif;
import '../theme/app_theme.dart';
import 'coach_sessions.dart';
import '../widgets/coach_explanation_sheet.dart';
import '../widgets/tajwid_help_sheet.dart' show kTajwidRuleInfo;
import 'coach_screen.dart';
import 'karaoke_recitation_screen.dart';
import 'memorization_ayah_picker_screen.dart';
import 'memorization_game_screen.dart';
import 'mind_map_screen.dart';
import 'surah_picker_screen.dart';

/// Borne le lot initial de récitation à la PAGE du premier verset, au lieu
/// de charger toute la sourate (correctif 2026-07-25, constat utilisateur :
/// « ne pas charger toute la sourate, ça doit être glissant page avant et
/// page après, ça alourdit le traitement »).
///
/// Mesuré : depuis ce point d'entrée, Al-Baqara arrivait entière —
/// `cible d'alignement : 6121 mots`. Coût réel côté Dart et UI, pas côté
/// modèle (`maxAlignWords = 80` borne déjà la DP) : `_onAligned` recopie
/// `state.words` à CHAQUE payload (~12 fois/s), soit 6121 éléments par
/// copie, et la tokenisation initiale enregistrait 1990 replis gloutons
/// (`hits=4113 misses=1987`).
///
/// La suite est chargée à la demande par `_maybeExtendNextPage` /
/// `extendAlignmentTarget` (mécanisme déjà en place, `_kExtendLookaheadWords`),
/// donc la récitation continue sans coupure au-delà de la page. Même borne
/// que celle déjà appliquée depuis le Mushaf (`_fragmentFromActive`) — ce
/// point d'entrée était le seul à ne pas la respecter.
///
/// `pageNumber` est nullable côté API : à défaut de pagination connue, on
/// renvoie la liste inchangée (comportement d'avant, jamais de perte).
List<Verse> _firstPageOf(List<Verse> verses) {
  if (verses.isEmpty) return verses;
  final page = verses.first.pageNumber;
  if (page == null) return verses;
  final samePage = verses.takeWhile((v) => v.pageNumber == page).toList();
  return samePage.isEmpty ? verses : samePage;
}


class CoachHubScreen extends ConsumerWidget {
  const CoachHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Text(AppLocalizations.of(context)!.coachHubTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
      ),
      // ── LE COACH N'EST PLUS UN LANCEUR (2026-08-06) ────────────────────
      //
      // Demande utilisateur : « comme maintenant la récitation, le jeu et la
      // mémorisation ça se fait depuis l'écran du Mushaf, je veux que le
      // coach se concentre sur les erreurs [...] pour se concentrer sur tout
      // ce qui est résultat ».
      //
      // Les quatre sections de lancement (`_ResumeSection`,
      // `_MemorizeSection`, `_GameSection`, `_ReciteSection`) faisaient
      // doublon avec la bulle du Mushaf, qui propose les mêmes actions AU
      // VERSET PRÈS -- donc mieux placée qu'un bouton générique ici. Elles
      // sont CONSERVÉES plus bas dans ce fichier, intactes : elles portent
      // leurs propres décisions (choix de préréglage, garde-fous de reprise)
      // et redeviendront utiles si le Coach reprend un rôle de lancement.
      //
      // Ce qui reste répond à une seule question : « qu'est-ce que j'ai fait,
      // et qu'est-ce qui a coincé ? » — session par session, avec la voix.
      //
      // ── LE CUMUL PAR SOURATE EST RETIRÉ (2026-08-09) ─────────────────────
      // Demande utilisateur, après le retour à la vue par session (cfea1f3) :
      // « du coup, supprimer le pavé Mes erreurs ». `_ErrorsSection` faisait
      // doublon avec `SessionsSection` -- la carte mentale et l'entraînement
      // qu'elle seule proposait vivent maintenant DANS la vue par session
      // (`coach_sessions.dart`, commit 5d63bb3). Classes conservées intactes
      // plus bas (convention projet), simplement non montées.
      // ── « MES RÉCITATIONS » (SessionsSection) RETIRÉE DE L'ÉCRAN
      //    (2026-08-14, décision utilisateur) ───────────────────────────────
      //
      // Constat de l'utilisateur : « je me demande l'utilité de les garder,
      // j'ai l'impression que c'est en doublon avec mémorisation ». Vérifié
      // dans le SCHÉMA, pas supposé : `portion_words` porte TOUTES les
      // colonnes de `session_words` (verdict, mot attendu, mot entendu, type
      // d'erreur, audio, position) et trois de plus -- `audio_expires_at`,
      // `deja_rate`, et surtout la PERMANENCE (les sessions sont purgées à
      // 7 jours). La vue par portion est donc strictement plus riche.
      //
      // Ce que les sessions apportaient en propre -- « ce que j'ai fait le
      // jour J » -- est désormais porté par le tableau de bord, qui lit
      // `jours_actifs` (série, points, objectif atteint, 7 derniers jours).
      //
      // ⚠️ SEUL L'AFFICHAGE DISPARAÎT. La table `sessions` reste écrite : son
      // ouverture/fermeture est ce qui DÉCLENCHE la comptabilisation Coach
      // (cf. `_cloturerArchive` côté karaoké, qui sort immédiatement si
      // `sessionCourante == null`). `SessionsSection` est conservée intacte
      // dans `coach_sessions.dart`, simplement non montée -- convention
      // projet, et remontage possible en une ligne.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          _ObjectifSection(),
          SizedBox(height: 4),
          PortionsSection(),
        ],
      ),
    );
  }
}

// ── OBJECTIF & SÉRIE (2026-08-13) ───────────────────────────────────────────
//
// Cf. `PLAN_COACH.md`. Répond à la question que le hub ne posait pas encore :
// « où dois-je en être, et qu'est-ce que je fais aujourd'hui ? » — au-dessus
// de la mémorisation par sourate et des récitations, qui répondent à « qu'est-
// ce que j'ai fait ».
//
// État vide (aucun objectif fixé) volontairement DIFFÉRENT de l'état actif :
// on ne montre jamais "0 %" ou "série : 0" tant que l'utilisateur n'a rien
// engagé — ce serait un échec affiché avant même d'avoir commencé.
/// Nombre de mots d'un quart de Hizb, EN MOYENNE : le Coran compte ~77 430
/// mots pour 240 quarts (60 Hizb × 4). Sert UNIQUEMENT à donner sa finesse à
/// la barre de progression entre deux quarts validés (cf. `avancement` dans
/// `_ObjectifSection`) -- jamais à afficher un nombre de mots, et jamais à
/// décider qu'un quart est acquis (ça, c'est le badge de portion, qui exige
/// une couverture réelle à 100 %).
// ⛔ RETIRÉE LE JOUR MÊME DE SON AJOUT (2026-08-14), garder la trace :
//     const double _kMotsParQuart = 77430 / 240;  // ~322,6 mots par quart
// Elle servait à convertir `jours_actifs.mots_recites` (cumulé) en fraction
// de quart pour la barre de progression. Le défaut n'est pas la constante,
// c'est la SOURCE : `mots_recites` est additif à chaque session, donc quinze
// récitations d'An-Nasr (23 mots) valaient 345 mots -- « plus d'un quart »
// affiché sans un seul mot nouveau mémorisé. La barre lit désormais
// `portions` (dédupliqué par `UNIQUE(portion_id, ayah, mot)`), où la part
// acquise d'un quart est `wordsGreen/wordsTotal`. Ne pas réintroduire une
// conversion mots→quart sur un compteur cumulatif.

/// Partagé entre `_ObjectifSection` et `_ReglageObjectifSheetState` -- un seul
/// endroit qui sait traduire une [PeriodeObjectif] en texte.
///
/// La période n'est plus un CHOIX depuis le 2026-08-14 (l'objectif se saisit
/// en années pour tout le Coran) : elle ne sert plus qu'à nommer les horizons
/// du rythme dérivé.
String _libellePeriodeObjectif(AppLocalizations t, PeriodeObjectif p) =>
    switch (p) {
      PeriodeObjectif.jour => t.coachObjectifPeriodeJour,
      PeriodeObjectif.semaine => t.coachObjectifPeriodeSemaine,
      PeriodeObjectif.mois => t.coachObjectifPeriodeMois,
    };

/// Un rythme en quarts, écrit comme on le lit à voix haute : « 0,2 », « 1,5 »,
/// « 20 ». Une décimale sous 10, aucune au-dessus -- « 19,7 quarts par mois »
/// donne une précision que le chiffre n'a pas (il dépend du reste à mémoriser,
/// qui bouge à chaque récitation).
///
/// Passe par [NumberFormat] et non par `toStringAsFixed` : le séparateur
/// décimal est une virgule en français, un point en anglais, et l'arabe a ses
/// propres chiffres. Écrire « 0.2 » à un lecteur francophone, ou des chiffres
/// latins dans une interface arabe, se remarque immédiatement.
String _formatRythme(BuildContext context, double v) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final f = v < 10
      ? NumberFormat('0.#', locale)
      : NumberFormat.decimalPattern(locale);
  return f.format(v);
}

class _ObjectifSection extends ConsumerWidget {
  const _ObjectifSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final objectif = ref.watch(objectifCoachProvider);
    final serie = ref.watch(serieProvider);
    final jours = ref.watch(derniersJoursProvider);
    // ⛔ N'ÉCOUTE PLUS `portionsProvider` (2026-08-14, second correctif) :
    //      final portions = ref.watch(portionsProvider);
    // C'était la source de l'avancement, sommée en fractions de portion. Une
    // sourate courte complète y valait un quart entier -- cf. le bloc de
    // calcul plus bas et `quartsAcquisDuMoisProvider` pour la mesure qui l'a
    // fait tomber. Cette liste reste utilisée par « Mémorisation par sourate »,
    // simplement plus par l'objectif.
    //
    // Base de calcul du rythme : ce qui reste à mémoriser (décision
    // utilisateur 2026-08-14), en mots DISTINCTS de tout le Coran -- sans le
    // plafond de 60 lignes d'affichage de `portionsProvider`.
    final quartsAcquis = ref.watch(quartsAcquisProvider);
    final quartsMois = ref.watch(quartsAcquisDuMoisProvider);
    final quartsAnnee = ref.watch(quartsAcquisDeLAnneeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(t.coachObjectifTitle,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                )),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.coachObjectifSheetTitle,
              icon: const Icon(Icons.tune_rounded,
                  size: 18, color: AppColors.green800),
              onPressed: () => _ouvrirReglageObjectif(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!objectif.actif)
          _EtatVideObjectif(onTap: () => _ouvrirReglageObjectif(context, ref))
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cream300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── L'OBJECTIF EN TOUTES LETTRES, EN PREMIER (2026-08-14) ────
                //
                // Constat utilisateur, capture d'écran à l'appui : « je ne
                // comprends pas la présentation de mon objectif, c'est mal
                // fait ». La carte n'affichait JAMAIS ce que l'utilisateur
                // avait réglé -- seulement des chiffres DÉRIVÉS (série,
                // progression). Or la première question d'un utilisateur qui
                // ouvre cette carte est « c'est quoi, mon objectif ? », pas
                // « où en est mon calcul ». Cette ligne répond à ça en un coup
                // d'œil, avant tout le reste.
                //
                // Depuis la refonte du même jour, elle dit aussi le BUT et non
                // plus une cadence : « Tout le Coran en 3 ans » se comprend
                // sans calcul, là où « 4 quarts par semaine » ne disait pas
                // vers quoi il menait.
                Row(
                  children: [
                    const Icon(Icons.flag_rounded,
                        color: AppColors.green800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.coachObjectifAnneesLabel(objectif.annees),
                            style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink),
                          ),
                          // ── LE TEMPS QUI RESTE (2026-08-14) ─────────────
                          // Sans cette ligne, dater l'échéance ne servirait à
                          // rien : le titre dirait « en 4 ans » pour toujours,
                          // et l'utilisateur n'aurait aucun moyen de voir que
                          // l'échéance approche -- alors que c'est exactement
                          // ce qu'il a demandé (« au départ 4 ans, dans
                          // 6 mois c'est 3 ans et 6 mois »).
                          if (objectif.actif && objectif.echeance != null)
                            Text(
                              _resteEnClair(t, objectif),
                              style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: objectif.depassee()
                                      ? AppColors.rythmeARattraper
                                      : AppColors.inkLight),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Le rythme dépend du RESTE à mémoriser : tant qu'il n'est pas
                // connu, on n'affiche rien plutôt qu'un chiffre calculé sur
                // « 0 quart acquis » qui se corrigerait sous les yeux de
                // l'utilisateur une fraction de seconde plus tard.
                quartsAcquis.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (e, _) => Text('$e',
                      style: GoogleFonts.manrope(
                          fontSize: 11, color: AppColors.inkLight)),
                  data: (acquis) {
                    final rythme = objectif.rythmePour(acquis);
                    // Avancement du mois, dans la MÊME unité que `acquis` --
                    // cf. `quartsAcquisDuMoisProvider` pour pourquoi ce n'est
                    // plus une somme de fractions de portions.
                    final quartsDuMois = quartsMois.maybeWhen(
                      data: (v) => v,
                      orElse: () => 0.0,
                    );
                    final quartsDeLAnnee = quartsAnnee.maybeWhen(
                      data: (v) => v,
                      orElse: () => 0.0,
                    );
                    return jours.when(
                  data: (l) {
                    // ── PROGRESSION SUR LE MOIS (2026-08-14) ─────────────────
                    //
                    // HISTORIQUE, à ne pas refaire : la barre a d'abord été
                    // ramenée à la SEMAINE quelle que soit la période saisie --
                    // « 1 quart par mois » y devenait « 0,2 quart par
                    // semaine », un nombre que personne ne pense naturellement
                    // (capture d'écran utilisateur : « 0 sur 0.2 quart(s) »).
                    // Elle a ensuite suivi la période de l'objectif, qui
                    // n'existe plus depuis que l'objectif est une durée.
                    //
                    // La fenêtre est donc FIXÉE AU MOIS (décision utilisateur
                    // 2026-08-14). Ce n'est pas un choix esthétique : c'est le
                    // seul horizon où la cible tombe sur un entier lisible sur
                    // toute la plage du curseur -- 20 quarts à 1 an, 3 à 6 ans.
                    // Sur la semaine, l'échéance la plus longue redonnerait
                    // « 0,8 quart », c'est-à-dire exactement le défaut qu'on
                    // vient de corriger.
                    const fenetre = 30;
                    final debut =
                        DateTime.now().subtract(const Duration(days: fenetre));
                    final periodeCourante =
                        l.where((j) => j.jour.isAfter(debut)).toList();
                    final cible = rythme.cibleDuMois;
                    // ── L'AVANCEMENT EST CONTINU, PAS PAR PALIERS ────────────
                    //
                    // Demande utilisateur (2026-08-14) : « que l'avancement
                    // soit plus encourageant, ça va travailler sur les mots
                    // appris sur les mots du Hizb SANS que ce soit visible que
                    // c'est par mots ».
                    //
                    // Un quart ne se valide qu'une fois récité EN ENTIER : un
                    // utilisateur à 80 % d'un quart voyait 0 %, et rien ne
                    // bougeait tant que le quart n'était pas bouclé -- le
                    // contraire d'un encouragement. La barre lit donc les mots
                    // ACQUIS, convertis en fraction de quart. Aucun compte de
                    // mots n'est affiché : il ne sert qu'à la finesse.
                    //
                    // ── LA SOURCE A CHANGÉ LE MÊME JOUR, ET C'EST IMPORTANT ──
                    // Première version : `jours_actifs.mots_recites` cumulé
                    // sur la période. DÉFAUT : ce compteur est ADDITIF à
                    // chaque session, donc réciter quinze fois An-Nasr
                    // (23 mots) valait 345 mots, soit « plus d'un quart » --
                    // 100 % affiché sans qu'un seul mot nouveau ait été
                    // mémorisé. Un pourcentage d'avancement qui monte en
                    // répétant le même passage ne mesure rien.
                    //
                    // Deuxième source, corrigée le même jour : `portions`,
                    // dédupliquée par construction, en sommant
                    // `wordsGreen/wordsTotal` PLAFONNÉ À 1 PAR PORTION.
                    //
                    // ── ET C'ÉTAIT ENCORE FAUX (2026-08-14, mesuré) ──────────
                    // Une portion « sourate entière » courte valait alors un
                    // quart PLEIN : Al-Kawthar (10 mots) comptait autant qu'un
                    // vrai quart de Hizb (~322 mots). Sur le téléphone de
                    // l'utilisateur, la barre totalisait 12,37 quarts pour
                    // 272 mots acquis, qui en valent 0,84 -- « 100 % ce
                    // mois-ci » s'affichait sous « il te reste 239 quarts sur
                    // 240 ». Deux chiffres contradictoires sur la même carte.
                    //
                    // La barre lit donc la MÊME grandeur que le reste à
                    // mémoriser (`quartsAcquisDuMoisProvider`) : des mots
                    // acquis distincts convertis en quarts. Les deux ne peuvent
                    // plus diverger, ils sortent de la même requête.
                    //
                    // ⛔ Le plancher `jours_actifs.quarts_valides` a sauté avec
                    // (il valait `math.max(quartsFaits, avancement)`) : ce
                    // compteur s'incrémente sur `PortionResume.badge`, donc il
                    // portait exactement le même biais.
                    final avancement = quartsDuMois;
                    final restant = (cible - avancement).ceil().clamp(0, cible);
                    // ── MATURITÉ DU SUIVI, POUR NE PAS PUNIR UN DÉBUTANT ─────
                    //
                    // Les fenêtres sont GLISSANTES (30 et 365 jours) : leur
                    // cible est donc due en permanence, et quelqu'un qui a
                    // installé l'app il y a trois jours serait « très en
                    // retard » sur un mois qu'il n'a pas vécu. On rapporte
                    // l'attendu au temps réellement suivi -- le plus ancien
                    // jour actif connu -- de sorte qu'un débutant régulier est
                    // vert, et qu'un habitué qui décroche devient rouge.
                    //
                    // `l` est trié du plus récent au plus ancien
                    // (`derniersJours`, ORDER BY jour DESC), donc `l.last` est
                    // le premier jour où le Coach a vu quelque chose.
                    final joursSuivis = l.isEmpty
                        ? 0
                        : DateTime.now().difference(l.last.jour).inDays + 1;
                    final maturiteMois =
                        (joursSuivis / fenetre).clamp(0.0, 1.0);
                    final maturiteAnnee = (joursSuivis / 365).clamp(0.0, 1.0);
                    final etatDuMois = EtatRythme.depuis(
                      fait: avancement,
                      attendu: cible * maturiteMois,
                    );
                    final etatDeLAnnee = EtatRythme.depuis(
                      fait: quartsDeLAnnee,
                      attendu: rythme.cibleDeLAnnee * maturiteAnnee,
                    );
                    // ── LES TROIS REPÈRES DE PROGRESSION LINÉAIRE ───────────
                    //
                    // Chacun répond à « où devrais-je en être AUJOURD'HUI »,
                    // mais sur trois échelles de temps qui n'ont pas la même
                    // nature -- c'est pour ça qu'ils ne se calculent pas de la
                    // même façon :
                    //
                    //  - MOIS et ANNÉE : fenêtres GLISSANTES. Leur cible est
                    //    due en permanence, donc le repère est au BOUT de la
                    //    barre (100 %) dès que le suivi a l'âge de la fenêtre.
                    //    Il ne recule que pour un débutant, à qui l'on ne
                    //    réclame pas un mois qu'il n'a pas vécu -- même
                    //    maturité que l'état coloré juste au-dessus, pour que
                    //    le trait et la couleur ne puissent jamais se
                    //    contredire.
                    //
                    //  - CORAN ENTIER : là, le repère est enfin ce qu'on
                    //    attend vraiment d'une progression linéaire, la part
                    //    du TEMPS d'échéance déjà dû. Il n'existe que depuis
                    //    que l'objectif est daté (2026-08-14) : sans date de
                    //    pose, « la moitié du chemin » n'avait aucun sens.
                    //    `null` si aucun objectif n'est fixé — on ne dessine
                    //    pas un repère sur une échéance inexistante.
                    //    Il vise la FIN de la journée en cours, jamais son
                    //    début (cf. `partDueALaFinDuJour`) : à zéro, il ne
                    //    demanderait rien le premier jour.
                    final o = objectif;
                    final repereCoran = (o.actif && o.debut != null)
                        ? o.partDueALaFinDuJour()
                        : null;
                    final pointsPeriode =
                        periodeCourante.fold<int>(0, (a, j) => a + j.points);
                    // ⛔ Plus lu depuis le retrait de l'état du jour
                    // (2026-08-14, cf. le bloc des tuiles). La donnée existe
                    // toujours en base (`jours_actifs.objectif_atteint`) et
                    // reste la base de la SÉRIE : c'est seulement son
                    // affichage isolé qui a disparu.
                    //   final cleAujourdhui = _MiniEvolution._cle(DateTime.now());
                    //   final objectifDuJourAtteint = l.any((j) =>
                    //       _MiniEvolution._cle(j.jour) == cleAujourdhui &&
                    //       j.objectifAtteint);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── LE DÉTAIL DU RYTHME N'EST PAS ICI (2026-08-14) ───
                        // Demande utilisateur : « je veux pas afficher le
                        // détail sur cet écran, il est quand on choisit
                        // l'objectif ». Le reste à mémoriser et le rythme par
                        // jour/semaine/mois vivent donc dans la FEUILLE DE
                        // RÉGLAGE, là où ils servent à décider. Cette carte
                        // répond à « où j'en suis », pas à « comment le calcul
                        // est fait ».
                        // ── DEUX TUILES, ET RIEN D'AUTRE (2026-08-14) ────────
                        //
                        // L'état du jour (« En cours / Atteint ») a été retiré
                        // en DEUX temps, et le second temps est une correction
                        // d'erreur :
                        //   1. il occupait une tuile entière -- « Aujourd'hui
                        //      en cours à côté de série, je ne comprends pas
                        //      l'utilité, il se peut à supprimer » ;
                        //   2. il a d'abord été FUSIONNÉ dans la tuile Série au
                        //      lieu d'être supprimé. Deux défauts d'un coup :
                        //      l'information que l'utilisateur ne voulait pas
                        //      était toujours là, et comme elle ne concernait
                        //      qu'UNE des deux tuiles, les deux rectangles
                        //      n'avaient plus la même hauteur (« c'est moche »,
                        //      capture à l'appui). Supprimé pour de bon.
                        //
                        // Leçon à ne pas repayer : quand l'utilisateur dit ne
                        // pas voir l'utilité d'un élément, on le RETIRE. Le
                        // garder sous une autre forme, c'est discuter sa
                        // demande, et ça se paie en plus par un défaut de mise
                        // en page. Deux tuiles au contenu identique, donc de
                        // hauteur identique par construction.
                        //
                        // Code retiré, gardé pour mémoire :
                        //   _TuileStat(icone: objectifDuJourAtteint
                        //       ? Icons.check_circle_rounded
                        //       : Icons.radio_button_unchecked_rounded,
                        //     libelle: t.coachDashTodayLabel,
                        //     valeur: objectifDuJourAtteint
                        //       ? t.coachDashTodayDone : t.coachDashTodayPending)
                        Row(
                          children: [
                            Expanded(
                              child: _TuileStat(
                                // Croissant, pas de flamme (2026-08-13) : « le
                                // feu et le Coran, ce n'est pas le bon
                                // univers ». Cohérent aussi avec le rappel du
                                // soir calé sur le Maghrib -- une série de
                                // « jours » est ici une série de nuits.
                                icone: Icons.nightlight_round,
                                couleurIcone: AppColors.brass,
                                libelle: t.coachDashStreakLabel,
                                valeur: serie.maybeWhen(
                                    data: (n) => t.coachDashStreakValue(n),
                                    orElse: () => '—'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TuileStat(
                                // Les points existaient déjà (barème d'effort
                                // et de répétition, indépendant des erreurs --
                                // cf. `_comptabiliserPourCoach`) mais n'étaient
                                // affichés NULLE PART. C'est la « récompense »
                                // demandée : montrer ce qui est déjà gagné, pas
                                // inventer un système de badges de jeu (refus
                                // explicite, cf. PLAN_COACH.md).
                                icone: Icons.workspace_premium_rounded,
                                couleurIcone: AppColors.brass,
                                libelle: t.coachDashPointsLabel,
                                valeur: '$pointsPeriode',
                              ),
                            ),
                          ],
                        ),
                        // Filets fins entre les trois zones de la carte
                        // (état du jour · progression · évolution) : sans eux,
                        // tout flottait dans le même bloc et rien ne disait où
                        // une information s'arrêtait.
                        const _FiletCarte(),
                        // ── UN SEUL HORIZON VISIBLE (2026-08-14) ─────────────
                        //
                        // Les trois barres ont d'abord été affichées à plat.
                        // Retour utilisateur immédiat : « la progression à
                        // l'année et au Coran, pas affichées au premier coup,
                        // ça doit être caché, que la progression du mois ».
                        //
                        // Le mois est le seul horizon SUR LEQUEL ON PEUT ENCORE
                        // AGIR aujourd'hui ; l'année et le Coran entier
                        // répondent à une question qu'on ne se pose pas tous
                        // les jours. Les empiler les mettait au même rang et
                        // noyait celui qui appelle une action.
                        _BarreProgression(
                          titre:
                              t.coachDashProgressTitle(t.coachObjectifPeriodeCeMois),
                          fait: avancement,
                          cible: cible.toDouble(),
                          etat: etatDuMois,
                          principale: true,
                          sousTitre: t.coachDashProgressRemaining(restant),
                          repereLineaire: maturiteMois,
                        ),
                        _BlocRepliable(
                          titre: t.coachDashProgressMoreHorizons,
                          enfants: [
                            _BarreProgression(
                              titre: t.coachDashProgressTitle(
                                  t.coachObjectifPeriodeCetteAnnee),
                              fait: quartsDeLAnnee,
                              cible: rythme.cibleDeLAnnee.toDouble(),
                              etat: etatDeLAnnee,
                              repereLineaire: maturiteAnnee,
                            ),
                            const SizedBox(height: 14),
                            // Le Coran entier n'a PAS d'état de rythme : c'est
                            // un cumul, pas une échéance à tenir. Le colorer en
                            // « à rattraper » parce qu'on en est à 0,4 %
                            // n'aurait aucun sens -- personne n'est en retard
                            // sur le Coran.
                            _BarreProgression(
                              titre: t.coachDashProgressTitle(
                                  t.coachObjectifPeriodeCoranEntier),
                              fait: acquis,
                              cible: ObjectifCoach.quartsDuCoran.toDouble(),
                              etat: null,
                              repereLineaire: repereCoran,
                            ),
                          ],
                        ),
                        const _FiletCarte(),
                        Text(t.coachObjectifMiniEvolutionCaption,
                            style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkLight)),
                        const SizedBox(height: 8),
                        _MiniEvolution(jours: l, libelleAujourdhui: t.coachObjectifToday),
                        // ── BOUTON « RÉCITER » RETIRÉ DE LA CARTE ────────────
                        //
                        // Ajouté le 2026-08-13 (« un accès direct à la
                        // récitation depuis l'objectif, sans forcer que ce soit
                        // le début du Coran »), retiré le 2026-08-14 : « enlève
                        // aussi Réciter, je ne l'utilise pas ». L'accès reste
                        // entier ailleurs dans le hub (`_ReciteSection` et le
                        // sélecteur de sourate), il faisait double emploi ici.
                        //
                        // Code retiré, gardé pour mémoire -- si l'accès direct
                        // revient un jour, c'est ce bloc, et surtout sa règle :
                        // l'objectif dit COMBIEN progresser, jamais PAR OÙ
                        // commencer (d'où le sélecteur libre, pas une cible
                        // imposée) :
                        //   OutlinedButton.icon(
                        //     onPressed: … SurahPickerScreen(
                        //       title: t.coachHubPickerReciteTitle,
                        //       onPicked: (surah, verses) => …
                        //           KaraokeRecitationScreen(
                        //               verses: _firstPageOf(verses))),
                        //     icon: Icon(Icons.menu_book_rounded), …)
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (e, _) => Text('$e',
                      style: GoogleFonts.manrope(
                          fontSize: 11, color: AppColors.inkLight)),
                    );
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  void _ouvrirReglageObjectif(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReglageObjectifSheet(),
    );
  }
}

/// « Il reste 3 ans et 6 mois » — le décompte, en années et mois pleins.
///
/// Volontairement PAS de jours au-delà d'un mois : un objectif de plusieurs
/// années affiché à la journée près donnerait un chiffre qui change tous les
/// jours sans jamais rien apprendre à l'utilisateur. Sous un mois, en
/// revanche, le jour compte vraiment -- c'est là que l'échéance se joue.
String _resteEnClair(AppLocalizations t, ObjectifCoach objectif) {
  if (objectif.depassee()) return t.coachObjectifEcheanceDepassee;
  final jours = objectif.joursRestants();
  final annees = jours ~/ 365;
  final mois = (jours % 365) ~/ 30;
  if (annees > 0) return t.coachObjectifResteAnneesMois(annees, mois);
  if (mois > 0) return t.coachObjectifResteMois(mois);
  return t.coachObjectifResteJours(jours);
}

/// Filet de séparation entre deux zones d'une même carte. Volontairement très
/// pâle : il doit se sentir plus qu'il ne se voit — une carte reste une carte,
/// pas trois cartes collées.
class _FiletCarte extends StatelessWidget {
  const _FiletCarte();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Container(height: 1, color: AppColors.cream200),
      );
}

/// Un repli discret : une ligne cliquable, et ce qu'elle cache.
///
/// Replié par défaut, à chaque ouverture de l'écran (état local, jamais
/// persisté) : ce qui est caché ici l'est parce qu'on ne se le demande PAS tous
/// les jours -- le rouvrir automatiquement parce qu'on l'a consulté une fois
/// remettrait au premier plan ce que l'utilisateur a demandé d'en retirer.
class _BlocRepliable extends StatefulWidget {
  final String titre;
  final List<Widget> enfants;

  const _BlocRepliable({required this.titre, required this.enfants});

  @override
  State<_BlocRepliable> createState() => _BlocRepliableState();
}

class _BlocRepliableState extends State<_BlocRepliable> {
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _ouvert = !_ouvert),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Text(widget.titre,
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: AppColors.green800)),
                const SizedBox(width: 2),
                Icon(
                    _ouvert
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.green800),
              ],
            ),
          ),
        ),
        if (_ouvert) ...[
          const SizedBox(height: 4),
          ...widget.enfants,
        ],
      ],
    );
  }
}

/// Une progression sur un horizon (mois, année, Coran entier).
///
/// ── LA COULEUR PORTE UN SENS, ET ELLE NE LE PORTE PAS SEULE ───────────────
///
/// Demande utilisateur (2026-08-14) : « je veux que la couleur ait un sens :
/// vert je suis dans le rythme, orange ça dérape un peu, rouge il faut que je
/// progresse ». Chaque couleur est donc doublée d'un LIBELLÉ écrit -- une
/// information qui ne tiendrait qu'à la teinte serait perdue pour un
/// utilisateur daltonien, et l'app n'a pas d'autre canal pour la redire.
///
/// [etat] à null : horizon SANS échéance (le Coran entier). La barre garde
/// alors la couleur d'identité et n'affiche aucun jugement.
class _BarreProgression extends StatelessWidget {
  final String titre;
  final double fait;
  final double cible;
  final EtatRythme? etat;
  final bool principale;
  final String? sousTitre;

  /// Où l'on DEVRAIT en être si la progression était linéaire, en fraction de
  /// la barre (0..1). `null` = pas de repère (aucune échéance connue).
  ///
  /// Demande utilisateur 2026-08-14 : « rajouter des pointeurs qui
  /// correspondent à la progression linéaire sur les trois ».
  ///
  /// C'est l'information qui manquait pour LIRE la barre : 18 % ne dit rien
  /// tout seul -- 18 % au bout d'un mois sur quatre ans est une avance, au
  /// bout de trois ans un retard. Le repère rend l'écart visible d'un coup
  /// d'œil, là où la pastille de couleur ne donnait qu'un verdict sans
  /// montrer de combien.
  final double? repereLineaire;

  const _BarreProgression({
    required this.titre,
    required this.fait,
    required this.cible,
    required this.etat,
    this.principale = false,
    this.sousTitre,
    this.repereLineaire,
  });

  static Color couleurDe(EtatRythme? e) => switch (e) {
        EtatRythme.tenu => AppColors.rythmeTenu,
        EtatRythme.derape => AppColors.rythmeDerape,
        EtatRythme.aRattraper => AppColors.rythmeARattraper,
        null => AppColors.green700,
      };

  static String libelleDe(AppLocalizations t, EtatRythme e) => switch (e) {
        EtatRythme.tenu => t.coachRythmeTenu,
        EtatRythme.derape => t.coachRythmeDerape,
        EtatRythme.aRattraper => t.coachRythmeARattraper,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final ratio = cible <= 0 ? 0.0 : (fait / cible).clamp(0.0, 1.0);
    final couleur = couleurDe(etat);
    // Une décimale sous 10 % : « 0 % » pour 0,4 % du Coran effacerait un
    // travail réel, et découragerait précisément là où la progression est la
    // plus lente à se voir.
    final pct = ratio * 100;
    final pourcent = pct > 0 && pct < 10
        ? _formatRythme(context, pct)
        : pct.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(titre,
                  style: GoogleFonts.manrope(
                      fontSize: principale ? 11 : 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkLight)),
            ),
            Text('$pourcent %',
                style: GoogleFonts.manrope(
                    fontSize: principale ? 22 : 15,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: couleur)),
          ],
        ),
        SizedBox(height: principale ? 8 : 5),
        // Le repère se pose PAR-DESSUS la barre, dans un Stack : il doit rester
        // lisible quand la progression le dépasse (barre pleine sous le trait)
        // comme quand elle est loin derrière (trait sur le fond crème). D'où
        // une couleur sombre unique plutôt qu'un contraste calculé.
        LayoutBuilder(
          builder: (context, contraintes) {
            final hauteur = principale ? 10.0 : 6.0;
            final barre = ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: hauteur,
                backgroundColor: AppColors.cream200,
                color: couleur,
              ),
            );
            final r = repereLineaire;
            if (r == null) return barre;
            final x = (r.clamp(0.0, 1.0)) * contraintes.maxWidth;
            const largeurTrait = 2.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                barre,
                // `PositionedDirectional` et non `Positioned` : en arabe la
                // barre se remplit de droite à gauche, et un repère posé à
                // gauche désignerait le mauvais instant.
                PositionedDirectional(
                  start: (x - largeurTrait / 2)
                      .clamp(0.0, contraintes.maxWidth - largeurTrait),
                  top: -2,
                  bottom: -2,
                  child: Container(
                    width: largeurTrait,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (sousTitre != null || etat != null) ...[
          SizedBox(height: principale ? 6 : 4),
          Row(
            children: [
              if (sousTitre != null)
                Flexible(
                  child: Text(sousTitre!,
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkLight)),
                ),
              if (sousTitre != null && etat != null)
                Text(' · ',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.inkLight)),
              if (etat != null)
                Text(libelleDe(t, etat!),
                    style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: couleur)),
            ],
          ),
        ],
      ],
    );
  }
}

class _EtatVideObjectif extends StatelessWidget {
  final VoidCallback onTap;
  const _EtatVideObjectif({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cream200,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.coachObjectifEmptyTitle,
              style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(t.coachObjectifEmptyBody,
              style: GoogleFonts.manrope(
                  fontSize: 12, height: 1.4, color: AppColors.inkLight)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: AppColors.green800),
            child: Text(t.coachObjectifSetButton,
                style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Une tuile du tableau de bord : une icône, un libellé, une valeur courte.
/// Trois côte à côte répondent aux trois questions immédiates de l'utilisateur
/// (objectif du jour, série, points) sans qu'il ait à calculer quoi que ce soit.
class _TuileStat extends StatelessWidget {
  final IconData icone;
  final Color couleurIcone;
  final String libelle;
  final String valeur;
  /// Fond teinté quand la tuile porte une bonne nouvelle (objectif du jour
  /// atteint) : c'est la seule qui change d'état d'un jour à l'autre, elle doit
  /// se repérer sans lire.
  ///
  /// Plus aucun appelant depuis le 2026-08-14 : la tuile « Aujourd'hui » qui
  /// s'en servait a été fusionnée dans la tuile Série (cf. [complement]).
  /// Conservé — c'est le seul mécanisme d'accentuation de ces tuiles, et le
  /// réécrire coûterait plus cher que de le laisser en place.
  // ignore: unused_element_parameter
  final bool accentue;

  // ⛔ `complement` / `complementAccentue` ont existé quelques heures le
  // 2026-08-14 pour loger l'état du jour sous la série. Retirés : l'utilisateur
  // n'en voulait pas, et n'alimenter qu'une tuile sur deux cassait l'égalité de
  // hauteur des rectangles. Si une tuile doit un jour porter une seconde ligne,
  // il faudra la donner aux DEUX (ou passer par IntrinsicHeight), sans quoi le
  // même défaut d'alignement reviendra.

  const _TuileStat({
    required this.icone,
    required this.couleurIcone,
    required this.libelle,
    required this.valeur,
    // ignore: unused_element_parameter
    this.accentue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: accentue
            ? AppColors.green700.withValues(alpha: 0.10)
            : AppColors.cream,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: accentue
                ? AppColors.green700.withValues(alpha: 0.35)
                : AppColors.cream300),
      ),
      // ── MISE EN PAGE HORIZONTALE (2026-08-14) ──────────────────────────
      // Constat utilisateur sur capture : « le design pas top ». La tuile
      // était une colonne (icône / valeur / libellé / complément) : quatre
      // lignes empilées pour une seule information, deux tuiles occupant
      // 200 px de haut. L'icône passe à gauche et le texte se lit sur deux
      // lignes serrées -- même contenu, un tiers de la hauteur, et une
      // diagonale de lecture au lieu d'un empilement.
      child: Row(
        children: [
          Icon(icone, size: 20, color: couleurIcone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(libelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 9.5,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkLight)),
                const SizedBox(height: 1),
                Text(valeur,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 7 barres, les 7 derniers jours (le plus ancien à gauche, RTL ou pas — la
/// chronologie prime ici sur la direction de lecture). Hauteur relative au
/// jour le plus chargé de la fenêtre, jamais à une constante devinée : sur
/// une semaine à 20 mots/jour comme sur une à 400, le graphique reste lisible.
class _MiniEvolution extends StatelessWidget {
  final List<JourActif> jours;
  /// Repère textuel affiché sous la DERNIÈRE barre (2026-08-14, constat
  /// utilisateur : le graphique n'avait aucun repère -- impossible de savoir
  /// ce que les barres représentaient sans lire le code). Un seul repère
  /// suffit à ancrer toute la lecture : "la barre la plus à droite, c'est
  /// aujourd'hui, donc ça va de {aujourd'hui-6j} à aujourd'hui, dans l'ordre".
  final String libelleAujourdhui;
  const _MiniEvolution({required this.jours, required this.libelleAujourdhui});

  @override
  Widget build(BuildContext context) {
    final aujourdhui = DateTime.now();
    final parJour = {for (final j in jours) _cle(j.jour): j.motsRecites};
    final sept = List.generate(7, (i) {
      final d = aujourdhui.subtract(Duration(days: 6 - i));
      return parJour[_cle(d)] ?? 0;
    });
    final max = sept.fold<int>(1, (a, v) => v > a ? v : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in sept)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: 4 + 32 * (v / max),
                      decoration: BoxDecoration(
                        color: v > 0
                            ? AppColors.green700.withValues(alpha: 0.55)
                            : AppColors.cream300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        // Le repère était placé dans un `Expanded` d'un septième de largeur :
        // « Aujourd'hui » y tenait sur DEUX lignes, coupé en « Aujourd'h /
        // ui » (visible sur la capture du 2026-08-14). Aligné à droite sur
        // toute la largeur, il reste sous la dernière barre sans être
        // contraint par elle.
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(libelleAujourdhui,
              maxLines: 1,
              style: GoogleFonts.manrope(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkLight)),
        ),
      ],
    );
  }

  static String _cle(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

/// Feuille de réglage de l'objectif — durée pour tout le Coran, niveau
/// d'accompagnement. Cf. `ObjectifCoach` pour ce que chaque champ engage.
class _ReglageObjectifSheet extends ConsumerStatefulWidget {
  const _ReglageObjectifSheet();

  @override
  ConsumerState<_ReglageObjectifSheet> createState() =>
      _ReglageObjectifSheetState();
}

class _ReglageObjectifSheetState
    extends ConsumerState<_ReglageObjectifSheet> {
  late int _annees;
  late NiveauCoach _niveau;

  @override
  void initState() {
    super.initState();
    final o = ref.read(objectifCoachProvider);
    // 3 ans par défaut : le milieu du curseur, et l'ordre de grandeur le plus
    // souvent cité pour une mémorisation complète menée régulièrement. Un
    // défaut à 1 an mettrait l'utilisateur en échec dès la première semaine,
    // ce que le §2 du plan cherche précisément à éviter.
    _annees = o.actif ? o.annees : 3;
    _niveau = o.niveau;
  }

  String _libelleNiveau(AppLocalizations t, NiveauCoach n) => switch (n) {
        NiveauCoach.aMonRythme => t.coachNiveauAMonRythme,
        NiveauCoach.regulier => t.coachNiveauRegulier,
        NiveauCoach.exigeant => t.coachNiveauExigeant,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            20 + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.coachObjectifSheetTitle,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 19, color: AppColors.green900)),
            const SizedBox(height: 18),
            // ── LA DURÉE, PAS LE VOLUME (2026-08-14) ─────────────────────────
            // « L'objectif devient mémoriser tout le Coran, l'utilisateur
            // choisit en combien d'années, et l'app affiche ce que ça donne
            // par jour, par semaine et par mois » (utilisateur). Le curseur va
            // de 1 à 6 ans -- borne haute décidée avec l'utilisateur : au-delà,
            // le rythme quotidien devient si faible qu'il ne guide plus rien.
            Text(t.coachObjectifSheetDureeTitle,
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkLight)),
            const SizedBox(height: 4),
            Text(
              t.coachObjectifAnneesLabel(_annees),
              style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink),
            ),
            Slider(
              value: _annees.toDouble(),
              min: ObjectifCoach.anneesMin.toDouble(),
              max: ObjectifCoach.anneesMax.toDouble(),
              divisions: ObjectifCoach.anneesMax - ObjectifCoach.anneesMin,
              label: t.coachObjectifAnneesCourt(_annees),
              activeColor: AppColors.green800,
              onChanged: (v) => setState(() => _annees = v.round()),
            ),
            // ── CE QUE ÇA ENGAGE, TOUT DE SUITE ──────────────────────────────
            // Le rythme s'affiche PENDANT que le curseur bouge : c'est la
            // seule façon de choisir une durée en connaissance de cause. Il
            // est calculé sur le reste à mémoriser, comme partout ailleurs --
            // un aperçu qui mentirait de quelques quarts par rapport au
            // tableau de bord serait pire que pas d'aperçu du tout.
            Consumer(builder: (context, ref, _) {
              final acquis = ref.watch(quartsAcquisProvider).maybeWhen(
                    data: (v) => v,
                    orElse: () => 0.0,
                  );
              final r =
                  ObjectifCoach(annees: _annees).rythmePour(acquis);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ce qui reste : la base du calcul. Affiché ICI et plus sur
                  // la carte du hub (demande utilisateur 2026-08-14) -- c'est
                  // au moment de CHOISIR la durée qu'il éclaire quelque chose.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      t.coachObjectifResteLabel(r.quartsRestants.floor()),
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                  ),
                  for (final (valeur, periode) in [
                    (r.parJour, PeriodeObjectif.jour),
                    (r.parSemaine, PeriodeObjectif.semaine),
                    (r.parMois, PeriodeObjectif.mois),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '≈ ${_formatRythme(context, valeur)} '
                        '${t.coachObjectifQuartUnite} '
                        '${_libellePeriodeObjectif(t, periode)}',
                        style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkLight),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 20),
            Text(t.coachNiveauTitle,
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkLight)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in NiveauCoach.values)
                  ChoiceChip(
                    label: Text(_libelleNiveau(t, n)),
                    selected: _niveau == n,
                    onSelected: (_) => setState(() => _niveau = n),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.green800),
                onPressed: () async {
                  final notifier = ref.read(objectifCoachProvider.notifier);
                  await notifier.definir(annees: _annees);
                  await notifier.setNiveau(_niveau);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(t.coachObjectifValider,
                    style: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Zone A — Reprendre ───────────────────────────────────────────────────────

/// Dernier verset travaillé, persisté par [CoachScreen]. Affiché en tête pour
/// que l'action la plus fréquente (« je continue là où j'en étais ») ne demande
/// jamais de re-naviguer.
// Retiree du hub le 2026-08-06 (cf. CoachHubScreen.build) et conservee
// volontairement : regle projet, on n'efface pas ce qui a ete concu.
// ignore: unused_element
class _ResumeSection extends ConsumerWidget {
  const _ResumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final last = ref.watch(lastCoachVerseProvider);
    return last.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) {
        if (v == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: _Card(
            accent: true,
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.brass, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.coachHubResumeLabel,
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brassLight)),
                      const SizedBox(height: 2),
                      // v.surahName vient de SharedPreferences, écrit lors
                      // d'une session passée dans la langue d'alors : ne
                      // jamais s'y fier pour l'affichage (bug corrigé
                      // 2026-07-22, "Sourate 94" affiché en mode arabe).
                      // On recalcule toujours depuis le numéro + la locale
                      // actuelle, via la vraie liste des sourates (nom
                      // complet, pas juste le repli générique "Sourate N").
                      FutureBuilder<List<Surah>>(
                        future: QuranApi.fetchSurahs(),
                        builder: (context, snap) {
                          final surahs = snap.data;
                          final name = surahs == null
                              ? t.coachSurahLabel(v.surahNumber)
                              : (isArabic
                                  ? surahs
                                      .firstWhere((s) => s.number == v.surahNumber,
                                          orElse: () => surahs.first)
                                      .nameArabic
                                  : surahs
                                      .firstWhere((s) => s.number == v.surahNumber,
                                          orElse: () => surahs.first)
                                      .nameSimple);
                          return Text(t.coachHubResumeVerse(name, v.ayahNumber),
                              style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.cream));
                        },
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openCoachForVerse(
                      context, v.surahNumber, v.ayahNumber),
                  child: Text(t.coachHubContinue,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: AppColors.brassLight)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openCoachForVerse(
    BuildContext context, int surahNumber, int ayahNumber) async {
  final verses = await QuranApi.fetchVerses(surahNumber);
  final verse = verses.firstWhere(
    (v) => v.ayahNumber == ayahNumber,
    orElse: () => verses.first,
  );
  if (!context.mounted) return;
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => CoachScreen(verses: [verse])));
}

// ── Zone B — Mémoriser (ayah par ayah) ───────────────────────────────────────

// Retiree du hub le 2026-08-06 (cf. CoachHubScreen.build) et conservee
// volontairement : regle projet, on n'efface pas ce qui a ete concu.
// ignore: unused_element
class _MemorizeSection extends StatelessWidget {
  const _MemorizeSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(t.coachHubMemorizeSectionTitle, t.coachHubMemorizeSectionSubtitle),
        _Card(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.school_rounded,
                title: t.coachHubMemorizeSurahTitle,
                subtitle: t.coachHubMemorizeSurahSubtitle,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurahPickerScreen(
                      title: t.coachHubPickerMemorizeTitle,
                      subtitle: t.coachHubPickerMemorizeSubtitle,
                      onPicked: (surah, verses) => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CoachScreen(verses: verses)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Zone B bis — Jeu de mémorisation (rappel progressif par palier) ─────────

/// Mode ludique : révélation progressive mot par mot (paliers), en
/// complément de `CoachScreen` (3 étapes classiques). Décision utilisateur
/// 2026-07-22, mécanique détaillée dans
/// `.claude/skills/jeux-memorisation/SKILL.md`.
// Retiree du hub le 2026-08-06 (cf. CoachHubScreen.build) et conservee
// volontairement : regle projet, on n'efface pas ce qui a ete concu.
// ignore: unused_element
class _GameSection extends StatelessWidget {
  const _GameSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(t.coachHubGameSectionTitle, t.coachHubGameSectionSubtitle),
        _Card(
          child: _ActionRow(
            icon: Icons.videogame_asset_rounded,
            title: t.coachHubGameActionTitle,
            subtitle: t.coachHubGameActionSubtitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SurahPickerScreen(
                  title: t.coachHubPickerGameTitle,
                  subtitle: t.coachHubPickerGameSubtitle,
                  onPicked: (surah, verses) {
                    // Sourate tenant sur une seule page du Mushaf : jeu direct
                    // sur la sourate entière. Sourate étalée sur plusieurs
                    // pages : demander l'aya de départ et se limiter à cette
                    // page (décision utilisateur 2026-07-22 -- ne jamais
                    // lancer une session de plusieurs centaines de versets
                    // d'un coup, cf. bug d'overflow constaté sur Al-Baqarah).
                    final pages = verses.map((v) => v.pageNumber).whereType<int>().toSet();
                    if (pages.length <= 1) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MemorizationGameScreen(
                                surah: surah, verses: verses)),
                      );
                    } else {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MemorizationAyahPickerScreen(
                            surah: surah,
                            verses: verses,
                            onPicked: (pageVerses) => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MemorizationGameScreen(
                                      surah: surah, verses: pageVerses)),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Zone C — Réciter : LE MOTEUR DE L'APP, mis en valeur ─────────────────────

/// Récitation continue. Volontairement présentée comme une GRANDE CARTE
/// D'ACTION et non comme une ligne de liste parmi d'autres (retour utilisateur
/// 2026-07-20 : « réciter une sourate c'est le moteur de l'app, il n'est pas
/// mis en valeur ») : c'est la fonction centrale du produit, elle doit se voir
/// et s'atteindre en un geste.
///
/// Les PARAMÈTRES DE VÉRIFICATION ne sont plus ici : ils vivent sur l'écran de
/// récitation lui-même, derrière une icône (karaoke_recitation_screen.dart,
/// `_openVerificationSheet`) -- ils ne servent que là, et souvent EN COURS de
/// récitation. Le RÉCITATEUR est retourné dans les Réglages généraux (choix
/// transverse : écoute, souffleur, corrections audio).
// Retiree du hub le 2026-08-06 (cf. CoachHubScreen.build) et conservee
// volontairement : regle projet, on n'efface pas ce qui a ete concu.
// ignore: unused_element
class _ReciteSection extends StatelessWidget {
  const _ReciteSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SurahPickerScreen(
            title: t.coachHubPickerReciteTitle,
            subtitle: t.coachHubPickerReciteSubtitle,
            onPicked: (surah, verses) => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => KaraokeRecitationScreen(verses: _firstPageOf(verses))),
            ),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.green800, AppColors.green900],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brass, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: AppColors.green900.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brass,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brass.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.green900, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.coachHubReciteSurahTitle,
                      style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 5),
                  Text(
                    t.coachHubReciteSurahSubtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, color: AppColors.brassLight),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.brassLight, size: 26),
          ],
        ),
      ),
    );
  }
}

// ── Zone D — Mes erreurs, par sourate ────────────────────────────────────────
// Plus montée depuis le 2026-08-09 (« supprimer le pavé Mes erreurs »,
// doublon avec SessionsSection). Conservée intacte.
// ignore: unused_element
class _ErrorsSection extends ConsumerWidget {
  const _ErrorsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(surahErrorSummariesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SectionTitle(t.coachHubErrorsSectionTitle,
                  t.coachHubErrorsSectionSubtitle),
            ),
            // Remise à zéro (demande utilisateur 2026-07-22) : IRRÉVERSIBLE
            // (efface tout l'historique, toutes sourates confondues) ->
            // toujours confirmer avant, jamais un simple tap direct.
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.inkLight),
              tooltip: t.coachHubResetErrorsTooltip,
              onPressed: () => _confirmAndResetErrors(context, ref, t),
            ),
          ],
        ),
        const _ErrorKindBreakdown(),
        const _TajwidRuleBreakdown(),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.green700)),
          ),
          error: (e, _) => _Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t.coachHubLoadErrorLog('$e'),
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.inkLight)),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return _Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 36, color: AppColors.green600),
                      const SizedBox(height: 10),
                      Text(t.coachHubNoErrorsTitle,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(
                        t.coachHubNoErrorsBody,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.inkLight),
                      ),
                    ],
                  ),
                ),
              );
            }
            return _Card(
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SurahErrorTile(summary: list[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Boîte de dialogue de confirmation puis remise à zéro complète du journal
/// (demande utilisateur 2026-07-22). Invalide les 3 providers qui en
/// dépendent pour que l'UI reflète immédiatement le vide, sans attendre un
/// prochain rebuild déclenché ailleurs.
Future<void> _confirmAndResetErrors(
    BuildContext context, WidgetRef ref, AppLocalizations t) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.coachHubResetErrorsDialogTitle),
      content: Text(t.coachHubResetErrorsDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t.coachHubResetErrorsDialogCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(t.coachHubResetErrorsDialogConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await RecitationErrorLogService.instance.resetAll();
  ref.invalidate(errorKindBreakdownProvider);
  ref.invalidate(surahErrorSummariesProvider);
  ref.invalidate(tajwidRuleBreakdownProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.coachHubResetErrorsDone)),
    );
  }
}

/// Répartition GLOBALE des erreurs tajwid PAR RÈGLE PRÉCISE (demande
/// utilisateur 2026-07-22) — même présentation que [_ErrorKindBreakdown]
/// (barre empilée + légende), mais un cran plus fin : à l'intérieur du seau
/// "Tajwid", QUELLE règle revient le plus souvent. Couleurs réutilisées de
/// `kTajwidRuleInfo` (tajwid_help_sheet.dart) -- source de vérité unique déjà
/// utilisée pour colorer le texte coranique, pas une nouvelle palette.
class _TajwidRuleBreakdown extends ConsumerWidget {
  const _TajwidRuleBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(tajwidRuleBreakdownProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        if (counts.isEmpty) return const SizedBox.shrink();
        final present = [...counts.keys]
          ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.coachHubRuleBreakdownTitle,
                      style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (final r in present)
                            Expanded(
                              flex: counts[r]!,
                              child: ColoredBox(
                                  color: kTajwidRuleInfo[r.key]?.color ??
                                      AppColors.inkLight),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (final r in present)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: kTajwidRuleInfo[r.key]?.color ??
                                      AppColors.inkLight,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${kTajwidRuleInfo[r.key]?.name(t) ?? r.key} · ${counts[r]}',
                              style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SurahErrorTile extends ConsumerWidget {
  final SurahErrorSummary summary;
  const _SurahErrorTile({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final s = summary.surah;
    // Le bouton « carte mentale » n'apparaît que si le contenu existe pour
    // cette sourate (12 sourates rédigées à ce jour) -- jamais un bouton mort.
    final mindMap = ref.watch(mindMapProvider(s.number));
    final hasMindMap = mindMap.asData?.value != null;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.green50,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text('${summary.totalErrors}',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
        ),
        title: Text(
            isArabic ? '${s.number}. ${s.nameArabic}' : '${s.number}. ${s.nameSimple}',
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: isArabic
                ? GoogleFonts.scheherazadeNew(fontSize: 16, color: AppColors.ink)
                : GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.coachHubVersesTouched(summary.versesTouched, s.versesCount),
                style: GoogleFonts.manrope(
                    fontSize: 11.5, color: AppColors.inkLight),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: summary.touchedRatio.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.cream300,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.brass),
                ),
              ),
            ],
          ),
        ),
        trailing: isArabic
            ? null
            : Text(s.nameArabic,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 18, color: AppColors.green800)),
        children: [
          if (hasMindMap)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: Text(t.coachHubGoToMindMap),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.green700),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MindMapScreen(surah: s))),
                ),
              ),
            ),
          _SurahTajwidRuleChips(surahNumber: s.number),
          for (final a in summary.ayahs)
            _AyahErrorRow(surah: s, count: a),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Puces compactes "règle · nombre" pour LES erreurs tajwid de CETTE sourate
/// précisément (demande utilisateur 2026-07-22 : stats par sourate ET par
/// règle, pas seulement l'une ou l'autre séparément). Masqué si la sourate
/// n'a aucune erreur de type tajwid -- ne pas afficher une rangée vide.
class _SurahTajwidRuleChips extends ConsumerWidget {
  final int surahNumber;
  const _SurahTajwidRuleChips({required this.surahNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(surahTajwidRuleBreakdownProvider(surahNumber));
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        if (counts.isEmpty) return const SizedBox.shrink();
        final present = [...counts.keys]
          ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in present)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (kTajwidRuleInfo[r.key]?.color ?? AppColors.inkLight)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${kTajwidRuleInfo[r.key]?.name(t) ?? r.key} · ${counts[r]}',
                    style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AyahErrorRow extends StatefulWidget {
  final Surah surah;
  final AyahErrorCount count;
  const _AyahErrorRow({required this.surah, required this.count});

  @override
  State<_AyahErrorRow> createState() => _AyahErrorRowState();
}

class _AyahErrorRowState extends State<_AyahErrorRow> {
  // Détail mot par mot replié par défaut (demande utilisateur 2026-07-22 :
  // « en détaille le mot ou il ya erreur et type d'erreur ») -- un tap sur la
  // ligne déplie/replie, pour ne pas alourdir la liste par sourate qui peut
  // déjà compter des dizaines de versets.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final surah = widget.surah;
    final count = widget.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18, color: AppColors.inkLight),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                              t.coachHubAyahErrorCount(
                                  count.ayahNumber, count.count),
                              style: GoogleFonts.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.coachHubExplanationTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.psychology_alt_outlined,
                      size: 19, color: AppColors.green700),
                  onPressed: () => showCoachExplanation(
                    context,
                    surahNumber: surah.number,
                    ayahNumber: count.ayahNumber,
                    title: isArabic
                        ? '${surah.nameArabic} — ${count.ayahNumber}'
                        : '${surah.nameSimple} — verset ${count.ayahNumber}',
                  ),
                ),
                IconButton(
                  tooltip: t.coachHubReviewVerseTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.school_outlined,
                      size: 19, color: AppColors.green700),
                  onPressed: () => _openCoachForVerse(
                      context, surah.number, count.ayahNumber),
                ),
              ],
            ),
            if (_expanded)
              _AyahErrorDetails(surahNumber: surah.number, ayahNumber: count.ayahNumber),
          ],
        ),
      ),
    );
  }
}

/// Liste mot par mot des erreurs d'un verset, avec le type et -- pour les
/// règles "frontière" (ikhafa/iqlab/idgham à cheval sur deux mots) -- la
/// PAIRE de mots plutôt qu'un seul mot isolé (demande utilisateur 2026-07-22).
class _AyahErrorDetails extends ConsumerWidget {
  final int surahNumber;
  final int ayahNumber;
  const _AyahErrorDetails({required this.surahNumber, required this.ayahNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(ayahErrorDetailsProvider(
        (surahNumber: surahNumber, ayahNumber: ayahNumber)));
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 24, right: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.pairWord != null
                              ? '${e.expectedWord}  ${e.pairWord}'
                              : e.expectedWord,
                          style: GoogleFonts.amiri(
                              fontSize: 16, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (e.rules.isEmpty)
                              Text(recitationErrorKindLabel(t, e.kind),
                                  style: GoogleFonts.manrope(
                                      fontSize: 10.5,
                                      color: AppColors.inkLight))
                            else
                              for (final r in e.rules)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (kTajwidRuleInfo[r.key]?.color ??
                                            AppColors.inkLight)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    kTajwidRuleInfo[r.key]?.name(t) ?? r.key,
                                    style: GoogleFonts.manrope(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Briques communes ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.manrope(
                    fontSize: 11.5, color: AppColors.inkLight)),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool accent;
  final bool padded;
  const _Card({required this.child, this.accent = false, this.padded = true});

  @override
  Widget build(BuildContext context) => Container(
        padding: padded ? const EdgeInsets.all(4) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: accent ? AppColors.green800 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: accent ? AppColors.green700 : AppColors.cream300),
        ),
        child: accent
            ? Padding(padding: const EdgeInsets.all(12), child: child)
            : child,
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.green50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.green700, size: 20),
        ),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(
                fontSize: 11.5, color: AppColors.inkLight)),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.inkLight),
        onTap: onTap,
      );
}


/// Répartition des erreurs par TYPE (demande utilisateur 2026-07-20 :
/// « catégoriser par type : tajwid ou prononciation »).
///
/// Placée AVANT la liste par sourate : elle répond à une question différente
/// et plus générale — « sur quoi je bute, des lettres, des voyelles, ou du
/// tajwid ? » — alors que la liste par sourate répond à « où travailler ? ».
class _ErrorKindBreakdown extends ConsumerWidget {
  const _ErrorKindBreakdown();

  static const _order = [
    RecitationErrorKind.lettre,
    RecitationErrorKind.harakat,
    RecitationErrorKind.tajwid,
    RecitationErrorKind.saute,
    RecitationErrorKind.oubli,
    RecitationErrorKind.inconnu,
  ];

  Color _color(RecitationErrorKind k) => switch (k) {
        RecitationErrorKind.lettre => AppColors.tajwidIkhfaa,
        RecitationErrorKind.harakat => AppColors.mindmapEthique,
        RecitationErrorKind.tajwid => AppColors.green700,
        RecitationErrorKind.saute => AppColors.inkLight,
        RecitationErrorKind.oubli => Colors.lightBlue.shade300,
        RecitationErrorKind.inconnu => AppColors.cream300,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final async = ref.watch(errorKindBreakdownProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) {
        final total = counts.values.fold(0, (a, b) => a + b);
        if (total == 0) return const SizedBox.shrink();
        final present = [
          for (final k in _order)
            if ((counts[k] ?? 0) > 0) k,
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barre empilée : proportions d'un coup d'œil.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (final k in present)
                            Expanded(
                              flex: counts[k]!,
                              child: ColoredBox(color: _color(k)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (final k in present)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: _color(k), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${recitationErrorKindLabel(t, k)} · ${counts[k]}',
                              style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Ne pas laisser croire que « Tajwid » est une preuve : c'est
                  // une déduction par élimination (cf. classifyError).
                  Text(
                    t.coachHubErrorNoteExplainer,
                    style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        height: 1.35,
                        color: AppColors.inkLight),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
