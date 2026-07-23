// Carte mentale des sourates -- REFONTE_IHM.md §7.
//
// Contenu chargé depuis assets/mindmaps/{lang}/{NNN}.json (mindMapProvider) :
// les 114 sourates sont fournies (2026-07-20). Le stub "bientôt disponible"
// ne sert plus que de filet en cas de fichier illisible.
//
// Le schéma réel porte `cat` sur le PASSAGE (enfant), pas sur la section :
// une section est donc colorée par sa catégorie DOMINANTE
// (MindMapBranch.dominantCategory), et chaque passage garde sa couleur propre.
//
// UN SEUL NIVEAU, TOUT AFFICHÉ D'UN COUP (décision utilisateur 2026-07-22,
// retour en arrière volontaire sur la navigation par niveau introduite le
// 2026-07-20) : racine + branches + TOUS leurs passages sont visibles sur un
// seul canevas pannable/zoomable, sans écran de drill-down ni fil d'Ariane.
// Chaque branche est positionnée comme avant (gauche/droite du centre), et
// SES passages sont affichés juste plus loin qu'elle, dans le même axe,
// reliés par un second niveau de connecteurs. Le compromis lisibilité pour
// les branches à beaucoup de passages (ex. Al-Baqara 178-253, 9 passages) est
// assumé par l'utilisateur : le pan/zoom de l'InteractiveViewer absorbe la
// taille du canevas, qui peut devenir grand.
//
// DISPOSITION MANUELLE, PAS `graphview` (2026-07-20, suite retour "c'est
// asymétrique" sur téléphone réel) : `MindmapAlgorithm` du package
// `graphview` répartit chaque enfant à gauche/droite du centre en comparant
// sa position à celle du centre APRÈS un premier passage Buchheim-Walker ;
// pour un centre à exactement 2 enfants, ce premier passage centre parfois
// le nœud racine exactement sur l'un des deux enfants plutôt qu'entre eux
// deux, et les deux enfants finissent alors classés du même côté (chevauche
// le centre). C'est un bug de centrage de la bibliothèque tierce sur les
// petits arbres, pas quelque chose que les données ou la config peuvent
// fiabiliser. Le centre et ses enfants sont donc positionnés à la main ici
// (répartition gauche/droite figée moitié-moitié, jamais dépendante d'un
// calcul de bibliothèque) -- même principe que le prototype HTML validé plus
// tôt : centre au milieu, éléments répartis en deux colonnes, connecteurs en
// courbe de Bézier dessinés par un CustomPainter.
//
// Couleurs de catégorie : palette manuscrite définitive, cf. app_theme.dart.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/mind_map_data.dart';
import '../models/verse.dart';
import '../providers/mind_map_provider.dart';
import '../theme/app_theme.dart';
import 'mushaf_screen.dart';

Color _categoryColor(MindMapCategory cat) => switch (cat) {
      MindMapCategory.recits => AppColors.mindmapRecits,
      MindMapCategory.croyance => AppColors.mindmapCroyance,
      MindMapCategory.eschatologie => AppColors.mindmapEschatologie,
      MindMapCategory.argumentation => AppColors.mindmapArgumentation,
      MindMapCategory.ethique => AppColors.mindmapEthique,
      MindMapCategory.legislation => AppColors.mindmapLegislation,
      MindMapCategory.signes => AppColors.mindmapSignes,
      MindMapCategory.adoration => AppColors.mindmapAdoration,
      MindMapCategory.autre => AppColors.mindmapAutre,
    };

class MindMapScreen extends ConsumerWidget {
  final Surah surah;
  const MindMapScreen({super.key, required this.surah});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mindMapProvider(surah.number));

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: AppColors.cream,
        title: Text(
            AppLocalizations.of(context)!.mindMapAppBarTitle(
                Localizations.localeOf(context).languageCode == 'ar'
                    ? surah.nameArabic
                    : surah.nameSimple),
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.green700)),
        error: (_, _) => _NotReadyStub(surah: surah),
        data: (data) => data == null
            ? _NotReadyStub(surah: surah)
            : _MindMapCanvas(surah: surah, data: data),
      ),
    );
  }
}

