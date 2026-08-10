import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import 'memorization_game_records_provider.dart';

/// Un verset découpé en mots pour le jeu.
class GameVerse {
  final Verse verse;
  final List<String> words;
  const GameVerse({required this.verse, required this.words});

  factory GameVerse.fromVerse(Verse verse) {
    // Split sur les espaces uniquement : les diacritiques (tashkeel) collés
    // aux lettres arabes font partie du mot et ne doivent pas être coupés.
    //
    // ── LES SIGNES DE PAUSE EXCLUS (2026-08-09, demande utilisateur) ───────
    // « exclu les signes dans le jeux, par exemple waqf, on se concentre sur
    // les mots, les vrais mots du Coran ». Un signe de pause (ۖ ۗ ۚ ۛ ۜ...)
    // ou une marque décorative (۞ fin de hizb, ۩ sajda) peut apparaître
    // isolé entre deux espaces dans le texte Uthmani -- ce n'est pas un mot
    // à mémoriser, le récitant ne le PRONONCE pas. Même filtre déjà utilisé
    // pour la même raison dans mushaf_screen.dart (désynchronisation de
    // l'index sinon) : un token qui ne contient AUCUNE lettre arabe une fois
    // normalisé (`ArabicNormalizer.normalize` ne garde que lettres+harakat)
    // n'est pas un mot.
    final tokens = verse.textUthmani
        .split(RegExp(r'\s+'))
        .where((w) =>
            w.trim().isNotEmpty && ArabicNormalizer.normalize(w).isNotEmpty)
        .toList();
    return GameVerse(verse: verse, words: tokens);
  }
}

/// État du jeu de mémorisation par QCM séquentiel mot par mot.
///
/// Mécanique (cf. `.claude/skills/jeux-memorisation/SKILL.md`, corrigée le
/// 2026-07-22 après un premier essai erroné) : à chaque étape, un seul mot
/// est "en jeu" -- soit le tout premier mot du verset (affiché seul, pas de
/// choix), soit un choix de plusieurs mots mélangés (mot correct + leurres)
/// pour les mots suivants. Taper le bon mot fait avancer ; taper un leurre ne
/// fait rien (pas de pénalité, mêmes choix retentés).
///
/// PARTIE ILLIMITÉE (demande utilisateur 2026-08-07, remplace la règle du
/// 2026-07-22 qui arrêtait la partie en fin de page) : une fois le dernier
/// mot du dernier verset CHARGÉ validé, le notifier va chercher la page
/// suivante du Mushaf tout seul (`QuranApi.fetchVersesByPage`, 100% local
/// donc quasi instantané) et l'ajoute à la liste -- la partie ne s'arrête
/// que si cette page n'existe plus (fin du Coran, page 604) ou si le
/// chargement échoue. `isLoadingNextPage` couvre le court instant entre les
/// deux pour que l'écran puisse afficher un état d'attente plutôt qu'un
/// dernier mot qui ne réagit plus.
class MemorizationGameState {
  final List<GameVerse> verses;
  final int currentVerseIndex;
  final int currentWordIndex; // mot en jeu dans le verset courant
  final List<String> choices; // vide si mot 0 (affiché seul, pas de QCM)
  final bool wrongFlash; // dernier tap = mauvais mot (feedback visuel bref)
  final bool isGameComplete; // fin du Coran atteinte, ou page suivante injoignable
  final bool isLoadingNextPage;
  final int totalWordsCompleted; // mots validés depuis le début de LA partie
  final bool justBeatRecord; // le mot qui vient d'être validé a battu le record

  /// Mot qui vient d'être raté -- reste affiché en surbrillance parmi les
  /// choix le temps que le joueur le voie, PUIS le verset redémarre (demande
  /// utilisateur 2026-08-10 : « une fois il rate, on lui montre la bonne
  /// réponse et il doit recommencer, ça entre dans la répétition pour se
  /// mémoriser [...] cherche une option pour l'aider à le retrouver, des
  /// effets sur le mot en question »). Pas de jauge de vies : CHAQUE erreur
  /// relance le verset -- l'ancien "aucune pénalité, mêmes choix retentés"
  /// est remplacé par cette révélation + répétition, jugée plus utile pour
  /// mémoriser qu'un essai-erreur silencieux et illimité.
  ///
  /// `null` hors de cette révélation. Le NOM du champ (pas juste
  /// `wrongFlash: true`) est nécessaire : l'écran doit savoir QUEL mot
  /// mettre en évidence, et `state.currentWord` aura déjà changé de sens une
  /// fois le verset relancé.
  final String? revealedAnswer;

