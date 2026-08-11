import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';

import 'diagnostic_log.dart';
import 'recitation_verifier.dart';

/// Relâche le micro quand on QUITTE la récitation — quel que soit l'écran.
///
/// ── POURQUOI CE GARDE EXISTE (2026-08-10) ────────────────────────────────
///
/// « le micro reste actif hors récitation » a été corrigé TROIS fois, et il est
/// revenu à chaque fois : `4a09848` (le `dispose()` de l'écran n'appelait ni
/// `stopContinuous()` ni `verifier.stop()`), `aa67adf`, puis `05240c2` (une
/// exception dans la clôture d'archive sautait la libération -> try/catch).
///
/// La cause n'était pas dans ces correctifs, elle était dans leur EMPLACEMENT.
/// Trois écrans démarrent une récitation :
///   - `karaoke_recitation_screen`  -> `startControle()` / `startTest()`
///   - `prayer_follow_screen`       -> `startPrayerFollow()`
///   - `recitation_screen`          -> `startControle()`
/// Un seul relâchait le micro. Le deuxième ne fait que `_scrollController
/// .dispose()`, le troisième n'a **aucun** `dispose()`. Chaque correctif a
/// durci le seul écran par lequel on avait constaté le défaut, pendant que les
/// deux autres restaient ouverts.
///
/// Recopier le bloc dans deux `dispose()` de plus aurait été le 4ᵉ et le 5ᵉ
/// point d'appel, et le prochain écran aurait rouvert le trou — c'est
/// exactement ce qui s'est produit trois fois.
///
/// Le filet du notifier ne joue pas ce rôle non plus : `recitationProvider`
/// est déclaré `autoDispose` puis appelle `ref.keepAlive()` (pour une raison
/// légitime et mesurée, cf. son commentaire du 2026-07-10) — son `dispose()`,
/// qui contient pourtant la bonne logique, ne s'exécute donc jamais.
///
/// ── CE QUE CE GARDE GARANTIT ─────────────────────────────────────────────
///
/// La question est posée à celui qui TIENT réellement la ressource : le
/// vérificateur (`recitationVerifierProvider`, non autoDispose, il survit aux
/// écrans). Aucun écran n'a rien à se rappeler de faire.
///
/// Deux déclencheurs, aucun ne dépend d'un écran :
///
///  1. **On quitte l'écran depuis lequel on récitait.** Le garde retient, pour
///     chaque écran empilé, si une capture tournait DÉJÀ au moment où il a été
///     poussé. Au retour arrière :
///       - l'écran avait été ouvert PENDANT la récitation (une sous-page) ->
///         le quitter, c'est REVENIR à la récitation : on ne touche à rien ;
///       - sinon -> c'est l'écran qui portait la récitation : on relâche.
///
///     ── POURQUOI PAS UNE PROFONDEUR DE PILE (défaut de ma 1re version,
///     trouvé en revue le 2026-08-10 avant toute mise sur device) ────────────
///     J'avais d'abord comparé la profondeur courante à celle relevée « au
///     démarrage de la capture ». Mais un observateur de navigation ne voit
///     que des navigations : si l'utilisateur ouvre l'écran, récite, puis
///     sort — le cas RÉEL, celui qui a été signalé — le premier événement
///     observé pendant la capture EST le `pop` de sortie, profondeur déjà
///     décrémentée. Le garde enregistrait alors une référence au lieu de
///     relâcher : il aurait échoué précisément sur le scénario à corriger.
///     Une profondeur ne distingue de toute façon pas « je reviens vers la
///     récitation » de « je la quitte » : dans les deux cas elle diminue.
///     La provenance de la route, elle, le distingue sans ambiguïté.
///
///  2. **L'application passe en arrière-plan.** Il n'existait aucun
///     `WidgetsBindingObserver` dans toute l'app (vérifié : zéro occurrence) :
///     un appui sur Accueil pendant une récitation laissait le micro détenu
///     indéfiniment, sans même un écran pour le rattraper. C'était le pire des
///     chemins, et le seul qu'aucun `dispose()` ne pouvait couvrir.
///
/// ── CE QU'IL NE FAIT PAS, DÉLIBÉRÉMENT ───────────────────────────────────
///
///  • **Il ne touche pas à la PAUSE** (décision utilisateur 2026-08-10). Une
///    pause garde le micro : le relâcher imposerait un `start()` à la reprise,
///    et le projet a mesuré le 2026-07-25 qu'un cycle micro mal mené fait que
///    le flux PCM **ne revient jamais** (« dernier bloc à 17:23:50.473, plus
///    rien après la reprise »). Sur cet appareil `pause()` a par ailleurs été
///    chronométré à 6,4 s, jusqu'à 24 s.
///
///  • **Il ignore les routes qui ne sont pas des écrans.** Les feuilles
///    modales (aide tajwid, réglages de lecture) et les dialogues sont des
///    `PopupRoute` : les compter ferait couper le micro en fermant une simple
///    feuille, en pleine récitation.
class GardeMicro extends NavigatorObserver with WidgetsBindingObserver {
  GardeMicro(this._verifier) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Résolu à la demande plutôt que capturé : le vérificateur est un provider,
  /// et ce garde est construit avant que le premier écran ne l'ait lu.
  final RecitationVerifier Function() _verifier;

