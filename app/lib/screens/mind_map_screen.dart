// Carte mentale des sourates -- REFONTE_IHM.md §7. STUB (2026-07-19,
// demande utilisateur : "concevoir avec toutes les fonctionnalités vides,
// après tu développes, pour comprendre l'acheminement des IHM") -- écran
// vide fonctionnel pour que la navigation soit complète et testable AVANT
// d'investir dans le rendu graphview + les données JSON par sourate.
//
// A construire (voir REFONTE_IHM.md §7 pour la spec complète) :
//   - app/assets/mindmaps/{lang}/{NNN}.json (schema deja specifie)
//   - package graphview, disposition eventail gauche/droite
//   - noeud central circulaire + noeuds de branche colores par categorie
//   - flip de fiche detail (Transform + Matrix4.rotationY)
//   - bouton "Aller au verset" -> MushafScreen(surah, ayah)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';

class MindMapScreen extends StatelessWidget {
  final Surah surah;
  const MindMapScreen({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: AppColors.cream,
        title: Text('Carte mentale — ${surah.nameSimple}',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_outlined, size: 64, color: AppColors.green700),
              const SizedBox(height: 16),
              Text(
                'Bientôt disponible',
                style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'La carte mentale de ${surah.nameArabic} (thèmes, branches, '
                'liens vers les versets) est en cours de conception.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
