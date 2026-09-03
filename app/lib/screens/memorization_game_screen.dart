// Mode jeu — mémorisation par QCM séquentiel mot par mot.
//
// Mécanique (cf. `.claude/skills/jeux-memorisation/SKILL.md`, décision
// utilisateur 2026-07-22, corrigée une première fois après un essai erroné) :
// le premier mot d'un verset s'affiche seul ; chaque mot suivant se choisit
// parmi plusieurs options mélangées (mot correct + leurres pris plus loin
// dans la sourate). Taper le bon mot fait avancer ; un mauvais tap ne fait
// que trembler brièvement, sans pénalité.
//
// Design (décision utilisateur 2026-07-22) : cet écran cible un public
// enfant et tranche volontairement avec le reste de l'app, plus sobre --
// palette saturée type appli de jeu (`AppColors.game*`), gros boutons ronds,
// animations de rebond/tremblement, célébration à étoiles en fin de partie.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../providers/debut_verset_game_provider.dart';
import '../providers/memorization_game_provider.dart';
import '../providers/memorization_game_records_provider.dart';
import '../providers/memorization_word_difficulty_provider.dart';
import '../theme/app_theme.dart';

class MemorizationGameScreen extends ConsumerWidget {
  final Surah surah;
  final List<Verse> verses;

