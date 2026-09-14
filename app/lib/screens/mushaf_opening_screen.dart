import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/riwaya.dart';
import '../providers/app_settings_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/mushaf_lignes_service.dart';
import '../services/mushaf_opening_position.dart';
import '../services/quran_api.dart';
import '../widgets/mushaf_cover_reveal.dart';
// `mushaf_maquette_screen.dart` n'est plus importe ici depuis le
// 2026-09-14 : la couverture ne l'ouvre plus (cf. build()).

/// Cold-launch presentation only. Recitation intents bypass this route.
class MushafOpeningScreen extends ConsumerStatefulWidget {
  const MushafOpeningScreen({super.key});

  @override
  ConsumerState<MushafOpeningScreen> createState() =>
      _MushafOpeningScreenState();
}

class _MushafOpeningScreenState extends ConsumerState<MushafOpeningScreen> {
  int? _page;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Future.microtask(_prepare);
  }

  Future<void> _prepare() async {
    try {
      final page = await _loadPage().timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      DiagnosticLog.log('Lecture', 'ChGPT ouverture mushaf impossible : $e');
      // An asset/preferences failure must never lock the user behind a cover.
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<int> _loadPage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return 1;
    final riwaya = prefs.getString('riwaya') == 'warsh'
        ? Riwaya.warsh
        : Riwaya.hafs;
    // Restore through the existing setter, before reading any Quran cache.
    await ref.read(riwayaProvider.notifier).set(riwaya);
    if (!mounted) return 1;
    ref.read(modeSombreProvider);
    ref.read(policeMushafPageProvider);
    ref.read(tajwidMushafPageProvider);
    final position = await lireDernierePositionLecture();
    var page = await MushafOpeningPosition.read(riwaya, position);
    if (page == null && position != null) {
      final verses = await QuranApi.fetchVerses(position.$1);
      page = verses
          .where((v) => v.ayahNumber == position.$2)
          .firstOrNull
          ?.pageNumber;
    }
    page = (page ?? 1).clamp(1, 604);
    final verses = riwaya == Riwaya.warsh
        ? await QuranApi.fetchWarshMushafVersesByPage(page)
        : await QuranApi.fetchVersesByPage(page);
    if (verses.isEmpty) throw StateError('Empty mushaf page $page');
    if (riwaya == Riwaya.hafs) {
      await MushafLignesService.instance.ensureLoaded();
    }
    // Amiri is already bundled, including the cover title. No new font or
    // network download is introduced by this presentation.
    await GoogleFonts.pendingFonts([
      GoogleFonts.amiri(),
      GoogleFonts.amiri(fontWeight: FontWeight.w700),
    ]);
    DiagnosticLog.log('Lecture', 'ChGPT ouverture ${riwaya.name} page=$page');
    return page;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── L'OUVERTURE DEBOUCHE SUR LA PAGE PRINCIPALE (2026-09-14) ─────────────
  //
  // Demande utilisateur : « je veux que l'ouverture, la couverture, n'atterrisse
  // pas dans le mushaf papier mais dans la page principale [...] où le menu
  // sera affiché ».
  //
  // AVANT, la couverture s'ouvrait SUR `MushafMaquetteScreen` : l'application
  // demarrait donc en lecture papier, plein ecran et sans barre d'onglets --
  // aucun menu, et rien n'indiquait comment rejoindre le reste de
  // l'application.
  //
  // MAINTENANT la route est TRANSPARENTE (`opaque: false`, cf. `main.dart`) et
  // la couverture s'ouvre sur ce qu'il y a DESSOUS, c'est-a-dire les onglets
  // deja montes. Quand l'animation est finie, cette route se referme d'elle-
  // meme et l'utilisateur est sur la page principale, menu compris.
  //
  // Le prechargement de `_prepare()` est CONSERVE tel quel : position de
  // lecture, riwaya, polices du mushaf. Il servait deja a autre chose qu'a
  // afficher cet ecran -- le supprimer reporterait ce cout sur la premiere
  // ouverture du mushaf.
  @override
  Widget build(BuildContext context) => MushafCoverReveal(
    ready: _page != null,
    onTermine: () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    },
    child: const SizedBox.shrink(),
  );
}
