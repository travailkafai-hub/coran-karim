import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/objectif_coach.dart';
import '../models/verse.dart';
import '../providers/memorization_game_records_provider.dart';
import '../providers/mind_map_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tajwid_help_sheet.dart';
import '../models/recitation_state.dart' show WordStatus;
import 'karaoke_recitation_screen.dart';
import 'mind_map_screen.dart';

/// LE COACH REGARDE EN ARRIÈRE (2026-08-06).
///
/// Demande utilisateur : « comme maintenant la récitation, le jeu et la
/// mémorisation, ça se fait depuis l'écran du Mushaf, je veux que le coach se
/// concentre sur les erreurs [...] on doit retravailler la partie coach pour
/// se concentrer sur tout ce qui est résultat ».
///
/// Ce que le Coach répondait avant : « que veux-tu faire ? » — quatre boutons
/// de lancement que le Mushaf propose désormais au verset près. Ce qu'il
/// répond maintenant : « voilà ce que tu as fait, et ce qui a coincé ».
///
/// Deux échelles de temps, volontairement distinctes :
///   - CETTE section : la SESSION, datée, avec la voix du récitant
///     (`SessionArchiveService`, gardée une semaine) ;
///   - `_ErrorsSection` du hub : le CUMUL par sourate et par règle
///     (`RecitationErrorLogService`, jamais effacé).
/// La première dit « ce jour-là », la seconde « en général ». Les mélanger
/// ferait perdre les deux.
final sessionsArchiveProvider = FutureProvider<List<SessionResume>>(
    (ref) => SessionArchiveService.instance.sessions());

final motsDeSessionProvider =
    FutureProvider.family<List<MotArchive>, int>((ref, sessionId) =>
        SessionArchiveService.instance.motsDeSession(sessionId));

/// Numéro -> nom de sourate (2026-08-11, constat utilisateur : « mes
/// récitations, mets les noms de sourate au lieu de "Sourate 113" »).
/// `sessions.surah_name` n'a jamais été renseigné à l'écriture (colonne
/// prévue mais jamais alimentée par `demarrer()`) -- résoudre le nom ICI, à
/// l'affichage, corrige aussi rétroactivement toutes les sessions déjà
/// archivées, sans migration. Source locale déjà chargée par ailleurs
/// (`QuranApi.fetchSurahs()`, mise en cache statique), pas d'appel réseau.
final surahNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final surahs = await QuranApi.fetchSurahs();
  return {for (final s in surahs) s.number: s.nameSimple};
});

/// Les 114 sourates, pour que « Mes portions » montre AUSSI celles qu'on n'a
/// jamais récitées (demande utilisateur 2026-08-15 : « rajoute toutes les
/// sourates même si elles ne sont jamais récitées, sans taux, en gris car
/// jamais récité, avec un moyen de lancer la récitation »).
///
/// POURQUOI ÇA COMPTE : la liste ne montrait que ce qui existe déjà en base,
/// donc le Coach ne parlait que du passé. Ce qui RESTE à faire — l'essentiel
/// d'un objectif « tout le Coran » — n'était visible nulle part, et il fallait
/// passer par le Mushaf pour attaquer une sourate neuve. Source déjà locale et
/// mise en cache (`QuranApi.fetchSurahs`), aucun appel réseau.
final toutesLesSouratesProvider =
    FutureProvider<List<Surah>>((ref) => QuranApi.fetchSurahs());

final tailleArchiveProvider =
    FutureProvider<int>((ref) => SessionArchiveService.instance.octetsAudio());

// ── SUIVI PERMANENT PAR PORTION (sourate/Hizb, 2026-08-10) ─────────────────
//
// Troisième échelle de temps, à côté des deux ci-dessus : ni la SESSION datée
// (`sessionsArchiveProvider`, 7 jours) ni le CUMUL d'erreurs par sourate
// (`RecitationErrorLogService`), mais le dernier verdict connu de CHAQUE mot
// d'une portion (sourate entière, ou tranche de Hizb/demi-Hizb pour une
// sourate qui s'étale sur plusieurs Hizb), mis à jour -- jamais dupliqué --
// à chaque récitation qui rejoue ce mot. Répond à la demande utilisateur
// 2026-08-08 : suivre une sourate dans la durée, avec un badge de réussite
// quand elle est intégralement couverte et juste (mots contestés inclus).
//
// Coexiste avec `sessionsArchiveProvider`, ne le remplace pas : la session
// datée garde son rôle (voix du jour, suppression au geste, budget 7 jours).
// ── LE JOURNAL DES JOURS (Coach, 2026-08-13) ────────────────────────────────
// Cf. `PLAN_COACH.md` et la doc de `_creerTableJours` -- la seule mémoire du
// Coach qui survive au-delà des 7 jours de `sessions`.
final derniersJoursProvider = FutureProvider<List<JourActif>>(
    (ref) => SessionArchiveService.instance.derniersJours(n: 60));

final serieProvider = FutureProvider<int>(
    (ref) => SessionArchiveService.instance.serieEnCours());

final portionsProvider = FutureProvider<List<PortionResume>>(
    (ref) => SessionArchiveService.instance.portions());

/// Quarts de Hizb déjà acquis sur tout le Coran (0 à 240), en fraction.
///
/// C'est la BASE DE CALCUL de l'objectif depuis le 2026-08-14 : l'échéance en
/// années porte sur ce qu'il RESTE à mémoriser (cf. `ObjectifCoach.rythmePour`).
/// Volontairement un provider séparé de [portionsProvider] : celui-ci est
/// plafonné à 60 portions pour l'affichage, alors que le compte doit porter
/// sur TOUT ce qui a été acquis, sans limite ni doublon (cf.
/// `SessionArchiveService.motsAcquisTousCoran`).
final quartsAcquisProvider = FutureProvider<double>((ref) async {
  final mots = await SessionArchiveService.instance.motsAcquisTousCoran();
  return (mots / ObjectifCoach.motsParQuart)
      .clamp(0.0, ObjectifCoach.quartsDuCoran.toDouble());
});

