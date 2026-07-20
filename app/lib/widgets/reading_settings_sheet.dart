import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final scale = ref.watch(textScaleProvider);
    final speed = ref.watch(autoScrollSpeedProvider);
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
                  'AFFICHAGE',
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
            const SizedBox(height: 20),
            Text(
              'DÉFILEMENT AUTOMATIQUE',
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Le texte défile tout seul à la vitesse choisie — pratique pour '
              'lire sans les mains. Un glissement manuel l\'arrête.',
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in AutoScrollSpeed.values)
                  ChoiceChip(
                    label: Text(_speedLabel(s)),
                    selected: speed == s,
                    selectedColor: AppColors.green700,
                    labelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: speed == s ? AppColors.cream : AppColors.ink,
                    ),
                    backgroundColor: AppColors.cream200,
                    onSelected: (_) {
                      ref.read(autoScrollSpeedProvider.notifier).state = s;
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            // Vitesse de lecture (audio) -- regroupee ici avec le defilement
            // et la repetition (retour utilisateur 2026-07-19 : "répétition
            // et vitesse seront dans la partie lecture"), retiree des
            // Reglages globaux. DIFFERENTE du "defilement automatique"
            // ci-dessus (celui-la fait scroller le TEXTE, celle-ci change la
            // vitesse de l'AUDIO du reciteur).
            const SizedBox(height: 20),
            Text(
              'VITESSE DE LECTURE (AUDIO)',
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in speedOptions)
                  ChoiceChip(
                    label: Text('${s}×'),
                    selected: playbackSpeed == s,
                    selectedColor: AppColors.green700,
                    labelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: playbackSpeed == s ? AppColors.cream : AppColors.ink,
                    ),
                    backgroundColor: AppColors.cream200,
                    onSelected: (_) =>
                        ref.read(playerProvider.notifier).setSpeed(s),
                  ),
              ],
            ),
            // Répétition / boucles -- regroupees ici avec le defilement
            // (retour utilisateur 2026-07-19 : "rajoute via reglage les
            // modes de lecture le defilement les repetitions les boucles"),
            // au lieu de rester uniquement dans l'ecran Reglages global,
            // loin de la lecture en cours.
            const SizedBox(height: 20),
            Text(
              'RÉPÉTITION / BOUCLES',
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Répète chaque verset (ou toute la sourate) en boucle avant '
              'de passer au suivant.',
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (mode, count, label) in const [
                  (RepeatMode.off, 0, 'Désactivé'),
                  (RepeatMode.verse, 3, 'Verset × 3'),
                  (RepeatMode.verse, 5, 'Verset × 5'),
                  (RepeatMode.verse, 10, 'Verset × 10'),
                  (RepeatMode.verse, 0, 'Verset × ∞'),
                  (RepeatMode.surah, 0, 'Sourate entière'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: repeatMode == mode &&
                        (mode != RepeatMode.verse || repeatCount == count),
                    selectedColor: AppColors.green700,
                    labelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: repeatMode == mode ? AppColors.cream : AppColors.ink,
                    ),
                    backgroundColor: AppColors.cream200,
                    onSelected: (_) {
                      final notifier = ref.read(playerProvider.notifier);
                      notifier.setRepeatMode(mode);
                      notifier.setRepeatCount(count);
                    },
                  ),
              ],
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _speedLabel(AutoScrollSpeed s) => switch (s) {
        AutoScrollSpeed.off => 'Arrêté',
        AutoScrollSpeed.slow => 'Lent',
        AutoScrollSpeed.normal => 'Normal',
        AutoScrollSpeed.fast => 'Rapide',
      };
}
