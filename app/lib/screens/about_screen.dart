// Écran « À PROPOS » — identité de l'app, ce qu'elle fait des données de
// l'utilisateur, avertissement sur le texte produit par le modèle de langage,
// sources et licences.
//
// ── POURQUOI CET ÉCRAN EXISTE (2026-08-09) ───────────────────────────────
// La tuile « À propos » des Réglages existait déjà... SANS `onTap` : elle
// n'ouvrait rien, et son sous-titre annonçait « Whisper » alors que la chaîne
// de vérification tourne sur FastConformer CTC depuis longtemps.
//
// Une application qui capte le micro, lit la position et produit du texte
// d'explication religieuse par un modèle de langage ne peut pas être publiée
// sans dire, DANS l'app :
//   1. ce qu'elle enregistre, où ça reste, comment l'effacer ;
//   2. ce que vaut le texte généré (aucune autorité religieuse) et comment en
//      signaler un mauvais — la politique « IA générative » de Google Play
//      exige ce moyen de signalement dans l'application ;
//   3. sous quelles conditions vivent les composants embarqués. La licence de
//      Gemma impose en particulier de TRANSMETTRE ses conditions d'utilisation
//      à l'utilisateur final : ce n'est pas une politesse, c'est la condition
//      de la redistribution du modèle.
//
// Les licences des paquets Dart/Flutter ne sont PAS recopiées à la main ici :
// `showLicensePage` les collecte déjà toutes, exactement, depuis les paquets
// eux-mêmes. Ce fichier n'ajoute au registre que ce qui vient d'AILLEURS que
// pub.dev (modèles ASR/LLM, ONNX Runtime, polices) — sinon la liste affichée
// mentirait par omission.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_log.dart';
import '../theme/app_theme.dart';

/// Version affichée à l'utilisateur. **À garder synchronisée avec le champ
/// `version:` de `pubspec.yaml`.**
///
/// Pas de `package_info_plus` : cela ajouterait une dépendance (et un canal
/// de plateforme) pour lire une valeur déjà connue à la compilation. Le prix
/// est cette synchronisation manuelle — assumée et signalée ici plutôt que
/// masquée.
const String kAppVersion = '1.0.0';
const String kAppBuild = '1';

/// Adresse de contact affichée pour signaler un texte généré inapproprié.
///
/// ⚠️ **VIDE = la section de signalement est masquée.** À renseigner AVANT
/// toute publication : la politique « IA générative » de Google Play exige un
/// moyen, accessible DANS l'application, de signaler le contenu produit par le
/// modèle. Laissée vide volontairement — choisir d'exposer une adresse
/// personnelle ou une adresse de support dédiée est une décision de l'éditeur,
/// pas de l'outil qui écrit cet écran.
const String kContactEmail = '';

/// Notices des composants qui ne viennent PAS de pub.dev — `showLicensePage`
/// ne peut pas les découvrir tout seul.
///
/// Enregistré une seule fois (le registre est global et `showLicensePage`
/// relit tous les fournisseurs à chaque ouverture : sans ce garde, rouvrir
/// l'écran dupliquerait chaque notice).
var _licencesEnregistrees = false;

