import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../services/portion_service.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import 'app_settings_provider.dart' show portionGranularityProvider;
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

  /// Index global (cf. [globalWordIndex]) du mot le plus loin jamais validé
  /// dans LA PARTIE -- traverse les retours en arrière de
  /// [afterVerseRestart] SANS être réinitialisé (décision 2026-08-10, cf. le
  /// bug documenté sur [globalWordIndex] et `submitWord`). `-1` = rien
  /// validé encore (le tout premier mot, index global 0, est alors bien une
  /// progression : `0 > -1`).
  final int furthestGlobalWordIndex;

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

  /// Identité de la PORTION (sourate ou tranche de Hizb, cf.
  /// `PortionService.resolve`) à laquelle appartient le verset courant --
  /// résolue de façon asynchrone (2026-08-12, cf. `_refreshCurrentPortionInfo`
  /// dans le notifier) : `null` tant que la toute première résolution n'est
  /// pas revenue (bref, données locales déjà en cache après le premier appel).
  /// Sert à afficher ET à faire correspondre "xx sur YY" au bon record dans
  /// `memorizationGameRecordsProvider` (clé `unitKey`) -- même découpe que
  /// « Mes portions » côté Coach, pour que battre un record ici se voie
  /// là-bas (demande utilisateur : « rattaché au coach avec mes portions »).
  final String? currentPortionUnitKey;
  final String? currentPortionLabel;
  final int? currentPortionWordsTotal;

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
    this.furthestGlobalWordIndex = -1,
    this.currentPortionUnitKey,
    this.currentPortionLabel,
    this.currentPortionWordsTotal,
  });

  /// Index global cumulé (sur tous les versets déjà chargés, dans l'ordre) du
  /// mot (verseIndex, wordIndex) -- ex. verset 0 de 3 mots puis verset 1 : le
  /// mot 0 du verset 1 a l'index global 3. Sert de base de comparaison stable
  /// à [furthestGlobalWordIndex] pour distinguer un mot qui fait progresser
  /// LE SCORE (jamais atteint avant dans la partie) d'un mot déjà validé
  /// qu'on retape après un retour en arrière ([afterVerseRestart]).
  /// Stable dans le temps car [withMoreVerses] n'ajoute des versets qu'À LA
  /// FIN de la liste -- la longueur des versets déjà chargés ne change
  /// jamais après coup.
  int globalWordIndex(int verseIndex, int wordIndex) {
    var offset = 0;
    for (var vi = 0; vi < verseIndex; vi++) {
      offset += verses[vi].words.length;
    }
    return offset + wordIndex;
  }

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
    int? furthestGlobalWordIndex,
    String? currentPortionUnitKey,
    String? currentPortionLabel,
    int? currentPortionWordsTotal,
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
        furthestGlobalWordIndex:
            furthestGlobalWordIndex ?? this.furthestGlobalWordIndex,
        currentPortionUnitKey: currentPortionUnitKey ?? this.currentPortionUnitKey,
        currentPortionLabel: currentPortionLabel ?? this.currentPortionLabel,
        currentPortionWordsTotal:
            currentPortionWordsTotal ?? this.currentPortionWordsTotal,
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
        furthestGlobalWordIndex: furthestGlobalWordIndex,
        currentPortionUnitKey: currentPortionUnitKey,
        currentPortionLabel: currentPortionLabel,
        currentPortionWordsTotal: currentPortionWordsTotal,
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
  /// `furthestGlobalWordIndex` est explicitement PRÉSERVÉ (pas omis comme
  /// `totalWordsCompleted` en serait tenté) : c'est précisément le champ qui
  /// doit survivre à ce retour en arrière pour empêcher `submitWord` de
  /// recréditer le score sur des mots déjà validés une première fois --
  /// cf. sa doc et le commentaire dans `submitWord`.
  MemorizationGameState afterVerseRestart() => MemorizationGameState(
        verses: verses,
        currentVerseIndex: currentVerseIndex > 0 ? currentVerseIndex - 1 : 0,
        currentWordIndex: 0,
        choices: const [],
        totalWordsCompleted: totalWordsCompleted,
        furthestGlobalWordIndex: furthestGlobalWordIndex,
        currentPortionUnitKey: currentPortionUnitKey,
        currentPortionLabel: currentPortionLabel,
        currentPortionWordsTotal: currentPortionWordsTotal,
      );
}

class MemorizationGameNotifier extends StateNotifier<MemorizationGameState> {
  final Random _random;
  final Ref _ref;

  /// Nombre de mots validés DANS CETTE PARTIE pour chaque portion déjà
  /// traversée (clé = `PortionInfo.unitKey`) -- sert de compteur courant à
  /// comparer au record persisté (`memorizationGameRecordsProvider`).
  /// N'incrémente que sur une progression réelle (même garde `isNewProgress`
  /// que `totalWordsCompleted`), donc jamais recompté après un
  /// `afterVerseRestart` sur des mots déjà comptés une première fois.
  final Map<String, int> _portionRunCounts = {};

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
    unawaited(_refreshCurrentPortionInfo());
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

