// Présentation au PREMIER LANCEMENT (2026-08-09, demande utilisateur : « je
// pense que tu dois travailler un onboarding qui explique toutes les étapes,
// ce que propose l'application ; se déclenche à la première utilisation »).
//
// ── CE QU'ELLE DIT, ET CE QU'ELLE NE DIT PAS ─────────────────────────────
// Chaque page décrit une fonction qui EXISTE et qui est atteignable dans
// cette version. Deux conséquences pratiques :
//   - « Suivre une prière » n'y figure pas : son bouton est retiré de la v1
//     (cf. `surah_list_screen.dart`). Une présentation qui vanterait une
//     fonction inaccessible serait un mensonge dès le premier écran ;
//   - la page « Vos données » reprend mot pour mot les affirmations déjà
//     vérifiées de `about_screen.dart` (analyse sur l'appareil, pas de
//     compte, pas de publicité, réseau seulement pour les téléchargements
//     demandés). Ne jamais y ajouter une promesse plus large que celle-là.
//
// La dédicace de la première page vient de l'utilisateur (« pour moi et pour
// mon père décédé »), c'est l'intention du projet, pas un texte décoratif.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Clé de persistance. Une seule valeur booléenne : la présentation a-t-elle
/// déjà été vue ? Volontairement PAS un numéro de version — reproposer tout
/// l'onboarding après chaque mise à jour serait une nuisance, et rien
/// aujourd'hui ne justifie de le rejouer.
const String kPrefOnboardingVu = 'onboarding_vu';

/// ⚠️ INTERRUPTEUR UNIQUE — LA PRÉSENTATION EST DÉSACTIVÉE (2026-08-09).
///
/// Décision utilisateur, le jour même où elle a été écrite et vérifiée sur
/// l'appareil : « c'est ok, l'onboarding, désactive-le maintenant jusqu'à ce
/// qu'on finalise l'app ; après je vais te demander de l'activer ».
///
/// Elle FONCTIONNE (7 pages, 3 langues, testée sur device) : ce n'est pas un
/// brouillon mis de côté. On la coupe parce que son contenu décrit des
/// fonctions encore en mouvement, et qu'une présentation qui promet ce que
/// l'app ne fait plus est pire que pas de présentation du tout.
///
/// POUR LA RÉACTIVER : passer cette constante à `true`. Rien d'autre. Ne pas
/// remplacer ce mécanisme par une suppression de l'appel dans `main.dart` --
/// c'est justement ce qui rendrait le retour en arrière coûteux.
const bool kOnboardingActif = false;

/// Vrai si la présentation n'a jamais été affichée.
///
/// Le défaut est `false` (= « déjà vu ») en cas d'erreur de lecture des
/// préférences : mieux vaut rater la présentation qu'imposer un plein écran à
/// chaque démarrage si le stockage est indisponible.
Future<bool> onboardingARegarder() async {
  if (!kOnboardingActif) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(kPrefOnboardingVu) ?? false);
  } catch (_) {
    return false;
  }
}

Future<void> marquerOnboardingVu() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefOnboardingVu, true);
  } catch (_) {
    // Sans conséquence : la présentation se reproposera au prochain
    // démarrage. Jamais bloquant.
  }
}

class _PageOnboarding {
  final String emoji;
  final String titre;
  final String corps;

  /// Ligne secondaire, plus petite : une astuce concrète, ou la dédicace sur
  /// la première page. Nulle quand la page n'en a pas.
  final String? note;

  /// La note est-elle la dédicace ? Elle est alors présentée autrement
  /// (encadré, italique) — ce n'est pas une astuce d'utilisation.
  final bool noteEstDedicace;

  const _PageOnboarding({
    required this.emoji,
    required this.titre,
    required this.corps,
    this.note,
    this.noteEstDedicace = false,
  });
}

class OnboardingScreen extends StatefulWidget {
  /// Appelé quand l'utilisateur termine ou passe la présentation.
  final VoidCallback onTermine;

