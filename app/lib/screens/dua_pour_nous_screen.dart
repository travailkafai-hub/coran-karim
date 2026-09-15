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
// ⚠️ CE QUI PRÉCÈDE N'EST PLUS EXACT DEPUIS LE 2026-09-14, et on le laisse
// pour qu'on sache ce que l'écran A ÉTÉ. L'invocation OFFERTE au lecteur a été
// retirée sur demande (« pour Dua, enlève la section pour vous »), et le
// PARTAGE a pris sa place : l'écran porte donc aujourd'hui UNE invocation
// demandée, et une invitation à faire connaître l'application. Les clés de
// l'invocation retirée restent définies dans les trois langues.
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
// ── PARTAGE REMIS EN SERVICE (2026-09-14, demande utilisateur) ────────────
// Il avait été « gardé comme fonctionnalité future » le 2026-08-09 ; il revient
// en TÊTE de cet écran, avec un motif explicite : « participer aux hassanate en
// partageant l'application ». `url_launcher` s'ajoute pour l'entrée WhatsApp
// directe (`https://wa.me/?text=`), demandée nommément.
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart' show kLienPlayStore;

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
      // ── UNE SEULE PAGE, SANS DÉFILEMENT (2026-09-14) ─────────────────────
      //
      // Demande utilisateur : « retravaille cet écran, je veux qu'il soit
      // attractif, incitant à partager l'application, consolidé pour que ça
      // tienne dans une page ».
      //
      // Ce qui a été retiré pour y arriver, et pourquoi ce n'est pas une
      // perte : le gros rond d'icône isolé (44 dp pour ne rien dire de plus
      // que l'icône désormais posée DANS la carte de partage) et les grands
      // écarts verticaux hérités d'un écran qui défilait. Aucun texte n'a été
      // coupé.
      //
      // ⚠️ LE `ListView` EST CONSERVÉ, et c'est délibéré : « tient dans une
      // page » est vrai sur cet appareil-ci et aux tailles de police par
      // défaut. Sur un écran plus court, ou avec l'agrandissement de texte du
      // système, la même mise en page déborderait -- un `Column` nu la ferait
      // alors DÉCOUPER (le bandeau jaune et noir), là où la liste laisse
      // simplement défiler les quelques pixels manquants. On consolide la
      // hauteur, on ne supprime pas la soupape.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        children: [
          // ── PHRASE D'INTRODUCTION RETIRÉE (2026-09-14) ──────────────────
          //
          // Demande utilisateur : « enlève "cette application est écrite",
          // on gagne deux lignes ».
          //
          // Deux lignes gagnées en haut de page, et rien de perdu : la carte
          // de partage juste dessous dit déjà à quoi sert l'application, et le
          // fait en demandant quelque chose. `duaPourNousIntro` reste définie
          // dans les trois langues et n'est plus affichée nulle part : rien
          // n'est perdu, la remonter tient à décommenter la ligne ci-dessous.
          //   Text(t.duaPourNousIntro, textAlign: TextAlign.center, ...),

          // ── LE PARTAGE EST LE SUJET DE L'ÉCRAN, PAS UN ENCART ───────────
          //
          // C'est la seule chose que cette page DEMANDE de faire : l'invocation
          // se lit, le partage s'agit. Il prend donc le haut, la couleur, et le
          // seul bouton plein de l'écran.
          const _CartePartage(),

          const SizedBox(height: 22),

          // ── ON DEMANDE, SANS PRÉAMBULE (2026-09-14) ─────────────────────
          //
          // Demande utilisateur : « "si elle vous est utile" : directement on
          // demande l'invocation ». Le titre posait une CONDITION avant la
          // demande -- et une demande précédée d'une condition se lit comme une
          // négociation. On demande, et celui qui lit décide.
          //
          // `duaPourNousAskTitle` reste définie dans les trois langues.
          //   _Titre(t.duaPourNousAskTitle),
          Text(
            t.duaPourNousAskBody,
            style: GoogleFonts.manrope(
                fontSize: 13, height: 1.6, color: AppColors.inkLight),
          ),
          const SizedBox(height: 12),
          _CarteInvocation(
            arabe: t.duaPourNousDeceasedArabic,
            traduction: t.duaPourNousDeceasedTranslation,
            source: t.duaPourNousDeceasedSource,
          ),

          // ── BLOC « ET POUR VOUS » RETIRE (2026-09-14) ───────────────────
          //
          // Demande utilisateur : « pour Dua, enlève la section pour vous ».
          // Il portait l'invocation OFFERTE au lecteur (celle du souci et de
          // la tristesse, Ahmad). Les clés `duaPourNousForYou*` restent
          // définies dans les trois langues : rien n'est perdu, et le bloc
          // tient en cinq lignes si on le remonte un jour.
          // Code retiré, gardé pour mémoire :
          //   _Titre(t.duaPourNousForYouTitle),
          //   Text(t.duaPourNousForYouBody, ...),
          //   _CarteInvocation(arabe: t.duaPourNousForYouArabic),
        ],
      ),
    );
  }
}