  /// Écrans ouverts ALORS QU'une capture tournait déjà — donc des sous-pages
  /// de la récitation, pas l'écran qui la porte. `Expando` plutôt qu'un `Set` :
  /// aucune référence forte retenue sur une route, donc aucune fuite si une
  /// route disparaît sans passer par `didPop` (remplacement, `pushAndRemoveUntil`).
  final _ouvertPendantRecitation = Expando<bool>('ouvertPendantRecitation');

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  // ── Navigation ──────────────────────────────────────────────────────────

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Seuls les ÉCRANS comptent : une feuille modale (aide tajwid, réglages de
    // lecture) ou un dialogue est une `PopupRoute`, et la fermer ne veut pas
    // dire qu'on quitte la récitation.
    if (route is PageRoute && _captureEnCours()) {
      _ouvertPendantRecitation[route] = true;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _quitte(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _quitte(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _quitte(oldRoute);
    if (newRoute is PageRoute && _captureEnCours()) {
      _ouvertPendantRecitation[newRoute] = true;
    }
  }

  /// Un écran vient d'être retiré de la pile.
  void _quitte(Route<dynamic> route) {
    if (route is! PageRoute) return;
    if (!_captureEnCours()) return;
    if (_ouvertPendantRecitation[route] == true) {
      // Sous-page ouverte pendant la récitation : la quitter, c'est y REVENIR.
      _ouvertPendantRecitation[route] = null;
      return;
    }
    // Cet écran existait avant la capture : c'est lui qui la portait.
    _relacher('sortie de l\'ecran de recitation');
  }

  bool _captureEnCours() {
    try {
      return _verifier().captureEnCours;
    } catch (_) {
      // Vérificateur pas encore construit (navigation d'amorçage) : rien à
      // garder, et surtout rien qui doive faire échouer une navigation.
      return false;
    }
  }

  // ── Cycle de vie de l'application ───────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` est VOLONTAIREMENT absent : il survient sur des événements
    // passagers (volet de notifications tiré, appel entrant qui s'affiche).
    // Y couper le micro le couperait en pleine récitation, pour un geste que
    // l'utilisateur n'a pas fait dans l'app.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_captureEnCours()) _relacher('application en arriere-plan ($state)');
    }
  }

  // ── Libération ──────────────────────────────────────────────────────────

  void _relacher(String motif) {
    DiagnosticLog.log('GardeMicro', 'relache le micro : $motif');
    // Fire-and-forget : ni une navigation ni un passage en arrière-plan ne
    // doivent attendre le matériel (appels plateforme mesurés jusqu'à 24 s sur
    // cet appareil). L'échec est journalisé, jamais propagé : ce garde est un
    // filet, il ne doit jamais devenir lui-même une cause de panne.
    unawaited(() async {
      try {
        await _verifier().stop();
        DiagnosticLog.log('GardeMicro', 'micro relache');
      } catch (e) {
        DiagnosticLog.log('GardeMicro', 'stop() a echoue : $e');
      }
    }());
  }
}
