import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../theme/app_theme.dart';

class ReciterSelectScreen extends StatelessWidget {
  final int currentId;
  const ReciterSelectScreen({super.key, required this.currentId});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text(t.reciterSelectTitle,
            style: GoogleFonts.fraunces(
                fontSize: 18, color: AppColors.cream)),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header note
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.green50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.green100),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.green700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.reciterSelectStreamingNote,
                    style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.inkLight),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: kReciters.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: AppColors.cream300),
              itemBuilder: (context, i) {
                final r = kReciters[i];
                final selected = r.id == currentId;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor:
                        selected ? AppColors.brass : AppColors.green50,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.manrope(
                        color: selected
                            ? AppColors.green900
                            : AppColors.green700,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(r.nameAr,
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.scheherazadeNew(
                          fontSize: 18,
                          color: AppColors.ink,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal)),
                  subtitle: Text(
                    isArabic
                        ? (r.style == 'Mujawwad' ? t.settingsStyleMujawwad : t.settingsStyleMurattal)
                        : '${r.nameFr}  •  ${r.style}',
                    style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.inkLight),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.green700)
                      : const Icon(Icons.radio_button_unchecked,
                          color: AppColors.cream300),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
          ),
          // Coming soon banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.green900,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.download_rounded, color: AppColors.brass, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.reciterSelectOfflineTitle,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.brassLight,
                              fontWeight: FontWeight.w700)),
                      Text(
                        t.reciterSelectOfflineSubtitle,
                        style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: AppColors.cream.withAlpha(160)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
