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
    // « au lieu de 1 2 3 GO, remplace avec une belle ecriture style arabe » puis
    // « en une seule fois, et enleve le GO, ca se declenche automatiquement ».
    //
    // Le decompte chiffre etait un artefact d'application ; on ouvre une
    // recitation du Coran par l'isti'adha, pas par un chronometre. Elle
    // s'affiche ENTIERE, sans devoilement progressif : la formule se lit d'un
    // trait, la couper en trois en faisait de nouveau un decompte.
    //
    // Le « GO » disparait aussi : la capture demarre toute seule, l'annoncer
    // n'apporte rien et rompt le ton. L'ecran d'attente porte donc une seule
    // chose du debut a la fin.
    //
    // La SEQUENCE n'est pas touchee (chargement du modele, ouverture du micro,
    // memes etapes, memes durees) -- seul son affichage change.
    //
    // ── ETENDUE A TOUTE LA SEQUENCE, MODELE INCLUS (demande utilisateur) ──
    //
    // « je veux a3oudo billah pour cacher le chargement du modele ; une fois
    // le modele charge, on enleve a3oudo billah ». La formule n'apparaissait
    // qu'a partir du decompte, PAS pendant `loadingModel` ni `startingCapture`
    // -- deux trous dans la sequence. Le chargement technique restait donc
    // visible en clair, et la formule DISPARAISSAIT puis REVENAIT entre le
    // decompte et le « go » (retiree a `startingCapture`, remise a `go`) :
    // l'AnimatedSwitcher rejouait sa transition d'entree pour le meme texte,
    // ce qui donnait l'impression qu'elle se rechargeait plusieurs fois.
    //
    // Elle couvre maintenant tout le trajet (sauf l'echec de chargement) :
    // un seul affichage continu, du premier instant jusqu'au « go ».
    //
    // ── NUANCE (2026-08-09, demande utilisateur) ───────────────────────
    //
    // « toujours trois ecrans » (chargement modele / decompte / preparation
    // micro) puis « pas besoin de montrer que le modele charge, ca doit etre
    // en arriere-plan ». Ce widget sait TOUJOURS peindre `loadingModel` (le
    // switch juste en dessous ne change pas) : l'ecran de recitation
    // (`karaoke_recitation_screen.dart`) ne monte simplement plus ce widget
    // tant que le stage vaut `loadingModel` -- l'ecran normal reste visible,
    // le chargement se fait sans overlay, et cette page-ci n'apparait qu'au
    // decompte, modele deja pret. Le cas `loadingModel` reste gere ICI pour
    // ne pas casser un futur appelant qui voudrait le montrer.
    const isti3adhaTexte = 'أَعُوذُ بِٱللَّهِ مِنَ ٱلشَّيْطَٰنِ ٱلرَّجِيمِ';
    final isti3adha = switch (stage) {
      RecitationStartStage.loadingModel ||
      RecitationStartStage.countdown3 ||
      RecitationStartStage.countdown2 ||
      RecitationStartStage.countdown1 ||
      RecitationStartStage.startingCapture ||
      RecitationStartStage.go => isti3adhaTexte,
      _ => null,
    };
    final countdown = isti3adha;
    final title = switch (stage) {
      RecitationStartStage.loadingModel => t.karaokeLoadingModel,
      // Plus de « Preparez-vous » ni de « GO » sous la formule : elle se
      // suffit, et un sous-titre y remettrait le decompte qu'on retire.
      RecitationStartStage.countdown3 ||
      RecitationStartStage.countdown2 ||
      RecitationStartStage.countdown1 ||
      RecitationStartStage.go => '',
      RecitationStartStage.startingCapture => t.karaokePreparingMicrophone,
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
                // MEME cle pour toutes les etapes qui portent la formule :
                // sinon l'AnimatedSwitcher la fait re-entrer a chaque etape et
                // elle clignote trois fois.
                key: ValueKey(isti3adha ?? stage),
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LA FORMULE D'ABORD, TOUJOURS. Le rond de progression
                  // ne la remplace plus -- il se glisse DESSOUS pendant les
                  // etapes techniques (chargement, micro). C'est ce
                  // remplacement qui la faisait disparaitre puis revenir.
                  isti3adha != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(
                              isti3adha,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.rtl,
                              // ── LE CHOIX DE LA POLICE ───────────────
                              //
                              // L'utilisateur a montre deux calligraphies
                              // THULUTH (composition compacte, hampes hautes).
                              // Aucune police libre ne fait du vrai thuluth
                              // compose, mais `arefRuqaa` en est la famille --
                              // ruqaa/thuluth, dessinee par Abdullah Aref --
                              // et c'est de loin la plus proche des trois
                              // candidates disponibles ici :
                              //   arefRuqaa      ruqaa/thuluth  <- retenue
                              //   amiri          naskh classique
                              //   scheherazadeNew naskh de lecture (le texte
                              //                   coranique de l'app)
                              // En gras : le trait plein est ce qui rapproche
                              // le plus du modele montre.
                              style: GoogleFonts.arefRuqaa(
                                fontSize: 40,
                                height: 2.1,
                                fontWeight: FontWeight.w700,
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
                  if (busy) ...[
                    const SizedBox(height: 26),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        color: AppColors.brassLight,
                        strokeWidth: 2,
                      ),
                    ),
                  ],
                  if ((busy || countdown != null) && title.isNotEmpty) ...[
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