/// Quarts acquis sur les 30 derniers jours — l'AVANCEMENT du mois.
///
/// ── POURQUOI CE PROVIDER EXISTE (2026-08-14, second correctif du jour) ──────
///
/// La barre de progression sommait des FRACTIONS DE PORTION, plafonnées à 1
/// par portion. Une portion « sourate entière » courte y valait donc un quart
/// PLEIN : Al-Kawthar (10 mots) comptait autant qu'un vrai quart de Hizb
/// (~322 mots). Mesuré sur le téléphone de l'utilisateur : la barre comptait
/// **12,37 quarts** pour 272 mots réellement acquis, qui en valent **0,84**.
/// La carte affichait « 100 % ce mois-ci » juste sous « il te reste 239 quarts
/// sur 240 » -- deux chiffres qui se contredisent à l'écran.
///
/// Même unité que [quartsAcquisProvider], donc : des mots acquis DISTINCTS
/// divisés par la moyenne du Coran. Les deux nombres de la carte ne peuvent
/// plus diverger, puisqu'ils sortent de la même requête.
///
/// ⛔ Ne pas réintroduire de plancher sur `jours_actifs.quarts_valides` : ce
/// compteur s'incrémente sur `PortionResume.badge` (portion complète), donc il
/// porte EXACTEMENT le même biais -- treize sourates courtes terminées y
/// valaient douze quarts.
final quartsAcquisDuMoisProvider = FutureProvider<double>((ref) async {
  final mots = await SessionArchiveService.instance.motsAcquisTousCoran(
      depuis: DateTime.now().subtract(const Duration(days: 30)));
  return (mots / ObjectifCoach.motsParQuart)
      .clamp(0.0, ObjectifCoach.quartsDuCoran.toDouble());
});

/// Quarts acquis sur les 365 derniers jours — la progression de l'ANNÉE.
///
/// Demande utilisateur 2026-08-14 : « il manque une progression annuelle et
/// une pour le Coran entier ». Trois horizons, trois questions différentes :
/// le mois dit « est-ce que je tiens mon rythme en ce moment », l'année « est-
/// ce que l'engagement tient dans la durée », le Coran entier « où j'en suis,
/// tout court ». Fenêtre GLISSANTE comme le mois (et non l'année civile) :
/// sinon, chaque 1er janvier, une progression durement acquise retomberait à
/// zéro du jour au lendemain.
final quartsAcquisDeLAnneeProvider = FutureProvider<double>((ref) async {
  final mots = await SessionArchiveService.instance.motsAcquisTousCoran(
      depuis: DateTime.now().subtract(const Duration(days: 365)));
  return (mots / ObjectifCoach.motsParQuart)
      .clamp(0.0, ObjectifCoach.quartsDuCoran.toDouble());
});

final motsDePortionProvider =
    FutureProvider.family<List<PortionMot>, int>((ref, portionId) =>
        SessionArchiveService.instance.motsDePortion(portionId));

/// Invalide TOUT le tableau de bord du Coach, en un seul appel.
///
/// ── POURQUOI CE POINT UNIQUE (2026-08-17) ──────────────────────────────────
/// DÉFAUT CONSTATÉ PAR L'UTILISATEUR, base à l'appui : « j'ai effacé, mais
/// l'objectif reste à 26 % ». Vérifié dans `session_archive.db` : `portions`,
/// `portion_words`, `jours_actifs` et `points_quart_jour` étaient TOUTES vides
/// -- l'effacement avait bien eu lieu. Le 26 % ne venait donc pas de la base
/// mais d'un provider jamais réinvalidé, qui resservait sa dernière lecture.
///
/// La cause est structurelle, pas un oubli isolé : chaque endroit qui supprime
/// listait SA propre poignée de providers, et aucun ne les avait tous --
/// suppression d'une portion : `portions` seul ; suppression d'une récitation :
/// `sessionsArchive` + `tailleArchive` ; sortie de récitation : sept sur huit.
/// `quartsAcquisDeLAnnee` n'était invalidé NULLE PART, et `quartsAcquis` --
/// celui qui porte la barre d'objectif -- ne l'était sur aucun chemin de
/// suppression. Une liste recopiée à la main à N endroits diverge toujours ;
/// c'est le N qu'il faut supprimer, pas les oublis un par un.
///
/// Prend la FONCTION d'invalidation plutôt qu'un `ref` : `WidgetRef` et
/// `ProviderContainer` ne partagent aucun type commun, et les deux sont
/// nécessaires -- le conteneur est le seul utilisable après démontage
/// (cf. `_container` dans karaoke_recitation_screen.dart).
void rafraichirTableauDeBordCoach(void Function(ProviderOrFamily) invalider) {
  invalider(sessionsArchiveProvider);
  invalider(tailleArchiveProvider);
  invalider(portionsProvider);
  invalider(derniersJoursProvider);
  invalider(serieProvider);
  invalider(quartsAcquisProvider);
  invalider(quartsAcquisDuMoisProvider);
  invalider(quartsAcquisDeLAnneeProvider);
}


/// Traduit un statut ARCHIVÉ (texte, en base) en statut d'AFFICHAGE, celui que
/// l'écran de récitation sait peindre.
///
/// `skipped` reste `skipped` -- gris barré, pas vert : précision explicite de
/// l'utilisateur (2026-08-12), « quand j'ai dit que les non jugés peuvent être
/// comptés verts, ça ne veut pas dire de les rendre verts ». La règle du
/// 2026-08-11 portait sur le POURCENTAGE, jamais sur la couleur.
///
/// `conteste` s'affiche vert : l'utilisateur a déclaré qu'il avait bien
/// prononcé ce mot, et c'est déjà ainsi qu'il est compté.
WordStatus _statutAffiche(String archive) => switch (archive) {
      'correct' || 'conteste' => WordStatus.correct,
      'unclear' => WordStatus.unclear,
      'error' || 'oubli' => WordStatus.error,
      _ => WordStatus.skipped,
    };