  const MemorizationGameScreen({
    super.key,
    required this.surah,
    required this.verses,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final provider = memorizationGameProvider(verses);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    // ── STYLE « DÉBUT DE VERSET » (2026-08-28, demande utilisateur) ─────────
    //
    // « à l'ouverture du jeu enchaînement tu peux basculer style start
    // verset -- ça va se jouer que sur les débuts de verset [...] deux mots
    // par deux mots avec des mélanges de début [...] le numéro du verset,
    // bien décoré, avec les 4 propositions ». Un mode alternatif, PAS un
    // remplacement : bascule visible dès l'ouverture (`_StyleToggle`
    // ci-dessous), l'enchaînement habituel reste le défaut inchangé tant
    // qu'on ne la touche pas. Cf. debut_verset_game_provider.dart.
    final debutVersetMode = ref.watch(debutVersetModeProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(isArabic ? surah.nameArabic : surah.nameSimple,
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          // "Recommencer le verset" n'a pas de sens en "début de verset" (il
          // n'y a pas de verset EN COURS à reprendre, chaque question pioche
          // un verset différent) -- masqué plutôt que branché sur rien.
          if (!debutVersetMode)
            IconButton(
              tooltip: t.memorizationGameRestartVerseTooltip,
              icon: const Icon(Icons.replay_rounded),
              onPressed: notifier.restartVerse,
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.gameBgTop, AppColors.gameBgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60), // sous l'AppBar transparente
              // Bascule de style -- visible dans les DEUX modes, à
              // l'ouverture du jeu comme demandé (« à l'ouverture du jeu
              // enchaînement tu peux basculer style »). Masquée une fois la
              // partie d'enchaînement terminée (`_CompletionView` prend tout
              // l'écran) : rebasculer dessus n'aurait aucun sens sur un écran
              // qui ne montre déjà plus de question.
              if (debutVersetMode || !state.isGameComplete)
                const _StyleToggle(),
              Expanded(
                child: debutVersetMode
                    ? _DebutVersetGameBody(surah: surah, verses: verses)
                    : state.isGameComplete
                        ? _CompletionView(
                            surah: surah,
                            isArabic: isArabic,
                            finalWords: state.totalWordsCompleted,
                            portionLabel: state.currentPortionLabel,
                            portionTotal: state.currentPortionWordsTotal,
                            portionBest: state.currentPortionUnitKey == null
                                ? 0
                                : ref.watch(memorizationGameRecordsProvider)[
                                        state.currentPortionUnitKey!] ??
                                    0,
                          )
                        : Column(
                  children: [
                    _ScoreBar(
                      words: state.totalWordsCompleted,
                      portionLabel: state.currentPortionLabel,
                      portionTotal: state.currentPortionWordsTotal,
                      portionBest: state.currentPortionUnitKey == null
                          ? 0
                          : ref.watch(memorizationGameRecordsProvider)[
                                  state.currentPortionUnitKey!] ??
                              0,
                      justBeatRecord: state.justBeatRecord,
                    ),
                    // ── RÈGLES TOUJOURS VISIBLES (2026-08-10) ────────────────
                    // Demande utilisateur : « que les règles du jeu soient
                    // claires ». Rien n'expliquait avant ce qui se passe sur
                    // une erreur -- annoncé une fois pour toutes ici, plutôt
                    // que de compter sur le joueur pour le deviner.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Text(
                        t.memorizationGameRulesHint,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                            fontSize: 11.5, color: AppColors.inkLight),
                      ),
                    ),
                    // ── BANDEAU DE RECUL, LE TEMPS DE LA RÉVÉLATION ──────────
                    // Demande utilisateur : « qu'on montre qu'on revient en
                    // arrière, sinon celui qui joue ne va pas comprendre ».
                    // Le halo vert sur la bonne réponse (`_ChoiceGrid`) dit
                    // QUEL mot fallait taper ; ce bandeau dit ce qui va SE
                    // PASSER (retour au verset précédent, pénalité) --
                    // les deux ensemble, pas l'un à la place de l'autre.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: state.revealedAnswer != null
                          ? Padding(
                              key: const ValueKey('wrong-banner'),
                              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.gameWrong.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: AppColors.gameWrong.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.replay_rounded,
                                        color: AppColors.gameWrong, size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        t.memorizationGameWrongAnswerBanner,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.manrope(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.gameWrong),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox(key: ValueKey('no-banner')),
                    ),
                    // ── LE TEXTE S'ÉCRIT AU FUR ET À MESURE (2026-08-10) ─────
                    // Demande utilisateur : « je me demande si le mot est
                    // validé, qu'on réserve une partie de l'écran où le texte
                    // s'écrit, c'est visuel -- mais n'oublie pas les numéros
                    // de verset ». Montre ce qui vient d'être validé dans LE
                    // VERSET EN COURS (réponse au clarifiement : « il affiche
                    // ce qui vient d'être validé ») -- se vide avec lui à
                    // chaque nouveau verset ou relance après erreur.
                    _ValidatedTextPanel(
                      verse: state.currentVerse,
                      validatedCount: state.currentWordIndex,
                    ),
                    // ── PONT DE TRANSITION (2026-08-26) ──────────────────────
                    // Demande utilisateur : « le début des mots des versets
                    // sont souvent assujettis à l'oubli, cherche une
                    // méthodologie pour aider à mémoriser le début de
                    // verset ». La rupture est à la JONCTION : on montre la
                    // fin du verset PRÉCÉDENT au moment exact où on demande
                    // le premier mot du suivant, pour faire travailler ce
                    // lien-là plutôt que le mot isolé. Cf.
                    // `MemorizationGameState.pontVersetPrecedent`.
                    if (state.pontVersetPrecedent != null)
                      _PontTransition(texte: state.pontVersetPrecedent!),
                    Expanded(
                      child: Center(
                        child: state.isLoadingNextPage
                            ? const _NextPageLoading()
                            : state.choices.isEmpty
                                ? _FirstWordBubble(
                                    word: state.currentWord,
                                    onTap: () =>
                                        notifier.submitWord(state.currentWord),
                                  )
                                : _ChoiceGrid(
                                    choices: state.choices,
                                    wrongFlash: state.wrongFlash,
                                    revealedAnswer: state.revealedAnswer,
                                    justRedeemed: state.justRedeemed,
                                    difficultes:
                                        ref.watch(memorizationWordDifficultyProvider),
                                    onChoiceTap: notifier.submitWord,
                                  ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bascule de style, visible dès l'ouverture du jeu (2026-08-28, demande
/// utilisateur). UN SEUL contrôle segmenté (pas deux puces flottantes,
/// corrigé le même jour -- retour utilisateur : « style toggle mais c'est
/// mal agencé ») : un fond neutre unique, un indicateur doré qui glisse d'un
/// côté à l'autre. Motif standard (segmented control iOS/Material) plutôt
/// qu'inventé, et sa largeur pleine (comme le reste de la colonne) l'aligne
/// proprement avec `_ScoreBar`/`_DebutVersetScoreBar` juste en dessous, là où
/// deux puces de tailles différentes créaient un bord gauche irrégulier.
class _StyleToggle extends ConsumerWidget {
  const _StyleToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final mode = ref.watch(debutVersetModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.cream300, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: mode ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.gameStar,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.gameStar.withValues(alpha: 0.45),
                          blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _StyleSegment(
                    label: t.memorizationGameStyleChaining,
                    selected: !mode,
                    onTap: () =>
                        ref.read(debutVersetModeProvider.notifier).state = false,
                  ),
                ),
                Expanded(
                  child: _StyleSegment(
                    label: t.memorizationGameStyleVerseStart,
                    selected: mode,
                    onTap: () =>
                        ref.read(debutVersetModeProvider.notifier).state = true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StyleSegment({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.baloo2(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.inkLight,
          ),
        ),
      ),
    );
  }
}

/// Jeu « début de verset » (2026-08-28) : pioche un verset au hasard dans la
/// PORTION déjà ouverte (même `verses` que l'enchaînement, cf. la doc de
/// `debutVersetGameProvider`), affiche son numéro en grand, et propose 4 QCM
/// pour ses deux premiers mots. Cf. debut_verset_game_provider.dart pour le
/// pourquoi de ce mode (ancrer le numéro du verset à SON début, l'endroit le
/// plus sujet à l'oubli).
class _DebutVersetGameBody extends ConsumerWidget {
  final Surah surah;
  final List<Verse> verses;
  const _DebutVersetGameBody({required this.surah, required this.verses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final provider = debutVersetGameProvider(verses);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final q = state.question;

    if (state.pool.length < 2) {
      // Portion trop courte pour fournir 2 versets distincts (ex. une
      // sourate d'un seul verset) -- le dire plutôt qu'un écran vide muet.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            t.memorizationGameStyleVerseStartTooShort,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.inkLight),
          ),
        ),
      );
    }
    if (q == null) return const SizedBox.shrink();

    // ── CONTENU REMONTÉ, PAS ÉTALÉ (2026-08-28, retour utilisateur : « remonte
    // plus en haut ») ──────────────────────────────────────────────────────
    // La version précédente enveloppait la grille dans `Expanded(child:
    // Center(...))` : sur un écran haut, ça la centrait dans TOUT l'espace
    // restant sous le médaillon -- un grand vide entre les deux. Un simple
    // `Column` sans `Expanded` empile médaillon et grille l'un sous l'autre,
    // resserrés, plutôt que dispersés sur toute la hauteur disponible.
    return Column(
      children: [
        _DebutVersetScoreBar(score: state.score, streak: state.streak),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Text(
            t.memorizationGameStyleVerseStartHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
          ),
        ),
        _VerseNumberMedallion(surah: surah, ayah: q.verset.verse.ayahNumber),
        _DebutVersetChoiceGrid(
          propositions: q.propositions,
          correcte: q.reponseCorrecte,
          revele: state.revele,
          wrongFlash: state.wrongFlash,
          onTap: notifier.repondre,
        ),
      ],
    );
  }
}

class _DebutVersetScoreBar extends StatelessWidget {
  final int score;
  final int streak;
  const _DebutVersetScoreBar({required this.score, required this.streak});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_rounded, color: AppColors.gameStar, size: 20),
          const SizedBox(width: 6),
          Text('$score',
              style: GoogleFonts.baloo2(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          if (streak >= 3) ...[
            const SizedBox(width: 14),
            const Icon(Icons.local_fire_department_rounded,
                color: AppColors.gameWrong, size: 18),
            const SizedBox(width: 4),
            Text('$streak',
                style: GoogleFonts.baloo2(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkLight)),
          ],
        ],
      ),
    );
  }
}

/// Le numéro du verset, « bien décoré » (demande utilisateur explicite) :
/// médaillon doré à deux anneaux plutôt que le petit badge octogonal sobre du
/// Mushaf (`verse_tile.dart`) -- ici le numéro EST la question, il doit
/// dominer l'écran, pas se fondre dans le texte.
class _VerseNumberMedallion extends StatelessWidget {
  final Surah surah;
  final int ayah;
  const _VerseNumberMedallion({required this.surah, required this.ayah});

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gameStar, Color(0xFFFFA000)],
              ),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                    color: AppColors.gameStar.withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: 2),
              ],
            ),
            child: Center(
              child: Text(
                '$ayah',
                style: GoogleFonts.baloo2(
                    fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic ? surah.nameArabic : surah.nameSimple,
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: GoogleFonts.baloo2(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkLight),
          ),
        ],
      ),
    );
  }
}

