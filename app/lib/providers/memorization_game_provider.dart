import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../services/quran_api.dart';
import 'memorization_game_records_provider.dart';

/// Un verset découpé en mots pour le jeu.
class GameVerse {
  final Verse verse;
  final List<String> words;
  const GameVerse({required this.verse, required this.words});

  factory GameVerse.fromVerse(Verse verse) {
    // Split sur les espaces uniquement : les diacritiques (tashkeel) collés
    // aux lettres arabes font partie du mot et ne doivent pas être coupés.
    final tokens = verse.textUthmani
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
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
  });

  GameVerse get currentVerse => verses[currentVerseIndex];
  String get currentWord => currentVerse.words[currentWordIndex];
  bool get isFirstWordOfVerse => currentWordIndex == 0;
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

  /// Construit un jeu de choix mélangés pour `currentWordIndex` si ce n'est
  /// pas le tout premier mot du verset courant (le mot 0 s'affiche seul).
  /// Préserve `justBeatRecord` tel quel (ne PAS re-suivre le défaut `??
  /// false` de `copyWith`) : cette méthode est appelée juste après que
  /// `submitWord`/`_loadNextPage` l'aient positionné pour LE mot qui vient
  /// d'être validé -- l'écraser ici ferait disparaître le flash "record
  /// battu" avant même le premier rebuild qui aurait pu l'afficher.
  void _prepareChoicesIfNeeded() {
    if (state.isFirstWordOfVerse) {
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

  /// Appelé quand l'utilisateur tape un mot (le premier mot affiché seul, ou
  /// un des choix du QCM). Si c'est le bon mot, avance ; sinon, déclenche un
  /// bref feedback visuel sans rien changer d'autre.
  void submitWord(String tapped) {
    if (state.isGameComplete || state.isLoadingNextPage) return;
    if (tapped != state.currentWord) {
      state = state.copyWith(wrongFlash: true);
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