class PortionsSection extends ConsumerWidget {
  const PortionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final portions = ref.watch(portionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(t.coachPortionsTitle,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                )),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.coachRefreshTooltip,
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.green800),
              onPressed: () {
                ref.invalidate(portionsProvider);
                // Le bouton rafraîchit TOUT le Coach, tableau de bord compris
                // (série, points, objectif du jour) -- sinon il ne rafraîchit
                // que la moitié de ce que l'utilisateur a sous les yeux.
                ref.invalidate(derniersJoursProvider);
                ref.invalidate(serieProvider);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        portions.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(t.coachPortionsError(e),
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight)),
          data: (list) => Column(
                  children: [
                    if (list.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.cream200,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cream300),
                        ),
                        child: Text(
                          t.coachPortionsEmpty,
                          style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              height: 1.45,
                              color: AppColors.inkLight),
                        ),
                      ),
                    // ── GROUPEES PAR SOURATE (2026-08-13) ──────────────
                    // Demande utilisateur : « je veux les portions par
                    // sourate avec stat globale, puis je change par Rub' /
                    // Hizb imbriqué dans la sourate ». Une sourate courte
                    // n'a qu'une portion : elle s'affiche telle quelle, sans
                    // niveau inutile. Une sourate longue (Al-Baqara, At-Tawbah)
                    // en a plusieurs : on montre son total, et ses tranches se
                    // déplient dedans.
                    for (final g in _grouperParSourate(list))
                      g.portions.length == 1
                          ? _CartePortion(g.portions.first)
                          : _GroupeSourate(g),
                    // ── CE QUI RESTE À FAIRE (2026-08-15) ────────────────
                    // Les sourates JAMAIS récitées, après celles qu'on
                    // travaille. En gris et SANS taux : un pourcentage à 0 %
                    // serait un jugement (« tu as échoué »), alors qu'il ne
                    // s'est simplement rien passé. Chacune porte un bouton
                    // pour lancer la récitation, sinon la liste ne fait
                    // qu'énumérer un manque.
                    _SouratesJamaisRecitees(
                        dejaVues: {for (final p in list) p.surahNumber}),
                  ],
                ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}


/// Une sourate et les portions qu'elle contient, avec ses totaux cumulés.

/// Confirmation de la remise à zéro d'une portion. Volontairement distincte de
/// celle d'une récitation : ce qui disparaît n'est pas la même chose, et un
/// texte approximatif sur une action irréversible est un piège.
Future<bool> _confirmerRemiseAZero(BuildContext context, String label) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Recommencer cette sourate ?'),
      content: Text(
          'Tout le suivi de « $label » sera effacé : les mots acquis, les mots '
          'ratés et leur historique. La prochaine récitation repartira de zéro. '
          'Tes récitations datées, elles, ne sont pas touchées.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Effacer le suivi',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _GroupePortions {
  final int surahNumber;
  final String nomSourate;
  final List<PortionResume> portions;
  const _GroupePortions(this.surahNumber, this.nomSourate, this.portions);

  int get wordsTotal =>
      portions.fold(0, (a, p) => a + p.wordsTotal);
  int get wordsGreen => portions.fold(0, (a, p) => a + p.wordsGreen);
  int get wordsReached => portions.fold(0, (a, p) => a + p.wordsReached);

  /// Même formule que [PortionResume.reussite], appliquée à la sourate
  /// entière : mots acquis sur le total de la sourate. Recalculée depuis les
  /// compteurs cumulés, jamais moyennée sur les pourcentages des tranches --
  /// une moyenne de pourcentages donnerait le même poids à un Hizb entier et
  /// à une tranche de trois versets.
  double? get reussite => wordsTotal <= 0 ? null : wordsGreen / wordsTotal;

  bool get badge => wordsTotal > 0 && wordsGreen >= wordsTotal;
}

/// Regroupe les portions par sourate, en conservant l'ordre canonique déjà
/// garanti par la requête (`ORDER BY surah_number, first_ayah`).
List<_GroupePortions> _grouperParSourate(List<PortionResume> list) {
  final out = <_GroupePortions>[];
  for (final p in list) {
    if (out.isNotEmpty && out.last.surahNumber == p.surahNumber) {
      out.last.portions.add(p);
    } else {
      // Le libellé d'une portion vaut « Sourate · Hizb N » : le nom seul est
      // ce qui précède le séparateur.
      final nom = p.label.split(' · ').first;
      out.add(_GroupePortions(p.surahNumber, nom, [p]));
    }
  }
  return out;
}

/// Une sourate longue : sa statistique globale, et ses tranches dépliables.
class _GroupeSourate extends StatefulWidget {
  final _GroupePortions g;
  const _GroupeSourate(this.g);

  @override
  State<_GroupeSourate> createState() => _GroupeSourateState();
}

class _GroupeSourateState extends State<_GroupeSourate> {
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final g = widget.g;
    final r = g.reussite;
    final couleur = r == null
        ? AppColors.inkLight
        : r >= 0.95
            ? AppColors.green700
            : r >= 0.85
                ? AppColors.brass
                : Colors.redAccent.shade200;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: g.badge ? AppColors.brass : AppColors.cream300,
            width: g.badge ? 1.4 : 1),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: g.badge
                ? const Icon(Icons.verified_rounded,
                    color: AppColors.brass, size: 26)
                : null,
            title: Text(g.nomSourate,
                style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            subtitle: Text(
              t.coachPortionWordsAcquired(g.wordsGreen, g.wordsTotal) +
                  (g.wordsReached < g.wordsTotal
                      ? t.coachPortionCoveredSuffix(g.wordsReached)
                      : t.coachPortionFullCoverage),
              style:
                  GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(r == null ? '—' : '${(r * 100).round()}%',
                        style: GoogleFonts.manrope(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: couleur)),
                  ],
                ),
                Icon(_ouvert ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.green800),
              ],
            ),
            onTap: () => setState(() => _ouvert = !_ouvert),
          ),
          if (_ouvert)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Column(
                children: [for (final p in g.portions) _CartePortion(p)],
              ),
            ),
        ],
      ),
    );
  }
}

