import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// flutter_gemma / flutter_gemma_litertlm retirés le 2026-08-10, cf. l'appel
// supprimé dans main() plus bas.
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_settings_provider.dart';
import 'providers/coach_notification_provider.dart';
import 'providers/prayer_settings_provider.dart';
import 'providers/recitation_provider.dart' show recitationVerifierProvider;
import 'services/garde_micro.dart';
import 'screens/recette_screen.dart';
import 'screens/surah_list_screen.dart';
import 'screens/duas_screen.dart';
import 'screens/coach_hub_screen.dart';
import 'screens/coach_sessions.dart'
    show
        sessionsArchiveProvider,
        tailleArchiveProvider,
        portionsProvider,
        derniersJoursProvider,
        serieProvider;
import 'screens/dua_pour_nous_screen.dart';
import 'screens/mushaf_opening_screen.dart';
import 'screens/mushaf_screen.dart';
import 'services/quran_api.dart';
import 'screens/onboarding_screen.dart';
import 'screens/preparation_screen.dart';
import 'screens/settings_screen.dart';
import 'services/diagnostic_log.dart';
import 'services/mesure_fluidite.dart';
import 'data/guides_catalogue.dart';
import 'widgets/guide_interactif.dart';
import 'widgets/mushaf_cover_reveal.dart';
import 'services/session_media.dart';
import 'services/reciter_download_service.dart';
import 'theme/app_theme.dart';
import 'package:upgrader/upgrader.dart';

import 'services/fastconformer_verifier.dart';