void enregistrerLicencesTierces() {
  if (_licencesEnregistrees) return;
  _licencesEnregistrees = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Gemma (modèle de langage embarqué)'],
      'Gemma is provided under and subject to the Gemma Terms of Use found at '
      'ai.google.dev/gemma/terms\n\n'
      "Le tuteur de cette application utilise un modèle Gemma de Google, "
      "affiné pour l'explication de versets. Son utilisation est soumise aux "
      "conditions ci-dessus ainsi qu'à la Gemma Prohibited Use Policy "
      '(ai.google.dev/gemma/prohibited_use_policy).',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Modèle de reconnaissance de récitation'],
      "La vérification de la récitation repose sur un modèle FastConformer CTC "
      "affiné pour la récitation coranique à partir du modèle de base "
      "nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1 (NVIDIA NeMo). "
      "Attribution à NVIDIA au titre de la licence du modèle de base.",
    );
    yield const LicenseEntryWithLineBreaks(
      ['ONNX Runtime'],
      'ONNX Runtime — Copyright (c) Microsoft Corporation. Distribué sous '
      'licence MIT. Utilisé pour exécuter les modèles de reconnaissance sur '
      "l'appareil.",
    );
    yield const LicenseEntryWithLineBreaks(
      ['Amiri, Scheherazade New (polices arabes)'],
      'Polices distribuées sous SIL Open Font License, Version 1.1 '
      '(scripts.sil.org/OFL). Amiri © Khaled Hosny. Scheherazade New © SIL '
      'International.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Textes et audio du Coran'],
      "Texte coranique, découpage en versets/pages et récitations audio "
      "fournis par Quran.com (Quran Foundation) — quran.com. Audio des "
      "invocations : hisnmuslim.com.",
    );
  });
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    enregistrerLicencesTierces();
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text(t.aboutTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Entete(tagline: t.aboutTagline),
          const SizedBox(height: 20),

          // ── 1. Données personnelles ─────────────────────────────────────
          _Section(
            titre: t.aboutSectionPrivacy,
            enfants: [
              _Paragraphe(t.aboutPrivacyIntro),
              const SizedBox(height: 12),
              _Puce(icone: Icons.mic_rounded, texte: t.aboutPrivacyMic),
              _Puce(
                  icone: Icons.location_on_rounded,
                  texte: t.aboutPrivacyLocation),
              _Puce(
                  icone: Icons.bug_report_rounded,
                  texte: t.aboutPrivacyDiagnostic),
              _Puce(icone: Icons.cloud_off_rounded, texte: t.aboutPrivacyNetwork),
            ],
          ),

          // ── 2. Avertissement sur le texte généré ────────────────────────
          _Section(
            titre: t.aboutSectionAi,
            // Fond ambré : cet encadré n'est pas une information de plus, c'est
            // une mise en garde. Elle doit se distinguer au premier coup d'œil
            // du reste de la page.
            fond: const Color(0xFFFDF4E0),
            bordure: AppColors.brass,
            enfants: [
              _Paragraphe(t.aboutAiWarning),
              if (kContactEmail.isNotEmpty) ...[
                const SizedBox(height: 14),
                _BlocSignalement(
                  titre: t.aboutAiReportTitle,
                  corps: t.aboutAiReportBody(kContactEmail),
                  confirmation: t.aboutCopied,
                ),
              ],
            ],
          ),

          // ── 3. Sources ──────────────────────────────────────────────────
          _Section(
            titre: t.aboutSectionSources,
            enfants: [
              _Puce(
                  icone: Icons.menu_book_rounded, texte: t.aboutSourceQuran),
              _Puce(
                  icone: Icons.volunteer_activism_rounded,
                  texte: t.aboutSourceDuas),
              _Puce(
                  icone: Icons.access_time_rounded, texte: t.aboutSourcePrayer),
            ],
          ),

          // ── 4. Licences ─────────────────────────────────────────────────
          _Section(
            titre: t.aboutSectionLicenses,
            enfants: [
              _Paragraphe(t.aboutLicensesIntro),
              const SizedBox(height: 4),
              // Notice Gemma reproduite EN CLAIR sur la page, en plus du
              // registre : sa licence exige qu'elle soit transmise, pas
              // qu'elle soit trouvable au bout de deux écrans.
              const _NoticeBrute(
                'Gemma is provided under and subject to the Gemma Terms of Use '
                'found at ai.google.dev/gemma/terms',
              ),
              const SizedBox(height: 12),
              _BoutonLicences(libelle: t.aboutLicensesAll),
            ],
          ),
        ],
      ),
    );
  }
}

