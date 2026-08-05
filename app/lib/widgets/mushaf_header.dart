import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';

class MushafHeader extends StatelessWidget implements PreferredSizeWidget {
  final Surah surah;
  final VoidCallback? onBack;
  final VoidCallback? onMindMap;

  const MushafHeader({super.key, required this.surah, this.onBack, this.onMindMap});

  @override
  // 120 -> 64 : la banniere d'heures de priere ne prend plus de hauteur
  // (cf. build). ⚠️ `MushafScreen._kMushafHeaderHeight` DOIT suivre -- c'est
  // une constante dupliquee, volontairement (eviter d'instancier un widget
  // pour lire sa taille), et le commentaire de la-bas le dit deja.
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.green900, AppColors.green800],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Mosque silhouette watermark
            Positioned.fill(
              child: Opacity(
                opacity: 0.06,
                child: CustomPaint(painter: _MosquePainter()),
              ),
            ),
            // Content
            Column(
              children: [
                // ── LA BANNIERE D'HEURES DE PRIERE QUITTE LE MUSHAF ────
                //
                // Demande utilisateur (2026-08-05) : l'en-tete empilait CINQ
                // reperes -- retour, JUZ, nom arabe, nom latin, mindmap --
                // AU-DESSUS d'une ligne entiere consacree a l'heure de la
                // priere suivante. Sur une page dont la raison d'etre est de
                // lire un texte, cela faisait deux lignes de chrome avant le
                // premier mot.
                //
                // L'information n'est pas perdue : elle vit sur l'ecran
                // d'accueil et sur « Suivre une priere », ou elle est
                // ACTIONNABLE. Ici elle ne servait qu'a occuper de la hauteur,
                // et personne n'ouvre une sourate pour connaitre l'heure du
                // Dhuhr. `_PrayerTimeBanner` est CONSERVE (non appele) : le
                // jour ou l'en-tete se replie sur un bandeau unique, il y a sa
                // place toute trouvee.
                const SizedBox(height: 4),
                _SurahNavRow(surah: surah, onBack: onBack, onMindMap: onMindMap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Conservee non appelee : cf. le commentaire de `build` -- l'heure de priere
// quitte le Mushaf mais garde sa place ailleurs, et ce widget est pret.
// ignore: unused_element
class _PrayerTimeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            AppLocalizations.of(context)!.mushafPrayerNextIn,
            style: GoogleFonts.manrope(
              fontSize: 11, color: AppColors.brassLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            AppLocalizations.of(context)!.mushafPrayerTimeLabel,
            style: GoogleFonts.manrope(
              fontSize: 11, color: AppColors.brassLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SurahNavRow extends StatelessWidget {
  final Surah surah;
  final VoidCallback? onBack;
  final VoidCallback? onMindMap;

  const _SurahNavRow({required this.surah, this.onBack, this.onMindMap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppColors.cream, size: 26),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          // ── TROIS PUCES DE POSITION -> UNE SEULE (2026-08-05) ────────────
          //
          // « JUZ 5 », « الأنعام » et « 6. Al-An'am » disaient la MEME chose
          // trois fois. Le nom romanise porte deja le numero et le nom ; le
          // chip arabe le repete dans une autre ecriture, et le juz est une
          // information de reperage qu'on ne consulte pas en lisant.
          //
          // ⚠️ EN ARABE, C'EST LE CHIP ARABE QUI RESTE (cf. le libelle plus
          // bas) : la regle du duo (REFONTE_IHM.md §7bis) interdit le nom
          // romanise quand l'app est en arabe. On ne garde donc pas « le chip
          // latin » mais « le chip de position », dont le contenu depend de la
          // langue -- ce qui etait deja le cas.
          //
          // `_juzOf` est CONSERVEE : elle sert au jour ou le juz revient dans
          // un fil d'ariane, et sa table approximative a un cout de
          // reconstitution non nul.
          Expanded(
            child: _NavChip(
              // En arabe, le chip arabe ci-dessus suffit déjà -- pas de nom
              // romanisé en plus (règle verrouillée REFONTE_IHM.md §7bis).
              label: Localizations.localeOf(context).languageCode == 'ar'
                  ? '${surah.number}'
                  : '${surah.number}. ${surah.nameSimple}',
              flex: true,
            ),
          ),
          if (onMindMap != null)
            IconButton(
              icon: const Icon(Icons.hub_outlined, color: AppColors.cream, size: 22),
              tooltip: AppLocalizations.of(context)!.mushafMindMapTooltip,
              onPressed: onMindMap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  // Approximate Juz for a surah (simplified)
  // Conservee non appelee : la table approximative des juz a un cout de
  // reconstitution non nul, et le juz reviendra dans un fil d'ariane.
  // ignore: unused_element
  static int _juzOf(int surah) {
    const starts = [1,2,2,3,4,5,6,7,8,9,9,10,11,12,13,13,14,15,15,16,17,17,
      18,18,19,19,20,21,22,22,23,23,24,24,24,25,26,26,27,27,28,28,28,28,28,
      26,26,26,26,26,26,26,26,26,26,27,27,27,27,28,28,28,28,28,28,28,29,29,
      29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,30,30,
      30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,
      30,30,30,30,30];
    if (surah < 1 || surah > starts.length) return 1;
    return starts[surah - 1];
  }
}

class _NavChip extends StatelessWidget {
  final String label;
  final bool isArabic;
  final bool flex;

  // ignore: unused_element_parameter
  const _NavChip({required this.label, this.isArabic = false, this.flex = false});

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.green700.withAlpha(160),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.green600.withAlpha(80), width: 1),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        style: isArabic
            ? GoogleFonts.amiri(fontSize: 15, color: AppColors.cream)
            : GoogleFonts.manrope(
                fontSize: 11, color: AppColors.cream, fontWeight: FontWeight.w600),
      ),
    );
    return flex ? child : child;
  }
}

// Simple geometric mosque silhouette
class _MosquePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final w = size.width; final h = size.height;
    final path = Path();

    // Central dome
    path.moveTo(w * 0.35, h * 0.85);
    path.lineTo(w * 0.35, h * 0.55);
    path.quadraticBezierTo(w * 0.35, h * 0.15, w * 0.5, h * 0.15);
    path.quadraticBezierTo(w * 0.65, h * 0.15, w * 0.65, h * 0.55);
    path.lineTo(w * 0.65, h * 0.85);

    // Left minaret
    path.moveTo(w * 0.18, h * 0.85);
    path.lineTo(w * 0.18, h * 0.35);
    path.quadraticBezierTo(w * 0.21, h * 0.2, w * 0.235, h * 0.2);
    path.quadraticBezierTo(w * 0.26, h * 0.2, w * 0.26, h * 0.35);
    path.lineTo(w * 0.26, h * 0.85);

    // Right minaret
    path.moveTo(w * 0.74, h * 0.85);
    path.lineTo(w * 0.74, h * 0.35);
    path.quadraticBezierTo(w * 0.765, h * 0.2, w * 0.79, h * 0.2);
    path.quadraticBezierTo(w * 0.815, h * 0.2, w * 0.815, h * 0.35);
    path.lineTo(w * 0.815, h * 0.85);

    // Ground line
    path.moveTo(0, h * 0.85);
    path.lineTo(w, h * 0.85);
    path.lineTo(w, h);
    path.lineTo(0, h);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
