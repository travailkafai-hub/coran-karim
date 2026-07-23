import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../providers/recitation_provider.dart';
import '../services/quran_verse_locator_service.dart';
import '../theme/app_theme.dart';

/// Ouvre la feuille d'écoute "Shazam coranique" (demande utilisateur
/// 2026-07-18) et retourne le verset identifié, ou `null` si l'utilisateur
/// ferme la feuille sans résultat retenu.
Future<QuranMatch?> showQuranShazamSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<QuranMatch>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ShazamSheet(),
  );
}

enum _ShazamState { listening, searching, found, notFound, error }

/// Durée d'écoute fixe avant de tenter la recherche (version simple retenue
/// par l'utilisateur : identifie puis affiche, pas de suivi continu ensuite).
/// Assez long pour recueillir plusieurs mots distinctifs (la recherche exige
/// au moins 4 mots, cf. QuranVerseLocatorService), assez court pour rester
/// réactif comme un vrai "Shazam".
const _kListenDuration = Duration(seconds: 7);

class _ShazamSheet extends ConsumerStatefulWidget {
  const _ShazamSheet();

  @override
  ConsumerState<_ShazamSheet> createState() => _ShazamSheetState();
}

class _ShazamSheetState extends ConsumerState<_ShazamSheet> {
  _ShazamState _state = _ShazamState.listening;
  QuranMatch? _match;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _state = _ShazamState.listening);
    final verifier = ref.read(recitationVerifierProvider);
    var latest = '';
    final sub = verifier.rawTranscript.listen((t) => latest = t);
    try {
      // Pas de texte attendu (expectedWords vide) : contrairement à la
      // récitation karaoké, le passage est encore INCONNU -- on veut la
      // transcription libre (greedy), pas un alignement forcé sur une cible.
      await verifier.start(const [], continuous: false);
      await Future.delayed(_kListenDuration);
      await verifier.stop();
    } catch (e) {
      await sub.cancel();
      if (!mounted) return;
      setState(() => _state = _ShazamState.error);
      return;
    }
    await sub.cancel();
    if (!mounted) return;
    setState(() => _state = _ShazamState.searching);
    final match = await QuranVerseLocatorService.instance.locate(latest);
    if (!mounted) return;
    setState(() {
      _match = match;
      _state = match == null ? _ShazamState.notFound : _ShazamState.found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _icon(),
            const SizedBox(height: 18),
            Text(
              _label(t),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            if (_state == _ShazamState.found && _match != null) ...[
              const SizedBox(height: 8),
              Text(
                t.shazamMatchLabel(_match!.surahNumber, _match!.ayahNumber),
                style: GoogleFonts.manrope(
                    fontSize: 14, color: AppColors.inkLight),
              ),
            ],
            const SizedBox(height: 22),
            _actions(t),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    if (_state == _ShazamState.listening) {
      return const _PulsingMicIcon();
    }
    final (icon, color) = switch (_state) {
      _ShazamState.searching => (Icons.search_rounded, AppColors.green800),
      _ShazamState.found => (Icons.check_circle_rounded, AppColors.green800),
      _ShazamState.notFound => (Icons.help_outline_rounded, AppColors.brass),
      _ShazamState.error => (Icons.error_outline_rounded, Colors.redAccent),
      _ShazamState.listening => (Icons.hearing_rounded, AppColors.green800),
    };
    return Icon(icon, size: 48, color: color);
  }

  String _label(AppLocalizations t) {
    switch (_state) {
      case _ShazamState.listening:
        return t.shazamListening;
      case _ShazamState.searching:
        return t.shazamSearching;
      case _ShazamState.found:
        return t.shazamFound;
      case _ShazamState.notFound:
        return t.shazamNotFound;
      case _ShazamState.error:
        return t.shazamError;
    }
  }

  Widget _actions(AppLocalizations t) {
    if (_state == _ShazamState.found) {
      return FilledButton(
        onPressed: () => Navigator.of(context).pop(_match),
        style: FilledButton.styleFrom(backgroundColor: AppColors.green800),
        child: Text(t.shazamGoThere),
      );
    }
    if (_state == _ShazamState.notFound || _state == _ShazamState.error) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.commonClose),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _run,
            style: FilledButton.styleFrom(backgroundColor: AppColors.green800),
            child: Text(t.commonRetry),
          ),
        ],
      );
    }
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(t.commonCancel),
    );
  }
}

/// Icône micro qui pulse doucement pendant l'écoute -- seul retour visuel
/// pendant les ~7s d'enregistrement (pas de niveau sonore affiché : cet
/// écran écoute l'AMBIANCE, pas la voix de l'utilisateur, un vu-mètre serait
/// trompeur).
class _PulsingMicIcon extends StatefulWidget {
  const _PulsingMicIcon();
  @override
  State<_PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<_PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: const Icon(Icons.hearing_rounded,
          size: 48, color: AppColors.green800),
    );
  }
}
