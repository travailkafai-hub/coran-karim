// Sélecteur d'aya de départ pour le jeu de mémorisation — décision
// utilisateur 2026-07-22 : "pour les grandes sourates on fait depuis l'aya
// qui a choisi et on se limite sur une page" / "on va pas faire pour toute la
// sourate mais depuis l'aya qui va choisir pour commencer".
//
// N'apparaît QUE pour les sourates qui s'étendent sur plusieurs pages du
// Mushaf (cf. `coach_hub_screen.dart`, vérifié via `Verse.pageNumber`) : pour
// une sourate tenant sur une seule page, le jeu démarre directement sur la
// sourate entière, pas la peine de demander un point de départ.
//
// DEUX ÉTAPES (corrigé 2026-07-22, retour utilisateur direct : "il ne faut
// pas mettre toutes les ayat sur la page") -- la première version affichait
// une grille avec TOUTES les ayat de la sourate d'un coup (jusqu'à 286 puces
// pour Al-Baqarah), ce qui noie l'écran. On choisit maintenant d'abord la
// PAGE du Mushaf (une poignée de puces, jamais plus d'une quinzaine), puis
// seulement l'aya de départ PARMI CELLES DE CETTE PAGE (elle aussi limitée à
// une quinzaine tout au plus) -- cohérent avec la règle déjà en vigueur que
// la session de jeu elle-même ne dépasse jamais une page.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';

class MemorizationAyahPickerScreen extends StatefulWidget {
  final Surah surah;
  final List<Verse> verses; // toute la sourate, déjà chargée
  final void Function(List<Verse> pageVerses) onPicked;

  const MemorizationAyahPickerScreen({
    super.key,
    required this.surah,
    required this.verses,
    required this.onPicked,
  });

  @override
  State<MemorizationAyahPickerScreen> createState() =>
      _MemorizationAyahPickerScreenState();
}

class _MemorizationAyahPickerScreenState
    extends State<MemorizationAyahPickerScreen> {
  int? _selectedPage;

  List<int> get _pages {
    final pages = widget.verses.map((v) => v.pageNumber).whereType<int>().toSet().toList()
      ..sort();
    return pages;
  }

  List<Verse> _versesOfPage(int page) =>
      widget.verses.where((v) => v.pageNumber == page).toList();

  /// Depuis l'aya choisie, restreint à ce qui reste sur LA MÊME page du
  /// Mushaf (pas toute la sourate) -- exactement la règle demandée.
  void _pick(Verse chosen) {
    final page = chosen.pageNumber;
    final pageVerses = page == null
        ? [chosen]
        : widget.verses
            .where((v) => v.pageNumber == page && v.ayahNumber >= chosen.ayahNumber)
            .toList();
    widget.onPicked(pageVerses);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final pages = _pages;
    // Sourate à une seule page atteignant quand même cet écran (défensif) :
    // pas la peine de demander la page, direct sur le choix de l'aya.
    final page = pages.length <= 1 ? (pages.isEmpty ? null : pages.first) : _selectedPage;

    return Scaffold(
      backgroundColor: AppColors.gameBgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        leading: page != null && pages.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: t.memorizationAyahPickerBackToPages,
                onPressed: () => setState(() => _selectedPage = null),
              )
            : null,
        title: Text(t.memorizationAyahPickerTitle,
            style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              page == null
                  ? t.memorizationAyahPickerSubtitle(
                      isArabic ? widget.surah.nameArabic : widget.surah.nameSimple)
                  : t.memorizationAyahPickerAyahSubtitle(page),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
            ),
          ),
          Expanded(
            child: page == null
                ? _PageGrid(
                    pages: pages,
                    onPicked: (p) => setState(() => _selectedPage = p),
                  )
                : _AyahGrid(
                    verses: _versesOfPage(page),
                    onPicked: _pick,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Étape 1 : une puce par PAGE du Mushaf (une poignée d'éléments, jamais des
/// centaines) -- forme rectangulaire pour se distinguer visuellement des
/// puces d'aya (rondes, étape 2).
class _PageGrid extends StatelessWidget {
  final List<int> pages;
  final void Function(int page) onPicked;
  const _PageGrid({required this.pages, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.3,
      ),
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final page = pages[i];
        final color = AppColors.gameChipColors[i % AppColors.gameChipColors.length];
        return GestureDetector(
          onTap: () => onPicked(page),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              t.memorizationAyahPickerPageLabel(page),
              style: GoogleFonts.baloo2(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

/// Étape 2 : une puce par aya, mais UNIQUEMENT celles de la page choisie --
/// jamais plus d'une quinzaine (taille typique d'une page de Mushaf), jamais
/// la sourate entière.
class _AyahGrid extends StatelessWidget {
  final List<Verse> verses;
  final void Function(Verse verse) onPicked;
  const _AyahGrid({required this.verses, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: verses.length,
      itemBuilder: (context, i) {
        final v = verses[i];
        final color = AppColors.gameChipColors[i % AppColors.gameChipColors.length];
        return GestureDetector(
          onTap: () => onPicked(v),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '${v.ayahNumber}',
              style: GoogleFonts.baloo2(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}
