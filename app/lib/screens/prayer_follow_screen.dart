import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recitation_state.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';

/// "Suivre une prière" (demande utilisateur 2026-07-18) : point d'entrée
/// DÉDIÉ pour un imam qui mène la salât, sans choisir de sourate au
/// préalable -- contrairement au karaoké classique (ouvert depuis une
/// sourate précise sur l'écran de lecture), ici l'app détecte Al-Fatiha à
/// chaque rak'ah puis identifie automatiquement (même moteur que "Shazam
/// coranique") quelle sourate suit, qui peut différer d'une rak'ah à
/// l'autre. Toute la logique de cycle vit dans RecitationNotifier
/// (startPrayerFollow, PrayerPhase) -- cet écran affiche et pilote deux
/// réglages qui lui sont PROPRES (sensibilité + souffleur, demande
/// utilisateur 2026-07-19 : "indépendamment de la sensibilité dans la
/// récitation, ils peuvent avoir deux niveaux différents").
class PrayerFollowScreen extends ConsumerStatefulWidget {
  const PrayerFollowScreen({super.key});

  @override
  ConsumerState<PrayerFollowScreen> createState() => _PrayerFollowScreenState();
}

class _PrayerFollowScreenState extends ConsumerState<PrayerFollowScreen> {
  // Souffleur automatique sur hésitation longue -- même principe que
  // l'ancien mécanisme du karaoké classique (retiré de cet écran-là avec le
  // toggle "réciteur confiant", cf. 2026-07-18) : remis à zéro à chaque
  // avancée réelle du pointeur, déclenche la lecture du mot attendu si aucune
  // avancée n'a eu lieu depuis le délai -- seule aide offerte dans ce mode
  // (jamais de blocage, cf. RecitationNotifier._confidentMode).
  Timer? _silenceTimer;
  // Réduit de 6s à 3s (demande utilisateur 2026-07-19) : dans ce mode, le
  // pointeur peut déjà être en retard sur ce qui est réellement récité (cf.
  // SUIVI_PRIERE.md §3.4/§3.9) -- un délai plus court aide à rattraper plus
  // vite plutôt que de laisser un long silence avant la première aide.
  static const _kSilenceHintDelay = Duration(seconds: 3);
  bool _promptingWord = false;

