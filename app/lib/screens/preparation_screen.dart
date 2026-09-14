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

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/riwaya.dart';
import '../providers/app_settings_provider.dart';

import '../models/verse.dart';
import '../services/quran_api.dart';
import 'karaoke_recitation_screen.dart';
import 'coach_screen.dart';
import 'memorization_game_screen.dart';
// `mushaf_screen.dart` n'est plus importé ici depuis le 2026-09-14 : la
// tuile « Lire et écouter » était son seul appelant (cf. plus bas).
import '../theme/app_theme.dart';
import '../widgets/choix_ecriture_sheet.dart';
import '../widgets/quran_pattern_background.dart';

/// Clé de persistance, distincte de `kPrefOnboardingVu` : voir la préparation
/// n'est pas voir la présentation, et fusionner les deux drapeaux empêcherait
/// d'activer l'une sans l'autre.
const String kPrefPreparationFaite = 'preparation_faite';

/// Vrai si la préparation n'a jamais été menée à son terme.
///
/// Défaut `false` (« déjà fait ») en cas d'erreur de lecture : même principe
/// que `onboardingARegarder` — mieux vaut manquer la préparation qu'imposer un
/// plein écran à chaque démarrage si le stockage est indisponible.
///
/// ── REJOUÉE À CHAQUE LANCEMENT PENDANT LA RECETTE (2026-09-13) ─────────────
///
/// Demande utilisateur : « je veux que l'onboarding se lance tout le temps,
/// période de recette ». Pendant qu'on met au point la préparation et la visite
/// guidée, devoir effacer les préférences du téléphone à chaque essai est une
/// friction absurde -- et on finit par tester autre chose que ce qu'on croit.
///
/// ⚠️ POURQUOI `!kReleaseMode` ET PAS UNE CONSTANTE À `true` : une constante
/// qu'il faut penser à repasser à `false` avant publication FINIT par partir
/// oubliée. Ici, la bascule est portée par le MODE DE COMPILATION : elle est
/// vraie pour tous les builds de développement (ceux qu'on installe tous les
/// jours, cf. la règle projet « builds en debug par défaut ») et
/// structurellement fausse pour un build release. Le défaut ne PEUT PAS
/// atteindre le Play Store -- ce n'est pas une discipline, c'est une
/// impossibilité.
///
/// Conséquence à connaître : en debug, `kPrefPreparationFaite` est toujours
/// écrit mais jamais relu. Si un jour on veut vérifier le comportement RÉEL du
/// premier lancement (l'écran ne doit apparaître qu'une fois), il faut un build
/// profile ou release -- pas un debug.
const bool _kRejouerAChaqueLancement = !kReleaseMode;

/// Le même interrupteur, exposé pour les autres morceaux de la chaîne de
/// démarrage (la démonstration de récitation, cf. `main.dart`).
///
/// Un SEUL point de vérité : si un jour on veut couper la recette, on coupe
/// ici et tout suit. Deux constantes séparées finiraient par diverger, et on
/// se retrouverait avec une démo qui s'ouvre toute seule alors qu'on croit
/// avoir tout éteint.
bool get preparationEnRecette => _kRejouerAChaqueLancement;