class _NotReadyStub extends StatelessWidget {
  final Surah surah;
  const _NotReadyStub({required this.surah});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_outlined, size: 64, color: AppColors.green700),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.mindMapNotReadyTitle,
              style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.mindMapNotReadyBody(surah.nameArabic),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une branche prête à être positionnée : sa carte + la couleur de sa
/// catégorie dominante + les cartes de SES passages déjà construites (avec
/// leur `onTap` déjà branché) -- `_RadialLayout` n'a plus qu'à les placer.
class _BranchGroup {
  final MindMapBranch branch;
  final Color color;
  final List<Widget> leafWidgets;
  const _BranchGroup({required this.branch, required this.color, required this.leafWidgets});
}

class _MindMapCanvas extends StatelessWidget {
  final Surah surah;
  final MindMapData data;
  const _MindMapCanvas({required this.surah, required this.data});

  void _goToVerse(BuildContext context, int ayah) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MushafScreen(surah: surah, initialAyahNumber: ayah),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final branch in data.branches)
        _BranchGroup(
          branch: branch,
          color: _categoryColor(branch.dominantCategory),
          leafWidgets: [
            for (final leaf in branch.children)
              _LeafCard(leaf: leaf, onTap: () => _goToVerse(context, leaf.firstAyah)),
          ],
        ),
    ];

    return _RadialLayout(
      center: _RootCard(data: data, surah: surah),
      groups: groups,
    );
  }
}

/// Un segment de connecteur (courbe de Bézier) entre deux points -- utilisé
/// aussi bien pour racine→branche que pour branche→passage, unifiés dans le
/// même painter puisque les deux sont visuellement le même type de lien.
class _Connector {
  final Offset from;
  final Offset to;
  final Color color;
  const _Connector({required this.from, required this.to, required this.color});
}

/// Centre au milieu, branches réparties moitié-moitié en deux colonnes fixes
/// (jamais dépendant d'un calcul de bibliothèque tierce), et les passages de
/// CHAQUE branche affichés juste plus loin qu'elle sur le même côté, reliés
/// par un second niveau de courbes de Bézier.
///
/// La taille du canevas est calculée à partir du CONTENU (pas une largeur
/// fixe arbitraire), et la vue démarre automatiquement mise à l'échelle pour
/// remplir l'espace disponible -- recalculée à chaque changement de taille du
/// viewport (rotation portrait/paysage, sourates avec peu de branches donnant
/// un canevas plus petit, etc.).
class _RadialLayout extends StatefulWidget {
  final Widget center;
  final List<_BranchGroup> groups;

  const _RadialLayout({required this.center, required this.groups});

  @override
  State<_RadialLayout> createState() => _RadialLayoutState();
}

class _RadialLayoutState extends State<_RadialLayout> {
  final TransformationController _controller = TransformationController();
  Size? _lastFittedViewport;

