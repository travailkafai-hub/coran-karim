import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/objectif_coach.dart';
import '../services/coach_notification_service.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart';
import 'app_settings_provider.dart' show objectifCoachProvider;
import 'prayer_settings_provider.dart';

/// Le verset qui revient le plus souvent dans le journal CUMULÉ d'erreurs
/// (`recitation_errors` -- jamais purgé, jamais un mot "non jugé" par la
/// chaîne, cf. la doc de `CoachNotificationService._messageApresMidi`).
/// `null` si aucune erreur n'est encore enregistrée.
Future<(String, String)?> _versetQuiCoince() async {
  final comptes = await RecitationErrorLogService.instance.errorCountsByAyah();
  if (comptes.isEmpty) return null;
  final pire = comptes.first;
  try {
    final versets = await QuranApi.fetchVerses(pire.surahNumber);
    final v = versets.firstWhere((v) => v.ayahNumber == pire.ayahNumber);
    return ('${pire.surahNumber}:${pire.ayahNumber}', v.textUthmani);
  } catch (_) {
    return null; // texte introuvable -> pas de rappel plutôt qu'un rappel vide
  }
}

/// Déclenche la reprogrammation des rappels du Coach (cf.
/// `CoachNotificationService`) à chaque changement de ce dont ils dépendent :
/// l'objectif/niveau, ou les horaires de prière du jour (position, méthode de
/// calcul). Un seul `ref.read(coachNotificationBootstrapProvider)` au
/// démarrage de l'app (même patron que `prayerSettingsProvider` dans
/// `main.dart`) suffit à tout tenir à jour ensuite.
///
/// `Provider` et non `StateNotifierProvider` : ce provider n'expose aucun
/// état, il n'existe que pour son EFFET DE BORD (`ref.listen`), posé une
/// seule fois à sa création.
final coachNotificationBootstrapProvider = Provider<void>((ref) {
  Future<void> reprogrammer() async {
    final prayerState = ref.read(prayerSettingsProvider);
    final today = prayerState.today;
    final tomorrow = prayerState.tomorrow;
    // Horaires pas encore calculés (position pas encore résolue) : rien à
    // faire, le prochain changement de `prayerSettingsProvider` relancera.
    if (today == null || tomorrow == null) return;

    final objectif = ref.read(objectifCoachProvider);
    if (!objectif.actif || objectif.niveau == NiveauCoach.aMonRythme) {
      await CoachNotificationService.instance.annulerTout();
      return;
    }

    final jours = await SessionArchiveService.instance.derniersJours(n: 1);
    final aujourdhui = jours.isEmpty ? null : jours.first;
    final serie = await SessionArchiveService.instance.serieEnCours();
    // Requête inutile hors niveau EXIGEANT (seul consommateur du résultat) --
    // évite un aller-retour base + resolution de verset à chaque
    // reprogrammation pour les deux autres niveaux.
    final versetQuiCoince = objectif.niveau == NiveauCoach.exigeant
        ? await _versetQuiCoince()
        : null;

    await CoachNotificationService.instance.scheduleUpcoming(
      today: today,
      tomorrow: tomorrow,
      niveau: objectif.niveau,
      objectifAtteintAujourdhui: aujourdhui?.objectifAtteint ?? false,
      serie: serie,
      versetQuiCoince: versetQuiCoince,
    );
  }

  ref.listen(prayerSettingsProvider, (_, __) => reprogrammer());
  ref.listen(objectifCoachProvider, (_, __) => reprogrammer());
  // Premier calcul : si les horaires du jour sont déjà connus au moment où
  // ce provider est lu (cas courant -- `prayerSettingsProvider` est
  // généralement déjà en cours de résolution avant celui-ci), on programme
  // tout de suite plutôt que d'attendre un changement futur.
  reprogrammer();
});
