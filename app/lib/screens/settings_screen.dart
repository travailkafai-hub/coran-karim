import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart' show recitationVerifierProvider;
import '../services/voice_lora_clip_service.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'prayer_times_settings_screen.dart';
import 'qibla_screen.dart';
import 'reciter_select_screen.dart';
// Conservé en commentaire : l'écran de calibrage existe toujours, seule son
// entrée dans les Réglages est retirée de la v1 (cf. plus bas).
// import 'voice_calibration_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final locale = ref.watch(appLocaleProvider);
    final reciter = ref.watch(playerProvider).reciter;
    // En arabe, aucun mot latin à l'écran (règle verrouillée REFONTE_IHM.md
    // §7bis) : le nom du récitateur et son style passent en arabe ; en fr/en,
    // le nom romanisé + le style (termes techniques déjà transparents dans
    // les deux langues) restent, avec le nom arabe en flourish à droite.
    final reciterStyleLabel = reciter.style == 'Mujawwad'
        ? t.settingsStyleMujawwad
        : t.settingsStyleMurattal;
    final reciterSubtitle = locale == 'ar'
        ? '${reciter.nameAr} • $reciterStyleLabel'
        : '${reciter.nameFr}  •  ${reciter.style}';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text(t.settingsTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Historique de cette section (ne pas re-déplacer sans relire) :
          //  - 2026-07-19 : "Mode de vérification" retiré d'ici (« alléger les
          //    paramètres globaux »).
          //  - 2026-07-20 (matin) : toute la section « Récitation » déplacée
          //    dans le hub Coach.
          //  - 2026-07-20 (correction utilisateur) : partage plus juste, sur
          //    le critère « à quoi sert ce réglage ? » plutôt que « où est
          //    l'écran ? » :
          //      * paramètres de VÉRIFICATION (mode tajwid, sensibilité,
          //        rigueur, correction auto, suivre sans bloquer) -> sur
          //        l'ÉCRAN DE RÉCITATION, derrière une icône : ils ne servent
          //        que là, et souvent EN COURS de récitation ;
          //      * RÉCITATEUR -> reste ici (ci-dessous) : transverse (écoute,
          //        souffleur, corrections audio), pas propre à la récitation.
          _SectionHeader(t.settingsSectionAudio),
          // Le RÉCITATEUR reste ici, dans les réglages généraux (précision
          // utilisateur 2026-07-20 : « le récitateur c'est dans réglages
          // générale »). C'est un choix TRANSVERSE : il sert à l'écoute d'une
          // sourate, au souffleur, aux corrections audio -- pas seulement à la
          // récitation. Les paramètres de VÉRIFICATION, eux, vivent sur
          // l'écran de récitation (icône dédiée), cf. REFONTE_IHM.md §11.
          _SettingsTile(
            icon: Icons.record_voice_over,
            title: t.settingsReciterTitle,
            subtitle: reciterSubtitle,
            color: AppColors.settingsAudio,
            // Flourish calligraphique -- uniquement en fr/en (en arabe, le
            // nom arabe est déjà le sous-titre principal, pas de doublon).
            trailing: locale == 'ar'
                ? null
                : Text(reciter.nameAr,
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.scheherazadeNew(
                        fontSize: 14, color: AppColors.green700)),
            onTap: () async {
              final picked = await Navigator.push<Reciter>(
                context,
                MaterialPageRoute(
                    builder: (_) => ReciterSelectScreen(
                        currentId: ref.read(playerProvider).reciter.id)),
              );
              if (picked != null) {
                ref.read(playerProvider.notifier).setReciter(picked);
              }
            },
          ),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionPrayer),
          _SettingsTile(
            icon: Icons.explore_rounded,
            title: t.settingsQiblaTitle,
            subtitle: t.settingsQiblaSubtitle,
            color: AppColors.settingsPrayer,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QiblaScreen())),
          ),
          _SettingsTile(
            icon: Icons.access_time_rounded,
            title: 'Horaires de prière',
            subtitle: 'Adhan programmé, rappel avant Sobh',
            color: AppColors.settingsPrayer,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrayerTimesSettingsScreen())),
          ),

          // ── CINQ RÉGLAGES RETIRÉS DE LA v1 (2026-08-09) ──────────────────
          //
          // Décision utilisateur, une raison donnée pour chacun :
          //
          //   1. « Calibrage des lettres confusables » -- « ça sert à rien ».
          //      `VoiceCalibrationScreen` existe toujours (écran + données),
          //      seule l'entrée disparaît.
          //   2. « Mes enregistrements de récitation » (`_VoiceLoraClipsTile`)
          //      -- « sera pas utilisé pour la prod » : c'est un outil de
          //      collecte de données d'entraînement, pas une fonction pour le
          //      récitateur.
          //   3. « Couleurs tajweed » -- l'interrupteur ne persistait rien
          //      (`value: true, onChanged: (_) {}`, TODO jamais fait) : il
          //      MENTAIT à l'utilisateur, qui pouvait le basculer sans le
          //      moindre effet. Un réglage inopérant est pire qu'absent.
          //   4. « Journal de diagnostic » (`_DiagnosticTile`) -- outil de
          //      développement. Le journal lui-même reste (il est désormais
          //      coupé par défaut en release, cf. `DiagnosticLog.enabled`),
          //      c'est son commutateur qui quitte l'IHM.
          //   5. « Suppression de bruit » (`_NoiseSuppressTile`) -- « pas
          //      efficace », ce que la mesure du projet disait déjà (banc du
          //      2026-07-23 : la désactiver donnait 22,8 % de WER contre
          //      70,2 % activée -- elle DÉGRADE la reconnaissance).
          //
          // Les widgets `_VoiceLoraClipsTile`, `_DiagnosticTile` et
          // `_NoiseSuppressTile` restent définis plus bas dans ce fichier
          // (convention projet : on n'efface pas ce qui a été conçu), ils ne
          // sont simplement plus montés. Deux sections entières disparaissent
          // avec eux (« Affichage » et « Diagnostic ») : elles n'auraient plus
          // contenu que du vide.
          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionVoicePersonalization),
          const _DisputedVerdictsTile(),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionApp),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: t.settingsLocaleTitle,
            subtitle: _localeLabel(locale),
            color: AppColors.settingsApp,
            onTap: () => _pickLocale(context, ref),
          ),
          // Cette tuile est restée SANS `onTap` jusqu'au 2026-08-09 : elle
          // affichait un sous-titre et n'ouvrait rien. Le sous-titre annonçait
          // en plus « Whisper », alors que la vérification tourne sur
          // FastConformer CTC — une information fausse montrée à l'utilisateur.
          // Elle mène désormais à AboutScreen, qui porte ce que l'app doit
          // dire avant d'être publiée (données captées, avertissement sur le
          // texte généré, sources, licences).
          // ── « UNE INVOCATION POUR NOUS » : DEVENUE UN ONGLET (2026-08-09) ─
          // Cette tuile a d'abord vécu ici (icône `volunteer_activism_rounded`,
          // retirée le même jour de l'onglet Invocations où l'utilisateur
          // l'avait jugée « utilisée après pour les dons »). Jugée trop
          // discrète à son tour (« je veux qu'elle soit visible pour inciter
          // les users à ne pas oublier »), la page est maintenant son PROPRE
          // onglet dans la barre de navigation (❤️, entre Coach et Réglages,
          // cf. `main.dart`) -- la dupliquer ici serait une redondance de
          // navigation, pas un service. `DuaPourNousScreen` et ses clés
          // `duaPourNousTile*` restent utilisés par cet onglet.
          // ── « NOUS CONTACTER » (2026-08-09, demande utilisateur) ─────────
          // « je veux que tu rajoutes nous contacter pour que les users
          // puissent nous envoyer leurs avis, les remarques ». Même adresse
          // que `kContactEmail` (about_screen.dart, déjà réservée au
          // signalement IA) -- une seule boîte, l'utilisateur l'a fournie
          // lui-même. Copie presse-papiers, pas `mailto:` : marche même sans
          // application de messagerie configurée (même raison que
          // `_BlocSignalement` dans about_screen.dart).
          _SettingsTile(
            icon: Icons.mail_outline_rounded,
            title: t.settingsContactTitle,
            subtitle: t.settingsContactSubtitle,
            color: AppColors.settingsApp,
            onTap: () => _ouvrirContact(context, t),
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: t.appTitle,
            subtitle: t.settingsAboutSubtitle,
            color: AppColors.settingsApp,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
    );
  }

  void _ouvrirContact(BuildContext context, AppLocalizations t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.settingsContactTitle,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 20, color: AppColors.green900)),
            const SizedBox(height: 10),
            Text(t.settingsContactBody,
                style: GoogleFonts.manrope(
                    fontSize: 13, height: 1.55, color: AppColors.ink)),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      const ClipboardData(text: kContactEmail));
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(t.settingsContactCopied)));
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.green900,
                  side: const BorderSide(color: AppColors.brass),
                ),
                label: Text(kContactEmail,
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localeLabel(String locale) => switch (locale) {
        'ar' => 'العربية',
        'en' => 'English',
        _ => 'Français',
      };

  void _pickLocale(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LocaleSheet(
        current: ref.read(appLocaleProvider),
        onPick: (locale) {
          ref.read(appLocaleProvider.notifier).set(locale);
          Navigator.pop(context);
        },
      ),
    );
  }

}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(title.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 10,
                color: AppColors.green700,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  /// Couleur de la pastille -- une par section (cf. AppColors.settings*),
  /// défaut vert pour ne rien casser là où elle n'est pas encore précisée.
  final Color color;
  const _SettingsTile({
    required this.icon, required this.title, required this.subtitle,
    this.trailing, this.onTap, this.color = AppColors.green700,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cream300),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title,
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
          subtitle: Text(subtitle,
              style: GoogleFonts.manrope(
                  fontSize: 11, color: AppColors.inkLight)),
          trailing: trailing ??
              (onTap != null
                  ? const Icon(Icons.chevron_right, color: AppColors.inkLight)
                  : null),
          onTap: onTap,
        ),
        ),
      );
}

