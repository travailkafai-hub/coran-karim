import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../models/prayer_settings.dart';
import '../providers/prayer_settings_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/prayer_labels.dart';

class MushafHeader extends StatelessWidget implements PreferredSizeWidget {
  final Surah surah;
  final VoidCallback? onBack;
  /// Cf. `_SurahNavRow.onMushafPapier` : l'en-tete ouvre le Mushaf papier
  /// depuis le 2026-09-09, la carte mentale est passee dans le panneau « ⋯ ».
  final VoidCallback? onMushafPapier;

  /// Lecture sur fond noir : le degrade vert du theme se confond avec la
  /// page et l'en-tete devient invisible (« le menu cache en mode dark est
  /// invisible », utilisateur 2026-08-07). On lui donne alors un fond sombre
  /// distinct du noir de la page, plus un liseré doré : ce n'est pas une
  /// couleur de marque ici, c'est un repere qui doit se voir.
  final bool modeSombre;

  const MushafHeader({super.key, required this.surah, this.onBack,
      this.onMushafPapier, this.modeSombre = false});

  /// ── 120 px NE SUFFISAIENT PAS (2026-09-09) ────────────────────────────
  ///
  /// Constate sur capture d'ecran : `BOTTOM OVERFLOWED BY 40 PIXELS` en plein
  /// milieu de l'en-tete, entre le bandeau de priere et la rangee de
  /// navigation.
  ///
  /// CAUSE : cette hauteur etait FIXE, alors que le contenu est enveloppe dans
  /// un `SafeArea` -- il doit donc loger, en plus de ses deux rangees, la barre
  /// d'etat et l'encoche de l'appareil. Sur le SM-S931B celles-ci prennent une
  /// quarantaine de pixels, exactement ce qui manquait. Une constante ne peut
  /// pas connaitre l'encoche : c'est une valeur qui change d'un telephone a
  /// l'autre.
  ///
  /// [hauteurPour] rend donc la hauteur reelle pour un contexte donne. Le
  /// `preferredSize` garde une valeur par defaut -- il est appele hors de
  /// l'arbre par `PreferredSizeWidget`, sans acces au `MediaQuery`.
  ///
  /// ⚠️ `MushafScreen._kMushafHeaderHeight` doit rester d'accord avec ceci :
  /// c'est lui qui reserve la place sous l'en-tete. Il appelle desormais la
  /// meme fonction (cf. son commentaire).
  /// Ce dont le CONTENU a besoin, mesure et non estime :
  ///
  ///     bandeau de priere   27  (padding vertical 6+6, texte 11 pt ~ 15)
  ///     espacement           4
  ///     rangee de navigation 48  (IconButton, dimension tactile minimale)
  ///     ────────────────────────
  ///     total               79   -> 84 avec une marge
  ///
  /// La valeur historique de 120 en reservait donc une quarantaine de trop.
  /// Premiere correction du jour : j'ai ajoute l'encoche PAR-DESSUS ces 120,
  /// ce qui a supprime le debordement mais laisse une bande vide sous la
  /// rangee de navigation -- signale aussitot par l'utilisateur (« tu as
  /// augmente la taille en haut pour quelle raison ! non, pas besoin
  /// d'autant »). On additionne maintenant le besoin REEL et l'encoche.
  static const _kContenu = 84.0;
  static double hauteurPour(BuildContext context) =>
      _kContenu + MediaQuery.paddingOf(context).top;

