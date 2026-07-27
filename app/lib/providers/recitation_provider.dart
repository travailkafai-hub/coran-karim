import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/judgement_options.dart';
import '../models/recitation_state.dart';
import '../models/verse.dart' show Verse;
import '../providers/gop_baseline_provider.dart';
import '../providers/judgement_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/fastconformer_verifier.dart' show AlignPayload, AlignedWord;
import '../services/quran_api.dart';
import '../services/quran_verse_locator_service.dart';
import '../services/recitation_verifier.dart';
import '../services/rule_annotation_service.dart';
import '../services/voice_lora_clip_service.dart';
import '../services/word_duration_store.dart';
import '../services/word_timing_service.dart';

/// Segment de texte à réciter, avec sa clé de verset quand elle est connue
/// (surah/ayah) -- permet l'annotation POSITIONNELLE des règles tajwid par le
/// [RuleAnnotationService] (cf. RecitedWord.alignTarget). `surah`/`ayah` nuls
/// = texte hors-Coran (ou verset inconnu) : repli sur la cible canonique, sûr.
typedef RecitationSegment = ({int? surah, int? ayah, String text});

const double _kSimThreshold = 0.6;
// Au-dessus de ce seuil de similarité squelette (sans harakat), un mot aligné
// mais sans correspondance stricte est jugé "unclear" (orange : bon mot,
// articulation imprécise) plutôt que "error" (rouge : mot faux).
const double _kUnclearSimThreshold = 0.85;
const int _kLookahead = 3;
const int _kAlignLookahead = 6; // tolérance mots sautés/bruit dans le texte reconnu (realign complet)

// ── Seuils GOP (alignement forcé, cf. ForcedAligner.kt — refonte 2026-07-11) ──
// gop = logprob(chemin forcé = mot attendu) − logprob(meilleur chemin libre),
// moyenné par frame sur les frames de tokens du mot. Toujours ≤ 0.
//  - gop ≥ seuil "correct" : l'audio soutient le mot attendu (harakat
//    comprises) presque aussi bien que ce que le modèle préférerait dire →
//    correct (vert).
//  - gop ≥ seuil "unclear" : hésitation nette mais pas un rejet — typiquement
//    une harakat approximative ou une articulation floue → unclear (orange).
//  - sinon : le modèle est nettement plus sûr d'avoir entendu AUTRE CHOSE
//    (le champ `actual` dit quoi) → error (rouge).
// Valeurs par défaut CALIBRÉES sur device (correspondent à sensibilité=0.5,
// cf. `correctionSensitivityProvider`) — chaque jugement est logué avec son
// gop précis pour ajuster (chercher "[GOP]" dans le log persistant).
//
// ── Historique de calibrage (conserver, cf. règle : une piste invalidée reste
//    documentée AVEC sa raison, sinon elle se re-tente) ────────────────────
//
// RECALIBRAGE 2026-07-16 (matin) -> -5.0/-10.0 : **ERREUR, ANNULÉ le soir même**.
// Motif invoqué à l'époque : au passage au modèle tajweed (tokenizer
// tajweed_bpe_v1), des mots reconnus EXACTEMENT (entendu == mot attendu)
// donnaient gop=-4.43/-4.64/-4.70/-8.98 -- tous sous l'ancien seuil tolérant
// (-2.50), donc plus rien ne pouvait être jugé correct. Conclusion tirée :
// "ce checkpoint est moins confiant, décalons les seuils".
//
// POURQUOI C'ÉTAIT FAUX : ces gop dégradés n'avaient RIEN à voir avec le
// modèle. `word_tokens.json` était généré avec un token '▁' parasite en tête
// de chaque mot (bug de build_word_token_lookup.py, cf. le commentaire détaillé
// dans ce script) : un token que le modèle n'émet jamais, que l'alignement
// forcé devait quand même placer, et dont la logprob ~-inf polluait la moyenne
// du mot. Décaler les seuils revenait à ajuster le thermomètre parce que le
// thermomètre était cassé -- et ça a rendu l'app AVEUGLE : avec "correct" à
// -5.0, un mot dont le gop tombait à -1.28 avec une shadda manquante à
// l'oreille ("ٱلصِّرَٰطَ" entendu "ٱلصرَٰطَ") passait vert. Constat utilisateur
// 2026-07-16 15h06 : "j'ai forcé des erreurs de prononciation mais tout est en
// vert". Une erreur non détectée est bien pire qu'un faux positif ici.
//
// Le '▁' corrigé, le gop est revenu dans sa plage historique (0 à -1.5 sur la
// Fatiha entière, mesuré 15h05) -- exactement la plage pour laquelle les
// valeurs pcd ci-dessous avaient été calibrées sur device. Donc : RETOUR aux
// valeurs pcd, qui n'ont jamais été le problème.
//
// LEÇON : un gop hors plage attendue est un signal de BUG dans la chaîne de
// tokens, pas une invitation à bouger les seuils. Avant tout recalibrage,
// vérifier que `forced ≈ free` sur un mot correctement prononcé (gop ≈ 0) et
// qu'aucun token forcé n'est absent de ce que le modèle émet réellement.
const double _kGopCorrectDefault = -0.45;
const double _kGopUnclearDefault = -1.6;
// Bornes de la sensibilité réglable (demande utilisateur 2026-07-12 :
// "je veux que ça soit dynamique... la possibilité de modifier la
// sensibilité pour que le réciteur veuille quelque chose de strict... ou
// plus tolérant"). sensibilité=0 -> bande verte large (tolérant), =1 ->
// bande verte étroite (strict) ; =0.5 reproduit exactement les valeurs
// calibrées ci-dessus. Deux segments linéaires (tolérant<->défaut,
// défaut<->strict) pour garantir que 0.5 == comportement historique inchangé.
// Bornes revenues aux valeurs pcd en même temps que les défauts ci-dessus
// (elles avaient été décalées proportionnellement au recalibrage erroné du
// 2026-07-16 matin -> -7/-14/-3/-6, annulé, cf. explication plus haut).
const double _kGopCorrectTolerant = -0.90;
const double _kGopUnclearTolerant = -2.50;
const double _kGopCorrectStrict = -0.20;
const double _kGopUnclearStrict = -0.90;

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Vrai si tous les caractères de [sub] apparaissent dans [full] dans le MÊME
/// ORDRE (pas forcément consécutifs) -- distingue une suppression interne
/// ("بلهم" dans "بلونهم", و/ن sautés) d'une substitution ("سرط" pour "صرط",
/// une lettre remplacée par une autre : pas de sous-séquence possible car la
/// toute première lettre diverge déjà). Cf. isFragment dans _onAlignment.
bool _isSubsequenceInOrder(String sub, String full) {
  var i = 0;
  for (var j = 0; j < full.length && i < sub.length; j++) {
    if (full[j] == sub[i]) i++;
  }
  return i == sub.length;
}

/// Moteur Whisper ONNX on-device.
/// Remplacer par MockRecitationVerifier() pour tester l'UI sans modèle.
final recitationVerifierProvider = Provider<RecitationVerifier>((ref) {
  final v = WhisperOnnxVerifier();
  ref.onDispose(v.dispose);
  return v;
});

final recitationProvider = StateNotifierProvider.autoDispose<
    RecitationNotifier, RecitationSessionState>((ref) {
  // Empêche l'autoDispose prématuré pendant le court instant où l'écran
  // karaoké s'abonne à `wordFailed` dans initState(), avant que build()
  // n'atteigne son propre ref.watch(recitationProvider) -- constat réel
  // 2026-07-10 : sans ça, Riverpod détruisait et recréait ce notifier entre
  // l'abonnement et le vrai démarrage de la récitation, laissant l'écran
  // accroché à une instance jetée. Résultat : aucune correction automatique
  // ne se déclenchait JAMAIS, silencieusement -- le flux `wordFailed` de la
  // nouvelle instance n'avait aucun abonné (confirmé en log,
  // `hasListener=false` au moment de l'émission).
  ref.keepAlive();
  final notifier = RecitationNotifier(ref.watch(recitationVerifierProvider));
  // Options de jugement (preset tajwid/adulte/enfant + règles + toggles) :
  // état initial + suivi des changements. Le notifier ne les lit pas lui-même
  // (StateNotifier sans ref) -- on les lui pousse (cf. applyJudgementOptions).
  notifier.applyJudgementOptions(ref.read(judgementOptionsProvider));
  ref.listen<JudgementOptions>(judgementOptionsProvider, (_, next) {
    notifier.applyJudgementOptions(next);
  });
  // Fiabilité mesurée par règle (asset versionné avec le modèle) : sert à
  // REFUSER LE VERT sur les règles dont la détection est trop imprécise, sans
  // pour autant en interdire l'activation (décision 2026-07-20, cf.
  // RecitationNotifier._capByRuleReliability). FutureProvider : on pousse dès
  // que chargé, et à chaque rechargement.
  final rel0 = ref.read(ruleReliabilityProvider).asData?.value;
  if (rel0 != null) notifier.applyRuleReliability(rel0);
  ref.listen<AsyncValue<Map<TajwidRule, RuleReliability>>>(
      ruleReliabilityProvider, (_, next) {
    final v = next.asData?.value;
    if (v != null) notifier.applyRuleReliability(v);
  });
  // Ligne de base gop par mot (cf. gop_baseline_provider.dart) : mesurée sur
  // 42 927 clips coraniques réels, sert à recentrer le gop des mots
  // structurellement durs (chadda, Bismillah...) avant de le comparer aux
  // seuils habituels -- même pattern de poussée que ci-dessus.
  final gopBase0 = ref.read(gopWordBaselineProvider).asData?.value;
  if (gopBase0 != null) notifier.applyGopWordBaseline(gopBase0);
  ref.listen<AsyncValue<Map<String, GopWordBaseline>>>(
      gopWordBaselineProvider, (_, next) {
    final v = next.asData?.value;
    if (v != null) notifier.applyGopWordBaseline(v);
  });
  return notifier;
});

class RecitationNotifier extends StateNotifier<RecitationSessionState> {
  final RecitationVerifier _verifier;
  StreamSubscription<RecognizedToken>? _tokenSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<({String committed, String preview})>? _structSub;
  StreamSubscription<AlignPayload>? _alignSub;

  // Correction automatique (demande utilisateur 2026-07-05) : émis UNE fois
  // par mot, exactement au moment où il est verrouillé rouge pour la première
  // fois (les mots verrouillés ne sont plus jamais rejugés, donc pas de risque
  // de doublon). L'écran karaoké écoute ça pour déclencher pause + lecture
  // réciteur + reprise, sans aucune interaction manuelle.
  final _wordFailedCtrl = StreamController<int>.broadcast();
  Stream<int> get wordFailed => _wordFailedCtrl.stream;

  // ── Alignement ANCRÉ (mode continu) ────────────────────────────────────────
  // Les segments figés (committed) sont append-only : on les aligne UNE fois,
  // définitivement, et on avance l'ancre. Seul l'aperçu (preview) est ré-aligné
  // à chaque passe, à partir de l'ancre. Un mot jugé garde toujours son
  // meilleur statut (vert > orange > rouge > sauté) : une re-transcription
  // dégradée ne peut plus "déjuger" un mot déjà validé — c'est ce qui bloquait
  // le curseur (test réel 2026-07-05 : le début du texte disparaissait des
  // re-transcriptions, le ré-alignement depuis le mot 0 calait à jamais).
  String _prevCommitted = '';
  int _anchorExp = 0;
  StreamSubscription<int>? _pendingSub;

  // Seuils GOP EN VIGUEUR -- modifiables en direct pendant la récitation via
  // setSensitivity (demande utilisateur 2026-07-12), cf. constantes ci-dessus
  // pour le mapping exact 0-1 -> seuils.
  double _gopCorrect = _kGopCorrectDefault;
  double _gopUnclear = _kGopUnclearDefault;

  // Seuil du garde-fou "trou d'alignement" (cf. son bloc dans _onAligned),
  // piloté par le MÊME curseur de sensibilité que les seuils GOP — demande
  // utilisateur 2026-07-26 : un seul réglage doit gouverner toute la sévérité,
  // pas une constante cachée à côté.
  //
  // Un mot sans frames attribuées dont le décodage libre est SÛR (`free`
  // proche de 0) est un trou d'alignement, pas une faute. Le seuil décide de
  // ce qu'on appelle "sûr" :
  //   tolérant : -0,15  -> couvre aussi les cas limites (le mot 15 mesuré à
  //                        free=-0,11 cesse d'être rouge) — moins de faux
  //                        rouges, mais une vraie omission peut passer.
  //   strict   : -0,02  -> ne blanchit que les trous incontestables
  //                        (mesurés à free=0,00 / -0,00) — toute hésitation du
  //                        modèle reste jugée.
  static const double _kFreeConfidentTolerant = -0.15;
  static const double _kFreeConfidentStrict = -0.02;
  double _freeConfident = _kFreeConfidentStrict;

  // Options de jugement post-décodage (REFONTE_IHM.md §1, presets
  // tajwid/adulte/enfant). Poussées par le provider via [applyJudgementOptions]
  // (ref.listen sur judgementOptionsProvider). Défaut = adulte (strict) tant
  // que le provider n'a rien poussé. Ces options RELÂCHENT seulement le verdict
  // (jamais le durcir) : le pipeline GOP reste la source de vérité, et un
  // preset plus permissif (enfant) ne fait que pardonner certaines classes
  // d'écart -- il ne peut pas transformer un mot faux en mot juste au-delà de
  // ce que l'acoustique autorise déjà (mot non prononcé reste rouge).
  bool _strictHarakat = true;
  bool _tolerateConfusables = false;
  Set<TajwidRule> _activeRules = const {};
  // Moteur de jugement (2026-07-20) : gop (défaut, `_onAligned`) ou diff
  // textuel flou (`_realignFromFullText`, historique, jamais supprimé) --
  // cf. JudgementOptions.useGopScoring pour le pourquoi.
  bool _useGopScoring = true;

  /// Poussé par le provider quand l'utilisateur change de preset / de règles.
  /// Ne touche PAS aux seuils GOP (gérés par setSensitivity, curseur en
  /// direct) -- agit uniquement à l'étape de RELÂCHE du verdict (_relaxJudged)
  /// et sur les règles tajwid affichées.
  void applyJudgementOptions(JudgementOptions opts) {
    // Journalisation du MODE et de ses CHANGEMENTS (demande utilisateur
    // 2026-07-20 : « rajoute quel type de mode et s'il y a des changements de
    // mode de récitation, pour meilleure analyse avec les règles actives »).
    //
    // POURQUOI C'EST INDISPENSABLE À L'ANALYSE : une ligne [GOP] isolée ne dit
    // pas sous QUEL régime elle a été jugée. Le même gop=-2.79 devient orange
    // ou vert selon le preset et la sensibilité ; et un changement de mode EN
    // COURS de session (possible depuis l'icône de l'écran de récitation)
    // rendait jusqu'ici les lignes d'avant et d'après incomparables sans
    // qu'aucune trace ne le signale.
    final changed = _judgementLogged &&
        (opts.preset != _preset ||
            opts.strictHarakat != _strictHarakat ||
            opts.tolerateConfusables != _tolerateConfusables ||
            opts.activeRules.length != _activeRules.length);
    _preset = opts.preset;
    _strictHarakat = opts.strictHarakat;
    _tolerateConfusables = opts.tolerateConfusables;
    _activeRules = opts.activeRules;
    _useGopScoring = opts.useGopScoring;
    _judgementLogged = true;
    final rules = _activeRules.isEmpty
        ? 'aucune'
        : '${_activeRules.length} (${_activeRules.map((r) => r.key).join(",")})';
    DiagnosticLog.log(
        'MODE',
        '${changed ? "CHANGEMENT EN COURS DE SESSION -> " : ""}'
            'preset=${opts.preset.name} '
            'strictHarakat=${opts.strictHarakat} '
            'tolereConfusables=${opts.tolerateConfusables} '
            'reglesActives=$rules');
  }

  /// Preset courant -- mémorisé UNIQUEMENT pour la journalisation (détecter un
  /// changement en cours de session et taguer les lignes [GOP]). Le jugement
  /// lui-même n'utilise que les toggles dérivés ci-dessus.
  JudgementPreset _preset = JudgementPreset.adulte;
  double _lastSensitivity = 0.5;
  bool _judgementLogged = false;

  /// Tag compact du régime de jugement, ajouté à chaque ligne [GOP] pour que
  /// chacune soit interprétable SEULE (sans devoir remonter au dernier [MODE]).
  String get _modeTag => 'mode=${_preset.name}'
      '${_strictHarakat ? "" : "/harakatSouple"}'
      '${_tolerateConfusables ? "/confusablesOK" : ""}'
      ' seuils=${_gopCorrect.toStringAsFixed(2)}/${_gopUnclear.toStringAsFixed(2)}'
      ' regles=${_activeRules.length}';

  /// Règles dont la détection est trop imprécise pour CERTIFIER un mot correct
  /// (`RuleReliability.capsToUnclear`). Poussé par le provider en même temps
  /// que les options, depuis `rule_reliability.json`.
  Set<TajwidRule> _cappingRules = const {};

  void applyRuleReliability(Map<TajwidRule, RuleReliability> reliability) {
    _cappingRules = {
      for (final e in reliability.entries)
        if (e.value.capsToUnclear) e.key,
    };
  }

  /// Ligne de base gop par mot (cf. gop_baseline_provider.dart), mesurée sur
  /// 42 927 clips coraniques réels -- moyenne observée quand le mot est bien
  /// récité. Poussée par le provider dès que l'asset est chargé.
  Map<String, GopWordBaseline> _gopWordBaseline = const {};

  void applyGopWordBaseline(Map<String, GopWordBaseline> baseline) {
    _gopWordBaseline = baseline;
  }

  /// Recentre [rawGop] sur la moyenne observée pour [word] quand la ligne de
  /// base est assez fiable (n>=5, cf. GopWordBaseline.reliable) -- sinon
  /// renvoie [rawGop] tel quel (comportement historique, sûr). Un mot
  /// structurellement dur (chadda, Bismillah : moyenne ~-5 à -7 même bien
  /// récité, cf. PLAN_ENTRAINEMENT_HYBRIDE.md §5quinquies) n'est plus jugé
  /// sur sa valeur brute mais sur son ÉCART à ce qui est normal POUR CE MOT --
  /// les seuils (_gopCorrect/_gopUnclear) restent inchangés, calibrés pour un
  /// écart proche de 0 = mot bien récité.
  double _normalizedGop(String word, double rawGop) {
    final baseline = _gopWordBaseline[word];
    if (baseline == null || !baseline.reliable) return rawGop;
    return rawGop - baseline.mean;
  }

  /// Plafonne le verdict à « incertain » quand le mot porte une règle ACTIVE
  /// dont la détection n'est pas assez fiable pour affirmer « c'est correct ».
  ///
  /// POURQUOI (décision utilisateur 2026-07-20) : ces règles étaient
  /// auparavant INTERDITES d'activation (toggle grisé), ce qui privait l'app
  /// de règles fondamentales comme le madd 6. Elles sont désormais activables,
  /// mais le garde-fou reste — il change juste de nature : au lieu
  /// d'interdire, il refuse de CERTIFIER. Un vert franc affiché sur une faute
  /// réelle est le pire comportement possible (biais canonique : l'utilisateur
  /// croit avoir juste), bien pire que l'absence de retour. L'orange dit
  /// honnêtement « il se passe quelque chose ici, je ne peux pas trancher ».
  ///
  /// Ne durcit rien d'autre : une erreur reste une erreur, et un mot sans
  /// règle active concernée n'est pas touché.
  WordStatus _capByRuleReliability(WordStatus judged, int wordIndex) {
    if (judged != WordStatus.correct) return judged;
    if (_activeRules.isEmpty || _cappingRules.isEmpty) return judged;
    if (wordIndex < 0 || wordIndex >= state.words.length) return judged;
    for (final r in state.words[wordIndex].expectedRules) {
      if (_activeRules.contains(r) && _cappingRules.contains(r)) {
        return WordStatus.unclear;
      }
    }
    return judged;
  }

  /// Règles tajwid ATTENDUES sur ce mot mais NON RÉALISÉES d'après le modèle.
  ///
  /// C'est LA vérification du tajwid, celle qui manquait jusqu'au 2026-07-20 :
  /// jusque-là, l'app avait des toggles, un écran de règles et des statuts de
  /// fiabilité, mais AUCUN code ne confrontait la règle attendue à la règle
  /// réalisée. Les deux données existaient pourtant de part et d'autre.
  ///
  /// PRINCIPE : le modèle 260h a appris à émettre un symbole (U+E000..U+E010)
  /// là où il ENTEND la règle réalisée. Si le mot attendu porte `ghunnah` et
  /// que la transcription de ce mot ne contient pas le symbole ghunnah, c'est
  /// que la règle n'a pas été réalisée (ou pas détectée).
  ///
  /// N'est appliqué QU'AUX RÈGLES ACTIVES : en mode adulte/enfant,
  /// `_activeRules` est vide -> aucune règle n'est contrôlée, ne pas faire
  /// l'idgham ou la qalqala n'est PAS une erreur (décision utilisateur :
  /// « en mode adulte [...] ça ne fait pas une erreur ; avec mode tajweed oui »).
  ///
  /// ⚠️ LIMITE : dépend de la capacité du modèle à détecter la règle. Une règle
  /// à 72% de recall produirait ~28% de FAUSSES accusations (« non réalisée »
  /// alors qu'elle l'était) -- le pire retour possible pour apprendre. C'est
  /// pourquoi le mode tajwid n'active d'office que les règles fiables
  /// (cf. JudgementOptionsNotifier.applyPreset) et pourquoi ce contrôle ne
  /// produit JAMAIS de rouge : au pire un orange nommé (cf. appel).
  /// [emitted] : règles RÉELLEMENT détectées sur les frames de ce mot par la
  /// tête 2 du modèle (cf. AlignedWord.detectedRules). Depuis l'architecture à
  /// deux têtes (2026-07-22), elles ne se lisent plus dans le texte : le
  /// modèle ne mélange plus lettres et symboles de règles dans une même sortie
  /// — c'était précisément la cause mesurée de la dégradation du gop
  /// (dilution de ~20 % de la masse de probabilité + fusion BPE `ٱ+ل` cassée).
  ///
  /// ⚠️ GARDE-FOU : sur un modèle à UNE seule tête, aucune règle n'est jamais
  /// détectée. Sans le test `hasRuleHead`, on conclurait « aucune règle
  /// réalisée » et TOUS les mots porteurs d'une règle passeraient orange —
  /// régression silencieuse. Dans ce cas on ne juge simplement pas le tajwid.
  /// Règles de JONCTION : elles se jouent ENTRE deux mots (le déclencheur est à
  /// la frontière -- tanwin/noun sur le mot précédent pour idgham/iqlab/ikhafa,
  /// hamzat al-wasl ٱ sur le mot suivant). L'alignement forcé attribue leur
  /// frame à l'un OU l'autre des deux mots selon le micro-timing : mesuré sur
  /// l'alignement forcé de production (test_forced_align_attribution.py, 5
  /// récitateurs, sourate 90), delta=0 domine mais delta=±1 arrive (ham_wasl
  /// 19× delta=0, 4× delta=-1). Une règle de jonction attendue sur un mot est
  /// donc considérée réalisée si le modèle l'a détectée sur CE mot OU sur son
  /// voisin de frontière (demande utilisateur 2026-07-23 : « la règle se joue
  /// sur deux mots, il faut vérifier les deux »). Robuste au jitter
  /// d'attribution SANS masquer une vraie omission : si l'utilisateur ne
  /// réalise pas la règle, le modèle ne la détecte NI sur le mot NI sur son
  /// voisin, donc elle reste signalée.
  static const _junctionRules = {
    TajwidRule.hamWasl,
    TajwidRule.iqlab,
    TajwidRule.idghamGhunnah,
    TajwidRule.idghamWoGhunnah,
    TajwidRule.ikhafa,
    TajwidRule.ikhafaShafawi,
    TajwidRule.idghamShafawi,
    TajwidRule.idghamMutajanisayn,
    TajwidRule.idghamMutaqaribayn,
  };

  /// Union des règles détectées sur les mots voisins immédiats de [wordIndex]
  /// (frontières gauche et droite). Lu depuis `state.words` -- valable en
  /// usage POST-HOC (classifyError, après que le jugement a écrit `state`).
  /// Pendant `_onAligned` (avant l'écriture de `state`), l'appelant fournit
  /// `neighborEmitted` calculé depuis le segment courant, car `state` n'est
  /// pas encore à jour.
  Set<TajwidRule> _neighborDetectedFromState(int wordIndex) {
    final out = <TajwidRule>{};
    if (wordIndex - 1 >= 0) out.addAll(state.words[wordIndex - 1].detectedRules);
    if (wordIndex + 1 < state.words.length) {
      out.addAll(state.words[wordIndex + 1].detectedRules);
    }
    return out;
  }

  List<TajwidRule> unrealizedRulesFor(int wordIndex, Set<TajwidRule> emitted,
      {Set<TajwidRule>? neighborEmitted}) {
    if (_activeRules.isEmpty) return const [];
    if (!_verifier.hasRuleHead) return const [];
    if (wordIndex < 0 || wordIndex >= state.words.length) return const [];
    final expected = state.words[wordIndex].expectedRules;
    if (expected.isEmpty) return const [];
    final neigh = neighborEmitted ?? _neighborDetectedFromState(wordIndex);
    return [
      for (final r in expected)
        if (_activeRules.contains(r) &&
            !emitted.contains(r) &&
            // Règle de jonction : tolère la détection sur le voisin de
            // frontière (cf. _junctionRules). Les règles intra-mot (madda,
            // ghunnah, qalaqah, slnt, laam_shamsiyah) restent strictes.
            !(_junctionRules.contains(r) && neigh.contains(r)))
          r,
    ];
  }

  /// Règles détectées portées par [w], converties depuis les ids du modèle.
  static Set<TajwidRule> _rulesOf(AlignedWord w) => {
        for (final d in w.detectedRules)
          if (d.id >= 0 && d.id < TajwidRule.values.length)
            TajwidRule.values[d.id],
      };

