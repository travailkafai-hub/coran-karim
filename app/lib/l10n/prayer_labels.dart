import 'package:flutter/widgets.dart';

import '../models/prayer_settings.dart';
import 'app_localizations.dart';

/// Noms des prières et des méthodes de calcul, dans la langue de l'écran.
///
/// ── POURQUOI UN FICHIER POUR CINQ MOTS (2026-09-09) ────────────────────────
///
/// Défaut signalé par l'utilisateur, application en arabe : « صلاة قادمة en
/// arabe, il y a du français aussi ». Le titre était bien traduit, mais le nom
/// de la prière juste en dessous restait `Sobh`, `Dhouhr`, `Ichaa` — une
/// translittération FRANÇAISE, affichée telle quelle sous un titre arabe.
///
/// Ces libellés étaient DUPLIQUÉS à trois endroits — l'écran des horaires,
/// l'accueil (`surah_list_screen`) et le service de notifications — chacun
/// avec sa propre `const Map`. Les traduire sur place aurait triplé le même
/// travail et laissé les trois copies libres de diverger. Un point unique
/// tient les trois.
///
/// ⚠️ CE FICHIER NE COUVRE PAS LES NOTIFICATIONS. `prayer_notification_service`
/// tourne hors arbre de widgets : il n'a pas de `BuildContext`, donc pas
/// d'accès à `AppLocalizations` par ce chemin. Sa `const Map` reste en place et
/// reste en français — cf. la note au-dessus d'elle. Le résoudre demande de
/// charger les traductions par `lookupAppLocalizations(Locale(...))` en
/// connaissant la langue courante, ce qui est un autre travail.
String nomPriere(BuildContext context, PrayerName p) {
  final t = AppLocalizations.of(context)!;
  return switch (p) {
    PrayerName.fajr => t.prayerNameFajr,
    PrayerName.dhuhr => t.prayerNameDhuhr,
    PrayerName.asr => t.prayerNameAsr,
    PrayerName.maghrib => t.prayerNameMaghrib,
    PrayerName.isha => t.prayerNameIsha,
  };
}

/// Nom complet d'une méthode de calcul.
///
/// « Muslim World League » et les sigles restent tels quels en toute langue :
/// ce sont des noms d'organisations, pas des expressions à traduire. Seule la
/// partie descriptive suit la langue.
String nomMethode(BuildContext context, PrayerCalculationMethod m) {
  final t = AppLocalizations.of(context)!;
  return switch (m) {
    PrayerCalculationMethod.muslimWorldLeague => t.prayerMethodMwl,
    PrayerCalculationMethod.ummAlQura => t.prayerMethodUmmAlQura,
    PrayerCalculationMethod.egyptian => t.prayerMethodEgyptian,
    PrayerCalculationMethod.franceUoif => t.prayerMethodFranceUoif,
  };
}
