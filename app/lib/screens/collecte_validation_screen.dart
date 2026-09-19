// « C'était juste » ou « je me suis trompé » — l'écran qui donne sa valeur au
// corpus.
//
// ── POURQUOI CET ÉCRAN EST LA PIÈCE MAÎTRESSE ───────────────────────────
//
// Un enregistrement brut ne dit pas si le modèle avait tort. Ici, la personne
// tranche sur chaque passage signalé, et c'est ce verdict humain qui
// transforme un clip en exemple d'entraînement :
//
//   « c'était juste »      -> le texte attendu EST ce qui a été prononcé.
//                             Étiquette CERTAINE, celle qui manque à tout
//                             corpus collecté en vrac. Part au manifeste.
//   « je me suis trompé »  -> l'app avait raison. L'audio reste utile, mais on
//                             ignore ce qui a été dit à la place : marqué
//                             `a_annoter`, hors manifeste.
//
// ⚠️ NE PAS PRÉSÉLECTIONNER L'UNE DES DEUX RÉPONSES, et ne pas rendre l'une
// plus facile à toucher que l'autre. Un corpus où « c'était juste » serait le
// défaut par un simple biais d'ergonomie apprendrait au modèle à valider de
// vraies fautes — le contraire exact du but de l'application.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_settings_provider.dart';
import '../services/collecte_envoi.dart';
import '../services/collecte_incidents.dart';
import '../services/collecte_paquet.dart';
import '../services/diagnostic_log.dart';
import '../theme/app_theme.dart';

class CollecteValidationScreen extends ConsumerStatefulWidget {
  const CollecteValidationScreen({super.key});

  @override
  ConsumerState<CollecteValidationScreen> createState() =>
      _CollecteValidationScreenState();
}

class _CollecteValidationScreenState
    extends ConsumerState<CollecteValidationScreen> {
  bool _envoiEnCours = false;

  Future<void> _terminer() async {
    setState(() => _envoiEnCours = true);
    try {
      final archive = await CollectePaquet.construire(
        incidents: CollecteIncidents.courants,
        build: DiagnosticLog.buildTag,
      );
      if (archive != null) await CollecteEnvoi.mettreEnFile(archive);
      CollecteIncidents.vider();
      unawaited(CollecteEnvoi.viderLaFile());
    } catch (e) {
      DiagnosticLog.log('Collecte', 'validation : $e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sombre = ref.watch(modeSombreProvider);
    final encre = sombre ? AppColors.cream : AppColors.ink;
    final fond = sombre ? AppColors.sombreBg : AppColors.mushafPapier;
    final incidents = CollecteIncidents.courants;
    final tranches = incidents.where((i) => i.avis != null).length;

    return Scaffold(
      backgroundColor: fond,
      appBar: AppBar(
        backgroundColor: fond,
        foregroundColor: encre,
        elevation: 0,
        title: Text('Ce que l\'application a signalé',
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700, color: encre)),
      ),
      body: incidents.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Rien à valider : aucun passage n\'a été signalé.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: encre.withAlpha(180)),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: incidents.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      'Pour chaque passage, dites-nous qui avait raison. '
                      'C\'est votre réponse qui permet de corriger le modèle.',
                      style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          height: 1.5,
                          color: encre.withAlpha(210)),
                    ),
                  );
                }
                return _carte(incidents[i - 1], encre, sombre);
              },
            ),
      bottomNavigationBar: incidents.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brass,
                    foregroundColor: AppColors.green900,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  // Sans aucune réponse, il n'y a rien à envoyer : le bouton
                  // reste éteint plutôt que de donner l'illusion d'un envoi.
                  onPressed:
                      tranches == 0 || _envoiEnCours ? null : _terminer,
                  child: Text(
                    _envoiEnCours
                        ? 'Envoi…'
                        : tranches == 0
                            ? 'Répondez à au moins un passage'
                            : 'Envoyer $tranches passage(s)',
                    style: GoogleFonts.manrope(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _carte(Incident incident, Color encre, bool sombre) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.cream.withAlpha(sombre ? 20 : 80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brass.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le mot attendu, en grand : c'est de lui qu'on parle.
          Text(incident.motAttendu,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiri(
                  fontSize: 26, height: 1.6, color: encre)),
          const SizedBox(height: 4),
          Text(
            incident.entendu.trim().isEmpty
                ? 'L\'application n\'a rien reconnu ici.'
                : 'L\'application a compris : ${incident.entendu}',
            style: GoogleFonts.manrope(
                fontSize: 12.5, color: encre.withAlpha(175)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _choix(
                  'C\'était juste',
                  incident.avis == AvisSurVerdict.appSeTrompe,
                  () => setState(
                      () => incident.avis = AvisSurVerdict.appSeTrompe),
                  encre,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choix(
                  'Je me suis trompé',
                  incident.avis == AvisSurVerdict.fauteReelle,
                  () => setState(
                      () => incident.avis = AvisSurVerdict.fauteReelle),
                  encre,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Les deux réponses ont EXACTEMENT la même forme, la même taille et la même
  /// couleur une fois choisies (cf. l'avertissement en tête de fichier).
  Widget _choix(String texte, bool actif, VoidCallback onTap, Color encre) =>
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: actif ? AppColors.brass.withAlpha(60) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: actif
                    ? AppColors.brass
                    : encre.withAlpha(70),
                width: actif ? 1.6 : 1),
          ),
          child: Text(texte,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                  color: encre)),
        ),
      );
}