/// Plus monté depuis le 2026-09-14 (le seul titre de section a été retiré),
/// conservé parce que les deux blocs commentés plus haut le réutilisent tel
/// quel si on les remonte un jour.
// ignore: unused_element
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
            // 25 -> 22 et interligne 2,0 -> 1,85 (2026-09-14) : la seule
            // retouche de taille de la consolidation, et elle porte sur les
            // deux lignes les plus hautes de la page. Le texte arabe reste
            // nettement le plus grand de l'ecran -- c'est lui qu'on lit.
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, height: 1.85, color: AppColors.green900),
          ),
          if (traduction != null) ...[
            const SizedBox(height: 10),
            Text(
              traduction!,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.inkLight),
            ),
          ],
          if (source != null) ...[
            const SizedBox(height: 6),
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

/// Le bloc « Participez aux hassanate » — la seule chose que cet écran demande
/// au lecteur de FAIRE (2026-09-14).
///
/// ── DEUX BOUTONS, PUIS UN SEUL (le même jour) ───────────────────────────────
///
/// La première version proposait un bouton WhatsApp vert vif et un bouton
/// « Autre moyen ». Constat de l'utilisateur : « c'est moche [...] ne distingue
/// pas WhatsApp ou autre, juste icône ».
///
/// Il a raison au-delà de l'esthétique : nommer WhatsApp, c'était refaire à la
/// main ce que le sélecteur de partage d'Android fait déjà mieux — il connaît
/// les applications RÉELLEMENT installées, dans l'ordre où la personne s'en
/// sert. Le vert de WhatsApp jurait en plus avec toute la palette de l'app, et
/// mettait en avant une marque tierce sur une page qui parle d'invocations.
///
/// Un seul bouton, donc, avec l'icône de partage du système.
class _CartePartage extends StatelessWidget {
  const _CartePartage();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // Le LIEN est ce qui compte : sans lui, le message partagé ne mène nulle
    // part et le destinataire doit chercher l'application lui-même.
    final texte = '${t.duaPourNousShareText}\n\n$kLienPlayStore';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        // Le vert profond de l'app, et non le vert pâle des cartes ordinaires :
        // c'est le seul bloc de la page qui appelle une action, il doit se
        // distinguer au premier coup d'œil de ce qui se lit.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.green800, AppColors.green900],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.brass.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.brass.withValues(alpha: .16),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brass.withValues(alpha: .5)),
            ),
            child: const Icon(Icons.volunteer_activism_rounded,
                color: AppColors.brassLight, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            t.duaPourNousHassanatTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: AppColors.brassLight),
          ),
          const SizedBox(height: 8),
          Text(
            t.duaPourNousHassanatBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 13, height: 1.6, color: AppColors.cream),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            // BOUTON PLEIN, et le seul de l'écran : un contour se lit comme une
            // action secondaire, or c'est l'action principale de la page.
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: AppColors.green900,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(text: texte)),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(t.duaPourNousShare,
                  style: GoogleFonts.manrope(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          // ── CE QU'ON DIT EN PARTAGEANT (2026-09-14) ─────────────────────
          //
          // Trois arguments, sous le bouton et non au-dessus : ils ne servent
          // pas à convaincre de lire la page, mais à donner au lecteur ce
          // qu'il RÉPÉTERA en passant le lien. « Je t'envoie une app de Coran »
          // ne se transmet pas ; « aucune pub, aucun compte, aucun traceur »
          // se transmet.
          //
          // Formulation reprise mot pour mot d'`onboardingPrivacyBody`, déjà
          // relue et validée : inventer une variante ici ferait deux promesses
          // légèrement différentes sur la même chose.
          Text(
            t.duaPourNousArguments,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 11.5,
                letterSpacing: .2,
                color: AppColors.cream.withValues(alpha: .72)),
          ),
        ],
      ),
    );
  }
}
