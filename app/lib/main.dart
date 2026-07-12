import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

class CoranKarimApp extends StatelessWidget {
  const CoranKarimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coran Karim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.menu_book_rounded,
                label: 'القرآن',
                active: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _NavItem(
                icon: Icons.volunteer_activism_rounded,
                label: 'الأذكار',
                active: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
              _NavItem(
                icon: Icons.psychology_alt_rounded,
                label: 'مدرّبي',
                active: _tab == 2,
                onTap: () => setState(() => _tab = 2),
              ),
              _NavItem(
                icon: Icons.settings_rounded,
                label: 'إعدادات',
                active: _tab == 3,
                onTap: () => setState(() => _tab = 3),
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
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? AppColors.brass : AppColors.cream.withAlpha(140),
                  size: 24),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.scheherazadeNew(
                    fontSize: 12,
                    color: active
                        ? AppColors.brass
                        : AppColors.cream.withAlpha(140),
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  )),
            ],
          ),
        ),
      );
}
