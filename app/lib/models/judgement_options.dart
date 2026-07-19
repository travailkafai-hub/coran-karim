// Système de vérification unifié -- REFONTE_IHM.md §1. Les "modes" ne sont
// PAS des modèles différents : ce sont des presets d'options appliquées à la
// comparaison post-décodage (cf. services/recitation_verifier.dart). Un seul
// modèle, une sortie fidèle à ce qui est prononcé -- ces options décident
// seulement de ce qu'on choisit de sanctionner.

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

  const JudgementOptions({
    required this.preset,
    required this.activeRules,
    required this.strictHarakat,
    required this.tolerateConfusables,
  });

  static const tajwidDefault = JudgementOptions(
    preset: JudgementPreset.tajwid,
    activeRules: {}, // rempli par l'utilisateur dans l'écran de règles
    strictHarakat: true,
    tolerateConfusables: false,
  );

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
  }) =>
      JudgementOptions(
        preset: preset ?? this.preset,
        activeRules: activeRules ?? this.activeRules,
        strictHarakat: strictHarakat ?? this.strictHarakat,
        tolerateConfusables: tolerateConfusables ?? this.tolerateConfusables,
      );

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'activeRules': activeRules.map((r) => r.key).toList(),
        'strictHarakat': strictHarakat,
        'tolerateConfusables': tolerateConfusables,
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

  bool get selectable => status == RuleStatus.ready;
}