  const MemorizationGameState({
    required this.verses,
    required this.currentVerseIndex,
    required this.currentWordIndex,
    required this.choices,
    this.wrongFlash = false,
    this.isGameComplete = false,
    this.isLoadingNextPage = false,
    this.totalWordsCompleted = 0,
    this.justBeatRecord = false,
    this.revealedAnswer,
  });

  GameVerse get currentVerse => verses[currentVerseIndex];
  String get currentWord => currentVerse.words[currentWordIndex];
  bool get isFirstWordOfVerse => currentWordIndex == 0;
  /// Vrai UNIQUEMENT pour le tout premier mot de TOUTE la partie -- distinct
  /// de [isFirstWordOfVerse]. Cf. `_prepareChoicesIfNeeded` pour pourquoi la
  /// distinction existe.
  bool get isVeryFirstWord => currentVerseIndex == 0 && currentWordIndex == 0;
  bool get isLastVerse => currentVerseIndex == verses.length - 1;
  bool get isLastWordOfVerse => currentWordIndex == currentVerse.words.length - 1;

  MemorizationGameState copyWith({
    int? currentVerseIndex,
    int? currentWordIndex,
    List<String>? choices,
    bool? wrongFlash,
    bool? isGameComplete,
    bool? isLoadingNextPage,
    int? totalWordsCompleted,
    bool? justBeatRecord,
    String? revealedAnswer,
  }) =>
      MemorizationGameState(
        verses: verses,
        currentVerseIndex: currentVerseIndex ?? this.currentVerseIndex,
        currentWordIndex: currentWordIndex ?? this.currentWordIndex,
        choices: choices ?? this.choices,
        wrongFlash: wrongFlash ?? false,
        isGameComplete: isGameComplete ?? this.isGameComplete,
        isLoadingNextPage: isLoadingNextPage ?? this.isLoadingNextPage,
        totalWordsCompleted: totalWordsCompleted ?? this.totalWordsCompleted,
        justBeatRecord: justBeatRecord ?? false,
        revealedAnswer: revealedAnswer ?? this.revealedAnswer,
      );

  /// Nouvelle liste avec des versets supplémentaires -- seul champ qui ne
  /// passe pas par `copyWith` (celui-ci garde `verses` figé, cf. son usage
  /// partout ailleurs pour ne PAS le faire varier par accident).
  MemorizationGameState withMoreVerses(List<GameVerse> extra) =>
      MemorizationGameState(
        verses: [...verses, ...extra],
        currentVerseIndex: currentVerseIndex,
        currentWordIndex: currentWordIndex,
        choices: choices,
        wrongFlash: wrongFlash,
        isGameComplete: isGameComplete,
        isLoadingNextPage: isLoadingNextPage,
        totalWordsCompleted: totalWordsCompleted,
        justBeatRecord: justBeatRecord,
        revealedAnswer: revealedAnswer,
      );

  /// Relance LE VERSET COURANT depuis son premier mot -- même geste que le
  /// bouton "recommencer" manuel, mais déclenché seul après une révélation
  /// (demande utilisateur 2026-08-10 : « il doit recommencer, ça entre dans
  /// la répétition pour se mémoriser »). Volontairement PAS toute la partie
  /// (« on ne va pas commencer depuis tout le début ») : la progression
  /// (mots enchaînés, pages déjà chargées) reste acquise.
  ///
  /// ── UN PALIER EN ARRIÈRE, PAS LE VERSET RATÉ LUI-MÊME (2026-08-10) ──────
  /// Retour utilisateur après le premier essai (palier = le verset raté lui-
  /// même) : « le mieux c'est de revenir à un palier avant pour continuer le
  /// jeu ». Repartir du verset PRÉCÉDENT (déjà validé -- on ne peut être sur
  /// `currentVerseIndex` qu'après avoir fini `currentVerseIndex - 1`, cf.
  /// `submitWord`) donne un petit élan de mots déjà sûrs avant de rattaquer
  /// le passage qui a fait échouer, au lieu de retomber immédiatement dessus.
  /// Verset 0 : rien avant, reste sur place (`currentVerseIndex - 1` borné à
  /// 0 par le `? :` ci-dessous).
  ///
  /// Construction directe plutôt que `copyWith` : il faut pouvoir remettre
  /// `revealedAnswer` à `null`, ce que le motif `champ ?? this.champ` de
  /// `copyWith` ne permet pas de faire explicitement.
  MemorizationGameState afterVerseRestart() => MemorizationGameState(
        verses: verses,
        currentVerseIndex: currentVerseIndex > 0 ? currentVerseIndex - 1 : 0,
        currentWordIndex: 0,
        choices: const [],
        totalWordsCompleted: totalWordsCompleted,
      );
}

