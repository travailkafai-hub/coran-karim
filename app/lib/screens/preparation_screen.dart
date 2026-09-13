// Préparer l'application — premier lancement, après la couverture du Mushaf.
//
// ── CE QUE L'UTILISATEUR A DEMANDÉ (2026-09-13) ──────────────────────────────
//
// « Au premier lancement, après la couverture du Mushaf : choisir la langue et
// Hafs ou Warsh ; choisir l'écriture, avec un aperçu réel ; configurer les
// options utiles, sans tout imposer immédiatement. Ces choix seraient
// réellement enregistrés. »
//
// Trois exigences, et chacune a une conséquence dans ce fichier :
//
//   « un aperçu RÉEL »       -> l'aperçu est rendu avec `styleEcriture`, le
//                               point de passage unique qu'utilisent déjà la
//                               mesure, les spans colorés et le rendu de page
//                               (cf. `choix_ecriture_sheet.dart`). Pas une
//                               image, pas une approximation : ce qu'on voit
//                               ici est très exactement ce qui s'affichera
//                               dans le Mushaf.
//   « réellement enregistrés » -> chaque choix passe par le provider qui le
//                               persiste déjà (`appLocaleProvider`,
//                               `riwayaProvider`, `policeMushafPageProvider`).
//                               Aucun état local qui serait perdu à la sortie.
//   « sans tout imposer »    -> trois étapes, et la dernière est facultative.
//                               On ne demande PAS les réglages fins (seuils,
//                               sensibilité, diagnostic) : ils ont des défauts
//                               corrects et n'ont de sens qu'une fois qu'on a
//                               utilisé l'app.
//
// ── CE QU'ON NE FAIT PAS ICI ─────────────────────────────────────────────────
//
// ⚠️ AUCUNE PERMISSION N'EST DEMANDÉE DEPUIS CET ÉCRAN (micro, position,
// notifications). Consigne explicite : « les autorisations du téléphone
// resteraient à accepter par l'utilisateur, jamais par la main simulée ». Les
// permissions sont demandées par la fonction qui en a besoin, au moment où
// elle en a besoin — c'est aussi ce qui permet à quelqu'un de comprendre
// POURQUOI on les demande.
//
// ⚠️ CE N'EST PAS UN REMPLACEMENT DE `onboarding_screen.dart`. Cette
// présentation-là (7 pages de texte, désactivée le 2026-08-09 par
// `kOnboardingActif = false`) explique ce que fait l'app. Celle-ci la prépare.
// Les deux peuvent coexister ; aucune n'est supprimée.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/riwaya.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/choix_ecriture_sheet.dart';

/// Clé de persistance, distincte de `kPrefOnboardingVu` : voir la préparation
/// n'est pas voir la présentation, et fusionner les deux drapeaux empêcherait
/// d'activer l'une sans l'autre.
const String kPrefPreparationFaite = 'preparation_faite';

/// Vrai si la préparation n'a jamais été menée à son terme.
///
/// Défaut `false` (« déjà fait ») en cas d'erreur de lecture : même principe
/// que `onboardingARegarder` — mieux vaut manquer la préparation qu'imposer un
/// plein écran à chaque démarrage si le stockage est indisponible.
Future<bool> preparationARegarder() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(kPrefPreparationFaite) ?? false);
  } catch (_) {
    return false;
  }
}

Future<void> marquerPreparationFaite() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefPreparationFaite, true);
  } catch (_) {
    // Sans conséquence : la préparation se reproposera. Jamais bloquant.
  }
}

class PreparationScreen extends ConsumerStatefulWidget {
  /// Appelé quand la préparation est terminée ou passée.
  final VoidCallback onTermine;

  const PreparationScreen({super.key, required this.onTermine});

  @override
  ConsumerState<PreparationScreen> createState() => _PreparationScreenState();
}

class _PreparationScreenState extends ConsumerState<PreparationScreen> {
  int _etape = 0;
  static const _nbEtapes = 3;

  /// Le verset d'aperçu : la Fātiḥa 1:2, choisie parce qu'elle porte ce qui
  /// distingue VRAIMENT deux écritures — un alif suscrit, une shadda avec sa
  /// voyelle, un madd, et le lām-alif. Un texte sans diacritiques rendrait
  /// toutes les polices identiques et l'aperçu ne servirait à rien.
  static const _apercu = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ';

