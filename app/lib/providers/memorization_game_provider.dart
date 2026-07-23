import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';

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
class MemorizationGameState {
  final List<GameVerse> verses;
  final int currentVerseIndex;
  final int currentWordIndex; // mot en jeu dans le verset courant
  final List<String> choices; // vide si mot 0 (affiché seul, pas de QCM)
  final bool wrongFlash; // dernier tap = mauvais mot (feedback visuel bref)
  final bool isGameComplete; // dernier mot du dernier verset validé

  const MemorizationGameState({
    required this.verses,
    required this.currentVerseIndex,
    required this.currentWordIndex,
    required this.choices,
    this.wrongFlash = false,
    this.isGameComplete = false,
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
  }) =>
      MemorizationGameState(
        verses: verses,
        currentVerseIndex: currentVerseIndex ?? this.currentVerseIndex,
        currentWordIndex: currentWordIndex ?? this.currentWordIndex,
        choices: choices ?? this.choices,
        wrongFlash: wrongFlash ?? false,
        isGameComplete: isGameComplete ?? this.isGameComplete,
      );
}

class MemorizationGameNotifier extends StateNotifier<MemorizationGameState> {
  final Random _random;

  MemorizationGameNotifier(List<Verse> verses, {Random? random})
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
  void _prepareChoicesIfNeeded() {
    if (state.isFirstWordOfVerse) {
      state = state.copyWith(choices: const []);
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
    state = state.copyWith(choices: choices);
  }

  /// Appelé quand l'utilisateur tape un mot (le premier mot affiché seul, ou
  /// un des choix du QCM). Si c'est le bon mot, avance ; sinon, déclenche un
  /// bref feedback visuel sans rien changer d'autre.
  void submitWord(String tapped) {
    if (state.isGameComplete) return;
    if (tapped != state.currentWord) {
      state = state.copyWith(wrongFlash: true);
      return;
    }
    if (state.wrongFlash) state = state.copyWith(wrongFlash: false);

    if (!state.isLastWordOfVerse) {
      state = state.copyWith(currentWordIndex: state.currentWordIndex + 1);
      _prepareChoicesIfNeeded();
      return;
    }
    if (!state.isLastVerse) {
      state = state.copyWith(
          currentVerseIndex: state.currentVerseIndex + 1, currentWordIndex: 0);
      _prepareChoicesIfNeeded();
      return;
    }
    // Dernier mot du dernier verset validé : jeu terminé.
    state = state.copyWith(choices: const [], isGameComplete: true);
  }

  /// Recommence le verset courant depuis le premier mot (bouton "recommencer").
  void restartVerse() {
    state = state.copyWith(
        currentWordIndex: 0, choices: const [], isGameComplete: false);
    _prepareChoicesIfNeeded();
  }
}

/// `family` sur la liste de versets choisie : un nouveau provider par session
/// de jeu, remis à zéro à chaque nouvelle sourate/plage sélectionnée via
/// `SurahPickerScreen` (aucune persistance -- volontairement minimal, comme
/// `last_coach_verse_provider.dart` le fait pour la reprise de mémorisation).
final memorizationGameProvider = StateNotifierProvider.family<
    MemorizationGameNotifier, MemorizationGameState, List<Verse>>(
  (ref, verses) => MemorizationGameNotifier(verses),
);
