import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../services/quran_api.dart';
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

// ── CE JEU NE PARTAGE PLUS LA PORTION DE L'ENCHAÎNEMENT (2026-09-19) ──────
//
// Constat utilisateur : « pourquoi j'ai qu'un seul choix ? est-ce qu'il y a un
// lien entre début verset et enchaînement par mot ? [...] je ne veux pas avoir
// de lien, il se peut que la personne sache déjà la sourate et veuille
// s'entraîner directement sur l'enchaînement par verset [...] je comprends,
// comme le verset est grand il tient une page, d'où ça. Il faut dissocier. »
//
// LE DIAGNOSTIC ÉTAIT LE BON. Les deux modes recevaient la MÊME liste, celle
// que le Mushaf découpe : `pageNumber == page && ayahNumber >= versetActif`.
// Sur un verset long (Al-Māʾida 5:2 fait 52 mots et remplit presque une page),
// cette portion tombe à UN SEUL verset -- donc une seule proposition, et le
// QCM n'en est plus un.
//
// AMPLEUR MESURÉE sur les 604 pages : 29 % des points de départ donnent moins
// de 4 versets, et 10 % en donnent un seul. Ce n'était donc pas un cas limite.
//
// POURQUOI LA DISSOCIATION EST LA BONNE RÉPONSE, et pas un élargissement de la
// portion commune : les deux jeux n'ont pas le même objet. L'enchaînement
// travaille le TEXTE mot à mot, donc la page qu'on a sous les yeux est la
// bonne unité. Celui-ci travaille le NUMÉRO du verset et son début : son unité
// naturelle est la sourate entière, y compris pour quelqu'un qui la connaît
// déjà et veut réviser les enchaînements d'un bout à l'autre.
//
// ET ÇA NE COÛTE RIEN. Inquiétude de l'utilisateur (« t'es pas obligé de tout
// charger, il suffit de charger les deux premiers mots ») : `QuranApi` charge
// déjà le Coran ENTIER une fois au démarrage, hors thread UI -- mesuré dans
// son propre journal, `114 sourates, 604 pages` en 306 ms. `fetchVerses` ne
// fait que lire l'index en mémoire ; demander la sourate entière n'ajoute
// aucun accès asset, aucune latence.

/// De quoi jouer : ce qu'on INTERROGE, et ce qui ne sert qu'à remplir le QCM.
///
/// ── POURQUOI DEUX LISTES ET PAS UNE (2026-09-19) ─────────────────────────
///
/// Demande utilisateur : « je veux tout le temps avoir 4 propositions et que
/// ça s'enchaîne jusqu'à la fin de la sourate ».
///
/// La sourate suffit dans 110 cas sur 114. Les quatre autres ne peuvent pas
/// fournir quatre débuts DIFFÉRENTS :
///     103 Al-ʿAṣr, 108 Al-Kawthar, 110 An-Naṣr -- 3 versets ;
///     113 Al-Falaq -- 5 versets mais 3 débuts seulement, plusieurs
///     commencent par `وَمِن شَرِّ`.
///
/// Il faut donc des leurres venus d'ailleurs. Mais un verset étranger à la
/// sourate ne doit JAMAIS devenir une question : réviser Al-Kawthar en se
/// voyant demander un verset d'Al-Māʿūn n'a aucun sens. Les deux rôles sont
/// donc portés par deux champs distincts -- c'est toute la raison de cette
/// classe.
@immutable
class PoolDebutVerset {
  /// La sourate en cours : les seuls versets qu'on interroge.
  final List<Verse> versets;

  /// Débuts pris dans les sourates voisines, UNIQUEMENT pour compléter les
  /// propositions quand la sourate n'en fournit pas assez. Vide le reste du
  /// temps, c'est-à-dire presque toujours.
  final List<String> leurresEnPlus;

  /// Ce qui identifie ce pool. `==` ne regarde QUE ce numéro : une `List` se
  /// compare par identité, donc sans cela chaque reconstruction de l'écran
  /// fabriquerait un nouveau provider et remettrait la partie à zéro.
  final int sourate;

