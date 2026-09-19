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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/riwaya.dart';
import '../models/judgement_options.dart';
import '../providers/app_settings_provider.dart';
import '../providers/judgement_provider.dart';
import '../providers/player_provider.dart';
import '../models/reciter.dart';
import '../widgets/tajweed_text.dart';

import '../models/verse.dart';
import '../services/quran_api.dart';
import 'karaoke_recitation_screen.dart';
import 'coach_screen.dart';
import 'memorization_game_screen.dart';
import 'mushaf_maquette_screen.dart';
import 'tajwid_rules_screen.dart' show PresetRow;
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
// ── LA PREPARATION NE SE JOUE QU'UNE FOIS (2026-09-14) ────────────────────
//
// Demande utilisateur : « maintenant l'onboarding doit fonctionner qu'une seule
// fois, au demarrage, la premiere fois de l'application ».
//
// ETAIT `!kReleaseMode` depuis le 2026-09-13, pour la recette : « je veux que
// l'onboarding se lance tout le temps, periode de recette ». La periode est
// finie -- l'ecran se comporte donc partout comme il se comportera chez les
// gens, et `kPrefPreparationFaite` redevient ce qui decide.
//
// ⚠️ CONSEQUENCE IMMEDIATE SUR UN TELEPHONE DE DEVELOPPEMENT : la preference a
// deja ete ecrite des dizaines de fois pendant la recette, donc la preparation
// NE S'AFFICHERA PLUS. Pour la revoir, il faut effacer les donnees de
// l'application (Parametres Android -> Stockage -> Effacer les donnees), ou
// desinstaller puis reinstaller. Ce n'est pas un defaut, c'est exactement ce
// que « une seule fois » veut dire.
//
// Le commentaire qui suit explique pourquoi la bascule etait portee par le mode
// de compilation ; il reste vrai le jour ou l'on rouvrirait une recette.
const bool _kRejouerAChaqueLancement = false;

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

  /// ── QUATRE ETAPES, PLUS CINQ (2026-09-14, demande utilisateur) ───────────
  ///
  /// « le mode enfant peut s'essayer avec l'entrainement, c'est bon, c'est
  /// deja fait ». La 5e etape existait pour faire essayer le mode enfant ; ce
  /// mode se choisit desormais dans la fenetre de l'entrainement, parmi les
  /// trois (cf. `choixDuMode`). Garder une etape entiere pour un choix devenu
  /// disponible deux ecrans plus tot, c'est faire recommencer l'essai pour
  /// changer un reglage.
  ///
  /// `_etapeEnfant` N'EST PAS SUPPRIMEE : elle reste la branche par defaut du
  /// `switch` ci-dessous, simplement plus atteignable. La remettre dans le
  /// parcours tient a ce seul nombre.
  /// ── UNE ETAPE POUR LE RECITATEUR (2026-09-14, demande utilisateur) ──────
  ///
  /// « on a oublie ce choix dans l'onboarding, de choisir le recitateur »,
  /// puis, sur sa place : « plutot apres le choix du texte ». C'est le bon
  /// ordre et il se raisonne : on choisit d'abord CE QU'ON LIT (la riwaya,
  /// puis l'ecriture), ensuite CE QU'ON ENTEND. Demander la voix avant de
  /// savoir quel texte on suit obligerait a y revenir des que la riwaya
  /// change, puisque la liste des recitateurs en depend.
  ///
  /// Le parcours repasse donc a cinq etapes -- ce n'est PAS le retour de
  /// l'etape « Mode enfant » retiree le meme jour (cf. `_etapeEnfant`).
  static const _nbEtapes = 5;

  // ── LE BALAYAGE AUTOMATIQUE A ÉTÉ RETIRÉ (2026-09-18) ──────────────────
  //
  // Demande utilisateur : « enlève dans l'onboarding le changement programmé,
  // c'est perturbant ». Tout le mécanisme est parti : le minuteur, le halo qui
  // se déplaçait de carte en carte, et les effets qu'il appliquait au passage.
  //
  // CE QUI AVAIT ÉTÉ CONSTRUIT, ET POURQUOI ON NE LE REFAIT PAS À L'IDENTIQUE
  // — trace des trois versions successives du 2026-09-14 :
  //
  //   1. « en attendant que le user choisisse, quand il y a plusieurs choix,
  //      il y a un balayage auto » — un halo se déplaçait pour dire qu'il y
  //      avait là quelque chose à choisir, sans rien changer d'autre. Verdict
  //      de l'utilisateur : « mais le balayage ACTIF !! sinon ça sert à rien,
  //      il doit modifier ou changer le texte ou lancer les audio ».
  //   2. Le balayage a donc APPLIQUÉ chaque effet : l'interface basculait de
  //      langue toutes les 2,5 s, l'aperçu changeait de lettres puis de fond,
  //      chaque voix se faisait entendre à tour de rôle. Le réglage persisté
  //      n'était jamais touché — ce qui avait été emprunté était rendu si on
  //      quittait l'étape sans rien choisir (`_rendreCeQuiEtaitLa`).
  //   3. L'étape du récitateur en a été retirée le jour même : « c'est
  //      compliqué pour le choix de récitateur, c'est pas intéressant » —
  //      huit secondes par voix font une démonstration qu'il faut SUBIR avant
  //      de pouvoir choisir.
  //
  // ⇒ Le 2026-09-18, la même objection s'étend aux trois étapes restantes : un
  // écran de préparation dont le contenu bouge tout seul empêche de lire ce
  // qu'on est en train de choisir. La version 1 (halo seul) n'est PAS le repli
  // à appliquer : elle avait déjà été rejetée en son temps. Ne réintroduire ni
  // l'une ni l'autre sans demande explicite.

  /// Empeche deux ouvertures simultanees si on tape deux fois.
  bool _chargementEssai = false;
  bool _explicationOuverte = false;
  bool get _occupe => _chargementEssai || _explicationOuverte;

  /// Le verset d'aperçu : la Fātiḥa 1:2, choisie parce qu'elle porte ce qui
  /// distingue VRAIMENT deux écritures — un alif suscrit, une shadda avec sa
  /// voyelle, un madd, et le lām-alif. Un texte sans diacritiques rendrait
  /// toutes les polices identiques et l'aperçu ne servirait à rien.
  static const _apercu = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ';

  @override
  void dispose() {
    _couperEcoute();
    super.dispose();
  }

  void _suivant() {
    _couperEcoute();
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
                  2 => _etapeReciteur(t),
                  3 => _etapeOptions(t),
                  4 => _etapeEssais(t),
                  _ => _etapeEnfant(t),
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
              style: AppTheme.readableUi(context, const TextStyle(
                color: AppColors.cream,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              )),
            ),
            const SizedBox(height: 4),
            Text(
              sous,
              style: AppTheme.readableUi(context, TextStyle(
                color: AppColors.cream.withAlpha(170),
                fontSize: 13,
                height: 1.4,
              )),
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
        for (var i = 0; i < kSupportedAppLocales.length; i++)
          _carte(
            titre: noms[kSupportedAppLocales[i]] ?? kSupportedAppLocales[i],
            choisi: locale == kSupportedAppLocales[i],
            onTap: () {
              ref
                  .read(appLocaleProvider.notifier)
                  .set(kSupportedAppLocales[i]);
            },
            arabe: kSupportedAppLocales[i] == 'ar',
          ),
        const SizedBox(height: 10),
        _titreEtape(t.settingsRiwayaTitle, t.preparationRiwayaSous),
        _carte(
          titre: 'حفص — Ḥafṣ',
          sous: t.settingsRiwayaHafs,
          choisi: riwaya == Riwaya.hafs,
          onTap: () {
            _choisirRiwaya(Riwaya.hafs);
          },
        ),
        _carte(
          titre: 'ورش — Warsh',
          sous: t.settingsRiwayaWarsh,
          choisi: riwaya == Riwaya.warsh,
          onTap: () {
            _choisirRiwaya(Riwaya.warsh);
          },
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
    // L'apercu montre l'ecriture CHOISIE, et elle seule (cf. le retrait du
    // balayage plus haut) : il change au tap, jamais tout seul.
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
                onTap: () {
                  ref
                      .read(policeMushafPageProvider.notifier)
                      .definir(e.famille);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Change la riwāya ET ramène le récitateur dedans.
  ///
  /// ── LE RÉCITATEUR NE SUIVAIT PAS (2026-09-14, demande utilisateur) ───────
  /// « pour le Warsh, mets récitateur Warsh par défaut ». Il l'était déjà
  /// partout AILLEURS : `settings_screen.dart` appelle `accorderALaRiwaya()`
  /// juste après avoir posé la riwāya, et `PlayerNotifier` le fait au
  /// démarrage. Cet écran-ci, écrit après, ne l'appelait pas — choisir Warsh
  /// au premier lancement laissait donc Al-Afasy, une voix Ḥafṣ, sur du texte
  /// Warsh.
  ///
  /// ⚠️ LA RÈGLE VIT À TROIS ENDROITS, ET C'EST LA CAUSE DU DÉFAUT. Elle
  /// devrait tenir dans `RiwayaSettingNotifier.set()`, mais ce notifier n'a
  /// pas de `ref` et ne peut pas atteindre `playerProvider` ; l'y faire
  /// descendre est un chantier à part. En attendant : tout nouvel endroit qui
  /// pose la riwāya doit appeler `accorderALaRiwaya()` juste après.
  void _choisirRiwaya(Riwaya valeur) {
    ref.read(riwayaProvider.notifier).set(valeur);
    ref.read(playerProvider.notifier).accorderALaRiwaya();
  }

  // ── ÉTAPE 3 : le récitateur ───────────────────────────────────────────────

  /// La liste est FILTRÉE PAR LA RIWĀYA (`Reciter.pour`) : en Warsh, seules les
  /// voix Warsh apparaissent. Ce n'est pas un confort, c'est la même exigence
  /// que `PlayerNotifier.accorderALaRiwaya` — un récitateur Hafs sur du texte
  /// Warsh fait entendre autre chose que ce qui est écrit, et la correction
  /// d'un mot enseignerait alors la mauvaise prononciation.
  ///
  /// `ref.watch(riwayaProvider)` et non `QuranApi.riwaya` : revenir à l'étape 1
  /// pour changer de riwāya doit refaire cette liste, et un champ statique ne
  /// déclenche aucune reconstruction.
  Widget _etapeReciteur(AppLocalizations t) {
    final riwaya = ref.watch(riwayaProvider);
    final courant = ref.watch(playerProvider).reciter;
    final voix = Reciter.pour(riwaya);
    final enArabe = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      key: const ValueKey(2),
      children: [
        _titreEtape(t.reciterSelectTitle, t.preparationReciteurSous),
        Expanded(
          child: ListView.builder(
            itemCount: voix.length,
            itemBuilder: (_, i) {
              final r = voix[i];
              return _carte(
                titre: enArabe ? r.nameAr : r.nameFr,
                // Le style (Murattal / Mujawwad) est ce qui distingue vraiment
                // deux voix à l'oreille ; en arabe on donne l'autre graphie du
                // nom, qui sert de repère à qui connaît le récitateur.
                sous: enArabe ? '${r.nameFr} · ${r.style}' : r.style,
                choisi: r.id == courant.id,
                onTap: () {
                  _ecouterUnExtrait(r);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── ÉTAPE 3 : quelques options, aucune imposée ────────────────────────────

  /// ── LES COULEURS SE MONTRENT, ELLES NE SE DECRIVENT PAS (2026-09-14) ────
  ///
  /// Demande utilisateur : « les couleurs du style, et le toggle tajwid ou pas
  /// couleur : donne un exemple comme tu as fait pour le texte ».
  ///
  /// L'etape n'offrait qu'un interrupteur « Mode sombre » et un interrupteur
  /// « Couleurs du tajwid » : deux questions dont on ne peut PAS connaitre la
  /// reponse avant d'avoir vu le resultat. C'est le meme raisonnement que
  /// l'apercu de l'ecriture, et la meme exigence -- « un apercu REEL » : ce
  /// qu'on voit ici passe par `tajweedSpansPerWord`, le rendu exact de la page
  /// du Mushaf, sur le VRAI verset 1:2 lu dans l'asset local. Pas une image,
  /// pas une imitation.
  ///
  /// LES TROIS FONDS sont ceux de `MushafScreen` (papier / kindleBg /
  /// sombreBg), pilotes par le MEME couple de reglages que la feuille de
  /// lecture (`kindleModeProvider` + `modeSombreProvider`) -- deux booleens
  /// pour trois etats, c'est l'existant, on ne le double pas ici.
  Widget _etapeOptions(AppLocalizations t) {
    final sombre = ref.watch(modeSombreProvider);
    final kindle = ref.watch(kindleModeProvider);
    final tajwid = ref.watch(tajwidMushafPageProvider);
    final famille = ref.watch(policeMushafPageProvider);
    final riwaya = ref.watch(riwayaProvider);
    // Trois fonds, dans l'ordre des pastilles : papier, kindle, sombre.
    final iFond = sombre ? 2 : (kindle ? 1 : 0);
    final fond = [
      AppColors.mushafPapier,
      AppColors.kindleBg,
      AppColors.sombreBg,
    ][iFond];
    final encre = iFond == 2 ? AppColors.cream : AppColors.ink;
    return ListView(
      key: const ValueKey(3),
      children: [
        _titreEtape(t.preparationOptionsTitre, t.preparationOptionsSous),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: BoxDecoration(
            color: fond,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brass, width: 1.2),
          ),
          child: _ApercuCouleurs(
            futur: _apercuPour(riwaya),
            repli: _apercu,
            tajwid: tajwid,
            sombre: sombre,
            style: styleEcriture(
              ecriturePour(famille),
              taille: 30,
              interligne: 1.9,
              couleur: encre,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Les trois fonds, montres et non nommes : une pastille dit sa couleur
        // mieux qu'un mot (cf. `_ThemeSwatch` dans la feuille de lecture, dont
        // ceci reprend le principe et les trois memes couleurs).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pastilleFond(
              couleur: AppColors.mushafPapier,
              choisi: !kindle && !sombre,
              onTap: () {
                ref.read(kindleModeProvider.notifier).set(false);
                ref.read(modeSombreProvider.notifier).set(false);
              },
            ),
            _pastilleFond(
              couleur: AppColors.kindleBg,
              choisi: kindle && !sombre,
              onTap: () {
                ref.read(kindleModeProvider.notifier).set(true);
                ref.read(modeSombreProvider.notifier).set(false);
              },
            ),
            _pastilleFond(
              couleur: AppColors.sombreBg,
              choisi: sombre,
              onTap: () {
                ref.read(modeSombreProvider.notifier).set(true);
                ref.read(kindleModeProvider.notifier).set(false);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
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


  /// Choisit la voix ET la fait entendre, sur les deux premiers versets
  /// d'Al-Baqara.
  ///
  /// ── ON N'ENTEND PAS UN NOM (2026-09-14, demande utilisateur) ─────────────
  /// « au moins au clic on lance un verset, deux versets d'Al-Baqara, il doit
  /// écouter ». C'est la même exigence que l'aperçu de l'écriture et celui des
  /// couleurs, transposée à l'oreille : « Murattal » et un nom propre ne
  /// disent RIEN de ce qu'on va entendre pendant des heures de lecture. La
  /// seule façon de choisir une voix est de l'entendre.
  ///
  /// DEUX VERSETS et pas la sourate entière : `play` enchaîne la liste qu'on
  /// lui donne puis s'arrête. 2:1 (الم) est très court, seul il ne laisserait
  /// presque rien entendre ; 2:2 donne la phrase, le souffle et le rythme.
  ///
  /// Le texte vient de l'asset local, donc l'extrait existe hors ligne ; seul
  /// l'AUDIO peut manquer sans réseau, et `play` pose alors son propre état
  /// d'erreur -- on ne prétend pas avoir joué.
  /// ⚠️ ON COUPE AVANT DE CHARGER, ET LE DERNIER TAP GAGNE (2026-09-18).
  ///
  /// Constat utilisateur : « choisir récitateur, y a un problème, je change le
  /// récitateur, ancienne récitation continue » puis « faut arrêter et changer
  /// de suite ».
  ///
  /// LA CAUSE. La version précédente appelait `play` APRÈS un `await` réseau
  /// (`fetchVerses`) sans jamais arrêter ce qui jouait déjà : entre le tap et
  /// le premier son de la nouvelle voix, l'ancienne continuait — d'autant plus
  /// longtemps que le réseau était lent. Le `stop` existait pourtant, mais
  /// seulement au changement d'étape et à la fermeture, jamais entre deux voix
  /// de la MÊME étape, qui est précisément le geste qu'on fait ici.
  ///
  /// L'ORDRE COMPTE, et chaque ligne répond à un des deux mots de la demande :
  ///   `setReciter` d'abord  -> « changer de suite » : la carte se coche au
  ///                            doigt, sans attendre le réseau ;
  ///   `stop` ensuite, AWAIT -> « arrêter » : le silence se fait avant qu'on
  ///                            aille chercher quoi que ce soit.
  ///
  /// LE JETON. Taper trois voix de suite lançait trois chargements concurrents,
  /// et c'était le plus RAPIDE à revenir qui se faisait entendre — pas le
  /// dernier touché. Chaque essai prend donc un numéro ; un essai qui revient
  /// et n'est plus le dernier se retire sans jouer.
  Future<void> _ecouterUnExtrait(Reciter r) async {
    final jeton = ++_essaiEcoute;
    _lecteur.setReciter(r);
    await _lecteur.stop();
    if (!mounted || jeton != _essaiEcoute) return;
    try {
      final versets = await QuranApi.fetchVerses(2);
      if (!mounted || jeton != _essaiEcoute || versets.isEmpty) return;
      final extrait = versets.take(2).toList();
      await _lecteur.play(extrait.first, extrait, reciter: r);
    } catch (_) {
      // Sourate illisible : le choix du récitateur reste fait, il n'y a
      // simplement rien à écouter. Jamais bloquant.
    }
  }

  /// Numéro du dernier essai demandé (cf. « LE JETON » ci-dessus).
  int _essaiEcoute = 0;

  /// ⚠️ LE SON NE DOIT PAS SURVIVRE À L'ÉTAPE (2026-09-14).
  ///
  /// Même piège que l'audio de l'entraînement corrigé le matin même : un
  /// lecteur lancé depuis un écran continue tout seul si personne ne l'arrête.
  /// Ici c'est plus simple à voir -- on entend Al-Baqara par-dessus l'essai de
  /// récitation de l'étape suivante -- mais c'est la même faute. On coupe donc
  /// à CHAQUE changement d'étape et à la fermeture.
  ///
  /// `_lecteur` est capturé une fois, comme objet : `ref.read` dans `dispose()`
  /// n'est pas sûr, le notifier lui survit.
  late final PlayerNotifier _lecteur = ref.read(playerProvider.notifier);

  void _couperEcoute() {
    _lecteur.stop();
  }

  Widget _pastilleFond({
    required Color couleur,
    required bool choisi,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: couleur,
              shape: BoxShape.circle,
              border: Border.all(
                color: choisi ? AppColors.brass : AppColors.cream.withAlpha(60),
                width: choisi ? 3 : 1,
              ),
            ),
          ),
        ),
      );

  /// Le verset 1:2 avec son balisage tajwid, lu dans l'asset local.
  ///
  /// Mis en cache PAR RIWAYA : revenir a l'etape 1 pour passer en Warsh doit
  /// refaire l'apercu, sinon on montrerait le texte Hafs sous un reglage Warsh.
  /// `QuranApi.fetchVerses` lit `assets/data/quran_verses*.json` -- aucun
  /// reseau, donc l'apercu existe aussi au tout premier lancement hors ligne.
  Future<Verse?>? _futurApercu;
  Riwaya? _apercuRiwaya;

  Future<Verse?> _apercuPour(Riwaya riwaya) {
    if (_futurApercu != null && _apercuRiwaya == riwaya) return _futurApercu!;
    _apercuRiwaya = riwaya;
    return _futurApercu = () async {
      try {
        final versets = await QuranApi.fetchVerses(1);
        for (final v in versets) {
          if (v.ayahNumber == 2) return v;
        }
      } catch (_) {
        // L'apercu retombe sur le texte en dur : mieux vaut un apercu sans
        // couleurs qu'un cadre vide au premier lancement.
      }
      return null;
    }();
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
      {int? surah, JudgementPreset? preset}) async {
    if (_chargementEssai) return;
    setState(() => _chargementEssai = true);
    try {
      final numero = surah ?? _sourateEssai;
      final sourates = await QuranApi.fetchSurahs();
      final versets = await QuranApi.fetchVerses(numero);
      final sourate = sourates.firstWhere((s) => s.number == numero);
      if (!context.mounted) return;
      if (versets.isEmpty) throw StateError('Empty trial passage');
      Future<void> ouvrir() async {
        if (!context.mounted) return;
        final route = MaterialPageRoute<void>(
          builder: (_) => ecran(sourate, versets));
        await Navigator.of(context, rootNavigator: true).push(
          route,
        );
        // Keep the trial preset through the closing animation and disposal.
        await route.completed;
      }
      if (preset == null) {
        await ouvrir();
      } else {
        await ref.read(judgementOptionsProvider.notifier)
            .withTemporaryPreset(preset, ouvrir);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.preparationEssaiErreur),
        ));
      }
    } finally {
      if (mounted) setState(() => _chargementEssai = false);
    }
  }

  Future<void> _ouvrirMushafPapier() async {
    if (_chargementEssai) return;
    setState(() => _chargementEssai = true);
    try {
      await Navigator.of(context, rootNavigator: true).push<int>(
        MaterialPageRoute(builder: (_) => const MushafMaquetteScreen()),
      );
    } finally {
      if (mounted) setState(() => _chargementEssai = false);
    }
  }

  Future<void> _presenterEssai({
    required String titre,
    required String consigne,
    /// Montre les trois modes de verification (Tajwid / Adulte / Enfant) DANS
    /// la fenetre, selectionnables avant de lancer l'essai.
    ///
    /// ── POURQUOI SEULEMENT ICI (2026-09-14, demande utilisateur) ──────────
    /// « dans l'entrainement, avec les trois modes tajwid/adulte/enfant dans
    /// la fenetre, pour montrer, selectionnable ».
    ///
    /// L'entrainement est le seul essai ou le mode CHANGE ce qu'on entend
    /// reprocher a sa propre voix pendant tout un palier : enfant tolere les
    /// harakat et les lettres confusables, adulte non, tajwid ne juge que la
    /// regle attendue. Le decouvrir apres coup, c'est refaire le palier.
    /// Les autres essais n'en ont pas besoin : le tajwid impose deja son
    /// preset, le jeu d'enchainement est un QCM (aucun micro), et la lecture
    /// du mushaf ne juge rien.
    ///
    /// Le choix s'applique VRAIMENT, tout de suite, comme dans la feuille du
    /// Coach (`afficherFeuilleModes`) -- c'est un ecran de PREPARATION, on y
    /// regle l'application pour de bon, pas seulement le temps d'un essai.
    bool choixDuMode = false,
    required Future<void> Function() commencer,
  }) async {
    if (_occupe) return;
    setState(() => _explicationOuverte = true);
    bool? confirme;
    try {
      final t = AppLocalizations.of(context)!;
      confirme = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('preparation.trial.dialog'),
          backgroundColor: AppColors.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Row(
            children: [
              Expanded(child: Text(titre, style: GoogleFonts.manrope(
                fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.ink,
              ))),
              IconButton(
                tooltip: t.preparationFermerExplication,
                onPressed: () => Navigator.of(dialogContext).pop(false),
                icon: const Icon(Icons.close, color: AppColors.ink),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(consigne, style: AppTheme.readableUi(dialogContext, GoogleFonts.manrope(
                  fontSize: 16, height: 1.65, color: AppColors.ink,
                ))),
                if (choixDuMode) ...[
                  const SizedBox(height: 18),
                  Text(t.coachVerificationModeTooltip.toUpperCase(),
                      style: GoogleFonts.manrope(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkLight)),
                  const SizedBox(height: 8),
                  // `Consumer` et non le `ref` de l'ecran : une fenetre de
                  // dialogue est un sous-arbre a part, elle ne se reconstruit
                  // pas quand l'ecran qui l'a ouverte se reconstruit. Sans
                  // lui, la puce choisie ne se colorerait qu'a la fermeture.
                  Consumer(
                    builder: (_, refDialogue, _) => PresetRow(
                      current: refDialogue.watch(judgementOptionsProvider).preset,
                      notifier:
                          refDialogue.read(judgementOptionsProvider.notifier),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton.icon(
              key: const ValueKey('preparation.trial.start'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.green800,
                foregroundColor: AppColors.cream),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(t.preparationCommencerTest),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _explicationOuverte = false);
    }
    if (mounted && confirme == true) await commencer();
  }

  Widget _etapeEssais(AppLocalizations t) {
    return ListView(
      key: const ValueKey(4),
      children: [
        _titreEtape(t.preparationEssaisTitre, t.preparationEssaisSous),
        if (_chargementEssai)
          const LinearProgressIndicator(color: AppColors.brass),
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
          // Le mode se choisit AVANT le palier, pas apres (cf. `choixDuMode`).
          choixDuMode: true,
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
        // ── ORDRE DES CINQ TUILES (2026-09-14, demande utilisateur) ─────
        //
        // « commence entraînement avant réciter : mode tajwid, entraînement,
        // réciter, enchaînement, lecture mushaf ».
        //
        // L'ordre va du plus ENCADRÉ au plus libre, et c'est ce qui le rend
        // juste : le tajwid ne demande qu'une règle à la fois, l'entraînement
        // fait entendre le passage AVANT de le demander, et réciter n'offre
        // plus aucun appui -- on ouvre le micro sur un texte qu'on doit tenir
        // seul. Mettre ce dernier en deuxième, c'était demander l'exercice le
        // plus exposé à quelqu'un qui n'a encore rien vu de l'application.
        _tuileEssai(
          emoji: '🎙️',
          titre: t.preparationEssaiReciter,
          sous: t.preparationEssaiReciterSous,
          consigne: t.preparationConsigneReciter,
          onTap: () => _essayer(
              context, (s, v) => KaraokeRecitationScreen(verses: v)),
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
        // ChGPT: open the paper reader, not the scrolling Mushaf list.
        // Seule tuile SANS fenêtre explicative (2026-09-14, demande
        // utilisateur) : lire une page ne demande aucun geste à expliquer.
        // Cf. le paramètre `consigne` de `_tuileEssai`.
        _tuileEssai(
          icon: Icons.menu_book_rounded,
          titre: t.preparationEssaiMushaf,
          sous: t.preparationEssaiMushafSous,
          onTap: _ouvrirMushafPapier,
        ),
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

  Widget _etapeEnfant(AppLocalizations t) => ListView(
    key: const ValueKey('preparation.child'),
    children: [
      _titreEtape(t.preparationEnfantTitre, t.preparationEnfantSous),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Icon(Icons.family_restroom_rounded,
          size: 84, color: AppColors.brassLight),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 14,
          children: [
            for (final item in [
              (Icons.headphones_rounded, t.preparationEnfantEcouter),
              (Icons.mic_rounded, t.preparationEnfantRepeter),
              (Icons.favorite_border_rounded, t.preparationEnfantAccompagner),
            ])
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(item.$1, size: 24, color: AppColors.cream),
                const SizedBox(height: 6),
                Text(item.$2, style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.cream)),
              ]),
          ],
        ),
      ),
      if (_chargementEssai)
        const LinearProgressIndicator(color: AppColors.brass),
      _tuileEssai(
        icon: Icons.child_care_rounded,
        titre: t.preparationEssaiEnfant,
        sous: t.preparationEssaiEnfantSous,
        consigne: t.preparationConsigneEnfant,
        accent: true,
        onTap: () => _essayer(context,
          (s, v) => CoachScreen(verses: v), preset: JudgementPreset.enfant),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _tuileEssai({
    String? emoji,
    IconData? icon,
    bool accent = false,
    required String titre,
    required String sous,
    /// Ce qu'il faut FAIRE, et ce que l'écran répondra. C'est la partie utile :
    /// le titre dit quelle fonction c'est, la consigne dit comment s'en servir.
    ///
    /// ── `null` = ON OUVRE, SANS RIEN EXPLIQUER (2026-09-14, demande util.) ──
    /// « lecture mushaf : pas besoin d'une fenêtre explicative, ça ouvre
    /// directement le mushaf papier ». Il a raison, et la règle se formule :
    /// une consigne ne se justifie que si l'écran attend un GESTE qu'on ne
    /// devine pas — réciter à voix haute, viser une règle de tajwid, répondre
    /// à un QCM. Lire une page ne s'explique pas : on l'ouvre et on lit.
    /// La chaîne `preparationConsigneMushaf` reste définie dans les trois
    /// langues — rien n'est perdu si la tuile en redemande une un jour.
    String? consigne,
    /// Cf. `_presenterEssai` : les trois modes dans la fenetre, selectionnables.
    bool choixDuMode = false,
    required Future<void> Function() onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Material(
          color: accent ? AppColors.cream : AppColors.cream.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _occupe
                ? null
                : (consigne == null
                    // Pas de consigne : on ouvre, point. Le garde `_occupe`
                    // reste, lui -- deux ouvertures simultanées resteraient
                    // deux ouvertures simultanées.
                    ? onTap
                    : () => _presenterEssai(
                        titre: titre,
                        consigne: consigne,
                        choixDuMode: choixDuMode,
                        commencer: onTap)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cream.withAlpha(38)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null)
                    Icon(icon, size: 28,
                      color: accent ? AppColors.green800 : AppColors.brassLight)
                  else
                    Text(emoji!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre,
                            style: AppTheme.readableUi(context, TextStyle(
                              fontSize: 15.5,
                              color: accent ? AppColors.ink : AppColors.cream,
                              fontWeight: FontWeight.w700,
                            ))),
                        const SizedBox(height: 3),
                        Text(sous,
                            style: AppTheme.readableUi(context, TextStyle(
                              fontSize: 11.5,
                              color: accent ? AppColors.inkLight :
                                  AppColors.cream.withAlpha(165),
                              height: 1.35,
                            ))),
                      ],
                    ),
                  ),
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
        return AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
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
                  color:
                      choisi ? AppColors.brass : AppColors.cream.withAlpha(38),
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
                          style: AppTheme.readableUi(context, arabe
                              ? GoogleFonts.scheherazadeNew(
                                  fontSize: 21,
                                  color: encre,
                                  fontWeight: FontWeight.w600,
                                )
                              : TextStyle(
                                  fontSize: 15.5,
                                  color: encre,
                                  fontWeight: FontWeight.w700,
                                )),
                        ),
                        if (sous != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            sous,
                            style: AppTheme.readableUi(context, TextStyle(
                              fontSize: 11.5,
                              color: encre.withAlpha(165),
                              height: 1.35,
                            )),
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
        child: OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 4,
          children: [
            TextButton(
              // « Passer » est toujours disponible, y compris à la première
              // étape : les trois réglages ont des défauts corrects, et un
              // premier lancement qu'on ne peut pas quitter est une prise en
              // otage, pas une préparation.
              onPressed: _occupe ? null : () {
                _couperEcoute();
                marquerPreparationFaite();
                widget.onTermine();
              },
              child: Text(
                t.preparationPasser,
                style: TextStyle(color: AppColors.cream.withAlpha(160)),
              ),
            ),
            if (_etape > 0)
              TextButton(
                onPressed: _occupe
                    ? null
                    : () {
                        _couperEcoute();
                        setState(() => _etape--);
                      },
                child: Text(t.preparationRetour,
                    style: const TextStyle(color: AppColors.cream)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: AppColors.green900,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: _occupe ? null : _suivant,
              // « Fin » et non « Commencer » (2026-09-14) : ce bouton FERME
              // la preparation, il ne demarre rien. Il disait « Mode enfant »
              // tant qu'il menait a la 5e etape ; celle-ci est sortie du
              // parcours, le libelle devait suivre -- un bouton qui nomme une
              // destination qu'il n'a plus est un mensonge d'interface.
              child: Text(_etape + 1 >= _nbEtapes
                  ? t.preparationFin
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

/// L'aperçu des couleurs de l'étape Options : le vrai verset, le vrai rendu.
///
/// Séparé en widget parce qu'il attend un `Future` — un `FutureBuilder` posé
/// dans le corps de l'étape la ferait reconstruire à chaque changement de
/// réglage, et le verset serait rechargé pour rien à chaque bascule.
///
/// [repli] est le texte en dur utilisé tant que l'asset n'a pas répondu (ou
/// s'il échoue) : on montre alors la BONNE écriture sans les couleurs, plutôt
/// qu'un cadre vide. Ce qui manque est signalé par l'absence de couleur, pas
/// par un trou.
class _ApercuCouleurs extends StatelessWidget {
  final Future<Verse?> futur;
  final String repli;
  final bool tajwid;
  final bool sombre;
  final TextStyle style;

  const _ApercuCouleurs({
    required this.futur,
    required this.repli,
    required this.tajwid,
    required this.sombre,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Verse?>(
      future: futur,
      builder: (_, snap) {
        final v = snap.data;
        if (v == null || !tajwid) {
          return Text(
            v?.textUthmani ?? repli,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: style,
          );
        }
        // Le MÊME appel que la page du Mushaf (`_PageMushaf`) : les couleurs
        // vues ici sont celles qui seront lues, à la lettre près.
        final mots = tajweedSpansPerWord(
            v.textUthmani, v.textUthmaniTajweed, style,
            sombre: sombre);
        return RichText(
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          text: TextSpan(
            style: style,
            children: [
              for (var i = 0; i < mots.length; i++) ...[
                if (i > 0) TextSpan(text: ' ', style: style),
                ...mots[i],
              ],
            ],
          ),
        );
      },
    );
  }
}
