// Provider du système de vérification unifié -- REFONTE_IHM.md §1.
// Persistance SharedPreferences, même pattern que app_settings_provider.dart.

import 'dart:convert';
import 'app_settings_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/judgement_options.dart';
import '../models/riwaya.dart';

// Clé passée en _v2 le 2026-07-20 : les valeurs par défaut du preset « adulte »
// ont changé (strictHarakat true -> false, cf. judgement_options.dart). Sans ce
// changement de clé, un réglage DÉJÀ ENREGISTRÉ aurait été restauré tel quel et
// aurait masqué la nouvelle valeur -- l'utilisateur aurait testé l'ancien
// comportement en croyant tester le nouveau, et la recette n'aurait rien voulu
// dire. Effet de bord assumé et signalé : la sélection de règles personnalisée
// repart à vide (elles ne faisaient de toute façon que plafonner des verts en
// orange, sans rien vérifier -- cf. audit du même jour).
//
// Repassée en _v3 le 2026-07-20 nuit : même raison, cette fois pour
// useGopScoring (défaut true -> false, cf. judgement_options.dart) -- une
// session de test précédente avait déjà persisté useGopScoring=true (gop
// actif) avant ce changement ; sans le bump de clé, ce réglage enregistré
// aurait masqué le nouveau défaut (texte pilote, gop en log seul).
//
// Repassée en _v4 le 2026-07-22 : même raison une 3e fois, useGopScoring
// revenu à false -> true (cf. judgement_options.dart) -- constat device
// (session 21:19, mode adulte) que le texte-diff restait bloqué sur les 2
// premiers mots pendant toute une récitation alors que le gop suivait
// correctement en parallèle. Sans ce bump, un réglage adulte déjà persisté
// avec useGopScoring=false aurait masqué le nouveau défaut et le bug aurait
// semblé toujours présent après la mise à jour.
// Repassée en _v5 le 2026-07-23 : le preset tajwid ne contrôle plus ham_wasl
// d'office (cf. _contextDependentRules -- élision positionnelle non détectable
// en récitation continue, flashait à tort chaque mot en ٱل-). Un réglage
// tajwid déjà persisté contenait ham_wasl dans activeRules ; sans ce bump il
// aurait continué à le vérifier malgré le changement.
const _kPrefJudgement = 'judgement_options_v5';

final judgementOptionsProvider =
    StateNotifierProvider<JudgementOptionsNotifier, JudgementOptions>((ref) {
  final n = JudgementOptionsNotifier();
  // Fiabilité mesurée par règle : sert à choisir quelles règles le mode tajwid
  // active d'office (cf. applyPreset). Poussée dès que l'asset est chargé.
  final r0 = ref.read(ruleReliabilityProvider).asData?.value;
  if (r0 != null) n.setReliability(r0);
  ref.listen<AsyncValue<Map<TajwidRule, RuleReliability>>>(
      ruleReliabilityProvider, (_, next) {
    final v = next.asData?.value;
    if (v != null) n.setReliability(v);
  });
  return n;
});


/// Vrai pendant qu'un ECRAN DE VERIFICATION TAJWID DEDIE (`_openKaraokeTajwid`
/// dans mushaf_screen.dart, `KaraokeRecitationScreen(modeTajwid: true)`) est
/// ouvert (2026-09-11).
///
/// Pilote UNIQUEMENT par cet ecran (`initState`/`dispose`) -- jamais ailleurs.
/// Sert de contexte a `judgementOptionsEffectivesProvider` ci-dessous, meme
/// principe que le garde-fou Warsh juste en dessous : DERIVE, pas une
/// ecriture dans `judgementOptionsProvider`. Le choix persiste de
/// l'utilisateur (Coach, mode Reciter normal) reste intact -- il ressort de
/// l'ecran Tajwid dedie et retrouve son preset d'avant sans rien refaire.
///
/// Retour utilisateur (2026-09-11) qui motive ce forcage : « dans le mode
/// tajwid il faut mettre un parametre independant de l'autre de reciter et le
/// forcer a tajwid, enleve ici alors adulte et enfant, pas d'utilite » --
/// Adulte/Enfant n'ont pas de sens dans un ecran dont le but EST de verifier
/// le tajwid.
final modeTajwidDedieActifProvider = StateProvider<bool>((ref) => false);

