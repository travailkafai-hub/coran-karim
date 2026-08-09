// Écran « À PROPOS » — identité de l'app, ce qu'elle fait des données de
// l'utilisateur, avertissement sur le texte produit par le modèle de langage,
// sources et licences.
//
// ── POURQUOI CET ÉCRAN EXISTE (2026-08-09) ───────────────────────────────
// La tuile « À propos » des Réglages existait déjà... SANS `onTap` : elle
// n'ouvrait rien, et son sous-titre annonçait « Whisper » alors que la chaîne
// de vérification tourne sur FastConformer CTC depuis longtemps.
//
// Une application qui capte le micro et juge une récitation ne peut pas être
// publiée sans dire, DANS l'app :
//   1. ce qu'elle enregistre, où ça reste, comment l'effacer ;
//   2. ce qui juge la récitation, et d'où ce modèle vient.
//
// LE POINT 2 EST UNE OBLIGATION, PAS UNE POLITESSE. Le modèle de
// reconnaissance descend de `nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1`,
// publié sous **CC BY 4.0** (vérifié sur la fiche du modèle le 2026-08-09, et
// non supposé). Cette licence impose quatre éléments dans l'attribution :
// le créateur, le titre du modèle, un lien vers la source, la licence avec son
// lien — ET l'indication que l'œuvre a été MODIFIÉE. Un modèle affiné reste une
// œuvre dérivée : l'entraînement maison n'efface pas l'attribution due.
//
// Les licences des paquets Dart/Flutter ne sont PAS recopiées à la main ici :
// `showLicensePage` les collecte déjà toutes, exactement, depuis les paquets
// eux-mêmes. Ce fichier n'ajoute au registre que ce qui vient d'AILLEURS que
// pub.dev (modèle ASR, ONNX Runtime, polices) — sinon la liste affichée
// mentirait par omission.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
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

/// Le tuteur textuel (Gemma) est-il EMBARQUÉ dans la version distribuée ?
///
/// **`false` aujourd'hui, et c'est un constat vérifié, pas une supposition**
/// (2026-08-09) : aucun chemin de l'application n'embarque ni ne télécharge le
/// `.litertlm`. `TutorLlmService.ensureLoaded` cherche le fichier dans le
/// stockage privé, ne le trouve pas, journalise « Modèle absent — ignoré » et
/// `explainVerse` rend `null`. Aucun texte n'est donc produit chez un
/// utilisateur final, et les conditions d'utilisation de Gemma — qui portent
/// sur la DISTRIBUTION du modèle — ne s'appliquent pas.
///
/// ⚠️ Ce que ce drapeau NE dit PAS : que le code est débranché. Le chemin IHM
/// est bien vivant (`showCoachExplanation`, appelé depuis coach_hub_screen et
/// deux fois depuis mushaf_screen) — en production cela donne un bouton qui
/// n'aboutit jamais. À trancher séparément : soit embarquer le modèle, soit
/// retirer ces entrées.
///
/// **Le jour où le modèle est embarqué, repasser ce drapeau à `true`** : cela
/// rétablit d'un coup l'avertissement sur le texte généré, le bloc de
/// signalement et la notice Gemma au registre des licences — les trois
/// obligations qui reviennent avec lui.
const bool kTuteurIaEmbarque = false;

/// Adresse de contact affichée pour signaler un texte généré inapproprié.
///
/// N'a d'effet que si [kTuteurIaEmbarque] vaut `true`. **VIDE = bloc masqué.**
/// À renseigner AVANT de publier une version embarquant le tuteur : la
/// politique « IA générative » de Google Play exige un moyen, accessible DANS
/// l'application, de signaler le contenu produit par le modèle. Laissée vide
/// volontairement — choisir d'exposer une adresse personnelle ou une adresse de
/// support dédiée est une décision de l'éditeur, pas de l'outil qui écrit cet
/// écran.
const String kContactEmail = '';

/// Notices des composants qui ne viennent PAS de pub.dev — `showLicensePage`
/// ne peut pas les découvrir tout seul.
///
/// Enregistré une seule fois (le registre est global et `showLicensePage`
/// relit tous les fournisseurs à chaque ouverture : sans ce garde, rouvrir
/// l'écran dupliquerait chaque notice).
/// ── ATTRIBUTION DU MODÈLE DE RECONNAISSANCE ──────────────────────────────
/// Notice COMPLÈTE, réservée à la page des licences.
///
/// Elle ne s'affiche PAS sur la page « À propos » (retour utilisateur
/// 2026-08-09 : « t'as trop détaillé, tu parles de ONNX, HuggingFace, mets
/// juste le nécessaire »). Un récitateur n'a que faire du nom du checkpoint,
/// du format d'export et d'une URL de dépôt de modèles ; la page ne garde donc
/// qu'un crédit court (`aboutAsrCredit`), et le détail vit ici.
///
/// C'est conforme : CC BY 4.0 demande une attribution « raisonnable au regard
/// du support », ce qui admet un renvoi vers un écran de licences accessible
/// en un geste — pas que tout figure sur l'écran d'accueil.
///
/// Volontairement NON TRADUIT : c'est une mention légale, pas un message
/// d'interface. Les noms propres, l'URL de la source et l'identifiant de
/// licence doivent rester identiques dans les trois langues.
const String kNoticeAsrTitre = 'Modèle de reconnaissance de la récitation';
const String kNoticeAsr =
    'Ce produit utilise un modèle dérivé de '
    '« stt_ar_fastconformer_hybrid_large_pcd_v1 » de NVIDIA '
    '(huggingface.co/nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0), '
    'distribué sous licence Creative Commons Attribution 4.0 International '
    '(CC BY 4.0) — creativecommons.org/licenses/by/4.0/\n\n'
    'MODIFICATIONS : le modèle a été affiné (fine-tuning) sur un corpus de '
    'récitation coranique, puis exporté au format ONNX pour fonctionner '
    "hors ligne sur l'appareil. NVIDIA n'endosse ni ne valide cette "
    'application ni cet usage.';