class _CartePortion extends ConsumerWidget {
  final PortionResume p;
  const _CartePortion(this.p);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    // ── RECORD DU JEU ENCHAÎNEMENT, RATTACHÉ À LA PORTION (2026-08-12) ──────
    // Demande utilisateur : « qu'il soit rattaché au coach avec mes portions,
    // à chaque record battu le record soit mis à jour côté coach ». Même clé
    // `unitKey` que celle résolue par `PortionService` côté jeu -- aucune
    // correspondance floue, la portion est LA MÊME des deux côtés.
    final gameRecord = ref.watch(memorizationGameRecordsProvider)[p.unitKey] ?? 0;
    final r = p.reussite;
    final couleur = r == null
        ? AppColors.inkLight
        : r >= 0.95
            ? AppColors.green700
            : r >= 0.85
                ? AppColors.brass
                : Colors.redAccent.shade200;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: p.badge ? AppColors.brass : AppColors.cream300,
            width: p.badge ? 1.4 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: p.badge
            ? const Icon(Icons.verified_rounded,
                color: AppColors.brass, size: 26)
            : null,
        title: Text(p.label,
            style: GoogleFonts.manrope(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        // ── LA FRACTION AFFICHÉE DOIT ÊTRE CELLE QUI PRODUIT LE POURCENTAGE
        // (2026-08-11, constat utilisateur : « ils ont tous les deux 22/24
        // mais deux pourcentages différents ») ─────────────────────────────
        //
        // Ce sous-titre montrait `wordsReached/wordsTotal` (les mots
        // COUVERTS) alors que le pourcentage à droite vaut
        // `wordsGreen/wordsTotal` (les mots ACQUIS) : le numérateur du calcul
        // n'apparaissait nulle part sur la carte. Cas réel relevé sur le
        // device, portion Al-Fil : « 22/23 mot(s) couvert(s) » et « 87 % » --
        // 22/23 fait 96 %, et 87 % vient de 20/23, un 20 invisible. Le
        // pourcentage semblait donc faux alors qu'il était juste, et il
        // devenait impossible de le rapprocher de celui d'une récitation.
        // On affiche maintenant la fraction du calcul ; la couverture reste
        // dite, mais en complément et seulement quand elle apporte une
        // information (portion pas encore entièrement récitée).
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.coachPortionWordsAcquired(p.wordsGreen, p.wordsTotal) +
                  (p.wordsReached < p.wordsTotal
                      ? t.coachPortionCoveredSuffix(p.wordsReached)
                      : t.coachPortionFullCoverage),
              style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
            ),
            if (gameRecord > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        size: 12, color: AppColors.brass),
                    const SizedBox(width: 3),
                    Text(
                      t.coachPortionGameRecord(gameRecord, p.wordsTotal),
                      style: GoogleFonts.manrope(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brass),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(r == null ? '—' : '${(r * 100).round()}%',
                    style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: couleur)),
              ],
            ),
            // ── REMETTRE A ZERO POUR REFAIRE (2026-08-13) ──────────────────
            // Demande utilisateur : « rajoute pour memorisation par sourate la
            // possibilite de supprimer le statut pour refaire ». Le suivi
            // d'une portion est CUMULE et permanent par conception -- un mot
            // acquis le reste. Sans ce geste, impossible de reprendre une
            // sourate de zero. Meme patron que la suppression d'une
            // recitation, confirmation comprise : c'est irreversible.
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded,
                  size: 20, color: AppColors.inkLight),
              tooltip: 'Remettre cette portion à zéro',
              onPressed: () async {
                final ok = await _confirmerRemiseAZero(context, p.label);
                if (!ok || !context.mounted) return;
                await SessionArchiveService.instance.supprimerPortion(p.id);
                // TOUT le tableau de bord, pas seulement la liste : effacer une
                // portion change les quarts acquis, donc l'objectif et le
                // rythme. N'invalider que `portionsProvider` laissait la barre
                // sur son ancienne valeur (cf. rafraichirTableauDeBordCoach).
                if (context.mounted) rafraichirTableauDeBordCoach(ref.invalidate);
              },
            ),
          ],
        ),
        // Meme ecran, en CUMULE : `portion_words` porte le dernier verdict
        // connu de chaque mot deja touche, mis a jour d'une recitation a
        // l'autre. Un mot jamais recite n'a pas de ligne : il reste `pending`,
        // donc gris -- il n'est pas compte comme juste.
        onTap: () async {
          final mots =
              await SessionArchiveService.instance.motsDePortion(p.id);
          final versets = await QuranApi.fetchVerses(p.surahNumber);
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KaraokeRecitationScreen(
              verses: versets
                  .where((v) =>
                      v.ayahNumber >= p.firstAyah && v.ayahNumber <= p.lastAyah)
                  .toList(),
              titreRelecture: p.label,
              relecture: {
                for (final m in mots)
                  (p.surahNumber, m.ayahNumber, m.wordInAyah): (
                    statut: _statutAffiche(m.status),
                    entendu: m.heardWord ?? '',
                    // L'extrait de voix archivé (`s{id}_m{index}.wav`) : sans
                    // lui, la relecture interrogeait la chaîne native, restée
                    // sur une AUTRE session -- et pouvait faire écouter
                    // l'audio d'une autre sourate (mesuré 2026-08-15).
                    audio: m.audioPath,
                    // Le TYPE d'erreur tel qu'etabli le jour de la recitation
                    // (cf. la doc de `relecture`) : la relecture ne doit pas
                    // le recalculer avec le reglage d'aujourd'hui.
                    kind: m.kind,
                  ),
              },
            ),
          ));
        },
      ),
    );
  }
}

