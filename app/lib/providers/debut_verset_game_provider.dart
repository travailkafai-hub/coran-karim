import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import 'memorization_game_provider.dart' show GameVerse;

/// Jeu « Début de verset » (demande utilisateur 2026-08-28) : à l'ouverture
/// du jeu d'enchaînement, un style alternatif -- au lieu d'avancer mot par
/// mot dans l'ordre du texte, il pioche des versets AU HASARD dans la même
/// portion/sourate et ne teste QUE leurs deux premiers mots, en QCM à 4
/// propositions. Objectif différent de l'enchaînement (qui construit la
/// suite d'un verset à l'autre) : ancrer LE NUMÉRO de chaque verset à SON
/// début, l'endroit précisément documenté comme le plus sujet à l'oubli
/// (cf. `pontVersetPrecedent` dans memorization_game_provider.dart).

/// Bascule affichée à l'ouverture de l'écran. `autoDispose` : un choix
/// d'écran, pas un réglage à retenir d'une partie à l'autre -- rouvrir le
/// jeu propose toujours l'enchaînement par défaut.
final debutVersetModeProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Une question : le verset à retrouver + ses propositions mélangées (une
/// vraie, les autres prises sur d'autres versets de la même portion).
class DebutVersetQuestion {
  final GameVerse verset;
  final String reponseCorrecte;
  final List<String> propositions;
  const DebutVersetQuestion({
    required this.verset,
    required this.reponseCorrecte,
    required this.propositions,
  });
}

class DebutVersetGameState {
  final List<GameVerse> pool;
  final DebutVersetQuestion? question;
  final int score;
  final int streak;
  final int meilleurStreak;
  /// Réponse correcte à montrer après une erreur -- `null` hors de cette
  /// révélation (même convention que `MemorizationGameState.revealedAnswer`).
  final String? revele;
  final bool wrongFlash;

  const DebutVersetGameState({
    required this.pool,
    this.question,
    this.score = 0,
    this.streak = 0,
    this.meilleurStreak = 0,
    this.revele,
    this.wrongFlash = false,
  });

  DebutVersetGameState copyWith({
    DebutVersetQuestion? question,
    int? score,
    int? streak,
    int? meilleurStreak,
    String? revele,
    bool? wrongFlash,
  }) =>
      DebutVersetGameState(
        pool: pool,
        question: question ?? this.question,
        score: score ?? this.score,
        streak: streak ?? this.streak,
        meilleurStreak: meilleurStreak ?? this.meilleurStreak,
        // Pas `?? this.revele` : une révélation ne vaut que pour l'ERREUR qui
        // vient de se produire, jamais reportée sur la question suivante.
        revele: revele,
        wrongFlash: wrongFlash ?? false,
      );
}

/// Paramétré par la liste de versets de la portion/sourate déjà ouverte --
/// même pool que le jeu d'enchaînement, pour rester dans ce qu'on est en
/// train de mémoriser plutôt que de piocher n'importe où dans le Coran.
final debutVersetGameProvider = StateNotifierProvider.autoDispose
    .family<DebutVersetGameNotifier, DebutVersetGameState, List<Verse>>(
        (ref, verses) => DebutVersetGameNotifier(verses));

class DebutVersetGameNotifier extends StateNotifier<DebutVersetGameState> {
  final _rng = Random();

  /// Position dans `pool`, SÉQUENTIELLE (2026-08-28, retour utilisateur après
  /// un premier essai en tirage aléatoire -- « il faut commencer par le
  /// premier, les versets c'est 1 puis 2 puis 3 »). Le tirage au hasard ne
  /// concerne QUE les leurres/l'ordre des 4 propositions, jamais QUEL verset
  /// est interrogé : la portion se parcourt dans l'ordre du texte, comme
  /// l'enchaînement -- seule la mécanique de la question (2 mots, QCM au lieu
  /// d'avancer mot à mot) change.
  int _index = 0;

  // ── LES VERSETS À UN SEUL MOT NE DOIVENT PAS DISPARAÎTRE (2026-08-28) ───
  //
  // BUG CORRIGÉ, constat utilisateur : « ça commence pas verset 1 !! ». La
  // 1ʳᵉ version excluait tout verset de moins de 2 mots (`words.length >= 2`)
  // pour pouvoir toujours en extraire "les deux premiers" -- mais plusieurs
  // sourates commencent PRÉCISÉMENT par un verset d'un seul "mot" (les
  // lettres disjointes/muqatta'at : المٓ, كٓهيعٓصٓ, نٓ...), un seul token sans
  // espace dans le texte Uthmani. Le filtre les faisait sauter en silence --
  // Al-Baqara démarrait donc au verset 2, jamais au 1. Corrigé en gardant
  // TOUS les versets dans le pool ; `_debutDe` (plus bas) s'adapte au nombre
  // de mots réellement disponibles au lieu d'en exiger deux partout.
  DebutVersetGameNotifier(List<Verse> verses)
      : super(DebutVersetGameState(
          pool: [
            for (final v in verses)
              if (GameVerse.fromVerse(v).words.isNotEmpty) GameVerse.fromVerse(v),
          ],
        )) {
    _poserQuestion();
  }

  // Les deux premiers mots -- UN SEUL si le verset n'en a qu'un (muqatta'at,
  // cf. la doc du constructeur ci-dessus) plutôt qu'un RangeError.
  String _debutDe(GameVerse gv) =>
      gv.words.length >= 2 ? '${gv.words[0]} ${gv.words[1]}' : gv.words[0];

  /// Boucle à la fin de la portion (`% pool.length`) -- même esprit
  /// "illimité" que le jeu d'enchaînement plutôt qu'un arrêt sec.
  void _poserQuestion() {
    final pool = state.pool;
    if (pool.length < 2) return; // portion trop courte -- rien de jouable
    final index = _index % pool.length;
    final verset = pool[index];
    final correcte = _debutDe(verset);

    // Leurres : UNIQUEMENT des versets FUTURS (2026-08-28, demande
    // utilisateur : « les propositions doivent être des versets futurs pas
    // passé ») -- jamais un verset déjà interrogé dans cette passe. Au
    // TEXTE différent du bon (deux versets peuvent partager les deux mêmes
    // premiers mots, ex. une anaphore -- un leurre identique à la bonne
    // réponse rendrait la question insoluble, et deux leurres identiques
    // entre eux donneraient l'impression de "choix en double" --
    // `!leurres.contains(texte)` exclut les deux cas). Près de la fin de la
    // portion il peut y avoir moins de 3 versets futurs disponibles : la
    // boucle plus bas s'arrête alors avec moins de leurres plutôt que de
    // piocher dans le passé.
    final candidats = [
      for (var i = index + 1; i < pool.length; i++) pool[i],
    ]..shuffle(_rng);
    final leurres = <String>[];
    for (final c in candidats) {
      final texte = _debutDe(c);
      if (texte != correcte && !leurres.contains(texte)) leurres.add(texte);
      if (leurres.length == 3) break;
    }

    final propositions = [correcte, ...leurres]..shuffle(_rng);
    state = state.copyWith(
      question: DebutVersetQuestion(
        verset: verset,
        reponseCorrecte: correcte,
        propositions: propositions,
      ),
      revele: null,
    );
  }

  void repondre(String choix) {
    final q = state.question;
    if (q == null || state.revele != null) return; // question déjà tranchée
    if (choix == q.reponseCorrecte) {
      final streak = state.streak + 1;
      state = state.copyWith(
        score: state.score + 1,
        streak: streak,
        meilleurStreak: max(streak, state.meilleurStreak),
      );
      _index++;
      _poserQuestion();
    } else {
      // Même geste que le jeu d'enchaînement sur une erreur (cf.
      // `revealedAnswer`) : on montre la bonne réponse, l'écran enchaîne sur
      // une nouvelle question après un court délai -- jamais de pénalité qui
      // bloque, la série repart juste à zéro. Même délai que là-bas (2500 ms,
      // ajusté 2026-08-26 après un retour utilisateur « c'est rapide »).
      // `_index` NE CHANGE PAS : une erreur repose la MÊME question, comme
      // `afterVerseRestart` relance le même verset côté enchaînement.
      state = state.copyWith(wrongFlash: true, streak: 0, revele: q.reponseCorrecte);
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        _poserQuestion();
      });
    }
  }
}