  static const double _centerBoxSize = 260;
  static const double _centerGap = 195; // centre -> bord proche d'une branche
  static const double _branchWidth = 170;
  static const double _branchHeight = 108;
  static const double _childGap = 40; // branche -> bord proche d'un passage
  static const double _leafWidth = 168;
  static const double _leafRowHeight = 148; // espace vertical alloué par passage

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fitToViewport(Size viewport, double canvasWidth, double canvasHeight) {
    if (viewport.isEmpty || _lastFittedViewport == viewport) return;
    _lastFittedViewport = viewport;
    final scale = (math.min(viewport.width / canvasWidth, viewport.height / canvasHeight) * 0.92)
        .clamp(0.12, 1.0);
    final dx = (viewport.width - canvasWidth * scale) / 2;
    final dy = (viewport.height - canvasHeight * scale) / 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;

    final leftCount = (groups.length / 2).ceil();
    final left = groups.take(leftCount).toList();
    final right = groups.skip(leftCount).toList();

    double bandHeight(_BranchGroup g) =>
        math.max(_branchHeight, g.leafWidgets.length * _leafRowHeight);

    final leftTotalH = left.fold(0.0, (sum, g) => sum + bandHeight(g));
    final rightTotalH = right.fold(0.0, (sum, g) => sum + bandHeight(g));

    final canvasHeight = math.max(420.0, math.max(leftTotalH, rightTotalH) + 140);
    final canvasWidth =
        _centerBoxSize + 2 * (_centerGap + _branchWidth + _childGap + _leafWidth) + 40;
    final centerX = canvasWidth / 2;
    final centerY = canvasHeight / 2;

    final connectors = <_Connector>[];
    final positioned = <Widget>[];

    void placeSide(List<_BranchGroup> side, bool isLeft) {
      if (side.isEmpty) return;
      final totalH = side.fold(0.0, (sum, g) => sum + bandHeight(g));
      var cursorY = centerY - totalH / 2;
      for (final g in side) {
        final bandH = bandHeight(g);
        final bandCenterY = cursorY + bandH / 2;

        final branchLeft = isLeft ? centerX - _centerGap - _branchWidth : centerX + _centerGap;
        final innerX = isLeft ? branchLeft + _branchWidth : branchLeft; // côté centre
        final outerX = isLeft ? branchLeft : branchLeft + _branchWidth; // côté passages

        positioned.add(Positioned(
          left: branchLeft,
          top: bandCenterY - _branchHeight / 2,
          width: _branchWidth,
          child: g.branchCard,
        ));
        connectors.add(_Connector(
          from: Offset(centerX, centerY),
          to: Offset(innerX, bandCenterY),
          color: g.color,
        ));

        final leafCount = g.leafWidgets.length;
        if (leafCount > 0) {
          final leafTotalH = leafCount * _leafRowHeight;
          var leafCursorY = bandCenterY - leafTotalH / 2;
          for (final leafWidget in g.leafWidgets) {
            final leafCenterY = leafCursorY + _leafRowHeight / 2;
            final leafLeft = isLeft ? outerX - _childGap - _leafWidth : outerX + _childGap;
            positioned.add(Positioned(
              left: leafLeft,
              top: leafCenterY - 64, // ~moitié de la hauteur estimée d'un passage
              width: _leafWidth,
              child: leafWidget,
            ));
            connectors.add(_Connector(
              from: Offset(outerX, bandCenterY),
              to: Offset(isLeft ? leafLeft + _leafWidth : leafLeft, leafCenterY),
              color: g.color,
            ));
            leafCursorY += _leafRowHeight;
          }
        }
        cursorY += bandH;
      }
    }

    placeSide(left, true);
    placeSide(right, false);

    return LayoutBuilder(builder: (context, constraints) {
      _fitToViewport(constraints.biggest, canvasWidth, canvasHeight);
      return InteractiveViewer(
        transformationController: _controller,
        constrained: false,
        minScale: 0.1,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(200),
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(canvasWidth, canvasHeight),
                painter: _ConnectorPainter(connectors: connectors),
              ),
              ...positioned,
              Positioned(
                left: centerX - _centerBoxSize / 2,
                top: centerY - _centerBoxSize / 2,
                width: _centerBoxSize,
                height: _centerBoxSize,
                child: Center(child: widget.center),
              ),
            ],
          ),
        ),
      );
    });
  }
}

extension on _BranchGroup {
  /// Construit la carte de la branche à la volée (elle a besoin de `color`
  /// déjà calculée, portée par ce groupe).
  Widget get branchCard => _BranchCard(branch: branch, color: color);
}

class _ConnectorPainter extends CustomPainter {
  final List<_Connector> connectors;
  const _ConnectorPainter({required this.connectors});

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in connectors) {
      final paint = Paint()
        ..color = c.color.withAlpha(160)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke;
      final dx = (c.to.dx - c.from.dx) * 0.45;
      final path = Path()
        ..moveTo(c.from.dx, c.from.dy)
        ..cubicTo(
          c.from.dx + dx, c.from.dy,
          c.to.dx - dx, c.to.dy,
          c.to.dx, c.to.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) =>
      oldDelegate.connectors != connectors;
}

class _RootCard extends StatelessWidget {
  final MindMapData data;
  final Surah surah;
  const _RootCard({required this.data, required this.surah});