/// Le détail d'une portion : chaque mot NON ENCORE VERT (le reste est déjà
/// acquis, pas la peine de le relister -- même philosophie que le Coach
/// « se concentre sur les erreurs », cf. l'en-tête de ce fichier), avec sa
/// voix archivée quand elle existe encore (7 jours).
class PortionDetailScreen extends ConsumerWidget {
  final PortionResume portion;
  const PortionDetailScreen({super.key, required this.portion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mots = ref.watch(motsDePortionProvider(portion.id));
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(portion.label,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: mots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final aRevoir =
              list.where((m) => m.status != 'correct' && m.status != 'conteste').toList();
          // Historique (2026-08-11, constat utilisateur : « on doit garder
          // l'historique des mots ratés [...] pas avec les audios [...] mais
          // le mot raté avec la possibilité de s'entraîner ») -- mots
          // REDEVENUS corrects/contestés (donc pas dans `aRevoir`) mais qui
          // ont été ratés au moins une fois (`dejaRate`). Toujours tappables :
          // la fiche partagée (Ma voix + règles + entraînement) reste
          // accessible même sur un mot déjà acquis.
          final historique = list
              .where((m) =>
                  m.dejaRate && (m.status == 'correct' || m.status == 'conteste'))
              .toList();
          final t = AppLocalizations.of(context)!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _BilanPortion(portion),
              const SizedBox(height: 18),
              if (aRevoir.isEmpty && historique.isEmpty)
                Text(
                  list.isEmpty
                      ? t.coachPortionNoneRecitedYet
                      : t.coachPortionNothingToReview,
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.inkLight),
                )
              else ...[
                for (final m in aRevoir) _LignePortionMot(portion: portion, m: m),
                if (historique.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t.coachPortionHistorySection,
                      style: GoogleFonts.manrope(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkLight)),
                  const SizedBox(height: 8),
                  for (final m in historique) _LignePortionMot(portion: portion, m: m),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BilanPortion extends StatelessWidget {
  final PortionResume p;
  const _BilanPortion(this.p);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final r = p.reussite;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.badge)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      color: AppColors.brassLight, size: 20),
                  const SizedBox(width: 6),
                  Text(t.coachPortionBadgeLabel,
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brassLight)),
                ],
              ),
            ),
          Text(
              r == null
                  ? '—'
                  : t.coachPortionBilanPercent((r * 100).round()),
              style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brassLight)),
          const SizedBox(height: 6),
          Text(
            t.coachPortionBilanDetail(
                p.wordsGreen, p.wordsReached, p.wordsTotal),
            style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.cream.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

class _LignePortionMot extends ConsumerStatefulWidget {
  final PortionResume portion;
  final PortionMot m;
  const _LignePortionMot({required this.portion, required this.m});

  @override
  ConsumerState<_LignePortionMot> createState() => _LignePortionMotState();
}

class _LignePortionMotState extends ConsumerState<_LignePortionMot> {
  bool _chargement = false;
  String? _erreur;

  Future<void> _ouvrir() async {
    final portion = widget.portion;
    final m = widget.m;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final versets = await QuranApi.fetchVerses(portion.surahNumber);
      final Verse verset = versets.firstWhere((v) => v.ayahNumber == m.ayahNumber,
          orElse: () => versets.first);
      if (!mounted) return;
      showTajwidHelpSheet(
        context,
        ref,
        verse: verset,
        playlist: versets,
        focusWord: m.expectedWord,
        entendu: m.heardWord,
        localWordIndex: m.wordInAyah,
        archivedAudioPath: m.audioPath,
        extraitDebut: m.wordInAyah,
        extraitFin: m.wordInAyah + 1,
        // "Réessayer ce mot" réussi depuis une portion : le mot est marqué
        // correct dans SA portion (pas juste retiré d'un journal d'erreurs),
        // c'est ce qui fait avancer la couverture et, à terme, le badge.
        onArchivedWordCorrected: () async {
          await SessionArchiveService.instance.upsertPortionWord(
            surahNumber: portion.surahNumber,
            unitKey: portion.unitKey,
            label: portion.label,
            firstAyah: portion.firstAyah,
            lastAyah: portion.lastAyah,
            wordsTotal: portion.wordsTotal,
            ayahNumber: m.ayahNumber,
            wordInAyah: m.wordInAyah,
            expectedWord: m.expectedWord,
            status: 'correct',
          );
          ref.invalidate(portionsProvider);
          ref.invalidate(motsDePortionProvider(portion.id));
        },
        // Contestation (pouce vers le bas) : même rafraîchissement -- le mot
        // passe à `conteste` dans SA portion, ce qui bouge le pourcentage
        // affiché ici (2026-08-11, constat utilisateur : le pourcentage ne
        // bougeait pas après une contestation).
        onWordContested: () {
          ref.invalidate(portionsProvider);
          ref.invalidate(motsDePortionProvider(portion.id));
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() =>
            _erreur = AppLocalizations.of(context)!.coachWordUnavailable);
      }
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final m = widget.m;
    // Historique (mot redevenu correct/contesté, mais raté au moins une
    // fois, cf. `PortionMot.dejaRate`) : vert + badge distinct, pour ne pas
    // se confondre avec un mot ACTUELLEMENT en erreur.
    final estHistorique =
        m.dejaRate && (m.status == 'correct' || m.status == 'conteste');
    final couleur = estHistorique
        ? AppColors.green700
        : switch (m.status) {
            'error' => Colors.redAccent.shade200,
            'unclear' => AppColors.brass,
            'oubli' => Colors.lightBlue.shade300,
            _ => AppColors.inkLight,
          };
    final estOubli = m.kind == 'oubli';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _chargement ? null : _ouvrir,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cream300),
        ),
        child: Row(
          children: [
            Container(width: 4, height: 30, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(m.expectedWord,
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                              fontSize: 22, color: AppColors.ink)),
                      if (estOubli) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.lightBlue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.lightBlue.shade200),
                          ),
                          child: Text(t.errorKindOubli,
                              style: GoogleFonts.manrope(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.lightBlue.shade700)),
                        ),
                      ],
                      if (estHistorique) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.green700.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.green700.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                              m.status == 'conteste'
                                  ? t.coachPortionContestedBadge
                                  : t.coachPortionCorrectedBadge,
                              style: GoogleFonts.manrope(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.green700)),
                        ),
                      ],
                    ],
                  ),
                  if (m.heardWord != null && m.heardWord!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${t.karaokeHeardLabel} : ${m.heardWord}',
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                              fontSize: 15, color: AppColors.inkLight)),
                    ),
                  if (_erreur != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_erreur!,
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: AppColors.inkLight)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 4),
              child: Text('${widget.portion.surahNumber}:${m.ayahNumber}',
                  style:
                      GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight)),
            ),
            _chargement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded,
                    color: AppColors.inkLight),
          ],
        ),
      ),
    );
  }
}