/// Grille des 4 propositions -- réutilise `_ChoiceChip` (même style que
/// l'enchaînement) sans les extras propres à celui-ci (anneau de difficulté,
/// onde de rédemption) : pas de mesure de difficulté par mot construite pour
/// ce mode, et « juste redeemed » suppose un mot déjà raté puis retrouvé au
/// même endroit, ce que ce mode -- qui pioche un verset différent à chaque
/// question -- ne peut pas offrir.
class _DebutVersetChoiceGrid extends StatefulWidget {
  final List<String> propositions;
  final String correcte;
  final String? revele;
  final bool wrongFlash;
  final void Function(String) onTap;
  const _DebutVersetChoiceGrid({
    required this.propositions,
    required this.correcte,
    required this.revele,
    required this.wrongFlash,
    required this.onTap,
  });

  @override
  State<_DebutVersetChoiceGrid> createState() => _DebutVersetChoiceGridState();
}

class _DebutVersetChoiceGridState extends State<_DebutVersetChoiceGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void didUpdateWidget(covariant _DebutVersetChoiceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wrongFlash && !oldWidget.wrongFlash) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.revele != null;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final offset = sin(_shake.value * pi * 6) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final p in widget.propositions)
              _ChoiceChip(
                word: p,
                color: couleurDuMot(p),
                anneau: null,
                flashWrong: widget.wrongFlash,
                revealed: p == widget.revele,
                locked: locked,
                onTap: locked ? null : () => widget.onTap(p),
              ),
          ],
        ),
      ),
    );
  }
}

