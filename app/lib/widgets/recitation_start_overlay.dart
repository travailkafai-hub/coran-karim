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
    final countdown = switch (stage) {
      RecitationStartStage.countdown3 => '3',
      RecitationStartStage.countdown2 => '2',
      RecitationStartStage.countdown1 => '1',
      _ => null,
    };
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
                    Text(
                      countdown ?? title,
                      style: GoogleFonts.fraunces(
                        fontSize:
                            countdown != null ||
                                stage == RecitationStartStage.go
                            ? 82
                            : 28,
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