/// Les options de jugement REELLEMENT appliquees a la chaine de recitation.
///
/// ── POURQUOI UN PROVIDER DERIVE (2026-08-21) ────────────────────────────────
/// En riwaya WARSH, le prereglage tajwid retombe sur ADULTE. Demande
/// utilisateur : « oublie le tajwid pour le Warsh pour le moment ; en Warsh,
/// adulte et enfant ». Adulte et enfant passent tels quels -- ils n'activent
/// AUCUNE regle (`activeRules` vide), donc rien a traduire.
///
/// CE QUI L'IMPOSE, ET CE N'EST PAS UN CHOIX DE CONFORT. Le texte annote
/// (`quran_rules_annotated.json`) nomme les madd a l'ancienne --
/// `madda_necessary`, `madda_obligatory`, `madda_permissible`,
/// `madda_normal` -- alors que le modele a quatre tetes sort `madd_long` et
/// `madd_court`. Constate au journal du 2026-08-21 :
///     [CTL][PARAMS] preset=tajwid regles=14(madda_necessary, madda_obligatory, ...)
/// La regle ATTENDUE et la regle DETECTEE ne peuvent donc plus correspondre sur
/// un madd : le mot serait signale non pas parce que la recitation est fausse,
/// mais parce que les deux cotes ne parlent pas la meme langue. Laisser le
/// tajwid actif en Warsh produirait des fautes inventees -- exactement ce que
/// l'app existe pour ne pas faire.
///
/// DERIVE et non ecriture forcee : le choix de l'utilisateur reste intact dans
/// `judgementOptionsProvider`. Il repasse en Hafs, il retrouve son mode tajwid
/// sans avoir rien a refaire.
///
/// ⚠️ A RETIRER le jour ou la correspondance des noms de madd sera posee (4
/// anciens noms vers 2 nouveaux). Ce provider est un GARDE-FOU temporaire, pas
/// une decision sur le Warsh : la tete tajwid du modele fonctionne, c'est son
/// vocabulaire de regles qui n'est pas encore raccorde.
final judgementOptionsEffectivesProvider = Provider<JudgementOptions>((ref) {
  // Ecran de verification tajwid dedie (2026-09-11, cf.
  // `modeTajwidDedieActifProvider`) : preset FORCE a tajwid, quel que soit le
  // choix persiste ailleurs (Coach, mode Reciter normal). Calcule AVANT le
  // garde-fou Warsh ci-dessous, qui doit continuer a s'appliquer par-dessus --
  // le vocabulaire de regles Warsh/modele ne correspond toujours pas, forcer
  // tajwid ici inventerait les memes fausses fautes qu'en Reciter normal.
  //
  // ⚠️ NE JAMAIS FORCER `JudgementOptions.tajwidDefault` NUE : sa liste
  // `activeRules` est VIDE par construction (elle est remplie par
  // `applyPreset`, depuis la fiabilite mesuree de chaque regle). La premiere
  // version de ce forcage le faisait, et produisait exactement l'inverse du
  // but : `preset=tajwid regles=aucune`, donc plus aucune coloration verte ou
  // violette dans l'ecran qui existe pour verifier le tajwid. Cf.
  // `JudgementOptionsNotifier.reglesFiables` pour le detail et la mesure.
  //
  // Et on ne force QUE si le preset persiste n'est pas deja tajwid : sinon on
  // ecraserait les regles que l'utilisateur a pu ajouter a la main dans
  // l'ecran des regles (le mode tajwid les laisse selectionnables, badge de
  // fiabilite a l'appui).
  final persiste = ref.watch(judgementOptionsProvider);
  final choisi = (ref.watch(modeTajwidDedieActifProvider) &&
          persiste.preset != JudgementPreset.tajwid)
      ? JudgementOptions.tajwidDefault.copyWith(
          activeRules: JudgementOptionsNotifier.reglesFiables(
              ref.watch(ruleReliabilityProvider).asData?.value ?? const {}))
      : persiste;
  final riwaya = ref.watch(riwayaProvider);
  if (riwaya != Riwaya.warsh) return choisi;
  if (choisi.preset != JudgementPreset.tajwid) return choisi;
  return JudgementOptions.adulteDefault;
});