/// Interrupteur du diagnostic : journal fichier (Dart + natif) ET capture des
/// WAV de chaque segment figé, pilotés ensemble.
///
/// Demande utilisateur 2026-07-25 : « je veux m'assurer que ces retards ne
/// sont pas dus à la création des logs ». Mesuré ce jour-là : 22 à 32
/// écritures fichier synchrones par seconde côté Dart, plus les lignes natives
/// émises depuis le thread d'inférence. Il faut pouvoir éteindre
/// l'instrumentation et refaire la mesure, sinon on ne peut pas distinguer le
/// retard de la chaîne ASR du retard causé par son observation.
///
/// Le natif est poussé ICI en plus du démarrage de session
/// (RecitationNotifier._applyDiagnosticCapture) pour que le basculement soit
/// effectif immédiatement, sans avoir à relancer une récitation.
// Plus monté depuis le 2026-08-09 (retiré des Réglages de la v1, cf. le bloc
// de commentaire dans `build`) -- conservé intact pour le rebrancher.
// ignore: unused_element
class _DiagnosticTile extends ConsumerWidget {
  const _DiagnosticTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final on = ref.watch(diagnosticEnabledProvider);
    return _SettingsTile(
      icon: Icons.bug_report_outlined,
      title: t.settingsDiagnosticTitle,
      subtitle: on
          ? t.settingsDiagnosticSubtitleOn
          : t.settingsDiagnosticSubtitleOff,
      color: AppColors.settingsDiagnostic,
      trailing: Switch.adaptive(
        value: on,
        activeColor: AppColors.green700,
        onChanged: (v) {
          ref.read(diagnosticEnabledProvider.notifier).set(v);
          unawaited(ref.read(recitationVerifierProvider).setLogEnabled(v));
        },
      ),
    );
  }
}

