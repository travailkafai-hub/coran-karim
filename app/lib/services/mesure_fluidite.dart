// Mesure de fluidite REELLE de l'interface, ecrite dans le journal de l'app.
//
// ── POURQUOI CE FICHIER EXISTE (2026-09-13) ──────────────────────────────────
//
// Demande utilisateur : « j'ai un serieux probleme de performance sur ce tel,
// audite » -- puis « audite bien la performance ». L'audit a bute sur une
// absence d'instrument, et sur une ERREUR DE METHODE qu'il faut consigner ici
// pour qu'elle ne soit pas refaite :
//
//   ⛔ `adb shell dumpsys gfxinfo <paquet>` NE MESURE PAS une application
//      Flutter. gfxinfo rapporte les frames de HWUI, le moteur de rendu des
//      vues Android ; Flutter, lui, dessine dans sa propre surface via
//      Impeller/Vulkan et ne passe pas par HWUI. Sur cette app, gfxinfo
//      annoncait « Total frames rendered: 5 », puis « 0 » apres une serie de
//      swipes -- c'est-a-dire le decor Android, pas l'interface. Les
//      percentiles spectaculaires qu'il affichait (50e = 300 ms, 90e = 1250 ms)
//      portaient donc sur une poignee de frames qui ne sont PAS celles de
//      l'application. En tirer « le cout est sur le thread UI » etait une
//      conclusion construite sur un instrument hors sujet.
//
// L'instrument correct est `SchedulerBinding.addTimingsCallback`, fourni par
// Flutter lui-meme : il rend, pour CHAQUE frame reellement produite, le temps
// de construction du widget tree (`buildDuration`, thread UI/Dart) et le temps
// de rasterisation (`rasterDuration`, thread GPU). C'est ce que fait DevTools,
// mais ici sans PC branche ni `flutter run` -- donc utilisable sur le telephone
// de n'importe qui, ce qu'exige la regle projet « ton travail doit etre
// fonctionnel sur n'importe quel telephone ».
//
// ── CE QU'IL COUTE ───────────────────────────────────────────────────────────
//
// Le rappel n'accumule que deux entiers par frame dans une liste bornee, et
// n'ecrit dans le journal qu'une ligne tous les [_kFramesParRapport]. Aucune
// allocation par frame en dehors de l'ajout a la liste. Il est de plus
// entierement inactif quand le diagnostic est coupe (`DiagnosticLog.enabled`,
// donc eteint par defaut en release) -- un instrument qui modifie ce qu'il
// mesure n'est pas un instrument, cf. la meme precaution deja prise pour la
// journalisation elle-meme dans `diagnostic_log.dart`.

import 'package:flutter/scheduler.dart';

import 'diagnostic_log.dart';

/// Nombre de frames agregees avant d'ecrire une ligne de rapport.
///
/// 240 frames ~= 4 s a 60 Hz, ~2 s a 120 Hz. Assez pour que les percentiles
/// veuillent dire quelque chose, assez court pour qu'un a-coup ressenti pendant
/// un defilement se retrouve dans le rapport suivant et non noye dans dix
/// minutes d'usage.
const int _kFramesParRapport = 240;

/// Délai au bout duquel on rapporte même sans avoir atteint
/// [_kFramesParRapport], à partir d'au moins [_kFramesMinimum] frames.
///
/// ⚠️ AJOUTÉ APRÈS UN PREMIER ESSAI QUI N'A RIEN RAPPORTÉ (2026-09-13), et
/// c'est le contraire d'un détail : avec le seul seuil de 240 frames, tourner
/// 7 pages de Mushaf n'a produit AUCUNE ligne. Cause : Flutter ne dessine que
/// lorsque quelque chose change — une page de Mushaf affichée est parfaitement
/// statique et produit **zéro frame**. L'instrument ne se déclenchait donc que
/// sous animation soutenue, c'est-à-dire précisément PAS dans le cas qu'on
/// cherchait à mesurer (« je suis sur le mushaf papier, juste une page »).
///
/// Un instrument qui ne parle que quand tout bouge est aveugle au symptôme le
/// plus courant : l'à-coup isolé au moment où l'on tourne la page.
const Duration _kDelaiMaxRapport = Duration(seconds: 8);

/// En dessous, les percentiles ne veulent rien dire — on continue d'accumuler.
const int _kFramesMinimum = 20;

