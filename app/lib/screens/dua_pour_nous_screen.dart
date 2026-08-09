// « Une invocation pour nous » (2026-08-09, demande utilisateur).
//
// ── POURQUOI CET ÉCRAN EXISTE ────────────────────────────────────────────
// Demande, dans ses mots : « fais la page pour demander des du'a pour moi et
// pour mon père [décédé], et fais également des du'a aux utilisateurs pour
// les aider à apprendre et réciter le Coran sans être dérangés par les pubs ».
//
// C'est la contrepartie assumée du choix « pas de publicité, pas de compte,
// pas de collecte » : l'application ne demande ni argent ni attention, elle
// demande une invocation. Elle porte donc DEUX invocations, pas une :
//   - celle qu'on DEMANDE (pour le père défunt de l'auteur, ses parents, sa
//     famille, et ceux qui ont contribué) ;
//   - celle qu'on OFFRE au lecteur (que le Coran lui soit facilité).
//
// L'icône est volontairement `volunteer_activism_rounded` -- l'ancienne icône
// de l'onglet Invocations, que l'utilisateur avait mise de côté « pour les
// dons ». C'est exactement sa place : ici, le don demandé est une du'a.
//
// Les deux textes arabes sont des invocations RAPPORTÉES, pas des
// compositions : la première est le du'a de la prière funéraire (Muslim), la
// seconde celle du souci et de la tristesse (Ahmad). Ne pas les réécrire.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class DuaPourNousScreen extends StatelessWidget {
  const DuaPourNousScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(t.duaPourNousTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 34),
        children: [
          Center(
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.green50,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.green100),
              ),
              child: const Icon(Icons.volunteer_activism_rounded,
                  color: AppColors.green700, size: 30),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t.duaPourNousIntro,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 14, height: 1.65, color: AppColors.ink),
          ),
          const SizedBox(height: 26),

          // ── Ce qu'on demande ────────────────────────────────────────────
          _Titre(t.duaPourNousAskTitle),
          const SizedBox(height: 8),
          Text(
            t.duaPourNousAskBody,
            style: GoogleFonts.manrope(
                fontSize: 13.5, height: 1.7, color: AppColors.inkLight),
          ),
          const SizedBox(height: 16),
          _CarteInvocation(
            arabe: t.duaPourNousDeceasedArabic,
            traduction: t.duaPourNousDeceasedTranslation,
            source: t.duaPourNousDeceasedSource,
          ),

          const SizedBox(height: 28),

          // ── Ce qu'on offre ──────────────────────────────────────────────
          _Titre(t.duaPourNousForYouTitle),
          const SizedBox(height: 8),
          Text(
            t.duaPourNousForYouBody,
            style: GoogleFonts.manrope(
                fontSize: 13.5, height: 1.7, color: AppColors.inkLight),
          ),
          const SizedBox(height: 16),
          _CarteInvocation(arabe: t.duaPourNousForYouArabic),

          const SizedBox(height: 30),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: const BorderSide(color: AppColors.green700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => SharePlus.instance
                .share(ShareParams(text: t.duaPourNousShareText)),
            icon: const Icon(Icons.ios_share_rounded,
                size: 17, color: AppColors.green700),
            label: Text(t.duaPourNousShare,
                style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green700)),
          ),
        ],
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  final String texte;
  const _Titre(this.texte);

  @override
  Widget build(BuildContext context) => Text(
        texte.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      );
}

class _CarteInvocation extends StatelessWidget {
  final String arabe;
  final String? traduction;
  final String? source;
  const _CarteInvocation(
      {required this.arabe, this.traduction, this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        // Même dégradé vert que le verset en cours de lecture et le bandeau
        // de la Bismillah -- code couleur unique de l'app (2026-08-09).
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.readingCursorBg, AppColors.readingCursorBgEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            arabe,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 25, height: 2.0, color: AppColors.green900),
          ),
          if (traduction != null) ...[
            const SizedBox(height: 12),
            Text(
              traduction!,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                  color: AppColors.inkLight),
            ),
          ],
          if (source != null) ...[
            const SizedBox(height: 8),
            Text(
              source!,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 11, color: AppColors.green700),
            ),
          ],
        ],
      ),
    );
  }
}