/// Score courant + record personnel (remplace l'ancienne barre "verset X sur
/// Y", cf. décision utilisateur 2026-08-07 : la partie est désormais
/// illimitée -- charge la page suivante toute seule au lieu de s'arrêter en
/// fin de page -- donc "X sur Y" n'a plus de sens (Y grandit sans cesse).
///
/// Reste un indicateur de TAILLE FIXE (deux nombres), ce qui préserve la
/// leçon du 2026-07-22 sur les grandes sourates (cf. historique de cette
/// classe) : jamais un élément par verset, même sous une autre forme.
class _ScoreBar extends StatefulWidget {
  final int words;
  // ── RECORD PAR PORTION, PAS GLOBAL (2026-08-12) ─────────────────────────
  // Remplace l'ancien `record` unique : la puce trophée affiche désormais le
  // record de LA PORTION (sourate/Hizb, cf. `PortionService`) à laquelle
  // appartient le verset EN COURS -- elle change donc de valeur en même
  // temps que le texte affiché plus bas change de sourate/Hizb, cohérent
  // avec « Mes portions » côté Coach qui suit le même découpage.
  // `portionTotal`/`portionLabel` sont `null` le temps très bref de la toute
  // première résolution asynchrone (cf. `_refreshCurrentPortionInfo`).
  final int portionBest;
  final int? portionTotal;
  final String? portionLabel;
  final bool justBeatRecord;
  const _ScoreBar({
    required this.words,
    required this.portionBest,
    required this.portionTotal,
    required this.portionLabel,
    required this.justBeatRecord,
  });

  @override
  State<_ScoreBar> createState() => _ScoreBarState();
}

class _ScoreBarState extends State<_ScoreBar> {
  bool _showNewRecord = false;

