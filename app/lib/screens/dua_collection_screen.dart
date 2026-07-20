import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/duas_data.dart';
import '../models/dua.dart';
import '../theme/app_theme.dart';
import '../widgets/dua_card.dart';

/// Liste des invocations d'une collection.
///
/// `highlightDuaId` sert au retour depuis les favoris : on ouvre la
/// collection sur la bonne carte, déjà dépliée, plutôt que de laisser
/// l'utilisateur la rechercher dans la liste.
class DuaCollectionScreen extends ConsumerWidget {
  final String collectionId;
  final String? highlightDuaId;

  const DuaCollectionScreen({
    super.key,
    required this.collectionId,
    this.highlightDuaId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = kCollectionsById[collectionId];
    final univers = kUniversByCollectionId[collectionId];
    final accent = univers?.color ?? AppColors.brass;
    final duas = duasForCollection(collectionId);

    // Une invocation mise en avant remonte en tête : sur une collection de
    // 15 entrées, la retrouver au milieu annulerait l'intérêt du raccourci.
    final ordered = highlightDuaId == null
        ? duas
        : [
            ...duas.where((d) => d.id == highlightDuaId),
            ...duas.where((d) => d.id != highlightDuaId),
          ];

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 132,
            backgroundColor: accent,
            foregroundColor: AppColors.cream,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14, right: 16),
              title: Text(
                collection?.labelFr ?? 'Invocations',
                style: GoogleFonts.fraunces(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cream,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.green900, accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          collection?.emoji ?? '🤲',
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          collection?.labelAr ?? '',
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                            fontSize: 20,
                            color: AppColors.brassLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (collection != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Text(
                  collection.hint,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.inkLight,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: ordered.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Cette collection est encore vide.',
                          style: TextStyle(color: AppColors.inkLight),
                        ),
                      ),
                    ),
                  )
                : SliverList.builder(
                    itemCount: ordered.length,
                    itemBuilder: (_, i) => DuaCard(
                      dua: ordered[i],
                      accent: accent,
                      initiallyExpanded:
                          highlightDuaId != null && ordered[i].id == highlightDuaId,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Liste d'invocations référencées par id — utilisée par l'écran de rite
/// pour afficher les duas propres à une étape.
class DuaIdList extends StatelessWidget {
  final List<String> duaIds;
  final Color accent;

  const DuaIdList({super.key, required this.duaIds, required this.accent});

  @override
  Widget build(BuildContext context) {
    final duas = duaIds.map((id) => kDuasById[id]).whereType<Dua>().toList();
    if (duas.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [for (final d in duas) DuaCard(dua: d, accent: accent)],
    );
  }
}