class SessionsSection extends ConsumerWidget {
  const SessionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsArchiveProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('MES RÉCITATIONS',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                )),
            const Spacer(),
            // Le budget de stockage a été fixé par l'utilisateur (~1 Mo par
            // session, une semaine) : il doit pouvoir le VÉRIFIER, pas le
            // croire sur parole.
            ref.watch(tailleArchiveProvider).maybeWhen(
                  data: (o) => Text(
                      '${(o / (1024 * 1024)).toStringAsFixed(1)} Mo · 7 j',
                      style: GoogleFonts.manrope(
                          fontSize: 10.5, color: AppColors.inkLight)),
                  orElse: () => const SizedBox.shrink(),
                ),
            // ── BOUTON RAFRAÎCHISSEMENT (2026-08-10) ────────────────────────
            //
            // Demande utilisateur, après constat sur device : « il faut que je
            // sorte et revienne pour qu'elle s'affiche [...] c'est compliqué,
            // ajoute un bouton rafraîchissement ». `sessionsArchiveProvider`
            // est un FutureProvider mis en cache -- sa tentative d'invalidation
            // automatique à la sortie de l'écran de récitation
            // (`karaoke_recitation_screen.dart`, dispose()) peut échouer
            // silencieusement (`ref` parfois invalide à cet instant précis,
            // déjà journalisé sous `[Archive] cloture archive a echoue`) : la
            // liste reste alors périmée jusqu'au prochain remontage. Ce bouton
            // permet de forcer un nouvel essai sans quitter toute l'app.
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.green800),
              onPressed: () {
                ref.invalidate(sessionsArchiveProvider);
                ref.invalidate(tailleArchiveProvider);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        sessions.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Archive illisible : $e',
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight)),
          data: (list) => list.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cream200,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cream300),
                  ),
                  child: Text(
                    'Aucune récitation enregistrée pour l’instant. '
                    'Après une récitation contrôlée, vous retrouverez ici '
                    'chaque mot signalé — avec votre voix.',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, height: 1.45, color: AppColors.inkLight),
                  ),
                )
              : Column(
                  children: [
                    for (final s in list) _CarteSession(s),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Titre d'une carte/écran de session : nom de sourate résolu via
/// [surahNamesProvider], repli sur "Sourate N" tant que le nom n'est pas
/// encore chargé (le provider est déjà en cache la plupart du temps --
/// `QuranApi.fetchSurahs()` est statique et quasi gratuit une fois chargé).
String _titreSession(WidgetRef ref, SessionResume s) {
  if (s.surahNumber == null) return 'Récitation';
  final noms = ref.watch(surahNamesProvider).asData?.value;
  final nom = noms?[s.surahNumber] ?? 'Sourate ${s.surahNumber}';
  return s.fromAyah != null ? '$nom · v.${s.fromAyah}-${s.toAyah}' : nom;
}

class _CarteSession extends ConsumerWidget {
  final SessionResume s;
  const _CarteSession(this.s);

  Future<bool> _confirmerSuppression(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette récitation ?'),
        content: const Text(
            'Le résultat et les enregistrements audio de mots de cette '
            'session seront définitivement supprimés. Le journal cumulé '
            'du Coach (statistiques par sourate) n\'est pas affecté.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final r = s.reussite;
    final couleur = r == null
        ? AppColors.inkLight
        : r >= 0.95
            ? AppColors.green700
            : r >= 0.85
                ? AppColors.brass
                : Colors.redAccent.shade200;
    return Dismissible(
      key: ValueKey('session_${s.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmerSuppression(context),
      onDismissed: (_) async {
        await SessionArchiveService.instance.supprimerSession(s.id);
        // Cf. rafraichirTableauDeBordCoach : une recitation supprimee retire
        // aussi ses mots des acquis, donc l'objectif et la serie changent.
        rafraichirTableauDeBordCoach(ref.invalidate);
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          _titreSession(ref, s),
          style: GoogleFonts.manrope(
              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        // Même correctif que sur `_CartePortion` ci-dessus : ce sous-titre ne
        // donnait QUE le dénominateur (« 14 mot(s) récité(s) ») à côté d'un
        // pourcentage calculé sur `wordsGreen/wordsReached` -- le numérateur
        // restait invisible. Cas réel du device, Al-'Asr : la carte récitation
        // annonçait « 14 mot(s) récité(s) · 93 % » sans un seul mot listé « à
        // revoir », pendant que la carte portion de la MÊME sourate annonçait
        // 14 mots sur 14 et 100 %. Deux nombres identiques, deux pourcentages
        // différents, et aucun moyen de comprendre lequel disait quoi.
        subtitle: Text(
          '${_dateCourte(s.startedAt)} · '
          // `wordsAcquis` et non `wordsGreen` : c'est bien le numérateur du
          // pourcentage affiché à droite (un mot non jugé par la chaîne y est
          // compté, cf. `SessionResume.reussite`) -- afficher `wordsGreen`
          // ici rouvrirait exactement l'écart que ce sous-titre corrige.
          '${t.coachSessionWordsCorrect(s.wordsAcquis, s.wordsReached)}'
          '${s.nonVerts > 0 ? ' · ${s.nonVerts} à revoir' : ''}',
          style:
              GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(r == null ? '—' : '${(r * 100).round()}%',
                    style: GoogleFonts.manrope(
                        fontSize: 17, fontWeight: FontWeight.w800, color: couleur)),
                // Nomme le DÉNOMINATEUR, pas la qualité : disait « justes »,
                // exactement l'étiquette de la carte portion, alors que les
                // deux pourcentages ne répondent pas à la même question (une
                // tentative datée / la maîtrise de toute la portion).
                Text(t.coachSessionAccuracyLabel,
                    style: GoogleFonts.manrope(
                        fontSize: 9, color: AppColors.inkLight)),
              ],
            ),
            // Icône explicite (demande utilisateur 2026-08-08 : le glissement
            // seul n'était pas assez visible/découvrable -- « rajoute
            // supprimer sur chaque récitation »). Le glissement reste
            // disponible en plus, pas retiré.
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.inkLight),
              tooltip: 'Supprimer cette récitation',
              onPressed: () async {
                final ok = await _confirmerSuppression(context);
                if (!ok || !context.mounted) return;
                await SessionArchiveService.instance.supprimerSession(s.id);
                // Cf. rafraichirTableauDeBordCoach : meme raison qu'au balayage.
                if (context.mounted) {
                  rafraichirTableauDeBordCoach(ref.invalidate);
                }
              },
            ),
          ],
        ),
        // ── LE COACH OUVRE L'ECRAN DE RECITATION, PAS UNE LISTE ──────────
        // Demande utilisateur repetee (2026-08-12/13) : « je veux la meme
        // fenetre du karaoke ou le texte est colorie », « pour eviter la
        // multitude d'ecrans ». La page-liste des mots fautifs est donc
        // supprimee -- ce n'est plus un ecran de moins a maintenir, c'est le
        // MEME rendu et la MEME palette que pendant la recitation.
        onTap: () async {
          final mots =
              await SessionArchiveService.instance.motsDeSession(s.id);
          final versets = await QuranApi.fetchVerses(s.surahNumber ?? 1);
          if (!context.mounted) return;
          final a = s.fromAyah ?? 1;
          final b = s.toAyah ?? 9999;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KaraokeRecitationScreen(
              verses: versets
                  .where((v) => v.ayahNumber >= a && v.ayahNumber <= b)
                  .toList(),
              titreRelecture: s.surahName ?? 'Sourate ${s.surahNumber}',
              // Sans cette borne, seuls les mots FAUTIFS seraient colories :
              // `session_words` ne garde que les exceptions (cf. la doc du
              // parametre). Constate sur capture : un seul mot visible.
              motsAtteintsRelecture: s.wordsReached,
              relecture: {
                for (final m in mots)
                  if (m.surahNumber != null &&
                      m.ayahNumber != null &&
                      m.wordInAyah != null)
                    (m.surahNumber!, m.ayahNumber!, m.wordInAyah!): (
                      statut: _statutAffiche(m.status),
                      entendu: m.heardWord ?? '',
                      audio: m.audioPath,
                      // Cf. la doc de `relecture` : verdict du jour meme.
                      kind: m.kind,
                    ),
              },
            ),
          ));
        },
      ),
      ),
    );
  }

  static String _dateCourte(DateTime d) {
    final maintenant = DateTime.now();
    final jours = DateTime(maintenant.year, maintenant.month, maintenant.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    final heure =
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    return switch (jours) {
      0 => "Aujourd'hui $heure",
      1 => 'Hier $heure',
      _ => 'Il y a $jours jours',
    };
  }
}

