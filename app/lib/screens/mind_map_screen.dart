// Carte mentale des sourates -- REFONTE_IHM.md §7.
//
// Rendu graphview (algorithme "mindmap" natif du package : éventail
// gauche/droite, root au centre) + flip de fiche détail (Transform +
// Matrix4.rotationY, pas de package tiers, comme demandé) + navigation
// "Aller au verset" -> MushafScreen(surah, initialAyahNumber).
//
// Contenu chargé depuis assets/mindmaps/fr/{NNN}.json (mindMapProvider).
// Pas encore rédigé pour toutes les sourates -> stub "Bientôt disponible"
// tant que le JSON n'existe pas (comportement conservé de la version stub).
//
// Couleurs de catégorie : PLACEHOLDER (AppColors.mindmap*, 2026-07-19) en
// attendant la palette manuscrite de l'utilisateur -- cf. commentaire dans
// app_theme.dart, ne pas considérer ces couleurs comme définitives.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:graphview/GraphView.dart';
import '../models/mind_map_data.dart';
import '../models/verse.dart';
import '../providers/mind_map_provider.dart';
import '../theme/app_theme.dart';
import 'mushaf_screen.dart';

Color _categoryColor(MindMapCategory cat) => switch (cat) {
      MindMapCategory.croyance => AppColors.mindmapCroyance,
      MindMapCategory.recit => AppColors.mindmapRecit,
      MindMapCategory.loi => AppColors.mindmapLoi,
      MindMapCategory.promesse => AppColors.mindmapPromesse,
      MindMapCategory.avertissement => AppColors.mindmapAvertissement,
      MindMapCategory.louange => AppColors.mindmapLouange,
    };

String _categoryLabel(MindMapCategory cat) => switch (cat) {
      MindMapCategory.croyance => 'Croyance',
      MindMapCategory.recit => 'Récit',
      MindMapCategory.loi => 'Loi',
      MindMapCategory.promesse => 'Promesse',
      MindMapCategory.avertissement => 'Avertissement',
      MindMapCategory.louange => 'Louange',
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
        title: Text('Carte mentale — ${surah.nameSimple}',
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
              'Bientôt disponible',
              style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'La carte mentale de ${surah.nameArabic} (thèmes, branches, '
              'liens vers les versets) est en cours de rédaction.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _MindMapCanvas extends StatefulWidget {
  final Surah surah;
  final MindMapData data;
  const _MindMapCanvas({required this.surah, required this.data});

  @override
  State<_MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<_MindMapCanvas> {
  final Graph _graph = Graph()..isTree = true;
  final Map<String, Object> _content = {}; // id -> String (root) | MindMapBranch | MindMapLeaf
  late final BuchheimWalkerConfiguration _config;

  @override
  void initState() {
    super.initState();
    _config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 40
      ..levelSeparation = 80
      ..subtreeSeparation = 40
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;
    _buildGraph();
  }

  void _buildGraph() {
    final root = Node.Id('root');
    _content['root'] = widget.data.themeCentral;
    _graph.addNode(root);

    for (var i = 0; i < widget.data.branches.length; i++) {
      final branch = widget.data.branches[i];
      final branchId = 'b$i';
      final branchNode = Node.Id(branchId);
      _content[branchId] = branch;
      _graph.addEdge(root, branchNode, paint: Paint()..color = _categoryColor(branch.cat));

      for (var j = 0; j < branch.children.length; j++) {
        final leaf = branch.children[j];
        final leafId = 'b${i}_$j';
        final leafNode = Node.Id(leafId);
        _content[leafId] = leaf;
        _graph.addEdge(branchNode, leafNode,
            paint: Paint()..color = _categoryColor(branch.cat).withAlpha(140));
      }
    }
  }

  void _goToVerse(int ayah) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MushafScreen(surah: widget.surah, initialAyahNumber: ayah),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      constrained: false,
      minScale: 0.4,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(200),
      child: GraphView(
        graph: _graph,
        algorithm: MindmapAlgorithm(_config, null),
        paint: Paint()
          ..color = AppColors.green600.withAlpha(120)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
        builder: (Node node) {
          final id = node.key!.value as String;
          final content = _content[id];
          if (content is String) {
            return _RootCard(themeCentral: content);
          } else if (content is MindMapBranch) {
            return _BranchCard(
              key: ValueKey(id),
              branch: content,
              onGoToVerse: () => _goToVerse(content.firstAyah),
            );
          } else if (content is MindMapLeaf) {
            return _LeafCard(
              leaf: content,
              onTap: () => _goToVerse(content.firstAyah),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _RootCard extends StatelessWidget {
  final String themeCentral;
  const _RootCard({required this.themeCentral});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brass, AppColors.green700],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        themeCentral,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        style: GoogleFonts.scheherazadeNew(
          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.cream,
        ),
      ),
    );
  }
}

/// Nœud de branche : face avant = titre + catégorie, face arrière = résumé
/// + bouton "Aller au verset". Flip manuel (Transform + Matrix4.rotationY),
/// pas de package tiers (demande explicite REFONTE_IHM.md §7).
class _BranchCard extends StatefulWidget {
  final MindMapBranch branch;
  final VoidCallback onGoToVerse;
  const _BranchCard({super.key, required this.branch, required this.onGoToVerse});

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _flipped = !_flipped);
    if (_flipped) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(widget.branch.cat);
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final angle = _controller.value * 3.14159265;
          final showBack = _controller.value > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159265),
                    child: _backFace(color),
                  )
                : _frontFace(color),
          );
        },
      ),
    );
  }

  Widget _frontFace(Color color) {
    return Container(
      width: 170,
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
            child: Text(_categoryLabel(widget.branch.cat),
                style: GoogleFonts.manrope(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text(widget.branch.title,
              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('Versets ${widget.branch.range}',
              style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.inkLight)),
        ],
      ),
    );
  }

  Widget _backFace(Color color) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.branch.resume,
              style: GoogleFonts.manrope(fontSize: 11, height: 1.35, color: Colors.white)),
          const SizedBox(height: 8),
          InkWell(
            onTap: widget.onGoToVerse,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text('Aller au verset',
                    style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                        decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ],
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
        width: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cream200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.brass, borderRadius: BorderRadius.circular(6)),
              child: Text(leaf.v, style: GoogleFonts.manrope(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(leaf.t,
                  style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.ink),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