Future<bool> preparationARegarder() async {
  if (_kRejouerAChaqueLancement) return true;
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
  static const _nbEtapes = 4;

  /// Empeche deux ouvertures simultanees si on tape deux fois.
  bool _chargementEssai = false;

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
      // ── L'ECRAN AVAIT ETE JUGE « MOCHE » (2026-09-13) ──────────────────
      //
      // Retour utilisateur sans detour. Trois choses manquaient, et ce sont
      // les memes qui font l'identite du reste de l'application :
      //   * un FOND qui vit -- degrade vert profond + le filigrane deja
      //     utilise sur l'accueil et la couverture du Mushaf, au lieu d'un
      //     aplat ;
      //   * l'ORNEMENT dore (filet, losange) qui signe chaque en-tete ;
      //   * des cartes en PARCHEMIN clair sur le vert, comme une page posee
      //     sur la reliure, plutot que des rectangles vert sur vert qui se
      //     distinguaient a peine les uns des autres.
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.green900, AppColors.green800],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: QuranPatternBackground(opacity: 0.07),
          ),
          SafeArea(
        child: Column(
          children: [
            _entete(t),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: switch (_etape) {
                  0 => _etapeLangueEtRiwaya(t),
                  1 => _etapeEcriture(t),
                  2 => _etapeOptions(t),
                  _ => _etapeEssais(t),
                },
              ),
            ),
            _pied(t),
          ],
        ),
          ),
        ],
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
                fontSize: 30,
                color: AppColors.cream,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            // Le filet a losange : c'est la signature visuelle de l'accueil et
            // de la couverture. Le reprendre ici fait de la preparation une
            // PAGE DE CET OUVRAGE, pas un formulaire de configuration pose
            // devant.
            const _FiletDore(),
            const SizedBox(height: 14),
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
        // ── CE QUE WARSH N'A PAS ENCORE (2026-09-14, demande utilisateur) ──
        //
        // « dans l'onboarding, au choix de Warsh, une information que l'IA
        // n'est pas encore entraînée sur les règles de tajwid Warsh ».
        //
        // POURQUOI ELLE EST TOUJOURS VISIBLE, et pas seulement une fois Warsh
        // coché : une limite qu'on découvre APRÈS avoir choisi n'aide plus à
        // choisir. Elle est posée sous la carte, au moment où la question se
        // pose.
        //
        // ELLE DIT AUSSI CE QUI MARCHE. « L'IA n'est pas entraînée sur Warsh »
        // tout court laisserait croire que la récitation entière y est
        // inutilisable — c'est faux : le texte Warsh est servi, les mots sont
        // suivis et corrigés (cf. le correctif du YEH BARREE, qui a porté le
        // squelette reconnu de 94,29 % à 98,06 %). Seule la tête de TAJWID est
        // entraînée sur Ḥafṣ. Une mise en garde trop large coûte un usage
        // qu'elle n'avait pas à décourager.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: AppColors.brassLight.withAlpha(200)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  t.preparationRiwayaWarshNote,
                  style: TextStyle(
                    color: AppColors.cream.withAlpha(165),
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
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


  // ── ÉTAPE 4 : ESSAYER, PLUTÔT QU'ÉCOUTER RACONTER (2026-09-14) ───────────
  //
  // Demande utilisateur, après avoir vu la visite guidée narrée : « sinon
  // c'est compliqué, on oublie et on va faire plutôt un YouTube — à moins
  // d'avoir des exemples de ce que l'app est capable de faire dans
  // l'onboarding, il y a des accès directs à la récitation, mémoriser, puis
  // tajwid, puis jeux, qu'il teste tout, par exemple sur Qul huwa Allahu
  // ahad ».
  //
  // C'est un meilleur principe que le tour narré, et il faut le dire : 57
  // étapes qui COMMENTENT l'application valent moins que quatre boutons qui la
  // font ESSAYER. Le guide n'est pas supprimé pour autant (il reste dans
  // Réglages → Découvrir), mais il n'est plus la seule porte d'entrée.
  //
  // ⚠️ CES BOUTONS OUVRENT LES VRAIS ÉCRANS, pas des aperçus. C'est tout
  // l'intérêt : le micro EST demandé quand on choisit « Réciter », parce que
  // l'utilisateur vient de le décider en appuyant. La règle qu'on s'est donnée
  // n'a jamais été « ne jamais demander le micro » — elle était « jamais par
  // une main simulée, toujours sur un geste de l'utilisateur ». Ici le geste
  // est réel, donc la demande est légitime.
  //
  // AL-IKHLĀṢ (112) et pas une sourate au hasard : quatre versets, quinze
  // mots. C'est assez court pour qu'un essai aille jusqu'au bout en moins
  // d'une minute — condition pour que quelqu'un tente les quatre — et c'est la
  // sourate que presque tout le monde connaît par cœur, donc la récitation et
  // la mémorisation ont une chance de réussir dès le premier essai. Une
  // sourate longue ou peu connue transformerait la découverte en échec.
  static const _sourateEssai = 112;

  /// Sourate de l'ESSAI D'ENTRAÎNEMENT : An-Nisāʾ (4) — cf. la tuile
  /// correspondante pour le pourquoi, et [_versetsEntrainement] pour la borne.
  static const _sourateEntrainement = 4;

  /// ⚠️ ON N'EN PREND QUE LE PREMIER VERSET.
  ///
  /// An-Nisāʾ compte 176 versets : la charger entière pour un essai de
  /// découverte donnerait une session sans fin, à l'opposé de ce que cet écran
  /// promet (« quelques minutes, tu peux revenir ensuite »). Son verset 1
  /// suffit largement — il est long, donc il SE DÉCOUPE, et c'est précisément
  /// ce qu'on veut montrer ici.
  static const _versetsEntrainement = 1;

  /// Charge la sourate d'essai puis ouvre l'écran demandé.
  ///
  /// Le chargement est fait ICI et non dans chaque écran : les quatre en ont
  /// besoin, et `QuranApi` met déjà la sourate en cache — le deuxième essai
  /// est donc immédiat.
  /// [surah] permet à une tuile de s'essayer sur une AUTRE sourate que la
  /// sourate de découverte (2026-09-14) : l'entraînement se fait sur An-Nās,
  /// cf. la tuile correspondante pour le pourquoi.
  Future<void> _essayer(
      BuildContext context, Widget Function(Surah, List<Verse>) ecran,
      {int? surah}) async {
    if (_chargementEssai) return;
    setState(() => _chargementEssai = true);
    try {
      final numero = surah ?? _sourateEssai;
      final sourates = await QuranApi.fetchSurahs();
      final versets = await QuranApi.fetchVerses(numero);
      final sourate = sourates.firstWhere((s) => s.number == numero,
          orElse: () => sourates.first);
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => ecran(sourate, versets)),
      );
    } catch (_) {
      // Un essai qui ne peut pas charger le texte ne doit pas casser la
      // préparation : on revient sans rien dire, l'utilisateur peut passer.
    } finally {
      if (mounted) setState(() => _chargementEssai = false);
    }
  }

  Widget _etapeEssais(AppLocalizations t) {
    return ListView(
      key: const ValueKey(3),
      children: [
        _titreEtape(t.preparationEssaisTitre, t.preparationEssaisSous),
        // ── LE TAJWID EN PREMIER (2026-09-14, demande utilisateur) ──────
        //
        // « dans essaie onboarding commence par tajwid ». C'est le bon ordre :
        // le mode tajwid ne peint que DEUX couleurs et ne répond qu'à une
        // question (« la règle attendue a-t-elle été faite ? »). La récitation
        // complète en peint cinq. On montre donc le plus simple d'abord.
        //
        // ⚠️ LES CONSIGNES DÉCRIVENT LE COMPORTEMENT RÉEL, vérifié dans
        // `karaoke_recitation_screen` (blocs « LE TAJWID, ET RIEN QUE LE
        // TAJWID » et le switch principal) et dans
        // `memorization_game_screen`. Une consigne fausse est pire que pas de
        // consigne : elle apprend le mauvais geste. Ne pas les retoucher sans
        // relire ces endroits.
        _tuileEssai(
          emoji: '🎨',
          titre: t.preparationEssaiTajwid,
          sous: t.preparationEssaiTajwidSous,
          consigne: t.preparationConsigneTajwid,
          onTap: () => _essayer(context,
              (s, v) => KaraokeRecitationScreen(verses: v, modeTajwid: true)),
        ),
        _tuileEssai(
          emoji: '🎙️',
          titre: t.preparationEssaiReciter,
          sous: t.preparationEssaiReciterSous,
          consigne: t.preparationConsigneReciter,
          onTap: () => _essayer(
              context, (s, v) => KaraokeRecitationScreen(verses: v)),
        ),
        // ── CETTE TUILE OUVRE L'ENTRAINEMENT, PAS LE JEU (2026-09-14) ────
        //
        // Elle lançait `MemorizationGameScreen` (le QCM) tout en s'appelant
        // « Mémoriser » : c'est le mélange que l'utilisateur a signalé --
        // « tu mélanges mémoriser avec le jeu d'enchaînement ».
        //
        // LES DEUX MODES SONT DISTINCTS, et ce n'est pas qu'une affaire de nom :
        //   - ENTRAINEMENT (`CoachScreen`) : on écoute un passage, on le répète
        //     à voix haute, le palier grandit à chaque réussite. C'est le حفظ.
        //   - JEU D'ENCHAINEMENT (`MemorizationGameScreen`) : un QCM où l'on
        //     retrouve le mot suivant parmi plusieurs. C'est لعبة التسلسل.
        // Le QCM n'est pas retiré de l'application (décision utilisateur :
        // « QCM c'est une autre, à laisser ») -- il reste accessible par la
        // barre du Mushaf. Il n'est simplement plus ce que cette tuile propose
        // d'essayer.
        _tuileEssai(
          emoji: '🧠',
          titre: t.preparationEssaiMemoriser,
          sous: t.preparationEssaiMemoriserSous,
          consigne: t.preparationConsigneMemoriser,
          // ── AN-NISĀʾ (4) ET NON AL-IKHLĀṢ (2026-09-14) ────────────────
          // Demande utilisateur : « pour l'entraînement, fais sourate
          // An-Nisāʾ, plus grand, on comprend que ça permet de couper ».
          //
          // Le mécanisme de cet écran est le PALIER : un verset est découpé,
          // puis le morceau s'allonge à chaque réussite. Sur les versets de
          // deux ou trois mots d'Al-Ikhlāṣ, IL N'Y A RIEN À DÉCOUPER —
          // l'écran affichait donc « Palier 1/5 » sans qu'on voie ce qu'il
          // faisait. Le verset 4:1 est long : le découpage devient visible,
          // et c'est toute la raison de ce changement.
          //
          // Borné au PREMIER verset (cf. `_versetsEntrainement`) : la sourate
          // en compte 176.
          onTap: () => _essayer(
              context,
              (s, v) => CoachScreen(
                  verses: v.take(_versetsEntrainement).toList()),
              surah: _sourateEntrainement),
        ),
        // ── LE JEU RESTE DANS L'ESSAI (2026-09-14) ───────────────────────
        // « mais faut garder le jeu d'enchaînement ». Il avait disparu de cet
        // écran quand la tuile 🧠 est passée à l'entraînement ; il revient
        // avec SES PROPRES libellés — c'est la séparation demandée : le حفظ
        // d'un côté, لعبة التسلسل de l'autre, chacun nommé pour ce qu'il est.
        _tuileEssai(
          emoji: '🧩',
          titre: t.preparationEssaiJeu,
          sous: t.preparationEssaiJeuSous,
          consigne: t.preparationConsigneJeu,
          onTap: () => _essayer(
              context, (s, v) => MemorizationGameScreen(surah: s, verses: v)),
        ),
        // ── « LIRE ET ÉCOUTER » RETIRÉ DE L'ESSAI (2026-09-14) ───────────
        //
        // Demande utilisateur : « enlève lire et écouter dans l'essai ».
        //
        // C'était la seule tuile qui ne faisait RIEN ESSAYER : ouvrir le
        // mushaf et faire défiler, c'est ce que l'application fait d'elle-même
        // dès qu'on la lance — il n'y a rien à découvrir là que le premier
        // écran ne montre déjà. Les trois autres proposent chacune un geste
        // que l'utilisateur ne devinerait pas seul.
        //
        // Les clés (`preparationEssaiLire`, `…LireSous`,
        // `preparationConsigneLire`) restent définies dans les trois langues :
        // la tuile tient en six lignes si elle doit revenir.
        //   _tuileEssai(emoji: '📖', titre: t.preparationEssaiLire, …
        //       onTap: () => _essayer(context, (s, v) => MushafScreen(surah: s))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            t.preparationEssaisNote,
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

  Widget _tuileEssai({
    required String emoji,
    required String titre,
    required String sous,
    /// Ce qu'il faut FAIRE, et ce que l'écran répondra. C'est la partie utile :
    /// le titre dit quelle fonction c'est, la consigne dit comment s'en servir.
    required String consigne,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Material(
          color: AppColors.cream.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _chargementEssai ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cream.withAlpha(38)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre,
                            style: const TextStyle(
                              fontSize: 15.5,
                              color: AppColors.cream,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 3),
                        Text(sous,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.cream.withAlpha(165),
                              height: 1.35,
                            )),
                        const SizedBox(height: 8),
                        // Détachée par un filet doré : c'est une CONSIGNE, pas
                        // la suite du sous-titre. Sans cette rupture les trois
                        // lignes se lisent comme un seul paragraphe et on ne
                        // voit plus ce qu'on doit faire.
                        Container(
                          padding: const EdgeInsetsDirectional.only(start: 9),
                          decoration: const BoxDecoration(
                            border: BorderDirectional(
                              start: BorderSide(
                                  color: AppColors.brass, width: 2),
                            ),
                          ),
                          child: Text(consigne,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.brassLight.withAlpha(225),
                                height: 1.45,
                              )),
                        ),
                      ],
                    ),
                  ),
                  // Alignée en haut depuis que la tuile porte trois lignes :
                  // centrée, elle flottait au milieu d'un pavé de texte.
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppColors.brass, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _carte({
    required String titre,
    String? sous,
    required bool choisi,
    required VoidCallback onTap,
    bool arabe = false,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Builder(builder: (context) {
        // Une seule variable pour l'encre : sur creme pleine il faut de
        // l'encre sombre, sur le vert translucide il faut du creme. Le calculer
        // ici evite de repeter la condition a chaque Text -- et d'en oublier
        // un, ce qui produirait du texte creme sur fond creme, invisible.
        final encre = choisi ? AppColors.ink : AppColors.cream;
        return Material(
          // Parchemin sur la reliure : la carte choisie passe en creme pleine,
          // les autres restent en vert clair translucide. Le contraste porte
          // donc sur la MATIERE et pas seulement sur un liseré -- avant, deux
          // cartes vert-sur-vert ne se distinguaient qu'a la bordure, ce qui
          // se voyait mal et faisait « plat ».
          color: choisi ? AppColors.cream : AppColors.cream.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          elevation: choisi ? 3 : 0,
          shadowColor: Colors.black54,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: choisi
                      ? AppColors.brass
                      : AppColors.cream.withAlpha(38),
                  width: choisi ? 1.6 : 1,
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
                                  fontSize: 21,
                                  color: encre,
                                  fontWeight: FontWeight.w600,
                                )
                              : TextStyle(
                                  fontSize: 15.5,
                                  color: encre,
                                  fontWeight: FontWeight.w700,
                                ),
                        ),
                        if (sous != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            sous,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: encre.withAlpha(165),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (choisi)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.brass, size: 23),
                ],
              ),
            ),
          ),
        );
        }),
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
          // ── POLICE FORCEE (2026-09-13) ──────────────────────────────────
          //
          // Defaut vu a l'ecran : « Mode sombre » et « Couleurs du tajwid »
          // s'affichaient dans la police ARABE decorative (Scheherazade), au
          // milieu d'un ecran en police d'interface. Cause : un `ListTile` prend
          // son style dans le `TextTheme` de l'application, dont la famille par
          // defaut est celle du texte coranique. Les `Text` voisins n'etaient
          // pas touches parce qu'ils declarent leur style eux-memes.
          //
          // On nomme donc la police ici. Ne pas se contenter d'une taille : le
          // defaut ne vient pas de la taille, il vient de la FAMILLE.
          title: Text(
            titre,
            style: GoogleFonts.manrope(
              color: AppColors.cream,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          activeThumbColor: AppColors.green900,
          activeTrackColor: AppColors.brass,
          inactiveThumbColor: AppColors.cream,
          inactiveTrackColor: AppColors.cream.withAlpha(40),
          tileColor: AppColors.cream.withAlpha(22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.cream.withAlpha(38)),
          ),
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


/// Le filet doré à losange qui souligne le titre.
///
/// Repris tel quel de l'accueil et de la couverture du Mushaf : c'est la
/// signature visuelle de l'application. Redessiné ici plutôt qu'importé parce
/// que l'original (`_TitleRule`, `surah_list_screen.dart`) est privé à son
/// fichier — le dupliquer est le moindre mal tant que personne n'a besoin d'un
/// troisième exemplaire ; au troisième, il faudra l'extraire dans `widgets/`.
class _FiletDore extends StatelessWidget {
  const _FiletDore();

  @override
  Widget build(BuildContext context) {
    Widget trait() => Container(
          width: 52,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brass.withAlpha(0),
                AppColors.brass.withAlpha(190),
              ],
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        trait(),
        const SizedBox(width: 7),
        Transform.rotate(
          angle: 0.785398, // 45° : un carré posé sur la pointe = le losange
          child: Container(width: 6, height: 6, color: AppColors.brass),
        ),
        const SizedBox(width: 7),
        // Le second trait est le miroir du premier : sans le retournement, le
        // dégradé irait dans le même sens des deux côtés et l'ornement
        // paraîtrait glisser vers la droite.
        Transform.flip(flipX: true, child: trait()),
      ],
    );
  }
}
