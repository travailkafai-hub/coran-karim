// L'écran où l'on accepte — ou pas — d'aider à améliorer la reconnaissance.
//
// ── CE QU'UN ÉCRAN DE CONSENTEMENT DOIT FAIRE, ET QUE PEU FONT ───────────
//
// Il ne suffit pas d'un interrupteur et d'un lien vers une politique que
// personne ne lit. Une personne doit pouvoir répondre à quatre questions AVANT
// de toucher quoi que ce soit, et les voir à l'écran, pas dans un document :
//
//     qu'est-ce qui part ?        l'audio, le texte attendu, ce qui a été compris
//     qui peut l'ouvrir ?         personne d'autre que nous, chiffré ici
//     combien de temps ?          douze mois, annoncés
//     comment revenir en arrière ? un interrupteur, et le numéro à donner
//
// ⚠️ L'INTERRUPTEUR EST À L'ARRÊT PAR DÉFAUT, et ce défaut n'est pas un détail
// d'implémentation : un consentement se donne, il ne se présume pas. Rien ici
// ne doit être pré-coché, et le bouton d'acceptation ne doit pas être plus
// visible que celui de refus.
//
// Le numéro affiché est un identifiant de casier tiré au hasard
// (`CollecteIdentite`) : il ne dit rien de la personne, mais sans lui une
// demande d'effacement serait impossible à honorer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_settings_provider.dart';
import '../services/collecte_envoi.dart';
import '../services/collecte_identite.dart';
import '../theme/app_theme.dart';

class CollecteConsentementScreen extends ConsumerStatefulWidget {
  const CollecteConsentementScreen({super.key});

  @override
  ConsumerState<CollecteConsentementScreen> createState() =>
      _CollecteConsentementScreenState();
}

class _CollecteConsentementScreenState
    extends ConsumerState<CollecteConsentementScreen> {
  bool? _accorde;
  String _identifiant = '';
  int _enAttente = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final accorde = await CollecteIdentite.consentement();
    final id = await CollecteIdentite.identifiant();
    final attente = await CollecteEnvoi.enAttente();
    if (!mounted) return;
    setState(() {
      _accorde = accorde;
      _identifiant = id;
      _enAttente = attente;
    });
  }

  Future<void> _basculer(bool valeur) async {
    setState(() => _accorde = valeur);
    await CollecteIdentite.definirConsentement(valeur);
    if (!valeur) {
      // Retrait : ce qui attendait ne doit plus partir. On efface la file
      // AVANT toute autre chose -- un envoi déclenché entre-temps serait
      // exactement ce que le retrait interdit.
      await CollecteEnvoi.viderSansEnvoyer();
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final sombre = ref.watch(modeSombreProvider);
    final encre = sombre ? AppColors.cream : AppColors.ink;
    final fond = sombre ? AppColors.sombreBg : AppColors.mushafPapier;

    return Scaffold(
      backgroundColor: fond,
      appBar: AppBar(
        backgroundColor: fond,
        foregroundColor: encre,
        elevation: 0,
        title: Text(t.collecteTitre,
            style: GoogleFonts.manrope(
                fontSize: 17, fontWeight: FontWeight.w700, color: encre)),
      ),
      body: _accorde == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _paragraphe(t.collecteExplication, encre, gras: true),
                const SizedBox(height: 20),
                _point(Icons.upload_file_rounded, t.collecteCeQuiPart, encre),
                _point(Icons.lock_rounded, t.collecteChiffre, encre),
                _point(Icons.wifi_rounded, t.collecteWifi, encre),
                _point(Icons.schedule_rounded,
                    _dureeConservation(t), encre),
                _point(Icons.undo_rounded, t.collecteRetrait, encre),
                const SizedBox(height: 24),
                // L'interrupteur vient APRÈS les explications : on ne demande
                // pas de décider avant d'avoir dit de quoi il s'agit.
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cream.withAlpha(sombre ? 22 : 90),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.brass.withAlpha(90)),
                  ),
                  child: SwitchListTile(
                    value: _accorde!,
                    onChanged: _basculer,
                    activeThumbColor: AppColors.brass,
                    title: Text(t.collecteSous,
                        style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: encre)),
                  ),
                ),
                if (_accorde!) ...[
                  const SizedBox(height: 20),
                  SelectableText(
                    t.collecteIdentifiant(_identifiant),
                    style: GoogleFonts.robotoMono(
                        fontSize: 12.5, color: encre.withAlpha(220)),
                  ),
                  const SizedBox(height: 6),
                  _paragraphe(t.collecteIdentifiantAide, encre.withAlpha(170),
                      taille: 12.5),
                  if (_enAttente > 0) ...[
                    const SizedBox(height: 14),
                    _paragraphe(t.collecteEnAttente(_enAttente),
                        encre.withAlpha(170), taille: 12.5),
                  ],
                ],
              ],
            ),
    );
  }

  /// La durée n'est pas une phrase traduite de plus : elle vient de la
  /// constante qui fait foi, pour qu'un changement de politique ne puisse pas
  /// laisser un texte périmé derrière lui.
  String _dureeConservation(AppLocalizations t) =>
      Localizations.localeOf(context).languageCode == 'ar'
          ? 'تُحفَظ التسجيلات $kCollecteConservationMois شهرًا ثم تُحذف.'
          : Localizations.localeOf(context).languageCode == 'en'
              ? 'Recordings are kept for $kCollecteConservationMois months, '
                  'then deleted.'
              : 'Les enregistrements sont conservés $kCollecteConservationMois '
                  'mois, puis supprimés.';

  Widget _paragraphe(String texte, Color couleur,
          {double taille = 14, bool gras = false}) =>
      Text(texte,
          style: GoogleFonts.manrope(
              fontSize: taille,
              height: 1.55,
              fontWeight: gras ? FontWeight.w600 : FontWeight.w400,
              color: couleur));

  Widget _point(IconData icone, String texte, Color encre) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 18, color: AppColors.brass),
            const SizedBox(width: 12),
            Expanded(child: _paragraphe(texte, encre.withAlpha(225))),
          ],
        ),
      );
}