class _Entete extends StatelessWidget {
  final String tagline;
  const _Entete({required this.tagline});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.green800,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.menu_book_rounded,
              color: AppColors.brassLight, size: 36),
        ),
        const SizedBox(height: 12),
        Text(t.appTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 26,
                color: AppColors.green900,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tagline,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 13, color: AppColors.inkLight, height: 1.4)),
        const SizedBox(height: 8),
        Text(
          t.aboutVersionLine(kAppVersion, kAppBuild),
          style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.green700,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4),
        ),
        // Identifiant du code embarqué — la même chaîne que celle inscrite en
        // tête de chaque journal de diagnostic. Sans elle, un utilisateur qui
        // signale un problème ne peut pas dire quelle version il utilise, et
        // un journal reçu ne peut pas être rattaché à un binaire.
        Text(
          DiagnosticLog.buildTag,
          style: GoogleFonts.manrope(
              fontSize: 10, color: AppColors.inkLight.withAlpha(140)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String titre;
  final List<Widget> enfants;
  final Color? fond;
  final Color? bordure;
  const _Section({
    required this.titre,
    required this.enfants,
    this.fond,
    this.bordure,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(titre.toUpperCase(),
                  style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.green700,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: fond ?? Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: bordure ?? AppColors.cream300,
                    width: bordure == null ? 1 : 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: enfants,
              ),
            ),
          ],
        ),
      );
}

class _Paragraphe extends StatelessWidget {
  final String texte;
  const _Paragraphe(this.texte);
  @override
  Widget build(BuildContext context) => Text(texte,
      style: GoogleFonts.manrope(
          fontSize: 13, color: AppColors.ink, height: 1.55));
}

class _Puce extends StatelessWidget {
  final IconData icone;
  final String texte;
  const _Puce({required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icone, size: 17, color: AppColors.green600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(texte,
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.ink, height: 1.55)),
            ),
          ],
        ),
      );
}

/// Notice légale reproduite telle quelle (jamais traduite : c'est le texte
/// exigé par la licence, pas un message d'interface).
class _NoticeBrute extends StatelessWidget {
  final String texte;
  const _NoticeBrute(this.texte);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
        ),
        // `ltr` forcé : ce texte est en anglais et doit rester lisible même
        // quand l'interface est en arabe (sinon la ponctuation et l'URL se
        // réordonnent).
        child: Text(texte,
            textDirection: TextDirection.ltr,
            style: GoogleFonts.manrope(
                fontSize: 11, color: AppColors.inkLight, height: 1.5)),
      );
}

class _BlocSignalement extends StatelessWidget {
  final String titre;
  final String corps;
  final String confirmation;
  const _BlocSignalement({
    required this.titre,
    required this.corps,
    required this.confirmation,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green900)),
          const SizedBox(height: 4),
          Text(corps,
              style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.ink, height: 1.55)),
          const SizedBox(height: 8),
          // Copie dans le presse-papiers plutôt qu'ouverture du client mail :
          // pas de dépendance supplémentaire (`url_launcher`), et surtout ça
          // marche même sur un téléphone sans application de messagerie
          // configurée — cas où un `mailto:` ne fait strictement rien et
          // laisse l'utilisateur sans recours.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    const ClipboardData(text: kContactEmail));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(confirmation)));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.green900,
                side: const BorderSide(color: AppColors.brass),
              ),
              label: Text(kContactEmail,
                  style: GoogleFonts.manrope(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );
}

class _BoutonLicences extends StatelessWidget {
  final String libelle;
  const _BoutonLicences({required this.libelle});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: t.appTitle,
          applicationVersion: '$kAppVersion+$kAppBuild',
          applicationLegalese: '© 2026',
        ),
        icon: const Icon(Icons.description_outlined, size: 16),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green900,
          side: const BorderSide(color: AppColors.green600),
        ),
        label: Text(libelle,
            style: GoogleFonts.manrope(
                fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