  @override
  void didUpdateWidget(covariant _ScoreBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.justBeatRecord && !oldWidget.justBeatRecord) {
      setState(() => _showNewRecord = true);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showNewRecord = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.bolt_rounded,
              color: AppColors.gameChipColors[1],
              label: t.memorizationGameWordsCount(widget.words),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedScale(
              scale: _showNewRecord ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: _StatChip(
                icon: Icons.emoji_events_rounded,
                color: AppColors.gameStar,
                label: _showNewRecord
                    ? t.memorizationGameNewRecord
                    : widget.portionTotal == null
                        ? '…'
                        : t.memorizationGameRecordLabel(
                            widget.portionBest, widget.portionTotal!),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatChip({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.baloo2(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );
}

/// Le texte du verset EN COURS, révélé mot par mot au fil des validations
/// (2026-08-10, demande utilisateur : « qu'on réserve une partie de l'écran
/// où le texte s'écrit [...] mais n'oublie pas les numéros de verset »).
///
/// Hauteur RÉSERVÉE fixe (`minHeight`) même à 0 mot validé : sans ça, le
/// reste de l'écran (grille de choix) sauterait verticalement à chaque mot
/// gagné -- l'utilisateur ne doit voir que le texte grandir, pas la mise en
/// page bouger. Vide -> tiret discret plutôt qu'un cadre qui semble cassé.
class _ValidatedTextPanel extends StatelessWidget {
  final GameVerse verse;
  final int validatedCount;
  const _ValidatedTextPanel({required this.verse, required this.validatedCount});

  @override
  Widget build(BuildContext context) {
    final texte = verse.words.take(validatedCount).join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              verse.verse.key,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                texte.isEmpty ? '—' : texte,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: GoogleFonts.scheherazadeNew(
                  fontSize: 24,
                  color: texte.isEmpty ? AppColors.inkLight : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Court état d'attente pendant que la page suivante se charge (quasi
/// instantané -- les données du Coran sont 100% locales, cf.
/// `QuranApi` -- mais un état visuel évite un dernier mot qui semble figé).
class _NextPageLoading extends StatelessWidget {
  const _NextPageLoading();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.gameStar),
        const SizedBox(height: 14),
        Text(t.memorizationGameLoadingNextPage,
            style: GoogleFonts.baloo2(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkLight)),
      ],
    );
  }
}

/// Le tout premier mot d'un verset : une seule grosse bulle à taper pour
/// démarrer, pas de QCM (rien à deviner, juste "c'est parti").
class _FirstWordBubble extends StatefulWidget {
  final String word;
  final VoidCallback onTap;
  const _FirstWordBubble({required this.word, required this.onTap});

  @override
  State<_FirstWordBubble> createState() => _FirstWordBubbleState();
}

class _FirstWordBubbleState extends State<_FirstWordBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.04).animate(
          CurvedAnimation(parent: _bounce, curve: Curves.easeInOut)),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gameStar, width: 4),
            boxShadow: [
              BoxShadow(
                color: AppColors.gameStar.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            widget.word,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(fontSize: 34, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Grille de choix mélangés (mot correct + leurres), rendus en gros boutons
/// ronds colorés type appli de jeu enfant. Tremble brièvement sur un mauvais
/// tap -- `wrongFlash` piloté par le provider.
///
/// [revealedAnswer] (2026-08-10, demande utilisateur : « une fois il rate, on
/// lui montre la bonne réponse [...] cherche une option pour l'aider à le
/// retrouver, des effets sur le mot en question ») -- non-null pendant la
/// courte fenêtre où le provider a déjà figé le verset en échec et s'apprête
/// à le relancer (cf. `MemorizationGameNotifier._restartVerseAfterReveal`) :
/// la puce qui porte ce mot se distingue des autres (halo vert, coche) pour
/// que l'œil s'y arrête avant la répétition.
class _ChoiceGrid extends StatefulWidget {
  final List<String> choices;
  final bool wrongFlash;
  final String? revealedAnswer;
  final void Function(String) onChoiceTap;

  /// Le mot qui vient d'être validé avait été raté auparavant (2026-08-26,
  /// demande utilisateur -- précisée le même jour : « pas vraiment le texte
  /// bravo mais un effet bravo »). D'où une ONDE de célébration dessinée
  /// par-dessus la grille (`_OndeReussite`), sans le moindre libellé : le
  /// geste se félicite tout seul, il n'a pas besoin d'être commenté.
  final bool justRedeemed;

  /// Échecs cumulés par mot (clé normalisée), cf.
  /// `memorization_word_difficulty_provider.dart` -- pilote la teinte fixe
  /// de chaque puce selon la règle unique `couleurDifficulte`.
  final Map<String, int> difficultes;

  const _ChoiceGrid({
    required this.choices,
    required this.wrongFlash,
    required this.revealedAnswer,
    required this.justRedeemed,
    required this.difficultes,
    required this.onChoiceTap,
  });

  @override
  State<_ChoiceGrid> createState() => _ChoiceGridState();
}

class _ChoiceGridState extends State<_ChoiceGrid>
    with TickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// L'effet de réussite sur un mot précédemment raté -- une seule passe,
  /// jamais en boucle : c'est une récompense ponctuelle.
  late final AnimationController _celebration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _ChoiceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wrongFlash && !oldWidget.wrongFlash) {
      _shake.forward(from: 0);
    }
    if (widget.justRedeemed && !oldWidget.justRedeemed) {
      _celebration.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _celebration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Verrouillé pendant la révélation : un tap pendant cette fenêtre est déjà
    // ignoré côté provider (`submitWord` sort tôt si `revealedAnswer != null`)
    // -- désactiver le geste ici évite en plus le petit "enfoncement" visuel
    // d'une puce qui ne va rien déclencher.
    final locked = widget.revealedAnswer != null;
    final grille = AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final offset = sin(_shake.value * pi * 6) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < widget.choices.length; i++)
              _ChoiceChip(
                word: widget.choices[i],
                // COULEUR DU MOT, jamais de la position dans la grille (la
                // grille est remélangée à chaque tour) -- cf. `couleurDuMot`
                // et le défaut qu'elle corrige.
                color: couleurDuMot(widget.choices[i]),
                // Canal SÉPARÉ pour la difficulté, pour que la couleur du mot
                // reste constante (cf. `anneauDifficulte`).
                anneau: anneauDifficulte(widget.difficultes[
                        MemorizationWordDifficulty.cle(widget.choices[i])] ??
                    0),
                flashWrong: widget.wrongFlash,
                revealed: widget.choices[i] == widget.revealedAnswer,
                locked: locked,
                onTap: locked ? null : () => widget.onChoiceTap(widget.choices[i]),
              ),
          ],
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        grille,
        // L'onde ne capte aucun geste (`IgnorePointer`) : elle passe
        // par-dessus la grille pendant que le jeu continue dessous.
        Positioned.fill(
          child: IgnorePointer(
            child: _OndeReussite(animation: _celebration),
          ),
        ),
      ],
    );
  }
}

