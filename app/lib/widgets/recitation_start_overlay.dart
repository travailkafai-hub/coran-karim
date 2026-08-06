import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../services/recitation_start_sequence.dart';
import '../theme/app_theme.dart';

class RecitationStartOverlay extends StatelessWidget {
  final RecitationStartStage stage;

  const RecitationStartOverlay({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // ── L'ISTI'ADHA REMPLACE LE DECOMPTE 3-2-1 (demande utilisateur) ──────
    //
    // « au lieu de 1 2 3 GO, remplace avec une belle ecriture style arabe
    // esquisse andalouse : قل أعوذ بالله من الشيطان الرجيم ».
    //
    // Le decompte chiffre etait un artefact d'application ; on ouvre une
    // recitation du Coran par l'isti'adha, pas par un chronometre. Elle se
    // devoile en trois temps, au rythme du decompte qu'elle remplace -- la
    // sequence de demarrage (chargement, micro) n'est pas touchee, seul son
    // affichage change.
    final isti3adha = switch (stage) {
      RecitationStartStage.countdown3 => 'أَعُوذُ',
      RecitationStartStage.countdown2 => 'أَعُوذُ بِٱللَّهِ',
      RecitationStartStage.countdown1 =>
        'أَعُوذُ بِٱللَّهِ مِنَ ٱلشَّيْطَٰنِ ٱلرَّجِيمِ',
      _ => null,
    };
    final countdown = isti3adha;
    final title = switch (stage) {
      RecitationStartStage.loadingModel => t.karaokeLoadingModel,
      RecitationStartStage.countdown3 ||
      RecitationStartStage.countdown2 ||
      RecitationStartStage.countdown1 => t.karaokeGetReady,
      RecitationStartStage.startingCapture => t.karaokePreparingMicrophone,
      RecitationStartStage.go => t.karaokeGo,
      RecitationStartStage.modelUnavailable => t.karaokeModelUnavailable,
    };
    final busy =
        stage == RecitationStartStage.loadingModel ||
        stage == RecitationStartStage.startingCapture;
    final semanticLabel = countdown == null ? title : '$title — $countdown';

    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: AppColors.green900.withValues(alpha: 0.94),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(stage),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        color: AppColors.brassLight,
                        strokeWidth: 3,
                      ),
                    )
                  else
                    // Scheherazade New pour l'arabe : c'est la police
                    // calligraphique deja utilisee pour le texte coranique
                    // (cf. karaoke/mushaf). Utiliser Fraunces, taillee pour le
                    // latin, rendrait un arabe sans liaisons ni proportions.
                    isti3adha != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(
                              isti3adha,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.rtl,
                              style: GoogleFonts.scheherazadeNew(
                                fontSize: 46,
                                height: 1.9,
                                color: AppColors.brassLight,
                              ),
                            ),
                          )
                        : Text(
                            title,
                            style: GoogleFonts.fraunces(
                              fontSize:
                                  stage == RecitationStartStage.go ? 82 : 28,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brassLight,
                            ),
                          ),
                  if (busy || countdown != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppColors.cream,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
