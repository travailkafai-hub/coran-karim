import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_settings_provider.dart';
import 'providers/prayer_settings_provider.dart';
import 'screens/recette_screen.dart';
import 'screens/surah_list_screen.dart';
import 'screens/duas_screen.dart';
import 'screens/coach_hub_screen.dart';
import 'screens/settings_screen.dart';
import 'services/diagnostic_log.dart';
import 'services/reciter_download_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Journal persistant sur le téléphone (cf. diagnostic_log.dart) — avant
  // tout le reste pour capturer même les tout premiers événements.
  await DiagnosticLog.init();
  // Résout la racine de l'audio téléchargé. DOIT précéder toute lecture :
  // sans ça `localPathIfPresent` renvoie toujours null et une sourate pourtant
  // téléchargée repart en streaming, sans le moindre message d'erreur.
  await ReciterDownloadService().ensureReady();
  // Moteur LiteRT-LM pour le Coach IA (Gemma 4 E2B, .litertlm) — moteur
  // opt-in de flutter_gemma, doit être enregistré avant tout usage.
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  runApp(const ProviderScope(child: CoranKarimApp()));
}

class CoranKarimApp extends ConsumerWidget {
  const CoranKarimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      home: const _PointDEntree(),
    );
  }
}

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
    setState(() => _ecran = extras == null
        ? const HomeScreen()
        : RecetteScreen(
            mode: extras['mode'] as String?,
            surah: (extras['sourate'] as num?)?.toInt() ?? 2,
            limite: (extras['versets'] as num?)?.toInt() ?? 20,
            depart: (extras['depart'] as num?)?.toInt() ?? 1,
            wav: extras['wav'] as String?,
            normal: extras['normal'] as bool? ?? false,
            fusion: extras['fusion'] as bool? ?? true,
            preuves: (extras['preuves'] as num?)?.toInt() ?? 2,
            pas: (extras['pas'] as num?)?.toDouble() ?? 4.0,
            largeur: (extras['largeur'] as num?)?.toDouble() ?? 4.0,
            maxBloc: (extras['maxbloc'] as num?)?.toDouble() ?? 10.0,
            maxFusion: (extras['maxfusion'] as num?)?.toDouble() ?? 18.0));
  }

  @override
  Widget build(BuildContext context) =>
      _ecran ?? const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Amorce la programmation de l'adhan meme si l'utilisateur ne visite
    // jamais l'ecran de reglages prieres -- lire le provider une fois suffit
    // a declencher son _bootstrap() (position GPS + calcul + programmation
    // des 5 prieres + rappel Sobh, cf. prayer_settings_provider.dart).
    Future.microtask(() => ref.read(prayerSettingsProvider));
  }

  // Keep all tabs alive
  static const _screens = [
    SurahListScreen(),
    DuasScreen(),
    CoachHubScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
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

  Widget _buildNav() {
    final t = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.green900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 12, offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // Chaque onglet dans un Expanded : les 4 se partagent la largeur à
          // parts égales et un libellé long (fr/en "Invocations"/"Réglages",
          // plus larges que l'arabe court) rétrécit/ellipse au lieu de faire
          // déborder la Row (bug "RIGHT OVERFLOWED BY N PIXELS" du 2026-07-19,
          // introduit par le passage des libellés arabes aux libellés
          // traduits). Ne plus jamais mettre de padding horizontal FIXE ici.
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.menu_book_rounded,
                  label: t.navQuran,
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.volunteer_activism_rounded,
                  label: t.navDuas,
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.psychology_alt_rounded,
                  label: t.navCoach,
                  active: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.settings_rounded,
                  label: t.navSettings,
                  active: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
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
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label,
      required this.active, required this.onTap});

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
              Icon(icon,
                  color: active ? AppColors.brass : AppColors.cream.withAlpha(140),
                  size: 24),
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
