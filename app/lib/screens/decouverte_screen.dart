// « Découvrir l'application » — le sommaire des visites guidées.
//
// ── POURQUOI UN SOMMAIRE PLUTÔT QU'UNE VISITE UNIQUE ─────────────────────────
//
// Demande utilisateur : « je veux un globale et de taillé même sous détaillé ».
// Et, plus tôt : « je privilégierais un démarrage court, puis des guides par
// fonction ; tout parcourir automatiquement dès l'installation serait long ».
//
// Cet écran est ce qui réconcilie les deux : le tour d'ensemble se joue seul au
// premier lancement, et tout le reste attend ici, disponible quand on en a
// besoin. On n'apprend pas une application en une fois, on y revient.
//
// ⚠️ CE N'EST PAS UNE LISTE DE PAGES D'AIDE. Chaque entrée LANCE la main sur
// les vrais écrans (cf. `data/guides_catalogue.dart`). Si un chapitre venait à
// ne plus faire que décrire, il vaudrait mieux le retirer : une aide qui parle
// sans montrer, c'est `onboarding_screen.dart`, qui existe déjà et qui est
// désactivée depuis le 2026-08-09 précisément parce qu'elle ne montrait rien.

import 'package:flutter/material.dart';

import '../data/guides_catalogue.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/guide_interactif.dart';

class DecouverteScreen extends StatelessWidget {
  const DecouverteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final chapitres = kChapitresGuide;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(t.guideDecouverteTitre),
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            t.guideDecouverteSous,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.ink.withAlpha(180),
            ),
          ),
          const SizedBox(height: 18),
          for (final c in chapitres) _carte(context, t, c),
        ],
      ),
    );
  }

  Widget _carte(BuildContext context, AppLocalizations t, ChapitreGuide c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _lancer(context, t, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.titre(t),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.resume(t),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.ink.withAlpha(165),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow_rounded,
                    color: AppColors.brass, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _lancer(BuildContext context, AppLocalizations t, ChapitreGuide c) {
    // ── ON QUITTE CE SOMMAIRE AVANT DE LANCER LA VISITE ────────────────────
    //
    // Sans ce `pop`, la main désignerait des onglets qui sont CACHÉS derrière
    // cet écran : la visite vit dans l'`Overlay` racine, donc elle se
    // dessinerait bien au-dessus, mais au-dessus du sommaire, pas de
    // l'application. On reviendrait à un guide qui commente une liste.
    //
    // On capture le navigateur AVANT le `pop` : après, ce `context` est
    // démonté et `Navigator.of(context)` lève.
    final navigateur = Navigator.of(context);
    final calque = Navigator.of(context, rootNavigator: true).context;
    navigateur.pop();
    // Un battement pour laisser l'accueil revenir et ses onglets se monter,
    // sinon la première étape mesure une cible qui n'existe pas encore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!calque.mounted) return;
      GuideHote.lancer(
        calque,
        etapes: c.etapes(calque, t),
        libellePasser: t.guidePasser,
        libelleSuivant: t.guideSuivant,
        libelleFin: t.guideFin,
      );
    });
  }
}
