// Système de vérification unifié -- REFONTE_IHM.md §1. Les "modes" ne sont
// PAS des modèles différents : ce sont des presets d'options appliquées à la
// comparaison post-décodage (cf. services/recitation_verifier.dart). Un seul
// modèle, une sortie fidèle à ce qui est prononcé -- ces options décident
// seulement de ce qu'on choisit de sanctionner.

import '../l10n/app_localizations.dart';

/// Les 17 règles de tajwid détectées par le modèle -- valeurs EXACTEMENT
/// celles de benchmark/data/quran_tajweed_rules/rules_map.json (jointure
/// avec les symboles produits par le modèle). Ne jamais renommer une valeur
/// sans renommer aussi côté benchmark.
enum TajwidRule {
  maddaNecessary('madda_necessary'),
  maddaObligatory('madda_obligatory'),
  maddaPermissible('madda_permissible'),
  maddaNormal('madda_normal'),
  ghunnah('ghunnah'),
  ikhafa('ikhafa'),
  ikhafaShafawi('ikhafa_shafawi'),
  idghamGhunnah('idgham_ghunnah'),
  idghamShafawi('idgham_shafawi'),
  iqlab('iqlab'),
  idghamWoGhunnah('idgham_wo_ghunnah'),
  idghamMutajanisayn('idgham_mutajanisayn'),
  idghamMutaqaribayn('idgham_mutaqaribayn'),
  laamShamsiyah('laam_shamsiyah'),
  hamWasl('ham_wasl'),
  slnt('slnt'),
  qalaqah('qalaqah');

  final String key;
  const TajwidRule(this.key);

