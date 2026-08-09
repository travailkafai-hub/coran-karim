import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
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
  // Passage a souffler quand la chaine constate un trou (mode priere).
  // Cf. RecitationNotifier.sautASouffler : ce n'est PAS un verdict, et rien
  // n'attend que l'imam repete -- on lui fait entendre, il continue.
  StreamSubscription<({int de, int a})>? _sautSub;
  int _dernierMotSuivi = -1;
  Timer? _silenceTimer;
  // Réduit de 6s à 3s (demande utilisateur 2026-07-19) : dans ce mode, le
  // pointeur peut déjà être en retard sur ce qui est réellement récité (cf.
  // SUIVI_PRIERE.md §3.4/§3.9) -- un délai plus court aide à rattraper plus
  // vite plutôt que de laisser un long silence avant la première aide.
  //
  // ── REMONTÉ À 8 s (demande utilisateur 2026-08-07) ─────────────────────
  //
  // Le raisonnement de 2026-07-19 supposait que le pointeur immobile signifie
  // « il hésite ». La mesure du 2026-08-07 montre que c'est faux, et
  // pourquoi : à 09:44:31 l'identification pose l'ancre au mot 177 (34:11) ;
  // à 09:44:34, soit 3 s plus tard EXACTEMENT, le souffleur part. Le pointeur
  // n'avait pas bougé non pas parce que l'imam se taisait -- le décodage
  // libre de la même seconde entend `مَلُوغُونَ بَصِيرٌ`, `نِِعْمَلَ سَ`,
  // `رَاتٍ وَقَقَدْد فِى ٱلسَّرْد`, il récitait sans interruption -- mais parce
  // que l'application regardait au mauvais endroit.
  //
  // Un délai court transforme donc chaque erreur de position en interruption.
  // Et pendant la salât, 3 s de silence sont ORDINAIRES : souffle entre deux
  // versets, pause avant d'enchaîner la sourate après Al-Fatiha, descente en
  // rukū'. Le souffleur est une PROPOSITION (« l'imam n'est pas obligé
  // d'attendre et d'écouter ») -- il doit se faire rare.
  //
  // 8 s : au-delà de toute respiration normale, en deçà d'un vrai blanc de
  // mémoire. Valeur à ajuster à l'usage, c'est une constante nommée.
  // Porté à 4 s (demande utilisateur 2026-08-07). NOTE : ce n'était PAS la
  // cause du déclenchement analysé ce jour-là -- cf. `_jugementDepuisCible`
  // juste en dessous. Le délai reste un confort, pas un correctif.
  static const _kSilenceHintDelay = Duration(seconds: 4);

  /// Un mot au moins a-t-il été jugé depuis le dernier changement de cible ?
  ///
  /// ── LE MINUTEUR MESURAIT LA LATENCE DE L'APP (corrigé 2026-08-07) ──────
  ///
  /// L'utilisateur : « je n'ai pas mémoire d'avoir fait 3 s de silence ».
  /// Il avait raison, et le journal le montre :
  ///     09:44:29.79  retranscription "وَأَلَنَّا لَهُ ٱلْحَدِيدَ…"  (34:10)
  ///     09:44:31.92  cible v2 posée, 883 mots, pointeur -> 177
  ///     09:44:34.66  [Souffleur] hésitation longue (3s)
  ///     09:44:37.34  v2 entend "مَلُوغُونَ بَصِيرٌ"           (34:11)
  /// Il récitait avant, il récitait après. Le minuteur est réarmé à chaque
  /// déplacement du pointeur ; le passage de la phase `detectingTarget` à
  /// `target` a fait sauter le pointeur à 177 et l'a donc armé -- alors que
  /// l'application n'avait encore RIEN pu juger sur cette cible toute neuve.
  ///
  /// Allonger le délai ne corrige pas cela, il le retarde. La condition qui
  /// manque est celle-ci : ne pas parler d'hésitation tant qu'on n'a pas
  /// prouvé qu'on sait juger cette cible. Un seul mot jugé suffit.
  bool _jugementDepuisCible = false;

  /// Contexte joue AUTOUR du passage saute (cf. `_soufflerPassage`).
  /// Un peu avant pour situer, un peu plus apres pour relancer.
  /// Duree jouee par le souffleur, en fraction de la plage complete.
  /// « L'audio de repetition est un peu long, reduis de 20 % » (2026-08-07).
  static const _kFacteurDureeSouffle = 0.8;
  static const _kMotsAvantSouffle = 2;
  static const _kMotsApresSouffle = 3;
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
  void initState() {
    super.initState();
    // ── ECOUTE IMMEDIATE (demande utilisateur 2026-08-07) ─────────────────
    // « Quand je clique sur suivre la priere, lance directement l'ecoute. »
    // On n'entre pas sur cet ecran par curiosite : on y entre parce que la
    // priere commence. Un tap de plus n'ajoute rien et fait rater le takbir.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final st = ref.read(recitationProvider);
      if (st.status == RecitationStatus.listening) return;
      DiagnosticLog.log('Priere',
          'demarrage automatique a l\'ouverture de l\'ecran');
      await ref.read(recitationProvider.notifier).startPrayerFollow();
      if (mounted) _scrollToCurrentWord(0);
    });
    _sautSub = ref
        .read(recitationProvider.notifier)
        .sautASouffler
        .listen(_soufflerPassage);
  }

  /// Joue l'audio du recitateur sur les mots [bornes.de]..[bornes.a].
  ///
  /// Volontairement SANS effet de bord : pas de recul d'ancre, pas d'attente,
  /// pas de replacement du curseur. Apres la lecture, la chaine continue de
  /// suivre l'imam la ou il en est reellement -- « on ne force pas a suivre »
  /// (utilisateur, 2026-08-07).
  Future<void> _soufflerPassage(({int de, int a}) bornes) async {
    if (!mounted || _promptingWord) return;
    final notifier = ref.read(recitationProvider.notifier);
    final debut = notifier.verseAndLocalIndexFor(bornes.de);
    if (debut == null) return;
    final (verse, local) = debut;
    final st = ref.read(recitationProvider);
    setState(() => _promptingWord = true);
    final verifier = ref.read(recitationVerifierProvider);
    final wasListening = st.status == RecitationStatus.listening;
    try {
      if (wasListening) await verifier.pauseCapture();
      try {
        // ── DU CONTEXTE AUTOUR DU PASSAGE (demande utilisateur 2026-08-07)
        //
        // « Rajoute le souffleur, il dit un peu avant et un peu plus apres,
        // style 5 mots. »
        //
        // Souffler le trou NU ne suffit pas a raccrocher : l'imam a besoin
        // d'entendre ou ca s'attache. Un peu avant pour reconnaitre l'endroit,
        // un peu PLUS apres pour repartir avec de l'elan -- c'est la meme
        // raison qui avait fait passer la correction de recitation a
        // « le mot plus le suivant » (2026-08-05).
        //
        // BORNES DU VERSET : `playWordRange` travaille a l'interieur d'UN
        // verset. Si le contexte deborde, ses propres garde-fous ramenent au
        // premier/dernier segment disponible -- on souffle alors un peu moins,
        // jamais le mauvais passage.
        await WordCorrectionAudio.playWordRange(
          verse, ref.read(playerProvider).reciter,
          errorWordIndex: local,
          wordsBefore: _kMotsAvantSouffle,
          wordsAfter: (bornes.a - bornes.de) + _kMotsApresSouffle,
        );
      } catch (e) {
        DiagnosticLog.log('Priere', 'souffle du passage impossible : $e');
      }
      // Le tampon est vide APRES la lecture : sans ca, l'audio du recitateur
      // capte par le micro se retrouverait dans la fenetre suivante et serait
      // pris pour la voix de l'imam.
      if (wasListening) await verifier.resetBuffer();
    } finally {
      if (wasListening) await verifier.resumeCapture();
      if (mounted) setState(() => _promptingWord = false);
    }
  }

  @override
  void dispose() {
    _sautSub?.cancel();
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
            errorWordIndex: local,
            wordsBefore: 0,
            wordsAfter: 0,
            facteurDuree: _kFacteurDureeSouffle);
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
          final t = AppLocalizations.of(context)!;
          final sensitivity = ref.watch(prayerSensitivityProvider);
          final souffleurEnabled = ref.watch(prayerSouffleurEnabledProvider);
          final followFree = ref.watch(followWithoutBlockingProvider);
          String label;
          if (sensitivity < 0.35) {
            label = t.prayerFollowSensitivityTolerant;
          } else if (sensitivity > 0.65) {
            label = t.prayerFollowSensitivityStrict;
          } else {
            label = t.prayerFollowSensitivityBalanced;
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.prayerFollowSensitivityTitle,
                      style: GoogleFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream)),
                  const SizedBox(height: 6),
                  Text(
                    t.prayerFollowSensitivityDescription,
                    style: TextStyle(
                        color: AppColors.cream.withOpacity(0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(t.prayerFollowSensitivityTolerant,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: sensitivity,
                          activeColor: AppColors.brassLight,
                          inactiveColor: Colors.white24,
                          onChanged: (v) =>
                              ref.read(prayerSensitivityProvider.notifier).state = v,
                        ),
                      ),
                      Text(t.prayerFollowSensitivityStrict,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                    title: Text(t.prayerFollowSouffleurTitle,
                        style: GoogleFonts.manrope(
                            color: AppColors.cream, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      t.prayerFollowSouffleurSubtitle(_kSilenceHintDelay.inSeconds),
                      style: TextStyle(
                          color: AppColors.cream.withOpacity(0.75), fontSize: 12),
                    ),
                  ),
                  // "Suivre sans bloquer" -- DÉPLACÉ ici depuis la sheet de
                  // vérification du karaoké le 2026-08-01 (demande
                  // utilisateur : ce réglage appartient au suivi de prière,
                  // pas à la récitation générale). Même provider, même
                  // logique (cf. karaoke_recitation_screen.dart::_onWordFailed) :
                  // seul le point de réglage change de place.
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.brassLight,
                    value: followFree,
                    onChanged: (v) =>
                        ref.read(followWithoutBlockingProvider.notifier).set(v),
                    title: Text(t.karaokeFollowFreeTitle,
                        style: GoogleFonts.manrope(
                            color: AppColors.cream, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      followFree
                          ? t.karaokeFollowFreeOnSubtitle
                          : t.karaokeFollowFreeOffSubtitle,
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
    final t = AppLocalizations.of(context)!;
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
      // Cible neuve (la sourate vient d'être identifiée, ou un takbir a tout
      // remis à zéro) : on repart sans preuve de jugement.
      if (next.words.length != prev?.words.length) _jugementDepuisCible = false;
      // ── `skipped` N'EST PAS UN JUGEMENT (corrige 2026-08-07) ───────────
      //
      // Ce garde-fou a ete mis en echec par mon propre code. Quand la sourate
      // est identifiee, `_beginIdentifiedTargetPhase` marque tous les mots
      // AVANT le point d'entree en `skipped` -- une facon de dire « on n'a pas
      // commence la ». Le test « un statut autre que pending/current » les
      // comptait comme des jugements, donc le souffleur s'armait AUSSITOT.
      //
      // MESURE (session 17:58) : cible posee a 17:58:15,5 sur 893 mots avec
      // 407 mots marques passes ; souffleur declenche a 17:58:19,3, soit 3,8 s
      // plus tard, sans qu'un seul mot ait ete reellement juge.
      //
      // On ne compte donc QUE les verdicts reels : vert, orange, rouge. Un mot
      // « passe » ou « en attente » ne prouve rien sur la capacite de la
      // chaine a juger cette cible.
      if (!_jugementDepuisCible &&
          next.words.any((w) =>
              w.status == WordStatus.correct ||
              w.status == WordStatus.unclear ||
              w.status == WordStatus.error)) {
        _jugementDepuisCible = true;
      }
      final eligible = _jugementDepuisCible &&
          next.status == RecitationStatus.listening &&
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
      // ── SUIVRE LE MOT MARQUE, PAS LE POINTEUR (corrige 2026-08-07) ────
      //
      // `_onV2` pose bien `WordStatus.current` sur le mot en cours, mais ne
      // met JAMAIS a jour `state.pointer` -- il n'ecrit que `words`. Le
      // defilement, cale sur `pointer`, ne se declenchait donc jamais :
      // « il n'y a pas le scrolling qui suit » (utilisateur).
      //
      // L'ecran de recitation ne s'y trompe pas : il cherche l'index du mot
      // marque `current`. On fait pareil ici plutot que de toucher a la
      // chaine -- meme source de verite, meme comportement.
      final courant = next.words.indexWhere(
          (w) => w.status == WordStatus.current);
      if (courant >= 0 && courant != _dernierMotSuivi) {
        _dernierMotSuivi = courant;
        _scrollToCurrentWord(courant);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.green900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.cream),
        title: Text(t.prayerFollowTitle,
            style: GoogleFonts.manrope(
                color: AppColors.cream, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.cream),
            tooltip: t.prayerFollowSettingsTooltip,
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

class _WordsArea extends ConsumerWidget {
  final RecitationSessionState state;
  final ScrollController scrollController;
  final List<GlobalKey> wordKeys;
  const _WordsArea({
    required this.state,
    required this.scrollController,
    required this.wordKeys,
  });

  /// Le mot [i] est-il le DERNIER de son verset ? Meme source de verite que
  /// le souffleur (`verseAndLocalIndexFor`), donc jamais de decalage entre ce
  /// qu'on affiche et ce qu'on juge.
  bool _finDeVerset(WidgetRef ref, int i) {
    final n = ref.read(recitationProvider.notifier);
    final ici = n.verseAndLocalIndexFor(i);
    if (ici == null) return false;
    if (i + 1 >= state.words.length) return true;
    final suivant = n.verseAndLocalIndexFor(i + 1);
    return suivant == null || suivant.$1.key != ici.$1.key;
  }

  int _numeroVerset(WidgetRef ref, int i) =>
      ref.read(recitationProvider.notifier).verseAndLocalIndexFor(i)?.$1
          .ayahNumber ??
      0;

  String _emptyLabel(AppLocalizations t) {
    switch (state.prayerPhase) {
      case PrayerPhase.standby:
        return t.prayerFollowWaitingFatiha;
      case PrayerPhase.detectingTarget:
        return t.prayerFollowIdentifying;
      case PrayerPhase.fatiha:
      case PrayerPhase.target:
      case PrayerPhase.none:
        return state.isActive
            ? t.prayerFollowListening
            : t.prayerFollowTapToStart;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.words.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _emptyLabel(AppLocalizations.of(context)!),
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
            // ── LE MEME REPERAGE QU'EN RECITATION (2026-08-07) ───────────
            //
            // « Ce n'est toujours pas le meme affichage que la recitation :
            // on a les numeros d'ayat, les separations de sourates. »
            //
            // Cet ecran n'affichait qu'une suite de mots, sans aucun repere :
            // sur 893 mots d'une sourate, impossible de savoir ou l'on est.
            // On rend donc le numero de verset a sa FIN, comme le fait
            // l'ecran de recitation -- meme convention (le numero clot le
            // verset, il ne l'ouvre pas), meme source de verite
            // (`verseAndLocalIndexFor`, qui connait le decoupage reel).
            for (var i = 0; i < state.words.length; i++) ...[
              KeyedSubtree(
                key: i < wordKeys.length ? wordKeys[i] : null,
                child: _WordChip(word: state.words[i]),
              ),
              if (_finDeVerset(ref, i)) _BadgeVerset(_numeroVerset(ref, i)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Numero de verset, pose APRES son dernier mot -- meme convention que
/// l'ecran de recitation (le numero clot le verset).
class _BadgeVerset extends StatelessWidget {
  final int numero;
  const _BadgeVerset(this.numero);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.brassLight.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$numero',
            style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brassLight)),
      );
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
    final t = AppLocalizations.of(context)!;
    final String label;
    final IconData icon;
    switch (phase) {
      case PrayerPhase.standby:
        label = t.prayerPhaseStandby;
        icon = Icons.pause_circle_outline_rounded;
      case PrayerPhase.fatiha:
        label = t.prayerPhaseFatiha;
        icon = Icons.menu_book_rounded;
      case PrayerPhase.detectingTarget:
        label = t.prayerPhaseDetecting;
        icon = Icons.search_rounded;
      case PrayerPhase.target:
        label = t.prayerPhaseTarget;
        icon = Icons.record_voice_over_rounded;
      case PrayerPhase.none:
        label = active ? t.prayerPhaseListening : t.prayerPhaseStopped;
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