  @override
  Widget build(BuildContext context) {
    // `theme_central` est une PHRASE entière dans les données réelles -- elle
    // ne tient pas dans un médaillon. Le cercle porte l'identité de la sourate
    // (nom arabe, n°, nombre de versets) ; la phrase et la note de sources
    // s'ouvrent au tap, où il y a la place de les lire.
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.cream,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        Localizations.localeOf(context).languageCode == 'ar'
                            ? '${data.surahNumber}. ${surah.nameArabic}'
                            : '${data.surahNumber}. ${data.nameLatin}',
                        style: GoogleFonts.fraunces(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: AppColors.green900)),
                    const SizedBox(height: 2),
                    Text(AppLocalizations.of(context)!.mindMapAyahCountBadge(data.ayatCount),
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.inkLight)),
                    const SizedBox(height: 14),
                    Text(AppLocalizations.of(context)!.mindMapThemeLabel,
                        style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green700)),
                    const SizedBox(height: 6),
                    Text(data.themeCentral,
                        style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            height: 1.45,
                            color: AppColors.ink)),
                    if (data.sourcesNote.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      // Affiché à l'utilisateur, pas masqué : la note dit d'où
                      // vient la structure et signale parfois qu'une partie
                      // reste à vérifier. C'est une information d'honnêteté.
                      Text(AppLocalizations.of(context)!.mindMapSourcesLabel,
                          style: GoogleFonts.manrope(
                              fontSize: 10.5,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green700)),
                      const SizedBox(height: 6),
                      Text(data.sourcesNote,
                          style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: AppColors.inkLight)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      child: Container(
        width: 124,
        height: 124,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brass, AppColors.green700],
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              data.nameAr,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.scheherazadeNew(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 2),
            Text(AppLocalizations.of(context)!.mindMapAyahCountBadge(data.ayatCount),
                style: GoogleFonts.manrope(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cream)),
            const SizedBox(height: 3),
            const Icon(Icons.info_outline_rounded,
                size: 13, color: AppColors.cream),
          ],
        ),
      ),
    );
  }
}

/// Nœud de branche : au tap, ouvre une feuille du bas avec le résumé complet
/// (plus de niveau "branche ouverte" séparé -- ses passages sont déjà visibles
/// juste à côté d'elle sur le canevas, seul le texte `resume` n'a pas d'autre
/// endroit où s'afficher).
class _BranchCard extends StatelessWidget {
  final MindMapBranch branch;
  final Color color;
  const _BranchCard({required this.branch, required this.color});

  void _showDetails(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.cream,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration:
                          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                      child: Text(categoryLabel(context, branch.dominantCategory),
                          style: GoogleFonts.manrope(
                              fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    Text(branch.title,
                        style: GoogleFonts.fraunces(
                            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.green900)),
                    const SizedBox(height: 3),
                    Text(AppLocalizations.of(context)!.mindMapVerses(branch.range),
                        style:
                            GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight)),
                    const SizedBox(height: 10),
                    Text(branch.resume,
                        style: GoogleFonts.manrope(
                            fontSize: 13, height: 1.45, color: AppColors.ink)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetails(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(categoryLabel(context, branch.dominantCategory),
                  style: GoogleFonts.manrope(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Text(branch.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)!.mindMapVerses(branch.range),
                style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.inkLight)),
          ],
        ),
      ),
    );
  }
}

class _LeafCard extends StatelessWidget {
  final MindMapLeaf leaf;
  final VoidCallback onTap;
  const _LeafCard({required this.leaf, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
          // Filet de couleur à gauche : chaque PASSAGE porte sa propre
          // catégorie dans les données réelles (elle peut différer de la
          // catégorie dominante de sa section), on la montre donc ici.
          border: Border(
            left: BorderSide(color: _categoryColor(leaf.cat), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.brass,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(leaf.v,
                      style: GoogleFonts.manrope(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(categoryLabel(context, leaf.cat),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: _categoryColor(leaf.cat))),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(leaf.t,
                style: GoogleFonts.manrope(
                    fontSize: 10.5, height: 1.3, color: AppColors.ink),
                maxLines: 5,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