  // Défilement automatique vers le mot courant (demande utilisateur
  // 2026-07-19 : "également rajoute le défilement... le texte reste figé")
  // -- une clé par mot pour pouvoir faire défiler jusqu'au mot en cours,
  // même principe que karaoke_recitation_screen.dart/mushaf_screen.dart.
  // Reconstruite à chaque fois que la liste de mots change de longueur
  // (changement de phase : Al-Fatiha <-> sourate identifiée).
  final _scrollController = ScrollController();
  List<GlobalKey> _wordKeys = [];

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentWord(int pointer) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || pointer < 0 || pointer >= _wordKeys.length) return;
      final ctx = _wordKeys[pointer].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    if (!ref.read(prayerSouffleurEnabledProvider)) return;
    _silenceTimer = Timer(_kSilenceHintDelay, () {
      final st = ref.read(recitationProvider);
      if (!mounted || st.status != RecitationStatus.listening) return;
      if (_promptingWord) return;
      DiagnosticLog.log('Souffleur',
          'hésitation longue (${_kSilenceHintDelay.inSeconds}s) -- souffleur automatique (Suivre une prière)');
      _promptCurrentWord();
    });
  }

  /// Joue l'extrait audio du mot actuellement attendu -- utilise
  /// `verseAndLocalIndexFor` (RecitationNotifier) pour retrouver le verset
  /// réel derrière le pointeur, qu'il appartienne à Al-Fatiha ou à la
  /// sourate identifiée par Shazam (ce mode n'a pas de liste de versets
  /// pré-chargée côté écran comme le karaoké classique).
  Future<void> _promptCurrentWord() async {
    if (_promptingWord) return;
    final notifier = ref.read(recitationProvider.notifier);
    final st = ref.read(recitationProvider);
    final target = notifier.verseAndLocalIndexFor(st.pointer);
    if (target == null) return;
    final (verse, local) = target;

    setState(() => _promptingWord = true);
    final verifier = ref.read(recitationVerifierProvider);
    final wasListening = st.status == RecitationStatus.listening;
    try {
      if (wasListening) await verifier.pauseCapture();
      final reciter = ref.read(playerProvider).reciter;
      try {
        await WordCorrectionAudio.playWordRange(verse, reciter,
            errorWordIndex: local, wordsBefore: 0, wordsAfter: 0);
      } catch (e) {
        DiagnosticLog.log('Souffleur', 'échec lecture (Suivre une prière) : $e');
      }
      await Future.delayed(const Duration(milliseconds: 400));
      if (wasListening) await verifier.resetBuffer();
      if (!mounted) return;
    } finally {
      if (wasListening) await verifier.resumeCapture();
      if (mounted) setState(() => _promptingWord = false);
    }
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final sensitivity = ref.watch(prayerSensitivityProvider);
          final souffleurEnabled = ref.watch(prayerSouffleurEnabledProvider);
          String label;
          if (sensitivity < 0.35) {
            label = 'Tolérant';
          } else if (sensitivity > 0.65) {
            label = 'Strict';
          } else {
            label = 'Équilibré (par défaut)';
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensibilité (suivi de prière)',
                      style: GoogleFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 6),
                  Text(
                    'Réglage indépendant de celui de la récitation classique -- '
                    'plus tolérant accepte des prononciations imprécises en vert, '
                    'plus strict exige davantage de précision.',
                    style: TextStyle(
                        color: AppColors.cream.withOpacity(0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Tolérant',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: sensitivity,
                          activeColor: AppColors.brassLight,
                          inactiveColor: Colors.white24,
                          onChanged: (v) =>
                              ref.read(prayerSensitivityProvider.notifier).state = v,
                        ),
                      ),
                      const Text('Strict',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  Center(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.brassLight,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.brassLight,
                    value: souffleurEnabled,
                    onChanged: (v) =>
                        ref.read(prayerSouffleurEnabledProvider.notifier).state = v,
                    title: Text('Souffleur automatique',
                        style: GoogleFonts.manrope(
                            color: AppColors.cream, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Joue le mot attendu après ${_kSilenceHintDelay.inSeconds}s '
                      'de silence -- jamais de blocage dans ce mode.',
                      style: TextStyle(
                          color: AppColors.cream.withOpacity(0.75), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(recitationProvider);
    final notifier = ref.read(recitationProvider.notifier);

    // Sensibilité EN DIRECT (comme le karaoké classique) -- effective sans
    // interrompre la session en cours.
    ref.listen(prayerSensitivityProvider, (prev, next) {
      notifier.setSensitivity(next);
    });
    // Souffleur automatique : toute avancée réelle du pointeur (ou entrée en
    // écoute) relance le délai de silence ; la sortie de l'écoute, le
    // standby (pas de "mot courant" légitime pendant rukū'/sujūd) ou Al-Fatiha
    // l'annule. Bug corrigé 2026-07-19 (retour utilisateur : "j'ai toujours
    // le mode correction qui se lance... la Fatiha est exclue de la
    // correction") -- Al-Fatiha était ABSENTE de cette liste d'exclusion,
    // alors que §3.17 (SUIVI_PRIERE.md) avait déjà établi la règle "aucune
    // correction pendant Al-Fatiha" côté coloration (gop forcé à `correct`) :
    // le souffleur, mécanisme de correction à part entière (joue l'audio du
    // mot attendu), n'avait jamais reçu la même exclusion et continuait de se
    // déclencher sur silence même pendant Al-Fatiha. Intention confirmée :
    // Al-Fatiha se contente d'ATTENDRE la fin de la récitation avant de
    // lancer détection puis correction -- aucune aide/correction avant ça.
    ref.listen(recitationProvider, (prev, next) {
      final eligible = next.status == RecitationStatus.listening &&
          next.prayerPhase != PrayerPhase.standby &&
          next.prayerPhase != PrayerPhase.detectingTarget &&
          next.prayerPhase != PrayerPhase.fatiha;
      if (eligible &&
          (next.pointer != prev?.pointer || prev?.status != RecitationStatus.listening)) {
        _resetSilenceTimer();
      } else if (!eligible) {
        _silenceTimer?.cancel();
      }
      // Défilement automatique : la liste de mots change de longueur à
      // chaque bascule de phase (Al-Fatiha <-> sourate identifiée) -- les
      // clés doivent être reconstruites avant que le pointeur suivant ne
      // tente d'y accéder.
      if (next.words.length != _wordKeys.length) {
        _wordKeys = List.generate(next.words.length, (_) => GlobalKey());
      }
      if (next.pointer != prev?.pointer) {
        _scrollToCurrentWord(next.pointer);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.green900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.cream),
        title: Text('Suivre une prière',
            style: GoogleFonts.manrope(
                color: AppColors.cream, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.cream),
            tooltip: 'Réglages',
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _PhaseBadge(phase: st.prayerPhase, active: st.isActive),
            const SizedBox(height: 8),
            Expanded(
              child: _WordsArea(
                state: st,
                scrollController: _scrollController,
                wordKeys: _wordKeys,
              ),
            ),
            _StartStopButton(
              state: st,
              notifier: notifier,
              onStart: () => notifier.setSensitivity(ref.read(prayerSensitivityProvider)),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _WordsArea extends StatelessWidget {
  final RecitationSessionState state;
  final ScrollController scrollController;
  final List<GlobalKey> wordKeys;
  const _WordsArea({
    required this.state,
    required this.scrollController,
    required this.wordKeys,
  });

  String get _emptyLabel {
    switch (state.prayerPhase) {
      case PrayerPhase.standby:
        return 'En attente du début d\'Al-Fatiha…';
      case PrayerPhase.detectingTarget:
        return 'Al-Fatiha terminée -- identification de la sourate suivante…';
      case PrayerPhase.fatiha:
      case PrayerPhase.target:
      case PrayerPhase.none:
        return state.isActive
            ? 'En écoute…'
            : 'Appuyez sur le micro pour commencer à suivre la prière.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state.words.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _emptyLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                color: AppColors.cream.withAlpha(190), fontSize: 15),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 16,
          children: [
            for (var i = 0; i < state.words.length; i++)
              KeyedSubtree(
                key: i < wordKeys.length ? wordKeys[i] : null,
                child: _WordChip(word: state.words[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  final RecitedWord word;
  const _WordChip({required this.word});

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color? border;
    var opacity = 1.0;
    switch (word.status) {
      case WordStatus.correct:
        bg = const Color(0xFF6fe3a8).withOpacity(0.38);
        border = const Color(0xFF6fe3a8);
      case WordStatus.unclear:
        bg = const Color(0xFFffcc80).withOpacity(0.42);
        border = const Color(0xFFffcc80);
      case WordStatus.error:
        if (word.locked) {
          bg = const Color(0xFFff8a80).withOpacity(0.42);
          border = const Color(0xFFff8a80);
        }
      case WordStatus.skipped:
        // Mots d'avant l'ancre d'identification (Shazam) -- jamais entendus
        // par l'ASR avant détection, ni jugés faux ni corrects.
        opacity = 0.35;
      case WordStatus.current:
        border = AppColors.brassLight;
      case WordStatus.pending:
        opacity = 0.5;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          bottom: BorderSide(color: border ?? Colors.transparent, width: 2),
        ),
      ),
      child: Opacity(
        opacity: opacity,
        child: Text(
          word.display,
          style: GoogleFonts.scheherazadeNew(
              fontSize: 26, height: 2.0, color: AppColors.cream),
        ),
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  final RecitationSessionState state;
  final RecitationNotifier notifier;
  final VoidCallback onStart;
  const _StartStopButton(
      {required this.state, required this.notifier, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final listening = state.status == RecitationStatus.listening;
    final busy = state.status == RecitationStatus.processing;
    return GestureDetector(
      onTap: busy
          ? null
          : () async {
              if (listening) {
                await notifier.stopContinuous();
              } else {
                await notifier.startPrayerFollow();
                onStart();
              }
            },
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: listening ? AppColors.brass : AppColors.green700,
          boxShadow: [
            BoxShadow(
                color: AppColors.brass.withAlpha(100),
                blurRadius: 16,
                spreadRadius: 2),
          ],
        ),
        child: Icon(
          listening ? Icons.stop_rounded : Icons.mic,
          color: AppColors.green900,
          size: 34,
        ),
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  final PrayerPhase phase;
  final bool active;
  const _PhaseBadge({required this.phase, required this.active});

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    switch (phase) {
      case PrayerPhase.standby:
        label = 'En attente (rukū\'/sujūd)';
        icon = Icons.pause_circle_outline_rounded;
      case PrayerPhase.fatiha:
        label = 'Al-Fatiha';
        icon = Icons.menu_book_rounded;
      case PrayerPhase.detectingTarget:
        label = 'Identification…';
        icon = Icons.search_rounded;
      case PrayerPhase.target:
        label = 'Sourate suivie';
        icon = Icons.record_voice_over_rounded;
      case PrayerPhase.none:
        label = active ? 'En écoute' : 'Arrêté';
        icon = Icons.mic_none_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.green800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.brassLight, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.manrope(
                  color: AppColors.cream,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
