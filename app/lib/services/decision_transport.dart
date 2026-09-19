// Ce que fait le bouton Lire/Pause, isolé de l'écran pour être TESTABLE.
//
// ── POURQUOI CETTE FONCTION EXISTE (2026-09-18) ───────────────────────────
//
// Ce bouton en est à sa CINQUIÈME version. Quatre correctifs successifs, tous
// justes pris un par un, et pourtant le symptôme du 2026-08-13 est revenu tel
// quel le 2026-09-18 : « audio tourne, je clique sur pause, parfois ça marche,
// parfois mon clic sur pause relance l'audio depuis là où un verset est
// sélectionné ».
//
// | date | plainte utilisateur | correctif |
// |---|---|---|
// | 08-01 | « je fais pause, il recommence » | transport SEULEMENT si verset actif == verset chargé |
// | 08-01 | « je change de sourate, je fais play, ça reste sur la première » | (la même comparaison le préserve) |
// | 08-13 | « je clique sur pause, la lecture se refait ; au 2e clic il y a la pause » | discriminant = le PASSAGE affiché, plus le verset |
// | 08-16 | « pause, je sélectionne un autre verset, au play ça doit prendre la nouvelle sélection » | retour à la comparaison verset-à-verset |
//
// Le correctif du 16 a ANNULÉ celui du 13, et le symptôme est réapparu.
//
// LA CAUSE N'EST PAS UNE ERREUR DE CONDITION, C'EST QU'IL Y EN A DEUX.
// Un seul booléen (`chargeEstLeSelectionne`) servait à trancher DEUX questions
// qui n'ont pas la même réponse :
//
//   1. « ce tap est-il une commande de TRANSPORT, ou un LANCEMENT ? »
//      -> dépend du PASSAGE : ce qui joue est-il sur l'écran que je regarde ?
//   2. « la reprise CONTINUE-t-elle, ou repart-elle d'une autre sélection ? »
//      -> dépend du VERSET sélectionné.
//
// Fusionnées, elles ne peuvent satisfaire qu'un scénario à la fois : le 13 a
// choisi le passage, le 16 est revenu au verset, chacun a cassé l'autre. Elles
// sont donc séparées ici, chacune sur SA branche.
//
// LE MÉCANISME QUI DÉCLENCHE LE BUG, et qu'aucune des deux versions ne voyait :
// la lecture ENCHAÎNE toute seule d'un verset au suivant (`PlayerNotifier.next`)
// alors que `_activeVerse` reste là où l'utilisateur l'avait posé. Dès le
// premier enchaînement les deux divergent — et c'est pour ça que « parfois ça
// marche » : tant que la lecture n'a pas dépassé le verset sélectionné, les
// deux coïncident encore.
//
// ⚠️ NE PAS refusionner ces conditions pour « simplifier ». La fonction est
// pure et couverte par `test/decision_transport_test.dart`, qui porte UN test
// par plainte ci-dessus, nommé par sa date. Un cinquième correctif qui casse
// un ancien scénario fera échouer son test au lieu de revenir chez
// l'utilisateur trois semaines plus tard.

/// Ce que le tap sur le bouton Lire/Pause doit déclencher.
enum ActionTransport {
  /// Mettre en pause ce qui joue.
  pause,

  /// Reprendre là où on s'était arrêté.
  reprise,

  /// (Re)lancer la lecture depuis le verset actuellement sélectionné.
  lectureNeuve,
}

/// Décide de l'action, sans connaître ni l'écran ni le lecteur.
///
/// - [afficheCeQuiJoue] : le verset chargé dans le lecteur fait-il partie du
///   passage affiché par CET écran ? C'est ce qui distingue « je commande le
///   transport de ce que j'écoute » de « une autre sourate joue ailleurs, je
///   lance celle-ci » (plainte du 08-01).
/// - [selectionEstLeVersetCharge] : le verset sélectionné est-il exactement
///   celui qui est chargé ? C'est ce qui distingue une reprise d'un
///   changement de cible (plainte du 08-16).
/// - [enLecture] / [enPause] : l'état du lecteur global.
ActionTransport decisionTransport({
  required bool afficheCeQuiJoue,
  required bool selectionEstLeVersetCharge,
  required bool enLecture,
  required bool enPause,
}) {
  // CE QUE LE BOUTON MONTRE, LE BOUTON DOIT LE FAIRE (règle posée le 08-13).
  // L'icône vaut `pause` dès que le lecteur joue : un tap doit alors mettre en
  // pause, sans demander QUEL verset est sélectionné — c'est précisément cette
  // exigence supplémentaire qui relançait la lecture au premier enchaînement.
  if (enLecture && afficheCeQuiJoue) return ActionTransport.pause;

  // En pause, la question change : reprendre le morceau interrompu n'a de sens
  // que si l'utilisateur n'a pas désigné autre chose entre-temps.
  if (enPause && selectionEstLeVersetCharge) return ActionTransport.reprise;

  // Tout le reste est un lancement : autre passage, autre sélection, ou rien
  // de chargé.
  return ActionTransport.lectureNeuve;
}