/// Suppression de bruit du micro — **éteinte par défaut, délibérément** (voir
/// noiseSuppressProvider pour les trois raisons mesurées le 2026-07-27 :
/// décalage entraînement/inférence, baisse du niveau d'entrée qui aggrave le
/// portier de segmentation à seuil absolu, et surtout le fait que le bruit
/// n'est pas le défaut mesuré). Ce réglage existe pour TRANCHER PAR LA MESURE :
/// réciter deux fois le même passage, avec et sans, et comparer les logs.
///
/// Prend effet au DÉMARRAGE de la prochaine récitation : la valeur est lue à
/// l'ouverture du flux micro, la changer en cours de session ne fait rien.
// Plus monté depuis le 2026-08-09 : « pas efficace » (utilisateur), ce que la
// mesure disait déjà -- le banc du 2026-07-23 donnait 22,8 % de WER sans
// suppression contre 70,2 % avec. Conservé intact.
// ignore: unused_element
class _NoiseSuppressTile extends ConsumerWidget {
  const _NoiseSuppressTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(noiseSuppressProvider);
    return _SettingsTile(
      icon: Icons.noise_control_off_outlined,
      title: 'Suppression de bruit du micro',
      subtitle: on
          ? 'Activée — à comparer avec le réglage éteint avant de la garder'
          : 'Éteinte (recommandé) — le modèle est entraîné sur de l\'audio non filtré',
      color: AppColors.settingsDiagnostic,
      trailing: Switch.adaptive(
        value: on,
        activeColor: AppColors.green700,
        onChanged: (v) => ref.read(noiseSuppressProvider.notifier).set(v),
      ),
    );
  }
}