  static TajwidRule? fromKey(String key) {
    for (final r in TajwidRule.values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

enum JudgementPreset { tajwid, adulte, enfant, custom }

/// Options de jugement -- immuable, se manipule par copyWith (pattern
/// standard du projet, cf. les autres providers de app_settings_provider.dart).
class JudgementOptions {
  final JudgementPreset preset;
  final Set<TajwidRule> activeRules;
  final bool strictHarakat;
  final bool tolerateConfusables;
  // Moteur de jugement (2026-07-20, demande utilisateur) : le gop (alignement
  // forcé) reste la méthode par défaut, mais l'ancien diff textuel flou
  // (_realignFromFullText, jamais supprimé -- servait déjà de repli quand le
  // modèle natif n'est pas déployé) reste désactivable/réactivable pour
  // comparer les deux SANS perdre l'un ou l'autre. Cf. mesure du soir même :
  // le gop sur-pénalise certains mots (chadda, hamzat wasl) même sur une
  // récitation parfaite/professionnelle, et la sensibilité du gop aux fautes
  // de harakat elles-mêmes s'est révélée faible (-0.16 à -0.90 sur des fautes
  // délibérées, souvent sous le seuil d'erreur).
  final bool useGopScoring;

  const JudgementOptions({
    required this.preset,
    required this.activeRules,
    required this.strictHarakat,
    required this.tolerateConfusables,
    // Défaut basculé à false le 2026-07-20 nuit (demande utilisateur) : le
    // diff textuel pilote maintenant l'affichage par défaut, le gop tourne en
    // PARALLÈLE et se journalise (`[GOP]` dans le log) sans agir sur l'écran
    // -- permet d'observer son vrai comportement (calibration par mot
    // incluse) sans qu'il bloque l'usage réel pendant qu'on continue de le
    // fiabiliser. Reste réactivable d'un tap (feuille de réglages).
    //
    // REVENU à true le 2026-07-22 (constat device, session 21:19 mode
    // adulte, decision utilisateur) : avec ce defaut a false, le texte-diff
    // est reste bloque sur "بِسْمِ ٱللَّهِ" (mots 0-1) pendant TOUTE la
    // session (~80s d'audio recu, log [ASR] bloc PCM jusqu'a #980) alors que
    // l'alignement force GOP progressait normalement en parallele (ancre
    // 0->10, cf. logs [BufferedTranscriber] alignement seq=9..22) -- le flux
    // natif committed/preview qui alimente _realignFromFullText ne grandissait
    // plus du tout. Cause racine (blocage cote natif du flux structure) pas
    // encore investiguee ; en attendant, on ne peut pas se fier au
    // texte-diff comme moteur par defaut puisqu'il ne suit pas la
    // recitation. Le gop, lui, a demontre qu'il suivait correctement cette
    // meme session -- redevient le defaut.
    this.useGopScoring = true,
  });

  static const tajwidDefault = JudgementOptions(
    preset: JudgementPreset.tajwid,
    activeRules: {}, // rempli par l'utilisateur dans l'écran de règles
    strictHarakat: true,
    tolerateConfusables: false,
  );

  // ADULTE ASSOUPLI le 2026-07-20 (demande utilisateur, après recette).
  //
  // AVANT : strictHarakat: true, tolerateConfusables: false -- soit EXACTEMENT
  // les mêmes valeurs que `tajwidDefault`. Les deux modes étaient donc
  // strictement identiques dans le moteur de jugement (`_relaxJudged` ne
  // déclenchait aucune de ses deux branches ni dans l'un ni dans l'autre), ce
  // que l'utilisateur a constaté sur device : « je ne vois pas la diff entre
  // les deux modes ». Ce n'était pas une impression, c'était le code.
  //
  // MAINTENANT : strictHarakat: false -> les lettres restent exigées à
  // l'identique, mais une voyelle courte / une articulation fine imprécise est
  // pardonnée. tolerateConfusables reste false : confondre س/ص ou ت/ط change le
  // MOT, ça ne doit pas passer pour un adulte.
  //
  // La gradation devient réelle :
  //   tajwid : harakat strictes  + lettres strictes   (le plus exigeant)
  //   adulte : harakat souples   + lettres strictes   (intermédiaire)
  //   enfant : harakat souples   + lettres tolérantes (le plus permissif)
  //
  // ── ADULTE REDEVENU STRICT LE 2026-08-14 (décision utilisateur) ──────────
  //
  // « tu peux implémenter harakat souple et lettre confusable pour le mode
  // enfant, garde adulte forcément strict. »
  //
  // Le commentaire ci-dessus est CONSERVÉ (il documente pourquoi l'adulte
  // avait été assoupli et ce que ça valait) mais sa conclusion ne tient plus :
  // `strictHarakat` repasse à `true` pour l'adulte. La gradation effective
  // devient donc :
  //   tajwid : harakat strictes + lettres strictes + RÈGLES de tajwid actives
  //   adulte : harakat strictes + lettres strictes, aucune règle de tajwid
  //   enfant : harakat souples  + lettres tolérées
  //
  // ⚠️ Conséquence assumée, à ne pas redécouvrir comme un bug : adulte et
  // tajwid jugent désormais LE TEXTE à l'identique. Ce n'est plus le défaut
  // constaté le 2026-07-20 (« je ne vois pas la diff entre les deux modes »),
  // parce qu'entre-temps le contrôle de tajwid a été rebranché sur la v2 : le
  // mode tajwid dégrade un mot dont une règle ACTIVE n'est pas réalisée, ce
  // que le mode adulte ne fait jamais (`activeRules` y est vide). La
  // différence est donc réelle, elle a simplement changé de nature -- elle
  // porte sur les RÈGLES, plus sur la tolérance aux voyelles.
  static const adulteDefault = JudgementOptions(
    preset: JudgementPreset.adulte,
    activeRules: {},
    strictHarakat: true,
    tolerateConfusables: false,
  );

  static const enfantDefault = JudgementOptions(
    preset: JudgementPreset.enfant,
    activeRules: {},
    strictHarakat: false,
    tolerateConfusables: true,
  );

  JudgementOptions copyWith({
    JudgementPreset? preset,
    Set<TajwidRule>? activeRules,
    bool? strictHarakat,
    bool? tolerateConfusables,
    bool? useGopScoring,
  }) =>
      JudgementOptions(
        preset: preset ?? this.preset,
        activeRules: activeRules ?? this.activeRules,
        strictHarakat: strictHarakat ?? this.strictHarakat,
        tolerateConfusables: tolerateConfusables ?? this.tolerateConfusables,
        useGopScoring: useGopScoring ?? this.useGopScoring,
      );

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'activeRules': activeRules.map((r) => r.key).toList(),
        'strictHarakat': strictHarakat,
        'tolerateConfusables': tolerateConfusables,
        'useGopScoring': useGopScoring,
      };

  factory JudgementOptions.fromJson(Map<String, dynamic> json) {
    return JudgementOptions(
      preset: JudgementPreset.values.firstWhere(
        (p) => p.name == json['preset'],
        orElse: () => JudgementPreset.adulte,
      ),
      activeRules: ((json['activeRules'] as List?) ?? [])
          .map((k) => TajwidRule.fromKey(k as String))
          .whereType<TajwidRule>()
          .toSet(),
      strictHarakat: json['strictHarakat'] as bool? ?? true,
      tolerateConfusables: json['tolerateConfusables'] as bool? ?? false,
      useGopScoring: json['useGopScoring'] as bool? ?? true,
    );
  }
}

/// Fiabilité par règle -- REFONTE_IHM.md §1.4. Généré depuis les évals
/// benchmark (assets/data/rule_reliability.json), jamais codé en dur : une
/// règle non fiable ne doit jamais pouvoir être activée dans l'écran de
/// sélection, quel que soit ce que l'utilisateur voudrait.
enum RuleStatus { ready, notReady, insufficientData }

class RuleReliability {
  final RuleStatus status;
  final double? recall;
  const RuleReliability({required this.status, this.recall});

  /// TOUTES les règles sont désormais activables (décision utilisateur
  /// 2026-07-20). Avant, `status == ready` bloquait le toggle : `madda_necessary`
  /// (le madd 6, une des règles LES PLUS fondamentales et les plus audibles)
  /// était grisé, même en mode enfant. L'utilisateur a contesté, à raison.
  ///
  /// POURQUOI LE GARDE-FOU ÉTAIT MAL FONDÉ (3 raisons, mesurées) :
  ///  1. La mesure évalue la MAUVAISE CHOSE : « quand le récitateur fait la
  ///     règle CORRECTEMENT, le modèle émet-il le symbole ? ». Or pour
  ///     enseigner, ce qui compte est l'inverse : « quand l'utilisateur RATE
  ///     la règle, le modèle le voit-il ? ». Jamais mesuré (cf.
  ///     PLAN_ENTRAINEMENT_HYBRIDE.md : « le set humain reste le juge de paix »).
  ///  2. Échantillons minuscules : madda_necessary n=32 -> 72% avec un IC95%
  ///     de [55%, 84%] ; idgham_mutaqaribayn n=3 -> « 100% » avec IC [44%,100%],
  ///     autrement dit aucune information.
  ///  3. La cause probable est la RARETÉ (143 occurrences de madda_necessary
  ///     dans tout le Coran), pas une difficulté acoustique intrinsèque.
  ///
  /// Le garde-fou ne disparaît pas, il CHANGE DE NATURE : au lieu d'interdire,
  /// on informe (badge de fiabilité) et on refuse le vert franc
  /// (cf. [capsToUnclear]) -- afficher « correct » sur une faute réelle reste
  /// le pire des comportements (biais canonique, combattu depuis le début).
  bool get selectable => true;

  /// Fiabilité insuffisante pour affirmer « c'est correct » : quand une telle
  /// règle est active, son verdict est PLAFONNÉ à « incertain » (orange) au
  /// lieu de passer au vert. L'utilisateur garde l'information (« il se passe
  /// quelque chose ici ») sans que l'app ne certifie à tort.
  ///
  /// Seuil 0.90 : cohérent avec le groupe « prêtes » mesuré (92-100%) ;
  /// en dessous, ou sans données, on ne certifie pas.
  bool get capsToUnclear =>
      status != RuleStatus.ready || (recall ?? 0) < 0.90;

  /// Libellé court pour le badge de l'écran de règles.
  String badgeLabel(AppLocalizations t) => switch (status) {
        RuleStatus.ready => recall == null
            ? t.ruleReliableLabel
            : t.ruleReliableLabelWithPct((recall! * 100).round()),
        RuleStatus.notReady => recall == null
            ? t.ruleUnreliableLabel
            : t.ruleUnreliableLabelWithPct((recall! * 100).round()),
        RuleStatus.insufficientData => t.ruleNotMeasuredLabel,
      };
}