/// Le détail d'une session : chaque mot non vert, avec SA VOIX telle qu'elle a
/// sonné ce jour-là, et celle du récitateur pour comparer.
///
/// C'est la raison d'être de l'archive audio. Sans elle, un mot signalé se
/// résume à un reproche sans preuve — et l'utilisateur ne peut ni le vérifier,
/// ni entendre ce qu'il a réellement dit.
class SessionDetailScreen extends ConsumerWidget {
  final SessionResume session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mots = ref.watch(motsDeSessionProvider(session.id));
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(
          _titreSession(ref, session),
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        // ── CARTE MENTALE IMBRIQUÉE ICI (2026-08-09, demande utilisateur) ──
        // « garde même format pour session et tu imbriques l'entraînement et
        // mindmap » -- le jeu (M'entraîner) était déjà accessible par mot
        // (`_LigneMot._entrainer`, plus bas) ; la carte mentale, elle,
        // n'existait que dans l'ancien volet "Mes erreurs". Même bouton que
        // `coach_hub_screen._SurahErrorTile` (masqué si aucun contenu pour
        // cette sourate -- jamais un bouton mort).
        actions: [
          if (session.surahNumber != null)
            Consumer(builder: (context, ref, _) {
              final mindMap =
                  ref.watch(mindMapProvider(session.surahNumber!));
              if (mindMap.asData?.value == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.hub_outlined),
                tooltip: 'Carte mentale',
                onPressed: () async {
                  final surahs = await QuranApi.fetchSurahs();
                  final surah = surahs
                      .firstWhere((s) => s.number == session.surahNumber);
                  if (!context.mounted) return;
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => MindMapScreen(surah: surah)));
                },
              );
            }),
        ],
      ),
      body: mots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Bilan(session),
            const SizedBox(height: 18),
            if (list.isEmpty)
              Text('Aucun mot signalé sur cette récitation.',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.inkLight))
            else
              for (final m in list) _LigneMot(m),
          ],
        ),
      ),
    );
  }
}

class _Bilan extends StatelessWidget {
  final SessionResume s;
  const _Bilan(this.s);

  @override
  Widget build(BuildContext context) {
    final r = s.reussite;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r == null ? '—' : '${(r * 100).round()} % de mots justes',
              style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brassLight)),
          const SizedBox(height: 6),
          // Le dénominateur est dit explicitement : c'est la question la plus
          // souvent mal comprise d'un score de récitation (« pourquoi 100 %
          // alors que je me suis arrêté au milieu ? »).
          Text(
            '${s.wordsGreen} mots justes sur ${s.wordsReached} récités. '
            'Les mots jamais atteints ne comptent pas.',
            style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.cream.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

// ── UNE SEULE FICHE MOT, PARTAGÉE AVEC LA RÉCITATION EN DIRECT (2026-08-09) ──
//
// Demande utilisateur : « lors de la récitation CTR, on a après les mots en
// erreur, on clique dessus, y a une page avec Ma voix / récitateur [...] je
// veux rajouter dans cette page un lien pour lancer la mémorisation et le
// jeu sur ce verset, cette même page je veux l'utiliser dans l'affichage
// coach [...] elle contient également les règles de tajweed, elle est bien
// faite ». Puis, sur la raison d'être : « on ne sait jamais que l'utilisateur
// ne fait rien [dans l'immédiat], il faut pouvoir revenir dessus via coach ».
//
// Avant : cette carte réimplémentait Ma voix / Le récitateur / M'entraîner /
// pouces avec sa PROPRE logique (fichier archivé plutôt qu'extraction v2),
// séparée de `tajwid_help_sheet.dart` -- deux endroits à faire évoluer pour
// le même geste, et aucune règle de tajwid ni lancement de jeu ici.
// Maintenant : `_LigneMot` n'est qu'un résumé tappable ; tout le détail (voix,
// règles, entraînement, pouces) vit dans la fiche partagée, ouverte avec
// `archivedAudioPath: m.audioPath` pour lui dire de rejouer le fichier déjà
// sur disque plutôt que d'extraire un flux v2 qui n'existe plus hors session.
class _LigneMot extends ConsumerStatefulWidget {
  final MotArchive m;
  const _LigneMot(this.m);

  @override
  ConsumerState<_LigneMot> createState() => _LigneMotState();
}

class _LigneMotState extends ConsumerState<_LigneMot> {
  bool _chargement = false;
  String? _erreur;

  Future<void> _ouvrir() async {
    final m = widget.m;
    if (m.surahNumber == null || m.ayahNumber == null) {
      setState(() => _erreur = 'Position du mot inconnue');
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final versets = await QuranApi.fetchVerses(m.surahNumber!);
      final Verse verset = versets.firstWhere(
          (v) => v.ayahNumber == m.ayahNumber,
          orElse: () => versets.first);
      if (!mounted) return;
      showTajwidHelpSheet(
        context,
        ref,
        verse: verset,
        playlist: versets,
        focusWord: m.expectedWord,
        entendu: m.heardWord,
        localWordIndex: m.wordInAyah,
        archivedAudioPath: m.audioPath,
        extraitDebut: m.wordInAyah,
        extraitFin: m.wordInAyah == null ? null : m.wordInAyah! + 1,
        // "Réessayer ce mot" réussi depuis l'archive (2026-08-10, demande
        // utilisateur) : pas de session live à corriger, on retire plutôt
        // l'erreur du journal cumulé -- le récitateur vient de prouver qu'il
        // sait le dire.
        onArchivedWordCorrected: (m.surahNumber == null ||
                m.ayahNumber == null ||
                m.wordInAyah == null)
            ? null
            : () => RecitationErrorLogService.instance.removeLatestError(
                  surahNumber: m.surahNumber!,
                  ayahNumber: m.ayahNumber!,
                  wordIndex: m.wordInAyah!,
                ),
        // Contestation (pouce vers le bas) -- constat utilisateur (2026-08-11,
        // exemple chiffré : session à 91 %, 5 mots contestés, doit passer à
        // 100 %) : « ça met à jour aussi, un contesté ça met à jour partout ».
        // Met à jour LA SESSION d'où le mot a été ouvert (pas une portion
        // indépendante -- `contesterMotDeSession` cible la ligne précise, cf.
        // sa doc) ET rafraîchit la liste des portions, qui peut contenir le
        // même mot.
        onWordContested: () async {
          await SessionArchiveService.instance.contesterMotDeSession(m.id);
          ref.invalidate(sessionsArchiveProvider);
          ref.invalidate(portionsProvider);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Verset indisponible');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    // 'oubli' (2026-08-09) : décrochage repris ou souffleur sollicité -- ni
    // une erreur de prononciation (rouge) ni une approximation (brass), donc
    // une couleur à part. Cf. `_archiverOubli` dans karaoke_recitation_screen.
    final couleur = switch (m.status) {
      'error' => Colors.redAccent.shade200,
      'unclear' => AppColors.brass,
      'oubli' => Colors.lightBlue.shade300,
      _ => AppColors.inkLight,
    };
    final estOubli = m.kind == 'oubli';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _chargement ? null : _ouvrir,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cream300),
        ),
        child: Row(
          children: [
            Container(width: 4, height: 30, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(m.expectedWord,
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                              fontSize: 22, color: AppColors.ink)),
                      if (estOubli) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.lightBlue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.lightBlue.shade200),
                          ),
                          child: Text('Oubli',
                              style: GoogleFonts.manrope(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.lightBlue.shade700)),
                        ),
                      ],
                    ],
                  ),
                  // Ce que la chaîne a entendu : la seule information qui
                  // permette de repérer un verdict à contester avant même
                  // d'ouvrir la fiche.
                  if (m.heardWord != null && m.heardWord!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('entendu : ${m.heardWord}',
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                              fontSize: 15, color: AppColors.inkLight)),
                    ),
                  if (_erreur != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_erreur!,
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: AppColors.inkLight)),
                    ),
                ],
              ),
            ),
            if (m.ayahNumber != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 4),
                child: Text('${m.surahNumber}:${m.ayahNumber}',
                    style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.inkLight)),
              ),
            _chargement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded,
                    color: AppColors.inkLight),
          ],
        ),
      ),
    );
  }
}

