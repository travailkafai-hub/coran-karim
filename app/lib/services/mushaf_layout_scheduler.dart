import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';

class MushafLayoutCancelled implements Exception {
  const MushafLayoutCancelled();
}

/// ChGPT: at most one paragraph measurement after each frame, across all pages.
/// TextPainter stays on the UI isolate; a Future alone would not prevent jank.
///
/// ── LE PREFETCH NE DOIT PAS REDEMANDER DE FRAMES (2026-09-15) ──────────────
///
/// Defaut mesure sur telephone (ANR « Coran Karim DEV ne repond pas », journal
/// du 15/09 07:16-07:18). Pendant que l'utilisateur ecoutait la lecture
/// continue, `[Fluidite]` donnait 90 a 100 % de frames ratees avec une
/// construction a 15-50 ms pour un budget de 8,3 ms, et l'instrumentation de
/// cet ordonnanceur montrait quatre pages mesurees coup sur coup :
///
///     page=77 calcul=230ms trancheMax=23,4ms premierPlan=true
///     page=76 calcul=156ms trancheMax=11,5ms premierPlan=false
///     page=78 calcul=172ms trancheMax=13,5ms premierPlan=false
///     page=79 calcul=124ms trancheMax=6,4ms  premierPlan=false
///
/// DEUX CHOSES QUE CES CHIFFRES ETABLISSENT :
///
/// 1. « Une mesure par frame » ne borne PAS le cout d'une frame. La garantie
///    porte sur le NOMBRE de paragraphes, pas sur leur DUREE : un seul
///    paragraphe a coute 23,4 ms, soit presque trois budgets de frame. On ne
///    peut pas decouper un `TextPainter.layout` en morceaux -- la seule
///    variable sur laquelle on a prise est QUAND on accepte de le payer.
///
/// 2. Trois des quatre pages n'etaient PAS a l'ecran (`premierPlan=false`).
///    `ensureVisualUpdate()` etait appele apres chaque mesure, y compris pour
///    celles-la : l'ordonnanceur REDEMANDAIT donc des frames en continu pour
///    pre-mesurer des pages que personne ne regardait, pendant que l'ecran
///    reellement affiche n'arrivait deja plus a tenir sa cadence.
///
/// CE QUI CHANGE. Le travail de PREMIER PLAN garde exactement son
/// comportement : il bloque le premier affichage de la page, il a le droit de
/// reclamer des frames jusqu'a finir. Le PREFETCH, lui, ne reclame plus rien :
/// il se contente des frames qui se produisent de toute facon, et il passe son
/// tour sur une frame deja en retard. Une page pre-mesuree en avance est un
/// confort ; la page qu'on regarde est le produit.
///
/// ⚠️ CE QUI N'EST PAS PROUVE : le blocage observe durait plus de deux minutes,
/// alors que ces quatre mesures ne couvrent que 19 secondes, et la gigue avait
/// commence AVANT elles. Ce correctif retire une cause etablie, il ne demontre
/// pas qu'elle etait la seule. A remesurer sur device par `[Fluidite]`.
class MushafLayoutScheduler {
  MushafLayoutScheduler._();
  static final instance = MushafLayoutScheduler._();

  final _pending = Queue<_Measurement>();
  bool _scheduled = false;

  /// Au-dela de cette duree, la frame qui vient de s'ecouler etait deja en
  /// retard : le prefetch passe son tour. 8,3 ms est le budget d'un ecran a
  /// 120 Hz (celui du telephone de recette) -- on garde un peu de marge pour
  /// ne pas suspendre le prefetch sur une frame simplement pleine.
  static const _frameEnRetard = Duration(milliseconds: 12);

  Duration? _debutFramePrecedente;

  Future<double> measure(
    double Function() calculate, {
    required bool Function() isCurrent,
    required bool Function() isForeground,
  }) {
    final work = _Measurement(calculate, isCurrent, isForeground);
    _pending.add(work);
    _schedule();
    return work.result.future;
  }

  void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((horodatage) {
      _scheduled = false;
      // Remove obsolete work before choosing a visible page over prefetch.
      for (final work in _pending.toList()) {
        if (!work.isCurrent()) {
          _pending.remove(work);
          work.result.completeError(const MushafLayoutCancelled());
        }
      }
      if (_pending.isEmpty) {
        _debutFramePrecedente = null;
        return;
      }
      final work = _pending.firstWhere(
        (entry) => entry.isForeground(),
        orElse: () => _pending.first,
      );
      // ── LE PREFETCH CEDE LE PAS A UNE FRAME EN RETARD (2026-09-15) ───────
      //
      // `horodatage` est l'instant de debut de la frame qui vient d'etre
      // construite : l'ecart avec celui de la frame precedente donne sa duree
      // reelle. Si elle a deja depasse le budget, ajouter une mesure de
      // paragraphe (jusqu'a 23 ms, cf. l'en-tete) ne ferait qu'aggraver le
      // retard -- et pour une page que personne ne regarde. On repasse donc la
      // main sans perdre le travail : il reste en file pour une frame calme.
      //
      // Le premier plan, lui, ne cede JAMAIS : cette mesure-la est ce qui
      // empeche la page affichee d'apparaitre, la retarder ne servirait
      // personne.
      final precedente = _debutFramePrecedente;
      _debutFramePrecedente = horodatage;
      final enRetard =
          precedente != null && horodatage - precedente > _frameEnRetard;
      if (enRetard && !work.isForeground()) {
        // Ne pas rearmer par `ensureVisualUpdate` : on attend une frame que
        // l'application produira d'elle-meme.
        _scheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((h) {
          _scheduled = false;
          _debutFramePrecedente = h;
          _schedule();
        });
        return;
      }
      _pending.remove(work);
      try {
        work.result.complete(work.calculate());
      } catch (error, stack) {
        work.result.completeError(error, stack);
      }
      _schedule();
    });
    // Unlike scheduleFrame during postFrameCallbacks, this also guarantees
    // a following frame after the current frame's scheduling flag is reset.
    //
    // ⚠️ SEULEMENT POUR LE PREMIER PLAN (2026-09-15). Reclamer une frame pour
    // du prefetch, c'est faire tourner l'ecran a plein regime pour mesurer des
    // pages que personne ne regarde -- mesure au journal : trois pages sur
    // quatre en `premierPlan=false` pendant que l'ecran affiche ratait 100 %
    // de ses frames. Sans cet appel le prefetch avance quand meme : il
    // s'accroche aux frames que l'application produit par ailleurs.
    if (_pending.any((entry) => entry.isForeground())) {
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }
}

class _Measurement {
  final double Function() calculate;
  final bool Function() isCurrent;
  final bool Function() isForeground;
  final result = Completer<double>();
  _Measurement(this.calculate, this.isCurrent, this.isForeground);
}