  /// Résout à quelle portion (Coach) appartient le verset EN COURS, et met
  /// l'identité de cette portion dans `state` pour l'affichage (2026-08-12).
  /// Appelée à chaque changement de verset via `_prepareChoicesIfNeeded` --
  /// jamais dans le flux synchrone de `submitWord` (qui, lui, ne doit pas
  /// attendre un `Future`, cf. `_reportPortionProgress` séparée ci-dessous).
  Future<void> _refreshCurrentPortionInfo() async {
    try {
      final granularite = _ref.read(portionGranularityProvider);
      final portion = await PortionService.resolve(
          verse: state.currentVerse.verse, granularity: granularite);
      if (!mounted) return;
      state = state.copyWith(
        currentPortionUnitKey: portion.unitKey,
        currentPortionLabel: portion.label,
        currentPortionWordsTotal: portion.wordsTotal,
      );
    } catch (_) {
      // Affichage seul : une résolution ratée ne doit jamais bloquer la partie.
    }
  }

  /// Enregistre la progression dans LA PORTION du mot qui vient de faire
  /// avancer le score (2026-08-12, demande utilisateur : « je veux que le
  /// record soit par sourate/Hizb [...] rattaché au coach avec mes portions,
  /// à chaque record battu le record soit mis à jour côté coach »). Remplace
  /// l'ancien record global unique (2026-08-07) : chaque sourate/tranche de
  /// Hizb garde désormais son propre meilleur enchaînement.
  ///
  /// ASYNCHRONE et séparée du flux synchrone de `submitWord` (qui, lui, reste
  /// inchangé) : résoudre la portion relit `QuranApi` (mis en cache, quasi
  /// instantané après le tout premier appel, mais reste un `Future`). Le mot
  /// avance à l'écran sans attendre cette résolution ; le flash "record battu"
  /// arrive au prochain rebuild, imperceptible dans les faits.
  Future<void> _reportPortionProgress(Verse verse) async {
    try {
      final granularite = _ref.read(portionGranularityProvider);
      final portion =
          await PortionService.resolve(verse: verse, granularity: granularite);
      final compte = (_portionRunCounts[portion.unitKey] ?? 0) + 1;
      _portionRunCounts[portion.unitKey] = compte;
      final battu = _ref
          .read(memorizationGameRecordsProvider.notifier)
          .reportScore(portion.unitKey, compte);
      if (battu && mounted) {
        state = state.copyWith(justBeatRecord: true);
      }
    } catch (_) {
      // Le record est un confort ludique : jamais un motif d'échec de partie.
    }
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

    // ── LE SCORE NE COMPTE QUE LA PROGRESSION AU-DELÀ DU POINT LE PLUS LOIN
    // JAMAIS ATTEINT (bug signalé par l'utilisateur, corrigé 2026-08-10) ────
    // `afterVerseRestart` (juste au-dessus) ramène volontairement au verset
    // PRÉCÉDENT après une erreur, pour que le joueur reparte avec un peu
    // d'élan avant de rattaquer le passage qui a fait échouer -- cf. sa doc.
    // Mais retaper ces mots déjà validés une première fois incrémentait
    // encore `totalWordsCompleted` : en bouclant volontairement sur un cycle
    // court (échouer au verset N+1, revenir à N, retaper N, re-échouer...),
    // le score grimpait indéfiniment sans jamais avancer réellement dans le
    // texte. `furthestGlobalWordIndex` retient l'index global (cf.
    // `MemorizationGameState.globalWordIndex`) du mot le plus loin jamais
    // validé dans LA PARTIE ; il n'est JAMAIS réinitialisé par
    // `afterVerseRestart`. Un mot qui ne dépasse pas strictement ce point
    // avance quand même normalement (même feedback de succès, expérience de
    // jeu inchangée) mais n'ajoute rien au score.
    final wordGlobalIndex =
        state.globalWordIndex(state.currentVerseIndex, state.currentWordIndex);
    final isNewProgress = wordGlobalIndex > state.furthestGlobalWordIndex;
    final total = isNewProgress
        ? state.totalWordsCompleted + 1
        : state.totalWordsCompleted;
    final furthest =
        isNewProgress ? wordGlobalIndex : state.furthestGlobalWordIndex;
    // Le record ne peut être battu que par une progression réelle : si le
    // score ne bouge pas, la portion n'a de toute façon rien de neuf à
    // signaler, pas la peine de la résoudre. Record PAR PORTION (2026-08-12),
    // cf. `_reportPortionProgress` -- ASYNCHRONE, capturer le verset ICI
    // (avant tout changement de `currentVerseIndex` ci-dessous).
    if (isNewProgress) {
      unawaited(_reportPortionProgress(state.currentVerse.verse));
    }

    if (!state.isLastWordOfVerse) {
      state = state.copyWith(
        currentWordIndex: state.currentWordIndex + 1,
        totalWordsCompleted: total,
        furthestGlobalWordIndex: furthest,
      );
      _prepareChoicesIfNeeded();
      return;
    }
    if (!state.isLastVerse) {
      state = state.copyWith(
        currentVerseIndex: state.currentVerseIndex + 1,
        currentWordIndex: 0,
        totalWordsCompleted: total,
        furthestGlobalWordIndex: furthest,
      );
      _prepareChoicesIfNeeded();
      return;
    }
    // Dernier mot du dernier verset CHARGÉ : la partie ne s'arrête pas ici
    // (cf. commentaire de la classe) -- va chercher la page suivante.
    state = state.copyWith(
        totalWordsCompleted: total, furthestGlobalWordIndex: furthest);
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