class MemorizationGameNotifier extends StateNotifier<MemorizationGameState> {
  final Random _random;
  final Ref _ref;

  MemorizationGameNotifier(List<Verse> verses, this._ref, {Random? random})
      : _random = random ?? Random(),
        super(_initialState([
          for (final v in verses) GameVerse.fromVerse(v)
        ])) {
    _prepareChoicesIfNeeded();
  }

  static MemorizationGameState _initialState(List<GameVerse> verses) =>
      MemorizationGameState(
        verses: verses,
        currentVerseIndex: 0,
        currentWordIndex: 0,
        choices: const [],
      );

  /// Nombre de leurres proposés en plus du mot correct.
  static const int _distractorCount = 3;

  /// Construit un jeu de choix mélangés pour `currentWordIndex`, SAUF pour le
  /// tout premier mot de toute la partie (affiché seul, rien à tester avant
  /// lui). Préserve `justBeatRecord` tel quel (ne PAS re-suivre le défaut `??
  /// false` de `copyWith`) : cette méthode est appelée juste après que
  /// `submitWord`/`_loadNextPage` l'aient positionné pour LE mot qui vient
  /// d'être validé -- l'écraser ici ferait disparaître le flash "record
  /// battu" avant même le premier rebuild qui aurait pu l'afficher.
  ///
  /// ── LE PREMIER MOT D'UN NOUVEAU VERSET EST DÉSORMAIS TESTÉ (2026-08-09) ──
  ///
  /// Demande utilisateur : « dans l'enchaînement des ayat, il commence
  /// toujours par le premier mot du verset, alors que c'est là qu'il y a
  /// l'oubli -- souvent les gens n'arrivent pas à se souvenir du premier
  /// mot ». Avant ce correctif, `isFirstWordOfVerse` (mot 0 de N'IMPORTE
  /// QUEL verset) sautait le QCM et AFFICHAIT le mot -- la transition, qui
  /// est précisément l'endroit où la mémoire lâche, n'était donc jamais
  /// vérifiée, seulement révélée.
  ///
  /// Seul le tout premier mot de la PARTIE ([isVeryFirstWord]) garde
  /// l'affichage seul : rien ne le précède, il n'y a rien à tester avant lui.
  void _prepareChoicesIfNeeded() {
    if (state.isVeryFirstWord) {
      state = state.copyWith(
          choices: const [], justBeatRecord: state.justBeatRecord);
      return;
    }
    final correct = state.currentWord;
    final pool = <String>[];
    // Leurres pris parmi les mots de la sourate NON ENCORE atteints dans la
    // progression -- cohérent avec ce qui est en cours de mémorisation,
    // jamais du texte déjà vu (qui donnerait un indice trop facile) ni d'un
    // autre endroit du Coran.
    for (var vi = state.currentVerseIndex; vi < state.verses.length; vi++) {
      final words = state.verses[vi].words;
      final startWord = vi == state.currentVerseIndex ? state.currentWordIndex + 1 : 0;
      for (var wi = startWord; wi < words.length; wi++) {
        final w = words[wi];
        if (w != correct) pool.add(w);
      }
    }
    pool.shuffle(_random);
    final distractors = pool.take(_distractorCount).toList();
    final choices = [correct, ...distractors]..shuffle(_random);
    state = state.copyWith(choices: choices, justBeatRecord: state.justBeatRecord);
  }

  /// Coût d'une erreur sur le compteur de mots enchaînés (demande
  /// utilisateur 2026-08-10 : « le nombre de mots enchaînés doit être avec
  /// punition en cas d'erreur, exemple -5 points »). Le compteur ne descend
  /// jamais sous 0 -- "-3 mots enchaînés" n'aurait aucun sens affiché.
  static const int _wrongAnswerPenalty = 5;