/// Clips de récitation VÉRIFIÉS CORRECTS (sessions de référence validées),
/// collectés en vue d'un futur mini-LoRA de personnalisation vocale
/// (FONCTIONNALITES_FUTURES.md, "Personnalisation voix -- niveau 3",
/// implémenté 2026-07-12). Export MANUEL uniquement (partage natif) -- aucune
/// synchronisation automatique, donnée vocale sensible.
class _VoiceLoraClipsTile extends StatefulWidget {
  const _VoiceLoraClipsTile();

  @override
  State<_VoiceLoraClipsTile> createState() => _VoiceLoraClipsTileState();
}

class _VoiceLoraClipsTileState extends State<_VoiceLoraClipsTile> {
  final _service = VoiceLoraClipService();
  int? _count;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // Captures de DIAGNOSTIC des récitations depuis le 2026-07-25 (et non plus
  // les clips "vérifiés corrects" du mini-LoRA, objectif abandonné) : on
  // compte/exporte désormais TOUS les enregistrements conservés, cf.
  // VoiceLoraClipService.newRecitationCaptureDir.
  Future<void> _refresh() async {
    final c = await _service.recitationClipCount();
    if (mounted) setState(() => _count = c);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final ok = await _service.exportRecitationCaptures();
    if (!mounted) return;
    setState(() => _exporting = false);
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? t.settingsExportStarted : t.settingsExportCancelled),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final count = _count;
    return _SettingsTile(
      icon: Icons.mic_external_on_rounded,
      title: t.settingsMyClipsTitle,
      subtitle: count == null
          ? t.settingsMyClipsLoading
          : count == 0
              ? t.settingsMyClipsEmpty
              : t.settingsMyClipsCount(count),
      color: AppColors.settingsVoice,
      trailing: _exporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.settingsVoice))
          : const Icon(Icons.ios_share_rounded, color: AppColors.settingsVoice),
      onTap: (count != null && count > 0 && !_exporting) ? _export : null,
    );
  }
}

/// Verdicts CONTESTÉS par l'utilisateur (pouce vers le bas sous l'extrait
/// « Ma voix », `tajwid_help_sheet.dart` -- demande utilisateur 2026-08-07) :
/// des faux positifs confirmés par la personne qui a récité, la matière la
/// plus utile pour recalibrer un futur entraînement. Même contrat que
/// [_VoiceLoraClipsTile] : export MANUEL uniquement (partage natif), aucune
/// synchronisation automatique, donnée vocale sensible.
class _DisputedVerdictsTile extends StatefulWidget {
  const _DisputedVerdictsTile();

  @override
  State<_DisputedVerdictsTile> createState() => _DisputedVerdictsTileState();
}

class _DisputedVerdictsTileState extends State<_DisputedVerdictsTile> {
  final _service = VoiceLoraClipService();
  int? _count;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await _service.disputedClipCount();
    if (mounted) setState(() => _count = c);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final ok = await _service.exportDisputedClips();
    if (!mounted) return;
    setState(() => _exporting = false);
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? t.settingsExportStarted : t.settingsExportCancelled),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final count = _count;
    return _SettingsTile(
      icon: Icons.rate_review_outlined,
      title: t.settingsDisputedTitle,
      subtitle: count == null
          ? t.settingsMyClipsLoading
          : count == 0
              ? t.settingsDisputedEmpty
              : t.settingsDisputedCount(count),
      color: AppColors.settingsVoice,
      trailing: _exporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.settingsVoice))
          : const Icon(Icons.ios_share_rounded, color: AppColors.settingsVoice),
      onTap: (count != null && count > 0 && !_exporting) ? _export : null,
    );
  }
}

class _LocaleSheet extends StatelessWidget {
  final String current;
  final void Function(String) onPick;
  const _LocaleSheet({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.settingsLocaleTitle,
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.settingsLocaleSheetDescription,
              style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.cream.withAlpha(200)),
            ),
            const SizedBox(height: 16),
            for (final (code, label) in const [
              ('ar', 'العربية'),
              ('fr', 'Français'),
              ('en', 'English'),
            ])
              ListTile(
                title: Text(label,
                    style: GoogleFonts.manrope(
                        color: AppColors.cream,
                        fontWeight: code == current ? FontWeight.w700 : FontWeight.normal)),
                trailing: code == current
                    ? const Icon(Icons.check_rounded, color: AppColors.brass)
                    : null,
                onTap: () => onPick(code),
                dense: true,
              ),
          ],
        ),
      );
}