var _licencesEnregistrees = false;

void enregistrerLicencesTierces() {
  if (_licencesEnregistrees) return;
  _licencesEnregistrees = true;
  LicenseRegistry.addLicense(() async* {
    // Le socle de l'application : c'est CE modèle qui juge la récitation.
    // Attribution CC BY 4.0 complète — les quatre éléments exigés y sont
    // (créateur, titre, lien vers la source, licence + lien) plus le cinquième
    // que l'on oublie systématiquement : DIRE QUE L'ŒUVRE A ÉTÉ MODIFIÉE.
    yield const LicenseEntryWithLineBreaks(
      [kNoticeAsrTitre],
      kNoticeAsr,
    );
    if (kTuteurIaEmbarque) {
      yield const LicenseEntryWithLineBreaks(
        ['Gemma (modèle de langage embarqué)'],
        'Gemma is provided under and subject to the Gemma Terms of Use found at '
        'ai.google.dev/gemma/terms\n\n'
        "Le tuteur de cette application utilise un modèle Gemma de Google, "
        "affiné pour l'explication de versets. Son utilisation est soumise aux "
        "conditions ci-dessus ainsi qu'à la Gemma Prohibited Use Policy "
        '(ai.google.dev/gemma/prohibited_use_policy).',
      );
    }
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

          // ── 2. Le moteur de reconnaissance : LE SOCLE ───────────────────
          // Placé haut, avant les sources et les licences : c'est ce qui juge
          // la récitation. L'utilisateur a le droit de savoir ce qui le
          // corrige, et NVIDIA a le droit d'être cité là où ça se lit.
          _Section(
            titre: t.aboutSectionAsr,
            enfants: [
              _Paragraphe(t.aboutAsrBody),
              const SizedBox(height: 10),
              // Crédit COURT : le créateur, la licence, et le fait que le
              // modèle a été modifié. Le reste (nom du checkpoint, lien vers
              // la source, exclusion de garantie) est dans les licences.
              _Mention(t.aboutAsrCredit),
            ],
          ),

          // ── 3. Avertissement sur le texte généré ────────────────────────
          // Affiché SEULEMENT si le tuteur est réellement embarqué : avertir
          // sur un texte qu'aucun utilisateur ne verra jamais n'informe
          // personne et brouille les mises en garde qui, elles, comptent.
          if (kTuteurIaEmbarque)
            _Section(
              titre: t.aboutSectionAi,
              // Fond ambré : cet encadré n'est pas une information de plus,
              // c'est une mise en garde. Elle doit se distinguer au premier
              // coup d'œil du reste de la page.
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

          // ── 4. Sources ──────────────────────────────────────────────────
          // Deux attributions, pas trois : la ligne « horaires calculés sur
          // l'appareil » disait la même chose que la puce Réseau ci-dessus.
          _Section(
            titre: t.aboutSectionSources,
            enfants: [
              _Puce(
                  icone: Icons.menu_book_rounded, texte: t.aboutSourceQuran),
              _Puce(
                  icone: Icons.volunteer_activism_rounded,
                  texte: t.aboutSourceDuas),
            ],
          ),

          // ── 5. Licences ─────────────────────────────────────────────────
          _Section(
            titre: t.aboutSectionLicenses,
            enfants: [
              // Pas de phrase d'introduction : le bouton dit déjà ce qu'il
              // fait, une ligne pour l'annoncer n'apprend rien.
              if (kTuteurIaEmbarque) ...[
                // Notice Gemma reproduite EN CLAIR, en plus du registre : ses
                // conditions exigent d'être transmises, pas d'être trouvables
                // au bout de deux écrans.
                const _NoticeBrute(
                  'Gemma is provided under and subject to the Gemma Terms of '
                  'Use found at ai.google.dev/gemma/terms',
                ),
              ],
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
        // Icone reelle de l'app (2026-08-09, demande utilisateur : « meme
        // dans a propos, remets l'icone de l'app ») -- remplace le
        // `Icons.menu_book_rounded` generique qui servait de repli avant que
        // l'icone finale (icone.png, cf. le launcher Android) existe.
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/icon/app_icon.png',
            width: 68,
            height: 68,
            fit: BoxFit.cover,
          ),
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
        // Le tag de code interne (DiagnosticLog.buildTag, ex.
        // « v146-decrochage-a-3-fenetres ») s'affichait ici. RETIRÉ le
        // 2026-08-09 : c'est du jargon de développement, illisible pour un
        // récitateur. Il reste inscrit en tête de chaque journal de
        // diagnostic — donc toujours disponible quand on analyse une session,
        // qui est le seul moment où il sert.
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

/// Ligne de crédit discrète, en bas d'une section : plus petite et plus pâle
/// que le corps du texte — présente et lisible, sans peser sur la lecture.
class _Mention extends StatelessWidget {
  final String texte;
  const _Mention(this.texte);
  @override
  Widget build(BuildContext context) => Text(texte,
      style: GoogleFonts.manrope(
          fontSize: 11, color: AppColors.inkLight, height: 1.5));
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