  /// Appelé quand l'utilisateur tape un mot (le premier mot affiché seul, ou
  /// un des choix du QCM). Si c'est le bon mot, avance ; sinon, retire
  /// [_wrongAnswerPenalty] au compteur, RÉVÈLE la bonne réponse (mise en
  /// évidence dans `_ChoiceGrid`) puis relance un palier plus tôt après un
  /// court délai -- cf. `MemorizationGameState.revealedAnswer` et
  /// `afterVerseRestart` pour le raisonnement complet.
  void submitWord(String tapped) {
    if (state.isGameComplete ||
        state.isLoadingNextPage ||
        state.revealedAnswer != null) {
      return;
    }
    if (tapped != state.currentWord) {
      final correct = state.currentWord;
      state = state.copyWith(
        wrongFlash: true,
        revealedAnswer: correct,
        totalWordsCompleted:
            max(0, state.totalWordsCompleted - _wrongAnswerPenalty),
      );
      unawaited(_restartVerseAfterReveal());
      return;
    }

    final total = state.totalWordsCompleted + 1;
    final beatRecord =
        _ref.read(memorizationGameRecordProvider.notifier).reportScore(total);

    if (!state.isLastWordOfVerse) {
      state = state.copyWith(
        currentWordIndex: state.currentWordIndex + 1,
        totalWordsCompleted: total,
        justBeatRecord: beatRecord,
      );
      _prepareChoicesIfNeeded();
      return;
    }
    if (!state.isLastVerse) {
      state = state.copyWith(
        currentVerseIndex: state.currentVerseIndex + 1,
        currentWordIndex: 0,
        totalWordsCompleted: total,
        justBeatRecord: beatRecord,
      );
      _prepareChoicesIfNeeded();
      return;
    }
    // Dernier mot du dernier verset CHARGÉ : la partie ne s'arrête pas ici
    // (cf. commentaire de la classe) -- va chercher la page suivante.
    state = state.copyWith(totalWordsCompleted: total, justBeatRecord: beatRecord);
    unawaited(_loadNextPage());
  }

  /// Étend la partie avec la page suivante du Mushaf, appelé quand le
  /// dernier mot chargé vient d'être validé. S'arrête (`isGameComplete`)
  /// seulement si la page n'existe pas (fin du Coran, page 604) ou si le
  /// chargement échoue -- jamais en fin de page comme avant le 2026-08-07.
  Future<void> _loadNextPage() async {
    final page = state.verses.last.verse.pageNumber;
    if (page == null) {
      state = state.copyWith(choices: const [], isGameComplete: true);
      return;
    }
    state = state.copyWith(
        isLoadingNextPage: true, justBeatRecord: state.justBeatRecord);
    List<Verse> nextVerses;
    try {
      nextVerses = await QuranApi.fetchVersesByPage(page + 1);
    } catch (_) {
      nextVerses = const [];
    }
    if (!mounted) return; // l'écran a pu être quitté pendant l'attente
    if (nextVerses.isEmpty) {
      state = state.copyWith(
          choices: const [], isGameComplete: true, isLoadingNextPage: false);
      return;
    }
    final firstNewIndex = state.verses.length;
    state = state
        .withMoreVerses(
            [for (final v in nextVerses) GameVerse.fromVerse(v)])
        .copyWith(
          currentVerseIndex: firstNewIndex,
          currentWordIndex: 0,
          isLoadingNextPage: false,
          justBeatRecord: state.justBeatRecord,
        );
    _prepareChoicesIfNeeded();
  }

  /// Recommence le verset courant depuis le premier mot (bouton "recommencer").
  /// Ne touche PAS `totalWordsCompleted` : c'est un choix délibéré du joueur
  /// de retenter ce verset, pas une pénalité qui doit annuler ce qu'il a déjà
  /// gagné dans cette partie.
  void restartVerse() {
    state = state.copyWith(
        currentWordIndex: 0, choices: const [], isGameComplete: false);
    _prepareChoicesIfNeeded();
  }

  /// Laisse la bonne réponse en évidence le temps que le joueur la voie, puis
  /// relance LE VERSET (le "palier" invisible le plus récemment validé --
  /// demande utilisateur 2026-08-10 : « ces paliers sont invisibles, quand il
  /// enchaîne et dépasse un palier sans erreur il est validé, après s'il
  /// rate il revient à ce palier » -- un palier = un verset : le précédent
  /// est acquis dès qu'on l'a quitté, seul le verset EN COURS se répète).
  Future<void> _restartVerseAfterReveal() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    state = state.afterVerseRestart();
    _prepareChoicesIfNeeded();
  }
}

/// `family` sur la liste de versets choisie : un nouveau provider par session
/// de jeu, remis à zéro à chaque nouvelle sourate/plage sélectionnée via
/// `SurahPickerScreen` (aucune persistance de la PROGRESSION -- volontairement
/// minimal, comme `last_coach_verse_provider.dart` le fait pour la reprise de
/// mémorisation ; seul le RECORD traverse les sessions, cf.
/// `memorization_game_records_provider.dart`).
final memorizationGameProvider = StateNotifierProvider.family<
    MemorizationGameNotifier, MemorizationGameState, List<Verse>>(
  (ref, verses) => MemorizationGameNotifier(verses, ref),
);
