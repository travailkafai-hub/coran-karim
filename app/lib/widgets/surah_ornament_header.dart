// Bandeau de séparation entre sourates -- demande utilisateur 2026-07-19,
// en remplacement de l'ancien `_SurahBanner` (simple pilule arrondie, sans
// caractère "design arabe").
//
// V1 (CustomPainter fait main, cadre ornemental complet) jugée
// "catastrophique" par l'utilisateur -- trop chargée, mal exécutée. V2
// (celle-ci) : un seul élément ornemental, le médaillon vectoriel
// assets/illumination/medallion.svg (généré par design/gen_medallion.js,
// palette AppColors exacte : vert/or), utilisé exactement comme prévu par
// son propre design (le médaillon réserve un disque vert central pour le
// texte superposé -- motif classique d'enluminure de mushaf : une rosette
// à côté du titre de sourate, pas un cadre autour de tout). Le reste est
// volontairement sobre (texte simple, pas de painter maison) pour ne pas
// répéter l'erreur de surcharge de la V1.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../models/verse.dart';

class SurahOrnamentHeader extends StatelessWidget {
  final Surah surah;
  const SurahOrnamentHeader({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    final isMeccan = surah.revelationPlace.toLowerCase().startsWith('makk');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // Médaillon : numéro de sourate superposé au disque vert central
          // réservé par le SVG.
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SvgPicture.asset('assets/illumination/medallion.svg',
                    width: 72, height: 72),
                Text(
                  '${surah.number}',
                  style: GoogleFonts.amiri(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cream,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'سُورَةُ ${surah.nameArabic}',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.amiri(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isMeccan ? 'مكية' : 'مدنية'} · ${surah.versesCount} آية',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.amiri(
                    fontSize: 13,
                    color: AppColors.inkLight,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