class JudgementOptionsNotifier extends StateNotifier<JudgementOptions> {
  JudgementOptionsNotifier() : super(JudgementOptions.adulteDefault) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefJudgement);
    if (raw != null && mounted) {
      try {
        // `useGopScoring` FORCÉ à true (2026-08-01) : son toggle a été retiré
        // de l'IHM (le gop est désormais le moteur, décision utilisateur) --
        // un état persisté à `false` par une session ANTÉRIEURE resterait
        // sinon indélébile, l'utilisateur n'ayant plus aucun moyen de
        // revenir. Trouvé par le superviseur avant recette, pas en usage.
        // Le repli automatique vers le texte-diff quand l'alignement natif
        // est indisponible n'est PAS concerné (il ne passe pas par ce flag,
        // cf. `!_verifier.alignmentActive` dans recitation_provider.dart).
        state = JudgementOptions.fromJson(
                jsonDecode(raw) as Map<String, dynamic>)
            .copyWith(useGopScoring: true);
      } catch (_) {
        // JSON corrompu (ex. après une migration de version) -> retombe sur
        // le défaut plutôt que de crasher l'app au démarrage.
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefJudgement, jsonEncode(state.toJson()));
  }

  /// Applique un preset complet -- écrase toutes les options actuelles.
  Future<void> applyPreset(JudgementPreset preset) async {
    state = switch (preset) {
      // MODE TAJWID = le tajwid EST contrôlé (décision utilisateur 2026-07-20 :
      // « en mode adulte, ne pas faire l'idgham ou la qalqala, ça ne fait pas
      // une erreur ; en mode tajwid, oui »). On active donc les règles d'office
      // -- sinon « mode tajwid » avec zéro règle ne vérifierait rien, ce qui
      // était exactement l'état incohérent d'avant.
      //
      // Seules les règles FIABLES sont activées par défaut (statut `ready` et
      // recall >= 0.90) : une règle mal détectée produirait de FAUSSES erreurs
      // (« ghunnah non réalisée » alors qu'elle l'était), le pire retour
      // possible pour apprendre. L'utilisateur reste libre d'ajouter les autres
      // à la main dans l'écran des règles, en connaissance de cause (badge de
      // fiabilité affiché).
      JudgementPreset.tajwid => JudgementOptions.tajwidDefault
          .copyWith(activeRules: _reliableRules),
      // ADULTE / ENFANT : aucune règle -> le tajwid n'est PAS contrôlé. Ne pas
      // réaliser une ghunnah n'est pas une erreur pour eux.
      JudgementPreset.adulte => JudgementOptions.adulteDefault,
      JudgementPreset.enfant => JudgementOptions.enfantDefault,
      JudgementPreset.custom => state.copyWith(preset: JudgementPreset.custom),
    };
    await _persist();
  }

  /// Règles CONTEXTUELLES exclues de la vérification d'office, quelle que soit
  /// leur fiabilité mesurée (2026-07-23, constat device Al-Fatiha).
  ///
  /// `ham_wasl` (hamzat al-wasl) N'est PAS une qualité acoustique graduée mais
  /// une ÉLISION positionnelle : le ٱ n'est prononcé qu'en DÉBUT de souffle,
  /// et ÉLIDÉ (silencieux) dès qu'il est connecté au mot précédent -- ce qui
  /// est le cas quasi partout en récitation continue ("رَبِّ ٱلْعَـٰلَمِينَ"
  /// -> "rabbil-'aalameen", ٱ muet). La tête tajwid ne détecte donc RIEN sur
  /// ces mots (correctement : il n'y a rien à entendre), et les vérifier
  /// comme "doit être réalisé" flashe à tort CHAQUE mot en ٱل- alors que la
  /// récitation est juste. Sa fiabilité 0.96 dans rule_reliability.json est
  /// mesurée sur des clips ISOLÉS (le ٱ y est en début de clip, donc
  /// prononcé) -- trompeuse pour le flux continu. Relève du treillis
  /// d'alignement forcé (cf. plan PARTIE 2, "branche optionnelle"), pas d'un
  /// classifieur entraîné. Reste sélectionnable À LA MAIN pour qui veut
  /// vérifier une hamzat al-wasl en début de récitation.
  static const _contextDependentRules = {TajwidRule.hamWasl};

  /// Règles jugées assez fiables pour être contrôlées d'office en mode tajwid.
  /// Alimenté depuis `rule_reliability.json` (asset versionné avec le modèle)
  /// par le provider ci-dessous -- pas codé en dur : quand un nouveau modèle
  /// améliore une règle, le fichier suffit à la faire entrer dans le mode.
  Set<TajwidRule> _reliableRules = const {};

  /// Le calcul des regles fiables, EXTRAIT pour avoir une seule source de
  /// verite (2026-09-11).
  ///
  /// `judgementOptionsEffectivesProvider` en a besoin lui aussi depuis qu'il
  /// peut forcer le mode tajwid (ecran dedie). Il avait d'abord ete ecrit avec
  /// `JudgementOptions.tajwidDefault` NUE -- dont `activeRules` est vide, les
  /// regles etant remplies ici par `applyPreset` -- ce qui donnait le
  /// contraire du but recherche : `preset=tajwid regles=aucune` dans le
  /// journal, et plus une seule coloration verte ou violette dans l'ecran
  /// tajwid. Defaut signale par l'utilisateur et confirme par correlation
  /// exacte, trois fois de suite : `KaraokeOuverture modeTajwid=true` suivi
  /// 3 s plus tard de `regles=aucune`.
  ///
  /// Dupliquer le filtre cote provider aurait fait diverger les deux le jour
  /// ou `_contextDependentRules` change : une fonction, deux appelants.
  /// Activees d'office MALGRE l'absence de mesure (2026-09-11, demande
  /// utilisateur : « idgham_mutajanisayn, idgham_mutaqaribayn -- active quand
  /// meme avec des seuils plus tolerants »).
  ///
  /// CE QU'ELLES SONT VRAIMENT, et ce n'est pas « peu fiables » :
  /// `rule_reliability.json` leur donne `status: insufficient_data` -- aucun
  /// recall mesure, ni bon ni mauvais. Le fichier date du 2026-07-23 et porte
  /// sur un modele anterieur ; le silence sur ces deux regles n'a jamais ete
  /// leve depuis. Le modele, lui, SORT bien une probabilite pour ces deux
  /// canaux (remarque utilisateur : « mais on a des probas quand meme »),
  /// et `seuils_tajwid.json` leur donne un seuil comme aux autres.
  ///
  /// Elles entrent donc dans le mode tajwid, mais avec un seuil de detection
  /// ABAISSE (0,30 au lieu de 0,50 dans le pack, soit 0,48 en strict et 0,30
  /// en tolerant contre 0,80/0,50) : faute de savoir ce que le modele rate,
  /// on preferera le laisser detecter trop que l'inverse -- une regle non
  /// detectee produit un VIOLET sur une recitation correcte, ce qui est le
  /// pire retour possible pour apprendre.
  ///
  /// ⚠️ RECTIFICATION, le jour meme : j'avais ecrit ici « elles restent
  /// capsToUnclear, jamais de vert franc, le jugement les plafonne a incertain
  /// (cf. `_capByRuleReliability`) ». C'est FAUX, et l'utilisateur l'a releve
  /// (« si vert, pas d'orange »). Verifie : `_capByRuleReliability` N'EXISTE
  /// PLUS dans le code -- il n'en reste que trois mentions en commentaire, ici
  /// et dans `recitation_provider.dart` / `tajwid_rules_screen.dart`, toutes
  /// annotees ce jour. `capsToUnclear` n'est plus lu que pour DECIDER DE
  /// L'ACTIVATION (juste en dessous) et pour un badge d'ecran ; il ne plafonne
  /// plus aucun verdict.
  ///
  /// Donc ces deux regles donnent bien un VERT FRANC quand elles sont
  /// detectees -- ce qui est le comportement voulu : une regle realisee ne
  /// doit pas laisser un mot en orange.
  static const _sansMesureMaisActivees = {
    TajwidRule.idghamMutajanisayn,
    TajwidRule.idghamMutaqaribayn,
  };

  static Set<TajwidRule> reglesFiables(
          Map<TajwidRule, RuleReliability> reliability) =>
      {
        for (final e in reliability.entries)
          if ((!e.value.capsToUnclear ||
                  _sansMesureMaisActivees.contains(e.key)) &&
              !_contextDependentRules.contains(e.key))
            e.key,
      };

  void setReliability(Map<TajwidRule, RuleReliability> reliability) {
    _reliableRules = reglesFiables(reliability);
  }

  /// Modifier une option individuelle bascule automatiquement le preset sur
  /// "custom" (sauf si on est déjà en train de construire un preset) --
  /// REFONTE_IHM.md §1.1 : "même adulte il y aura des options".
  Future<void> setActiveRules(Set<TajwidRule> rules) async {
    state = state.copyWith(activeRules: rules, preset: JudgementPreset.custom);
    await _persist();
  }

  Future<void> toggleRule(TajwidRule rule, bool active) async {
    final next = Set<TajwidRule>.from(state.activeRules);
    if (active) {
      next.add(rule);
    } else {
      next.remove(rule);
    }
    await setActiveRules(next);
  }

  Future<void> setStrictHarakat(bool value) async {
    state = state.copyWith(strictHarakat: value, preset: JudgementPreset.custom);
    await _persist();
  }

  Future<void> setTolerateConfusables(bool value) async {
    state = state.copyWith(
        tolerateConfusables: value, preset: JudgementPreset.custom);
    await _persist();
  }

  /// Moteur de jugement (gop vs diff textuel, cf. JudgementOptions) : ne
  /// touche PAS `preset` -- c'est un choix de méthode de mesure, pas une
  /// gradation de tolérance tajwid/adulte/enfant.
  Future<void> setUseGopScoring(bool value) async {
    state = state.copyWith(useGopScoring: value);
    await _persist();
  }
}

/// Fiabilité par règle -- chargée une fois depuis l'asset embarqué avec le
/// modèle (jamais codée en dur, cf. REFONTE_IHM.md §1.4).
final ruleReliabilityProvider =
    FutureProvider<Map<TajwidRule, RuleReliability>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/rule_reliability.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final rules = json['rules'] as Map<String, dynamic>;
  final result = <TajwidRule, RuleReliability>{};
  for (final entry in rules.entries) {
    final rule = TajwidRule.fromKey(entry.key);
    if (rule == null) continue;
    final data = entry.value as Map<String, dynamic>;
    final status = switch (data['status']) {
      'ready' => RuleStatus.ready,
      'not_ready' => RuleStatus.notReady,
      _ => RuleStatus.insufficientData,
    };
    result[rule] = RuleReliability(
      status: status,
      recall: (data['recall'] as num?)?.toDouble(),
    );
  }
  return result;
});