  const OnboardingScreen({super.key, required this.onTermine});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controleur = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  List<_PageOnboarding> _pages(AppLocalizations t) => [
        _PageOnboarding(
          emoji: '🕌',
          titre: t.onboardingWelcomeTitle,
          corps: t.onboardingWelcomeBody,
          note: t.onboardingWelcomeDedication,
          noteEstDedicace: true,
        ),
        _PageOnboarding(
          emoji: '📖',
          titre: t.onboardingReadTitle,
          corps: t.onboardingReadBody,
          note: t.onboardingReadHint,
        ),
        _PageOnboarding(
          emoji: '🎤',
          titre: t.onboardingReciteTitle,
          corps: t.onboardingReciteBody,
          note: t.onboardingReciteHint,
        ),
        _PageOnboarding(
          emoji: '🧩',
          titre: t.onboardingMemorizeTitle,
          corps: t.onboardingMemorizeBody,
          note: t.onboardingMemorizeHint,
        ),
        _PageOnboarding(
          emoji: '🎓',
          titre: t.onboardingCoachTitle,
          corps: t.onboardingCoachBody,
          note: t.onboardingCoachHint,
        ),
        _PageOnboarding(
          emoji: '🤲',
          titre: t.onboardingDuasTitle,
          corps: t.onboardingDuasBody,
        ),
        _PageOnboarding(
          emoji: '🔒',
          titre: t.onboardingPrivacyTitle,
          corps: t.onboardingPrivacyBody,
        ),
      ];

  Future<void> _terminer() async {
    await marquerOnboardingVu();
    widget.onTermine();
  }

  void _suivant(int total) {
    if (_page >= total - 1) {
      _terminer();
      return;
    }
    _controleur.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final pages = _pages(t);
    final dernier = _page >= pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.green900,
      body: SafeArea(
        child: Column(
          children: [
            // « Passer » toujours accessible, y compris sur la dernière page :
            // personne ne doit se sentir retenu par une présentation.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _terminer,
                child: Text(
                  t.onboardingSkip,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cream.withAlpha(170),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controleur,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _VuePage(page: pages[i]),
              ),
            ),
            _Points(total: pages.length, actif: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brass,
                    foregroundColor: AppColors.green900,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _suivant(pages.length),
                  child: Text(
                    dernier ? t.onboardingStart : t.onboardingNext,
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VuePage extends StatelessWidget {
  final _PageOnboarding page;
  const _VuePage({required this.page});

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(page.emoji,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 64, height: 1.1)),
          const SizedBox(height: 26),
          Text(
            page.titre,
            textAlign: TextAlign.center,
            // Même règle que la barre de navigation (REFONTE_IHM.md §7bis) :
            // la police calligraphique arabe seulement en locale arabe.
            style: isArabic
                ? GoogleFonts.scheherazadeNew(
                    fontSize: 30,
                    height: 1.6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brassLight)
                : GoogleFonts.fraunces(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brassLight),
          ),
          const SizedBox(height: 14),
          Text(
            page.corps,
            textAlign: TextAlign.center,
            style: isArabic
                ? GoogleFonts.scheherazadeNew(
                    fontSize: 21, height: 1.9, color: AppColors.cream)
                : GoogleFonts.manrope(
                    fontSize: 14.5, height: 1.65, color: AppColors.cream),
          ),
          if (page.note != null) ...[
            const SizedBox(height: 20),
            page.noteEstDedicace
                ? Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.brass.withAlpha(70)),
                    ),
                    child: Text(
                      page.note!,
                      textAlign: TextAlign.center,
                      style: isArabic
                          ? GoogleFonts.scheherazadeNew(
                              fontSize: 19,
                              height: 1.9,
                              color: AppColors.brassLight)
                          : GoogleFonts.manrope(
                              fontSize: 12.5,
                              height: 1.6,
                              fontStyle: FontStyle.italic,
                              color: AppColors.brassLight),
                    ),
                  )
                : Text(
                    page.note!,
                    textAlign: TextAlign.center,
                    style: isArabic
                        ? GoogleFonts.scheherazadeNew(
                            fontSize: 18,
                            height: 1.9,
                            color: AppColors.cream.withAlpha(180))
                        : GoogleFonts.manrope(
                            fontSize: 12.5,
                            height: 1.6,
                            color: AppColors.cream.withAlpha(180)),
                  ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _Points extends StatelessWidget {
  final int total;
  final int actif;
  const _Points({required this.total, required this.actif});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == actif ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == actif ? AppColors.brass : AppColors.cream.withAlpha(70),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