  @override
  Size get preferredSize => const Size.fromHeight(_kContenu);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: modeSombre
              ? const [AppColors.sombreBgDeep, Color(0xFF262626)]
              : const [AppColors.green900, AppColors.green800],
        ),
        border: modeSombre
            ? Border(
                bottom: BorderSide(
                    color: AppColors.sombreAccent.withAlpha(120), width: 1))
            : null,
      ),
      child: SafeArea(
        // ChGPT: this is a TOP header. Reserving Android's bottom navigation
        // inset here shrinks its 84px content after returning from paper view.
        bottom: false,
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
                // Status bar space + prayer time banner
                const _PrayerTimeBanner(),
                const SizedBox(height: 4),
                // Navigation row
                _SurahNavRow(surah: surah, onBack: onBack,
                    onMushafPapier: onMushafPapier),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rappel de la PROCHAINE priere, en haut du Mushaf.
///
/// ── CE QU'IL Y AVAIT AVANT, ET POURQUOI C'ETAIT GRAVE (2026-09-03) ────────
///
/// Ce bandeau affichait deux chaines de traduction ECRITES EN DUR --
/// `mushafPrayerNextIn` = « Dhuhr dans 2h 14m » et `mushafPrayerTimeLabel` =
/// « Dhuhr 13:30 » -- telles quelles, a n'importe quelle heure. Rien n'etait
/// calcule. Signale par l'utilisateur : « il y a en haut le temps pour les
/// prieres qui ne correspond a rien ! ». Une maquette jamais branchee, restee
/// en place : un affichage faux est pire qu'un affichage absent.
///
/// ── CE QU'IL FAIT MAINTENANT ──────────────────────────────────────────────
///
/// Il LIT `PrayerState.prochainePriere`, le calcul deja partage par l'ecran des
/// reglages et par le rappel de la liste des sourates. Il ne le refait pas : le
/// commentaire de son extraction le dit, « deux ecrans qui annonceraient une
/// prochaine priere differente seraient pires que pas de rappel du tout ».
///
/// Position inconnue ou refusee : on n'affiche RIEN. Ni bandeau vide, ni
/// « --:-- » qui ferait croire a une panne -- meme regle que la liste des
/// sourates.
class _PrayerTimeBanner extends ConsumerStatefulWidget {
  const _PrayerTimeBanner();

  @override
  ConsumerState<_PrayerTimeBanner> createState() => _PrayerTimeBannerState();
}

class _PrayerTimeBannerState extends ConsumerState<_PrayerTimeBanner> {
  Timer? _horloge;

  @override
  void initState() {
    super.initState();
    // Une minute, pas plus : le compte a rebours s'affiche en heures et
    // minutes, rafraichir plus souvent redessinerait pour rien. Plus rarement,
    // et le « dans 1 h 23 » resterait faux jusqu'a une minute -- visible
    // precisement quand on regarde pour savoir s'il reste du temps.
    _horloge = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _horloge?.cancel();
    super.dispose();
  }

  /// Les memes noms que le rappel de la liste des sourates.
  // ── LES NOMS DE PRIERE VIENNENT DU HELPER PARTAGE (2026-09-09) ──────────
  //
  // Une `const Map` locale portait `Sobh`, `Dhohr`, `Ichaa` -- affiches tels
  // quels au-dessus d'une page entierement arabe. C'est ce que l'utilisateur a
  // vu sur sa capture : « Dhohr 13:49 » et « Dhohr maintenant » en francais,
  // alors que toute la barre du bas etait bien en arabe.
  //
  // Quatrieme copie des memes libelles (avec l'ecran des horaires, l'accueil
  // et le service de notifications) ; elle passe maintenant par
  // `l10n/prayer_labels.dart`.

  String _restant(BuildContext context, Duration d) {
    final t = AppLocalizations.of(context)!;
    if (d.inMinutes < 1) return t.prayerInNow;
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return t.prayerInMinutes(m);
    return m == 0 ? t.prayerInHours(h) : t.prayerInHoursMinutes(h, m);
  }

  @override
  Widget build(BuildContext context) {
    final suivante = ref.watch(prayerSettingsProvider).prochainePriere;
    if (suivante == null) return const SizedBox(height: 4);

    final locale = suivante.time.toLocal();
    final hm = '${locale.hour.toString().padLeft(2, '0')}:'
        '${locale.minute.toString().padLeft(2, '0')}';
    final nom = nomPriere(context, suivante.name);
    final style = GoogleFonts.manrope(
      fontSize: 11,
      color: AppColors.brassLight,
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${nomPriere(context, suivante.name)} '
              '${_restant(context, suivante.time.difference(DateTime.now()))}',
              style: style),
          Text('$nom $hm', style: style),
        ],
      ),
    );
  }
}

class _SurahNavRow extends StatelessWidget {
  final Surah surah;
  final VoidCallback? onBack;

  /// ── L'EN-TETE OUVRE LE MUSHAF PAPIER (2026-09-09) ─────────────────────
  ///
  /// Cette place portait la CARTE MENTALE (`Icons.hub_outlined`). Demande
  /// utilisateur : « a la place de l'acces mindmap, remplace-le par l'acces
  /// Mushaf papier ».
  ///
  /// Le raisonnement tient a la frequence : la carte mentale est une vue
  /// d'ensemble qu'on ouvre UNE FOIS pour situer une sourate, le Mushaf papier
  /// est une facon de LIRE, qu'on bascule au fil de la lecture. L'acces en un
  /// tap va a ce qu'on repete.
  ///
  /// La carte mentale n'est pas perdue : elle descend dans le panneau « ⋯ »,
  /// a la place exacte que l'action « Signet » y libere (cf.
  /// `reading_settings_sheet.dart`). Le panneau ne gagne donc aucune ligne.
  final VoidCallback? onMushafPapier;

  const _SurahNavRow({required this.surah, this.onBack, this.onMushafPapier});

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
          _NavChip(label: AppLocalizations.of(context)!.mushafJuzChip(_juzOf(surah.number))),
          const SizedBox(width: 6),
          _NavChip(label: surah.nameArabic, isArabic: true),
          const SizedBox(width: 6),
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
          if (onMushafPapier != null)
            IconButton(
              icon: const Icon(Icons.auto_stories_rounded,
                  color: AppColors.cream, size: 22),
              tooltip: AppLocalizations.of(context)!.mushafPaperTooltip,
              onPressed: onMushafPapier,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  // Approximate Juz for a surah (simplified)
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
