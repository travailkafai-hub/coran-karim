// Sélecteur de sourate réutilisable (REFONTE_IHM.md §11.2, zones B et C).
//
// POURQUOI UN ÉCRAN DÉDIÉ : le hub Coach doit lancer soit la mémorisation
// (CoachScreen) soit la récitation (KaraokeRecitationScreen), qui attendent
// tous deux une `List<Verse>`. Sans ce sélecteur, il faudrait dupliquer une
// liste de sourates dans chaque zone -- exactement le copier-coller que la
// demande interdit. Ici : UNE liste, deux usages, le `onPicked` décide.
//
// Charge les versets de la sourate choisie avant de rendre la main, pour que
// l'appelant n'ait jamais à gérer l'asynchrone lui-même.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';

class SurahPickerScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final void Function(Surah surah, List<Verse> verses) onPicked;

  const SurahPickerScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPicked,
  });

  @override
  State<SurahPickerScreen> createState() => _SurahPickerScreenState();
}

class _SurahPickerScreenState extends State<SurahPickerScreen> {
  List<Surah>? _surahs;
  String? _error;
  int? _loadingSurah; // sourate dont on charge les versets (feedback visuel)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await QuranApi.fetchSurahs();
      if (!mounted) return;
      setState(() => _surahs = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pick(Surah surah) async {
    if (_loadingSurah != null) return; // évite le double-tap
    setState(() => _loadingSurah = surah.number);
    try {
      final verses = await QuranApi.fetchVerses(surah.number);
      if (!mounted) return;
      widget.onPicked(surah, verses);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSurah = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.surahPickerLoadVersesError('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.subtitle,
                style: GoogleFonts.manrope(
                    fontSize: 11, color: AppColors.brassLight)),
          ],
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.surahPickerLoadListError(_error!),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: AppColors.inkLight)),
              ),
            )
          : _surahs == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.green700))
              : ListView.separated(
                  itemCount: _surahs!.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.cream300),
                  itemBuilder: (context, i) {
                    final s = _surahs![i];
                    final loading = _loadingSurah == s.number;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.brass, width: 1.5),
                          color: AppColors.cream200,
                        ),
                        alignment: Alignment.center,
                        child: Text('${s.number}',
                            style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brass)),
                      ),
                      title: Text(isArabic ? s.nameArabic : s.nameSimple,
                          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                          style: isArabic
                              ? GoogleFonts.scheherazadeNew(
                                  fontSize: 18, color: AppColors.ink)
                              : GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                      subtitle: Text(t.surahPickerVerseCount(s.versesCount),
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: AppColors.inkLight)),
                      trailing: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.green700))
                          : isArabic
                              ? null
                              : Text(s.nameArabic,
                                  textDirection: TextDirection.rtl,
                                  style: GoogleFonts.scheherazadeNew(
                                      fontSize: 20, color: AppColors.green800)),
                      onTap: () => _pick(s),
                    );
                  },
                ),
    );
  }
}