  void _suivant() {
    if (_etape + 1 >= _nbEtapes) {
      marquerPreparationFaite();
      widget.onTermine();
      return;
    }
    setState(() => _etape++);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.green900,
      body: SafeArea(
        child: Column(
          children: [
            _entete(t),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: switch (_etape) {
                  0 => _etapeLangueEtRiwaya(t),
                  1 => _etapeEcriture(t),
                  _ => _etapeOptions(t),
                },
              ),
            ),
            _pied(t),
          ],
        ),
      ),
    );
  }

  Widget _entete(AppLocalizations t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'القرآن الكريم',
              style: GoogleFonts.scheherazadeNew(
                fontSize: 26,
                color: AppColors.cream,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            // Une barre de progression plutôt qu'un « étape 1 sur 3 » : elle
            // dit la même chose sans texte à traduire, et se lit d'un coup
            // d'œil dans les trois langues.
            Row(
              children: [
                for (var i = 0; i < _nbEtapes; i++) ...[
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= _etape
                            ? AppColors.brass
                            : AppColors.cream.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < _nbEtapes - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      );

  Widget _titreEtape(String titre, String sous) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre,
              style: const TextStyle(
                color: AppColors.cream,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sous,
              style: TextStyle(
                color: AppColors.cream.withAlpha(170),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  // ── ÉTAPE 1 : langue et riwaya ────────────────────────────────────────────

  Widget _etapeLangueEtRiwaya(AppLocalizations t) {
    final locale = ref.watch(appLocaleProvider);
    final riwaya = ref.watch(riwayaProvider);
    // Les noms de langue sont écrits DANS leur propre langue, jamais traduits :
    // quelqu'un qui ouvre l'app dans une langue qu'il ne lit pas doit pouvoir
    // trouver la sienne. « Arabe » n'aide personne qui cherche « العربية ».
    const noms = {'ar': 'العربية', 'fr': 'Français', 'en': 'English'};
    return ListView(
      key: const ValueKey(0),
      children: [
        _titreEtape(t.settingsLocaleTitle, t.preparationLangueSous),
        for (final code in kSupportedAppLocales)
          _carte(
            titre: noms[code] ?? code,
            choisi: locale == code,
            onTap: () =>
                ref.read(appLocaleProvider.notifier).set(code),
            arabe: code == 'ar',
          ),
        const SizedBox(height: 10),
        _titreEtape(t.settingsRiwayaTitle, t.preparationRiwayaSous),
        _carte(
          titre: 'حفص — Ḥafṣ',
          sous: t.settingsRiwayaHafs,
          choisi: riwaya == Riwaya.hafs,
          onTap: () => ref.read(riwayaProvider.notifier).set(Riwaya.hafs),
        ),
        _carte(
          titre: 'ورش — Warsh',
          sous: t.settingsRiwayaWarsh,
          choisi: riwaya == Riwaya.warsh,
          onTap: () => ref.read(riwayaProvider.notifier).set(Riwaya.warsh),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── ÉTAPE 2 : l'écriture, avec un aperçu réel ─────────────────────────────

  Widget _etapeEcriture(AppLocalizations t) {
    final famille = ref.watch(policeMushafPageProvider);
    return Column(
      key: const ValueKey(1),
      children: [
        _titreEtape(t.settingsMushafScriptTitle, t.preparationEcritureSous),
        // L'aperçu est FIXE en haut et la liste défile dessous : sans ça, on
        // choisit une écriture puis on doit remonter pour voir ce qu'elle
        // donne, et l'aperçu ne sert plus à comparer.
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEF6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brass, width: 1.2),
          ),
          child: Text(
            _apercu,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: styleEcriture(
              ecriturePour(famille),
              taille: 30,
              interligne: 1.9,
              couleur: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: kEcrituresMushaf.length,
            itemBuilder: (_, i) {
              final e = kEcrituresMushaf[i];
              return _carte(
                titre: e.libelle,
                sous: e.note,
                choisi: e.famille == famille,
                onTap: () => ref
                    .read(policeMushafPageProvider.notifier)
                    .definir(e.famille),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── ÉTAPE 3 : quelques options, aucune imposée ────────────────────────────

  Widget _etapeOptions(AppLocalizations t) {
    final sombre = ref.watch(modeSombreProvider);
    final tajwid = ref.watch(tajwidMushafPageProvider);
    return ListView(
      key: const ValueKey(2),
      children: [
        _titreEtape(t.preparationOptionsTitre, t.preparationOptionsSous),
        _bascule(
          titre: t.preparationModeSombre,
          valeur: sombre,
          onChanged: (v) => ref.read(modeSombreProvider.notifier).set(v),
        ),
        _bascule(
          titre: t.scriptTajwidColors,
          valeur: tajwid,
          onChanged: (v) =>
              ref.read(tajwidMushafPageProvider.notifier).set(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            // Dit explicitement que rien n'est définitif. C'est ce qui permet
            // de passer sans crainte -- et donc de ne pas abandonner ici.
            t.preparationToutModifiable,
            style: TextStyle(
              color: AppColors.cream.withAlpha(150),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _carte({
    required String titre,
    String? sous,
    required bool choisi,
    required VoidCallback onTap,
    bool arabe = false,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Material(
          color: choisi
              ? AppColors.brass.withAlpha(46)
              : AppColors.cream.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: choisi ? AppColors.brass : Colors.transparent,
                  width: 1.3,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titre,
                          style: arabe
                              ? GoogleFonts.scheherazadeNew(
                                  fontSize: 19,
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w600,
                                )
                              : const TextStyle(
                                  fontSize: 15,
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w600,
                                ),
                        ),
                        if (sous != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            sous,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.cream.withAlpha(160),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (choisi)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.brass, size: 22),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _bascule({
    required String titre,
    required bool valeur,
    required ValueChanged<bool> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: SwitchListTile(
          value: valeur,
          onChanged: onChanged,
          title: Text(titre,
              style: const TextStyle(color: AppColors.cream, fontSize: 15)),
          activeThumbColor: AppColors.brass,
          tileColor: AppColors.cream.withAlpha(18),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _pied(AppLocalizations t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Row(
          children: [
            TextButton(
              // « Passer » est toujours disponible, y compris à la première
              // étape : les trois réglages ont des défauts corrects, et un
              // premier lancement qu'on ne peut pas quitter est une prise en
              // otage, pas une préparation.
              onPressed: () {
                marquerPreparationFaite();
                widget.onTermine();
              },
              child: Text(
                t.preparationPasser,
                style: TextStyle(color: AppColors.cream.withAlpha(160)),
              ),
            ),
            const Spacer(),
            if (_etape > 0)
              TextButton(
                onPressed: () => setState(() => _etape--),
                child: Text(t.preparationRetour,
                    style: const TextStyle(color: AppColors.cream)),
              ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: AppColors.green900,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: _suivant,
              child: Text(_etape + 1 >= _nbEtapes
                  ? t.preparationCommencer
                  : t.preparationSuivant),
            ),
          ],
        ),
      );
}