/// Chronomètre une étape de démarrage sans changer son comportement : rend le
/// même futur, et range sa durée dans [mesures] quand il se termine.
///
/// Exister pour une raison précise (2026-09-13) : l'audit de démarrage a buté
/// sur le fait qu'on ne savait PAS quelle étape coûtait quoi. `am start -W`
/// donne 3861 ms de bout en bout et `onCreate` 903 ms, mais entre les deux
/// personne ne pouvait dire si le temps partait dans le journal, dans la
/// résolution du dossier audio ou dans la session média — on ne pouvait que
/// supposer. Trois compteurs coûtent trois `Stopwatch` et suppriment la
/// supposition : à chaque lancement, le journal porte désormais la répartition.
Future<T> _etape<T>(
  String nom,
  Map<String, int> mesures,
  Future<T> Function() action,
) {
  final t = Stopwatch()..start();
  return action().whenComplete(() {
    t.stop();
    mesures[nom] = t.elapsedMilliseconds;
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const _DemarrageApp());
}

// ChGPT: only the cover mounts before initialization, never audio providers.
class _DemarrageApp extends StatefulWidget {
  const _DemarrageApp();

  @override
  State<_DemarrageApp> createState() => _DemarrageAppState();
}

class _DemarrageAppState extends State<_DemarrageApp> {
  late Future<void> _initialisation = _initialiserServices();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialisation,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return const ProviderScope(child: CoranKarimApp());
      }
      if (!snapshot.hasError) {
        return const Directionality(
          textDirection: TextDirection.ltr,
          child: MushafClosedCover(),
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const MushafClosedCover(),
              Center(
                child: Material(
                  color: mushafCoverColor,
                  child: IconButton(
                    tooltip: 'Réessayer le démarrage',
                    color: Colors.white,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() {
                      _initialisation = _initialiserServices();
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _initialiserServices() async {
  final tTotal = Stopwatch()..start();
  final mesures = <String, int>{};

  // ── LES TROIS ÉTAPES DE DÉMARRAGE SONT LANCÉES ENSEMBLE (2026-09-13) ──────
  //
  // Elles étaient `await`ées l'une APRÈS l'autre, alors qu'AUCUNE ne dépend du
  // résultat d'une autre : trois allers-retours de canal de plateforme mis
  // bout à bout, dont le coût s'additionnait au lieu de se recouvrir. Elles
  // sont désormais démarrées simultanément et attendues ensemble.
  //
  // ⚠️ CE QUI NE CHANGE PAS, ET C'EST VOULU : on attend toujours les trois
  // AVANT de monter CoranKarimApp et ses providers. Seule la couverture
  // statique est affichee pendant cette attente (ChGPT, 2026-09-13).
  // Ne pas monter les ecrans fonctionnels plus tot :
  //   * `ReciterDownloadService.ensureReady` : tant qu'il n'a pas répondu,
  //     `localPathIfPresent` rend `null` et une sourate POURTANT téléchargée
  //     repart en streaming, silencieusement (cf. son propre commentaire).
  //   * `initSessionMedia` : `AudioService.init` doit précéder la création de
  //     `PlayerNotifier`, qui lui branche ses rappels. Dans l'app, un
  //     premier `ref.watch(playerProvider)` peut arriver avant — et la
  //     notification média serait morte sans que rien ne le dise.
  // Le gain vient donc du recouvrement, pas d'un report : aucune garantie
  // d'ordre n'est sacrifiée.
  //
  // Les erreurs sont journalisées APRÈS le `Future.wait`, pas dans les `catch`
  // individuels : à ce moment `DiagnosticLog.init()` est forcément terminé,
  // donc une panne de session média ne peut plus être perdue faute de fichier
  // de journal ouvert — ce qui aurait été le cas en les journalisant en vol.
  Object? panneSessionMedia;
  await Future.wait([
    // Journal persistant sur le téléphone (cf. diagnostic_log.dart).
    _etape('journal', mesures, DiagnosticLog.init),
    // Résout la racine de l'audio téléchargé. DOIT être fait avant toute
    // lecture : sans ça `localPathIfPresent` renvoie toujours null et une
    // sourate pourtant téléchargée repart en streaming, sans le moindre
    // message d'erreur.
    _etape('audioLocal', mesures, ReciterDownloadService().ensureReady),
    // ── SESSION MEDIA (2026-09-03) ─────────────────────────────────────────
    // C'est elle qui declare le service de premier plan qui portera la lecture
    // quand l'app sera reduite. Demande utilisateur : « pause/play depuis la
    // notification [...] mais garder toute l'app en arriere-plan, c'est pas
    // une bonne idee » -- une session media laisse justement le systeme
    // suspendre l'interface Flutter.
    //
    // Un echec n'est PAS fatal : mieux vaut une app sans notification qu'une
    // app qui ne demarre pas. La variable globale sessionMedia reste alors
    // null, et tout le branchement cote PlayerNotifier se desactive de
    // lui-meme.
    _etape('sessionMedia', mesures, () async {
      try {
        if (sessionMedia == null) await initSessionMedia();
      } catch (e) {
        panneSessionMedia = e;
      }
    }),
  ]);
  if (panneSessionMedia != null) {
    DiagnosticLog.log(
      'Lecture',
      'session media indisponible : $panneSessionMedia',
    );
  }
  DiagnosticLog.log(
    'Demarrage',
    'services avant app=${tTotal.elapsedMilliseconds}ms '
        '(journal=${mesures['journal']}ms '
        'audioLocal=${mesures['audioLocal']}ms '
        'sessionMedia=${mesures['sessionMedia']}ms — lances en parallele, '
        'le total est donc le MAX et non la somme)',
  );
  // Mesure de fluidite dans le journal de l'app (cf. mesure_fluidite.dart) --
  // inactive si le diagnostic est coupe, donc silencieuse en release.
  demarrerMesureFluidite();
  // Le moteur LiteRT-LM du Coach IA (Gemma 4 E2B) était initialisé ici.
  // RETIRÉ le 2026-08-10 : le modèle `.litertlm` n'a jamais été livré, donc
  // aucune explication n'a jamais été produite — mais ses bibliothèques
  // natives pesaient ~90 Mo par architecture dans l'APK, soit plus de la
  // moitié de la charge utile arm64. Détail et mesures dans
  // `coach_explanation_sheet._loadGemmaFallback`.
  // La rigueur du tajwid est un reglage PERSISTE (2026-09-05, demande
  // utilisateur : « que ca reste tolere apres redemarrage »). Le provider la
  // restaure depuis les preferences, mais c'est le NATIF qui juge : sans ce
  // rappel, l'ecran afficherait « tolerant » pendant que le plugin garde son
  // defaut `v2TajwidStrict = true`. Branche AVANT les providers, donc avant la
  // premiere lecture du provider -- l'inverse laisserait passer la
  // restauration sans la pousser.
  TajwidStrictSettingNotifier.pousseurNatif =
      FastConformerVerifier.pousserTajwidStrict;
}

/// `ConsumerStatefulWidget` et non `ConsumerWidget` — uniquement pour pouvoir
/// construire [GardeMicro] UNE SEULE FOIS (2026-08-10). Un observateur de
/// navigation recréé à chaque `build` serait réenregistré à chaque changement
/// de langue ou de thème, et perdrait la profondeur de pile qu'il suit.
class CoranKarimApp extends ConsumerStatefulWidget {
  const CoranKarimApp({super.key});

  @override
  ConsumerState<CoranKarimApp> createState() => _CoranKarimAppState();
}

class _CoranKarimAppState extends ConsumerState<CoranKarimApp> {
  /// Relâche le micro dès qu'on quitte l'écran qui récitait, et quand l'app
  /// passe en arrière-plan. Enregistré ici, au-dessus de toute navigation :
  /// c'est ce qui le rend valable pour les TROIS écrans qui démarrent une
  /// récitation aujourd'hui — et pour ceux de demain, sans que personne ait à
  /// y penser. Cf. `services/garde_micro.dart` pour l'historique du défaut
  /// (corrigé trois fois au mauvais endroit).
  late final GardeMicro _gardeMicro = GardeMicro(
    () => ref.read(recitationVerifierProvider),
  );

  @override
  void dispose() {
    _gardeMicro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appLocaleProvider);
    return MaterialApp(
      title: 'Coran Karim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: kSupportedAppLocales.map(Locale.new),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [_gardeMicro, observateurDeRoutes],
      home: const _PointDEntree(),
    );
  }
}

/// Observateur de routes de l'application.
///
/// ── POURQUOI IL EXISTE (2026-09-14, demande utilisateur) ────────────────────
/// « à chaque retour arrière dans l'application, là où se trouve le menu, qu'il
/// s'affiche au lieu de rester caché ».
///
/// Le Mushaf efface son en-tête et sa barre du bas après quelques secondes de
/// lecture silencieuse -- volontaire, c'est ce qui donne le plein écran. Mais
/// l'écran n'est jamais reconstruit quand on REVIENT d'un sous-écran (il vit
/// dans un `IndexedStack`, son `initState` ne rejoue pas) : on retombait donc
/// sur une page nue, sans aucun moyen visible de naviguer, et il fallait
/// toucher l'écran au hasard pour faire réapparaître le menu.
///
/// `didPopNext` est le seul signal qui dit « on vient de revenir SUR moi ».
/// Un `.then()` sur chaque `Navigator.push` aurait couvert les appels qu'on
/// pense à modifier, jamais ceux qu'on ajoutera plus tard.
final RouteObserver<ModalRoute<void>> observateurDeRoutes =
    RouteObserver<ModalRoute<void>>();

/// Aiguillage de démarrage : ouvre la RECETTE si l'app a été lancée par intent
/// (`--es recette ecoute|lecture --ei sourate N`), l'accueil normal sinon.
///
/// Ajouté le 2026-07-28 pour le banc à deux téléphones : sans lui, chaque
/// itération de test demandait la même navigation manuelle sur DEUX appareils,
/// ce qui coûte du temps et, surtout, fait varier le protocole entre deux
/// mesures censées être comparables.
class _PointDEntree extends StatefulWidget {
  const _PointDEntree();
  @override
  State<_PointDEntree> createState() => _PointDEntreeState();
}

class _PointDEntreeState extends State<_PointDEntree> {
  static const _canal = MethodChannel('coran_karim/recette');
  Widget? _ecran;

  @override
  void initState() {
    super.initState();
    _aiguiller();
  }

  Future<void> _aiguiller() async {
    Map? extras;
    try {
      extras = await _canal.invokeMethod<Map>('lire');
    } catch (_) {
      // Canal absent (autre plateforme, moteur pas encore prêt) : accueil normal.
    }
    if (!mounted) return;
    // ── MISE À JOUR FORCÉE (2026-09-11) ─────────────────────────────────
    //
    // Demande utilisateur : « est-ce qu'il y a moyen [...] de forcer
    // l'utilisateur à mettre à jour l'application s'il y a une nouvelle
    // version [sur le] Play Store ». Deux options possibles : l'API Play
    // Core « immediate update » (natif, mais ne peut se tester qu'une
    // fois déjà publié) ou une vérification via le package `upgrader`
    // (compare la version installée à celle du Play Store, testable dès
    // que l'app a une fiche sur le Store). Choix validé : `upgrader`.
    //
    // `showIgnore: false` + `showLater: false` retirent les deux seules
    // échappatoires du dialog ; `barrierDismissible` (tap extérieur) ET
    // le bouton retour Android sont déjà bloqués par défaut dans le
    // package tant qu'aucun des deux n'est explicitement autorisé (cf.
    // `UpgradeAlert.barrierDismissible = false` par défaut, et
    // `onCanPop()` qui s'aligne dessus en l'absence de `shouldPopScope`).
    // Seul le bouton "Mettre à jour" reste actionnable -- pas besoin de
    // maintenir un `minAppVersion` à la main : dès qu'une version plus
    // récente existe sur le Store, le dialog s'affiche et ne peut plus
    // être esquivé. `checkOnResume` (par défaut `true`) revérifie aussi
    // au retour dans l'app si l'utilisateur est allé sur le Store sans
    // finaliser la mise à jour.
    //
    // UNIQUEMENT sur l'accueil normal, JAMAIS sur le banc de recette
    // (`RecetteScreen`, ci-dessous) : un banc de mesure automatisé ne
    // doit jamais se retrouver bloqué par un dialog qui attend un geste
    // humain sur le Play Store.
    //
    // VÉRIFIÉ SUR DEVICE (pas supposé) : le nom de package interrogé est
    // TOUJOURS `packageInfo.packageName` (`upgrade_store_controller.dart`),
    // donc `com.corankarim.coran_karim.dev` sur un build debug -- qui
    // n'existe pas sur le Play Store, la vraie comparaison de version ne
    // peut donc pas être testée avant publication. Ce qui A été vérifié
    // par exécution, avec `Upgrader(debugDisplayAlways: true)` temporaire
    // (retiré après coup, JAMAIS à laisser en place -- il afficherait ce
    // dialog en permanence, même sans mise à jour) : le dialog s'affiche
    // bien avec pour seul bouton "MAINTENANT", et le bouton retour Android
    // ne le ferme pas (l'écran passe en arrière-plan, le dialog reste
    // au-dessus) -- capture d'écran à l'appui.
    setState(
      () => _ecran = extras == null
          ? UpgradeAlert(
              showIgnore: false,
              showLater: false,
              child: const HomeScreen(),
            )
          : RecetteScreen(
              mode: extras['mode'] as String?,
              surah: (extras['sourate'] as num?)?.toInt() ?? 2,
              limite: (extras['versets'] as num?)?.toInt() ?? 20,
              depart: (extras['depart'] as num?)?.toInt() ?? 1,
              wav: extras['wav'] as String?,
              ecriture: extras['ecriture'] as String?,
              riwaya: extras['riwaya'] as String?,
              normal: extras['normal'] as bool? ?? false,
              bornerVersets: extras['borner'] as bool? ?? false,
              fusion: extras['fusion'] as bool? ?? true,
              preuves: (extras['preuves'] as num?)?.toInt() ?? 2,
              pas: (extras['pas'] as num?)?.toDouble() ?? 4.0,
              largeur: (extras['largeur'] as num?)?.toDouble() ?? 4.0,
              maxBloc: (extras['maxbloc'] as num?)?.toDouble() ?? 10.0,
              maxFusion: (extras['maxfusion'] as num?)?.toDouble() ?? 18.0,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => _ecran ?? const MushafClosedCover();
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  bool _ouvertureEnCours = true;

  /// Présentation du premier lancement (2026-08-09). `null` tant que la
  /// réponse des préférences n'est pas arrivée : on affiche alors l'app
  /// normalement plutôt qu'un écran d'attente. Lire un booléen dans
  /// SharedPreferences prend quelques millisecondes -- imposer un splash pour
  /// ça coûterait plus cher que le rare cas où la présentation apparaît une
  /// fraction de seconde après le premier rendu.
  bool _montrerOnboarding = false;

  /// Préparation du premier lancement (2026-09-13, demande utilisateur : « au
  /// premier lancement, après la couverture du Mushaf : choisir la langue et
  /// Hafs ou Warsh, choisir l'écriture avec un aperçu réel »).
  ///
  /// DISTINCTE de [_montrerOnboarding], et vérifiée AVANT lui : préparer et
  /// présenter ne sont pas la même chose. La présentation
  /// (`onboarding_screen.dart`) décrit ce que fait l'app ; la préparation
  /// (`preparation_screen.dart`) enregistre de vrais réglages. Les deux
  /// drapeaux sont séparés pour qu'on puisse activer l'un sans l'autre -- la
  /// présentation est d'ailleurs coupée aujourd'hui (`kOnboardingActif`).
  bool _montrerPreparation = false;

  /// Visite guidée : la main 👆 se promène sur les vrais onglets et
  /// l'application navigue pour de bon (cf. `widgets/guide_interactif.dart`).
  bool _montrerVisite = false;

  /// ── POINT D'ACCROCHE DE LA VISITE GUIDÉE (2026-09-13) ──────────────────
  ///
  /// Un chapitre de découverte doit pouvoir changer d'onglet ET connaître la
  /// position des onglets, depuis un fichier de catalogue qui n'a aucun accès
  /// à cet état. On expose donc trois choses, et rien de plus : aller à un
  /// onglet, et les clés des onglets à mettre en lumière.
  ///
  /// Assignées dans `initState` plutôt que passées par un provider : le
  /// catalogue est de la DONNÉE, pas un widget -- il n'a pas de `Ref`. Elles
  /// vivent au premier niveau de `data/guides_catalogue.dart` et non ici : les
  /// statiques d'une classe privée sont invisibles depuis un autre fichier
  /// (erreur commise d'abord, signalée en « unused_field »).

  /// Clés posées sur les VRAIS onglets. La visite lit leur position à
  /// l'exécution -- aucune coordonnée codée, sans quoi la main se poserait à
  /// côté dès qu'on change de téléphone.
  final GlobalKey _cleOngletCoran = GlobalKey();
  final GlobalKey _cleOngletDuas = GlobalKey();
  final GlobalKey _cleOngletCoach = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Amorce la programmation de l'adhan meme si l'utilisateur ne visite
    // jamais l'ecran de reglages prieres -- lire le provider une fois suffit
    // a declencher son _bootstrap() (position GPS + calcul + programmation
    // des 5 prieres + rappel Sobh, cf. prayer_settings_provider.dart).
    Future.microtask(() => ref.read(prayerSettingsProvider));
    // Même principe pour les rappels du Coach (2026-08-13) -- lire une fois
    // suffit à poser les `ref.listen` qui garderont la programmation à jour,
    // cf. coach_notification_provider.dart.
    Future.microtask(() => ref.read(coachNotificationBootstrapProvider));
    allerAOngletGuide = (i) {
      if (mounted) setState(() => _tab = i);
    };
    cleOngletCoran = _cleOngletCoran;
    cleOngletDuas = _cleOngletDuas;
    cleOngletCoach = _cleOngletCoach;
    _aiguillerPremierLancement();
  }

  @override
  void dispose() {
    // Sans ça, un chapitre lancé après la destruction de cet écran appellerait
    // un `setState` sur un State mort.
    allerAOngletGuide = null;
    cleOngletCoran = null;
    cleOngletDuas = null;
    cleOngletCoach = null;
    super.dispose();
  }

  /// Enchaîne préparation -> présentation -> lecture, en s'arrêtant au premier
  /// qui a quelque chose à montrer.
  ///
  /// Écrit comme une seule fonction séquentielle plutôt qu'en `.then()`
  /// imbriqués : l'ordre de ces trois écrans EST la décision, et il doit se
  /// lire en trois lignes. La version précédente n'en enchaînait que deux et
  /// l'imbrication était déjà à la limite.
  Future<void> _aiguillerPremierLancement() async {
    if (await preparationARegarder()) {
      if (!mounted) return;
      setState(() => _montrerPreparation = true);
      return; // la suite reprend dans `onTermine` de la préparation.
    }
    if (await onboardingARegarder()) {
      if (!mounted) return;
      setState(() => _montrerOnboarding = true);
      return;
    }
    _reprendreLectureAuLancement();
  }

  /// ChGPT: open the paper reader once per cold launch. Returning from it
  /// reveals the existing tabs; resuming the app never replays the cover.
  Future<void> _reprendreLectureAuLancement() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder<int>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          // TRANSPARENTE depuis le 2026-09-14 : la couverture s'ouvre sur les
          // onglets déjà montés dessous, puis se referme seule. Opaque, elle
          // révélait un écran vide — cf. `MushafOpeningScreen.build`.
          opaque: false,
          pageBuilder: (_, _, _) => const MushafOpeningScreen(),
        ),
      );
    } finally {
      if (mounted) setState(() => _ouvertureEnCours = false);
    }
    await _rouvrirLaDerniereLecture();
  }

  /// ── L'APPLICATION ROUVRE OU L'ON S'ETAIT ARRETE (2026-09-14) ───────────
  ///
  /// Demande utilisateur : « normalement sur les versions d'avant j'ai laisse
  /// la possibilite de revenir sur la page ou j'etais avant », puis, sur la
  /// carte que j'avais ajoutee a la place : « non, tu rajoutes de toi-meme,
  /// avant c'etait AUTOMATIQUE ».
  ///
  /// CE QUI S'ETAIT PASSE : la position est enregistree a chaque verset lu
  /// depuis le 2026-08-26 et l'ouverture la relit toujours -- mais depuis que
  /// la couverture debouche sur la page principale (demande du meme jour),
  /// plus rien n'y menait. La position etait calculee, mise en cache, et
  /// n'ouvrait plus rien. J'avais propose une carte « Reprendre » sur
  /// l'accueil : ce n'est pas ce qui existait, et ce n'est pas ce qui a ete
  /// demande -- elle est retiree.
  ///
  /// ⚠️ LE LECTEUR DEROULANT, JAMAIS LE MUSHAF PAPIER. C'est la condition
  /// posee le matin meme, dans la meme phrase que la demande d'origine : « ou
  /// bien acces direct a l'ancienne lecture mais PAS PAPIER, ou le menu sera
  /// affiche ». Le papier s'ouvre en plein ecran sans barre d'onglets ; le
  /// lecteur deroulant, lui, porte son propre menu. Les deux demandes tiennent
  /// donc ensemble, a condition de ne pas se tromper d'ecran.
  ///
  /// La route est POUSSEE par-dessus les onglets : un retour arriere ramene a
  /// la page principale, qui est deja montee dessous. Personne n'est enferme.
  ///
  /// Silencieux si rien n'a jamais ete lu (premier lancement) ou si la sourate
  /// est introuvable : on reste sur la page principale, sans message -- il n'y
  /// a rien a signaler, juste rien a reprendre.
  Future<void> _rouvrirLaDerniereLecture() async {
    if (!mounted) return;
    try {
      final position = await lireDernierePositionLecture();
      if (!mounted || position == null) return;
      final sourates = await QuranApi.fetchSurahs();
      if (!mounted) return;
      final s = sourates.where((x) => x.number == position.$1).firstOrNull;
      if (s == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MushafScreen(surah: s, initialAyahNumber: position.$2),
        ),
      );
    } catch (_) {
      // Reprise best-effort : une lecture de preferences ou un cache de
      // sourates en echec ne doit jamais empecher l'application de demarrer.
    }
  }

  // Keep all tabs alive
  //
  // CINQUIÈME ONGLET (2026-08-09, demande utilisateur) : la page "Une
  // invocation pour nous" (DuaPourNousScreen) était atteignable seulement
  // depuis une tuile des Réglages, jugée trop discrète -- « je veux qu'elle
  // soit visible pour inciter les users à ne pas oublier ». Placée ENTRE
  // Coach et Réglages (demande explicite), ce qui décale l'index des
  // Réglages de 3 à 4 -- cf. `_openReglages` ci-dessous, seul point qui doit
  // suivre ce décalage.
  static const _screens = [
    SurahListScreen(),
    DuasScreen(),
    CoachHubScreen(),
    DuaPourNousScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // La présentation couvre l'app au lieu d'être poussée en route : les
    // quatre onglets restent montés dessous (`IndexedStack`, « keep all tabs
    // alive »), donc rien n'est reconstruit à sa fermeture, et l'utilisateur
    // retombe exactement sur l'app déjà chargée.
    // AVANT la présentation et avant la couverture : c'est le premier écran
    // avec lequel on interagit. Il couvre l'app de la même façon (les onglets
    // restent montés dessous), donc rien n'est reconstruit à sa fermeture.
    if (_montrerPreparation) {
      return PreparationScreen(
        onTermine: () {
          setState(() {
            _montrerPreparation = false;
            _ouvertureEnCours = false;
          });
          // ── PRÉPARER, PUIS FAIRE DÉCOUVRIR (2026-09-13) ──────────────
          //
          // La visite guidée suit immédiatement la préparation : c'est la
          // deuxième moitié de la demande (« 1. préparer l'application,
          // 2. découvrir en manipulant »). On ne passe PAS par
          // `_aiguillerPremierLancement()` ici -- il repartirait sur la
          // couverture du Mushaf, qui recouvrirait la visite avant qu'on
          // l'ait vue.
          // Visite guidée désactivée (`kVisitesGuideesActives`, 2026-09-14) :
          // la préparation rend donc la main directement à l'application. Sa
          // dernière étape vient de proposer d'essayer les quatre fonctions,
          // ce qui remplace le tour narré.
          if (kVisitesGuideesActives) demarrerVisite();
        },
      );
    }
    if (_montrerOnboarding) {
      return OnboardingScreen(
        onTermine: () {
          setState(() => _montrerOnboarding = false);
          _reprendreLectureAuLancement();
        },
      );
    }
    if (_ouvertureEnCours) return const MushafClosedCover();
    // La visite se pose PAR-DESSUS l'app réelle, dans un `Stack` -- et non
    // dans un `OverlayEntry` : elle doit mourir avec cet écran. Les onglets
    // restent montés dessous, donc la main désigne de VRAIS boutons et
    // l'`action` de chaque étape fait naviguer l'application pour de bon.
    return Stack(children: [_appareil(), if (_montrerVisite) _visite()]);
  }

  /// Démarre la visite guidée. Appelée à la fin de la préparation, et
  /// rappelable depuis les réglages.
  void demarrerVisite() {
    setState(() {
      _tab = 0;
      _montrerVisite = true;
    });
  }

  Widget _visite() {
    final t = AppLocalizations.of(context)!;
    // ── UNE SEULE DÉFINITION DU TOUR D'ENSEMBLE (2026-09-13) ──────────────
    //
    // Les étapes étaient écrites ICI en dur, ET dans le catalogue. Deux
    // définitions de la même visite finissent toujours par diverger : on
    // corrige un texte d'un côté, et l'autre continue de dire l'ancienne
    // chose. Le catalogue est la source unique ; ce premier lancement joue
    // simplement son premier chapitre.
    return VisiteGuidee(
      libellePasser: t.guidePasser,
      libelleSuivant: t.guideSuivant,
      libelleFin: t.guideFin,
      onTermine: () => setState(() => _montrerVisite = false),
      // ── EN RECETTE, LE DEMARRAGE JOUE TOUT (2026-09-14) ────────────────
      //
      // Constat utilisateur, capture a l'appui : « je ne vois que ce qu'il y a
      // dans le menu principal ». C'etait exact, et c'etait le comportement
      // normal -- le premier chapitre du catalogue est le TOUR D'ENSEMBLE, qui
      // ne parcourt que les cinq onglets (4 etapes). Les ~53 etapes detaillees
      // (reglages, menu d'un verset, prieres, Coach, memorisation) n'etaient
      // atteignables que par Reglages -> Decouvrir l'application, ou personne
      // ne va spontanement pendant une recette.
      //
      // Pendant la recette, le demarrage enchaine donc TOUS les chapitres. En
      // release il rejoue le seul tour d'ensemble : imposer 57 etapes a
      // quelqu'un qui ouvre l'app pour la premiere fois serait exactement ce
      // que l'utilisateur voulait eviter (« tout parcourir automatiquement des
      // l'installation serait long »). Les deux besoins sont opposes, d'ou la
      // bascule -- et c'est la MEME que celle qui rejoue la preparation, donc
      // rien de nouveau a penser a eteindre avant publication.
      etapes: preparationEnRecette
          ? [for (final ch in kChapitresGuide) ...ch.etapes(context, t)]
          : kChapitresGuide.first.etapes(context, t),
    );
  }

  Widget _appareil() {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TickerMode(enabled: _tab == 0, child: _screens[0]),
          _screens[1],
          // ── L'ONGLET COACH SAIT QUAND IL N'EST PLUS REGARDÉ (2026-09-14) ──
          //
          // Bug signalé : « lors de l'entraînement par palier, au lancement de
          // l'audio, si je bascule sur autre chose, l'audio continue ; il doit
          // s'arrêter ».
          //
          // La cause n'est pas dans l'écran d'entraînement, qui coupe bien son
          // audio dans `dispose()` : c'est que `dispose()` N'ARRIVE JAMAIS.
          // `IndexedStack` garde les cinq onglets montés — c'est voulu (on
          // retrouve chaque onglet où on l'avait laissé) — donc changer d'onglet
          // ne détruit rien.
          //
          // `TickerMode` est le signal qui manquait : il passe à `false` dès que
          // l'onglet sort de l'écran, et l'entraînement s'y abonne pour couper
          // sa lecture (cf. `IncrementalRepeatStep.didChangeDependencies`).
          TickerMode(enabled: _tab == 2, child: _screens[2]),
          ..._screens.skip(3),
        ],
      ),
      // ── LES BOUTONS DE DEVELOPPEMENT SONT RETIRES (2026-08-06) ───────────
      //
      // Demande utilisateur : « enlève le calibrage, il ne sert plus à rien ;
      // et la recette, c'est toi qui y accèdes -- plus d'affichage dans l'app,
      // tu laisses l'accès direct pour toi ».
      //
      // Les deux ecrans EXISTENT toujours et restent atteignables :
      //   - RECETTE   : par intent, cf. MainActivity + `_PointDEntree`
      //                 (`--es recette ecoute --ei sourate N`) -- c'est le
      //                 chemin qu'utilise `benchmark/recette_2tel.sh`, il n'a
      //                 jamais eu besoin du bouton ;
      //   - CALIBRAGE : `CalibrageScreen` est conserve, simplement plus
      //                 propose. Son role a ete repris par le decoupage aux
      //                 silences reels et par le profil de pause.
      // On ne supprime AUCUN code : on retire deux entrees d'une IHM destinee
      // au recitateur, pas au developpeur.
      //
      // Le SIGNET, lui, vit dans la barre du haut de la liste des sourates,
      // a cote de l'oreille et de la mosquee (demande utilisateur : « place-le
      // dans le coin en haut a cote de l'oeil et suivre priere »).
      bottomNavigationBar: _buildNav(),
    );
  }

  /// Ouvre l'onglet Coach en le forçant à relire l'archive des sessions.
  ///
  /// BUG CORRIGÉ (2026-08-09), constat utilisateur : après pause puis retour
  /// arrière depuis une récitation, le Coach ne montrait pas la dernière
  /// session, MÊME APRÈS le correctif du try/catch dans le `dispose()` de
  /// l'écran de récitation. `_tab` est géré par un simple `IndexedStack` --
  /// « Keep all tabs alive » -- donc `CoachHubScreen` ne se reconstruit
  /// JAMAIS depuis zéro : il ne peut compter que sur l'invalidation faite
  /// PAR L'ÉCRAN DE RÉCITATION pour savoir qu'une nouvelle session existe.
  /// C'est fragile par construction -- ça dépend d'un timing et d'un chemin
  /// de sortie précis dans un écran totalement différent, et toute nouvelle
  /// façon de quitter la récitation (une de plus s'ajoutera un jour) peut
  /// la faire manquer.
  ///
  /// Le bon endroit pour garantir des données fraîches, c'est là où
  /// l'utilisateur regarde effectivement le Coach : CE tap. On invalide
  /// systématiquement en l'ouvrant -- coûte une requête SQLite de plus par
  /// ouverture d'onglet (négligeable), et rend inutile de deviner tous les
  /// chemins de sortie possibles d'une récitation.
  void _openCoachTab() {
    ref.invalidate(sessionsArchiveProvider);
    ref.invalidate(tailleArchiveProvider);
    // Suivi permanent par portion (2026-08-10) : même raison que les deux
    // lignes ci-dessus -- l'onglet Coach reste monté (IndexedStack), sans
    // ça il continuerait d'afficher les portions telles qu'elles étaient à
    // la dernière ouverture.
    ref.invalidate(portionsProvider);
    // Le tableau de bord (serie, points, progression) se relit ici aussi :
    // c'est le point de passage OBLIGE vers l'onglet Coach.
    ref.invalidate(derniersJoursProvider);
    ref.invalidate(serieProvider);
    _detecterAccesCachePriere();
    setState(() => _tab = 2);
  }

  /// 5 taps sur l'onglet Coach en moins de 2 s = accès caché à « Suivre une
  /// prière » (2026-08-26, demande utilisateur -- cf. la doc de
  /// `suivrePriereAccesCacheProvider`). Compteur remis à zéro si l'écart
  /// entre deux taps dépasse ce délai : sans ça, cinq visites NORMALES et
  /// espacées de l'onglet Coach finiraient par déclencher l'accès sans que
  /// personne ne l'ait cherché.
  int _tapsCoach = 0;
  DateTime? _dernierTapCoach;
  static const _delaiTapsCoach = Duration(seconds: 2);

  void _detecterAccesCachePriere() {
    final maintenant = DateTime.now();
    final precedent = _dernierTapCoach;
    _dernierTapCoach = maintenant;
    _tapsCoach =
        (precedent != null &&
            maintenant.difference(precedent) <= _delaiTapsCoach)
        ? _tapsCoach + 1
        : 1;
    if (_tapsCoach < 5) return;
    _tapsCoach = 0;
    if (ref.read(suivrePriereAccesCacheProvider)) return; // déjà actif
    ref.read(suivrePriereAccesCacheProvider.notifier).set(true);
  }

  Widget _buildNav() {
    final t = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.green900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // Chaque onglet dans un Expanded : les cinq se partagent la largeur
          // à parts égales (cinquième onglet ajouté le 2026-08-09) et un
          // libellé long (fr/en "Invocations"/"Réglages",
          // plus larges que l'arabe court) rétrécit/ellipse au lieu de faire
          // déborder la Row (bug "RIGHT OVERFLOWED BY N PIXELS" du 2026-07-19,
          // introduit par le passage des libellés arabes aux libellés
          // traduits). Ne plus jamais mettre de padding horizontal FIXE ici.
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  key: _cleOngletCoran,
                  // ── LES QUATRE ONGLETS EN EMOJI (2026-08-09, demande
                  // utilisateur, apres l'emoji des Invocations) : « l'emoji
                  // invocation est bien, mais les autres sont vieux [les
                  // icones Material] » -- uniformise les quatre plutot que de
                  // laisser un seul onglet moderne au milieu de trois datés.
                  // ── LE LOGO SUR LE PREMIER ONGLET (2026-09-14) ────────
                  //
                  // Demande utilisateur : « je parle du Coran, premier icone ».
                  // C'est l'onglet d'accueil, celui qui porte le nom de
                  // l'application -- le logo y designe l'app elle-meme, la ou
                  // le livre ouvert (📖) etait l'emoji generique de n'importe
                  // quel lecteur.
                  icon: null,
                  image: 'assets/icon/app_icon.png',
                  label: t.navQuran,
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  key: _cleOngletDuas,
                  // ── ICONE DES INVOCATIONS (2026-08-09, demande utilisateur)
                  //
                  // « il y a l'icone des invocations, je l'ai utilisee apres
                  // pour les dons, remplace-la par deux mains ouvertes, signe
                  // pour les invocations ». `volunteer_activism_rounded`
                  // (main + coeur) est en effet l'icone standard du DON en
                  // Material Design -- ambigu ici, et reserve pour plus tard.
                  //
                  // PREMIER ESSAI (retire le meme jour, jugé par l'utilisateur
                  // « ne ressemble pas vraiment ») : composer deux
                  // `front_hand_rounded` en miroir, faute de glyphe Material à
                  // deux mains. L'ÉMOJI 🤲 (U+1F932, PALMS UP TOGETHER) est
                  // littéralement le geste de l'invocation dans la norme
                  // Unicode -- plus fidèle qu'une composition d'icônes, et
                  // rendu par la police système, pas par un dessin approché.
                  icon: null,
                  emoji: '🤲',
                  label: t.navDuas,
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  key: _cleOngletCoach,
                  icon: null,
                  emoji: '🎓',
                  label: t.navCoach,
                  active: _tab == 2,
                  onTap: _openCoachTab,
                ),
              ),
              Expanded(
                child: _NavItem(
                  // ── CINQUIÈME ONGLET (2026-08-09, demande utilisateur) ──
                  // « émoticône entre Coach et Réglages » -- la page "Une
                  // invocation pour nous" (jusque-là une tuile discrète dans
                  // Réglages) devient un onglet à part entière, à l'endroit
                  // demandé, pour que les utilisateurs ne l'oublient pas.
                  // ⚠️ LE COEUR EST REVENU (2026-09-14). J'avais mis le
                  // logo ICI ; l'utilisateur parlait du PREMIER onglet :
                  // « non, je parle du Coran, premier icone [...] et remets le
                  // coeur pour Dua ». Les deux corrections sont faites.
                  icon: null,
                  emoji: '❤️',
                  label: t.navDuaPourNous,
                  active: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: null,
                  emoji: '⚙️',
                  label: t.navSettings,
                  active: _tab == 4,
                  onTap: () => setState(() => _tab = 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  /// Nul quand [emoji] est fourni -- les deux sont mutuellement exclusifs,
  /// cf. l'onglet Invocations (🤲, aucune icône Material équivalente).
  final IconData? icon;
  final String? emoji;

  /// Chemin d'un asset image, troisieme forme possible pour la pastille de
  /// l'onglet (2026-09-14, demande utilisateur : « remplacer l'emoticone dans
  /// le menu en bas avec notre icone »).
  ///
  /// POURQUOI UNE IMAGE ET PAS UNE `Icon` : c'est le logo de l'application,
  /// une vraie illustration en couleurs -- aucun glyphe Material ne le rend, et
  /// le redessiner en trait serait un AUTRE dessin. Meme traitement que
  /// l'emoji : encombrement force a 24x24 et teinte par `Opacity`, parce qu'on
  /// ne peut pas recolorer une image en couleurs sans la denaturer.
  final String? image;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// `super.key` ajouté le 2026-09-13 : la visite guidée pose une `GlobalKey`
  /// sur chaque onglet pour LIRE sa position à l'exécution (cf.
  /// `widgets/guide_interactif.dart`). Sans elle il faudrait coder des
  /// coordonnées, qui seraient fausses dès le téléphone suivant.
  const _NavItem({
    super.key,
    this.icon,
    this.emoji,
    this.image,
    required this.label,
    required this.active,
    required this.onTap,
  }) : assert(icon != null || emoji != null || image != null);

  @override
  Widget build(BuildContext context) {
    // Police arabe (Scheherazade New) seulement en locale arabe -- en fr/en
    // le libellé de menu est en latin, la police calligraphique arabe ne
    // convient plus (REFONTE_IHM.md §7bis).
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final labelStyle = isArabic
        ? GoogleFonts.scheherazadeNew(
            fontSize: 12,
            color: active ? AppColors.brass : AppColors.cream.withAlpha(140),
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          )
        : GoogleFonts.manrope(
            fontSize: 10.5,
            color: active ? AppColors.brass : AppColors.cream.withAlpha(140),
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Padding horizontal MODESTE (l'espacement vient du partage Expanded,
        // plus d'un padding fixe qui débordait) -- garde juste une marge pour
        // que les libellés ne se touchent pas.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            image != null
                ? Opacity(
                    opacity: active ? 1.0 : 0.55,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      // ── AGRANDI DE 25 % (2026-09-14) ─────────────
                      //
                      // Constat utilisateur : « il parait petit ». Il l'est,
                      // et pas a cause de la taille demandee : un icone de
                      // lancement porte une ZONE DE SECURITE dans son propre
                      // fichier (le dessin ne remplit pas le carre, Android
                      // la recadre au moment de poser l'icone sur l'ecran
                      // d'accueil). Pose tel quel dans une case de 24, il
                      // apparait donc plus petit que les emoji voisins, qui
                      // eux remplissent leur cadratin.
                      //
                      // `Transform.scale` et NON une case plus grande : la
                      // case donne sa hauteur a la colonne, l'agrandir
                      // descendrait le libelle de cet onglet-la tout seul --
                      // exactement le decalage corrige le 2026-08-09 sur
                      // l'emoji des Invocations. Ici le dessin grandit, la
                      // mise en page ne bouge pas.
                      child: Transform.scale(
                        scale: 1.25,
                        child: Image.asset(image!, fit: BoxFit.contain),
                      ),
                    ),
                  )
                : emoji != null
                // ── DÉCALAGE CORRIGÉ (2026-08-09, constat utilisateur) ────
                // Un `Text` d'emoji n'a PAS le même encombrement vertical
                // qu'une `Icon` : sa hauteur de ligne vient de la police
                // système (marge au-dessus/en-dessous du glyphe), pas d'une
                // boîte carrée de `size`. Ligne "Invocations" décalée par
                // rapport aux trois autres onglets (Coran, Coach...). On
                // force donc le même encombrement 24x24 que `Icon(size: 24)`
                // ci-dessous, `Center` recadrant le glyphe dedans -- même
                // teinte active/inactive que le reste faite par `Opacity`
                // (impossible de teinter un emoji couleur autrement).
                ? Opacity(
                    opacity: active ? 1.0 : 0.55,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Text(
                          emoji!,
                          style: const TextStyle(fontSize: 20, height: 1),
                        ),
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: active
                        ? AppColors.brass
                        : AppColors.cream.withAlpha(140),
                    size: 24,
                  ),
            const SizedBox(height: 2),
            Text(
              label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
