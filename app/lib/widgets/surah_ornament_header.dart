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

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/verse.dart';

class SurahOrnamentHeader extends StatelessWidget {
  final Surah surah;
  const SurahOrnamentHeader({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isMeccan = surah.revelationPlace.toLowerCase().startsWith('makk');
    final place = isMeccan ? t.surahMeccan : t.surahMedinan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(
        // Bandeau recentré (demande utilisateur 2026-07-22 : "met tout au
        // milieu") -- médaillon puis titre puis métadonnées, tous centrés,
        // plutôt que la disposition médaillon-à-côté-du-texte d'origine.
        children: [
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
          const SizedBox(height: 10),
          // Titre flanqué d'un ornement (trait + losange) des deux côtés --
          // même formule que `_TitleRule` de la page de couverture
          // (surah_list_screen.dart), reprise ici pour rester cohérent.
          // Police distincte de la ligne de métadonnées en dessous
          // (Scheherazade New, plus grande, en gras) pour que le nom de la
          // sourate se distingue clairement au premier regard.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _OrnamentLine(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'سُورَةُ ${surah.nameArabic}',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.scheherazadeNew(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green900,
                  ),
                ),
              ),
              const _OrnamentLine(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.surahOrnamentMeta(place, surah.versesCount),
            textAlign: TextAlign.center,
            textDirection: Localizations.localeOf(context).languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            style: GoogleFonts.amiri(
              fontSize: 13,
              color: AppColors.inkLight,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trait + losange, même formule que `_TitleRule` (surah_list_screen.dart)
/// -- reproduit ici en privé plutôt qu'exporté : les deux écrans n'ont pas
/// vocation à partager un widget pour un détail purement décoratif.
class _OrnamentLine extends StatelessWidget {
  const _OrnamentLine();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Transform.rotate(
              angle: 0.785398, // 45°
              child: Container(width: 5, height: 5, color: AppColors.brass),
            ),
          ),
        ],
      );

  Widget _line() => Container(
        width: 28,
        height: 1,
        color: AppColors.brassLight.withValues(alpha: 0.6),
      );
}
