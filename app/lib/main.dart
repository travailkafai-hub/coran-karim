import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_settings_provider.dart';
import 'screens/surah_list_screen.dart';
import 'screens/duas_screen.dart';
import 'screens/coach_ai_screen.dart';
import 'screens/settings_screen.dart';
import 'services/diagnostic_log.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Journal persistant sur le téléphone (cf. diagnostic_log.dart) — avant
  // tout le reste pour capturer même les tout premiers événements.
  await DiagnosticLog.init();
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
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // Keep all tabs alive
  static const _screens = [
    SurahListScreen(),
    DuasScreen(),
    CoachAiScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
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
