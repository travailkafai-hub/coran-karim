import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/player_state_model.dart' show RepeatMode;
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

/// Réglages de lecture (demande utilisateur 2026-07-06) : taille du texte
/// ("zoomer") et défilement automatique à vitesse réglable ("lire le Coran
/// et ça scroll selon sa vitesse"). Regroupés dans un même tiroir "Plus".
void showReadingSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cream,
    // isScrollControlled + hauteur bornée : depuis l'ajout des sections
    // "vitesse de lecture (audio)" et "répétition / boucles" (2026-07-19), le
    // contenu dépasse la hauteur par défaut d'un bottom sheet (constaté :
    // "BOTTOM OVERFLOWED BY 284 PIXELS"). Le contenu défile désormais dans la
    // limite de 85% de l'écran au lieu de déborder.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _ReadingSettingsSheet(),
  );
}

class _ReadingSettingsSheet extends ConsumerWidget {
  const _ReadingSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final scale = ref.watch(textScaleProvider);
    final kindleMode = ref.watch(kindleModeProvider);
    final kindleAutoTurn = ref.watch(kindleAutoTurnProvider);
    final kindlePageSeconds = ref.watch(kindlePageSecondsProvider);
    final playerState = ref.watch(playerProvider);
    final repeatMode = playerState.repeatMode;
    final repeatCount = playerState.repeatCount;
    final playbackSpeed = playerState.speed;
    const speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return SafeArea(
      child: ConstrainedBox(
        // Plafonne à 85% de l'écran ; au-delà, le contenu défile (cf.
        // SingleChildScrollView) plutôt que de déborder.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.readingSettingsDisplaySection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.text_decrease_rounded),
                  color: AppColors.green800,
                  onPressed: () => ref
                      .read(textScaleProvider.notifier)
                      .set(scale - 0.1),
                ),
                Expanded(
                  child: Slider(
                    value: scale,
                    min: kTextScaleMin,
                    max: kTextScaleMax,
                    divisions: 9,
                    activeColor: AppColors.green700,
                    label: '${(scale * 100).round()}%',
                    onChanged: (v) =>
                        ref.read(textScaleProvider.notifier).set(v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase_rounded),
                  color: AppColors.green800,
                  onPressed: () => ref
                      .read(textScaleProvider.notifier)
                      .set(scale + 0.1),
                ),
              ],
            ),
            Center(
              child: Text(
                'بِسْمِ ٱللَّهِ',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                  fontSize: 26 * scale,
                  color: AppColors.ink,
                ),
              ),
            ),
            // Défilement automatique (off/slow/normal/fast) RETIRÉ
            // 2026-08-01 (demande utilisateur : "plus raison d'être" une fois
            // le mode Kindle en place, qui couvre ce besoin -- cf. §Kindle
            // plus bas, tournage de page automatique).
            //
            // Vitesse de lecture (audio) -- curseur plutôt que des puces
            // fixes (demande utilisateur 2026-08-01 : "un curseur avec les
            // choix, ça optimise l'espace"). DIFFÉRENTE de l'ancien
            // "défilement automatique" (qui faisait scroller le TEXTE) :
            // celle-ci change la vitesse de l'AUDIO du réciteur.
            const SizedBox(height: 20),
            Text(
              t.readingSettingsPlaybackSpeedSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${playbackSpeed.toStringAsFixed(2)}×',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
            ),
            Slider(
              value: playbackSpeed,
              min: speedOptions.first,
              max: speedOptions.last,
              divisions: 6, // pas de 0.25 entre 0.5 et 2.0
              activeColor: AppColors.green700,
              onChanged: (v) => ref.read(playerProvider.notifier).setSpeed(v),
            ),
            // Répétition / boucles -- curseur pour le nombre de répétitions
            // (même raison que ci-dessus), "Illimité"/"Sourate entière"
            // restent des puces car ce ne sont pas des points sur une échelle
            // numérique continue.
            const SizedBox(height: 12),
            Text(
              t.readingSettingsRepeatSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.readingSettingsRepeatDescription,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              repeatMode == RepeatMode.off
                  ? t.readingSettingsRepeatOff
                  : repeatMode == RepeatMode.surah
                      ? t.readingSettingsRepeatSurah
                      : repeatCount == 0
                          ? t.readingSettingsRepeatVerseInfinite
                          : t.readingSettingsRepeatVerseCount(repeatCount),
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
            ),
            Slider(
              value: (repeatMode == RepeatMode.verse ? repeatCount : 0)
                  .clamp(0, 20)
                  .toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              activeColor: AppColors.green700,
              onChanged: (v) {
                final notifier = ref.read(playerProvider.notifier);
                notifier.setRepeatMode(v == 0 ? RepeatMode.off : RepeatMode.verse);
                notifier.setRepeatCount(v.round());
              },
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t.readingSettingsRepeatVerseInfinite),
                  selected: repeatMode == RepeatMode.verse && repeatCount == 0,
                  selectedColor: AppColors.green700,
                  labelStyle: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: repeatMode == RepeatMode.verse && repeatCount == 0
                        ? AppColors.cream
                        : AppColors.ink,
                  ),
                  backgroundColor: AppColors.cream200,
                  onSelected: (_) {
                    final notifier = ref.read(playerProvider.notifier);
                    notifier.setRepeatMode(RepeatMode.verse);
                    notifier.setRepeatCount(0);
                  },
                ),
                ChoiceChip(
                  label: Text(t.readingSettingsRepeatSurah),
                  selected: repeatMode == RepeatMode.surah,
                  selectedColor: AppColors.green700,
                  labelStyle: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: repeatMode == RepeatMode.surah
                        ? AppColors.cream
                        : AppColors.ink,
                  ),
                  backgroundColor: AppColors.cream200,
                  onSelected: (_) {
                    final notifier = ref.read(playerProvider.notifier);
                    notifier.setRepeatMode(RepeatMode.surah);
                    notifier.setRepeatCount(0);
                  },
                ),
              ],
            ),
            // Mode Kindle (demande utilisateur 2026-08-01) : thème repos-yeux
            // + navigation par pages, regroupé ici avec les autres réglages
            // de lecture -- même logique que le défilement et la répétition
            // ci-dessus (§ commentaires 2026-07-19/20).
            const SizedBox(height: 20),
            Text(
              t.readingSettingsKindleSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.readingSettingsKindleDescription,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                t.readingSettingsKindleToggle,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              value: kindleMode,
              activeColor: AppColors.kindleAccent,
              onChanged: (v) => ref.read(kindleModeProvider.notifier).set(v),
            ),
            if (kindleMode) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.readingSettingsKindleAutoTurn,
                  style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink),
                ),
                value: kindleAutoTurn,
                activeColor: AppColors.kindleAccent,
                onChanged: (v) =>
                    ref.read(kindleAutoTurnProvider.notifier).state = v,
              ),
              if (kindleAutoTurn) ...[
                Text(
                  t.readingSettingsKindleSpeed(kindlePageSeconds.round()),
                  style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
                ),
                Slider(
                  value: kindlePageSeconds,
                  min: kKindlePageSecondsMin,
                  max: kKindlePageSecondsMax,
                  divisions: (kKindlePageSecondsMax - kKindlePageSecondsMin).round(),
                  activeColor: AppColors.kindleAccent,
                  onChanged: (v) =>
                      ref.read(kindlePageSecondsProvider.notifier).set(v),
                ),
              ],
            ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