  /// Classe une erreur de récitation (demande utilisateur 2026-07-20 :
  /// « catégoriser par type : tajwid ou prononciation »).
  ///
  /// Méthode : COMPARER l'attendu à l'entendu, du plus concret au plus
  /// déductif — jamais une étiquette posée a priori.
  ///   1. rien entendu           -> mot sauté
  ///   2. squelette différent    -> LETTRE (ص/س, ط/ت...)   [prononciation]
  ///   3. squelette égal mais forme stricte différente
  ///                             -> HARAKAT (رَبِّ vs رَبُّ) [prononciation]
  ///   4. lettres ET harakat justes, mais le mot portait une règle tajwid
  ///                             -> TAJWID
  ///   5. sinon                  -> indéterminé
  ///
  /// ⚠️ LIMITE ASSUMÉE (ne pas la masquer dans l'UI) : le cas 4 est une
  /// déduction PAR ÉLIMINATION, pas une détection directe de la règle ratée.
  /// L'écart peut venir d'autre chose (durée, liaison) sans qu'on sache le
  /// distinguer aujourd'hui. Tant que la mesure « détection de fautes
  /// délibérées » n'existe pas (REFONTE_IHM.md §12), « Tajwid » se lit
  /// « écart non expliqué par les lettres ni les harakat, sur un mot qui
  /// porte une règle » — pas comme une preuve que la règle a été ratée.
  RecitationErrorKind classifyError(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= state.words.length) {
      return RecitationErrorKind.inconnu;
    }
    final w = state.words[wordIndex];
    if (w.status == WordStatus.skipped || w.heard.trim().isEmpty) {
      return RecitationErrorKind.saute;
    }
    final heardSkeleton = ArabicNormalizer.normalize(w.heard);
    if (heardSkeleton != w.normalized) {
      // TRONCATURE DE SEGMENT, pas une faute de lettre (correctif 2026-07-23,
      // mesuré sur device -- session Al-Balad d'un réciteur confirmé).
      //
      // Le buffer streaming coupe régulièrement un mot en plein milieu : le
      // squelette entendu diffère alors FORCÉMENT de l'attendu, et cette
      // comparaison concluait « erreur de LETTRE » sur des mots parfaitement
      // récités. Cas réels du log : "عَلَيْ" pour عَلَيْهِمْ, "كَفَ" pour
      // كَفَرُوا۟, "تَ" pour وَأَنتَ, "طَعَامٌ" pour إِطْعَـٰمٌ -- 6 des 7
      // erreurs classées `lettre` de la session étaient de simples
      // troncatures, toutes jugées `correct` par le moteur quelques secondes
      // plus tard. Le moteur de jugement, lui, SAIT déjà les reconnaître
      // (flag `fragment`, cf. isFragment dans _onAligned) ; classifyError
      // était le seul endroit à l'ignorer, ce qui polluait les statistiques
      // par type avec de fausses fautes de lettres.
      //
      // On ne renvoie donc `lettre` que si l'entendu n'est PAS un simple
      // morceau de l'attendu. Sinon `inconnu` : l'écart est réel (le mot a
      // échoué) mais on ne sait pas l'attribuer -- plus honnête que de
      // l'imputer aux lettres.
      final isTruncation = heardSkeleton.isNotEmpty &&
          (w.normalized.startsWith(heardSkeleton) ||
              w.normalized.endsWith(heardSkeleton) ||
              _isSubsequenceInOrder(heardSkeleton, w.normalized));
      return isTruncation
          ? RecitationErrorKind.inconnu
          : RecitationErrorKind.lettre;
    }
    final heardStrict = ArabicNormalizer.normalizeStrict(w.heard);
    if (heardStrict != w.strict) return RecitationErrorKind.harakat;
    // Règle attendue, ACTIVE, et symbole non émis par le modèle : c'est un
    // CONSTAT (on a comparé attendu et réalisé), pas la déduction par
    // élimination décrite plus bas. Depuis 2026-07-20, `w.heard` conserve les
    // symboles, donc cette comparaison est possible ici aussi.
    if (unrealizedRulesFor(wordIndex, w.detectedRules).isNotEmpty) {
      return RecitationErrorKind.tajwid;
    }
    if (w.expectedRules.isNotEmpty) return RecitationErrorKind.tajwid;
    return RecitationErrorKind.inconnu;
  }

  /// Règles tajwid à AFFICHER sur le mot d'index [wordIndex] : celles que le
  /// modèle attend sur ce mot (RecitedWord.expectedRules) ET que l'utilisateur
  /// a activées dans son preset ([_activeRules]). Ordre d'apparition dans le
  /// mot préservé. Vide si aucune règle active ne s'y applique. La fiabilité
  /// par règle (ready/notReady/insufficient) est appliquée en amont côté écran
  /// des règles (une règle non fiable n'est jamais sélectionnable), donc pas
  /// re-filtrée ici. L'UI karaoké lit ceci pour poser des badges de règle.
  ///
  /// ⚠️ NOTE 2026-07-20 : la phrase ci-dessus « une règle non fiable n'est
  /// jamais sélectionnable » N'EST PLUS VRAIE. Toutes les règles sont
  /// désormais activables (le grisage privait l'app du madd 6 ; cf.
  /// `RuleReliability.selectable` pour les 3 raisons mesurées). Le garde-fou
  /// vit maintenant dans [_capByRuleReliability], qui refuse le vert franc sur
  /// une règle peu fiable au lieu d'en interdire l'activation. Ici, on affiche
  /// donc bien TOUTES les règles actives, y compris les moins fiables — c'est
  /// voulu : l'utilisateur doit voir ce qui est évalué.
  List<TajwidRule> shownRulesFor(int wordIndex) {
    if (_activeRules.isEmpty) return const [];
    if (wordIndex < 0 || wordIndex >= state.words.length) return const [];
    final expected = state.words[wordIndex].expectedRules;
    if (expected.isEmpty) return const [];
    return [
      for (final r in expected)
        if (_activeRules.contains(r)) r,
    ];
  }

  /// Relâche un verdict selon le preset courant (jamais ne le durcit). Appelé
  /// APRÈS la décision GOP, uniquement quand il y a eu de la parole (un mot
  /// jamais prononcé reste rouge quel que soit le preset -- on ne saute pas un
  /// mot). [expected] est le mot attendu, [heardNorm] le squelette réellement
  /// décodé (biaisé canonique, donc fiable seulement pour ASSOUPLIR).
  WordStatus _relaxJudged(
      WordStatus judged, RecitedWord expected, String heardNorm) {
    if (judged == WordStatus.correct) return judged;
    final skeletonOk = heardNorm == expected.normalized ||
        ArabicNormalizer.similarity(heardNorm, expected.normalized) >=
            _kUnclearSimThreshold;
    // Harakat non strictes (mode enfant) : lettres bonnes (squelette identique),
    // seule la voyelle courte / l'articulation fine diverge -> on pardonne.
    if (!_strictHarakat && skeletonOk) return WordStatus.correct;
    // Lettres confusables tolérées (mode enfant) : sin/sad, ta/tah... comptées
    // équivalentes. On ne pardonne que si le SEUL écart squelette est une paire
    // confusable (pas un mot entièrement différent).
    if (_tolerateConfusables &&
        !skeletonOk &&
        _differsOnlyByConfusables(heardNorm, expected.normalized)) {
      return _strictHarakat ? WordStatus.unclear : WordStatus.correct;
    }
    return judged;
  }

  // Paires de lettres arabes acoustiquement/graphiquement proches, souvent
  // confondues par un débutant (mode enfant). Squelette (sans harakat) des deux
  // côtés. Liste volontairement CONSERVATRICE : uniquement les confusions
  // classiques d'apprentissage, pas toute la phonologie.
  static const _confusableClasses = <Set<String>>[
    {'س', 'ص'}, // sin / sad
    {'ت', 'ط'}, // ta / tah
    {'ذ', 'ظ', 'ز'}, // dhal / dha / zay
    {'ح', 'ه'}, // ha / heh
    {'ق', 'ك'}, // qaf / kaf
    {'ض', 'د'}, // dad / dal
    {'ث', 'س'}, // tha / sin
  ];

  bool _sameConfusableClass(String a, String b) {
    if (a == b) return true;
    for (final c in _confusableClasses) {
      if (c.contains(a) && c.contains(b)) return true;
    }
    return false;
  }

  /// Vrai si [a] et [b] ont la même longueur et ne diffèrent qu'en lettres
  /// d'une même classe confusable (au moins une vraie substitution, sinon
  /// c'est juste l'égalité déjà traitée en amont).
  bool _differsOnlyByConfusables(String a, String b) {
    if (a.length != b.length || a.isEmpty) return false;
    var subs = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i]) continue;
      if (!_sameConfusableClass(a[i], b[i])) return false;
      subs++;
    }
    return subs > 0;
  }

  // Mode "réciteur confiant" -- vrai UNIQUEMENT pendant une session démarrée
  // via [startPrayerFollow] (écran dédié "Suivre une prière", plus de toggle
  // séparé depuis le retrait du karaoké classique, 2026-07-18). Ne change PAS
  // le jugement vert/orange/rouge lui-même (les seuils GOP restent ceux de
  // setSensitivity) : gouverne la détection du takbir/cycle de prière
  // ci-dessous, et le blocage/correction côté écran
  // (karaoke_recitation_screen.dart::_onWordFailed n'y est plus sensible --
  // seul PrayerFollowScreen tourne avec `_confidentMode` actif).
  bool _confidentMode = false;

  // Longueur de `parts.committed` déjà scrutée pour le takbir -- `committed`
  // est append-only et n'est JAMAIS purgé par resetTrackingToStart() : sans
  // ce curseur, un takbir déjà géré une fois resterait présent dans le texte
  // accumulé et redéclencherait resetTrackingToStart() à CHAQUE passe
  // suivante. On ne scrute donc que la portion nouvellement arrivée depuis
  // le dernier appel.
  int _takbirScannedCommittedLen = 0;

  // Vrai tant que le takbir n'a pas encore été détecté pour l'aperçu
  // (`preview`) en cours -- cf. bug réel constaté 2026-07-18 (log device) :
  // "ٱللَّهُ ٱللَّهُ أَكْبَرُ" est resté en APERÇU PUR pendant ~13s (11 passes
  // consécutives identiques) avant de finir par être figé -- l'ASR ne fige
  // un segment que sur un déclencheur externe (ex. début d'une phrase
  // suivante), pas juste parce que le contenu est stable. Ne scruter que
  // `committed` (comme avant) retarde donc la détection d'autant, ce qui se
  // vit comme "il n'a pas détecté Allahu Akbar" alors que l'utilisateur
  // l'avait déjà dit plusieurs fois. `preview` n'est PAS append-only (il est
  // ré-évalué/remplacé à chaque passe) donc pas de curseur de longueur
  // possible dessus -- ce booléen sert de garde à la place : réarmé dès que
  // l'aperçu redevient vide (nouvelle occurrence), pour ne déclencher qu'une
  // fois par occurrence plutôt qu'à chaque passe des ~11 qui répètent le
  // même texte.
  bool _takbirArmed = true;

  // ── Cycle de prière (mode "réciteur confiant", 2026-07-18) ────────────────
  // Une salât répète Al-Fatiha à chaque rak'ah puis une sourate au choix de
  // l'imam -- mais dit aussi "الله أكبر" plusieurs fois PAR rak'ah pour les
  // changements de position (rukū', sujūd...), pas seulement au lever pour
  // réciter. Impossible de distinguer ces takbirs entre eux par leur seul
  // son : TOUT takbir renvoie donc en [PrayerPhase.standby] (cf. _hasTakbir
  // ci-dessus) -- seule la reconnaissance EFFECTIVE du début d'Al-Fatiha fait
  // basculer vers [PrayerPhase.fatiha]. Ainsi les takbirs de rukū'/sujūd,
  // suivis de silence/tasbih (pas de Coran), laissent juste la session en
  // standby sans dégât, en attendant le prochain vrai début de récitation.

  // Mots d'Al-Fatiha (mêmes champs que RecitedWord normal), chargés une seule
  // fois et mis en cache -- texte fixe, jamais réévalué. Prefetché dès
  // startContinuous() en mode confiant pour être prêt AVANT le premier takbir
  // (une salât peut se dérouler sans réseau fiable, ex. mosquée).
  List<RecitedWord>? _fatihaWords;
  List<Verse>? _fatihaVerses;
  bool _fetchingFatiha = false;

  // Sourate suivie à l'origine (celle chargée à l'ouverture de la session),
  // TOUJOURS resynchronisée avec `state.words` juste avant de quitter la
  // phase [target] (cf. _enterPrayerStandby) -- pas une capture figée une
  // seule fois : sans ça, un enchaînement de page en cours de [target]
  // (_maybeExtendNextPage côté écran) serait perdu au cycle de prière suivant,
  // qui reviendrait à une version plus courte du texte suivi.
  List<RecitedWord>? _originalTargetWords;

  // Longueur de `parts.committed` au moment d'entrer en standby -- borne le
  // texte scruté pour reconnaître le début d'Al-Fatiha au strict nouveau
  // contenu depuis CE takbir (pas l'ancien cycle).
  int _standbyScanStart = 0;

  // ── Découverte dynamique de la sourate suivie (demande utilisateur
  // 2026-07-18, "Suivre une prière" : "on va dans une sourate puis on récite,
  // ce n'est pas adéquat... il vaut mieux utiliser Shazam pour détecter où
  // commence la sourate après Fatiha") ────────────────────────────────────
  // Vrai UNIQUEMENT pour une session démarrée via startPrayerFollow() : AUCUNE
  // sourate n'est pré-chargée, celle qui suit Al-Fatiha est identifiée à la
  // volée (via QuranVerseLocatorService, même moteur que "Shazam coranique")
  // à CHAQUE rak'ah -- elle peut différer d'un cycle à l'autre. Distingue ce
  // flux du karaoké classique (sourate fixe pré-sélectionnée, _originalTargetWords)
  // : dans CE mode, _enterPrayerStandby ne doit jamais figer une sourate
  // suivie, et la fin d'Al-Fatiha doit relancer une détection, pas restaurer
  // un texte pré-chargé.
  bool _dynamicTargetDiscovery = false;

  // Garde contre les appels concurrents à QuranVerseLocatorService.locate()
  // (async, potentiellement lent au tout premier appel -- chargement de
  // l'index JSON) : _onStructured peut être invoqué à nouveau avant qu'un
  // appel précédent ne soit résolu.
  bool _targetLookupInFlight = false;

  // Longueur de `parts.committed` au moment d'entrer en détection -- même
  // principe que `_standbyScanStart`, pour ne soumettre à Shazam que le texte
  // nouvellement reconnu depuis la fin d'Al-Fatiha (pas un résidu d'un cycle
  // précédent).
  int _targetDetectScanStart = 0;

  // ── Resynchronisation continue via Shazam (demande utilisateur 2026-07-18,
  // "le maître c'est le récitateur, il faut qu'il le suive... sinon il doit
  // lancer probablement plusieurs fois le Shazam pour s'aligner") ──────────
  // Constat réel (log natif) : l'alignement forcé GOP ne verrouille souvent
  // que 0-1 mot par segment figé même quand plusieurs mots ont été récités --
  // le pointeur/l'ancre peuvent donc rester en retard sur ce qui est
  // RÉELLEMENT dit. Plutôt que de dépendre uniquement de cette passe (lente,
  // parfois bloquée), on relance PÉRIODIQUEMENT le même moteur de
  // localisation que "Shazam coranique" sur le texte reconnu pendant
  // [fatiha]/[target] : s'il retrouve une position plus avancée que l'ancre
  // actuelle (même sourate), on rattrape l'ancre -- jamais en arrière. Le
  // récitateur reste maître : l'app rattrape sa position réelle plutôt que de
  // rester bloquée sur un jugement mot-à-mot en retard.
  List<Verse>? _currentTargetVerses;
  int? _currentTargetSurah;
  bool _resyncInFlight = false;
  // Longueur de `parts.committed` au moment d'entrer en phase [target] --
  // le texte figé natif est un buffer GLOBAL à la session (jamais purgé
  // entre phases) : sans ce curseur, le rattrapage soumettrait à Shazam du
  // texte d'AVANT cette sourate (Al-Fatiha, standby...), risquant de
  // matcher une position obsolète.
  int _targetTrackingScanStart = 0;

  // ── Repli "continuité entre rak'ah" (demande utilisateur 2026-07-19,
  // "dans la deuxième rak'ah normalement après Fatiha, s'il n'entend rien,
  // il doit me proposer ce que je lisais avant, la continuité") ──────────
  // Une sourate longue peut être répartie sur plusieurs rak'ah -- si aucune
  // identification n'aboutit après un délai de silence, on suppose que
  // l'imam continue la MÊME sourate depuis où la rak'ah précédente s'est
  // arrêtée, plutôt que d'attendre indéfiniment une nouvelle identification.
  // Mémorisés à chaque sortie de [PrayerPhase.target] (cf. _enterPrayerStandby)
  // -- jamais effacés ailleurs, donc toujours la DERNIÈRE position atteinte.
  int? _lastTargetSurahForContinuation;
  int? _lastTargetAnchorForContinuation;
  Timer? _detectingTargetFallbackTimer;
  String _lastDetectingTargetProbe = '';
  static const _kDetectingTargetSilenceFallbackDelay = Duration(seconds: 5);

  // ── Identification en DEUX temps (demande utilisateur 2026-07-19, "il faut
  // afficher le premier puis le confirmer ; sinon recherche 4-6 mots suivant,
  // je trouve actuellement la méthode lourde") ──────────────────────────────
  // Remplace le rescoring de la requête ENTIÈRE accumulée depuis la fin
  // d'Al-Fatiha (qui grossit sans cesse pendant `detectingTarget`, cf.
  // commentaire "PAS de plafond _kRecentWindowWords ICI" plus bas) par deux
  // fenêtres FIXES et COURTES : une première fenêtre donne un candidat
  // PROVISOIRE, la fenêtre suivante CONFIRME (ou non) contre la vraie
  // continuation du texte. Avantages sur l'ancienne approche : (a) un bon
  // match sur les 6 premiers mots n'est plus dilué par du bruit ASR
  // accumulé sur les mots suivants (le score ne porte que sur une fenêtre à
  // la fois, jamais sur la requête complète) ; (b) coût de calcul borné par
  // fenêtre au lieu de re-scorer une chaîne qui grossit sans cesse à chaque
  // appel (~80-100ms) tant que `detectingTarget` dure.
  QuranMatch? _provisionalMatch;
  int _detectWordsConsumed = 0;
  static const _kProvisionalWindowWords = 6;
  static const _kConfirmWindowWords = 6;
  // Seuil plus bas que _kMinIdentifyConfidence (0.70, cf. plus bas) : ce
  // candidat n'est PAS encore accepté, seulement retenu pour être testé par
  // la fenêtre de confirmation suivante -- la vraie protection contre les
  // faux positifs vient de cette confirmation, pas de ce premier seuil.
  static const _kProvisionalMinConfidence = 0.5;
  static const _kConfirmMinConfidence = 0.55;

  // ── Filtrage "mots sûrs / mots douteux" (demande utilisateur 2026-07-19,
  // "avec une boucle, si on trouve pas il recommence en gardant les mots
  // sûrs et enlève les mots avec doute") ────────────────────────────────
  // Le texte FIGÉ (`committed`) est par construction "sûr" (jamais
  // réévalué). L'APERÇU (`preview`), lui, est réévalué à chaque passe --
  // ses derniers mots peuvent encore changer d'une passe à l'autre (log
  // device réel : "اهدنااصراط" légèrement différent d'un appel au suivant).
  // Un mot d'aperçu n'est traité comme "sûr" que s'il reste IDENTIQUE, à la
  // MÊME position, sur deux passes consécutives -- sinon il est "douteux"
  // et exclu de la recherche ce tour-ci (il sera réévalué au prochain
  // aperçu, une fois stabilisé). Coûte au plus un cycle de re-transcription
  // de latence (~1,5-3s) sur le tout dernier mot, en échange de ne jamais
  // soumettre à la recherche un mot encore à moitié décodé.
  List<String> _lastDetectingTargetPreviewTokens = [];

  /// Plus long préfixe de [preview] resté IDENTIQUE depuis la dernière passe
  /// -- le reste (encore en train de changer) est considéré "douteux" et
  /// tronqué. Met à jour la mémoire de comparaison pour le prochain appel.
  String _stablePreviewPrefix(String preview) {
    final tokens =
        preview.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final prevTokens = _lastDetectingTargetPreviewTokens;
    var stableCount = 0;
    while (stableCount < tokens.length &&
        stableCount < prevTokens.length &&
        tokens[stableCount] == prevTokens[stableCount]) {
      stableCount++;
    }
    _lastDetectingTargetPreviewTokens = tokens;
    return tokens.take(stableCount).join(' ');
  }

  // Horodatage du dernier avancement CONFIRMÉ de l'ancre (jugement GOP normal
  // OU rattrapage Shazam déjà accepté) -- garde-fou contre un rattrapage
  // ABSURDE (constat réel utilisateur 2026-07-19 : "je récite ayat 5... il y
  // a le même mot ou deux dans ayat 15, ça active la 15" -- un mot partagé
  // entre deux versets ÉLOIGNÉS de la même sourate peut faire "matcher"
  // Shazam sur le mauvais, et rien n'empêchait alors un saut de plusieurs
  // versets d'un coup). cf. _maybeResyncPosition : le saut proposé est borné
  // par ce qu'il est PHYSIQUEMENT possible d'avoir récité depuis ce moment.
  DateTime? _lastAnchorAdvanceAt;

  // Vitesse de récitation MAXIMALE plausible (mots/seconde) -- volontairement
  // généreuse (une récitation rapide dépasse rarement 3-4 mots/s en continu)
  // pour ne jamais rejeter un vrai rattrapage, seulement un saut absurde.
  static const _kMaxPlausibleWordsPerSecond = 4.0;

  // Seuil de confiance BEAUCOUP plus strict que le seuil générique de
  // QuranVerseLocatorService (0.45, calibré pour "Shazam coranique" -- un
  // geste explicite de l'utilisateur, qui peut retenter). Ici la recherche
  // tourne en fond automatiquement sur des micro-fenêtres, en continu :
  // constat réel 2026-07-19, un match à 0.50 (jute au-dessus du seuil
  // générique) a verrouillé la session sur "2:277" (mot 5775/6117 d'Al-
  // Baqarah) alors que rien de tel n'avait été récité -- une confiance
  // aussi faible sur un texte aussi long ne doit jamais suffire à
  // engager tout le suivi.
  static const _kMinIdentifyConfidence = 0.70;

  /// Charge Al-Fatiha (verset 1, 7 ayat) une seule fois -- même construction
  /// de mots que `setup()`/`extendWords()` (RecitedWord avec ses 4 formes).
  /// Garde aussi la liste `Verse` brute (`_fatihaVerses`) -- nécessaire pour
  /// retrouver l'index de mot d'un verset identifié par Shazam pendant la
  /// resynchronisation (cf. _maybeResyncPosition).
  Future<void> _ensureFatihaWords() async {
    if (_fatihaWords != null || _fetchingFatiha) return;
    _fetchingFatiha = true;
    try {
      await RuleAnnotationService.instance.ensureLoaded();
      await WordTimingService.instance.ensureLoaded();
      await WordDurationStore.instance.ensureLoaded();
      final verses = await QuranApi.fetchVerses(1);
      _fatihaWords = _wordsFromVerses(verses);
      _fatihaVerses = verses;
      DiagnosticLog.log('Prière',
          'Al-Fatiha chargée en cache (${_fatihaWords!.length} mots)');
      return;
    } catch (e) {
      DiagnosticLog.log('Prière', 'échec chargement Al-Fatiha (hors-ligne ?) : $e');
    } finally {
      _fetchingFatiha = false;
    }
  }

  // Ouvertures reconnaissables d'Al-Fatiha -- avec Bismillah dite à voix
  // haute, OU direct au verset 2 (Bismillah dite à voix basse/silencieuse,
  // pratique courante). Comparaison sur une PAIRE consécutive de mots (pas
  // juste présence isolée) pour ne pas confondre avec une autre formule de la
  // salât qui partage un mot avec Al-Fatiha -- ex. l'i'tidal "سَمِعَ اللَّهُ
  // لِمَنْ حَمِدَهُ رَبَّنَا وَلَكَ الْحَمْدُ" contient aussi "الحمد" mais
  // jamais suivi de "لله".
  static final _fatihaOpenings = <List<String>>[
    ['بسم', 'الله'],
    ['الحمد', 'لله'],
  ].map((p) => p.map(ArabicNormalizer.normalize).toList()).toList();

  /// BUG corrigé 2026-07-18 (constat réel, log device en conditions de
  /// mosquée) : cette paire n'était comparée qu'aux 2 PREMIERS mots du texte
  /// scruté -- en pratique l'ASR a produit ~20s de hallucinations bruyantes
  /// (shahada répétée, écho probable de l'ambiance mosquée) AVANT que "بسم
  /// الله" n'apparaisse enfin, donc jamais en position 0/1 -- la session
  /// restait bloquée en standby indéfiniment malgré Al-Fatiha bel et bien
  /// récitée. Cherche maintenant la paire n'IMPORTE où dans le texte scruté,
  /// pas seulement au tout début.
  ///
  /// Fenêtre RÉCENTE plutôt que texte cumulé depuis le début de la phase
  /// (demande utilisateur 2026-07-18 : "la logique pour moi c'est de lancer
  /// des micro écoutes 3-4 mots, si ça ne correspond pas on refait, jusqu'à
  /// ce qu'on tombe sur le verset qui correspond") -- utilisée pour les
  /// requêtes envoyées à QuranVerseLocatorService (identification/
  /// resynchronisation), qui a besoin d'assez de mots pour un score fiable
  /// (une fenêtre à 3-4 mots pile sur la frontière bismillah/vrai contenu
  /// coupe le contenu utile en deux) -- 15 mots reste court (quelques
  /// secondes de parole), se réessaie à chaque nouveau texte reconnu, et
  /// "oublie" naturellement un essai raté plutôt que de traîner un texte de
  /// plus en plus long au fil d'une longue sourate.
  static const _kRecentWindowWords = 15;

  String _lastWords(String text, int n) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length <= n) return tokens.join(' ');
    return tokens.sublist(tokens.length - n).join(' ');
  }

  bool _looksLikeFatihaStart(String rawText) {
    final tokens = ArabicNormalizer.normalize(rawText)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i + 1 < tokens.length; i++) {
      for (final o in _fatihaOpenings) {
        if (tokens[i] == o[0] && tokens[i + 1] == o[1]) return true;
      }
    }
    return false;
  }

  static final _bismillahWords =
      ['بسم', 'الله', 'الرحمن', 'الرحيم'].map(ArabicNormalizer.normalize).toList();

  /// Retire la formule d'ouverture "بسم الله الرحمن الرحيم" de [rawText] si
  /// présente PRÈS du début (mots RAW conservés pour le reste, seule la
  /// comparaison est normalisée) -- cette formule est identique mot pour mot
  /// à Al-Fatiha 1:1, la SEULE entrée de l'index de recherche qui la contient
  /// réellement comme verset (les autres sourates ne l'ont pas dans leur
  /// texte indexé, cf. QuranApi.fetchBismillah -- ajoutée séparément à
  /// l'affichage). Sans ce retrait, Shazam ne voit qu'elle tant que la vraie
  /// sourate n'a pas commencé et identifie systématiquement 1:1.
  ///
  /// Cherche la formule à PARTIR de n'importe laquelle des [_kBismillahMaxLead]
  /// premières positions (pas seulement en tout début strict) -- même classe
  /// de bug que _looksLikeFatihaStart : en conditions de mosquée réelles,
  /// quelques mots de bruit/hallucination ASR peuvent précéder la vraie
  /// formule. Retourne `null` si une formule INCOMPLÈTE se termine pile au
  /// bout du texte connu (probablement encore en train d'être dictée -- pas
  /// encore prête à être soumise à la recherche).
  static const _kBismillahMaxLead = 10;

  String? _stripBismillahPrefix(String rawText) {
    final rawTokens =
        rawText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final normTokens = rawTokens.map(ArabicNormalizer.normalize).toList();
    for (var start = 0;
        start < normTokens.length && start < _kBismillahMaxLead;
        start++) {
      var matched = 0;
      while (matched < _bismillahWords.length &&
          start + matched < normTokens.length &&
          normTokens[start + matched] == _bismillahWords[matched]) {
        matched++;
      }
      if (matched == _bismillahWords.length) {
        return rawTokens.skip(start + matched).join(' ');
      }
      if (matched > 0 && start + matched == normTokens.length) {
        return null; // formule incomplète en fin de texte connu -- attendre la suite
      }
    }
    return rawText; // formule absente (ex. At-Tawbah) -- rien à retirer
  }

  // Longueur de `parts.committed` au moment d'entrer en phase [fatiha] --
  // même principe que `_standbyScanStart`, pour la détection de FIN
  // ci-dessous (_looksLikeFatihaEnd).
  int _fatihaScanStart = 0;

  // Dernier mot d'Al-Fatiha ("ٱلضَّالِّينَ") -- assez distinctif pour ne pas
  // se confondre avec une autre formule de la salât.
  static final _fatihaClosingWord = ArabicNormalizer.normalize('الضالين');
  // Déclencheur alternatif (2026-07-19, bug réel confirmé par log device) :
  // "ٱلْمَغْضُوبِ" (avant-dernier mot distinctif du verset 7) -- occurrence
  // UNIQUE dans tout le Coran (vérifié sur les 6236 versets bundlés
  // localement), donc tout aussi fiable que le mot de clôture, mais placé
  // PLUS TÔT dans la phrase. Constat réel : segment ASR figé en plein mot
  // final ("غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَٱلضَّ" -- "الضالين" tronqué en
  // "والض", coupure de segment avant la fin du mot), donc `_fatihaClosingWord`
  // seul ne matchait JAMAIS -- la phase restait bloquée en `fatiha`
  // indéfiniment, empêchant toute identification Shazam de la sourate
  // suivante (elle n'était même pas tentée). Un mot plus tôt dans la phrase
  // est moins exposé à ce type de troncature de fin de segment.
  static final _fatihaAlmostClosingWord = ArabicNormalizer.normalize('المغضوب');

  // Fenêtre de recherche du strip ci-dessous -- généreuse (Fatiha 6-7 peut
  // représenter jusqu'à ~20 mots : "اهدنا الصراط المستقيم صراط الذين انعمت
  // عليهم غير المغضوب عليهم ولا الضالين"), même principe que
  // _kBismillahMaxLead mais pas la même constante (formule différente).
  static const _kFatihaTailMaxLead = 25;

  /// Retire un résidu de fin d'Al-Fatiha en tête de [rawText] si présent
  /// (2026-07-19, bug réel confirmé par log device -- requête observée :
  /// "...غير المغضوب عليهم ولا الضالين ءامر اهلك بالصلاه..." au lieu du seul
  /// "ءامر اهلك بالصلاه..." attendu, Al-Fatiha 1:7 dominant alors le score
  /// Shazam au lieu du vrai verset suivant, correctement récité).
  ///
  /// CAUSE : `_targetDetectScanStart` (cf. `_beginTargetDetection`) se cale
  /// sur la longueur du texte COMMITTED au moment où `_looksLikeFatihaEnd`
  /// répond vrai -- or cette détection scrute `sinceFatihaStart + preview`
  /// (donc peut se déclencher sur du texte encore en APERÇU, pas encore
  /// committed). Quand ce même texte finit par committer quelques passes
  /// plus tard, il tombe malgré tout DANS la fenêtre post-détection (déjà
  /// "consommée" en théorie) et pollue la requête suivante. Contournement
  /// ICI (pas une correction du calage de `_targetDetectScanStart` lui-même,
  /// plus risqué à modifier sans casser d'autres cas) : retire tout ce qui
  /// précède et inclut la DERNIÈRE occurrence du mot de clôture d'Al-Fatiha
  /// (ou de son mot précédent, cf. `_fatihaAlmostClosingWord`) dans les
  /// [_kFatihaTailMaxLead] premiers mots -- au-delà, un match serait plus
  /// probablement une coïncidence (ex. Al-Baqarah 2:198 contient aussi
  /// "الضالين", légitimement, si l'imam y a repris) que du résidu.
  String _stripFatihaTailPrefix(String rawText) {
    final rawTokens =
        rawText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final normTokens = rawTokens.map(ArabicNormalizer.normalize).toList();
    var cut = -1;
    for (var i = 0; i < normTokens.length && i < _kFatihaTailMaxLead; i++) {
      if (normTokens[i] == _fatihaClosingWord ||
          normTokens[i] == _fatihaAlmostClosingWord) {
        cut = i; // dernière occurrence trouvée dans la fenêtre -- pas la 1ère
      }
    }
    if (cut < 0) return rawText;
    return rawTokens.skip(cut + 1).join(' ');
  }

  /// Détecte la fin d'Al-Fatiha PAR LE TEXTE reconnu, pas par l'avancée du
  /// pointeur GOP -- constat réel (log device 2026-07-18) : le pointeur GOP
  /// peut rester bloqué sur les tout premiers mots pendant plus de 30 secondes
  /// alors que le texte FIGÉ montre déjà Al-Fatiha ENTIÈREMENT récitée (et
  /// même la sourate suivante déjà commencée en aperçu). La passe
  /// d'alignement forcé prend un retard croissant sur le flux réel à mesure
  /// que le buffer audio de la session grandit (la DP native retraite tout
  /// le buffer accumulé depuis le début, coût O(T × 2N+1) qui augmente avec
  /// T) -- attendre `pointer >= words.length` (cf. _onAligned) aurait bloqué
  /// la bascule vers la sourate suivante indéfiniment alors que l'utilisateur
  /// avait déjà bel et bien terminé et enchaîné. Utilise la MÊME approche que
  /// la détection du début (texte reconnu, pas jugement) : plus lent à juger
  /// mot par mot n'empêche pas de reconnaître que la phrase entière est là.
  bool _looksLikeFatihaEnd(String rawText) {
    final tokens = ArabicNormalizer.normalize(rawText)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    return tokens.any(
        (t) => t == _fatihaClosingWord || t == _fatihaAlmostClosingWord);
  }

  /// Takbir détecté (n'importe lequel) : arrête de juger l'ancienne cible et
  /// attend de reconnaître le début d'Al-Fatiha (cf. commentaire de
  /// PrayerPhase). Resynchronise `_originalTargetWords` sur `state.words`
  /// SEULEMENT si on quitte [none] ou [target] -- jamais depuis [fatiha]
  /// (Al-Fatiha n'est pas la sourate suivie) ni [standby] (déjà à jour).
  void _enterPrayerStandby() {
    if (!_dynamicTargetDiscovery &&
        (state.prayerPhase == PrayerPhase.none ||
            state.prayerPhase == PrayerPhase.target)) {
      _originalTargetWords = List<RecitedWord>.of(state.words);
    }
    // Mémorise "où on en était" pour le repli de continuité (cf. commentaire
    // des champs `_lastTargetSurahForContinuation`) -- que la sortie de
    // [target] soit une fin normale ou une interruption par ce même takbir
    // (rukū'/sujūd) en plein milieu, c'est la position à reprendre à la
    // prochaine rak'ah si rien de nouveau n'est identifié.
    if (_dynamicTargetDiscovery &&
        state.prayerPhase == PrayerPhase.target &&
        _currentTargetSurah != null) {
      _lastTargetSurahForContinuation = _currentTargetSurah;
      _lastTargetAnchorForContinuation = _anchorExp;
    }
    _detectingTargetFallbackTimer?.cancel();
    _standbyScanStart = _takbirScannedCommittedLen;
    // Persisté (pas juste debugPrint) : ce log survit à un logcat qui tourne
    // (buffer limité, évincé par le bruit UI/graphique en quelques secondes,
    // constat réel 2026-07-19 -- plusieurs diagnostics ont échoué faute de
    // cette trace encore disponible au moment de tirer le log).
    DiagnosticLog.log('Prière', 'standby -- en attente du début d\'Al-Fatiha '
        '(sourate suivie mémorisée : ${_originalTargetWords?.length ?? 0} mots)');
    state = state.copyWith(prayerPhase: PrayerPhase.standby);
  }

  /// Bascule vers Al-Fatiha dès que son début est reconnu (cf.
  /// _looksLikeFatihaStart). No-op si la phase a déjà changé entre-temps
  /// (course avec un autre takbir/détection) ou si Al-Fatiha est
  /// indisponible (échec réseau -- on reste en standby, mode confiant donc
  /// aucun blocage de toute façon).
  Future<void> _beginFatihaPhase() async {
    await _ensureFatihaWords();
    final fatiha = _fatihaWords;
    if (fatiha == null || fatiha.isEmpty) return;
    if (state.prayerPhase != PrayerPhase.standby) return;
    final fresh =
        fatiha.map((w) => w.copyWith(status: WordStatus.pending, locked: false)).toList();
    fresh[0] = fresh[0].copyWith(status: WordStatus.current);
    _anchorExp = 0;
    _lastAnchorAdvanceAt = DateTime.now();
    _prevCommitted = '';
    _fatihaScanStart = _takbirScannedCommittedLen;
    state = state.copyWith(
      words: fresh,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.fatiha,
    );
    await _verifier.replaceAlignmentTarget(
        fatiha.map((w) => w.alignTarget).toList(), 0,
        refMinFrames: _refMinFrames(fatiha));
    DiagnosticLog.log('Prière', 'Al-Fatiha reconnue -- suivi actif (${fatiha.length} mots)');
  }

  /// Al-Fatiha terminée (pointeur au bout) : reprend la sourate suivie à
  /// l'origine depuis SON début -- "je dois recommencer à réciter la vraie
  /// sourate" (demande utilisateur 2026-07-18).
  Future<void> _beginTargetPhase() async {
    final target = _originalTargetWords;
    if (target == null || target.isEmpty) return;
    final fresh =
        target.map((w) => w.copyWith(status: WordStatus.pending, locked: false)).toList();
    fresh[0] = fresh[0].copyWith(status: WordStatus.current);
    _anchorExp = 0;
    _lastAnchorAdvanceAt = DateTime.now();
    _prevCommitted = '';
    state = state.copyWith(
      words: fresh,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.target,
    );
    await _verifier.replaceAlignmentTarget(
        target.map((w) => w.alignTarget).toList(), 0,
        refMinFrames: _refMinFrames(target));
    debugPrint('[Prière] Al-Fatiha terminée -- reprise de la sourate suivie '
        '(${target.length} mots)');
  }

  /// Al-Fatiha terminée, mode "Suivre une prière" (_dynamicTargetDiscovery) :
  /// contrairement à [_beginTargetPhase], AUCUNE sourate n'est déjà connue --
  /// on efface l'affichage et on attend de RECONNAÎTRE (via Shazam,
  /// cf. _onStructured) quelle sourate l'imam a choisie pour cette rak'ah.
  void _beginTargetDetection() {
    _targetDetectScanStart = _takbirScannedCommittedLen;
    // Départ du chrono de plausibilité (cf. _kMaxPlausibleWordsPerSecond,
    // _beginIdentifiedTargetPhase) : borne combien de mots ont PU être
    // récités entre la fin d'Al-Fatiha et le moment de l'identification.
    _lastAnchorAdvanceAt = DateTime.now();
    // Repli "continuité entre rak'ah" (cf. commentaire des champs) : armé
    // dès l'entrée en détection, réarmé tant que du texte NOUVEAU arrive
    // (cf. _onStructured) -- ne se déclenche donc que sur un vrai silence
    // prolongé, jamais pendant une identification encore en cours (même
    // lente, ex. ouverture par lettres disjointes mal transcrite).
    _lastDetectingTargetProbe = '';
    _lastDetectingTargetPreviewTokens = [];
    // Identification en deux temps (cf. _tryIdentifyTargetTwoStep) : repartir
    // à zéro à chaque nouvelle entrée en détection (nouveau rak'ah) -- sinon
    // un candidat provisoire d'un cycle précédent pourrait survivre à tort.
    _provisionalMatch = null;
    _detectWordsConsumed = 0;
    _armDetectingTargetFallbackTimer();
    state = state.copyWith(
      words: const [],
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.detectingTarget,
    );
    debugPrint('[Prière] Al-Fatiha terminée -- identification de la sourate '
        'suivante (Shazam)');
  }

  void _armDetectingTargetFallbackTimer() {
    _detectingTargetFallbackTimer?.cancel();
    _detectingTargetFallbackTimer =
        Timer(_kDetectingTargetSilenceFallbackDelay, () {
      if (state.prayerPhase == PrayerPhase.detectingTarget) {
        _resumeContinuationIfAvailable();
      }
    });
  }

  /// Repli "continuité entre rak'ah" (cf. commentaire des champs
  /// `_lastTargetSurahForContinuation`) : appelé quand le silence se
  /// prolonge en [PrayerPhase.detectingTarget] sans identification aboutie
  /// -- reprend la MÊME sourate que la rak'ah précédente, exactement où elle
  /// s'était arrêtée (pas depuis le début), plutôt que d'attendre
  /// indéfiniment. No-op silencieux si aucune rak'ah précédente n'existe
  /// encore (1er cycle de la session) -- reste alors en détection normale.
  void _resumeContinuationIfAvailable() {
    if (state.prayerPhase != PrayerPhase.detectingTarget) return;
    final surahNumber = _lastTargetSurahForContinuation;
    final anchor = _lastTargetAnchorForContinuation;
    final verses = _currentTargetVerses;
    if (surahNumber == null ||
        anchor == null ||
        verses == null ||
        verses.isEmpty ||
        _currentTargetSurah != surahNumber) {
      return;
    }
    final allWords = _wordsFromVerses(verses);
    if (allWords.isEmpty || anchor >= allWords.length) return;
    final fresh = <RecitedWord>[
      for (var i = 0; i < allWords.length; i++)
        allWords[i].copyWith(
            status: i < anchor ? WordStatus.skipped : WordStatus.pending),
    ];
    fresh[anchor] = fresh[anchor].copyWith(status: WordStatus.current);
    _anchorExp = anchor;
    _lastAnchorAdvanceAt = DateTime.now();
    _prevCommitted = '';
    _targetTrackingScanStart = _takbirScannedCommittedLen;
    state = state.copyWith(
      words: fresh,
      pointer: anchor,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.target,
    );
    unawaited(_verifier.replaceAlignmentTarget(
        allWords.map((w) => w.alignTarget).toList(), anchor,
        refMinFrames: _refMinFrames(allWords)));
    debugPrint('[Prière] silence prolongé, aucune identification -- reprise '
        'de la continuité : sourate $surahNumber depuis le mot '
        '$anchor/${allWords.length}');
  }

  /// Verset + index local (dans ce verset) correspondant à l'index ABSOLU
  /// [wordIndex] dans la liste de mots actuellement suivie (Al-Fatiha ou la
  /// sourate identifiée) -- utilisé par PrayerFollowScreen pour le souffleur
  /// automatique (jouer l'extrait audio du bon mot). `null` hors
  /// [PrayerPhase.fatiha]/[PrayerPhase.target] ou index invalide -- ce mode
  /// n'a pas de `_verses` propre côté écran comme le karaoké classique,
  /// contrairement à lui la sourate suivie n'est même pas connue à l'avance.
  (Verse, int)? verseAndLocalIndexFor(int wordIndex) {
    final verses = switch (state.prayerPhase) {
      PrayerPhase.fatiha => _fatihaVerses,
      PrayerPhase.target => _currentTargetVerses,
      _ => null,
    };
    if (verses == null || wordIndex < 0) return null;
    var offset = 0;
    for (final v in verses) {
      final count = ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      if (wordIndex < offset + count) return (v, wordIndex - offset);
      offset += count;
    }
    return null;
  }

  /// Sourate identifiée (Shazam) pendant [PrayerPhase.detectingTarget] :
  /// charge sa liste complète de mots, place l'ancre sur le mot exact du
  /// verset identifié (les mots d'avant -- non entendus par l'ASR avant
  /// détection -- sont marqués `skipped`, jamais jugés faux) et bascule en
  /// suivi actif. Retourne `false` (rejeté, RIEN commité) si la phase a déjà
  /// changé entre-temps ou si le fetch échoue -- appelée par
  /// `_tryIdentifyTargetTwoStep` UNE FOIS le candidat déjà confirmé (plus de
  /// garde-fou de confiance/plausibilité ici, la confirmation par
  /// continuation en tient lieu).
  Future<bool> _beginIdentifiedTargetPhase(QuranMatch match) async {
    if (state.prayerPhase != PrayerPhase.detectingTarget) return false;
    List<Verse> verses;
    try {
      verses = await QuranApi.fetchVerses(match.surahNumber);
    } catch (e) {
      debugPrint('[Prière] échec chargement sourate identifiée '
          '(${match.surahNumber}) : $e');
      return false;
    }
    if (state.prayerPhase != PrayerPhase.detectingTarget) return false;
    final allWords = _wordsFromVerses(verses);
    // Ancre = nombre de mots des versets AVANT celui identifié (reprise
    // possible au milieu de la sourate, pas forcément au verset 1).
    var anchor = 0;
    for (final v in verses) {
      if (v.ayahNumber < match.ayahNumber) {
        anchor += ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      }
    }
    if (allWords.isEmpty) return false;
    anchor = anchor.clamp(0, allWords.length - 1);
    // Garde-fou de plausibilité RETIRÉ ici (constat device 2026-07-19) :
    // comparer l'ancre (position ABSOLUE dans la sourate identifiée) au temps
    // écoulé depuis la fin d'Al-Fatiha supposait à tort que la récitation
    // reprend TOUJOURS au verset 1 de la nouvelle sourate -- rien n'empêche
    // l'imam de commencer au milieu (confirmé par l'utilisateur). Log réel :
    // requête "ما جعل الله" -> 33:29/33:30 (Al-Ahzab) trouvés avec confiance
    // 0.78-0.87 STABLE sur plus de 10s (8+ passes consécutives), donc
    // clairement un vrai match, mais rejetés en boucle car l'ancre (~500,
    // ces versets sont ~40% dans une sourate de 73) dépassait le nombre de
    // mots jugé "possible" depuis Al-Fatiha -- alors que cette ancre ne
    // représente pas une distance parcourue depuis Al-Fatiha, juste la
    // position du verset choisi par l'imam dans la sourate. Le garde-fou
    // visait à l'origine (cf. §3.10 de SUIVI_PRIERE.md) un faux match à
    // confiance 0.50 sur Al-Baqarah -- déjà exclu aujourd'hui par le seuil
    // _kMinIdentifyConfidence=0.70 à lui seul. Ancien code gardé en trace :
    // if (_lastAnchorAdvanceAt != null) {
    //   final elapsedMs =
    //       DateTime.now().difference(_lastAnchorAdvanceAt!).inMilliseconds;
    //   final maxPlausible =
    //       (elapsedMs / 1000 * _kMaxPlausibleWordsPerSecond).ceil();
    //   if (anchor > maxPlausible) {
    //     debugPrint('[Prière] candidat ${match.surahNumber}:${match.ayahNumber} '
    //         'rejeté : ancre $anchor invraisemblable (max plausible '
    //         '$maxPlausible mots en ${elapsedMs}ms depuis la fin d\'Al-Fatiha) '
    //         '-- candidat suivant');
    //     return false;
    //   }
    // }
    // Identification aboutie -- plus besoin du repli de continuité (cf.
    // _armDetectingTargetFallbackTimer) pour ce cycle.
    _detectingTargetFallbackTimer?.cancel();
    final fresh = <RecitedWord>[
      for (var i = 0; i < allWords.length; i++)
        allWords[i].copyWith(
            status: i < anchor ? WordStatus.skipped : WordStatus.pending),
    ];
    fresh[anchor] = fresh[anchor].copyWith(status: WordStatus.current);
    _anchorExp = anchor;
    _lastAnchorAdvanceAt = DateTime.now();
    _prevCommitted = '';
    _currentTargetVerses = verses;
    _currentTargetSurah = match.surahNumber;
    _targetTrackingScanStart = _takbirScannedCommittedLen;
    state = state.copyWith(
      words: fresh,
      pointer: anchor,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.target,
    );
    await _verifier.replaceAlignmentTarget(
        allWords.map((w) => w.alignTarget).toList(), anchor,
        refMinFrames: _refMinFrames(allWords));
    DiagnosticLog.log('Prière', 'sourate identifiée : ${match.surahNumber}:'
        '${match.ayahNumber} (confiance ${match.confidence.toStringAsFixed(2)}) '
        '-- suivi actif dès le mot $anchor/${allWords.length}');
    return true;
  }

  // ANCIENNE APPROCHE (gardée en référence, convention du projet -- "ne
  // supprime rien, mets l'ancienne fonction en commentaire") : un seul appel
  // Shazam sur la requête ENTIÈRE accumulée depuis la fin d'Al-Fatiha, qui
  // grossit sans cesse tant que `detectingTarget` dure. Essayait chaque
  // candidat DANS L'ORDRE du score jusqu'à ce qu'un candidat passe tous les
  // garde-fous (pas "1:1", confiance suffisante) -- déjà un progrès sur un
  // essai unique (constat 2026-07-19 : requête "ما جعل الله" -> meilleur
  // candidat coïncidentiel "50:26" rejeté, alors que "33:4" -- la vraie
  // sourate récitée -- était probablement aussi dans la liste).
  //
  // REMPLACÉE (2026-07-19, retour utilisateur : "c'est pas logique, dans deux
  // versets il y a 20 mots, s'il a détecté 5 mots qui se suivent bien... il
  // n'aura même pas besoin des deux versets") : le score `_orderedOverlap`
  // est `matched / longueur_totale_de_la_requête` -- une requête qui GROSSIT
  // (du bruit ASR s'ajoute sur les mots suivant un bon match) DILUE le score
  // d'un match par ailleurs excellent, au lieu de le laisser confirmé
  // rapidement. Cf. _tryIdentifyTargetTwoStep ci-dessous : deux fenêtres
  // FIXES et courtes (candidat provisoire + confirmation par continuation)
  // au lieu d'une requête cumulative sans borne.
  //
  // Future<void> _tryIdentifyTarget(String probe) async {
  //   _targetLookupInFlight = true;
  //   try {
  //     final matches = await QuranVerseLocatorService.instance.locateTopMatches(probe);
  //     if (matches.isEmpty || state.prayerPhase != PrayerPhase.detectingTarget) {
  //       return;
  //     }
  //     for (final match in matches) {
  //       if (match.surahNumber == 1) {
  //         debugPrint('[Prière] candidat "1:1" ignoré (bismillah/fin '
  //             'd\'Al-Fatiha encore dans la fenêtre récente) -- candidat suivant');
  //         continue;
  //       }
  //       if (match.confidence < _kMinIdentifyConfidence) {
  //         debugPrint('[Prière] candidat ${match.surahNumber}:${match.ayahNumber} '
  //             'ignoré : confiance trop faible '
  //             '(${match.confidence.toStringAsFixed(2)} < $_kMinIdentifyConfidence) '
  //             '-- candidat suivant');
  //         continue;
  //       }
  //       if (await _beginIdentifiedTargetPhase(match)) return;
  //       if (state.prayerPhase != PrayerPhase.detectingTarget) return;
  //     }
  //     debugPrint('[Prière] aucun candidat exploitable parmi ${matches.length} '
  //         '-- nouvelle tentative au prochain texte reconnu');
  //   } catch (e) {
  //     debugPrint('[Prière] échec locate() (identification) : $e');
  //   } finally {
  //     _targetLookupInFlight = false;
  //   }
  // }

  /// Identification en DEUX temps (cf. commentaire des champs
  /// `_provisionalMatch`/`_detectWordsConsumed`) : une première fenêtre FIXE
  /// de [_kProvisionalWindowWords] mots donne un candidat PROVISOIRE (seuil
  /// bas, `_kProvisionalMinConfidence`) ; la fenêtre SUIVANTE de
  /// [_kConfirmWindowWords] mots est comparée à la VRAIE continuation du
  /// candidat dans le texte du Coran (pas un rescoring de la requête
  /// cumulée) -- confirmée seulement si elle colle (`_kConfirmMinConfidence`).
  /// Sur échec de confirmation, la fenêtre ratée devient la NOUVELLE première
  /// fenêtre d'un nouvel essai (rien n'est réessayé deux fois, "recherche 4-6
  /// mots suivant" -- demande utilisateur).
  Future<void> _tryIdentifyTargetTwoStep(String cleanedProbe) async {
    if (_targetLookupInFlight) return;
    final allWords = cleanedProbe
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    _targetLookupInFlight = true;
    try {
      if (_provisionalMatch == null) {
        final remaining = allWords.skip(_detectWordsConsumed).toList();
        if (remaining.length < _kProvisionalWindowWords) return;
        final windowWords = remaining.take(_kProvisionalWindowWords).toList();
        final matches = await QuranVerseLocatorService.instance.locateTopMatches(
            windowWords.join(' '),
            minScore: _kProvisionalMinConfidence);
        QuranMatch? picked;
        for (final m in matches) {
          if (m.surahNumber == 1) continue; // bismillah/fin Fatiha résiduelle
          picked = m;
          break;
        }
        // Avance TOUJOURS (trouvé ou pas) -- ne jamais retenter la MÊME
        // fenêtre indéfiniment, cf. "sinon recherche 4-6 mots suivant".
        _detectWordsConsumed += _kProvisionalWindowWords;
        if (picked != null) {
          _provisionalMatch = picked;
          DiagnosticLog.log('Prière', 'candidat PROVISOIRE ${picked.surahNumber}:'
              '${picked.ayahNumber} (confiance ${picked.confidence.toStringAsFixed(2)}) '
              '-- en attente de confirmation');
        } else {
          debugPrint('[Prière] aucun candidat sur cette fenêtre de '
              '$_kProvisionalWindowWords mots -- fenêtre suivante');
        }
        return;
      }

      // Un candidat provisoire existe déjà -- chercher la fenêtre de
      // CONFIRMATION (mots reconnus JUSTE APRÈS la fenêtre provisoire).
      final remaining = allWords.skip(_detectWordsConsumed).toList();
      if (remaining.length < _kConfirmWindowWords) return;
      final confirmWindow = remaining.take(_kConfirmWindowWords).toList();
      final provisional = _provisionalMatch!;
      final continuation = await QuranVerseLocatorService.instance
          .continuationWords(provisional.surahNumber, provisional.ayahNumber,
              _kConfirmWindowWords + 15); // marge -- offset exact dans le verset inconnu
      final score = QuranVerseLocatorService.instance
          .scoreWordWindows(confirmWindow, continuation);
      if (score >= _kConfirmMinConfidence) {
        DiagnosticLog.log('Prière', 'candidat ${provisional.surahNumber}:'
            '${provisional.ayahNumber} CONFIRMÉ (score continuation '
            '${score.toStringAsFixed(2)})');
        _provisionalMatch = null;
        _detectWordsConsumed = 0;
        await _beginIdentifiedTargetPhase(provisional);
      } else {
        DiagnosticLog.log('Prière', 'confirmation échouée pour '
            '${provisional.surahNumber}:${provisional.ayahNumber} '
            '(score ${score.toStringAsFixed(2)} < $_kConfirmMinConfidence) -- '
            'la fenêtre de confirmation devient le nouvel essai');
        // NE PAS avancer _detectWordsConsumed ici : au prochain appel,
        // `remaining` (donc `confirmWindow` et la suite) redevient la
        // PREMIÈRE fenêtre d'un nouvel essai -- rien n'est perdu, rien n'est
        // réessayé deux fois.
        _provisionalMatch = null;
      }
    } catch (e) {
      debugPrint('[Prière] échec identification en deux temps : $e');
    } finally {
      _targetLookupInFlight = false;
    }
  }

  bool _leftFatihaCheckInFlight = false;

  /// Détecte la fin d'Al-Fatiha par un signal INDÉPENDANT du mot de clôture
  /// exact (cf. commentaire d'appel, `_looksLikeFatihaEnd`) : si la même
  /// recherche Shazam qui sert au rattrapage (`_maybeResyncPosition`)
  /// retrouve, avec une confiance suffisante, un passage qui n'appartient
  /// PLUS à Al-Fatiha (sourate ≠ 1), c'est la preuve qu'on a quitté Al-Fatiha
  /// -- peu importe si le mot de clôture lui-même a été bien transcrit.
  /// Seuil aligné sur `_kMinIdentifyConfidence` (0.70) : cette vérification
  /// déclenche un changement de PHASE, pas un simple rattrapage de position,
  /// donc mérite la même rigueur que la première identification.
  Future<void> _checkLeftFatihaViaShazam(String probe) async {
    if (_leftFatihaCheckInFlight || probe.isEmpty) return;
    if (state.prayerPhase != PrayerPhase.fatiha) return;
    _leftFatihaCheckInFlight = true;
    try {
      final match = await QuranVerseLocatorService.instance.locate(probe);
      if (match == null || match.surahNumber == 1) return;
      if (match.confidence < _kMinIdentifyConfidence) return;
      if (state.prayerPhase != PrayerPhase.fatiha) return; // phase déjà changée entre-temps
      DiagnosticLog.log('Prière', 'Al-Fatiha visiblement terminée (Shazam retrouve '
          '${match.surahNumber}:${match.ayahNumber} hors Al-Fatiha, confiance '
          '${match.confidence.toStringAsFixed(2)}) -- bascule');
      if (_dynamicTargetDiscovery) {
        _beginTargetDetection();
      } else {
        unawaited(_beginTargetPhase());
      }
    } finally {
      _leftFatihaCheckInFlight = false;
    }
  }

  /// Resynchronisation continue (cf. commentaire des champs
  /// `_currentTargetVerses`/`_resyncInFlight`) : relance le moteur de
  /// localisation "Shazam" sur le texte reconnu depuis [scanStart] pendant
  /// [PrayerPhase.fatiha]/[PrayerPhase.target], et rattrape l'ancre si une
  /// position PLUS AVANCÉE (même sourate) est retrouvée -- jamais en arrière,
  /// jamais vers une autre sourate (constat réel : la passe GOP peut rester
  /// bloquée loin derrière ce qui est réellement récité).
  void _maybeResyncPosition({
    required String probe,
    required int surahNumber,
    required List<Verse>? verses,
  }) {
    if (_resyncInFlight || verses == null || probe.isEmpty) return;
    _resyncInFlight = true;
    QuranVerseLocatorService.instance.locate(probe).then((match) {
      _resyncInFlight = false;
      if (match == null || match.surahNumber != surahNumber) return;
      // Toujours la phase visée (pas de course avec un takbir/une bascule
      // entre-temps) -- comparé après l'await, l'état a pu changer.
      if (state.prayerPhase != PrayerPhase.fatiha &&
          state.prayerPhase != PrayerPhase.target) {
        return;
      }
      // Même seuil strict que l'identification initiale (cf.
      // _kMinIdentifyConfidence) : un rattrapage n'est pas moins risqué
      // qu'une première identification, un score limite peut tout autant
      // tomber sur un verset éloigné qui partage un mot ou deux (constat réel
      // utilisateur 2026-07-19 : "je récite ayat 5... il y a le même mot ou
      // deux dans ayat 15, ça active la 15").
      if (match.confidence < _kMinIdentifyConfidence) return;
      var newAnchor = 0;
      for (final v in verses) {
        if (v.ayahNumber >= match.ayahNumber) break;
        newAnchor += ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
      }
      newAnchor = newAnchor.clamp(0, state.words.length);
      if (newAnchor <= _anchorExp) return; // pas en avance -- rien à rattraper
      // Garde-fou de plausibilité (cf. _kMaxPlausibleWordsPerSecond) : le
      // saut proposé ne doit pas dépasser ce qu'il est PHYSIQUEMENT possible
      // d'avoir récité depuis le dernier avancement confirmé de l'ancre.
      if (_lastAnchorAdvanceAt != null) {
        final elapsedMs =
            DateTime.now().difference(_lastAnchorAdvanceAt!).inMilliseconds;
        final maxPlausible =
            (elapsedMs / 1000 * _kMaxPlausibleWordsPerSecond).ceil();
        final jump = newAnchor - _anchorExp;
        if (jump > maxPlausible) {
          debugPrint('[Prière] resynchronisation ignorée : saut de $jump '
              'mots invraisemblable en ${elapsedMs}ms (max plausible '
              '$maxPlausible) -- probable faux match Shazam sur un mot '
              'partagé avec un verset éloigné');
          return;
        }
      }
      final words = [...state.words];
      for (var i = _anchorExp; i < newAnchor && i < words.length; i++) {
        if (!words[i].locked) {
          words[i] = words[i].copyWith(status: WordStatus.skipped, locked: true);
        }
      }
      _anchorExp = newAnchor;
      _lastAnchorAdvanceAt = DateTime.now();
      for (var i = 0; i < words.length; i++) {
        if (i != newAnchor && words[i].status == WordStatus.current) {
          words[i] = words[i].copyWith(status: WordStatus.pending);
        }
      }
      if (newAnchor < words.length &&
          words[newAnchor].status == WordStatus.pending) {
        words[newAnchor] = words[newAnchor].copyWith(status: WordStatus.current);
      }
      state = state.copyWith(words: words, pointer: newAnchor);
      unawaited(_verifier.setAlignmentAnchor(newAnchor));
      debugPrint('[Prière] resynchronisation (Shazam) : ancre rattrapée à '
          '$newAnchor (verset ${match.surahNumber}:${match.ayahNumber}, '
          'confiance ${match.confidence.toStringAsFixed(2)})');
    }).catchError((e) {
      _resyncInFlight = false;
      debugPrint('[Prière] échec locate() (resynchronisation) : $e');
    });
  }

  // ── `_collectedClips` / `takeCollectedClips()` SUPPRIMÉS (2026-07-25) ────
  // Cette liste servait à sélectionner, parmi les WAV écrits par Kotlin, les
  // seuls segments 100 % corrects, pour les remonter vers un stockage
  // permanent en vue du mini-LoRA de personnalisation vocale. L'objectif
  // (entraînement sur le téléphone) est abandonné ; les WAV servent
  // désormais au diagnostic de la chaîne ASR et sont TOUS conservés, écrits
  // directement par Kotlin dans un dossier durable. Plus rien à collecter ni
  // à déplacer côté Dart -- cf. le commentaire détaillé dans `_onAligned`
  // (là où vivait le filtre) et VoiceLoraClipService.

  /// Applique une sensibilité 0.0 (tolérant) .. 1.0 (strict) aux seuils GOP,
  /// EFFECTIVE DÈS LE PROCHAIN MOT JUGÉ (pas besoin de redémarrer la
  /// session) -- demande utilisateur 2026-07-12 : réglable "surtout pour
  /// celui qui récite", donc en cours de récitation, pas seulement avant.
  void setSensitivity(double sensitivity) {
    final s = sensitivity.clamp(0.0, 1.0);
    // Réglable EN DIRECT pendant la récitation -> tracé, sinon deux lignes
    // [GOP] du même run peuvent avoir été jugées sous des seuils différents
    // sans que rien ne l'indique.
    DiagnosticLog.log('MODE',
        'sensibilite -> ${s.toStringAsFixed(2)} (etait ${_lastSensitivity.toStringAsFixed(2)})');
    _lastSensitivity = s;
    if (s <= 0.5) {
      final t = s / 0.5;
      _gopCorrect = _lerp(_kGopCorrectTolerant, _kGopCorrectDefault, t);
      _gopUnclear = _lerp(_kGopUnclearTolerant, _kGopUnclearDefault, t);
    } else {
      final t = (s - 0.5) / 0.5;
      _gopCorrect = _lerp(_kGopCorrectDefault, _kGopCorrectStrict, t);
      _gopUnclear = _lerp(_kGopUnclearDefault, _kGopUnclearStrict, t);
    }
    // Le garde-fou "trou d'alignement" suit le même curseur (cf. sa
    // déclaration) : interpolé de bout en bout, il n'a pas de palier central
    // à distinguer.
    _freeConfident = _lerp(_kFreeConfidentTolerant, _kFreeConfidentStrict, s);
    DiagnosticLog.log('MODE',
        'seuils -> correct=${_gopCorrect.toStringAsFixed(2)} '
        'unclear=${_gopUnclear.toStringAsFixed(2)} '
        'trouAlignement(free)=${_freeConfident.toStringAsFixed(2)}');
  }

  /// Vrai pendant le stop() — empêche le double-stop et préserve le statut
  /// "processing" pendant que l'ASR tourne dans son isolate.
  bool _stopping = false;

  /// Vrai entre stopContinuous() et la vidange complète de la file de
  /// segments — le statut reste "processing" tant que pendingSegments > 0.
  bool _endingContinuous = false;

  /// Génération de session capturée juste après _verifier.start() (cf.
  /// Finding #1, revue de code 2026-07-16) — repassée à
  /// stopIfCurrentSession() au dispose pour que ce nettoyage fire-and-forget
  /// ne s'applique QUE si aucune session plus récente n'a démarré depuis
  /// (sinon il saboterait cette nouvelle session sur réouverture rapide de
  /// l'écran). -1 = aucune session démarrée par ce notifier.
  int _myGeneration = -1;

  /// Dernière ligne [TEXTDIFF] journalisée par index de mot — sert à ne
  /// journaliser que les CHANGEMENTS de verdict (cf. _realignFromFullText).
  /// Vidé à chaque nouvelle cible : les index changent de signification.
  final Map<int, String> _lastTextDiffLine = {};

  /// Verdict NÉGATIF vu sur les aperçus successifs, par index de mot, et
  /// nombre d'aperçus consécutifs où il est resté identique.
  ///
  /// Sert à déclencher la correction dès le **2e aperçu au verdict identique**,
  /// sans attendre le gel du segment (2026-07-25, validé par l'utilisateur).
  /// Mesure qui l'impose : sur une correction réelle, le mot 30 "هُمْ" a été
  /// jugé `error` sur **quatre aperçus consécutifs** (17:08:56.704, .708, .711,
  /// .715) avec `lock=false`, et la correction n'a été déclenchée qu'au gel, à
  /// 17:08:58.550 -- 1,84 s d'attente sur une information déjà stable.
  ///
  /// Pourquoi pas dès le 1er aperçu : un aperçu peut mal couvrir la fin d'un
  /// mot, et un recul d'ancre injustifié est bien plus coûteux qu'un léger
  /// délai. Deux aperçus identiques attestent la stabilité sans attendre le
  /// gel. Si des reculs injustifiés apparaissent, monter à 3.
  final Map<int, WordStatus> _previewNegative = {};
  final Map<int, int> _previewNegativeStreak = {};

  /// Numéro de séquence d'alignement (`AlignPayload.seq`) de la DERNIÈRE passe
  /// comptée pour ce mot.
  ///
  /// Indispensable, sinon le compteur est faux (bug mesuré 2026-07-25) : le
  /// même résultat d'alignement peut être traité DEUX fois côté Dart, et les
  /// deux verdicts arrivent à **2 ms d'écart avec des valeurs rigoureusement
  /// identiques** (`mot=41 "ٱلَّذِينَ" gop=-0.25 forced=-4.10 free=-3.85`, deux
  /// fois à 17:35:29.165 et .167). Mon compteur croyait voir une confirmation
  /// sur deux passes ; il ne voyait qu'un doublon. La correction a été
  /// déclenchée, puis 253 ms plus tard la VRAIE passe suivante jugeait le mot
  /// `correct` -- l'utilisateur voyait donc du vert à l'écran et entendait
  /// quand même la correction. Deux verdicts du même `seq` comptent pour un.
  final Map<int, int> _previewNegativeSeq = {};

  /// Mots pour lesquels la correction a déjà été signalée SANS verrouillage
  /// (cf. _previewNegative) -- évite de refirer à chaque aperçu suivant.
  final Set<int> _failureSignalled = {};

  static const int _kPreviewsBeforeCorrection = 2;

  RecitationNotifier(this._verifier) : super(const RecitationSessionState());

  void setup(String arabicText) {
    final words = _wordsFromText(arabicText);
    _lastTextDiffLine.clear();
    _previewNegative.clear();
    _previewNegativeStreak.clear();
    _previewNegativeSeq.clear();
    _failureSignalled.clear();
    state = RecitationSessionState(words: words);
  }

  /// Construit les mots d'un texte SANS annotation de règles (cible
  /// d'alignement = forme canonique). Utilisé pour le texte hors-Coran (Coach
  /// libre) et comme repli. Le modèle stage1b-260h émet quand même ses
  /// symboles librement, mais le chemin FORCÉ ne les attend pas -> léger biais
  /// gop sur les frames de symbole (borné, == comportement d'avant l'annotation).
  static List<RecitedWord> _wordsFromText(String arabicText) =>
      ArabicNormalizer.splitExpectedWords(arabicText)
          .map((w) => RecitedWord(
                display: w,
                normalized: ArabicNormalizer.normalize(w),
                strict: ArabicNormalizer.normalizeStrict(w),
                training: ArabicNormalizer.normalizeTraining(w),
              ))
          .toList();

  /// Planchers de durée de référence PARALLÈLES à la cible d'alignement
  /// envoyée au natif — toujours construits à partir de la MÊME liste de mots
  /// que `alignTarget`, pour que les deux listes ne puissent pas se
  /// désynchroniser (cf. ForcedAligner.combinedMinFrames).
  static List<int?> _refMinFrames(List<RecitedWord> words) =>
      words.map((w) => w.refMinFrames).toList();

  /// Construit les mots d'un ou plusieurs segments AVEC annotation de règles
  /// tajwid quand la clé de verset est connue et présente dans l'asset :
  /// la cible d'alignement forcé (`alignTarget`) devient la forme apprise par
  /// le modèle (lettres + harakat + symboles), et `expectedRules` liste les
  /// règles portées par chaque mot. Mapping POSITIONNEL : garanti par la
  /// génération de l'asset (nombre de mots annotés == canoniques par verset) ;
  /// tout écart de comptage retombe en silence sur le canonique (sûr) plutôt
  /// que de risquer un décalage mot-à-mot.
  static List<RecitedWord> _wordsFromSegments(List<RecitationSegment> segments) {
    final out = <RecitedWord>[];
    for (final seg in segments) {
      final canonWords = ArabicNormalizer.splitExpectedWords(seg.text);
      List<String>? annotated;
      List<int>? refMs;
      if (seg.surah != null && seg.ayah != null) {
        annotated =
            RuleAnnotationService.instance.annotatedWords(seg.surah!, seg.ayah!);
        if (annotated != null && annotated.length != canonWords.length) {
          // Décalage inattendu (marques de waqf comptées différemment, etc.) :
          // ne pas risquer un mauvais alignement mot-à-mot, revenir au canonique.
          DiagnosticLog.log('Rules',
              'décalage annot ${seg.surah}:${seg.ayah} '
              '(${annotated.length} vs ${canonWords.length} mots) -> canonique');
          annotated = null;
        }
        // Durées de référence : MÊME précaution positionnelle que les
        // annotations juste au-dessus, et pour la même raison. L'asset est
        // généré contre `text_uthmani.split()` alors qu'on découpe ici avec
        // splitExpectedWords -- tout écart de comptage doit retomber sur
        // "aucune référence" (le plancher CTC reste seul), jamais sur un
        // décalage silencieux qui attribuerait la durée d'un mot à son voisin.
        refMs = WordTimingService.instance.msForVerse(seg.surah!, seg.ayah!);
        if (refMs != null && refMs.length != canonWords.length) {
          DiagnosticLog.log('WordTiming',
              'décalage durées ${seg.surah}:${seg.ayah} '
              '(${refMs.length} vs ${canonWords.length} mots) -> sans référence');
          refMs = null;
        }
      }
      // Bismillah = TOUJOURS le verset 1:1 verbatim, qu'elle soit Al-Fatiha
      // elle-même ou insérée devant une autre sourate (cf. QuranApi.fetchBismillah,
      // karaoke_recitation_screen._buildChunk : `segments.add((surah: 1, ayah: 1, ...))`
      // dans les deux cas) -- ce tag suffit à identifier les 4 mots sans dépendre
      // du contexte d'appel.
      final isBasmalaSeg = seg.surah == 1 && seg.ayah == 1;
      for (var i = 0; i < canonWords.length; i++) {
        final w = canonWords[i];
        final aw = annotated?[i];
        // PRIORITE (2026-07-27, demande utilisateur) : la durée mesurée dans
        // la voix de l'utilisateur REMPLACE celle importée de quran.com dès
        // qu'elle existe. Elle est meilleure sur les deux axes qui comptent :
        // c'est une durée ARTICULÉE (pas une borne incluant le silence
        // jusqu'au mot suivant, cf. le « هُمُ » à 3030 ms qui avait imposé le
        // facteur ×0,4), et elle existe pour ce que l'utilisateur récite
        // vraiment — là où quran.com ne couvre que 1 % des versets de 41+ mots.
        // Repli sur quran.com tant que le mot n'a jamais été validé : il
        // couvre bien les versets courts (98 % sous 5 mots).
        // `training` = la clé du magasin : c'est aussi ce que devient
        // `alignTarget` ici (passé à null juste en dessous), donc la même forme
        // que celle sous laquelle la durée a été apprise.
        final training = ArabicNormalizer.normalizeTraining(w);
        final learned = WordDurationStore.instance.minFramesFor(training);
        final refMinFrames = learned ??
            (refMs == null ? null : WordTimingService.minFramesFromMs(refMs[i]));
        out.add(RecitedWord(
          display: w,
          normalized: ArabicNormalizer.normalize(w),
          strict: ArabicNormalizer.normalizeStrict(w),
          training: training,
          isBasmala: isBasmalaSeg,
          // Cible d'alignement = texte NU (lettres + harakat), PAS la forme
          // annotée : voir la note « INVALIDÉ PAR LA MESURE » sur
          // RecitedWord.alignTarget. Aligner sur les symboles de règles
          // contaminait le jugement de prononciation par le tajwid dans tous
          // les modes. `expectedRules` (ci-dessous) reste extrait de la forme
          // annotée : les règles restent connues, elles serviront à une
          // vérification SÉPARÉE.
          alignTarget: null,
          expectedRules: aw != null ? RuleSymbols.rulesIn(aw) : const [],
          refMinFrames: refMinFrames,
        ));
      }
    }
    return out;
  }

  /// Variante verset-consciente de [setup] : annote les règles tajwid. À
  /// préférer dès que l'appelant connaît les versets (karaoké). Précharge les
  /// annotations si besoin (idempotent, sans coût après le 1er chargement).
  Future<void> setupVerses(List<RecitationSegment> segments) async {
    await RuleAnnotationService.instance.ensureLoaded();
    await WordTimingService.instance.ensureLoaded();
    await WordDurationStore.instance.ensureLoaded();
    _lastTextDiffLine.clear();
    _previewNegative.clear();
    _previewNegativeStreak.clear();
    _previewNegativeSeq.clear();
    _failureSignalled.clear();
    state = RecitationSessionState(words: _wordsFromSegments(segments));
  }

  /// Mots annotés d'une liste de [Verse] (chacun sait sa surah/ayah) — raccourci
  /// pour les chemins qui tiennent déjà des Verse (Al-Fatiha, cible identifiée
  /// par Shazam). L'appelant doit avoir chargé les annotations au préalable
  /// (ensureLoaded) ; à défaut, repli canonique par mot (sûr).
  static List<RecitedWord> _wordsFromVerses(List<Verse> verses) =>
      _wordsFromSegments([
        for (final v in verses)
          (surah: v.surahNumber, ayah: v.ayahNumber, text: v.textUthmani),
      ]);

  /// Étend la session EN COURS avec du texte supplémentaire (enchaînement sur
  /// la sourate suivante, demande utilisateur 2026-07-11) — contrairement à
  /// [setup], ne touche RIEN de la progression déjà acquise (mots jugés,
  /// pointeur, ancre d'alignement) : ajoute seulement de nouveaux mots
  /// "pending" à la fin de la liste, et étend la cible native en conséquence
  /// SANS bouger son ancre (cf. RecitationVerifier.extendAlignmentTarget) —
  /// la récitation continue exactement où elle en était, juste avec plus de
  /// texte à réciter derrière.
  Future<void> extendWords(String moreArabicText) async {
    final newWords = _wordsFromText(moreArabicText);
    if (newWords.isEmpty) return;
    state = state.copyWith(words: [...state.words, ...newWords]);
    await _verifier
        .extendAlignmentTarget(newWords.map((w) => w.alignTarget).toList(),
            refMinFrames: _refMinFrames(newWords));
  }

  /// Variante verset-consciente de [extendWords] : annote les règles tajwid
  /// des nouveaux versets enchaînés (page suivante du Mushaf). Même contrat
  /// que [extendWords] par ailleurs (n'altère rien de la progression acquise).
  Future<void> extendVerses(List<RecitationSegment> segments) async {
    await RuleAnnotationService.instance.ensureLoaded();
    await WordTimingService.instance.ensureLoaded();
    await WordDurationStore.instance.ensureLoaded();
    final newWords = _wordsFromSegments(segments);
    if (newWords.isEmpty) return;
    state = state.copyWith(words: [...state.words, ...newWords]);
    await _verifier
        .extendAlignmentTarget(newWords.map((w) => w.alignTarget).toList(),
            refMinFrames: _refMinFrames(newWords));
  }

  Future<void> start() async {
    if (state.words.isEmpty || state.isActive) return;
    final reset = state.words
        .map((w) => w.copyWith(status: WordStatus.pending))
        .toList();
    if (reset.isNotEmpty) reset[0] = reset[0].copyWith(status: WordStatus.current);
    state = state.copyWith(
      words: reset,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      status: RecitationStatus.listening,
      rawTranscript: '',
    );
    _tokenSub = _verifier.tokens.listen(_onToken);
    _levelSub = _verifier.soundLevel
        .listen((lvl) => state = state.copyWith(soundLevel: lvl));
    _rawSub = _verifier.rawTranscript.listen(_onRawSegment);
    _alignSub = _verifier.alignedWords.listen(_onAligned);
    // Forme fidèle à l'entraînement (PAS `strict`, qui fusionne des lettres
    // que le modèle a appris à distinguer — cf. normalizeTraining).
    await _verifier.start(state.words.map((w) => w.alignTarget).toList(),
        refMinFrames: _refMinFrames(state.words));
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Démarre une récitation continue (plusieurs versets/une sourate entière),
  /// segmentée automatiquement par détection de silence (VAD). [arabicText]
  /// doit couvrir tout le fragment à réciter (setup() l'a déjà découpé en mots).
  Future<void> startContinuous() async {
    if (state.words.isEmpty || state.isActive) return;
    final reset = state.words.map((w) => w.copyWith(status: WordStatus.pending)).toList();
    if (reset.isNotEmpty) reset[0] = reset[0].copyWith(status: WordStatus.current);
    _endingContinuous = false;
    state = state.copyWith(
      words: reset,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      status: RecitationStatus.listening,
      rawTranscript: '',
      continuous: true,
      pendingSegments: 0,
      prayerPhase: PrayerPhase.none,
    );
    _prevCommitted = '';
    _anchorExp = 0;
    _takbirScannedCommittedLen = 0;
    _takbirArmed = true;
    _originalTargetWords = null;
    _dynamicTargetDiscovery = false;

    // Prefetch Al-Fatiha en tâche de fond (mode confiant) : prête AVANT le
    // premier takbir plutôt que de découvrir un réseau indisponible en pleine
    // salât.
    if (_confidentMode) unawaited(_ensureFatihaWords());
    _tokenSub = _verifier.tokens.listen(_onToken);
    _levelSub = _verifier.soundLevel
        .listen((lvl) => state = state.copyWith(soundLevel: lvl));
    _structSub = _verifier.structuredTranscript.listen(_onStructured);
    _pendingSub = _verifier.pendingSegments.listen(_onPendingChanged);
    _alignSub = _verifier.alignedWords.listen(_onAligned);
    // ── Diagnostic : WAV + journal, ICI et pas dans un écran (2026-07-25) ──
    // Avant, la capture des WAV était activée par KaraokeRecitationScreen
    // uniquement. Conséquence mesurée le 2026-07-25 : deux tests de suite
    // lancés depuis un AUTRE écran ont produit un log complet mais AUCUN
    // audio (`capture de clips desactivee`), donc impossible de vérifier ce
    // que le modèle avait réellement entendu — exactement l'information qui
    // manquait pour conclure. La capture est une propriété de « une session de
    // récitation tourne », pas d'un écran : elle appartient donc ici, sur le
    // chemin que TOUS les écrans empruntent.
    await _applyDiagnosticCapture();
    // Forme fidèle à l'entraînement — cible de l'alignement forcé GOP.
    await _verifier.start(
      state.words.map((w) => w.alignTarget).toList(),
      continuous: true,
      refMinFrames: _refMinFrames(state.words),
    );
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Aligne l'état du diagnostic natif (journal + capture WAV) sur le réglage
  /// utilisateur, au démarrage de CHAQUE session.
  ///
  /// Les deux sont pilotés par le même interrupteur
  /// ([diagnosticEnabledProvider]) : quand on analyse un log on a besoin de
  /// l'audio correspondant, et quand on mesure le retard sans instrumentation
  /// l'écriture des WAV ne doit pas rester allumée en douce.
  Future<void> _applyDiagnosticCapture() async {
    final on = DiagnosticLog.enabled;
    await _verifier.setLogEnabled(on);
    if (!on) {
      await _verifier.setClipCapture(null);
      return;
    }
    try {
      final dir = await VoiceLoraClipService().newRecitationCaptureDir();
      await _verifier.setClipCapture(dir);
    } catch (e) {
      // Le diagnostic ne doit JAMAIS empêcher une récitation de démarrer.
      DiagnosticLog.log('ASR', 'capture WAV indisponible : $e');
    }
  }

  /// "Suivre une prière" (demande utilisateur 2026-07-18) : point d'entrée
  /// dédié, SANS sourate pré-sélectionnée -- contrairement à
  /// [startContinuous] (qui suppose `state.words` déjà rempli via [setup]),
  /// l'imam peut réciter n'importe quelle sourate après Al-Fatiha, pas
  /// forcément la même d'une rak'ah à l'autre. La session démarre directement
  /// en [PrayerPhase.standby] (attend Al-Fatiha, pas besoin d'un takbir
  /// préalable pour la toute première rak'ah) ; la sourate qui suit chaque
  /// Al-Fatiha est identifiée à la volée via Shazam
  /// (cf. _beginTargetDetection/_beginIdentifiedTargetPhase).
  Future<void> startPrayerFollow() async {
    if (state.isActive) return;
    _dynamicTargetDiscovery = true;
    _confidentMode = true; // ce mode EST le mode confiant, pas une option
    _endingContinuous = false;
    _originalTargetWords = null;
    _prevCommitted = '';
    _anchorExp = 0;
    _takbirScannedCommittedLen = 0;
    _takbirArmed = true;
    _standbyScanStart = 0;
    _targetDetectScanStart = 0;

    unawaited(_ensureFatihaWords());
    state = const RecitationSessionState(
      status: RecitationStatus.listening,
      continuous: true,
      prayerPhase: PrayerPhase.standby,
    );
    _tokenSub = _verifier.tokens.listen(_onToken);
    _levelSub = _verifier.soundLevel
        .listen((lvl) => state = state.copyWith(soundLevel: lvl));
    _structSub = _verifier.structuredTranscript.listen(_onStructured);
    _pendingSub = _verifier.pendingSegments.listen(_onPendingChanged);
    _alignSub = _verifier.alignedWords.listen(_onAligned);
    // Cible vide au départ -- rien à aligner tant qu'Al-Fatiha n'est pas
    // reconnue (cf. fix _startStreamingCapture, recitation_verifier.dart :
    // une cible vide ne doit PAS dégrader la transcription libre).
    await _verifier.start(const [], continuous: true);
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Remplace (pas d'accumulation) : en mode streaming, chaque appel renvoie
  /// déjà le texte COMPLET décodé jusqu'ici ; en mode segment unique (Coach),
  /// il n'y a qu'un seul segment par session donc remplacer == accumuler.
  void _onRawSegment(String txt) {
    // RuleSymbols.strip : "entendu" est un sous-titre pour l'utilisateur, pas
    // un outil de diagnostic -- les symboles de regles (zone privee Unicode)
    // n'ont pas de glyphe dans la police de l'app et s'affichaient en carres
    // vides (tofu). Le jugement tajwid lit RecitedWord.heard (brut, ailleurs),
    // pas ce transcript -- rien ne depend de garder les symboles ici.
    final stripped = RuleSymbols.strip(txt);
    state = state.copyWith(rawTranscript: stripped);
    // Diff textuel : TOUJOURS calculé + journalisé ([TEXTDIFF]) pour pouvoir
    // comparer les deux méthodes sur la même session (demande utilisateur
    // 2026-07-20) -- mais ne PILOTE l'affichage (`apply`) qu'en repli (modèle
    // natif indisponible) ou si l'utilisateur a choisi ce moteur
    // explicitement ; sinon _onAligned (gop) reste l'unique source affichée.
    _realignFromFullText(stripped,
        apply: !_useGopScoring || !_verifier.alignmentActive);
    // Phrase de clôture traditionnelle "Sadaqa Allahu al-'Adhim" (صدق الله
    // العظيم) dite en fin de récitation — la détecter arrête l'écoute
    // automatiquement, en complément du bouton dédié (demande utilisateur
    // 2026-07-09, suite au tap accidentel qui coupait les derniers mots
    // d'An-Nas). Gardée derrière `_anchorExp >= words.length` : elle n'est
    // vérifiée qu'une fois tout le texte attendu déjà atteint, pour ne
    // jamais interrompre une récitation en cours sur une coïncidence de mots
    // (le modèle n'a jamais appris cette formule comme un verset).
    if (_anchorExp >= state.words.length && _hasClosingPhrase(txt)) {
      stopContinuous();
    }
    // Takbir "الله أكبر" (mode "réciteur confiant" 2026-07-18, suivi de
    // prière) : transition entre deux cycles de récitation (ex. nouveau
    // rak'ah) -- le texte qui suit ne correspond plus à ce qu'on était en
    // train de suivre, repartir de zéro plutôt que de continuer à juger
    // contre un texte devenu obsolète. Seulement en mode confiant : dans le
    // mode normal (apprentissage/vérification), on ne veut PAS qu'un takbir
    // entendu par erreur (bruit ASR) réinitialise silencieusement la
    // progression d'un utilisateur qui vérifie sa mémorisation.
    if (_confidentMode && _hasTakbir(txt)) {
      resetTrackingToStart();
    }
  }

  static final _closingPhraseWords =
      ['صدق', 'الله', 'العظيم'].map(ArabicNormalizer.normalize).toList();

  bool _hasClosingPhrase(String rawText) {
    final tokens = ArabicNormalizer.normalize(rawText).split(RegExp(r'\s+'));
    var idx = 0;
    for (final t in tokens) {
      if (t == _closingPhraseWords[idx]) {
        idx++;
        if (idx == _closingPhraseWords.length) return true;
      }
    }
    return false;
  }

  static final _takbirWords =
      ['الله', 'اكبر'].map(ArabicNormalizer.normalize).toList();

  /// Détecte "الله أكبر" (takbir) dans un texte reconnu librement. Simplifié
  /// 2026-07-18 (demande utilisateur, suite à un 1er essai raté sur "الله
  /// أكبر" reconnu "الله الله وأكبر" -- l'ordre/l'adjacence stricte des deux
  /// mots ratait trop souvent sur du bruit ASR réel) : "le plus important,
  /// c'est qu'après Allah et akbar il n'y aura pas de récitation du Coran" --
  /// on exige seulement la PRÉSENCE des deux mots dans le passage reconnu,
  /// peu importe l'ordre ou ce qu'il y a entre les deux (répétitions, écho).
  /// Tolère aussi le second mot collé à un "و" ("وَأَكْبَرُ" -- écriture arabe
  /// normale, la conjonction ne s'écrit jamais séparée).
  bool _hasTakbir(String rawText) {
    final tokens = ArabicNormalizer.normalize(rawText).split(RegExp(r'\s+'));
    final hasAllah = tokens.any((t) => t == _takbirWords[0]);
    final hasAkbar =
        tokens.any((t) => t == _takbirWords[1] || t.endsWith(_takbirWords[1]));
    return hasAllah && hasAkbar;
  }

  /// Réinitialise le suivi (ancre d'alignement + statut de tous les mots)
  /// SANS arrêter la capture ni la session -- pour repartir de zéro sur un
  /// nouveau cycle de récitation (takbir en prière, mode "réciteur confiant"
  /// 2026-07-18). Contrairement à stopContinuous()/reset(), l'écoute continue
  /// sans interruption ; contrairement à setup(), ne touche pas la liste de
  /// mots elle-même (même texte attendu, on reprend juste au début).
  ///
  /// BUG corrigé 2026-07-18 (constat réel, log device) : cette méthode ne
  /// remettait à zéro QUE `_anchorExp` côté Dart -- jamais l'ancre native
  /// (ForcedAligner.kt, pilotée via `setAlignmentAnchor`). Or `_onAligned`
  /// RÉÉCRASE `_anchorExp` avec `p.anchor` (l'ancre native) dès la passe
  /// suivante (cf. "trueExtent" plus bas) : sans ce reset natif, le native
  /// continuait de juger/avancer tout seul sur les mots suivants du texte
  /// D'AVANT le takbir (log réel : mot=17 "فَوَيْلٌ" -> mot=18
  /// "لِّلْمُصَلِّينَ" -> mot=19 "ٱلَّذِينَ", en erreur, PENDANT que
  /// l'utilisateur récitait déjà Al-Fatiha) -- la réinitialisation semblait
  /// n'avoir aucun effet sur le jugement réel, seulement sur l'affichage.
  void resetTrackingToStart() {
    final cleared = state.words
        .map((w) => w.copyWith(status: WordStatus.pending, locked: false))
        .toList();
    if (cleared.isNotEmpty) {
      cleared[0] = cleared[0].copyWith(status: WordStatus.current);
    }
    _anchorExp = 0;
    _prevCommitted = '';
    unawaited(_verifier.setAlignmentAnchor(0));
    state = state.copyWith(
      words: cleared,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
    );
  }

  // Un mot ayant reçu un jugement DÉFINITIF (vert/orange/rouge) est verrouillé
  // pour toujours — aucune passe ultérieure ne peut plus le modifier, dans
  // AUCUN sens. Décision utilisateur 2026-07-05, suite à un test réel : avec
  // la règle précédente ("jamais rétrograder", vert protégé mais rouge
  // librement upgradable), un mot correctement jugé rouge (harakat volontai-
  // rement fautive) est repassé vert dès qu'une repasse ultérieure — bénéfi-
  // ciant de plus de contexte — a vu le modèle "corriger" silencieusement
  // vers le texte canonique (biais du modèle vers les formules très
  // fréquentes, cf. SKILL.md). Verrouiller dans les deux sens élimine ce faux
  // négatif : le premier jugement honnête prime, y compris s'il est rouge.
  //
  // MAIS (bug réel constaté juste après, même jour) : verrouiller aveuglément
  // capture aussi les mots dont la reconnaissance est encore INCOMPLÈTE — le
  // DERNIER mot reconnu d'un aperçu en formation peut n'être qu'à moitié
  // prononcé/décodé (ex: "ايا" pour "اياك", "الرحمه" pour "الرحمان"). Verrouillé
  // trop tôt en rouge, jamais corrigé même quand la passe suivante (mot
  // complet, plus de contexte) le reconnaît parfaitement. Fix : ne verrouiller
  // un mot que s'il n'est PAS le dernier jeton de la passe courante (donc le
  // modèle a bien continué au-delà, preuve que ce mot est acoustiquement
  // "fermé") — sauf si le texte est définitivement figé (segment commit),
  // où là tout se verrouille immédiatement (l'audio de ce segment ne sera
  // plus jamais réanalysé).
  // Fenêtre de tolérance EN ARRIÈRE (demande utilisateur 2026-07-06) :
  // combien de mots déjà validés avant l'ancre peuvent être répétés sans
  // pénalité (reprise d'élan naturelle avant de continuer). Ne concerne QUE
  // les mots déjà jugés/verrouillés -- jamais une recherche en avant.
  // Élargie de 3 à 5 (demande utilisateur 2026-07-09) : après une correction
  // (rewindAndUnlock), le réciteur reprend parfois 3-4 mots AVANT le mot fautif
  // pour un élan naturel avant de le redire -- à 3, le 4e mot de recul sortait
  // de la fenêtre et se faisait juger (à tort) comme une erreur sur le mot
  // attendu courant, au lieu d'être toléré comme une simple reprise.
  static const int _kBackToleranceWindow = 5;

  void _judge(List<RecitedWord> words, int i, WordStatus judged,
      {required bool lock, List<int>? newErrors, String? heard,
      Set<TajwidRule>? detectedRules, int? alignSeq}) {
    if (words[i].locked) return;
    // `heard` : ce qui a été réellement entendu, conservé sur le mot pour
    // pouvoir CLASSER l'erreur ensuite (lettre / harakat / tajwid) --
    // cf. RecitationErrorKind. Passage unique par _judge, donc un seul
    // endroit à alimenter.
    words[i] = words[i].copyWith(status: judged, locked: lock, heard: heard,
        detectedRules: detectedRules);
    // Rouge (faux), orange (imprécis) ET gris (sauté) déclenchent la
    // correction — demande utilisateur 2026-07-05 (rouge/orange) puis
    // 2026-07-06 (sauté) : "pour moi c'est une erreur aussi" — sauter un mot
    // n'est plus juste constaté passivement, ça doit aussi être corrigé.
    final isNegative = judged == WordStatus.error ||
        judged == WordStatus.unclear ||
        judged == WordStatus.skipped;
    if (lock && isNegative) {
      newErrors?.add(i);
      return;
    }
    if (!isNegative) {
      // Le mot est redevenu bon : la série d'aperçus négatifs est cassée, et on
      // oublie AUSSI qu'un échec a été signalé -- sinon une vraie erreur
      // ultérieure sur ce même mot ne serait plus jamais signalée.
      _previewNegative.remove(i);
      _previewNegativeStreak.remove(i);
      _previewNegativeSeq.remove(i);
      _failureSignalled.remove(i);
      return;
    }
    // Négatif mais PAS verrouillé (aperçu). Sans numéro de passe on ne compte
    // rien : mieux vaut attendre le gel que compter un doublon (cf.
    // _previewNegativeSeq).
    if (alignSeq == null) return;
    if (_previewNegativeSeq[i] == alignSeq) return; // même passe, déjà comptée
    _previewNegativeSeq[i] = alignSeq;
    if (_previewNegative[i] == judged) {
      _previewNegativeStreak[i] = (_previewNegativeStreak[i] ?? 1) + 1;
    } else {
      _previewNegative[i] = judged;
      _previewNegativeStreak[i] = 1;
    }
    if (_previewNegativeStreak[i]! >= _kPreviewsBeforeCorrection &&
        _failureSignalled.add(i)) {
      DiagnosticLog.log('Correction',
          'declenchee sur apercu stable : mot=$i statut=$judged '
          '(${_previewNegativeStreak[i]} apercus identiques, sans attendre le gel)');
      newErrors?.add(i);
    }
  }

  /// Aligne séquentiellement [recNorm]/[recStrict] sur les mots attendus à
  /// partir de [from]. [isFinal] : true pour un segment figé (verrouille
  /// tout immédiatement), false pour un aperçu encore révisable (ne
  /// verrouille pas son dernier mot, possiblement incomplet). [newErrors]
  /// collecte les mots FRAÎCHEMENT verrouillés rouge/orange (pour déclencher
  /// la correction automatique après coup). Retourne l'index attendu atteint.
  ///
  /// COMPARAISON DIRECTE, SANS RECHERCHE EN AVANT (demande utilisateur
  /// 2026-07-06 : "je veux même pas que tu vérifies... tu compares juste
  /// avec le mot attendu direct") — chaque jeton reconnu est comparé
  /// UNIQUEMENT au mot attendu à la position courante, jamais à une fenêtre
  /// de mots plus loin. Un saut (l'utilisateur dit un mot plus loin dans le
  /// verset) n'est donc plus "détecté" spécialement : le mot attendu ne
  /// correspond juste à rien, et après quelques tentatives sans
  /// correspondance (voir l'abandon ci-dessous), il est marqué faux comme
  /// n'importe quelle erreur — cohérent avec la demande précédente de
  /// traiter un saut comme une erreur à corriger, pas un cas spécial détecté
  /// par avance.
  int _alignChunk(List<RecitedWord> words, List<String> recNorm,
      List<String> recStrict, int from,
      {required bool isFinal, List<int>? newErrors}) {
    var expIdx = from;
    // Un aperçu (isFinal=false) repart TOUJOURS de _anchorExp, qui n'avance
    // QUE sur du texte figé -- un abandon ("give-up") décidé pendant un
    // aperçu verrouille bien le mot, mais _anchorExp lui-même ne bouge pas.
    // Sans ce saut, l'appel suivant retente le MÊME mot déjà verrouillé,
    // échoue pareil, ré-abandonne, boucle indéfiniment (bug réel constaté
    // 2026-07-06 : "abandon sur ... " répété en continu, récitation bloquée).
    while (expIdx < words.length && words[expIdx].locked) {
      expIdx++;
    }
    for (var r = 0; r < recNorm.length && expIdx < words.length; r++) {
      var tokNorm = recNorm[r];
      var tokStrict = recStrict[r];
      var consumed = 1;
      var sim = ArabicNormalizer.similarity(tokNorm, words[expIdx].normalized);

      if (sim < _kSimThreshold) {
        // AVANT toute tentative de fusion avec le jeton suivant : ce jeton
        // seul n'est-il pas simplement la reprise d'un mot déjà validé, ou
        // l'écho d'une syllabe déjà traitée ? Un mot déjà passé ne doit
        // JAMAIS participer à une fusion avec le mot attendu courant —
        // régression réelle constatée 2026-07-10 (sourate 113) : "برب"
        // (déjà verrouillé juste avant) collé à tort à "الفلق" pour former
        // "بربالفلق", faisant chuter "الفلق" en rouge alors qu'il avait été
        // reconnu parfaitement (sim=1.00) quelques passes plus tôt.
        final prevTok = r > 0 ? recNorm[r - 1] : null;
        final isEcho =
            tokNorm.length <= 2 && prevTok != null && prevTok.endsWith(tokNorm);
        if (isEcho) {
          // Écho/doublon halluciné : un jeton très court qui n'est que la
          // syllabe finale du jeton reconnu JUSTE AVANT — constat réel
          // 2026-07-10 ("الْحَمْدُ" ressort parfois "الْحَمْدُ دُ", la syllabe finale
          // redite comme un "mot" séparé). Aucun vrai mot coranique isolé ne
          // fait 1-2 lettres ; ignorer ce cas précis n'affecte pas la
          // détection de vrais mots sautés/faux.
          debugPrint('[Align] rec="$tokNorm" -> écho/doublon halluciné '
              'ignoré (reprend la fin de "$prevTok")');
          continue;
        }
        // Tolérance sur ce qui est DÉJÀ PASSÉ, exigence sur ce qui VA VENIR
        // (demande utilisateur 2026-07-06) : recherche UNIQUEMENT en
        // arrière, jamais en avant (la règle "comparaison directe, sans
        // recherche en avant" du 2026-07-06 reste intacte pour le mot
        // attendu). Si ça correspond à du passé, c'est toléré sans pénalité.
        if (_matchesRecentPast(words, expIdx, tokNorm)) {
          debugPrint('[Align] rec="$tokNorm" exp=$expIdx -> toléré '
              '(reprise d\'un mot déjà validé, ignoré sans pénalité)');
          continue;
        }
        // Fusion de 2 jetons adjacents mal scindés par l'ASR (constat réel
        // 2026-07-10, sourate 111 : "وما" ressort parfois comme deux jetons
        // séparés par un espace, "و" puis "ما" — le second, isolé, ne matche
        // que partiellement "وما" et se verrouille faux à tort). Seulement
        // maintenant qu'on sait que ce jeton n'est ni un écho ni une reprise
        // du passé -- on ne l'utilise que si elle améliore réellement le
        // score.
        if (r + 1 < recNorm.length) {
          final mergedNorm = recNorm[r] + recNorm[r + 1];
          final simMerged = ArabicNormalizer.similarity(
              mergedNorm, words[expIdx].normalized);
          if (simMerged > sim) {
            tokNorm = mergedNorm;
            tokStrict = recStrict[r] + recStrict[r + 1];
            consumed = 2;
            sim = simMerged;
          }
        }
      }
      if (sim >= _kSimThreshold) {
        final isLastToken = (r + consumed - 1) == recNorm.length - 1;
        final isExact =
            ArabicNormalizer.matchesTolerant(tokStrict, words[expIdx].strict);
        final judged = isExact
            ? WordStatus.correct
            : (sim >= _kUnclearSimThreshold ? WordStatus.unclear : WordStatus.error);
        // Un jugement ERREUR ne se verrouille QUE sur un segment vraiment
        // figé (isFinal) -- jamais sur un simple aperçu, même si ce jeton
        // n'est pas le dernier de la passe (demande/constat utilisateur
        // 2026-07-10, répété sur "لينبذن" ET "الذين" : un aperçu encore
        // instable peut rater la dernière lettre d'un mot, puis un segment
        // figé ULTÉRIEUR reconnaît le même passage correctement -- mais le
        // mot était déjà verrouillé rouge à tort, donc jamais rattrapable).
        // Vert/orange restent verrouillables tôt (aucun souci constaté là).
        final lock = isFinal || (!isLastToken && judged != WordStatus.error);
        debugPrint('[Align] rec="$tokNorm" (strict="$tokStrict") '
            'exp=$expIdx sim=${sim.toStringAsFixed(2)} '
            'exp.norm="${words[expIdx].normalized}" exp.strict="${words[expIdx].strict}" '
            '-> $judged (lock=$lock)'
            '${consumed == 2 ? ' [fusion de 2 jetons]' : ''}');
        _judge(words, expIdx, judged, lock: lock, newErrors: newErrors);
        expIdx++;
        r += consumed - 1;
      } else {
        // L'écho/doublon halluciné et la reprise d'un mot déjà validé sont
        // déjà écartés plus haut (avant la tentative de fusion) -- ce qui
        // arrive ici n'est ni l'un ni l'autre : un vrai signal de bruit/mot
        // inconnu.
        debugPrint('[Align] rec="$tokNorm" exp=$expIdx '
            '("${words[expIdx].normalized}") -> AUCUNE correspondance '
            '(sim=${sim.toStringAsFixed(2)} < seuil $_kSimThreshold, '
            'ni avec un mot déjà passé) -- ignoré comme bruit');
        // Exigence immédiate sur du texte FIGÉ (demande utilisateur
        // 2026-07-06 : un mot inventé/inséré qui ne correspond ni à ce qui
        // vient ni à ce qui est déjà passé doit être détecté tout de suite,
        // pas après plusieurs tentatives). isFinal seulement : un aperçu
        // (isFinal=false) est ré-évalué très souvent PENDANT qu'un mot est
        // encore en train d'être prononcé -- l'audio incomplet produit
        // presque toujours des lectures partielles déformées avant de se
        // stabiliser ; juger sur un aperçu a déjà causé un abandon prématuré
        // en cascade (bug réel constaté 2026-07-06). Une fois le segment
        // FIGÉ (donc l'audio complet), un jeton qui ne correspond à rien de
        // connu est un signal fiable dès la première fois.
        if (isFinal) {
          debugPrint('[Align] "${words[expIdx].display}" ne correspond à '
              'rien de connu -> WordStatus.error immédiat');
          _judge(words, expIdx, WordStatus.error, lock: true, newErrors: newErrors);
          expIdx++;
        }
      }
    }
    return expIdx;
  }

  /// Vrai si [recNorm] ressemble à l'un des [_kBackToleranceWindow] derniers
  /// mots DÉJÀ VALIDÉS (verrouillés) avant [expIdx] — jamais une recherche en
  /// avant, seulement en arrière, et seulement des mots déjà jugés (pas de
  /// mots encore en attente).
  bool _matchesRecentPast(List<RecitedWord> words, int expIdx, String recNorm) {
    final start = (expIdx - _kBackToleranceWindow).clamp(0, expIdx);
    for (var e = start; e < expIdx; e++) {
      if (!words[e].locked) continue;
      if (ArabicNormalizer.similarity(recNorm, words[e].normalized) >= _kSimThreshold) {
        return true;
      }
    }
    return false;
  }

  List<String> _splitNorm(String txt) => txt
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(ArabicNormalizer.normalize)
      .toList();

  List<String> _splitStrict(String txt) => txt
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(ArabicNormalizer.normalizeStrict)
      .toList();

  /// Mode continu : scoring ancré sur les segments figés.
  /// REPLI uniquement — quand l'alignement forcé GOP est actif, _onAligned
  /// juge et cette méthode ne fait plus que rafraîchir le texte affiché.
  void _onStructured(({String committed, String preview}) parts) {
    // Mode "Suivre une prière" (_dynamicTargetDiscovery) : `state.words` est
    // légitimement VIDE pendant standby/detectingTarget (aucune cible connue
    // tant qu'Al-Fatiha ou la sourate suivante n'ont pas été reconnues) --
    // seul le mode normal (aucun cycle de prière) exige des mots déjà chargés.
    if (state.words.isEmpty && state.prayerPhase == PrayerPhase.none) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    if (_verifier.alignmentActive) {
      final display = [parts.committed, parts.preview]
          .where((t) => t.isNotEmpty)
          .join(' ');
      // RuleSymbols.strip : cf. _onRawSegment -- "entendu" est un sous-titre,
      // pas un outil de diagnostic, les symboles de regles s'y affichaient en
      // carres vides (tofu).
      state = state.copyWith(rawTranscript: RuleSymbols.strip(display));
      // Diff textuel TOUJOURS calculé + journalisé ([TEXTDIFF]), en parallèle
      // du gop, pour comparaison (cf. _onRawSegment) -- ne pilote l'affichage
      // que si l'utilisateur a choisi ce moteur. La détection takbir/prière
      // ci-dessous reste active dans les deux cas, indépendante du moteur.
      _realignFromFullText(RuleSymbols.strip(display), apply: !_useGopScoring);
      // BUG corrigé 2026-07-18 : la détection du takbir vivait dans
      // _onRawSegment, qui n'est abonnée qu'en mode segment unique (Coach,
      // cf. start()) -- jamais en mode continu (karaoké, startContinuous()
      // abonne _onStructured à la place). Résultat : le takbir n'était
      // JAMAIS détecté en pratique pendant une vraie récitation continue,
      // alors que c'est exactement le cas d'usage visé (suivi de prière).
      // Rajouté ici, dans la branche RÉELLEMENT empruntée quand l'alignement
      // forcé GOP est actif (notre cas courant, modèle déployé).
      if (_confidentMode) {
        final newCommitted = parts.committed.length > _takbirScannedCommittedLen
            ? parts.committed.substring(_takbirScannedCommittedLen)
            : '';
        _takbirScannedCommittedLen = parts.committed.length;
        if (parts.preview.isEmpty) _takbirArmed = true;
        // Committed (déjà figé, jamais réévalué) OU preview (encore ré-évalué
        // à chaque passe, cf. commentaire de _takbirArmed -- couvre le cas où
        // l'ASR met plusieurs secondes à figer le takbir).
        final detected = _hasTakbir(newCommitted) ||
            (_takbirArmed && parts.preview.isNotEmpty && _hasTakbir(parts.preview));
        if (detected) {
          _takbirArmed = false;
          // Texte exact loggé (2026-07-19, constat réel : un takbir détecté
          // en PLEINE Al-Fatiha renvoie à tort en standby, cause jamais
          // confirmée faute de ce texte encore disponible au moment du log
          // -- logcat évincé avant qu'on tire le log) -- persisté ici pour
          // que ça ne se reproduise plus.
          DiagnosticLog.log('Takbir', '"الله أكبر" détecté (mode confiant) '
              '-- texte déclencheur committed="$newCommitted" '
              'preview="${parts.preview}" phase avant=${state.prayerPhase}');
          _enterPrayerStandby();
        } else if (state.prayerPhase == PrayerPhase.standby) {
          // En attente : la salât répète Al-Fatiha à CHAQUE rak'ah, mais
          // "الله أكبر" est aussi dit pour rukū'/sujūd (pas suivi de Coran) --
          // on ne bascule sur Al-Fatiha que si son début est RECONNU, jamais
          // sur le seul takbir (cf. commentaire de PrayerPhase).
          final sinceStandby = parts.committed.length > _standbyScanStart
              ? parts.committed.substring(_standbyScanStart)
              : '';
          final probe = sinceStandby.isNotEmpty ? sinceStandby : parts.preview;
          if (probe.isNotEmpty && _looksLikeFatihaStart(probe)) {
            unawaited(_beginFatihaPhase());
          }
        } else if (state.prayerPhase == PrayerPhase.detectingTarget &&
            !_targetLookupInFlight) {
          // Al-Fatiha terminée, sourate suivante pas encore identifiée --
          // même moteur que "Shazam coranique" (QuranVerseLocatorService),
          // appliqué au texte reconnu depuis la fin d'Al-Fatiha (demande
          // utilisateur 2026-07-18 : "il vaut mieux utiliser Shazam pour
          // détecter où commence la sourate après Fatiha" -- pas de sourate
          // pré-sélectionnée dans ce mode, elle peut changer à chaque rak'ah).
          final sinceDetect = parts.committed.length > _targetDetectScanStart
              ? parts.committed.substring(_targetDetectScanStart)
              : '';
          // ANCIENNE APPROCHE (gardée en référence, demande utilisateur
          // 2026-07-19 : "ne supprime rien, mets l'ancienne fonction en
          // commentaire") -- fenêtre glissante brute sur committed+preview,
          // incluait des mots d'aperçu encore instables (pas encore
          // stabilisés d'une passe à l'autre) dans la recherche :
          // final rawProbe = _lastWords(
          //     [sinceDetect, parts.preview].where((t) => t.isNotEmpty).join(' '),
          //     _kRecentWindowWords);
          //
          // NOUVELLE APPROCHE : ne garder que les mots "sûrs" (committed,
          // toujours sûr par construction, + le préfixe stable de l'aperçu,
          // cf. _stablePreviewPrefix) -- les mots "douteux" (aperçu encore
          // en train de changer) sont exclus de la recherche ce tour-ci.
          //
          // PAS de plafond `_kRecentWindowWords` ICI (demande utilisateur
          // 2026-07-19, "non il doit prendre en continu -- pour vérifier") :
          // contrairement au rattrapage pendant fatiha/target (§3.9, une
          // sourate en cours peut durer longtemps), cette phase
          // d'identification est courte (quelques secondes tout au plus,
          // avant match ou repli de continuité) -- laisser le texte "sûr"
          // s'accumuler en entier depuis la fin d'Al-Fatiha donne à Shazam
          // de plus en plus de contexte pour DÉPARTAGER un match coïncidentiel
          // court (ex. "ما جعل الله" seul matchait à tort "50:26") du vrai
          // verset, plus long dès qu'assez de mots sûrs sont accumulés.
          final stablePreview = _stablePreviewPrefix(parts.preview);
          final rawProbe =
              [sinceDetect, stablePreview].where((t) => t.isNotEmpty).join(' ');
          // BUG corrigé 2026-07-19 (constat utilisateur : "il y a plusieurs
          // répétitions du texte") : tant que rien de NOUVEAU n'est reconnu,
          // `rawProbe` reste identique d'une passe à l'autre (le natif rejoue
          // le même committed/preview entre deux re-transcriptions réelles) --
          // relancer Shazam dessus à chaque appel de `_onStructured` (toutes
          // les ~80-100ms) ne faisait que répéter la MÊME recherche pour rien.
          // On ne relance donc la recherche QUE si le texte a changé -- ce qui
          // sert aussi de signal pour réarmer le repli de continuité
          // (cf. _armDetectingTargetFallbackTimer) : un silence réel se
          // reconnaît justement à `rawProbe` qui reste inchangé.
          final probeChanged = rawProbe != _lastDetectingTargetProbe;
          if (probeChanged) {
            _lastDetectingTargetProbe = rawProbe;
            _armDetectingTargetFallbackTimer();
            // BUG corrigé 2026-07-18 (constat réel, log device) : "بِسْمِ
            // ٱللَّهِ ٱلرَّحْمَـٰنِ" -> Shazam répond "1:1" avec confiance
            // 1.00 -- FAUX, c'est juste la formule d'ouverture récitée
            // devant N'IMPORTE quelle sourate, pas le contenu réel de la
            // sourate suivante. Elle n'est indexée comme verset QUE dans
            // Al-Fatiha (1:1) -- les autres sourates ne l'ont pas dans leur
            // texte indexé (ajoutée séparément à l'affichage, cf.
            // QuranApi.fetchBismillah) -- donc Shazam matchait TOUJOURS 1:1
            // tant que seule la Bismillah avait été entendue. On la retire
            // du DÉBUT du texte avant recherche : la détection attend alors
            // le vrai contenu distinctif de la sourate.
            //
            // Résidu de fin d'Al-Fatiha (cf. _stripFatihaTailPrefix) retiré
            // AVANT la Bismillah : la fenêtre observée en pratique est
            // "...ولا الضالين" PUIS potentiellement une nouvelle Bismillah
            // avant le vrai contenu de la sourate suivante -- l'ordre des
            // deux strips doit suivre l'ordre réel du texte.
            final probe = _stripBismillahPrefix(_stripFatihaTailPrefix(rawProbe));
            if (probe != null && probe.isNotEmpty) {
              unawaited(_tryIdentifyTargetTwoStep(probe));
            }
          }
        } else if (state.prayerPhase == PrayerPhase.fatiha) {
          // Fin d'Al-Fatiha détectée par le TEXTE reconnu, PAS par l'avancée
          // du pointeur GOP (cf. _looksLikeFatihaEnd -- constat réel : le
          // pointeur peut rester bloqué sur les tout premiers mots pendant
          // 30s+ alors qu'Al-Fatiha est déjà entièrement récitée, la passe
          // d'alignement forcé prenant un retard croissant sur le flux réel).
          final sinceFatihaStart = parts.committed.length > _fatihaScanStart
              ? parts.committed.substring(_fatihaScanStart)
              : '';
          final probe = [sinceFatihaStart, parts.preview]
              .where((t) => t.isNotEmpty)
              .join(' ');
          if (probe.isNotEmpty && _looksLikeFatihaEnd(probe)) {
            DiagnosticLog.log('Prière', 'fin d\'Al-Fatiha reconnue par le texte '
                '(pointeur GOP peut être en retard) -- bascule immédiate');
            if (_dynamicTargetDiscovery) {
              _beginTargetDetection();
            } else {
              unawaited(_beginTargetPhase());
            }
          } else {
            // Al-Fatiha pas encore terminée : rattrape quand même le pointeur
            // mot-à-mot si le GOP a pris du retard sur ce qui est réellement
            // récité (cf. _maybeResyncPosition) -- micro-écoute récente
            // (_kRecentWindowWords), pas tout le texte cumulé depuis le début
            // de la phase.
            final recentProbe = _lastWords(probe, _kRecentWindowWords);
            // Repli complémentaire à _looksLikeFatihaEnd (retour utilisateur
            // 2026-07-19, "il faut pas lâcher le récitateur, toujours cherche
            // le mot dans toute la sourate") : le déclencheur textuel exact
            // (UN seul mot, "الضالين"/"المغضوب") peut échouer si l'ASR
            // tronque JUSTEMENT ce fragment précis -- déjà arrivé deux fois
            // cette session malgré le second mot de secours. Ici, si la
            // recherche Shazam retrouve avec confiance un passage qui n'est
            // PLUS dans Al-Fatiha du tout, c'est en soi la preuve qu'elle est
            // terminée, peu importe quel mot précis a été (mal) transcrit en
            // dernier.
            unawaited(_checkLeftFatihaViaShazam(recentProbe));
            _maybeResyncPosition(
                probe: recentProbe, surahNumber: 1, verses: _fatihaVerses);
          }
        } else if (state.prayerPhase == PrayerPhase.target &&
            _dynamicTargetDiscovery) {
          // Même rattrapage pendant la sourate suivie (identifiée par
          // Shazam) -- SEULEMENT en mode "Suivre une prière" : le karaoké
          // classique connaît sa cible depuis l'ouverture de l'écran (sa
          // propre extension de page gère déjà la suite, cf.
          // _maybeExtendNextPage côté écran). Scruté depuis l'entrée en
          // phase [target] (`_targetTrackingScanStart`) -- `committed` est un
          // buffer GLOBAL à la session, jamais purgé entre phases : sans ce
          // curseur, Al-Fatiha/le standby précédents pollueraient la requête.
          final sinceTarget = parts.committed.length > _targetTrackingScanStart
              ? parts.committed.substring(_targetTrackingScanStart)
              : '';
          final probe = [sinceTarget, parts.preview]
              .where((t) => t.isNotEmpty)
              .join(' ');
          _maybeResyncPosition(
              probe: _lastWords(probe, _kRecentWindowWords),
              surahNumber: _currentTargetSurah ?? -1,
              verses: _currentTargetVerses);
        }
      }
      return;
    }

    final words = [...state.words];
    final newErrors = <int>[];

    // 1. Nouveau texte figé ? Aligné UNE fois, définitivement, depuis l'ancre.
    if (parts.committed != _prevCommitted) {
      if (parts.committed.startsWith(_prevCommitted)) {
        final newPart = parts.committed.substring(_prevCommitted.length);
        _anchorExp = _alignChunk(
            words, _splitNorm(newPart), _splitStrict(newPart), _anchorExp,
            isFinal: true, newErrors: newErrors);
      } else {
        // Le buffer figé natif a redémarré (nouveau segment VAD) au lieu de
        // prolonger le précédent -- constat réel 2026-07-10 (sourate 98) :
        // le verset 1 entier revenait comme "nouveau" texte alors que
        // l'ancre attendait déjà le verset 2/3 ; chaque mot réellement dit
        // était comparé au mauvais mot attendu -> avalanche de 10 mots faux
        // d'un coup dans le même appel. Impossible de savoir de façon fiable
        // où ce texte redémarré se situe dans l'attendu (pas de recherche en
        // avant, cf. _alignChunk) -- dans tous les cas observés, il s'agit
        // d'une reconfirmation de contenu déjà entendu, jamais de contenu
        // qui ne reviendrait plus. On l'ignore plutôt que de le comparer à
        // l'aveugle contre l'ancre courante ; du contenu vraiment nouveau
        // reviendra dans un commit suivant, avec au pire un cycle de retard.
        debugPrint('[Align] Redémarrage du texte figé détecté (ne prolonge '
            'plus le précédent, ${parts.committed.length} car.) -- segment '
            'ignoré pour éviter une comparaison au mauvais endroit');
      }
      _prevCommitted = parts.committed;
    }

    // 2. Aperçu : ré-aligné à chaque passe depuis l'ancre. isFinal=false : le
    //    dernier mot reconnu peut être incomplet, pas verrouillé tant qu'une
    //    passe ultérieure ne confirme pas qu'on est passé au-delà.
    var reach = _anchorExp;
    if (parts.preview.isNotEmpty) {
      reach = _alignChunk(
          words, _splitNorm(parts.preview), _splitStrict(parts.preview), _anchorExp,
          isFinal: false, newErrors: newErrors);
    }

    // 3. Pointeur = premier mot encore pending/current (les mots jugés ou
    //    sautés sont verrouillés/avancés, donc il ne recule jamais).
    var pointer = 0;
    while (pointer < words.length &&
        words[pointer].status != WordStatus.pending &&
        words[pointer].status != WordStatus.current) {
      pointer++;
    }
    if (pointer < reach) pointer = reach;

    // Invariant : au plus UN mot "current" à la fois. Une passe d'aperçu
    // révisée peut recalculer un `reach` plus petit que celui d'une passe
    // précédente (transcription réévaluée) et laisser un ancien marqueur
    // "current" orphelin plus loin dans la liste, jamais nettoyé. Bug réel
    // constaté en test (2026-07-06) : deux mots "current" simultanément ->
    // crash Flutter (GlobalKey dupliquée côté UI, qui suppose un seul mot
    // courant). On nettoie tout marqueur "current" qui n'est pas au nouveau
    // pointeur avant d'en poser un nouveau.
    for (var i = 0; i < words.length; i++) {
      if (i != pointer && words[i].status == WordStatus.current) {
        words[i] = words[i].copyWith(status: WordStatus.pending);
      }
    }
    if (pointer < words.length &&
        words[pointer].status == WordStatus.pending) {
      words[pointer] = words[pointer].copyWith(status: WordStatus.current);
    }

    var correct = 0, unclear = 0, errors = 0;
    for (final w in words) {
      switch (w.status) {
        case WordStatus.correct:
          correct++;
        case WordStatus.unclear:
          unclear++;
        case WordStatus.error:
          errors++;
        default:
          break;
      }
    }

    final display = RuleSymbols.strip([parts.committed, parts.preview]
        .where((t) => t.isNotEmpty)
        .join(' '));
    final done = pointer >= words.length;
    state = state.copyWith(
      words: words,
      pointer: pointer,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      rawTranscript: display,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
    // Émis APRÈS que `state` reflète déjà le nouveau statut, pour que les
    // écouteurs (correction automatique) voient un état cohérent.
    for (final i in newErrors) {
      _wordFailedCtrl.add(i);
    }
  }

  /// Jugement PRIMAIRE (refonte 2026-07-11) : alignement forcé GOP calculé
  /// nativement sur les log-probabilités du modèle (cf. ForcedAligner.kt).
  /// Remplace le diff textuel flou (_alignChunk/_realignFromFullText, gardés
  /// en repli quand le modèle n'est pas déployé) : chaque mot couvert par
  /// l'audio reçoit gop = P(mot attendu|audio) − P(meilleur chemin|audio) —
  /// on mesure si l'AUDIO soutient le mot attendu (harakat comprises), au lieu
  /// de comparer deux textes après qu'un décodeur biaisé vers le texte
  /// canonique (cf. SKILL.md) a déjà lissé les erreurs. Les rustines
  /// d'alignement historiques (écho/doublon, fusion de jetons, tolérance
  /// arrière, redémarrage de segment) deviennent sans objet ici : la position
  /// de chaque mot est déterminée acoustiquement par la DP, plus par une
  /// correspondance de chaînes.
  void _onAligned(AlignPayload p) {
    // Tourne TOUJOURS (calcule + logue [GOP]), même si useGopScoring=false --
    // demande utilisateur 2026-07-20 : comparer les deux méthodes en
    // parallèle sur la même session, pas juste basculer l'une ou l'autre à
    // l'aveugle. Seul l'AFFICHAGE (state.words/pointer) est piloté par
    // _useGopScoring ; cf. les 3 `state = state.copyWith` plus bas, gardés
    // par `if (_useGopScoring)`.
    // En standby (attend Al-Fatiha) OU detectingTarget (Al-Fatiha finie,
    // sourate suivante pas encore identifiée) : aucune cible valable à juger
    // (cf. PrayerPhase) -- le natif continue de calculer des passes (cible
    // encore celle d'avant le takbir/d'Al-Fatiha), on les ignore simplement
    // plutôt que de juger à l'aveugle contre un texte qui n'est plus récité.
    // AVANT le check `words.isEmpty` : en mode "Suivre une prière"
    // (_dynamicTargetDiscovery), `state.words` est précisément vide pendant
    // ces deux phases -- sans ce test en premier, `pointer(0) >= words.length
    // (0)` serait trivialement vrai plus bas et terminerait la session à tort.
    if (state.prayerPhase == PrayerPhase.standby ||
        state.prayerPhase == PrayerPhase.detectingTarget) {
      return;
    }
    // Passe d'alignement d'une session PRÉCÉDENTE -> ignorer (bug constaté sur
    // device 2026-07-25, log 10:51:45, cf. JOURNAL_TESTS_LOGS.md) : arrêter une
    // récitation, revenir en arrière puis en relancer une autre faisait juger
    // les 4 premiers mots de la NOUVELLE sourate avec le texte entendu de
    // l'ANCIENNE ("أَحَدٌ" jugé avec entendu="ٱلْمَغْضُوبِ"...). Preuve que c'est
    // bien la même passe native rejouée et non du nouvel audio : gop/forced/
    // free/rescore étaient identiques au caractère près à ceux de la session
    // d'avant, seul normGop différait (recalculé sur le nouveau mot attendu).
    //
    // POURQUOI la fenêtre existe : `startContinuous` s'abonne à
    // `alignedWords` (_alignSub) AVANT d'attendre `_verifier.start()`, qui
    // seul remplace la cible native (setAlignmentTarget) et purge le buffer
    // (resetBuffered). Toute passe native encore en vol pendant cet await est
    // donc livrée au nouveau _onAligned, qui l'indexe sur les NOUVEAUX
    // state.words. `_myGeneration` n'est affecté qu'APRÈS ce même await, d'où
    // le rejet aussi quand il vaut encore -1 : aucun audio légitime ne peut
    // avoir été transcrit avant que start() ait créé le flux micro, donc on ne
    // perd jamais une passe valable ici.
    if (_myGeneration < 0 || _verifier.sessionGeneration != _myGeneration) {
      return;
    }
    if (state.words.isEmpty) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    final words = [...state.words];
    final newErrors = <int>[];
    // Plus haut index effectivement jugé cette passe (même non verrouillé,
    // cf. commentaire de `coveredExtent` plus bas) -- constat réel 2026-07-19
    // (log device) : plusieurs mots d'affilée reçoivent un statut correct en
    // aperçu (mots 25 à 36 jugés en quelques passes) alors que `p.frontier`
    // natif, lui, avance beaucoup plus prudemment -- le pointeur (et donc le
    // marqueur "mot courant"/défilement automatique) restait visuellement en
    // retard sur des mots déjà colorés, donnant l'impression que l'app "ne
    // suit pas" alors que le jugement progressait bien.
    var maxJudgedIndex = -1;

    // Règles détectées par index de mot sur CE segment -- construit AVANT la
    // boucle de jugement pour que la tolérance de jonction (cf.
    // unrealizedRulesFor / _junctionRules) puisse lire les voisins de
    // frontière sans dépendre de `state` (pas encore écrit à ce stade).
    final detectedByIndex = <int, Set<TajwidRule>>{
      for (final r in p.words) r.index: _rulesOf(r),
    };
    // La Bismillah est volontairement exclue de la vérification (décision
    // produit documentée plus bas), mais le garde-fou `actual vide = erreur`
    // passait avant cette exemption. Cas réel causal du 2026-07-26 : les
    // quatre mots de la Bismillah avaient `actual=""`, puis LA MÊME passe
    // reconnaissait correctement "ٱلْحَمْدُ لِلَّهِ". Le système colorait les
    // quatre premiers mots en rouge, déclenchait une correction et reculait
    // l'ancre 6 -> 0 : le curseur semblait ne jamais avancer.
    //
    // Une parole décodée ailleurs dans la même passe est une preuve acoustique
    // suffisante pour appliquer l'exemption aux mots Bismillah. Une passe
    // entièrement vide reste protégée : aucun silence n'est validé.
    // CORRECTIF RETENU (2026-07-26, revue du correctif ci-dessus) : le premier
    // jet validait ces mots en VERT dès que la passe contenait de la parole
    // ailleurs (`payloadContainsSpeech`). Rejeté : ça remet exactement le
    // comportement banni le 2026-07-25 (`mot=3 "ٱلرَّحِيمِ" entendu="" ->
    // correct`, cf. le garde-fou `!hasSpeech` plus bas et son « Ne pas le
    // redescendre »). Une parole décodée sur un AUTRE mot n'est pas une preuve
    // sur CELUI-CI.
    // La réponse honnête est de ne pas juger du tout : ni vert (rien
    // d'entendu), ni rouge (Bismillah exclue de toute vérification, décision
    // produit). Le mot reste sans couleur et l'ancre avance quand même, ce qui
    // supprime la correction parasite et le recul d'ancre 6 -> 0 sans rien
    // valider à tort. Cf. le `continue` dans la boucle de jugement.

    // ── VALIDATION GROUPÉE PAR GOP — RETIRÉE le 2026-07-26 ─────────────────
    // ⚠️ Tout le bloc ci-dessous documente une voie rapide qui N'EXISTE PLUS
    // dans le code (décision utilisateur après mesure). Conservé parce qu'il
    // porte le POURQUOI de sa création et les mesures qui l'ont motivée — sans
    // ça, un futur agent ne pourrait plus distinguer « jamais essayé » de
    // « essayé puis retiré ».
    //
    // CE QUI L'A FAIT RETIRER (mesure sur la session du 21:03-21:09, modèle
    // causal) : les deux bénéfices annoncés plus bas ont disparu.
    //   • « valide 5 ou 6 mots d'un coup » -> mesuré : 1 mot 34 fois, 2 mots
    //     21 fois, 3 mots 6 fois, 4 mots 1 fois. Jamais 5 ni 6. Plus de la
    //     moitié des déclenchements ne validaient qu'UN mot, ce que la voie
    //     mot-par-mot fait de toute façon.
    //   • « sauve les mots au texte artefacté » -> mesuré : sur 25 mots
    //     `autreMot=OUI` de la session, **0 validé** par la voie rapide, 25
    //     dégradés. Le bénéfice pour lequel elle existait ne s'est produit
    //     aucune fois.
    // Ne restait donc que son coût : valider sans contrôle textuel, ce qui
    // laisse passer le piège س/ص (« RENONCEMENT ASSUMÉ » plus bas). Hypothèse
    // pour l'écart avec la mesure du 25/07 : elle avait été calibrée sur le
    // modèle dual-head, pas sur le causal déployé depuis.
    // Si on la réintroduit un jour, la condition à vérifier D'ABORD est
    // qu'elle sauve réellement des mots `autreMot=OUI` — c'est sa seule raison
    // d'être, et c'est exactement ce qui a cessé d'être vrai.
    //
    // ── Documentation d'origine (2026-07-25) ──────────────────────────────
    // Avant de carver mot par mot, on prend la plus longue suite EN TÊTE dont
    // le GOP est franchement bon, et on la valide d'un bloc — sans passer par
    // les contrôles textuels.
    //
    // POURQUOI (mesuré sur la session du 17:42, 42 segments figés) : le texte
    // `entendu` de chaque mot est découpé dans les frames que la DP lui a
    // attribuées, et ce découpage produit des artefacts — `الذينلذين`,
    // `عليلهم`, `ءاممننا`, `أُو۟لَأُو۟لَـٰٓئِكَ` (syllabes doublées),
    // `لَ` pour `ٱلَّذِينَ` (tronqué). Ces artefacts déclenchent
    // `spellsDifferentWord` et dégradent le verdict alors que **le GOP dit que
    // la prononciation est bonne**. Cas relevés, tous avec un normGop AU-DESSUS
    // du seuil du vert :
    //     mot 12 `ٱلَّذِينَ`      orange  normGop=+0,77
    //     mot 17 `وَمِمَّا`        orange  normGop=+0,83  (deux fois)
    //     mot 37 `وَأُو۟لَـٰٓئِكَ` orange  normGop=+0,06  (deux fois)
    // 15 segments sur 42 (35 %) ont TOUS leurs mots au-dessus du seuil : la
    // voie rapide y valide 5 ou 6 mots d'un coup, ce qui est aussi tout
    // l'intérêt côté fluidité. Les 27 autres ont un GOP réellement faible
    // (−2,46, −3,39, −19,93) et basculent en mot-par-mot à juste titre.
    //
    // TROIS CONDITIONS, aucune négociable :
    //  1. `covered` — jamais le mot en cours de prononciation à la frontière
    //     d'un aperçu (bug historique 2026-07-05).
    //  2. `actual` NON VIDE — un mot sans aucune frame a un `forced ≈ free ≈ 0`
    //     sur du blank pur, donc un gop trompeusement bon. Le mot 65 `مَن`
    //     (`entendu=""`, normGop=−0,00) serait passé vert par cette
    //     coïncidence : ce serait valider un mot sans AUCUNE preuve
    //     acoustique, exactement ce que l'utilisateur refuse. Il reste donc
    //     rouge, via la voie mot-par-mot.
    //  3. suite CONTIGUË depuis le début de la passe — on s'arrête au premier
    //     mot qui échoue, on ne saute personne.
    //
    // RENONCEMENT ASSUMÉ (arbitré avec l'utilisateur) : le contrôle textuel
    // court-circuité est aussi celui qui attrape le piège س/ص (bon gop, mais le
    // modèle a écrit une autre lettre). Les 5 mots ci-dessus portent tous
    // `autreMot=OUI`, donc on ne peut pas conserver ce contrôle en n'excluant
    // que les fragments (`لَ` est un préfixe de `ٱلَّذِينَ` mais trop court
    // pour être reconnu comme tel). Le garde-fou propre pour س/ص est le
    // rescoring NLL déjà calculé et journalisé (`rescore=`), pas encore branché
    // au verdict faute de seuil calibré sur device. C'est le chantier suivant.
    for (final r in p.words) {
      if (r.index < 0 || r.index >= words.length) continue;
      if (words[r.index].locked) continue;
      // Mot à la frontière d'un aperçu : encore en cours de prononciation,
      // l'audio ne le couvre pas entièrement — ne pas juger (le verrouillage
      // prématuré d'un mot à moitié décodé est LE bug historique 2026-07-05).
      if (!r.covered && !p.isFinal) continue;
      if (r.index > maxJudgedIndex) maxJudgedIndex = r.index;

      final expected = words[r.index];
      final actualStrict = ArabicNormalizer.normalizeStrict(r.actual);
      final actualNorm = ArabicNormalizer.normalize(r.actual);
      final textMatches =
          ArabicNormalizer.matchesTolerant(actualStrict, expected.strict);

      // IMPORTANT : la confirmation textuelle (`textMatches`) ne peut que
      // RATTRAPER un score limite vers "correct" — jamais sauver un gop
      // franchement rejeté (< _kGopUnclear). Bug corrigé 2026-07-11 : la
      // version précédente acceptait `textMatches` seule, sans plancher —
      // un mot avec gop=-5.1 (rejet massif du chemin forcé) ressortait quand
      // même "correct" dès que le décodage libre épelait le mot attendu.
      // Comme le décodage libre est PRÉCISÉMENT ce que le GOP est censé
      // contourner (biais du modèle vers le texte canonique, cf. SKILL.md),
      // ce bypass sans plancher annulait tout l'intérêt de la refonte.
      // Bug corrigé 2026-07-16 : sur des frames quasi-silencieuses (utilisateur
      // qui ne parle pas / pause), `r.actual` (entendu) est vide -- le chemin
      // forcé ET le chemin libre prédisent alors tous deux du blank quasi-pur,
      // donc leur différence (gop) tombe près de 0 par pur hasard, sans
      // qu'aucun contenu réel n'ait été confirmé. Observé sur device : gop=0.00,
      // entendu="" -> jugé "correct" alors que l'utilisateur n'avait rien dit
      // ("le mot se met au vert tout seul après un silence"). `hasSpeech`
      // bloque ce cas : jamais "correct" sans au moins un caractère décodé.
      final hasSpeech = r.actual.trim().isNotEmpty;

      // Le décodage libre épelle-t-il franchement un AUTRE mot ? (2026-07-16)
      //
      // Jusqu'ici la comparaison textuelle ne servait que dans UN sens : rendre
      // le verdict plus INDULGENT (`textMatches` rattrape un gop limite). Rien
      // n'empêchait l'inverse -- être vert alors que le modèle a écrit un autre
      // mot. Cas réel mesuré sur device (log 16h59, modèle mixed-e02) :
      //     attendu "صِرَٰطَ" (sad) / entendu "سَرَٰطَ" (sin)
      //     gop=-0.35 forced=-1.77 free=-1.42  -> jugé CORRECT (vert)
      // Le modèle avait PARFAITEMENT entendu le sin de l'utilisateur, mais le
      // gop est une mesure RELATIVE (forced - free) : le modèle hésitant sur
      // tout à cet endroit (free=-1.42), le chemin forcé n'était "pas beaucoup
      // pire" que son meilleur choix -> écart faible -> vert. Aucun réglage de
      // seuil ne corrige ça proprement (en strict, -0.35 passerait orange par
      // chance, pas par raisonnement), alors que l'information est là, écrite
      // noir sur blanc dans `entendu`.
      //
      // Distinction essentielle -- SUBSTITUTION vs TRONCATURE : le texte
      // reconnu diffère aussi pour un pur artefact de découpage, quand la
      // coupure de segment ampute le mot (même log : attendu "ٱلْحَمْدُ",
      // entendu "مْدُ", gop=-0.04). Traiter les deux pareil ferait passer
      // orange des mots parfaitement récités. Un fragment (préfixe ou suffixe
      // de l'attendu) reste donc jugé sur le gop seul, comme avant ; seule une
      // vraie substitution (lettre/harakat changée) bloque le vert.
      // Bug corrigé 2026-07-16 (revue de code, Finding #6) : cette borne
      // (>=2 caractères ET >=1/3 de la longueur du mot attendu) était absente
      // -- `endsWith`/`startsWith` sur UN SEUL caractère coïncidant avec la
      // première/dernière lettre de `expected.strict` suffisait à passer
      // isFragment=true, rouvrant exactement le bug sin/sad de ce même jour
      // (une transcription fausse d'un seul caractère aurait forcé
      // spellsDifferentWord=false et renvoyé au jugement gop seul). Calculé
      // sur les cas réels observés : troncature légitime ("ٱلْحَمْدُ"->"مْدُ")
      // = ratio 0.44, coïncidence 1 caractère = ratio 0.14 -- un seuil à 1/3
      // sépare proprement les deux sans perdre le cas de troncature.
      final isLongEnoughToBeFragment =
          actualStrict.length >= 2 && actualStrict.length * 3 >= expected.strict.length;
      // Suppression au milieu (2026-07-16 soir, cas réel device : attendu
      // "بَلَوْنَـٰهُمْ", entendu "بَلَهُمْ" -- le CTC glouton a avalé "وْنَ" au
      // milieu, hors des frontières de mot). Contrairement au sin/sad
      // ci-dessus (VRAIE substitution : une lettre remplacée par une autre),
      // ici les lettres restantes ("ب ل ه م") apparaissent dans le MÊME ORDRE
      // que dans l'attendu ("ب ل و ن ه م", و et ن juste sautés) -- une
      // sous-séquence, pas un remplacement. `endsWith`/`startsWith` ne couvre
      // que les troncatures en bord de mot ; ceci étend la tolérance aux
      // suppressions internes SANS rouvrir le cas sin/sad (سرط n'est PAS une
      // sous-séquence de صرط : la toute première lettre diverge déjà, aucune
      // lettre commune à sauter par-dessus).
      final isOrderedSubsequence = actualStrict.isNotEmpty &&
          _isSubsequenceInOrder(actualStrict, expected.strict);
      final isFragment = hasSpeech &&
          actualStrict.isNotEmpty &&
          expected.strict.isNotEmpty &&
          isLongEnoughToBeFragment &&
          (expected.strict.endsWith(actualStrict) ||
              expected.strict.startsWith(actualStrict) ||
              isOrderedSubsequence);
      final spellsDifferentWord = hasSpeech && !textMatches && !isFragment;

      // Recentré sur la ligne de base du mot (cf. _normalizedGop) : sur un
      // mot structurellement dur (moyenne connue négative), r.gop brut serait
      // jugé faux même parfaitement récité -- normGop mesure l'ÉCART à ce qui
      // est normal pour CE mot, comparé aux mêmes seuils que d'habitude.
      final normGop = _normalizedGop(expected.training, r.gop);

      // Bismillah dont AUCUN son n'a été capté : non jugée du tout (cf. le
      // bloc « CORRECTIF RETENU » avant la boucle). Sortir AVANT la cascade
      // laisse le mot sans couleur, sans verrou et hors du compte d'erreurs ;
      // l'ancre, elle, avance normalement plus bas (`p.anchor +
      // p.words.length` sur un segment figé), donc plus de blocage ni de
      // correction déclenchée sur du silence.
      if (expected.isBasmala && !hasSpeech) {
        DiagnosticLog.log(
            'GOP',
            'mot=${r.index} "${expected.display}" Bismillah sans preuve '
                'acoustique -> NON JUGEE (ni verte ni rouge)');
        continue;
      }

      // ── TROU D'ALIGNEMENT : LE MODÈLE EST SÛR, L'ALIGNEUR A ÉCHOUÉ ───────
      // (2026-07-26, demande utilisateur : « si modèle confiant, pas de
      // jugement ».)
      //
      // `free` = score du décodage LIBRE sur ces frames (ce que le modèle
      // entend sans contrainte) ; `forced` = score du chemin CONTRAINT sur le
      // mot attendu. Quand `entendu` est vide, la DP n'a attribué AUCUNE frame
      // au mot -- deux situations opposées se cachent derrière :
      //
      //   • le mot n'a pas été prononcé      -> vraie faute, doit rester rouge
      //   • la DP a placé son audio ailleurs -> TROU, le mot est bien là
      //
      // Le discriminant mesuré (session 21:21-21:23, 5 mots signalés) :
      //     mot 49 `لَا`          forced=-20,00  free= 0,00  <- présent dans le libre
      //     mot 50 `يُؤْمِنُونَ`   forced=-16,93  free=-0,00  <- présent dans le libre
      //     mot 14 `بِٱلْغَيْبِ`   forced=-13,09  free=-0,00  <- présent dans le libre
      //     mot 15 `وَيُقِيمُونَ`  forced= -2,54  free=-0,11  <- ABSENT du libre
      // Un `free` collé à zéro signifie que le modèle est PARFAITEMENT sûr de
      // ce qu'il entend sur ces frames : elles portent donc du signal exploité,
      // simplement attribué à un autre mot par la DP. Conclure « pas prononcé »
      // dans ce cas est faux -- et c'est exactement ce qui produisait les faux
      // rouges, les corrections injustifiées et les reculs d'ancre en cascade
      // (3 faux rouges sur 5 mots signalés, 3 corrections déclenchées à tort).
      //
      // Le mot 15, lui, garde `free=-0,11` : le modèle hésite un peu, le mot
      // est vraiment absent de sa transcription libre. En position STRICTE il
      // reste donc jugé ; en position TOLÉRANTE le seuil descend à -0,15 et il
      // cesse d'être rouge. C'est précisément le curseur que l'utilisateur
      // règle (cf. `_freeConfident`), pas une constante figée.
      //
      // Ce n'est PAS de la tolérance ajoutée (cf. règle « pas de correctif
      // palliatif ») : on ne valide rien, on refuse de CONDAMNER sans preuve.
      // Même forme que le garde-fou Bismillah juste au-dessus, et symétrique
      // du principe déjà en vigueur « aucune preuve -> aucun verdict positif ».
      // `starved` (2026-07-27) : DEUXIÈME preuve indépendante du même
      // diagnostic, complémentaire à `free`. Mesure qui l'impose (session
      // 11:56, mot 63 "وَمِنَ") : `entendu=""`, `free=-0,24` -- juste SOUS le
      // seuil de confiance tolérant (-0,15), donc le garde-fou `free` seul ne
      // tirait pas. Le mot n'était alors JAMAIS verrouillé (aucun rouge
      // affiché) mais la SÉRIE d'aperçus négatifs stables déclenchait quand
      // même une correction (cf. `_previewNegativeStreak` plus bas) --
      // invisible à l'écran, 9 corrections sur 15 dans cette session sont
      // passées par cette voie. Le décodage libre du même segment contenait
      // pourtant le mot en entier ("وَمِنَ ٱلنَّاسِ مَن يَقُولُ...").
      // `starved` (calculé côté Kotlin : frames attribuées < minimum requis
      // par le CTC pour ce nombre de tokens) attrape ce cas que `free` seul
      // manquait : la DP a physiquement trop peu de place pour ce mot, quelle
      // que soit sa confiance sur ces quelques frames.
      final free = r.forced - r.gop;
      if (!hasSpeech && (free >= _freeConfident || r.starved)) {
        DiagnosticLog.log(
            'GOP',
            'mot=${r.index} "${expected.display}" trou d\'alignement '
                '(free=${free.toStringAsFixed(2)} forced=${r.forced.toStringAsFixed(2)} '
                'starved=${r.starved}) '
                '-> NON JUGE : le modele est sur de ce qu\'il entend, '
                'la DP n\'a pas su placer ce mot');
        continue;
      }

      WordStatus judged;
      if (!hasSpeech) {
        // ── AUCUNE PREUVE ACOUSTIQUE -> AUCUN VERDICT POSITIF ──────────────
        // Testé AVANT le laisser-passer Al-Fatiha/Basmala (déplacé ici le
        // 2026-07-25). Preuve mesurée, log du 16:32, MÊME absence totale de
        // son donnant des verdicts OPPOSÉS :
        //   mot=3  "ٱلرَّحِيمِ" forced=-18.99 entendu="" -> correct (lock=true)
        //   mot=26 "أُنزِلَ"    forced=-20.00 entendu="" -> error   (lock=true)
        // Le premier passait vert par le laisser-passer basmala, évalué avant
        // ce garde-fou : un mot dont AUCUN son n'a été capté était validé.
        // C'est précisément ce que l'utilisateur refuse -- pire que « la moitié
        // d'un mot jugée valide », ici il n'y a rien du tout.
        //
        // Le laisser-passer existe pour un problème de CALIBRATION (la basmala
        // est récitée ~44 % plus vite dans le dataset, le modèle la score mal).
        // Sans aucun son, il n'y a rien à calibrer : la seule réponse honnête
        // est « pas prononcé ».
        judged = WordStatus.error;
      } else if (state.prayerPhase == PrayerPhase.fatiha || expected.isBasmala) {
        // Demande utilisateur 2026-07-19 : "je ne veux pas de correction
        // dans la récitation de Al-Hamdo [Al-Fatiha], elle est très connue
        // et rare, les erreurs dans cette sourate c'est juste du bruit" --
        // Al-Fatiha est récitée des dizaines de fois par jour, une vraie
        // erreur de prononciation y est rarissime ; un rouge/orange dessus
        // reflète presque toujours du bruit ASR (écho/réverbération de
        // mosquée, segmentation), pas une vraie faute. On ne juge donc
        // jamais négativement pendant cette phase -- seule la POSITION
        // (avancement de l'ancre/du pointeur, cf. plus bas, nécessaire pour
        // la bascule de phase) continue d'être suivie normalement.
        //
        // `expected.isBasmala` (2026-07-20, demande utilisateur) : étend ce
        // même laisser-passer aux 4 mots de "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ
        // ٱلرَّحِيمِ" QUELLE QUE SOIT la sourate (pas seulement en cycle de
        // prière Al-Fatiha) -- mesuré sur le dataset d'entraînement : la
        // Bismillah y est récitée ~44% plus vite en médiane que le reste du
        // Coran (certains réciteurs 3-4x plus vite), et le modèle est
        // structurellement mal calibré dessus quelle que soit la méthode
        // d'entraînement (3 pistes testées le même soir, même échec). Ce
        // n'est pas une faute du récitant, ne pas la lui reprocher.
        judged = WordStatus.correct;
        // (Bug corrigé 2026-07-16, revue de code, Finding #9 : `hasSpeech` ne
        // protégeait QUE la branche `correct` ci-dessous -- un mot jamais
        // prononcé (r.actual=="") avec un gop proche de 0 par coïncidence
        // (forced≈free≈0 sur du blank pur) tombait dans la branche `unclear`
        // juste en dessous, qui ne vérifiait que `r.gop >= _gopUnclear`. Un mot
        // sans aucun son capté n'a de sens NI en "correct" NI en "unclear" --
        // toujours `error`. Ce test vivait ICI ; il a été REMONTÉ au-dessus du
        // laisser-passer Al-Fatiha/Basmala le 2026-07-25, qui le contournait.
        // Ne pas le redescendre.)
      } else if (!spellsDifferentWord &&
          // TEST 2026-07-23 : plancher `normGop >= _gopUnclear` RETIRE sur la
          // rescousse textMatches. Un mot dont le modele a ecrit EXACTEMENT la
          // forme attendue (entendu strict == attendu strict, cf. textMatches)
          // est juge correct QUEL QUE SOIT le forced/gop -- on fait confiance
          // au MODELE (decodage libre) plutot qu'au forced token-level, qui se
          // fait piéger par un desaccord de decoupage BPE sur un mot pourtant
          // parfaitement prononce (ex. لَآ forced=-12.97 free=-0.08 entendu="لَآ",
          // إِيَّاكَ pareil -- premiers mots qui bloquaient toute la recitation).
          // Le cas piege س/ص reste exclu : la, entendu != attendu (squelette
          // different) donc textMatches=false. Si ce test est concluant sans
          // faux positifs, le rendre definitif ; sinon le remplacer par le fix
          // de fond (GOP invariant au decoupage / alignement squelette).
          (normGop >= _gopCorrect || textMatches)) {
        judged = WordStatus.correct;
      } else if (normGop >= _gopUnclear ||
          ArabicNormalizer.similarity(actualNorm, expected.normalized) >=
              _kUnclearSimThreshold) {
        // Bon mot mais rendu imprécis : hésitation acoustique modérée, ou
        // squelette quasi identique avec harakat divergentes.
        judged = WordStatus.unclear;
      } else {
        judged = WordStatus.error;
      }

      // ── TENTATIVE ANNULÉE (2026-07-25) : requalifier `correct` tout mot dont
      // le verdict serait `error` mais dont le texte entendu est un fragment
      // de l'attendu (`isFragment`), pour compenser les troncatures de capture
      // du buffer (9 faux rouges contre 4 vraies fautes mesurés ce jour-là,
      // cf. JOURNAL_TESTS_LOGS.md).
      //
      // REFUSÉE par l'utilisateur, à juste titre : un récitateur qui ne dit
      // que la MOITIÉ d'un mot était alors validé -- précisément ce que l'app
      // existe pour détecter. Le correctif neutralisait le symptôme dans la
      // couche de jugement alors que la cause naît dans la couche de capture
      // (le buffer coupe en plein mot). Ne pas le réintroduire : la bonne
      // correction est en amont (recouvrement d'audio au gel / coupe qui ne
      // tombe pas au milieu d'un mot, cf. ARCHITECTURE_RECITATION.md §3.1 et
      // piste C), à valider sur les bancs hors device.
      //
      // Le diagnostic reste disponible sans changer aucun verdict : les mots
      // tronqués sont déjà identifiables dans le log par le flag `fragment`
      // (`grep 'fragment' | grep error` en donne le compte).

      // Relâche selon le preset (tajwid/adulte/enfant) -- uniquement quand il y
      // a eu de la parole (pas en phase Fatiha, déjà forcée à correct). Ne
      // durcit jamais : un mot faux au-delà du pardon du preset reste rouge.
      //
      // `!expected.isBasmala` (bug corrigé 2026-07-20, constaté sur device) :
      // sans cette exclusion, le laisser-passer Basmala ci-dessus (`judged =
      // WordStatus.correct`) était ensuite DÉGRADÉ par `_capByRuleReliability`
      // dès qu'une règle portée par ces mots (ex. ham_wasl sur "ٱللَّهِ") est
      // active en mode tajwid -- le mot repassait en orange malgré le
      // laisser-passer, exactement le comportement qu'on voulait supprimer.
      if (hasSpeech &&
          state.prayerPhase != PrayerPhase.fatiha &&
          !expected.isBasmala) {
        judged = _relaxJudged(judged, expected, actualNorm);
        judged = _capByRuleReliability(judged, r.index);
      }
      // ── Vérification du TAJWID, séparée de la prononciation ──────────────
      // Le verdict ci-dessus porte sur les LETTRES et les HARAKAT (رَبِّ vs
      // رَبُّ : le texte change). Ici on regarde une autre nature d'erreur :
      // le texte est juste, mais une règle de récitation n'a pas été réalisée
      // (qalqala, ghunnah, idgham). L'utilisateur exige que les deux soient
      // distinguées -- elles ne s'apprennent ni ne se corrigent pareil.
      //
      // Ne s'applique qu'aux règles ACTIVES : vide en adulte/enfant.
      // N'aggrave JAMAIS au-delà de l'orange, et ne touche pas un mot déjà
      // rouge (la prononciation prime : inutile de reprocher une ghunnah sur
      // un mot qui n'est pas le bon).
      // `!expected.isBasmala` : même raison que le garde-fou ci-dessus -- la
      // Bismillah n'est pas fiablement annotée en tajwid dans le corpus
      // d'entraînement (récitée vite, formule rituelle), on ne peut pas non
      // plus se fier à ce qu'elle "devrait" réaliser ici.
      final detected = _rulesOf(r);
      // Voisins de frontière du segment courant (union gauche+droite), pour la
      // tolérance des règles de jonction -- lu depuis `detectedByIndex` (ce
      // segment) et non `state` (pas encore à jour dans cette boucle).
      final neighborDetected = <TajwidRule>{
        ...?detectedByIndex[r.index - 1],
        ...?detectedByIndex[r.index + 1],
      };
      // TAJWID jugé uniquement quand le mot est ENTIÈREMENT COUVERT par
      // l'audio (`r.covered`) -- correctif 2026-07-23 en DEUX temps :
      //
      // 1er constat (session Al-Balad, réciteur confirmé) : la tête tajwid
      // tournait sur des buffers partiels (1s/3s/4s glissants) qui coupent le
      // mot en bord de segment. Or ConvTajwidHead a un noyau temporel de 5
      // frames : sans le contexte voisin, elle ne déclenche pas. Mesuré :
      // `emises=` VIDE sur des idgham/qalqala pourtant bien réalisés, et le
      // MÊME mot donnait `emises=` puis `emises=madda_normal` selon le
      // découpage du buffer (mot=33 يَرَهُۥٓ) -- c'était le segment, pas la
      // récitation.
      //
      // 1re tentative de correctif : conditionner à `p.isFinal`. ERREUR --
      // mesurée sur la session suivante : seuls 3 jugements sur 16 tombent
      // sur un segment figé. Un mot jugé `correct` en aperçu est VERROUILLÉ
      // immédiatement (cf. `lock` plus bas) et n'est jamais rejugé sur la
      // passe finale : son tajwid n'était donc contrôlé NULLE PART. Ce
      // garde-fou désactivait en pratique 80 % de la vérification tajwid,
      // c'est-à-dire la raison d'être du coach.
      //
      // Bon critère : `r.covered` (le mot est derrière la frontière = son
      // audio est complet ET il a du contexte des deux côtés), indépendamment
      // de la finalité du segment. C'est exactement la condition dont la tête
      // a besoin, et elle est vraie sur la grande majorité des aperçus.
      //
      // 3e temps (2026-07-24, mesuré sur clip réel 90:3 + simulation de
      // coupure) : `r.covered` protège le mot LUI-MÊME, mais pas les règles
      // de JONCTION (idgham/iqlab/ikhafa...), dont l'acoustique se résout
      // dans le mot VOISIN. Preuve chiffrée : idgham_ghunnah gagne l'argmax
      // sans ambiguïté sur audio complet (rang 0, score quasi 0 contre blank
      // à -14), mais retombe au rang 1 (perd de justesse) dès que le buffer
      // est coupé AVANT que le mot voisin soit capté -- ce n'est pas un
      // manque de contexte du noyau (5 frames ≈ 400ms, largement suffisant,
      // confirmé : dès que 50% du clip est présent, ça regagne), c'est
      // l'ABSENCE du mot voisin, pas encore prononcé/capté. `neighborDetected`
      // ci-dessus lit `detectedByIndex`, qui ne contient QUE les mots déjà
      // présents dans CETTE passe -- un voisin absent du segment est donc
      // traité comme "rien détecté", identique à un vrai échec de détection.
      // Effet mesuré sur device : mot bien récité marqué orange à tort, qui
      // déclenche en cascade `_onWordFailed` -> pauseCapture() (cf.
      // karaoke_recitation_screen.dart) -- une coupure du micro que
      // l'utilisateur n'a pas demandée, prise pour une pause de sa part.
      //
      // Correctif : pour une règle de JONCTION, ne conclure "non détectée"
      // que si le mot voisin pertinent est réellement COUVERT dans cette
      // passe (son audio est capté et jugé, pas juste absent du segment).
      // Sinon on DIFFÈRE -- ce mot sera réévalué à la prochaine passe, une
      // fois le voisin disponible, au lieu d'un verdict prématuré.
      final neighborCovered = p.words.any((w) =>
          (w.index == r.index - 1 || w.index == r.index + 1) && w.covered);
      final unrealizedRaw = (expected.isBasmala || !r.covered)
          ? const <TajwidRule>[]
          : unrealizedRulesFor(r.index, detected,
              neighborEmitted: neighborDetected);
      final unrealized = neighborCovered
          ? unrealizedRaw
          : unrealizedRaw.where((rr) => !_junctionRules.contains(rr)).toList();
      // ⚠️ Le simple filtrage ci-dessus NE SUFFIT PAS : `_judge` verrouille
      // le mot dès que `judged != error` (cf. `lock` plus bas), sur CETTE
      // passe -- si on se contente de sauter la règle de jonction, le mot se
      // verrouille "correct" AVANT que le voisin n'arrive, et n'est plus
      // JAMAIS réévalué (`if (words[i].locked) return;`, cf. `_judge`). Le
      // report devient alors un simple SAUT de la vérification, pas un vrai
      // report -- pire que l'ancien comportement sur ce mot précis (plus
      // aucune chance de contrôle tajwid). Il faut donc AUSSI empêcher le
      // verrouillage tant que le report est réel, cf. `deferredTajwid` sur
      // le calcul de `lock` plus bas. Sur un segment FINAL, en revanche, il
      // n'y aura plus jamais de passe suivante pour ce mot -- verrouiller
      // quand même (comme avant), sinon le mot resterait indéfiniment
      // "pending" alors que son audio ne sera plus jamais réanalysé.
      final deferredTajwid =
          !p.isFinal && unrealized.length < unrealizedRaw.length;
      if (unrealized.isNotEmpty && judged == WordStatus.correct) {
        judged = WordStatus.unclear;
        // Libellé « NON DETECTEE » et non « non réalisée » (correctif
        // 2026-07-23, demande utilisateur) : ce que la ligne constate est
        // `attendues` MOINS `emises`, c'est-à-dire « l'asset attendait cette
        // règle ici et la tête tajwid ne l'a pas détectée ». Ça n'est PAS une
        // preuve que le récitant ne l'a pas faite -- le modèle peut
        // simplement l'avoir ratée. Preuve mesurée sur device : le MÊME mot
        // (mot=33 يَرَهُۥٓ, même audio) sortait `emises=` vide sur une passe
        // puis `emises=madda_normal` sur la suivante, selon le découpage du
        // buffer. L'ancien libellé accusait le récitant d'une faute que le
        // système ne peut pas établir ; cf. la même mise en garde déjà
        // présente dans classifyError.
        DiagnosticLog.log(
            'TAJWID',
            'mot=${r.index} "${expected.display}" regle(s) NON DETECTEE(S) : '
                '${unrealized.map((x) => x.key).join(",")}'
                ' | attendues=${expected.expectedRules.map((x) => x.key).join(",")}'
                ' emises=${detected.map((x) => x.key).join(",")}');
      }
      // Une erreur ne se verrouille QUE sur un segment figé (décision
      // utilisateur 2026-07-10, conservée) : un aperçu peut encore mal couvrir
      // la fin d'un mot ; le segment figé ultérieur tranche définitivement.
      // `!deferredTajwid` (2026-07-24) : ne pas verrouiller un mot dont la
      // vérification tajwid a été reportée (voisin pas encore couvert) --
      // sinon `_judge` (`if (words[i].locked) return;`) fige "correct" pour
      // toujours, et la règle de jonction reportée n'est plus jamais
      // contrôlée. Cf. commentaire complet sur `deferredTajwid` plus haut.
      //
      // `judged == correct` et non `judged != error` (2026-07-25, validé par
      // l'utilisateur) : un `unclear` ne se verrouille PLUS sur un aperçu.
      // « Orange » signifie littéralement « je ne suis pas sûr » -- figer une
      // incertitude sur une preuve incomplète est exactement ce qu'il ne faut
      // pas faire, car la transcription complète qui arrive ensuite ne peut
      // plus la corriger. Mesuré sur la session du 14:25 : les 5 orange de la
      // session étaient TOUS des artefacts d'aperçu tronqué --
      //   mot=43 "سَوَآءٌ"        entendu="سَ"
      //   mot=48 "تُنذِرْهُمْ"      entendu="ٱلْ"
      //   mot=45 "ءَأَنذَرْتَهُمْ"  entendu="يَسْتَ"
      //   mot=16 "ٱلصَّلَوٰةَ"      entendu="ٱلصَّدْةَ"  (aperçu d'1 s)
      //   mot=15 "وَيُقِيمُونَ"     entendu="وَٱللَّهُ يَعْلَمُونَ"
      // -- verrouillés orange à 14:25:37, alors que le segment figé suivant,
      // à 14:25:42, transcrivait PARFAITEMENT « وَيُقِيمُونَ ٱلصَّلَوٰةَ وَمِمَّا
      // رَزَقْنَـٰهُمْ يُنفِقُونَ ». Le réciteur avait bien dit les mots ; seul le
      // verrouillage prématuré empêchait la correction.
      // Ce n'est PAS de la tolérance ajoutée (cf. règle "pas de correctif
      // palliatif") : au gel du segment, le verdict est appliqué tel quel --
      // le mot peut parfaitement finir orange ou rouge.
      final lock =
          p.isFinal || (judged == WordStatus.correct && !deferredTajwid);
      // `free` (= forced - gop) et `autreMot` sont logués car le gop seul ne
      // permet PAS de diagnostiquer : un gop proche de 0 signifie soit "bien
      // récité", soit "modèle hésitant sur tout" (free très négatif), deux
      // situations opposées. Cf. le cas sin/sad ci-dessus.
      // rescore : signal DIAGNOSTIQUE uniquement (cf. AlignedWord.rescoreMargin)
      // -- pas encore branché au verdict `judged` ci-dessus, seuil non calibré
      // sur device. Loggé pour comparer a posteriori aux vrais cas gop=0/vert
      // à tort une fois le rescoring activé (setRescoringEnabled).
      final rescoreInfo = r.rescoreMargin != null
          ? ' rescore=${r.rescoreMargin!.toStringAsFixed(2)}'
              '${r.rescoreHeard != null ? "(${r.rescoreHeard})" : ""}'
          : '';
      DiagnosticLog.log('GOP', 'mot=${r.index} "${expected.display}" '
          'gop=${r.gop.toStringAsFixed(2)} '
          '${normGop != r.gop ? "normGop=${normGop.toStringAsFixed(2)} " : ""}'
          'forced=${r.forced.toStringAsFixed(2)} '
          'free=${(r.forced - r.gop).toStringAsFixed(2)}'
          '$rescoreInfo '
          'entendu="${r.actual}" src=${r.actualFromFree ? "libre" : "dp"}'
          '${spellsDifferentWord ? " autreMot=OUI" : ""}'
          '${isFragment ? " fragment" : ""}'
          ' -> $judged (lock=$lock, final=${p.isFinal})'
          ' | $_modeTag');
      // `heard` = transcription BRUTE (symboles de règles conservés) et non
      // `actualStrict` : la forme stricte filtre la zone privée Unicode, ce qui
      // effacerait justement les symboles dont la vérification tajwid a besoin.
      // Les normalisations sont réappliquées à la lecture (classifyError).
      // APPRENTISSAGE DE LA DUREE (2026-07-27) : un mot juge correct ET
      // verrouille donne une mesure fiable de sa duree d'articulation dans la
      // voix de l'utilisateur -> elle remplacera la duree quran.com au prochain
      // setup (cf. WordDurationStore, et _wordsFromSegments pour la priorite).
      // Conditions volontairement strictes :
      //  - `correct` seulement : la duree d'un mot mal recite, ou tronque par
      //    une coupe de segment, n'a aucune raison de servir de plancher
      //    (garde-fou souleve par l'utilisateur : « on a egalement la
      //    validation ») ;
      //  - `lock` seulement : un apercu non verrouille peut encore etre rejuge,
      //    sa duree n'est pas definitive ;
      //  - hors Bismillah : ces 4 mots ne sont pas juges (cf.
      //    RecitedWord.isBasmala), et sont recites ~44 % plus vite que le reste
      //    du Coran -- leur duree n'est pas representative.
      if (judged == WordStatus.correct && lock && r.frames > 0 &&
          !expected.isBasmala) {
        WordDurationStore.instance.record(expected.alignTarget, r.frames);
      }
      _judge(words, r.index, judged,
          lock: lock, newErrors: newErrors, heard: r.actual,
          detectedRules: detected, alignSeq: p.seq);
    }

    // ── SÉLECTION DE CLIPS SUPPRIMÉE (2026-07-25) ────────────────────────
    // Ici se trouvait un filtre qui ne retenait un segment QUE si TOUS ses
    // mots étaient corrects (`allCorrect`), au service du mini-LoRA de
    // personnalisation vocale : il fallait des exemples propres pour
    // entraîner. Cet objectif est abandonné (entraînement sur le téléphone
    // plus envisageable) et la règle est INVERSÉE : les WAV servent
    // maintenant au DIAGNOSTIC de la chaîne ASR, où ce sont précisément les
    // segments contenant des mots signalés qui portent l'information.
    //
    // Mesuré le 2026-07-25 avant ce changement : une session de référence a
    // écrit 8 WAV sans aucune erreur d'écriture, puis les a TOUS supprimés
    // faute d'un seul segment intégralement correct. La preuve était créée
    // puis détruite. Ne pas réintroduire de filtre de rétention ici : Kotlin
    // écrit désormais chaque segment figé dans un dossier DURABLE que rien
    // ne nettoie (cf. VoiceLoraClipService.newRecitationCaptureDir).
    // `p.clipPath` reste disponible dans le payload pour un usage futur.

    // L'ancre (utilisée par la correction, cf. rewindRangeEnd) doit avancer
    // EXACTEMENT jusqu'où ce bloc a verrouillé des mots — pas jusqu'à
    // `frontier` seul. Sur un segment figé, TOUS les mots de p.words sont
    // jugés/verrouillés ci-dessus (y compris celui à la frontière, non
    // couvert mais quand même jugé puisque isFinal bypasse le garde-fou
    // `!r.covered`) — donc la vraie étendue verrouillée est
    // `p.anchor + p.words.length`, pas `p.frontier` (peut être strictement
    // inférieur d'un mot). Bug corrigé 2026-07-11 : sous-évaluer l'ancre ici
    // désynchronisait Dart de l'ancre native (cf. BufferedTranscriber.kt,
    // runAlignment) — l'appel suivant redemandait à la DP de forcer
    // l'alignement sur un mot déjà verrouillé, absent du nouvel audio,
    // corrompant l'attribution de frames du mot RÉELLEMENT suivant (constat :
    // "مَـٰلِكِ" verrouillé error à tort, gop=-7.36, alors que le décodage
    // libre du même segment le montrait parfaitement reconnu).
    if (p.isFinal) {
      final trueExtent = p.anchor + p.words.length;
      if (trueExtent > _anchorExp) {
        _anchorExp = trueExtent;
        // Garde à jour la référence temporelle du garde-fou de plausibilité
        // (cf. _kMaxPlausibleWordsPerSecond) : un jugement GOP normal est
        // aussi un avancement confirmé de l'ancre, pas seulement un
        // rattrapage Shazam.
        _lastAnchorAdvanceAt = DateTime.now();
      }
      // Bismillah exclue de TOUTE vérification, alignement compris (2026-07-24,
      // constat device : blocage systématique sur قُلْ après la Bismillah).
      // Quand un segment FINAL n'aligne AUCUN mot (p.words vide) alors que
      // l'ancre pointe sur un mot Bismillah, ce mot (ٱلرَّحِيمِ / ٱلرَّحْمَـٰنِ :
      // chadda sans signature acoustique propre) obtient 0 frame dans la DP
      // native forcée, qui s'arrête dessus (`break`, ForcedAligner.kt) et
      // empêche le mot SUIVANT (قُلْ, pourtant parfaitement décodé en libre)
      // d'être crédité -> ancre figée, cascade de blocages. L'exemption
      // Bismillah n'existait que côté verdict/couleur (ce fichier, cf.
      // `expected.isBasmala`), JAMAIS côté alignement natif (qui ignore
      // totalement la notion, vérifié : aucune trace de "basmala" en Kotlin).
      // On fait respecter la règle ici, dans la couche qui connaît isBasmala :
      // sauter l'ancre au premier mot NON-Bismillah. Sûr car Bismillah n'est de
      // toute façon jamais jugée.
      if (p.words.isEmpty &&
          p.anchor >= 0 &&
          p.anchor < words.length &&
          words[p.anchor].isBasmala) {
        var skip = p.anchor;
        while (skip < words.length && words[skip].isBasmala) {
          skip++;
        }
        if (skip > p.anchor && skip > _anchorExp) {
          _anchorExp = skip;
          _lastAnchorAdvanceAt = DateTime.now();
          unawaited(_verifier.setAlignmentAnchor(skip));
          DiagnosticLog.log(
              'ASR',
              'Bismillah exclue de l\'alignement : ancre débloquée '
              '${p.anchor} -> $skip (mot Bismillah non aligné, ne doit '
              'jamais bloquer la progression)');
        }
      }
    }

    // Pointeur = frontière acoustique (premier mot que l'audio ne couvre pas
    // entièrement) — mais sur un segment figé, tous les mots jusqu'à
    // `_anchorExp` viennent d'être verrouillés (cf. ci-dessus), donc le
    // pointeur doit au moins les dépasser aussi, pas juste `p.frontier`
    // (identique à la correction de l'ancre). Jamais en arrière : une passe
    // ponctuellement dégradée ne fait pas reculer l'UI.
    final coveredExtent =
        p.isFinal ? _anchorExp : max(p.frontier, maxJudgedIndex + 1);
    final pointer =
        max(state.pointer, coveredExtent.clamp(0, words.length).toInt());

    // Invariant : au plus UN mot "current" à la fois (cf. crash GlobalKey
    // dupliquée, 2026-07-06).
    for (var i = 0; i < words.length; i++) {
      if (i != pointer && words[i].status == WordStatus.current) {
        words[i] = words[i].copyWith(status: WordStatus.pending);
      }
    }
    if (pointer < words.length && words[pointer].status == WordStatus.pending) {
      words[pointer] = words[pointer].copyWith(status: WordStatus.current);
    }

    var correct = 0, unclear = 0, errors = 0;
    for (final w in words) {
      switch (w.status) {
        case WordStatus.correct:
          correct++;
        case WordStatus.unclear:
          unclear++;
        case WordStatus.error:
          errors++;
        default:
          break;
      }
    }

    final done = pointer >= words.length;
    // Cycle de prière (mode confiant) : la fin d'Al-Fatiha ou de la sourate
    // suivie N'ARRÊTE PAS la session -- elle enchaîne sur le temps suivant de
    // la salât (cf. PrayerPhase). Seul le mode normal (aucun cycle en cours)
    // termine réellement la session sur `done`.
    // Comparaison en parallèle (cf. commentaire début _onAligned) : quand le
    // texte-diff pilote l'affichage, le gop continue de tourner et de se
    // journaliser (boucle ci-dessus) mais ne doit PLUS toucher `state` ni
    // déclencher ses effets de bord (transitions de phase, fin de session) --
    // ceux-ci restent la responsabilité exclusive du moteur actif.
    if (!_useGopScoring) {
      // Bug corrigé 2026-07-22 (audit demandé par l'utilisateur) :
      // `_realignFromFullText` (texte-diff) ne sait PAS calculer les règles
      // tajwid -- seul le bloc ci-dessus (GOP, tourne TOUJOURS, cf. début de
      // fonction) le fait. Sans cette fusion, `detectedRules` restait
      // calculé sur la liste locale `words` puis jeté (jamais persisté dans
      // `state`), et `_realignFromFullText` copiait `state.words[i]` tel
      // quel (`copyWith(status: ...)` sans passer `detectedRules`, qui
      // restait donc vide) : la tête tajwid tournait pour rien dès que
      // useGopScoring=false (défaut de JudgementOptions()). On ne touche
      // QUE `detectedRules` ici, jamais `status`/`pointer` (propriété
      // exclusive du texte-diff quand il pilote l'affichage, cf. commentaire
      // plus haut) -- pour les mots non traités cette passe, `words[i]` est
      // une simple copie de `state.words[i]` (ligne 2442), donc sans effet.
      final withRules = [
        for (var i = 0; i < words.length; i++)
          state.words[i].copyWith(detectedRules: words[i].detectedRules),
      ];
      state = state.copyWith(words: withRules);
      return;
    }
    if (done && state.prayerPhase == PrayerPhase.fatiha) {
      state = state.copyWith(
        words: words, pointer: pointer, correctCount: correct,
        unclearCount: unclear, errorCount: errors,
      );
      for (final i in newErrors) {
        _wordFailedCtrl.add(i);
      }
      // "Suivre une prière" (_dynamicTargetDiscovery) : pas de sourate
      // pré-chargée -- il faut d'abord l'identifier (Shazam). Karaoké
      // classique (mode confiant sur une sourate pré-sélectionnée) : reprend
      // directement cette sourate, déjà connue.
      if (_dynamicTargetDiscovery) {
        _beginTargetDetection();
      } else {
        unawaited(_beginTargetPhase());
      }
      return;
    }
    if (done && state.prayerPhase == PrayerPhase.target) {
      state = state.copyWith(
        words: words, pointer: pointer, correctCount: correct,
        unclearCount: unclear, errorCount: errors,
      );
      for (final i in newErrors) {
        _wordFailedCtrl.add(i);
      }
      _enterPrayerStandby();
      return;
    }
    state = state.copyWith(
      words: words,
      pointer: pointer,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
    // Émis APRÈS que `state` reflète le nouveau statut (cohérence écouteurs).
    for (final i in newErrors) {
      _wordFailedCtrl.add(i);
    }
  }

  /// Ré-aligne TOUT le scoring vert/rouge à partir du texte complet reconnu
  /// jusqu'ici, en repartant de zéro à chaque appel (au lieu d'accumuler mot
  /// par mot via [_onToken]). Nécessaire pour le mode streaming "bufferisé" :
  /// chaque re-transcription re-décode tout le buffer audio et peut légèrement
  /// réviser ce qui précède (voir SKILL.md "Streaming CTC : incompatibilité
  /// architecturale") — le texte n'est PAS garanti strictement append-only,
  /// donc une simple accumulation mot-par-mot afficherait des correspondances
  /// fausses dès qu'une révision survient. Recalculer à chaque fois est plus
  /// coûteux mais toujours cohérent avec la meilleure compréhension actuelle.
  /// [apply] : quand false, calcule et journalise ([TEXTDIFF]) le verdict de
  /// CETTE méthode sans toucher `state` -- permet de faire tourner gop et
  /// diff textuel en parallèle sur la même session pour les comparer
  /// (demande utilisateur 2026-07-20), sans que les deux se disputent
  /// l'affichage. Défaut true : comportement historique (repli quand le
  /// modèle natif est indisponible).
  void _realignFromFullText(String fullText, {bool apply = true}) {
    if (state.words.isEmpty) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    final recNorm = fullText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(ArabicNormalizer.normalize)
        .toList();
    final recStrict = fullText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(ArabicNormalizer.normalizeStrict)
        .toList();

    // `expected` : lecture seule des mots attendus. La copie mutable n'est
    // construite QUE si l'on applique réellement le résultat.
    //
    // Pourquoi (mesure 2026-07-25) : en mode gop (le cas normal), cette méthode
    // est appelée avec apply=false ~12,5 fois par seconde uniquement pour
    // journaliser sa comparaison. Elle recopiait à chaque fois l'INTÉGRALITÉ de
    // `state.words` — 6121 mots sur une sélection Al-Baqara complète, soit
    // ~76 000 allocations par seconde — alors que la boucle ci-dessous s'arrête
    // typiquement au 2e mot et qu'aucune écriture n'a lieu. C'est cette charge
    // (plus les écritures fichier du log, cf. plus bas) qui saturait l'isolate
    // Dart et faisait arriver les blocs PCM par rafales côté natif — la rafale
    // qui a déclenché la course de gel du BufferedTranscriber (deux feed() à
    // 4 ms d'écart, cf. commitInFlight).
    final expected = state.words;
    final words = apply
        ? expected.map((w) => w.copyWith(status: WordStatus.pending)).toList()
        : const <RecitedWord>[];

    var expIdx = 0;
    var recIdx = 0;
    var correct = 0;
    var unclear = 0;
    var errors = 0;

    while (expIdx < expected.length && recIdx < recNorm.length) {
      var bestRec = -1;
      var bestSim = 0.0;
      final windowEnd = (recIdx + _kAlignLookahead).clamp(0, recNorm.length - 1);
      for (var j = recIdx; j <= windowEnd; j++) {
        final sim = ArabicNormalizer.similarity(recNorm[j], expected[expIdx].normalized);
        if (sim > bestSim) {
          bestSim = sim;
          bestRec = j;
        }
      }

      if (bestSim >= _kSimThreshold && bestRec >= 0) {
        // Jugement à 3 niveaux :
        //  - vert   : correspondance stricte (harakat comprises, alef tolérant)
        //  - orange : c'est manifestement le bon mot (squelette quasi-identique)
        //             mais rendu imprécis — harakat différentes ou consonne
        //             floue. Feedback "effort de prononciation", pas une faute.
        //  - rouge  : aligné mais trop éloigné = mot réellement faux.
        final isExact =
            ArabicNormalizer.matchesTolerant(recStrict[bestRec], expected[expIdx].strict);
        final WordStatus judged;
        if (expected[expIdx].isBasmala) {
          // Cf. le même laisser-passer côté gop (_onAligned) : Bismillah
          // récitée ~44% plus vite en médiane dans le dataset d'entraînement,
          // modèle mal calibré dessus quelle que soit la méthode -- pas une
          // faute du récitant.
          judged = WordStatus.correct;
          correct++;
        } else if (isExact) {
          judged = WordStatus.correct;
          correct++;
        } else if (bestSim >= _kUnclearSimThreshold) {
          judged = WordStatus.unclear;
          unclear++;
        } else {
          judged = WordStatus.error;
          errors++;
        }
        if (apply) words[expIdx] = words[expIdx].copyWith(status: judged);
        // entenduStrict/isExact ajoutés le 2026-07-20 nuit (demande utilisateur) :
        // le squelette seul (entendu=recNorm, sans harakat) ne permettait pas de
        // vérifier si un CHANGEMENT DE HARAKAT délibéré était bien vu par la
        // comparaison stricte (matchesTolerant, sur recStrict) -- indispensable
        // pour distinguer "la comparaison a raté le changement" de "le modèle a
        // \"corrigé\" la harakat vers le canonique avant même la comparaison"
        // (même biais que la substitution س/ص constatée la même nuit).
        // Journalisé UNIQUEMENT quand le verdict de CE mot change (2026-07-25).
        // Mesuré avant : 299 lignes rigoureusement identiques pour le mot 0 et
        // 299 pour le mot 1 en 27 s de récitation (22 à 32 écritures fichier
        // synchrones par seconde), sur des mots verrouillés depuis la 3e
        // seconde. La répétition ne porte aucune information — ce qui intéresse
        // la comparaison diff/gop, ce sont les transitions — et son coût
        // saturait l'isolate (cf. le commentaire sur `expected` plus haut).
        final line = 'mot=$expIdx "${expected[expIdx].display}" '
            '(strict="${expected[expIdx].strict}") '
            'entendu="${recNorm[bestRec]}" entenduStrict="${recStrict[bestRec]}" '
            'sim=${bestSim.toStringAsFixed(2)} isExact=$isExact -> $judged'
            '${apply ? "" : " (comparaison, gop pilote l'affichage)"}';
        if (_lastTextDiffLine[expIdx] != line) {
          _lastTextDiffLine[expIdx] = line;
          DiagnosticLog.log('TEXTDIFF', line);
        }
        recIdx = bestRec + 1;
        expIdx++;
      } else {
        // Pas de correspondance suffisante dans la fenêtre de tolérance :
        // on s'arrête ici, ce mot devient le mot "courant" (pas encore confirmé).
        break;
      }
    }

    // Garde-fou : une re-transcription ponctuelle peut être ponctuellement
    // dégradée (cf. SKILL.md) et faire "reculer" l'alignement recalculé à
    // partir de zéro. On n'affiche jamais un recul — un nouveau calcul qui
    // couvre MOINS de mots que la meilleure position déjà atteinte est ignoré
    // (on garde l'affichage précédent, en attendant une meilleure lecture).
    if (!apply) return; // comparaison seule : rien à figer, déjà journalisé.
    if (expIdx < state.pointer) return;

    if (expIdx < expected.length) {
      words[expIdx] = words[expIdx].copyWith(status: WordStatus.current);
    }

    final done = expIdx >= words.length;
    state = state.copyWith(
      words: words,
      pointer: expIdx,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
  }

  void _onPendingChanged(int pending) {
    state = state.copyWith(pendingSegments: pending);
    // La session est en cours de finalisation (stopContinuous) et la file
    // vient de se vider : tout est transcrit, on peut vraiment terminer.
    if (_endingContinuous && pending == 0) {
      _cleanup();
    }
  }

  /// Traite un mot reconnu — accepte les tokens en état listening ET processing
  /// (le mode batch Whisper émet tous les tokens PENDANT stop()).
  void _onToken(RecognizedToken token) {
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;
    if (state.isComplete) return;

    final words = [...state.words];
    final p = state.pointer;
    final recognized = ArabicNormalizer.normalize(token.text);
    final recognizedStrict = ArabicNormalizer.normalizeStrict(token.text);

    // Alignement de position : tolérant (squelette sans harakat), pour savoir
    // à quel mot du verset le token reconnu correspond à peu près.
    int bestIdx = -1;
    double bestSim = 0;
    final end = (p + _kLookahead).clamp(0, words.length - 1);
    for (var i = p; i <= end; i++) {
      final sim = ArabicNormalizer.similarity(recognized, words[i].normalized);
      if (sim > bestSim) {
        bestSim = sim;
        bestIdx = i;
      }
    }

    var correct = state.correctCount;
    var errors = state.errorCount;
    int newPointer;

    if (token.confidence >= 0.5 && bestSim >= _kSimThreshold && bestIdx >= 0) {
      for (var i = p; i < bestIdx; i++) {
        words[i] = words[i].copyWith(status: WordStatus.skipped);
        errors++;
      }
      // Jugement de correction : strict, harakat inclus. Un mot aligné sur la
      // bonne position mais prononcé avec une voyelle courte différente
      // (ex: رَبِّ récité رَبُّ) compte comme une erreur, pas un match.
      final isExact = recognizedStrict == words[bestIdx].strict;
      words[bestIdx] =
          words[bestIdx].copyWith(status: isExact ? WordStatus.correct : WordStatus.error);
      if (isExact) {
        correct++;
      } else {
        errors++;
      }
      newPointer = bestIdx + 1;
    } else {
      words[p] = words[p].copyWith(status: WordStatus.error);
      errors++;
      newPointer = p + 1;
    }

    if (newPointer < words.length) {
      words[newPointer] = words[newPointer].copyWith(status: WordStatus.current);
    }

    final done = newPointer >= words.length;
    state = state.copyWith(
      words: words,
      pointer: newPointer,
      correctCount: correct,
      errorCount: errors,
      // En mode batch (stopping=true) on garde "processing" pour les tokens
      // intermédiaires ; "finished" uniquement quand tous les mots sont traités.
      status: done
          ? RecitationStatus.finished
          : (_stopping ? RecitationStatus.processing : RecitationStatus.listening),
    );
    if (done) _finish();
  }

  /// Appelé quand tous les mots ont été traités (streaming Mock ou batch Whisper).
  void _finish() {
    // En mode batch, _verifier.stop() est déjà en cours → ne pas rappeler
    if (!_stopping) {
      _verifier.stop(); // streaming : stopper le Mock
    }
    _cleanup();
  }

  void _cleanup() {
    _tokenSub?.cancel();
    _levelSub?.cancel();
    _rawSub?.cancel();
    _structSub?.cancel();
    _pendingSub?.cancel();
    _alignSub?.cancel();
    // Mode continu : ce chemin ne passe PAS par stop(), il lui faut son propre
    // flush (idempotent, no-op si rien n'a change).
    unawaited(WordDurationStore.instance.flush());
    _stopping = false;
    _endingContinuous = false;
    state = state.copyWith(status: RecitationStatus.finished, soundLevel: 0);
  }

  /// Stop manuel (bouton rouge). Change le statut immédiatement en "processing"
  /// → l'UI reste réactive pendant que l'inférence tourne dans compute().
  Future<void> stop() async {
    if (_stopping || !state.isActive) return;
    _stopping = true;

    // Arrêt de l'affichage du niveau micro
    _levelSub?.cancel();
    _levelSub = null;

    // ← L'UI voit "processing" tout de suite ; le bouton change de couleur
    state = state.copyWith(status: RecitationStatus.processing, soundLevel: 0);

    try {
      // WhisperOnnxVerifier.stop() : enregistrement + compute() ASR + emit tokens
      // Les tokens arrivent ici via _onToken pendant l'await
      await _verifier.stop();
    } finally {
      _tokenSub?.cancel();
      _rawSub?.cancel();
      _structSub?.cancel();
      _alignSub?.cancel();
      // Ecriture GROUPEE des durees apprises pendant la session : `record()`
      // est appele sur chaque mot valide (des dizaines par session), on ne veut
      // pas un acces disque par mot. Sans effet si rien n'a change.
      unawaited(WordDurationStore.instance.flush());
      _stopping = false;
      if (state.status != RecitationStatus.finished) {
        state = state.copyWith(status: RecitationStatus.finished);
      }
    }
  }

  /// Arrêt manuel d'une récitation continue (l'utilisateur peut s'arrêter
  /// avant la fin du fragment). Le statut reste "processing" tant que la file
  /// de segments n'est pas vidée — voir [_onPendingChanged].
  Future<void> stopContinuous() async {
    if (!state.isActive || !state.continuous) return;
    _endingContinuous = true;
    _levelSub?.cancel();
    _levelSub = null;
    state = state.copyWith(status: RecitationStatus.processing, soundLevel: 0);

    await _verifier.stop(); // enfile le dernier segment, retourne vite

    // Si la file était déjà vide au moment du stop (dernier segment invalide
    // ou pas de nouveau segment), _onPendingChanged ne sera pas redéclenché.
    if (state.pendingSegments == 0) _cleanup();
  }

  void reset() {
    _stopping = false;
    _endingContinuous = false;
    final cleared = state.words
        .map((w) => w.copyWith(status: WordStatus.pending))
        .toList();
    state = RecitationSessionState(words: cleared);
  }

  /// Boucle de correction interactive (demande utilisateur 2026-07-05) : marque
  /// le mot [index] comme corrigé après un ré-essai validé (l'appelant a déjà
  /// vérifié la prononciation via une transcription séparée, cf.
  /// `WordCorrectionSheet`). Verrouillé comme n'importe quel jugement définitif
  /// — mais celui-ci vient d'une vérification EXPLICITE demandée par
  /// l'utilisateur, pas d'une passe automatique, donc jamais suspect
  /// d'incomplétude : verrouillage immédiat justifié.
  void markWordCorrected(int index) {
    if (index < 0 || index >= state.words.length) return;
    final words = [...state.words];
    final wasError = words[index].status == WordStatus.error;
    final wasUnclear = words[index].status == WordStatus.unclear;
    words[index] = words[index].copyWith(status: WordStatus.correct, locked: true);
    // Mot validé par correction explicite : l'ancre d'alignement (native et
    // locale) doit repartir APRÈS lui, pour que la suite de la récitation soit
    // comparée au mot suivant.
    if (_anchorExp < index + 1) _anchorExp = index + 1;
    unawaited(_verifier.setAlignmentAnchor(index + 1));
    state = state.copyWith(
      words: words,
      correctCount: state.correctCount + 1,
      errorCount: wasError ? state.errorCount - 1 : state.errorCount,
      unclearCount: wasUnclear ? state.unclearCount - 1 : state.unclearCount,
    );
  }

  /// Recul + déverrouillage d'un mot fautif (demande utilisateur 2026-07-06,
  /// répétée et précisée à plusieurs reprises) : après avoir entendu la
  /// correction (mot précédent + mot fautif), le réciteur doit pouvoir
  /// REFAIRE ce mot précis avec un NOUVEL audio -- contrairement au
  /// verrouillage normal (qui protège contre le biais du modèle sur le MÊME
  /// audio réévalué avec plus de contexte, cf. commentaire de _judge), ici
  /// c'est une tentative différente, donc le mot doit pouvoir redevenir vert
  /// si elle est correcte. On déverrouille le mot ET on ramène l'ancre
  /// d'alignement dessus, pour que la prochaine transcription soit comparée
  /// à CE mot plutôt qu'au suivant.
  /// Fin (exclusive) de la plage qui sera déverrouillée par
  /// [rewindAndUnlock] si on l'appelle MAINTENANT sur [wordIndex] — à lire
  /// AVANT d'appeler rewindAndUnlock (qui modifie l'ancre), pour savoir
  /// jusqu'où étendre l'audio de correction (demande utilisateur 2026-07-06 :
  /// pour un saut de plusieurs mots, le réciteur doit dire TOUS les vrais
  /// mots sautés, pas juste le premier).
  int rewindRangeEnd() => _anchorExp;

  /// Recul + déverrouillage d'une plage fautive (demande utilisateur
  /// 2026-07-06, précisée à plusieurs reprises) : après avoir entendu la
  /// correction, le réciteur doit pouvoir REFAIRE cette plage avec un NOUVEL
  /// audio -- contrairement au verrouillage normal (qui protège contre le
  /// biais du modèle sur le MÊME audio réévalué avec plus de contexte, cf.
  /// commentaire de _judge), ici c'est une tentative différente, donc les
  /// mots doivent pouvoir redevenir verts si elle est correcte. Déverrouille
  /// TOUT depuis [wordIndex] jusqu'à l'ancre actuelle (pas seulement
  /// [wordIndex] seul) : un saut de plusieurs mots verrouille plusieurs mots
  /// d'un coup (les sautés + celui qui a causé le saut) et un seul événement
  /// de correction est émis pour toute la plage — reculer sur un seul mot
  /// laisserait les autres verrouillés "sauté" pour toujours.
  void rewindAndUnlock(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= state.words.length) return;
    // Le réciteur va REDIRE cette plage : la mémoire des aperçus négatifs doit
    // repartir de zéro dessus, sinon un verdict resté en mémoire pourrait
    // re-déclencher une correction avant même qu'il ait reparlé, ou au
    // contraire empêcher un nouvel échec d'être signalé (`_failureSignalled`).
    _previewNegative.removeWhere((k, _) => k >= wordIndex);
    _previewNegativeStreak.removeWhere((k, _) => k >= wordIndex);
    _previewNegativeSeq.removeWhere((k, _) => k >= wordIndex);
    _failureSignalled.removeWhere((k) => k >= wordIndex);
    final words = [...state.words];
    final end = _anchorExp.clamp(wordIndex + 1, words.length);
    var correctDelta = 0, errorDelta = 0, unclearDelta = 0;
    for (var i = wordIndex; i < end; i++) {
      if (words[i].status == WordStatus.correct) correctDelta++;
      if (words[i].status == WordStatus.error ||
          words[i].status == WordStatus.skipped) {
        errorDelta++;
      }
      if (words[i].status == WordStatus.unclear) unclearDelta++;
      words[i] = words[i].copyWith(status: WordStatus.pending, locked: false);
    }
    // Le pointeur UI et l'ancre native représentent la même position de
    // reprise. Avant ce correctif, seule l'ancre reculait : l'écran continuait
    // d'indiquer l'ancien mot courant, donc le réciteur suivait le mot N
    // pendant que l'aligneur attendait encore le mot wordIndex. Le journal du
    // 2026-07-26 l'a rendu visible : recul 9 -> 3, puis 22 ids CTC reconnus
    // sans aucun nouveau verdict. On rétablit aussi l'invariant d'un unique
    // mot `current`, déjà appliqué dans _onAligned.
    for (var i = 0; i < words.length; i++) {
      if (i != wordIndex && words[i].status == WordStatus.current) {
        words[i] = words[i].copyWith(status: WordStatus.pending);
      }
    }
    words[wordIndex] =
        words[wordIndex].copyWith(status: WordStatus.current, locked: false);
    // Trace décisive pour l'audit du 2026-07-20 (cascade de faux oranges) :
    // après une correction, l'ancre RECULE sur le mot raté — le système attend
    // que le réciteur le RÉPÈTE. S'il enchaîne au lieu de répéter, l'alignement
    // forcé cherche ce mot dans un audio qui ne le contient pas : `forced`
    // s'effondre pendant que `free` reste bon, et le décalage se propage aux
    // mots suivants. Sans cette ligne, impossible de distinguer ce scénario
    // d'une vraie faute de prononciation dans le log.
    // Le mot nomme est celui de DESTINATION du recul, pas forcement le mot
    // FAUTIF : depuis le 2026-07-25 l'appelant recule d'un mot de plus, pour
    // que l'ancre coincide avec ce qu'on fait entendre au reciteur
    // (`_kCorrectionWordsBefore`). Le libelle le dit explicitement, sinon le
    // log est trompeur -- constate sur `recul 29 -> 22 (correction sur
    // "بِمَآ")` alors que le mot fautif etait le 23 (`أُنزِلَ`).
    DiagnosticLog.log('ANCRE',
        'recul $_anchorExp -> $wordIndex | reprise demandee sur '
        '"${words[wordIndex].display}" | remis en attente: ${end - wordIndex} mot(s)');
    _anchorExp = wordIndex;
    // Le buffer natif est vidé séparément (verifier.resetBuffer(), appelé par
    // l'écran avant resumeCapture()) -- on oublie ici le texte figé déjà vu,
    // pour que le prochain texte figé reçu (la nouvelle tentative) soit
    // traité comme entièrement nouveau, pas comme une suite du texte d'avant
    // le recul.
    _prevCommitted = '';
    // Ancre de l'alignement forcé GOP : la prochaine passe doit comparer le
    // nouvel audio à CE mot, pas à la suite du texte.
    unawaited(_verifier.setAlignmentAnchor(wordIndex));
    state = state.copyWith(
      words: words,
      pointer: wordIndex,
      correctCount: state.correctCount - correctDelta,
      errorCount: state.errorCount - errorDelta,
      unclearCount: state.unclearCount - unclearDelta,
    );
  }

  @override
  void dispose() {
    // Dernier recours : ecran quitte sans arret propre -- ne pas perdre les
    // durees apprises pendant la session.
    unawaited(WordDurationStore.instance.flush());
    _tokenSub?.cancel();
    _levelSub?.cancel();
    _rawSub?.cancel();
    _structSub?.cancel();
    _pendingSub?.cancel();
    _alignSub?.cancel();
    _detectingTargetFallbackTimer?.cancel();
    _wordFailedCtrl.close();

    // Bug corrigé 2026-07-16 — FUITE DE SESSION. Ce dispose n'annulait que les
    // abonnements Dart : le MICRO continuait d'enregistrer et le
    // BufferedTranscriber natif (un SINGLETON, côté Kotlin) continuait
    // d'empiler de l'audio après la sortie de l'écran. Ce provider est
    // autoDispose, mais `recitationVerifierProvider` NE L'EST PAS -- le
    // verifier (et son enregistreur) survit donc à l'écran qui l'a lancé.
    //
    // Constaté sur device (log 17h17-17h21, sourate Al-Baqara) : la session
    // précédente en était à `bloc PCM #1800` quand la nouvelle démarrait --
    // deux flux micro concurrents alimentant le MÊME buffer natif. D'où :
    //   - un `wordFailed` sur "الٓمٓ" 100 ms après l'ouverture, AVANT même le
    //     premier bloc PCM de la nouvelle session (impossible d'avoir récité) ;
    //   - des transcriptions de bruit ambiant ("تَسُجْززْ", "يَ") jugées comme
    //     de vrais mots -> mots marqués rouges, correction automatique
    //     déclenchée toute seule, audio du récitateur joué sans raison ;
    //   - remarque utilisateur : "quand je veux tester Baqara il ne part pas du
    //     début, il retient ce que j'ai fait il y a longtemps".
    //
    // `stop()` annule _pcmSub ET arrête l'enregistreur ; `resetBuffer()` purge
    // l'état natif (samples, texte figé, aperçu) pour que la session suivante
    // reparte réellement de zéro. Fire-and-forget : dispose() est synchrone et
    // ne doit jamais bloquer la fermeture de l'écran.
    //
    // Bug corrigé 2026-07-16 (revue de code, Finding #1) : ce nettoyage
    // appelait stop()+resetBuffer() SANS AUCUNE garde contre une nouvelle
    // session démarrée entre-temps (recitationVerifierProvider n'est PAS
    // autoDispose -- une réouverture rapide de l'écran karaoké réutilise le
    // MÊME verifier). Le stop() de cette ancienne session pouvait s'exécuter
    // APRÈS que la nouvelle ait déjà appelé _recorder.startStream(), tuant
    // silencieusement le nouvel enregistrement. `stopIfCurrentSession`
    // (verrou sérialisé + vérification de génération côté verifier) ne fait
    // plus rien si une session plus récente a déjà pris le relais.
    if (_myGeneration >= 0) {
      unawaited(_verifier.stopIfCurrentSession(_myGeneration).catchError(
          (e) => DiagnosticLog.log('ASR', 'arrêt de session au dispose échoué : $e')));
    }

    super.dispose();
  }
}