/// Les sourates qu'on n'a JAMAIS récitées — la moitié manquante de « Mes
/// portions » (demande utilisateur 2026-08-15).
///
/// Trois choix de fond, tous délibérés :
///
///  1. AUCUN POURCENTAGE. Afficher « 0 % » sur une sourate jamais ouverte
///     serait un verdict là où il ne s'est rien passé — la même faute que
///     peindre un mot en rouge sans preuve acoustique. Ces lignes disent
///     « pas encore », pas « raté ».
///  2. GRIS, la couleur que l'app réserve déjà à « ni succès ni échec »
///     (mot omis, mot soufflé) — jamais le rouge.
///  3. UN BOUTON POUR COMMENCER. Sans lui, la liste ne ferait qu'énumérer un
///     manque ; avec lui, elle devient le point de départ naturel d'une
///     séance. La récitation démarre sur la PREMIÈRE PAGE de la sourate,
///     comme partout ailleurs dans l'app (une session ne se lance jamais sur
///     une sourate entière de plusieurs pages).
class _SouratesJamaisRecitees extends ConsumerStatefulWidget {
  final Set<int> dejaVues;
  const _SouratesJamaisRecitees({required this.dejaVues});

  @override
  ConsumerState<_SouratesJamaisRecitees> createState() =>
      _SouratesJamaisReciteesState();
}

class _SouratesJamaisReciteesState
    extends ConsumerState<_SouratesJamaisRecitees> {
  /// Repliées par défaut : 114 sourates dépliées d'office noieraient le suivi
  /// réel, qui est le sujet principal de cette section.
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    final toutes = ref.watch(toutesLesSouratesProvider);
    return toutes.maybeWhen(
      data: (surahs) {
        final restantes =
            surahs.where((s) => !widget.dejaVues.contains(s.number)).toList();
        if (restantes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _ouvert = !_ouvert),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(_ouvert
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.inkLight),
                    const SizedBox(width: 4),
                    Text(
                      'Pas encore récitées — ${restantes.length}',
                      style: GoogleFonts.manrope(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkLight),
                    ),
                  ],
                ),
              ),
            ),
            if (_ouvert)
              for (final s in restantes) _LigneSourateNeuve(surah: s),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _LigneSourateNeuve extends StatelessWidget {
  final Surah surah;
  const _LigneSourateNeuve({required this.surah});

  @override
  Widget build(BuildContext context) {
    const gris = Color(0xFF9e9e9e);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gris.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${surah.number}',
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gris)),
          ),
          Expanded(
            child: Text(
              surah.nameSimple,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkLight),
            ),
          ),
          Text(
            '${surah.versesCount} v.',
            style: GoogleFonts.manrope(fontSize: 10.5, color: gris),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Commencer cette sourate',
            icon: const Icon(Icons.play_circle_outline_rounded,
                size: 22, color: AppColors.green700),
            onPressed: () async {
              final versets = await QuranApi.fetchVerses(surah.number);
              if (!context.mounted) return;
              // Première page seulement : une session ne démarre jamais sur
              // une sourate de plusieurs pages (même règle que le hub et le
              // sélecteur de sourate).
              final premierePage = versets.first.pageNumber;
              final page = premierePage == null
                  ? versets
                  : versets
                      .where((v) => v.pageNumber == premierePage)
                      .toList();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    KaraokeRecitationScreen(verses: page.isEmpty ? versets : page),
              ));
            },
          ),
        ],
      ),
    );
  }
}