  const PoolDebutVerset({
    required this.sourate,
    required this.versets,
    this.leurresEnPlus = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is PoolDebutVerset && other.sourate == sourate;

  @override
  int get hashCode => sourate.hashCode;
}

/// Construit le pool d'une sourate, en allant chercher des leurres chez les
/// voisines si — et seulement si — elle ne porte pas quatre débuts distincts.
///
/// Ne coûte aucun accès asset : `QuranApi` a déjà tout le Coran en mémoire
/// (cf. le bloc en tête de fichier).
final versetsSourateProvider =
    FutureProvider.family<PoolDebutVerset, int>((ref, numeroSourate) async {
  final versets = await QuranApi.fetchVerses(numeroSourate);
  String debutDe(Verse v) {
    final mots = GameVerse.fromVerse(v).words;
    if (mots.isEmpty) return '';
    return mots.length >= 2 ? '${mots[0]} ${mots[1]}' : mots[0];
  }

  final propres = {for (final v in versets) debutDe(v)}..remove('');
  if (propres.length >= 4) {
    return PoolDebutVerset(sourate: numeroSourate, versets: versets);
  }
  // Voisines immédiates d'abord (même contexte de mémorisation : dans le juz
  // ʿamma, les sourates courtes se révisent ensemble), puis on s'éloigne.
  final extra = <String>[];
  for (var ecart = 1; ecart <= 5 && propres.length + extra.length < 4; ecart++) {
    for (final n in [numeroSourate - ecart, numeroSourate + ecart]) {
      if (n < 1 || n > 114) continue;
      for (final v in await QuranApi.fetchVerses(n)) {
        final d = debutDe(v);
        if (d.isEmpty || propres.contains(d) || extra.contains(d)) continue;
        extra.add(d);
        if (propres.length + extra.length >= 4) break;
      }
      if (propres.length + extra.length >= 4) break;
    }
  }
  return PoolDebutVerset(
      sourate: numeroSourate, versets: versets, leurresEnPlus: extra);
});

/// Paramétré par la liste de versets à interroger -- désormais la SOURATE
/// entière (cf. `versetsSourateProvider`), plus la portion de l'enchaînement.
final debutVersetGameProvider = StateNotifierProvider.autoDispose
    .family<DebutVersetGameNotifier, DebutVersetGameState, PoolDebutVerset>(
        (ref, pool) => DebutVersetGameNotifier(pool));

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
  /// Leurres venus des sourates voisines, jamais interroges (cf.
  /// `PoolDebutVerset`). Vide sauf sur les quatre sourates trop courtes.
  final List<String> _leurresEnPlus;

  DebutVersetGameNotifier(PoolDebutVerset pool)
      : _leurresEnPlus = pool.leurresEnPlus,
        super(DebutVersetGameState(
          pool: [
            for (final v in pool.versets)
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
    // ── TOUJOURS QUATRE PROPOSITIONS (2026-09-18) ─────────────────────────
    //
    // Demande utilisateur : « faut toujours proposer 4 choix ». Sur les
    // dernières questions d'une portion, il n'y a plus trois versets futurs
    // disponibles et l'écran tombait à trois cases, puis deux -- jusqu'à une
    // seule, qui donne la réponse sans rien demander.
    //
    // ⚠️ LA RÈGLE DU 28/08 TIENT TOUJOURS, elle passe juste en PREMIER CHOIX.
    // « les propositions doivent être des versets futurs pas passé » : la
    // boucle ci-dessus ne regarde que l'avant, et elle est servie d'abord. Le
    // passé n'est sollicité QUE pour compléter les cases manquantes, jamais
    // pour remplacer un verset futur disponible. Les deux demandes ne se
    // contredisent que sur la fin de portion, où il faut bien trancher : une
    // question à deux cases n'en est plus une.
    if (leurres.length < 3) {
      final passes = [
        for (var i = 0; i < index; i++) pool[i],
      ]..shuffle(_rng);
      for (final c in passes) {
        final texte = _debutDe(c);
        if (texte != correcte && !leurres.contains(texte)) leurres.add(texte);
        if (leurres.length == 3) break;
      }
    }
    // Dernier recours : les sourates voisines (cf. `PoolDebutVerset`). Sur
    // Al-Kawthar ou Al-Falaq, la sourate entiere ne porte pas quatre debuts
    // differents -- sans cela le QCM tomberait a trois cases, puis a deux.
    if (leurres.length < 3 && _leurresEnPlus.isNotEmpty) {
      final secours = [..._leurresEnPlus]..shuffle(_rng);
      for (final texte in secours) {
        if (texte != correcte && !leurres.contains(texte)) leurres.add(texte);
        if (leurres.length == 3) break;
      }
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
