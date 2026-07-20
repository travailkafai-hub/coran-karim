// Filigrane de fond partagé (défilement du Coran + couverture) : tuile SVG
// générée par design/gen_pattern.js (pavage octogones + carrés, construction
// géométrique -- cf. commentaire du générateur), répétée comme une texture
// de papier. Fixe (ne scrolle pas avec le contenu), opacité très faible pour
// ne jamais concurrencer le texte -- même prudence que pour le médaillon de
// sourate, après le retour utilisateur sur la V1 du bandeau
// ("catastrophique... trop chargée"). Extrait de mushaf_screen.dart quand la
// couverture (surah_list_screen.dart) en a eu besoin aussi.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class QuranPatternBackground extends StatelessWidget {
  final double opacity;
  const QuranPatternBackground({super.key, this.opacity = 0.05});

  // Doit rester en phase avec la taille de tuile écrite par gen_pattern.js
  // (viewBox D×D, affiché dans son log "régénéré (tuile ...)").
  static const double _tileSize = 82.08;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / _tileSize).ceil() + 1;
              final rows = (constraints.maxHeight / _tileSize).ceil() + 1;
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: cols * _tileSize,
                  maxHeight: rows * _tileSize,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      rows,
                      (_) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          cols,
                          (_) => SvgPicture.asset(
                            'assets/illumination/quran_pattern_tile.svg',
                            width: _tileSize,
                            height: _tileSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
}
