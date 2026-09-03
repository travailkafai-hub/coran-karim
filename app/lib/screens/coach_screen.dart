import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/coach_session.dart';
import '../models/recitation_state.dart';
import '../models/riwaya.dart' show Riwaya;
import '../models/verse.dart';
import '../providers/app_settings_provider.dart'
    show coachPassageAutoProvider, coachControleCumulatifProvider;
import '../providers/coach_provider.dart';
import '../providers/last_coach_verse_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/portion_word_archiver.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart';
import '../services/voice_fingerprint_service.dart';
import '../theme/app_theme.dart';
import 'coach_incremental_repeat.dart';
import 'coach_sessions.dart' show portionsProvider;
import 'tajwid_rules_screen.dart';
import '../widgets/tajwid_help_sheet.dart';
import '../widgets/tajweed_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class CoachScreen extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const CoachScreen({super.key, required this.verses});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  /// Derniere taille de cible de controle journalisee -- evite de repeter la
  /// ligne a chaque frame (le build tourne des dizaines de fois par seconde).
  int _dernierTraceControle = -1;

  // ── JAMAIS DÉMARRER UNE SESSION SUR LA SEULE BISMILLAH (2026-08-09) ───────
  //
  // Demande utilisateur : « il ne faut jamais se lancer sur Bismillah, ça
  // doit passer directement au suivant ». Seul verset qui EST la Bismillah
  // dans les données de l'app : Al-Fatiha 1:1 (`QuranApi.fetchBismillah`
  // pointe dessus). Partout ailleurs (récitation live), elle est exclue de
  // tout jugement -- ce n'est pas un contenu à mémoriser en soi, l'y lancer
  // (ex. Mushaf positionné dessus au moment d'ouvrir "Mémoriser", qui ne
  // passe qu'UN verset) donnerait une session sans objet.
  //
  // Résolu ICI plutôt qu'à chaque point d'entrée (Mushaf, fiche d'un mot en
  // erreur, hub Coach...) pour n'exister qu'à un seul endroit. `_verses` est
  // `null` tant que la résolution n'est pas faite -- `build()` affiche un
  // simple indicateur de chargement pendant ce temps plutôt que de risquer
  // un flash de la Bismillah le temps d'un premier frame (elle était encore
  // lisible via `widget.verses.first` avant que `setup()` ne s'exécute).
  List<Verse>? _verses;

  @override
  void initState() {
    super.initState();
    // ⚠️ DANS le post-frame, pas directement dans initState : lire
    // AppLocalizations (donc `context`) avant le premier frame lève
    // « dependOnInheritedWidgetOfExactType<_LocalizationsScope>() was called
    // before _CoachScreenState.initState() completed » et l'écran entier
    // s'affiche en rouge d'erreur (constaté sur device 2026-07-22). Toute la
    // résolution (Bismillah comprise) est donc faite APRÈS ce premier frame,
    // pas seulement la lecture d'AppLocalizations.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resoudreVersets());
    });
  }

  Future<void> _resoudreVersets() async {
    var v = widget.verses;
    if (v.isNotEmpty && v.first.surahNumber == 1 && v.first.ayahNumber == 1) {
      if (v.length > 1) {
        v = v.sublist(1);
      } else {
        final fatiha = await QuranApi.fetchVerses(1);
        final suivant = fatiha.where((x) => x.ayahNumber == 2);
        if (suivant.isNotEmpty) v = [suivant.first];
      }
    }
    if (!mounted) return;
    ref.read(coachProvider.notifier).setup(v);
    // Mémorise le verset travaillé pour la carte « Reprendre » du hub Coach
    // (REFONTE_IHM.md §11.2 zone A). Silencieux : un échec d'écriture ne doit
    // jamais empêcher la session de démarrer.
    final premier = v.first;
    unawaited(recordLastCoachVerse(
      surahNumber: premier.surahNumber,
      ayahNumber: premier.ayahNumber,
      surahName:
          AppLocalizations.of(context)!.coachSurahLabel(premier.surahNumber),
    ));
    setState(() => _verses = v);
  }

  @override
  Widget build(BuildContext context) {
    // Tant que la résolution (Bismillah comprise, cf. `_resoudreVersets`)
    // n'est pas faite, aucun contenu à afficher -- surtout pas
    // `widget.verses.first` en repli, qui redonnerait exactement le flash
    // qu'on cherche à éviter si ce premier verset est la Bismillah.
    // ── ABONNE AVANT LE RETOUR ANTICIPE, SINON LA SESSION EST PERDUE ──────
    //
    // `coachProvider` est `autoDispose`. Ce `watch` etait place APRES le
    // garde `verses == null` ci-dessous, donc jamais atteint au PREMIER
    // frame -- celui ou l'ecran affiche encore son indicateur de chargement.
    // Sequence mesuree (2026-08-19) :
    //   1. build #1 : `_verses == null` -> retour anticipe, le provider n'a
    //      AUCUN ecouteur ;
    //   2. post-frame : `_resoudreVersets()` fait `ref.read(...).setup(v)` --
    //      le provider est cree, l'etat pose, puis DETRUIT en fin de frame
    //      faute d'ecouteur (c'est la definition d'`autoDispose`) ;
    //   3. build #2 : `ref.watch` le RECREE avec l'etat par defaut, donc
    //      `verses: []`.
    //
    // Ce qu'on a vu a l'ecran, et qui vient de la : la ligne
    // `session.verses.isEmpty ? verses.first : session.currentVerse` retombe
    // sur le PREMIER verset du passage au lieu du verset courant -- « il
    // lance la lecture du Mushaf au lieu du verset sur l'ecran ». Et
    // `prolongerAvec` construisait l'historique du cumul a partir de cette
    // liste vide, donc sans son verset de depart -- « il se contente de
    // valider l'en-cours ».
    //
    // Un `watch` pose AVANT le garde donne un ecouteur des le premier frame :
    // `setup()` survit. Il ne coute rien de plus -- l'ecran l'appelait de
    // toute facon une ligne plus bas.
    final session = ref.watch(coachProvider);
    final verses = _verses;
    if (verses == null) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Ayah par ayah même sur une sourate entière (demande utilisateur
    // 2026-07-24) : les 3 modes ne travaillent QUE sur le verset courant
    // (session.currentVerse), jamais sur `verses` entier concaténé.
    final currentVerse = session.verses.isEmpty ? verses.first : session.currentVerse;
    final multiVerse = verses.length > 1;

    // ── LE CUMUL, CALCULE DEFENSIVEMENT (2026-08-18) ─────────────────────
    //
    // `session.verses` peut etre VIDE -- la ligne juste au-dessus le sait
    // depuis toujours et retombe sur `verses.first`. La premiere version du
    // cumul l'a ignore et faisait `sublist(0, index + 1)` sur cette liste
    // vide : ecran rouge `RangeError (end): Invalid value: Only valid value
    // is 0: 1` des l'ouverture du Controle. Un repli deja present dans le
    // fichier ne se contourne pas, il se reutilise.
    final cumulControle = ref.watch(coachControleCumulatifProvider);
    final versesControle = (!cumulControle || session.verses.isEmpty)
        ? [currentVerse]
        : session.verses.sublist(
            0, (session.currentVerseIndex + 1).clamp(1, session.verses.length));
    // Trace posee le 2026-08-19. MESURE qui l'impose : le controle de 07:00:21
    // portait sur `cible=5 mots`, soit 1:3 + 1:4 -- la session avait PERDU
    // 1:2, son propre point de depart. Constat utilisateur : « il se contente
    // de valider l'en-cours ». Ce qu'on ne sait pas encore, c'est QUAND la
    // liste se vide : on ecrit donc la liste elle-meme, a chaque changement.
    if (session.mode == CoachMode.controle && _dernierTraceControle != versesControle.length) {
      _dernierTraceControle = versesControle.length;
      DiagnosticLog.log('Coach',
          'controle : cumul=$cumulControle index=${session.currentVerseIndex} '
          'session=[${session.verses.map((v) => v.key).join(",")}] '
          '-> porte sur [${versesControle.map((v) => v.key).join(",")}]');
    }

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: currentVerse.key),
            if (multiVerse)
              _VerseNavBar(
                current: session.currentVerseIndex,
                total: verses.length,
                onPrevious: session.hasPreviousVerse
                    ? () => ref.read(coachProvider.notifier).previousVerse()
                    : null,
                onNext: session.hasNextVerse
                    ? () => ref.read(coachProvider.notifier).nextVerse()
                    : null,
              ),
            _StepBar(
              session: session,
              onSelect: (m) => ref.read(coachProvider.notifier).setMode(m),
            ),
            Expanded(
              child: GestureDetector(
                // Glisser pour passer au verset suivant/précédent SANS
                // quitter l'écran (demande utilisateur 2026-07-24, "un
                // scrolling par exemple pour passer à l'ayah suivante") --
                // seuil de vitesse pour ne pas confondre avec un simple
                // scroll vertical du contenu (SingleChildScrollView à
                // l'intérieur de chaque mode).
                onHorizontalDragEnd: !multiVerse
                    ? null
                    : (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v < -250) {
                          ref.read(coachProvider.notifier).nextVerse();
                        } else if (v > 250) {
                          ref.read(coachProvider.notifier).previousVerse();
                        }
                      },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  // Clé incluant l'index du verset : sans ça, rester dans le
                  // même mode (ex. Lecture) en glissant vers l'ayah suivante
                  // réutiliserait le même State et n'appellerait jamais
                  // initState -- l'écran resterait bloqué sur l'ancien
                  // verset "terminé" au lieu de redémarrer proprement.
                  child: switch (session.mode) {
                    CoachMode.lecture => _LectureMode(
                        key: ValueKey('lecture-${session.currentVerseIndex}'),
                        verses: [currentVerse],
                      ),
                    CoachMode.apprentissage => _ApprentissageMode(
                        key: ValueKey(
                            'apprentissage-${session.currentVerseIndex}'),
                        verses: [currentVerse],
                      ),
                    // ── LE CONTROLE PORTE SUR LE CUMUL (2026-08-18) ─────
                    //
                    // Demande utilisateur : « le controle se fait sur le cumul
                    // de la session depuis le debut ; pour passer au verset 3
                    // on reussit 1 et 2 ; si on a commence au verset 5, pour
                    // passer au 7 on doit reussir 5 et 6 ».
                    //
                    // `session.verses` commence AU verset de depart choisi --
                    // « depuis le debut de la session », pas depuis le debut
                    // de la sourate. Partir du verset 5 donne donc bien
                    // l'index 0 sur le verset 5.
                    //
                    // La CLE inclut la borne cumulee : sans elle, rester en
                    // mode controle en avancant d'un verset reutiliserait le
                    // meme State et garderait le texte precedent.
                    CoachMode.controle => _ControleMode(
                        key: ValueKey(cumulControle
                            ? 'controle-cumul-0..${session.currentVerseIndex}'
                            : 'controle-${session.currentVerseIndex}'),
                        verses: versesControle,
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseNavBar extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  const _VerseNavBar({
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      color: AppColors.green900,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: onPrevious != null ? AppColors.brassLight : Colors.white24,
            onPressed: onPrevious,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            t.memorizationGameVerseProgress(current + 1, total),
            style: GoogleFonts.manrope(
                fontSize: 12, color: AppColors.brassLight, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: onNext != null ? AppColors.brassLight : Colors.white24,
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.green900, AppColors.green800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.coachHeaderLabel,
                style: GoogleFonts.manrope(
                  color: AppColors.brassLight,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                title,
                style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          const Spacer(),
          // Réglages de vérification (tajwid/adulte/enfant, règles activées)
          // -- retour utilisateur 2026-07-19 : "alléger les paramètres
          // globaux", ce reglage vit ici (le Coach est l'ecran de
          // verification de recitation) plutot que dans Reglages global.
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.brassLight),
            tooltip: t.coachVerificationModeTooltip,
            // Feuille courte (modes seuls), cf. afficherFeuilleModes.
            onPressed: () => afficherFeuilleModes(context),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-Step Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final CoachSessionState session;
  final void Function(CoachMode) onSelect;
  const _StepBar({required this.session, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      color: AppColors.green900,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      // ── LECTURE RETIRÉE DE LA BARRE (2026-08-24) ────────────────────────
      //
      // Demande utilisateur : « je veux enlever dans mémorisation par palier
      // la première étape Lecture, on passe directement à Entraînement ».
      // `CoachMode.lecture` et `_LectureMode` restent dans le code (cf.
      // `CoachNotifier.setup`) -- seule cette barre ne propose plus d'y
      // aller. Deux puces au lieu de trois, une seule ligne de liaison.
      child: Row(
        children: [
          _StepChip(
            label: t.coachStepTrain,
            icon: Icons.headphones_outlined,
            active: session.mode == CoachMode.apprentissage,
            done: false,
            onTap: () => onSelect(CoachMode.apprentissage),
          ),
          _StepLine(done: session.mode3Done),
          _StepChip(
            label: t.coachStepControl,
            icon: Icons.visibility_off_outlined,
            active: session.mode == CoachMode.controle,
            done: session.mode3Done,
            onTap: () => onSelect(CoachMode.controle),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool done;
  final VoidCallback onTap;
  const _StepChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.brass
        : done
            ? AppColors.green100
            : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.brass.withAlpha(30)
                  : done
                      ? AppColors.green700.withAlpha(60)
                      : Colors.white10,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(
              done && !active ? Icons.check_rounded : icon,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({required this.done});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 22, left: 6, right: 6),
          decoration: BoxDecoration(
            color: done ? AppColors.green600 : Colors.white12,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 1 — Lecture Guidée
// ─────────────────────────────────────────────────────────────────────────────

class _LectureMode extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const _LectureMode({super.key, required this.verses});

  @override
  ConsumerState<_LectureMode> createState() => _LectureModeState();
}

// ── LECTURE REDEVIENT UNE ÉCOUTE (2026-08-09, demande utilisateur) ─────────
//
// « Lecture c'est l'audio qui récite tout le verset » -- avant ce correctif,
// Lecture demandait au contraire à l'utilisateur de réciter et calculait un
// score (baseline), servant à comparer avec le Contrôle final. L'utilisateur
// a choisi explicitement : Lecture = écoute seule (récitateur audio), sans
// mic. Reprend le corps de l'ancienne sous-étape "Écoute" du mode Entraîne
// (aujourd'hui retiré, cf. `_ApprentissageMode`).
//
// CONSÉQUENCE ASSUMÉE : `baselineAccuracy`/`difficultWords` (modèle
// `CoachSessionState`) ne sont plus jamais renseignés -- Lecture ne produit
// plus de score. `_GapCard` (comparaison Lecture/Contrôle) dans
// `_ControleMode` ne s'affichera donc plus jamais (son garde
// `session.baselineAccuracy != null` reste faux) : pas cassé, juste éteint.
// Champs et widget conservés intacts (convention projet).
class _LectureModeState extends ConsumerState<_LectureMode> {
  bool _audioStarted = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final player = ref.watch(playerProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          InfoBanner(
            icon: Icons.headphones_outlined,
            text: t.coachListenInstruction,
          ),
          const SizedBox(height: 16),
          VerseDisplay(words: const [], verses: widget.verses),
          const SizedBox(height: 28),
          _PlayButton(
            isPlaying: player.isPlaying,
            onTap: () {
              setState(() => _audioStarted = true);
              if (player.isPlaying) {
                ref.read(playerProvider.notifier).pause();
              } else if (player.isPaused) {
                ref.read(playerProvider.notifier).resume();
              } else {
                ref.read(playerProvider.notifier).play(
                      widget.verses.first,
                      widget.verses,
                    );
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            player.isPlaying ? t.coachListeningAudio : t.coachTapToListen,
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
          ),
          if (_audioStarted) ...[
            const SizedBox(height: 28),
            ActionButton(
              label: t.coachTrainButton,
              icon: Icons.arrow_forward_rounded,
              primary: true,
              onTap: () {
                ref.read(playerProvider.notifier).stop();
                ref.read(coachProvider.notifier).setMode(CoachMode.apprentissage);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 2 — Entraîne (corrigé le 2026-08-09, deux passes le même jour)
// ─────────────────────────────────────────────────────────────────────────────
//
// PREMIÈRE PASSE (erronée, gardée en trace) : j'avais compris qu'il fallait
// retirer le mécanisme par palier et vérifier le verset entier d'un coup.
// Correction de l'utilisateur : « le fonctionnement de l'entraînement c'est
// PAR PALIER, et ça commence toujours par l'audio qui dit le palier » -- le
// palier reste la mécanique voulue. Ce qui devait changer, relu avec ce
// correctif :
//   - « enlève ce deuxième palier » = les sous-étapes Écoute et Imite
//     (préambules avant la répétition), PAS le mécanisme de palier lui-même
//     -- `IncrementalRepeatStep` joue déjà l'audio du palier avant l'écoute
//     (`_startRound(playAudio: true)`), donc les fusionner avec lui les rend
//     redondantes ;
//   - « en répétant tout le temps depuis le début du verset » = la fenêtre
//     ne doit plus GLISSER (oublier les premières unités une fois
//     `repeatWindowSizeProvider` dépassé) -- elle doit rester CUMULATIVE
//     depuis l'unité 0 ;
//   - « n'affiche pas entendu, on fait juste colorié » = retirer
//     `RawTranscriptBox` de `IncrementalRepeatStep` ;
//   - le décalage texte/audio signalé : cf. le commentaire sur
//     `_currentWindow` dans `coach_incremental_repeat.dart`.
//
// `_ApprentissageMode` n'est donc plus qu'un habillage fin autour
// d'`IncrementalRepeatStep` -- plus de sous-barre d'étapes.
class _ApprentissageMode extends ConsumerWidget {
  final List<Verse> verses;
  const _ApprentissageMode({super.key, required this.verses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(coachProvider);
    return IncrementalRepeatStep(
      key: ValueKey('incremental-${verses.first.key}'),
      verse: verses.first,
      isLastVerse: session.isLastVerse,
      onAllVersesDone: () {
        // Arme le demarrage automatique du micro : on arrive au Controle par
        // la reussite des paliers, l'utilisateur est deja en train de reciter.
        ref.read(coachProvider.notifier).demarrerControleAuto = true;
        ref.read(coachProvider.notifier).setMode(CoachMode.controle);
      },
    );
  }
}

// ── SOUS-ÉTAPES ÉCOUTE/IMITE RETIRÉES (2026-08-09) ─────────────────────────
// La sous-étape "Répète" reste (`IncrementalRepeatStep`, monté directement
// par `_ApprentissageMode` ci-dessus) -- seules Écoute et Imite disparaissent
// du flux, désormais redondantes avec l'audio joué à chaque tour du palier.
// Classes conservées intactes (convention projet), plus référencées.
// ignore: unused_element
List<String> _appStepLabels(AppLocalizations t) =>
    [t.coachSubStepListen, t.coachSubStepImitate, t.coachSubStepRepeat];

// ignore: unused_element
class _AppSubStepBar extends StatelessWidget {
  final int currentStep;
  final void Function(int) onTap;
  const _AppSubStepBar({required this.currentStep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final labels = _appStepLabels(AppLocalizations.of(context)!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: AppColors.green50,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.only(bottom: 14),
                  color: i <= currentStep
                      ? AppColors.green600
                      : AppColors.green100,
                ),
              ),
            GestureDetector(
              onTap: () => onTap(i),
              child: _SubStepDot(
                index: i,
                label: labels[i],
                currentStep: currentStep,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubStepDot extends StatelessWidget {
  final int index;
  final String label;
  final int currentStep;
  const _SubStepDot(
      {required this.index,
      required this.label,
      required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final done = index < currentStep;
    final active = index == currentStep;
    final bg = active
        ? AppColors.green800
        : done
            ? AppColors.green600
            : AppColors.green100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : Text(
                    '${index + 1}',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: active || done ? Colors.white : AppColors.inkLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            color: active ? AppColors.green800 : AppColors.inkLight,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE 3 — Contrôle (récitation aveugle)
// ─────────────────────────────────────────────────────────────────────────────

class _ControleMode extends ConsumerStatefulWidget {
  final List<Verse> verses;
  const _ControleMode({super.key, required this.verses});

  @override
  ConsumerState<_ControleMode> createState() => _ControleModeState();
}

class _ControleModeState extends ConsumerState<_ControleMode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  final _fingerprint = VoiceFingerprintService();
  double? _fingerprintScore;
  bool _fingerprintChecked = false;
  bool _avanceAutoDeclenchee = false;

  /// Un contrôle a-t-il été LANCÉ depuis cet écran ?
  ///
  /// ── SANS LUI, L'ÉCRAN DÉCIDE SUR L'ÉTAT D'UN AUTRE (2026-08-18) ──────────
  /// `recitationProvider` est PARTAGÉ avec les paliers. Quand le contrôle se
  /// monte juste après un palier réussi, il y trouve encore la session du
  /// palier : `finished` vrai, tous les mots verts. `controleParfait` était
  /// donc vrai AVANT que le contrôle ait commencé, et le passage automatique
  /// partait aussitôt.
  ///
  /// Mesure qui l'établit (journal v165, cumul activé) :
  ///     22:13:39.46  palier 1:4 -> 3 mots definitif:vert
  ///     22:13:42.13  audio du palier de 1:5      <- verset suivant
  /// 2,67 s d'écart, soit exactement le `Future.delayed(2600)` du passage
  /// automatique. Constat utilisateur : « j'arrive à passer au verset suivant
  /// sans réciter depuis le début ». Aucun contrôle n'avait eu lieu.
  ///
  /// `setup()` ne suffisait pas à s'en prémunir : il repasse les mots à
  /// `pending` mais il est appelé dans un post-frame, donc APRÈS ce premier
  /// build -- et c'est ce build-là qui décidait.
  ///
  /// Un écran ne décide que sur SA session.
  bool _controleLance = false;

  StreamSubscription<int>? _wordLockedSub;

  /// ── ARRÊT AUTOMATIQUE DE L'ENREGISTREMENT (2026-08-27) ───────────────────
  ///
  /// Demande utilisateur : « au lieu que le user clique sur l'arrêt de
  /// l'enregistrement, je propose de chercher toujours à passer au suivant
  /// [...] si le modèle valide le dernier mot il faut arrêter l'enregistrement
  /// auto, également dans le contrôle ». Le palier l'avait déjà
  /// (`coach_incremental_repeat.dart`), le contrôle non : il fallait taper sur
  /// le micro pour clore, alors que la récitation était finie.
  ///
  /// ⚠️ LE CRITÈRE N'EST PAS « LE DERNIER MOT EST VALIDÉ », et c'est
  /// structurel : le dernier mot n'obtient son verdict qu'À LA FERMETURE de
  /// session (il lui faut `k=2` observations de fenêtres distinctes, or aucune
  /// fenêtre ne vient après lui). Attendre sa validation, c'est attendre
  /// l'instant qu'on cherche justement à provoquer. Le piège est déjà mesuré :
  /// « TOUS JUGÉS » avait été essayé le 2026-08-18 côté palier -- 0
  /// déclenchement sur 4 tours.
  ///
  /// Le signal retenu est donc le même que celui qui marche là-bas : le
  /// dernier mot a été ATTEINT (il quitte `pending` dès que l'ancre arrive
  /// dessus, sans attendre de verdict) ET la voix est retombée depuis
  /// [_delaiSilence].
  Timer? _finAuto;
  static const double _seuilSilence = 0.10;
  static const Duration _delaiSilence = Duration(milliseconds: 800);

  /// Survit au démontage de l'écran, contrairement à `ref` -- capturé au
  /// premier build (cf. son usage) pour que `_archiverMotDansPortion` puisse
  /// encore lire les providers si un mot se verrouille juste après la
  /// navigation. Même pattern que `_container` dans
  /// `karaoke_recitation_screen.dart` (introduit le 2026-08-14 pour la même
  /// raison, généralisé ici le 2026-08-24).
  ProviderContainer? _container;

  T _lireProvider<T>(ProviderListenable<T> p) {
    final c = _container;
    return c != null ? c.read(p) : ref.read(p);
  }

  String get _text => widget.verses.map((v) => v.textUthmani).join(' ');
  String get _passageKey => widget.verses.map((v) => v.key).join('-');

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = ref.read(recitationProvider.notifier);
      n.setup(_text);
      // ── MICRO OUVERT D'OFFICE APRES LES PALIERS (2026-09-02) ───────────
      // `consommerDemarrageAuto` ne rend true que si l'on vient de valider le
      // dernier palier, et une seule fois -- cf. sa doc. Meme sequence que le
      // tap sur le micro (`resetControl` + `_controleLance` + `startControle`)
      // pour qu'il n'y ait pas deux chemins de demarrage a maintenir.
      if (ref.read(coachProvider.notifier).consommerDemarrageAuto()) {
        ref.read(coachProvider.notifier).resetControl();
        setState(() {
          _fingerprintChecked = false;
          _fingerprintScore = null;
          _controleLance = true;
        });
        n.startControle();
      }
    });
    _fingerprint.ensureLoaded();
    // ── SUIVI PERMANENT PAR PORTION, COMME EN RÉCITATION LIVE (2026-08-24) ──
    //
    // Demande utilisateur : reprendre « celui qui existe dans la vraie
    // récitation » (`karaoke_recitation_screen.dart::_archiverMotDansPortion`)
    // -- ce mode Contrôle n'écrivait JAMAIS dans `portion_words`. Conséquence
    // mesurée : le pouce vers le bas de la fiche tajwid (`onWordContested`)
    // faisait un `UPDATE ... WHERE ...` sur une ligne qui n'avait jamais été
    // créée -- l'écran affichait « merci » sans que rien ait changé nulle
    // part, un faux succès silencieux. Sans cet abonnement, le bouton reste
    // câblé mais inopérant : il lui faut une ligne à mettre à jour.
    _wordLockedSub = ref
        .read(recitationProvider.notifier)
        .wordLocked
        .listen(_archiverMotDansPortion);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fingerprint.dispose();
    _wordLockedSub?.cancel();
    _finAuto?.cancel();
    super.dispose();
  }

  /// Avance au verset suivant de la session, ou PROLONGE la session si elle
  /// n'en contient pas d'autre -- extrait tel quel de l'enchaînement
  /// automatique (2026-08-24) pour que le balayage manuel (ci-dessous) fasse
  /// EXACTEMENT la même chose, pas une variante.
  ///
  /// DEFAUT MESURE (journal v164, 22:02 et 22:04) : controle sur `cible=4
  /// mots` -- le seul verset 1:2 -- quatre mots `definitif:vert`, donc
  /// controle PARFAIT, et pourtant aucun passage. Cause : la session ne
  /// contenait QU'UN verset, donc `hasNextVerse` etait faux et l'ancienne
  /// condition sortait sans rien faire ni rien dire. Constat utilisateur :
  /// « j'ai reussi, pas de passage au prochain verset ».
  ///
  /// Entrer dans le Coach sur UN verset est pourtant le cas courant (carte
  /// « Reprendre », revision d'une erreur ponctuelle) : sans ceci, la
  /// bascule n'aurait jamais rien fait dans ce cas.
  ///
  /// On charge le verset qui SUIT celui en cours -- jamais le debut de la
  /// sourate : la session commence ou l'utilisateur l'a demarree, et
  /// s'etend vers l'aval.
  Future<void> _avancerAuVersetSuivant(CoachSessionState session) async {
    final notifier = ref.read(coachProvider.notifier);
    if (session.hasNextVerse) {
      notifier.advanceAfterPerfectControl();
      return;
    }
    final courant =
        session.verses.isEmpty ? widget.verses.last : session.currentVerse;
    try {
      final tous = await QuranApi.fetchVerses(courant.surahNumber);
      if (!mounted) return;
      final suivants =
          tous.where((x) => x.ayahNumber == courant.ayahNumber + 1);
      if (suivants.isEmpty) return; // fin de sourate : rien apres
      notifier.prolongerAvec(courant, suivants.first);
    } catch (e) {
      DiagnosticLog.log(
          'Coach', 'prolongation impossible apres ${courant.key} : $e');
    }
  }

  /// Balayage horizontal (n'importe quel sens) pour FORCER le passage au
  /// verset suivant -- demande utilisateur explicite (2026-08-24) : « c'est
  /// pour forcer le passage », en réponse au constat que l'exigence des 100 %
  /// (`controleParfait`, tous les mots verts) bloque parfois l'avancée à
  /// tort quand le modèle juge trop sévèrement un mot en réalité correct.
  ///
  /// N'attend PAS `controleParfait` : c'est tout son intérêt, un contournement
  /// manuel assumé de cette exigence, pas une bascule de plus dessus. Actif
  /// seulement une fois le contrôle terminé (`finished`) -- balayer avant
  /// n'a pas de sens, il n'y a encore rien à valider ni à contourner.
  void _forcerPassageManuel() {
    final session = ref.read(coachProvider);
    unawaited(_avancerAuVersetSuivant(session));
  }

  /// Verset contenant [wordIndex] (indice global, concaténation de
  /// `widget.verses`) et son indice LOCAL dans ce verset -- même calcul que
  /// `_openWordHelp`.
  (Verse, int)? _verseEtLocal(int wordIndex) {
    var offset = 0;
    for (final v in widget.verses) {
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) return (v, wordIndex - offset);
      offset += count;
    }
    return null;
  }

  /// Délègue à `services/portion_word_archiver.dart` -- MÊME fonction que
  /// l'écran karaoké (factorisé le 2026-08-24, cf. sa doc en tête de fichier :
  /// « ça sera mieux de réutiliser » plutôt que deux copies qui dérivent).
  /// `_lireProvider` (dispose-safe) plutôt que `ref.read` : ce mode tourne
  /// via un abonnement (`_wordLockedSub`) qui peut encore livrer un mot après
  /// le démontage de l'écran -- même raison que documentée sur
  /// `_lireProvider` dans `karaoke_recitation_screen.dart`.
  Future<void> _archiverMotDansPortion(int wordIndex) async {
    final words = _lireProvider(recitationProvider).words;
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final ve = _verseEtLocal(wordIndex);
    if (ve == null) return;
    final (verse, local) = ve;
    await archiverMotDansPortion(
      lire: _lireProvider,
      verse: verse,
      wordIndexLocal: local,
      wordIndexGlobal: wordIndex,
      mot: words[wordIndex],
    );
  }

  /// Tap sur un mot orange/rouge du résultat : retrouve le verset contenant ce
  /// mot (les mots affichés sont la concaténation des versets, découpés avec
  /// la même règle `\s+` que setup()) et ouvre la fiche tajwid + réciteur.
  void _openWordHelp(List<RecitedWord> words, int wordIndex) {
    var offset = 0;
    for (final v in widget.verses) {
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) {
        final local = wordIndex - offset;
        // ── N'AFFICHER QUE LE MOT EN CAUSE, PAS TOUTE L'AYA (2026-08-24) ────
        //
        // Manquait ici alors que déjà corrigé dans l'écran karaoké le
        // 2026-08-05 (constat utilisateur sur CET écran-ci : « il affiche
        // tout le verset, j'avais corrigé ça »). Même fonction PARTAGÉE que
        // l'écran karaoké désormais (`services/portion_word_archiver.dart`),
        // pas une copie -- cf. la doc en tête de ce fichier.
        final (debut, finExclusif) = etendreAuxMotsContigusEnErreur(
          words: words,
          wordIndexGlobal: wordIndex,
          wordIndexLocal: local,
          motsDuVerset: count,
        );
        showTajwidHelpSheet(
          context,
          ref,
          verse: v,
          playlist: widget.verses,
          focusWord: words[wordIndex].display,
          entendu: words[wordIndex].heard,
          wordIndex: wordIndex,
          localWordIndex: local,
          extraitDebut: debut,
          extraitFin: finExclusif,
          onWordContested: () => ref.invalidate(portionsProvider),
          // riwaya de LA SESSION (déjà figée par setup()) -- cf.
          // RecitationSessionState.riwaya.
          riwaya: ref.read(recitationProvider).riwaya,
        );
        return;
      }
      offset += count;
    }
  }

  @override
  Widget build(BuildContext context) {
    _container ??= ProviderScope.containerOf(context, listen: false);
    final t = AppLocalizations.of(context)!;
    final rst = ref.watch(recitationProvider);
    final session = ref.watch(coachProvider);
    final listening = rst.status == RecitationStatus.listening;
    final finished = rst.status == RecitationStatus.finished && rst.total > 0;

    // Arrêt automatique de l'enregistrement (cf. la doc de `_finAuto`) --
    // même mécanisme éprouvé que le palier, jamais « tous jugés » (piège
    // mesuré, cf. cette même doc).
    ref.listen<RecitationSessionState>(recitationProvider, (prev, next) {
      if (!_controleLance || next.status != RecitationStatus.listening) {
        _finAuto?.cancel();
        _finAuto = null;
        return;
      }
      final dernier = next.words.isEmpty ? null : next.words.last;
      final finAtteinte = dernier != null && dernier.status != WordStatus.pending;
      if (finAtteinte && next.soundLevel < _seuilSilence) {
        // `??=` : ne pas ré-armer à chaque bloc PCM, sinon le minuteur repart
        // de zéro en permanence et n'échoit jamais.
        _finAuto ??= Timer(_delaiSilence, () {
          _finAuto = null;
          if (!mounted) return;
          if (ref.read(recitationProvider).status != RecitationStatus.listening) {
            return;
          }
          DiagnosticLog.log('Controle',
              'arret auto : dernier mot atteint + silence '
              '${_delaiSilence.inMilliseconds} ms');
          ref.read(recitationProvider.notifier).stopContinuous();
        });
      } else {
        // Il reparle, ou un mot vient de repasser en cours de jugement : on
        // désarme, la fin n'est plus acquise.
        _finAuto?.cancel();
        _finAuto = null;
      }
    });

    if (finished && session.controlAccuracy == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(coachProvider.notifier).saveControlScore(rst.accuracy);
      });
    }

    // ── ENCHAÎNEMENT AUTOMATIQUE SUR CONTRÔLE PARFAIT (2026-08-09) ─────────
    //
    // Demande utilisateur : « une fois le contrôle d'un verset validé, on
    // passe au verset suivant [...] je veux limiter les clics ». Précisé au
    // clarifiement : « validé » = AUCUNE erreur signalée, tous les mots
    // verts -- une seule orange ou rouge garde l'utilisateur sur ce verset,
    // avec les boutons Réessayer / Retour entraînement déjà en place plus
    // bas. Pas de déclenchement sur un score simplement "bon" : ce serait
    // déplacer le critère de ce qu'est une mémorisation réussie, ce que le
    // projet interdit (cf. skill `solution-de-fond`).
    final controleParfait = _controleLance &&
        finished &&
        rst.words.isNotEmpty &&
        rst.words.every((w) => w.status == WordStatus.correct);
    // Le passage au verset suivant etait IMPOSE ; il devient un choix
    // (2026-08-18, bascule en bas de cet ecran). Le critere de reussite, lui,
    // ne bouge pas : tous les mots verts. Deplacer ce critere pour "fluidifier"
    // reviendrait a deplacer la definition d'une memorisation reussie, ce que
    // le projet interdit.
    final passageAuto = ref.watch(coachPassageAutoProvider);
    if (controleParfait && passageAuto && !_avanceAutoDeclenchee) {
      _avanceAutoDeclenchee = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.coachIncrementalVerseAdvance),
            duration: const Duration(seconds: 3),
          ),
        );
        // ── LAISSER LE TEMPS DE COMPRENDRE (2026-08-18) ─────────────────
        //
        // 900 ms auparavant. Demande utilisateur : « ça doit pas être
        // rapide, donne le temps qu'il comprenne qu'il a réussi le verset
        // pour passer au suivant ». Le score parfait et les mots tout verts
        // sont la récompense de l'exercice ; les balayer en moins d'une
        // seconde revient à ne pas la donner.
        await Future.delayed(const Duration(milliseconds: 2600));
        if (!mounted) return;

        await _avancerAuVersetSuivant(session);
      });
    }

    if (finished && !_fingerprintChecked) {
      _fingerprintChecked = true;
      final audioPath = ref.read(recitationVerifierProvider).lastAudioPath;
      if (audioPath != null) {
        _fingerprint.compareToReference(audioPath, _passageKey).then((score) {
          if (!mounted) return;
          setState(() => _fingerprintScore = score);
          debugPrint('[VoiceFingerprint] Comparaison "$_passageKey" : $score');
        });
      }
    }

    // Balayage horizontal pour FORCER le passage au verset suivant (cf. la
    // doc de `_forcerPassageManuel`) -- seulement actif une fois le contrôle
    // terminé, `null` sinon désactive proprement le geste plutôt que de le
    // laisser capter des drags sans effet.
    return GestureDetector(
      onHorizontalDragEnd:
          finished ? (_) => _forcerPassageManuel() : null,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          InfoBanner(
            icon: Icons.visibility_off_outlined,
            text: t.coachRecallInstruction,
            dark: true,
          ),
          const SizedBox(height: 20),
          // Before finish: blurred card. After: colored words revealed.
          finished
              ? VerseDisplay(
                  // Les mots dont la cause est le tajwid : `classifyError`,
                  // meme source que la recitation et la fiche du mot.
                  motsTajwidRates: {
                    for (var i = 0; i < rst.words.length; i++)
                      if (ref
                              .read(recitationProvider.notifier)
                              .classifyError(i) ==
                          RecitationErrorKind.tajwid)
                        i
                  },
                  words: rst.words,
                  verses: widget.verses,
                  onProblemWordTap: (i) => _openWordHelp(rst.words, i),
                )
              : _BlurredVerse(verses: widget.verses),
          const SizedBox(height: 28),
          MicSection(
            listening: listening,
            processing: rst.status == RecitationStatus.processing,
            finished: finished,
            pulse: _pulse,
            statusText: listening
                ? t.coachListeningControl
                : finished
                    ? t.coachControlDone
                    : t.coachTapToRecall,
            onTap: () {
              // ── LE CONTROLE FINAL DOIT PASSER PAR LA v2 (2026-08-18) ─────
              //
              // DEFAUT MESURE sur la session du 2026-08-18 21:10 (verset 4:1,
              // apres les cinq paliers) :
              //     [v2] chaine parallele ACTIVE   : 1
              //     [v2] f=  (fenetres traitees)   : 0
              //     [V2] mot= (verdicts)           : 0
              //     micro continu=false            : 1
              //     [TEXTDIFF] mot= (verdicts v1)  : 17
              //     [ForcedAligner] ZERO FRAME     : 2
              // La v2 etait ACTIVEE mais n'a jamais recu un octet de PCM :
              // l'alimentation passe uniquement par `_processContinuousChunk`
              // (cf. `RecitationVerifier`), donc par le mode CONTINU. Le
              // controle final etait donc juge par la v1 -- celle-la meme qui
              // ne peint plus l'ecran depuis le 2026-08-04 -- avec ses
              // impasses connues (`ZERO FRAME`, `AVANCE SANS JUGER` sur le
              // mot 17, jamais juge).
              //
              // Exactement le meme defaut que le palier de memorisation, et le
              // meme remede, valide par l'utilisateur le 2026-08-17 : un
              // chemin ecrit pour la v1, reste en place, qui a cesse d'agir le
              // jour ou la v2 a pris l'affichage sans que personne le decide.
              //
              // `stopContinuous()` et non `stop()` : `stop()` sort sans rien
              // faire sur une session continue, et c'est lui qui appelle
              // `v2Terminer()` -- sans quoi les derniers mots resteraient
              // PROVISOIRES a jamais.
              final n = ref.read(recitationProvider.notifier);
              if (listening) {
                n.stopContinuous();
              } else {
                n.setup(_text);
                ref.read(coachProvider.notifier).resetControl();
                setState(() {
                  _fingerprintChecked = false;
                  _fingerprintScore = null;
                  _controleLance = true;
                });
                n.startControle();
              }
            },
            onReset: () {
              ref.read(recitationProvider.notifier).setup(_text);
              ref.read(coachProvider.notifier).resetControl();
              setState(() {
                _fingerprintChecked = false;
                _fingerprintScore = null;
              });
            },
          ),
          RawTranscriptBox(text: rst.rawTranscript),
          if (finished) ...[
            const SizedBox(height: 20),
            _ScoreRow(accuracy: rst.accuracy),
            if (_fingerprintScore != null) ...[
              const SizedBox(height: 8),
              _FingerprintBadge(score: _fingerprintScore!),
            ],
            if (session.baselineAccuracy != null) ...[
              const SizedBox(height: 8),
              _GapCard(
                baseline: session.baselineAccuracy!,
                control: rst.accuracy,
              ),
            ],
            const SizedBox(height: 12),
            _CoachBubble(
              accuracy: rst.accuracy,
              difficultWords: rst.words
                  .where((w) =>
                      w.status == WordStatus.error ||
                      w.status == WordStatus.unclear ||
                      w.status == WordStatus.skipped)
                  .map((w) => w.display)
                  .toList(),
              mode: CoachMode.controle,
              baseline: session.baselineAccuracy,
            ),
            const SizedBox(height: 16),
            // ── LES DEUX BOUTONS DU BAS SONT REMPLACES (2026-08-18) ────────
            //
            // « Les deux boutons en bas ne servent a rien, on peut les
            // remplacer par [un] toggle passage automatique [...] et un autre
            // pour dire [que] le controle se fait sur le cumul de la
            // session ». Regle de projet : un element d'IHM juge inutile se
            // SUPPRIME -- on ne le recase pas ailleurs.
            //
            // « Reessayer » ne manque pas : le micro de cet ecran relance
            // deja un controle propre (il appelle `setup` + `resetControl`
            // avant `startControle`). « Retour entrainement » non plus : le
            // bandeau d'etapes en haut y ramene en un tap.
            _BasculeCoach(
              titre: t.coachTogglePassageAutoTitre,
              detail: t.coachTogglePassageAutoDetail,
              valeur: ref.watch(coachPassageAutoProvider),
              onChange: (v) =>
                  ref.read(coachPassageAutoProvider.notifier).set(v),
            ),
            const SizedBox(height: 8),
            _BasculeCoach(
              titre: t.coachToggleCumulTitre,
              detail: t.coachToggleCumulDetail,
              valeur: ref.watch(coachControleCumulatifProvider),
              onChange: (v) =>
                  ref.read(coachControleCumulatifProvider.notifier).set(v),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Bascule de réglage du Coach, posée en bas de l'écran Contrôle.
///
/// Elle prend la place des deux boutons d'action retirés le 2026-08-18 : un
/// réglage se lit et se change là où son effet se constate, pas dans un écran
/// de préférences qu'il faudrait aller chercher au milieu d'une session.
class _BasculeCoach extends StatelessWidget {
  final String titre;
  final String detail;
  final bool valeur;
  final ValueChanged<bool> onChange;

  const _BasculeCoach({
    required this.titre,
    required this.detail,
    required this.valeur,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.cream200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inkLight.withAlpha(35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(detail,
                    style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.inkLight)),
              ],
            ),
          ),
          Switch(
            value: valeur,
            onChanged: onChange,
            activeThumbColor: AppColors.cream,
            activeTrackColor: AppColors.green600,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class RawTranscriptBox extends StatelessWidget {
  final String text;
  const RawTranscriptBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cream300.withAlpha(150),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inkLight.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.coachTranscriptLabel,
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkLight),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.scheherazadeNew(
                  fontSize: 20, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool dark;
  const InfoBanner({super.key, required this.icon, required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? AppColors.green900 : AppColors.green50;
    final fg = dark ? AppColors.brassLight : AppColors.green700;
    final tx = dark ? AppColors.cream : AppColors.inkLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: dark ? Colors.transparent : AppColors.green100),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: tx, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class VerseDisplay extends StatelessWidget {
  final List<RecitedWord> words;
  final List<Verse> verses;

  /// Tap sur un mot jugé orange (unclear) ou rouge (error) — ouvre l'aide
  /// tajwid + lecture réciteur en mode Contrôle. Null ailleurs (pas de tap).
  final void Function(int wordIndex)? onProblemWordTap;

  /// Index des mots dont l'erreur est une REGLE DE TAJWID non realisee
  /// (2026-09-02) -- peints en violet au lieu de l'orange des imprecisions.
  ///
  /// Fourni par l'appelant, qui a `ref` : ce widget est sans etat et ne peut
  /// pas interroger `classifyError` lui-meme. Vide = aucun violet, donc le
  /// rendu d'avant au pixel pres.
  final Set<int> motsTajwidRates;

  const VerseDisplay({
    super.key,
    required this.words,
    required this.verses,
    this.onProblemWordTap,
    this.motsTajwidRates = const {},
  });

  @override
  Widget build(BuildContext context) {
    // `QuranApi.riwaya` : ce widget reçoit des `Verse` déjà chargés au bon
    // riwaya par l'appelant (cf. QuranApi._versesAsset) -- cloisonnement
    // Hafs/Warsh, cf. ArabicNormalizer.normalizeWarsh.
    final warsh = QuranApi.riwaya == Riwaya.warsh;
    final display = words.isNotEmpty
        ? words
        : verses
            .expand((v) => ArabicNormalizer.splitExpectedWords(v.textUthmani)
                .map((w) => RecitedWord(
                      display: w,
                      normalized: warsh
                          ? ArabicNormalizer.normalizeWarsh(w)
                          : ArabicNormalizer.normalize(w),
                      strict: warsh
                          ? ArabicNormalizer.normalizeStrictWarsh(w)
                          : ArabicNormalizer.normalizeStrict(w),
                      training: warsh
                          ? ArabicNormalizer.normalizeTrainingWarsh(w)
                          : ArabicNormalizer.normalizeTraining(w),
                    )))
            .toList();

    // Coloration tajwid lettre-par-lettre "partout où le texte apparaît"
    // (demande utilisateur 2026-07-05) — même approche que karaoke_recitation_screen :
    // le texte porte la couleur tajwid, le jugement vert/orange/rouge passe par
    // le fond du chip pour ne jamais se disputer la même couleur.
    final tajwidSpans = [
      for (final v in verses)
        ...tajweedSpansPerWord(
          v.textUthmani,
          v.textUthmaniTajweed,
          GoogleFonts.scheherazadeNew(fontSize: 28, height: 1.9, color: AppColors.ink),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 10,
          children: [
            for (var i = 0; i < display.length; i++)
              _wordChip(display[i], i, tajwidSpans),
          ],
        ),
      ),
    );
  }

  Widget _wordChip(
      RecitedWord w, int index, List<List<TextSpan>> tajwidSpans) {
    final tappable = onProblemWordTap != null &&
        (w.status == WordStatus.unclear ||
            w.status == WordStatus.error ||
            w.status == WordStatus.skipped);

    Color? bgTint;
    Color? borderTint;
    var opacity = 1.0;
    // Fonds plus vifs (retour utilisateur 2026-07-06 : "il y a plus le
    // rouge, le vrai rouge et l'orange" — trop discrets depuis l'intégration
    // du tajwid). Le texte reste coloré tajwid ; le jugement se voit
    // maintenant au fond ET au contour, plus franchement.
    switch (w.status) {
      case WordStatus.correct:
        bgTint = AppColors.green600.withOpacity(0.32);
        borderTint = AppColors.green600;
        break;
      case WordStatus.unclear:
        // ── VIOLET SI C'EST LE TAJWID (2026-09-02) ─────────────────────
        // Un mot degrade par une REGLE non realisee et un mot simplement
        // imprecis arrivaient tous deux en `unclear`, donc tous deux en
        // orange. Ils n'appellent pourtant pas le meme geste : l'orange dit
        // « redis-le mieux », le violet dit « les lettres etaient justes,
        // c'est la regle qui manque ». La couleur existait depuis le
        // 2026-08-01 mais n'etait posee que dans l'ecran de recitation.
        //
        // `classifyError` : meme source que la recitation et que la fiche du
        // mot -- une seule definition de « erreur de tajwid » dans l'app.
        final tajwid = motsTajwidRates.contains(index);
        bgTint = tajwid
            ? AppColors.recitationTajwidError.withOpacity(0.34)
            : AppColors.tajwidMadd.withOpacity(0.36);
        borderTint =
            tajwid ? AppColors.recitationTajwidError : AppColors.tajwidMadd;
        break;
      case WordStatus.error:
        // Rouge SEULEMENT si verrouillé (demande utilisateur 2026-07-09,
        // même souci que karaoke_recitation_screen.dart : un aperçu pas
        // encore figé peut sembler faux un instant avant de se stabiliser).
        if (w.locked) {
          bgTint = const Color(0xFFb00020).withOpacity(0.30);
          borderTint = const Color(0xFFb00020);
        }
        break;
      case WordStatus.skipped:
      case WordStatus.current:
        break;
      case WordStatus.pending:
        opacity = 0.45;
        break;
    }

    final base = GoogleFonts.scheherazadeNew(
        fontSize: 28, height: 1.9, color: AppColors.ink);
    final tajwidWord = index < tajwidSpans.length ? tajwidSpans[index] : null;
    // Mot sauté : gris + souligné pointillé, préservé lettre par lettre pour
    // ne pas perdre la coloration tajwid pendant qu'on signale le saut.
    final decoStyle = TextStyle(
      decoration:
          w.status == WordStatus.skipped ? TextDecoration.underline : null,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: AppColors.inkLight,
    );
    final textWidget = (tajwidWord != null && tajwidWord.isNotEmpty)
        ? RichText(
            text: TextSpan(
              children: [
                for (final s in tajwidWord)
                  TextSpan(
                    text: s.text,
                    children: s.children,
                    recognizer: s.recognizer,
                    style: (s.style ?? base).merge(decoStyle),
                  ),
              ],
            ),
          )
        : Text(w.display, style: base.merge(decoStyle));

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: w.status == WordStatus.current
            ? AppColors.brass.withAlpha(25)
            : bgTint,
        borderRadius: BorderRadius.circular(6),
        border: w.status == WordStatus.current
            ? Border.all(color: AppColors.brass.withAlpha(60))
            : (borderTint != null ? Border.all(color: borderTint, width: 1.5) : null),
      ),
      child: Opacity(opacity: opacity, child: textWidget),
    );
    if (!tappable) return chip;
    return GestureDetector(
      onTap: () => onProblemWordTap!(index),
      child: chip,
    );
  }
}

class _BlurredVerse extends StatelessWidget {
  final List<Verse> verses;
  const _BlurredVerse({required this.verses});

  @override
  Widget build(BuildContext context) {
    final text = verses.map((v) => v.textUthmani).join(' ');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 28, height: 1.9, color: AppColors.ink),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.green900.withAlpha(200),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.visibility_off_rounded,
                        color: AppColors.brassLight, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.green900.withAlpha(180),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.coachRecallBadge,
                      style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MicSection extends StatelessWidget {
  final bool listening;
  final bool processing; // ASR en cours dans compute() — UI doit rester réactive
  final bool finished;
  final AnimationController pulse;
  final String statusText;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const MicSection({
    super.key,
    required this.listening,
    required this.processing,
    required this.finished,
    required this.pulse,
    required this.statusText,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // ── État "processing" : spinner doré pendant l'inférence Whisper ──────────
    if (processing) {
      return Column(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.brass,
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green900.withAlpha(200),
                    border: Border.all(color: AppColors.brass.withAlpha(80)),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.brass, size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.coachAnalyzingAudio,
            style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.brass,
                fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    // ── État normal : mic button ──────────────────────────────────────────────
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AnimatedMicButton(
                listening: listening, pulse: pulse, onTap: onTap),
            // ── BOUTON « REFAIRE » RETIRE (2026-09-02) ────────────────────
            // Constat utilisateur : « le micro et le signe pour refaire,
            // c'est la meme chose -- enleve la fleche a cote du micro ».
            //
            // Il avait raison : une fois la recitation terminee, appuyer sur
            // le micro RELANCE deja un tour (cf. le `onTap` du micro, qui
            // appelle `setup` + `resetControl` + `startControle` quand on
            // n'ecoute pas). Les deux boutons faisaient donc la meme chose,
            // cote a cote, avec deux icones differentes -- de quoi croire
            // qu'ils different.
            //
            // `onReset` reste EN PLACE et cable (il sert au « retour
            // entrainement » et pourra resservir) : seul ce bouton en double
            // disparait de l'ecran.
          ],
        ),
        const SizedBox(height: 8),
        Text(
          statusText,
          style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.inkLight,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _AnimatedMicButton extends StatelessWidget {
  final bool listening;
  final AnimationController pulse;
  final VoidCallback onTap;
  const _AnimatedMicButton(
      {required this.listening,
      required this.pulse,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Transform.scale(
          scale: listening ? (1.0 + pulse.value * 0.14) : 1.0,
          child: child,
        ),
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (listening)
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFb00020).withAlpha(25),
                  ),
                ),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: listening
                        ? const [Color(0xFFd32f2f), Color(0xFFb00020)]
                        : [AppColors.green700, AppColors.green900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (listening
                              ? const Color(0xFFb00020)
                              : AppColors.green800)
                          .withAlpha(80),
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green800,
            boxShadow: [
              BoxShadow(
                  color: AppColors.green900.withAlpha(80),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      );
}

class _ScoreRow extends StatelessWidget {
  final double accuracy;
  const _ScoreRow({required this.accuracy});

  @override
  Widget build(BuildContext context) {
    final pct = accuracy.round();
    final color = pct >= 90
        ? AppColors.green600
        : pct >= 70
            ? AppColors.brass
            : const Color(0xFFb00020);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Row(
            children: [
              Icon(
                pct >= 70
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.coachAccuracyPercent(pct),
                style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Score de l'empreinte vocale (niveau 1 "personnalisation voix", comparaison
/// audio-à-audio DTW contre la lecture de référence vérifiée) — voir SKILL.md.
/// Affiché séparément du score ASR classique (_ScoreRow) : source différente,
/// pas encore assez de recul pour les fusionner en un seul chiffre.
class _FingerprintBadge extends StatelessWidget {
  final double score; // [0,1]
  const _FingerprintBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score >= 0.9
        ? AppColors.green600
        : score >= 0.85
            ? AppColors.brass
            : const Color(0xFFb00020);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.coachFingerprintScore(pct),
                style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GapCard extends StatelessWidget {
  final double baseline;
  final double control;
  const _GapCard({required this.baseline, required this.control});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final gap = control - baseline;
    final memorized = gap >= 5;
    final color = memorized ? AppColors.green700 : AppColors.brass;
    final sign = gap >= 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(
            memorized
                ? Icons.trending_up_rounded
                : Icons.trending_flat_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memorized
                      ? t.coachMemorizedConfirmed
                      : t.coachKeepTraining,
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
                Text(
                  t.coachGapSummary(
                      baseline.round(), control.round(), '$sign${gap.round()}'),
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.inkLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachBubble extends StatelessWidget {
  final double accuracy;
  final List<String> difficultWords;
  final CoachMode mode;
  final double? baseline;
  const _CoachBubble({
    required this.accuracy,
    required this.difficultWords,
    required this.mode,
    required this.baseline,
  });

  String _message(AppLocalizations t) {
    final pct = accuracy.round();
    switch (mode) {
      case CoachMode.lecture:
        if (pct >= 90) {
          return t.coachMsgLectureExcellent;
        }
        if (difficultWords.isNotEmpty) {
          final preview = difficultWords.take(3).join('  ');
          return t.coachMsgLectureDifficultWords(preview);
        }
        return t.coachMsgLectureHesitant;

      case CoachMode.apprentissage:
        if (pct >= 85) {
          return t.coachMsgTrainGreat;
        }
        if (pct >= 65) {
          return t.coachMsgTrainGoodStart;
        }
        return t.coachMsgTrainRestart;

      case CoachMode.controle:
        final b = baseline;
        if (b != null && accuracy > b + 5) {
          return t.coachMsgControlMashallah;
        }
        if (pct >= 85) {
          return t.coachMsgControlVeryGood;
        }
        if (pct >= 65) {
          return t.coachMsgControlGoodPath;
        }
        return t.coachMsgControlKeepTraining;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.green900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.brass),
              child: const Icon(Icons.auto_awesome,
                  color: AppColors.green900, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _message(AppLocalizations.of(context)!),
                style: GoogleFonts.manrope(
                    fontSize: 13, color: AppColors.cream, height: 1.5),
              ),
            ),
          ],
        ),
      );
}

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green800,
          foregroundColor: AppColors.cream,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(double.infinity, 50),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.green700,
        side: const BorderSide(color: AppColors.green700),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }
}
