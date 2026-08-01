import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/reciter_download_service.dart';
import '../theme/app_theme.dart';

/// Gestion du téléchargement hors-ligne, sourate par sourate, pour UN
/// récitateur. L'unité est la sourate parce qu'un récitateur complet pèse
/// ~1,6 Go (mesuré, cf. `reciter_download_service.dart`) : forcer ce volume à
/// qui ne veut qu'Al-Kahf n'aurait pas de sens. « Tout télécharger » reste
/// offert, il enfile simplement les 114.
class ReciterDownloadsScreen extends StatefulWidget {
  final Reciter reciter;
  const ReciterDownloadsScreen({super.key, required this.reciter});

  @override
  State<ReciterDownloadsScreen> createState() => _ReciterDownloadsScreenState();
}

class _ReciterDownloadsScreenState extends State<ReciterDownloadsScreen> {
  final _svc = ReciterDownloadService();

  List<Surah> _surahs = const [];
  Set<int> _downloaded = {};
  final _estimates = <int, int>{};
  final _progress = <int, SurahDownloadProgress>{};
  int _used = 0;
  int _estimateAll = 0;
  bool _loading = true;
  bool _bulk = false;
  StreamSubscription<SurahDownloadProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.progressStream.listen(_onProgress);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    // On n'annule PAS les téléchargements en quittant l'écran : ils sont
    // reprenables et l'utilisateur s'attend à ce qu'une grosse sourate
    // continue pendant qu'il navigue ailleurs.
    super.dispose();
  }

  Future<void> _load() async {
    final surahs = await QuranApi.fetchSurahs();
    final downloaded = await _svc.downloadedSurahs(widget.reciter.id);
    final used = await _svc.bytesUsed(widget.reciter.id);
    var all = 0;
    for (final s in surahs) {
      final b = await _svc.estimatedBytes(s.number);
      _estimates[s.number] = b;
      all += b;
    }
    if (!mounted) return;
    setState(() {
      _surahs = surahs;
      _downloaded = downloaded;
      _used = used;
      _estimateAll = all;
      _loading = false;
    });
  }

  void _onProgress(SurahDownloadProgress p) {
    if (!mounted || p.reciterId != widget.reciter.id) return;
    setState(() {
      if (p.phase == DownloadPhase.running) {
        _progress[p.surahNumber] = p;
      } else {
        _progress.remove(p.surahNumber);
        if (p.phase == DownloadPhase.complete) {
          _downloaded.add(p.surahNumber);
        } else if (p.phase == DownloadPhase.absent) {
          _downloaded.remove(p.surahNumber);
        }
      }
    });
    if (p.phase == DownloadPhase.complete || p.phase == DownloadPhase.absent) {
      _refreshUsed();
    }
    if (p.phase == DownloadPhase.failed && mounted) {
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.reciterDownloadFailed)));
    }
  }

  Future<void> _refreshUsed() async {
    final used = await _svc.bytesUsed(widget.reciter.id);
    if (mounted) setState(() => _used = used);
  }

  Future<void> _toggleSurah(Surah s) async {
    if (_svc.isDownloading(widget.reciter.id, s.number)) {
      _svc.cancel(widget.reciter.id, s.number);
      return;
    }
    if (_downloaded.contains(s.number)) {
      await _svc.deleteSurah(widget.reciter.id, s.number);
      return;
    }
    await _svc.downloadSurah(widget.reciter.id, s.number);
  }

  Future<void> _downloadAll() async {
    if (_bulk) {
      _svc.cancelAll();
      setState(() => _bulk = false);
      return;
    }
    setState(() => _bulk = true);
    for (final s in _surahs) {
      if (!mounted || !_bulk) break;
      if (_downloaded.contains(s.number)) continue;
      final ok = await _svc.downloadSurah(widget.reciter.id, s.number);
      // Un échec réseau interrompt la file : inutile d'enchaîner 113 échecs.
      // Ce qui est déjà sur le disque est conservé, une relance reprendra.
      if (!ok) break;
    }
    if (mounted) setState(() => _bulk = false);
  }

  Future<void> _deleteAll() async {
    final t = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.reciterDeleteAllTitle),
        content: Text(t.reciterDeleteAllBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t.reciterDeleteAllConfirm)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bulk = false);
    await _svc.deleteReciter(widget.reciter.id);
    if (!mounted) return;
    setState(() {
      _downloaded = {};
      _progress.clear();
      _used = 0;
    });
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
        title: Text(t.reciterDownloadsTitle,
            style: GoogleFonts.fraunces(fontSize: 18, color: AppColors.cream)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _header(t, isArabic),
                Expanded(
                  child: ListView.separated(
                    itemCount: _surahs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppColors.cream300),
                    itemBuilder: (context, i) => _surahTile(_surahs[i], t, isArabic),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(AppLocalizations t, bool isArabic) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: AppColors.green900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? widget.reciter.nameAr : widget.reciter.nameFr,
            style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.brassLight,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            t.reciterStorageUsed(
                _fmtSize(_used), '${_downloaded.length}', '${_surahs.length}'),
            style: GoogleFonts.manrope(
                fontSize: 11, color: AppColors.cream.withAlpha(180)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brass,
                    foregroundColor: AppColors.green900,
                  ),
                  onPressed: _downloadAll,
                  icon: Icon(
                      _bulk ? Icons.stop_rounded : Icons.download_rounded,
                      size: 18),
                  label: Text(
                    _bulk
                        ? t.reciterDownloadStop
                        : t.reciterDownloadAll(_fmtSize(_estimateAll)),
                    style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (_used > 0) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _deleteAll,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.cream,
                  tooltip: t.reciterDeleteAllTitle,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _surahTile(Surah s, AppLocalizations t, bool isArabic) {
    final prog = _progress[s.number];
    final done = _downloaded.contains(s.number);
    final estimate = _estimates[s.number] ?? 0;

    Widget trailing;
    if (prog != null) {
      trailing = SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: prog.fraction == 0 ? null : prog.fraction,
              strokeWidth: 2.5,
              color: AppColors.green700,
            ),
            const Icon(Icons.stop_rounded, size: 14, color: AppColors.green700),
          ],
        ),
      );
    } else if (done) {
      trailing = const Icon(Icons.delete_outline_rounded,
          color: AppColors.inkLight, size: 22);
    } else {
      trailing = const Icon(Icons.download_rounded,
          color: AppColors.green700, size: 22);
    }

    return ListTile(
      onTap: () => _toggleSurah(s),
      leading: CircleAvatar(
        backgroundColor: done ? AppColors.green700 : AppColors.green50,
        child: done
            ? const Icon(Icons.offline_pin_rounded,
                color: AppColors.cream, size: 18)
            : Text('${s.number}',
                style: GoogleFonts.manrope(
                    color: AppColors.green700,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
      ),
      title: Text(
        isArabic ? s.nameArabic : s.nameSimple,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        style: isArabic
            ? GoogleFonts.scheherazadeNew(fontSize: 18, color: AppColors.ink)
            : GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        prog != null
            ? t.reciterDownloadingProgress('${prog.done}', '${prog.total}')
            // « ≈ » assumé : la taille est estimée depuis la longueur du texte
            // (±12 % médian), pas mesurée — la mesurer exigerait un appel
            // réseau par sourate, exactement ce qu'on cherche à éviter.
            : done
                ? t.reciterSurahOffline
                : '≈ ${_fmtSize(estimate)}  •  ${s.versesCount} ${t.reciterVersesShort}',
        style: GoogleFonts.manrope(
            fontSize: 11,
            color: done ? AppColors.green700 : AppColors.inkLight),
      ),
      trailing: trailing,
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2).replaceAll('.', ',')} Go';
    }
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).round()} Mo';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} ko';
    return '$bytes o';
  }
}
