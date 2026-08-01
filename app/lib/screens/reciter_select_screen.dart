import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../services/reciter_download_service.dart';
import '../theme/app_theme.dart';
import 'reciter_downloads_screen.dart';

/// Choix du récitateur. Chaque ligne dit EXPLICITEMENT si la récitation est
/// disponible hors-ligne ou si elle exige une connexion (demande utilisateur
/// 2026-07-28) : jusque-là tout était en streaming sans que ce soit dit, et
/// une bannière annonçait un téléchargement « disponible prochainement » qui
/// n'existait pas.
class ReciterSelectScreen extends StatefulWidget {
  final int currentId;
  const ReciterSelectScreen({super.key, required this.currentId});

  @override
  State<ReciterSelectScreen> createState() => _ReciterSelectScreenState();
}

class _ReciterSelectScreenState extends State<ReciterSelectScreen> {
  final _svc = ReciterDownloadService();

  /// Nombre de sourates téléchargées, par récitateur.
  final _offlineCount = <int, int>{};
  int _totalUsed = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final r in kReciters) {
      _offlineCount[r.id] = (await _svc.downloadedSurahs(r.id)).length;
    }
    final used = await _svc.bytesUsedTotal();
    if (mounted) setState(() => _totalUsed = used);
  }

  Future<void> _openDownloads(Reciter r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReciterDownloadsScreen(reciter: r)),
    );
    await _refresh();
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
                final selected = r.id == widget.currentId;
                final offline = _offlineCount[r.id] ?? 0;
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic
                            ? (r.style == 'Mujawwad' ? t.settingsStyleMujawwad : t.settingsStyleMurattal)
                            : '${r.nameFr}  •  ${r.style}',
                        style: GoogleFonts.manrope(
                            fontSize: 11, color: AppColors.inkLight),
                      ),
                      const SizedBox(height: 3),
                      _availabilityBadge(t, offline),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _openDownloads(r),
                        tooltip: t.reciterDownloadsTitle,
                        icon: Icon(
                          offline > 0
                              ? Icons.folder_open_rounded
                              : Icons.download_rounded,
                          color: AppColors.green700,
                          size: 20,
                        ),
                      ),
                      selected
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.green700)
                          : const Icon(Icons.radio_button_unchecked,
                              color: AppColors.cream300),
                    ],
                  ),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
          ),
          // Espace occupé, tous récitateurs confondus. Rendu visible ici parce
          // que l'audio va dans le stockage PRIVÉ de l'app : l'utilisateur ne
          // peut pas le retrouver dans un gestionnaire de fichiers, donc s'il
          // n'est pas affiché il est purement invisible.
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.green900,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.sd_storage_rounded,
                    color: AppColors.brass, size: 22),
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
                        t.reciterSelectStorageTotal(_fmtSize(_totalUsed)),
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

  /// Badge d'état : c'est LUI qui répond à « celui-là est en local, les autres
  /// c'est avec internet ». Volontairement textuel et pas seulement iconique.
  Widget _availabilityBadge(AppLocalizations t, int offline) {
    final full = offline >= 114;
    final some = offline > 0;
    final bg = some ? AppColors.green50 : AppColors.cream200;
    final fg = some ? AppColors.green700 : AppColors.inkLight;
    final label = full
        ? t.reciterBadgeOfflineFull
        : some
            ? t.reciterBadgeOfflinePartial('$offline', '114')
            : t.reciterBadgeOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(some ? Icons.offline_pin_rounded : Icons.cloud_outlined,
              size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.manrope(
                  fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2).replaceAll('.', ',')} Go';
    }
    if (bytes >= 1048576) return '${(bytes / 1048576).round()} Mo';
    if (bytes >= 1024) return '${(bytes / 1024).round()} ko';
    return '$bytes o';
  }
}