/// EFFET DE RÉUSSITE sur un mot qui avait été raté (2026-08-26).
///
/// Demande utilisateur, précisée en cours de route : « pas vraiment le texte
/// bravo mais un effet bravo ». Donc aucun libellé, aucune icône de
/// félicitation -- une onde dorée qui s'ouvre depuis le centre de la grille
/// et s'efface. Le joueur comprend qu'il vient de récupérer un mot qui lui
/// résistait, sans qu'on ait besoin de le lui écrire.
///
/// Dessiné plutôt qu'animé en widgets : trois anneaux concentriques décalés
/// coûtent un seul repaint, là où trois `AnimatedContainer` empilés
/// relayeraient une reconstruction à chaque frame.
class _OndeReussite extends StatelessWidget {
  final Animation<double> animation;
  const _OndeReussite({required this.animation});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) => animation.value == 0
            ? const SizedBox.shrink()
            : CustomPaint(painter: _OndePainter(animation.value)),
      );
}

class _OndePainter extends CustomPainter {
  final double t; // 0 -> 1
  _OndePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final rayonMax = size.shortestSide * 0.9;
    // Trois anneaux décalés dans le temps : le premier part tout de suite, les
    // suivants avec un retard, ce qui donne la pulsation plutôt qu'un cercle
    // unique qui grandit.
    for (var i = 0; i < 3; i++) {
      final avance = (t - i * 0.15).clamp(0.0, 1.0);
      if (avance <= 0) continue;
      final opacite = (1 - avance) * 0.55;
      if (opacite <= 0) continue;
      canvas.drawCircle(
        centre,
        rayonMax * avance,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - avance) + 1
          ..color = AppColors.gameStar.withValues(alpha: opacite),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OndePainter old) => old.t != t;
}