/// Seuils de qualification d'une frame, en microsecondes.
///
/// ⚠️ 16,7 ms est le budget d'un ecran 60 Hz. Le Redmi Note 9 Pro affiche en
/// 60 Hz mais beaucoup de telephones sont en 90 ou 120 Hz, ou changent de
/// frequence en cours de route. Le budget REEL est donc lu sur l'appareil (cf.
/// [_budgetMicrosecondes]) plutot que code en dur -- une frame de 15 ms est
/// confortable a 60 Hz et ratee a 120 Hz, et un seuil fixe donnerait un
/// verdict faux sur la moitie du parc.
int _budgetMicrosecondes() {
  final hz = SchedulerBinding.instance.platformDispatcher.views.isEmpty
      ? 60.0
      : SchedulerBinding
              .instance.platformDispatcher.views.first.display.refreshRate;
  // Garde-fou : certaines plateformes rendent 0 ou une valeur absurde.
  final valide = (hz.isFinite && hz >= 24 && hz <= 480) ? hz : 60.0;
  return (1000000 / valide).round();
}

final List<int> _construction = <int>[]; // buildDuration, thread UI (Dart)
final List<int> _rasterisation = <int>[]; // rasterDuration, thread GPU
bool _branche = false;

/// Depuis quand la tranche courante accumule. Remis à zéro à chaque rapport.
final Stopwatch _depuisRapport = Stopwatch();

/// Pire frame de la tranche, avec le moment où elle est survenue.
///
/// Les percentiles lissent : sur 240 frames, une seule frame à 900 ms se range
/// dans le p99 et peut passer inaperçue. Or c'est EXACTEMENT ce qu'un
/// utilisateur ressent quand il tourne une page — un à-coup unique, pas une
/// dégradation moyenne. Le maximum est donc rapporté à part.
int _pireSpan = 0;

int _p(List<int> tries, int centile) {
  if (tries.isEmpty) return 0;
  final i = ((tries.length - 1) * centile / 100).round();
  return tries[i];
}

/// Branche la mesure. Idempotent : un second appel ne double pas le rappel
/// (piege classique -- un rappel enregistre deux fois compte chaque frame deux
/// fois, et les percentiles restent justes pendant que le compte de frames
/// ment).
void demarrerMesureFluidite() {
  if (_branche) return;
  if (!DiagnosticLog.enabled) return;
  _branche = true;
  _depuisRapport.start();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final c = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      _construction.add(c);
      _rasterisation.add(r);
      if (c + r > _pireSpan) _pireSpan = c + r;
    }
    final assezDeFrames = _construction.length >= _kFramesParRapport;
    final assezDeTemps = _depuisRapport.elapsed >= _kDelaiMaxRapport &&
        _construction.length >= _kFramesMinimum;
    if (!assezDeFrames && !assezDeTemps) return;

    final budget = _budgetMicrosecondes();
    final total = _construction.length;
    var ratees = 0;
    var graves = 0;
    for (var i = 0; i < total; i++) {
      final span = _construction[i] + _rasterisation[i];
      if (span > budget) ratees++;
      if (span > budget * 2) graves++;
    }
    _construction.sort();
    _rasterisation.sort();

    String ms(int micro) => (micro / 1000).toStringAsFixed(1);
    DiagnosticLog.log(
        'Fluidite',
        'frames=$total budget=${ms(budget)}ms '
            'ratees=$ratees (${(100 * ratees / total).toStringAsFixed(1)}%) '
            'graves=$graves PIRE=${ms(_pireSpan)}ms | '
            'construction p50=${ms(_p(_construction, 50))} '
            'p90=${ms(_p(_construction, 90))} '
            'p99=${ms(_p(_construction, 99))} | '
            'rasterisation p50=${ms(_p(_rasterisation, 50))} '
            'p90=${ms(_p(_rasterisation, 90))} '
            'p99=${ms(_p(_rasterisation, 99))}');

    // Vider APRES le rapport, pas avant : un rapport se lit comme une tranche
    // fermee de N frames, jamais comme une moyenne glissante depuis le
    // demarrage -- sinon un a-coup du lancement resterait dans le p99 pendant
    // toute la session et on chercherait un defaut la ou il n'y en a plus.
    _construction.clear();
    _rasterisation.clear();
  });
  DiagnosticLog.log('Fluidite',
      'mesure branchee (rapport toutes les $_kFramesParRapport frames)');
}