/// PONT DE TRANSITION : la fin du verset précédent, affichée au moment où le
/// premier mot du verset suivant est demandé (2026-08-26). Cf. la doc de
/// `MemorizationGameState.pontVersetPrecedent` pour le raisonnement.
class _PontTransition extends StatelessWidget {
  final String texte;
  const _PontTransition({required this.texte});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.gameStar.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gameStar.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              t.memorizationGameBridgeHint,
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkLight),
            ),
            const SizedBox(height: 4),
            Text(
              texte,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: GoogleFonts.scheherazadeNew(
                  fontSize: 22, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatefulWidget {
  final String word;
  final Color color;

  /// Anneau de DIFFICULTÉ, canal distinct de [color] pour que la couleur du
  /// mot reste constante (cf. `anneauDifficulte`). `null` = mot jamais raté.
  final Color? anneau;
  final bool flashWrong;
  final bool revealed;
  final bool locked;
  final VoidCallback? onTap;

  const _ChoiceChip({
    required this.word,
    required this.color,
    required this.anneau,
    required this.flashWrong,
    required this.revealed,
    required this.locked,
    required this.onTap,
  });

  @override
  State<_ChoiceChip> createState() => _ChoiceChipState();
}

class _ChoiceChipState extends State<_ChoiceChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Le mot révélé se distingue par un halo vert franc + une coche, plutôt
    // qu'une simple bordure -- il doit sauter aux yeux au premier coup d'œil,
    // pas se remarquer seulement en cherchant.
    final glow = widget.revealed ? AppColors.gameCorrect : widget.color;
    return GestureDetector(
      onTapDown: widget.locked ? null : (_) => setState(() => _pressed = true),
      onTapCancel: widget.locked ? null : () => setState(() => _pressed = false),
      onTapUp: widget.locked ? null : (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: widget.revealed ? 1.08 : (_pressed ? 0.9 : 1.0),
        duration: const Duration(milliseconds: 220),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(28),
            // La révélation prime sur l'anneau de difficulté : pendant cette
            // fenêtre, c'est « voici la bonne réponse » qui doit se lire, pas
            // l'historique du mot.
            border: widget.revealed
                ? Border.all(color: Colors.white, width: 3)
                : widget.anneau != null
                    ? Border.all(color: widget.anneau!, width: 3)
                    : null,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: widget.revealed ? 0.9 : 0.5),
                blurRadius: widget.revealed ? 22 : 10,
                spreadRadius: widget.revealed ? 3 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.word,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 26, color: Colors.white, fontWeight: FontWeight.w600),
              ),
              if (widget.revealed) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  final Surah surah;
  final bool isArabic;
  final int finalWords;
  final String? portionLabel;
  final int? portionTotal;
  final int portionBest;
  const _CompletionView({
    required this.surah,
    required this.isArabic,
    required this.finalWords,
    required this.portionLabel,
    required this.portionTotal,
    required this.portionBest,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.star_rounded,
                        color: AppColors.gameStar, size: 52),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.memorizationGameCompleteTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              t.memorizationGameCompleteBody(
                  isArabic ? surah.nameArabic : surah.nameSimple),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.inkLight),
            ),
            const SizedBox(height: 10),
            Text(
              t.memorizationGameFinalScore(
                  finalWords, max(finalWords, portionBest)),
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gameStar),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gameCorrect,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(t.memorizationGameBackToHub,
                  style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
