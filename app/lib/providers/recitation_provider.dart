import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/judgement_options.dart';
import '../models/recitation_state.dart';
import '../models/verse.dart' show Verse;
import '../providers/judgement_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../services/quran_verse_locator_service.dart';
import '../services/recitation_verifier.dart';
import '../services/rule_annotation_service.dart';
import '../services/voice_lora_clip_service.dart';
import '../services/reference_timing_extractor.dart';
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
  return notifier;
});

class RecitationNotifier extends StateNotifier<RecitationSessionState> {
  final RecitationVerifier _verifier;
  StreamSubscription<RecognizedToken>? _tokenSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<({String committed, String preview})>? _structSub;
  // MODE PRIERE seulement (2026-08-07) : le decodage libre de la v2 et le
  // signal de passage saute. Nuls dans tous les autres modes.
  StreamSubscription<String>? _libreSub;
  StreamSubscription<({int de, int a})>? _sautSub;

  // ── CHAINE v2, BRANCHÉE EN PARALLÈLE (2026-07-30) ────────────────────────
  // La v2 tourne EN PLUS de la v1, sur le même audio, et rend des STATUTS
  // (pas des scores) : c'est elle qui a la couche de décision, pas Dart.
  // Mesure de référence sur le même flux brut (banc `BancFluxBrut`, récitation
  // professionnelle de 379,8 s) : v1 10,10 % de mots non verts, v2 2,03 %.
  //
  // Motif volontairement identique à `useGopScoring` : les deux moteurs
  // calculent, un seul peint l'écran. La v1 ne peut donc pas régresser du fait
  // du branchement, et une session compare les deux sur le MÊME audio.
  StreamSubscription<List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})>>? _v2Sub;
  StreamSubscription<int>? _decrochageSub;

  /// La v2 pilote-t-elle l'affichage ? Quand c'est faux, elle tourne quand même
  /// et ses verdicts sont journalisés — exactement comme le double moteur GOP /
  /// text-diff. Le passer à false suffit à revenir au comportement v1.
  static const bool _v2PiloteAffichage = true;

  /// Exposé pour que l'écran sache si l'ancre v1 a encore un sens (elle est
  /// figée quand la v2 pilote : la v1 ne décode plus).
  bool get v2PiloteAffichage => _v2PiloteAffichage;

  // Correction automatique (demande utilisateur 2026-07-05) : émis UNE fois
  // par mot, exactement au moment où il est verrouillé rouge pour la première
  // fois (les mots verrouillés ne sont plus jamais rejugés, donc pas de risque
  // de doublon). L'écran karaoké écoute ça pour déclencher pause + lecture
  // réciteur + reprise, sans aucune interaction manuelle.
  final _wordFailedCtrl = StreamController<int>.broadcast();
  Stream<int> get wordFailed => _wordFailedCtrl.stream;

  // ── TOUT MOT VERROUILLE NON VERT, POUR L'ARCHIVE DU COACH (2026-08-06) ───
  //
  // `wordFailed` ne convient PAS pour archiver : c'est le declencheur de la
  // correction automatique, filtre par ses propres conditions (reglage
  // desactive, anti-rafale, mode reference, mode confiant). Un mot rouge qui
  // ne declenche pas de correction reste un mot rouge -- il doit se retrouver
  // dans les resultats du Coach.
  //
  // Ce flux dit une seule chose : « ce mot vient d'etre VERROUILLE sur un
  // verdict non vert ». Aucune politique, aucun filtre. L'archivage (extrait
  // de la voix + verdict en base) est fait par l'ecran, seul endroit qui sache
  // relier un index global a sa position sourate/verset.
  //
  // ⚠️ L'extrait doit etre pris TOUT DE SUITE : la voix vit dans un anneau de
  // 300 s cote natif (`voixSurPlage`), et le fichier rendu par
  // `v2ExtraitVoix` porte toujours le meme nom -- c'est exactement ce que
  // l'utilisateur a constate le 2026-08-06 (« j'ai ecouté ma voix sur la
  // premiere erreur, puis il n'y a plus de voix »).
  final _nonVertCtrl = StreamController<int>.broadcast();
  Stream<int> get wordLockedNonGreen => _nonVertCtrl.stream;

  // Meme principe que ci-dessus, mais SANS filtre de couleur -- ajoute pour
  // le suivi permanent par portion (sourate/Hizb) du Coach : une portion doit
  // pouvoir mettre a jour un mot deja connu comme faux si une recitation
  // ulterieure le rejoue et le reussit, ce que `wordLockedNonGreen` seul ne
  // permet pas de voir (il ne signale jamais un mot devenu vert).
  final _wordLockedCtrl = StreamController<int>.broadcast();
  Stream<int> get wordLocked => _wordLockedCtrl.stream;

  // ── DÉCROCHAGE : le récitateur dit AUTRE CHOSE (2026-08-01) ───────────────
  // MÉCANISME ENTIÈREMENT NEUF, volontairement isolé (demande utilisateur :
  // « éviter de toucher les fonctions qui sont appelées par un autre mode...
  // ça c'est un fonctionnement nouveau »). Il n'écrit RIEN dans `state.words`,
  // n'appelle NI `_judge` NI `_realignFromFullText` : il se contente
  // d'observer et de signaler. Coach, suivi de prière et jeux ne peuvent donc
  // pas régresser à cause de lui.
  //
  // LE TROU QU'IL COMBLE. L'alignement forcé doit placer chaque mot ATTENDU
  // quelque part sur l'audio : il sait dire « ce mot attendu n'y est pas »
  // (`omis`), jamais « ce que j'entends n'est pas dans le texte ». Et le
  // diff textuel (`_realignFromFullText`) s'ARRÊTE (`break`) au premier mot
  // non apparié. Résultat mesuré sur la session de l'utilisateur : on peut
  // réciter n'importe quoi puis reprendre le texte, tout repasse au vert --
  // exactement ce que ce mode existe pour détecter.
  //
  // RÈGLE (formulée par l'utilisateur) : « tout ce que le modèle reçoit, il
  // va le juger, du coup on va rien perdre ; une fois qu'on détecte deux mots
  // qui ne collent pas avec le mot qui suit, c'est que le récitateur déraille
  // de la récitation. »
  final _decrochageCtrl = StreamController<int>.broadcast();
  /// Émis (avec la position de l'ancre) quand [_kMotsHorsTexteAvantDecrochage]
  /// mots CONSÉCUTIFS décodés ne correspondent à aucun mot attendu autour de
  /// l'ancre. L'écran de récitation s'y abonne pour reprendre la main.
  Stream<int> get decrochageDetecte => _decrochageCtrl.stream;
  /// Relaie le décrochage signalé par la chaîne v2 (le récitateur s'est
  /// écarté du texte attendu). Le DÉTECTEUR vit dans la v2, en Kotlin, là où
  /// le décodage libre existe -- une première version tentait de le refaire
  /// ici, à partir du texte de la v1 : inopérante, la v1 étant coupée dès que
  /// la v2 pilote (`FastConformerCtcPlugin.kt`, `v1Coupee`).
  void _onDecrochageV2(int dernierDefinitif) {
    // ── EN PHASE FATIHA, UN DECROCHAGE VEUT DIRE « IL EST PASSE A LA SUITE »
    //
    // MESURE (session 17:26) : la Fatiha finie, le recitant enchaine sur
    // Al-Baqara. Le decodage libre le dit en clair --
    //     entendu="يَكَادُ ٱلْبَرْقُ يَخْتِفُوٓا"    (2:20)
    //     entendu="كُلَّمَآ أَضَآءَ لَهُمْ"           (2:20)
    // -- et la chaine repete pourtant `dernierDefinitif=27 prochains=[الضالين]
    // horsTexte=9` : elle attend un mot 28 qui ne viendra plus, quinze
    // secondes durant.
    //
    // POURQUOI LE FILET AVAIT DISPARU : le repli « Shazam constate qu'il est
    // ailleurs » (`_checkLeftFatihaViaShazam`) vit dans `_onStructured`, donc
    // sur la v1 -- coupee des que la v2 recoit une cible, ce qui est
    // precisement ce que j'ai fait en donnant la Fatiha a la v2. J'ai supprime
    // le filet en installant le mecanisme qu'il protegeait.
    //
    // Ici, la v2 sait deja qu'elle est perdue : c'est ce que dit son
    // decrochage. En phase Fatiha, cela ne veut pas dire « erreur », cela veut
    // dire « la Fatiha est finie ». On bascule.
    if (_dynamicTargetDiscovery &&
        state.prayerPhase == PrayerPhase.fatiha) {
      DiagnosticLog.log('Priere',
          'decrochage pendant Al-Fatiha -- il est passe a la sourate, '
          'bascule vers l\'identification (dernierDefinitif=$dernierDefinitif)');
      _beginTargetDetection();
      return;
    }
    // Le suivi de prière enchaîne des formules hors texte (takbir, du'a) :
    // ce mode ne doit JAMAIS être interrompu là-dessus.
    if (_confidentMode) return;
    if (state.status != RecitationStatus.listening) return;
    // Reprendre au mot SUIVANT le dernier validé, pas au pointeur : quand la
    // v2 n'a rien pu juger, le pointeur reste à 0 -- il pointait alors sur la
    // Bismillah, où `_verseContaining` rend null, donc aucun audio ne partait
    // (mesure 2026-08-01 : `ancre=0 "بِسْمِ"`, aucune correction audible).
    final reprise = dernierDefinitif >= 0
        ? (dernierDefinitif + 1).clamp(0, state.words.length - 1)
        : state.pointer;
    DiagnosticLog.log('Decrochage',
        'signalé par la v2 -- dernierDefinitif=$dernierDefinitif '
        'reprise=$reprise '
        '"${reprise < state.words.length ? state.words[reprise].display : "?"}"');
    _decrochageCtrl.add(reprise);
  }

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
    // ── LE REPLI PAR ÉLIMINATION DOIT LUI AUSSI RESPECTER LE PRESET ─────
    //
    // Défaut signalé (2026-08-06) : « il y a du violet alors que je ne suis pas
    // en mode tajweed ». Session `preset=adulte regles=aucune`, mot 43
    // `لَّخَبِيرٌۢ` jugé `unclear` par le gop (lettres et harakat justes) :
    // il porte un ghunnah dans le TEXTE, donc cette ligne le classait
    // « erreur de tajwid » et l'écran le peignait en violet -- alors que
    // l'utilisateur n'a jamais demandé qu'on juge le ghunnah.
    //
    // La branche du dessus filtrait déjà par les règles actives
    // (`unrealizedRulesFor`) ; celle-ci lisait `w.expectedRules` brut, c'est-à-
    // dire TOUTES les règles que le texte porte. Les deux branches gardent leur
    // rôle -- constat d'un côté, élimination de l'autre -- mais aucune ne peut
    // accuser sur une règle que le mode ne juge pas.
    //
    // En mode adulte, `shownRulesFor` est vide : on rend `inconnu`, et le mot
    // reste simplement orange (« imprécis »), sans étiquette de tajwid.
    if (shownRulesFor(wordIndex).isNotEmpty) return RecitationErrorKind.tajwid;
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

  // ── Retour a standby sur silence prolonge en [PrayerPhase.target]
  // (demande utilisateur 2026-08-07) ──────────────────────────────────────
  // Jusqu'ici seul un takbir faisait sortir de [target]. Or un silence
  // PROLONGE (l'imam a fini la sourate, passe au rukū' sans "الله أكبر"
  // clairement capte, ou le suivi s'est verrouille sur la mauvaise sourate
  // et plus rien ne s'aligne) doit aussi y ramener -- sans quoi le suivi
  // reste bloque indefiniment sur une cible qui ne vaut plus rien. Un silence
  // COURT (l'imam hesite, cherche la suite) ne doit PAS declencher ce retour :
  // d'ou un delai nettement plus long que celui du souffleur (3s, propose de
  // l'aide) ou du repli de continuite en detection (5s, `_kDetectingTargetSilenceFallbackDelay`).
  // Valeur de depart, PAS ENCORE MESUREE sur device (meme reserve que
  // `_kMinIdentifyConfidence` avant sa recalibration du 2026-08-07) -- a
  // ajuster sur de vrais logs si elle se revele trop courte/trop longue.
  Timer? _targetSilenceStandbyTimer;
  static const _kTargetSilenceStandbyDelay = Duration(seconds: 8);

  void _armTargetSilenceStandbyTimer() {
    _targetSilenceStandbyTimer?.cancel();
    _targetSilenceStandbyTimer = Timer(_kTargetSilenceStandbyDelay, () {
      if (state.prayerPhase != PrayerPhase.target) return;
      DiagnosticLog.log('Priere',
          'silence de ${_kTargetSilenceStandbyDelay.inSeconds}s pendant le '
          'suivi de la sourate -- retour en attente (la rak\'ah suivante '
          'sera reconnue via sa Fatiha, pas besoin d\'un takbir explicite)');
      _enterPrayerStandby();
      resetTrackingToStart();
    });
  }

  // ── Identification en DEUX temps -- REMPLACÉE le 2026-08-02 (cf.
  // `_tryIdentifyTarget` plus bas) par le nouveau scoring
  // `QuranVerseLocatorService` (hachage de paires + vote de décalage, style
  // Shazam) : ce scoring ne se dilue plus quand la requête grossit, donc le
  // découpage en deux fenêtres fixes ci-dessous (qui existait PRÉCISÉMENT
  // pour contourner cette dilution) n'est plus nécessaire. Champs et
  // constantes gardés en commentaire (convention projet, cf. `_tryIdentifyTargetTwoStep`
  // plus bas pour le corps de la méthode) :
  //
  // QuranMatch? _provisionalMatch;
  // int _detectWordsConsumed = 0;
  // static const _kProvisionalWindowWords = 6;
  // static const _kConfirmWindowWords = 6;
  // static const _kProvisionalMinConfidence = 0.5;
  // static const _kConfirmMinConfidence = 0.55;

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
  // ── RECALIBRE SUR DONNEES REELLES (2026-08-07) ─────────────────────────
  //
  // 0.70 datait de l'ANCIEN scoring (fraction de recouvrement ordonne) et
  // n'avait jamais ete redérive pour le scoring actuel (vote de decalage sur
  // paires de mots). Le fichier portait l'avertissement -- il est reste tel
  // quel faute de mesure. La mesure existe maintenant.
  //
  // METHODE : l'algorithme de `QuranVerseLocatorService` a ete rejoue hors
  // device sur les requetes REELLES d'une session (Az-Zukhruf 43:49-51,
  // 2026-08-07 11:37), a partir du meme index `quran_search_index.json`.
  //
  //   requete (extrait)                    1er     score   2e      rapport
  //   إننا لمهتدون فلما..شنا عنهم العذاب   43:49   0,200   0,100   2,0x
  //   ربك بما عد عندك إننا لمهتدون..       43:49   0,206   0,088   2,3x
  //   عنهم العذاب إذا هم ينكثون..          43:50   0,176   0,088   2,0x
  //   بما عد عندك إننا لمهتدون..           43:49   0,147   0,088   1,7x
  //   العذاب إذا هم ينكثون وه تجري..       43:50   0,088   0,059   1,5x
  //
  // DEUX FAITS. (1) Le bon verset est PREMIER dans tous les cas -- le
  // classement fonctionne. (2) Son score plafonne a 0,206 : le seuil etait
  // faux d'un facteur quatre, et l'identification ne pouvait donc quasiment
  // jamais aboutir (35 tentatives, toutes "0 match(s) bruts", sur 45 s).
  //
  // POURQUOI SI BAS, ET POURQUOI C'EST NORMAL : le score est la fraction des
  // paires de la requete qui votent pour le decalage gagnant. Un mot fondu par
  // l'ASR (ادع لنا -> ادعنا) ou perdu detruit TOUTES les paires qui le
  // contiennent -- une dizaine, pas une. Le denominateur compte donc des
  // paires condamnees d'avance. Exiger 70 % de paires exactes sur une sortie
  // ASR reelle est hors d'atteinte par construction.
  //
  // 0,05 est un PLANCHER ANTI-BRUIT, pas un critere de decision : le vrai
  // verset n'est jamais descendu sous 0,088. Ce qui decide, c'est l'ecart au
  // second (cf. _kEcartMinSurSecond).
  static const _kMinIdentifyConfidence = 0.05;

  /// Avance minimale du 1er candidat sur le 2e pour trancher.
  ///
  /// Demande utilisateur (2026-08-07) : « si on descend la barre, il y en aura
  /// plusieurs qui vont respecter, mais il faut avoir un ordre [...] les
  /// prioriser, la meilleure qui va sortir ».
  ///
  /// C'est le bon critere, et la mesure ci-dessus le montre : le vrai verset
  /// devance son suivant d'un facteur 1,5 a 2,3, quand les candidats
  /// coincidentiels se tiennent tous au meme niveau (0,088 pour trois d'entre
  /// eux). 1,3 accepte les six cas mesures avec de la marge, et refuse encore
  /// un peloton serre -- exactement le cas ou il faut attendre plus de texte
  /// plutot que de deviner.
  static const _kEcartMinSurSecond = 1.3;

  /// Nombre ABSOLU de paires devant voter pour le verset retenu.
  ///
  /// ── LE RATIO SEUL EST UN MAUVAIS JUGE (mesure 2026-08-07) ───────────────
  /// Le score est une fraction : deux votes contre un donnent 1,50x, tout
  /// comme neuf contre six. L'un est du bruit, l'autre une certitude, et
  /// l'avance relative ne les distingue pas.
  ///
  /// Mesure sur cas de verite connue (algorithme rejoue hors device) :
  ///   43:49   9 votes / 26 paires   juste
  ///   43:49  11 votes / 26 paires   juste
  ///   43:50   6 votes / 26 paires   juste
  ///    9:88   6 votes / 22 paires   juste
  ///   25:43   2 votes / 22 paires   FAUX -- ancre posee sur un passage deja
  ///                                 recite, souffleur declenche a tort
  /// Les justes tiennent entre 6 et 11, la fausse en a 2 : aucune zone grise.
  /// Plancher a 5, qui laisse de la marge aux quatre cas justes.
  ///
  /// COROLLAIRE, ET C'EST LE POINT DE L'UTILISATEUR : « le systeme a besoin de
  /// plusieurs paires pour decider, c'est pour ca qu'il ne doit pas se
  /// precipiter ». Ce plancher EST le mecanisme d'attente -- tant qu'il n'y a
  /// pas assez de matiere, on ne tranche pas, et l'imam continue de reciter
  /// pendant ce temps.
  static const _kVotesMinIdentification = 5;

  /// Taille de la fenetre RECENTE soumise a l'identification, en mots.
  /// Assez pour etre distinctif (le localisateur vote sur des paires de mots),
  /// assez court pour que le score ne se dilue pas quand la recitation dure.
  static const _kMotsFenetreIdentification = 12;

  /// Combien de mots avant la fin d'Al-Fatiha suffisent a la declarer finie.
  /// 1 = l'avant-dernier suffit (cf. `_onV2`). Le dernier mot est celui qui a
  /// le moins de chances d'etre verrouille : il est toujours en bout de bande.
  static const _kToleranceFinFatiha = 1;

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
    // ── L'EGALITE STRICTE RATAIT LE MOT ALORS QU'IL ETAIT DIT ────────────
    //
    // MESURE (session du 2026-08-07, 09:44:09). Le modele a emis :
    //     "ضَّآلِّينَ"
    // c'est-a-dire le mot de cloture SANS SON ARTICLE `ٱل`. Normalise, cela
    // donne `ضالين` -- et `ضالين != الضالين`, donc aucune correspondance. La
    // fin d'Al-Fatiha n'a pas ete reconnue alors qu'elle avait ete
    // correctement entendue, et l'application est restee 20 s de trop dans la
    // phase Fatiha, jusque dans les versets 1 a 10 de Saba'. Toute la suite en
    // decoule : identification sur le mauvais passage (34:10/34:11), ancre
    // posee au mot 177, souffleur declenche, mots condamnes a tort.
    //
    // ⚠️ J'AI D'ABORD CONCLU L'INVERSE, ET C'ETAIT FAUX : un `grep` sur `ضال`
    // dans un journal entierement diacrite avait rendu zero, et j'en avais
    // deduit que le modele n'avait jamais emis ce mot. C'est l'instrument qui
    // echouait. Le controle refait en retirant les diacritiques des DEUX
    // cotes rend bien 1 occurrence. (Regle projet : un resultat negatif est
    // une affirmation a verifier, jamais un fait acquis.)
    //
    // On compare donc par SUFFIXE : un article manquant, un prefixe de
    // liaison ou une lettre parasite en tete ne doivent plus faire rater un
    // mot que le modele a pourtant produit. Le sens du test est inchange --
    // ces deux mots restent uniques dans tout le Coran, donc un suffixe ne
    // peut pas les confondre avec autre chose.
    // ── LE PARASITE PEUT ETRE AUX DEUX BOUTS (corrige 2026-08-07, 2e fois) ─
    //
    // La comparaison par SUFFIXE (posee le matin meme) couvrait le mot rendu
    // SANS SON ARTICLE : `ضالين` pour `الضالين`. Mesure de 17:18, session de
    // priere : le modele a rendu
    //     "بِ مِنَ ٱلضَّآلِّينَم"        <- un م colle A LA FIN
    //     "بِ ٱلضَّآلِّينَملُوْقَ"        <- la syllabe suivante soudee
    // Le jeton ne se TERMINE donc pas par le mot cherche, il le CONTIENT. La
    // fin d'Al-Fatiha n'a une seconde fois pas ete reconnue, alors qu'elle
    // avait ete correctement entendue -- quatre fois de suite.
    //
    // On passe donc a la CONTENANCE, qui couvre les deux bouts d'un coup :
    // article manquant en tete, syllabe soudee en queue, ou les deux.
    //
    // POURQUOI C'EST SANS RISQUE ICI, et seulement ici : `الضالين` et
    // `المغضوب` sont uniques dans tout le Coran (verifie sur les 6236
    // versets). Aucun autre mot ne peut les contenir par accident. Ce
    // relachement ne serait PAS acceptable sur un mot courant -- ce n'est pas
    // une tolerance de jugement, c'est la reconnaissance d'un marqueur unique.
    return tokens.any((t) =>
        t.contains(_fatihaClosingWord) ||
        t.contains(_fatihaAlmostClosingWord));
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
    _targetSilenceStandbyTimer?.cancel();
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
  /// [departMot] : ou le recitant en est DEJA dans Al-Fatiha.
  ///
  /// ── ON NE SE BLOQUE PAS SUR LE DEBUT (utilisateur, 2026-08-07) ──────────
  /// « Il ne faut pas se bloquer sur le debut ; on doit juste chercher a se
  /// PLACER sur la Fatiha, ce n'est pas grave. »
  ///
  /// C'est plus juste que de guetter l'ouverture : rater `الحمد لله` -- que le
  /// modele rend `ٱلْمِدِي` -- ne doit pas empecher de suivre le reste. On
  /// entre donc la ou le recitant se trouve, et les mots precedents sont
  /// simplement marques comme passes. Le localisateur affinera : en mode
  /// priere le saut lui est libre.
  Future<void> _beginFatihaPhase({int departMot = 0}) async {
    await _ensureFatihaWords();
    final fatiha = _fatihaWords;
    if (fatiha == null || fatiha.isEmpty) return;
    if (state.prayerPhase != PrayerPhase.standby) return;
    final depart = departMot.clamp(0, fatiha.length - 1);
    final fresh = <RecitedWord>[
      for (var i = 0; i < fatiha.length; i++)
        fatiha[i].copyWith(
            status: i < depart ? WordStatus.skipped : WordStatus.pending,
            locked: false),
    ];
    fresh[depart] = fresh[depart].copyWith(status: WordStatus.current);
    _anchorExp = depart;
    _lastAnchorAdvanceAt = DateTime.now();
    _prevCommitted = '';
    _fatihaScanStart = _takbirScannedCommittedLen;
    state = state.copyWith(
      words: fresh,
      pointer: depart,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.fatiha,
    );
    final cibleFatiha = fatiha.map((w) => w.alignTarget).toList();
    await _verifier.replaceAlignmentTarget(cibleFatiha, depart,
        refMinFrames: _refMinFrames(fatiha));
    // ── ON CONNAIT LA FATIHA : PLUS AUCUNE RAISON DE DEVINER ──────────────
    //
    // Remarque de l'utilisateur (2026-08-07) : « du coup, on sait que dans la
    // priere c'est la Fatiha en premier ; apres, une fois la sourate detectee,
    // il sait la sourate ». C'est juste, et ca change la nature du probleme.
    //
    // L'encodeur ne recoit JAMAIS le texte attendu : il n'a que l'audio. Le
    // texte n'intervient qu'apres, dans l'alignement. Deux usages de la meme
    // matrice de probabilites :
    //   - DECODAGE LIBRE : « qu'est-ce qui a ete dit ? », choisir dans tout le
    //     vocabulaire a chaque frame. Sur un modele CAUSAL (contexte [70,13],
    //     14 frames valides), il decide presque sans futur -- d'ou les mots
    //     soudes mesures ce jour : `ٱلضَّآلِّينَملُوْقَ`, `مَآ أَآءَ مَا حَوْلَهُۥٓ` ;
    //   - ALIGNEMENT FORCE : « ou se placent CES mots-la ? ». Le texte est
    //     donne, il ne reste qu'a trouver les frontieres. Bien plus simple.
    //
    // La cible v2 restait VIDE pendant toute la Fatiha, donc la phase la plus
    // previsible de la priere tournait dans le mode le plus difficile. On lui
    // donne desormais le texte : la Fatiha est jugee comme une recitation
    // normale, et sa FIN se lit a la position de l'ancre plutot qu'a un jeton
    // exact -- ce qui a echoue trois fois aujourd'hui (article manquant,
    // lettre doublee du takbir, syllabe soudee).
    //
    // `depart: 0` : l'imam commence la Fatiha par le debut.
    await _verifier.v2Activer(true, cibleFatiha,
        mode: 'PRIERE',
        depart: depart,
        // Meme raison qu'a l'identification de sourate : entrer au milieu
        // d'Al-Fatiha ne rend pas les mots precedents « oublies ».
        nonJugeables: [for (var i = 0; i < depart; i++) i]);
    DiagnosticLog.log('Priere',
        'cible v2 = Al-Fatiha (${cibleFatiha.length} mots), entree au mot '
        '$depart -- alignement force au lieu du decodage libre, et la fin se '
        'lira a l\'ancre');
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
    // Plus de candidat provisoire à réinitialiser depuis le passage au
    // scoring par vote de décalage (cf. _tryIdentifyTarget) -- chaque appel
    // rescore le texte "sûr" accumulé depuis `_targetDetectScanStart`
    // (réinitialisé juste au-dessus), rien à repartir à zéro ici.
    _armDetectingTargetFallbackTimer();
    state = state.copyWith(
      words: const [],
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.detectingTarget,
    );
    // ── CE CHEMIN ETAIT INVISIBLE (corrige 2026-08-07) ──────────────────
    //
    // Tout le parcours d'identification ecrivait en `debugPrint` : rien n'en
    // arrivait dans le journal de l'appareil. Sur la session du 09:21, Shazam
    // a pu tourner cinquante fois et echouer cinquante fois -- le journal
    // aurait ete rigoureusement identique, et j'ai failli en conclure a tort
    // qu'il n'avait jamais ete appele. Un mecanisme sans trace n'est pas
    // diagnosticable ; c'est la premiere chose a reparer, avant tout reglage.
    DiagnosticLog.log('Priere',
        'Al-Fatiha terminee -- debut de l\'identification de la sourate '
        '(scan a partir de $_targetDetectScanStart caracteres)');
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
    _armTargetSilenceStandbyTimer();
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
  /// `_tryIdentifyTarget` UNE FOIS le candidat déjà accepté (plus de
  /// garde-fou de confiance/plausibilité ici, le seuil + l'unicité du
  /// candidat dans `_tryIdentifyTarget` en tiennent lieu).
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
    // ── L'ANCRE SE POSE APRES LE PASSAGE APPARIE (corrige 2026-08-07) ────
    //
    // DEFAUT MESURE (session 17:34) : identification `25:43`, ancre au mot
    // 508 -- le DEBUT de 25:43. Sept secondes plus tard :
    //     passage non entendu : mots 508..520 ("أَرَءَيْتَ مَنِ ٱتَّخَذَ...")
    // c'est-a-dire le verset entier souffle, alors qu'il venait d'etre recite
    // correctement.
    //
    // LA CAUSE EST STRUCTURELLE, pas un reglage : on identifie un verset
    // PARCE QU'IL VIENT D'ETRE DIT. Le temps de le reconnaitre, le recitant
    // est deja au suivant. Poser l'ancre a son debut, c'est poser le curseur
    // la ou il ETAIT, jamais la ou il EST -- et tout ce qu'il a deja dit
    // devient un « passage non entendu ».
    //
    // On se cale donc APRES le verset apparie. Le localisateur affinera de
    // lui-meme si le recitant est ailleurs : c'est son metier, et en mode
    // priere le saut lui est libre (`sautLibre`).
    // ── ON REVIENT AU DEBUT DU VERSET APPARIE (2026-08-07, 2e passe) ─────
    //
    // La premiere version de ce correctif posait l'ancre APRES le verset
    // trouve, pour compenser le retard de Shazam. C'etait traiter le symptome.
    //
    // Le vrai mecanisme : le localisateur cherche dans
    // `[ancre - reculMax, ancre + avanceMax]` = -20/+80. Il est QUATRE FOIS
    // plus tolerant vers l'avant -- une ancre un peu en arriere se rattrape
    // toute seule, une ancre trop en avant ne se rattrape pas. Se caler au
    // debut du verset reconnu est donc le choix sur.
    //
    // Ce qui posait probleme n'etait pas la position mais le SOUFFLEUR : les
    // mots entre le point d'entree et la position reelle etaient declares
    // « non entendus ». Ils n'avaient jamais ete attendus -- c'est le
    // decalage d'entree, pas un oubli. Traite cote chaine
    // (`ChaineRecitation.premiereLocalisation`), a sa place.
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
    _armTargetSilenceStandbyTimer();
    state = state.copyWith(
      words: fresh,
      pointer: anchor,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      prayerPhase: PrayerPhase.target,
    );
    final cibleV2 = allWords.map((w) => w.alignTarget).toList();
    await _verifier.replaceAlignmentTarget(cibleV2, anchor,
        refMinFrames: _refMinFrames(allWords));
    // ── LA CIBLE DOIT AUSSI ALLER A LA v2 (corrige 2026-08-07) ────────────
    //
    // DEFAUT CONSTATE PAR L'UTILISATEUR : « apres la correction, l'ancre
    // attend ; il faut activer le localiseur pour chercher ou l'imam est
    // arrive, car l'imam n'est pas oblige d'attendre et d'ecouter le
    // souffleur -- c'est une proposition ».
    //
    // MESURE (session 09:35, sourate 12 identifiee a 0,85 de confiance,
    // suivi arme au mot 104/1777) : `[V2] mot=` vaut ZERO sur toute la
    // session, `SAUT ACCEPTE` aussi, et deux souffleurs de silence tombent a
    // 09:35:51 puis 09:36:50 -- une minute sans la moindre avancee.
    //
    // CAUSE : cette fonction posait la cible sur l'aligneur v1
    // (`replaceAlignmentTarget`) et sur LUI SEUL. v1 et v2 ont chacun leur
    // cible native, volontairement separees (cf. le commentaire de
    // `v2SetTarget` cote Kotlin) -- `v2Mots` restait donc vide, la chaine
    // n'avait rien a localiser, et tout le mode retombait sur l'alignement
    // FORCE de la v1, qui attend a l'ancre par construction. Le mode priere
    // etait branche sur la v2 au demarrage, puis la perdait des la premiere
    // sourate identifiee.
    //
    // C'est ce qui rend le localisateur reellement operant : quand l'imam ne
    // reprend pas la ou on l'attendait, la v2 le RETROUVE au lieu de
    // l'attendre -- et `sautLibre` fait que le trou ne bloque rien.
    if (_dynamicTargetDiscovery) {
      // `depart: anchor` -- SANS LUI LA CHAINE CHERCHAIT ENTRE 0 ET 80
      // (mesure du 2026-08-07, cf. ChaineRecitation.definirTexte) : la sourate
      // 9 identifiee au mot 1652, une region de recherche de 80 mots autour du
      // mot 0, et `bande=inconnue` sur toutes les fenetres. L'identification
      // connait la position, elle la transmet maintenant.
      // ── LES MOTS AVANT L'ENTREE NE SONT PAS DES OUBLIS (2026-08-07) ───
      //
      // MESURE (session 18:07) : entree au mot 577 (25:49), la chaine suit
      // correctement -- `bande=600..606 conf=1,00`, mots 605/606/607 verts --
      // et declare pourtant :
      //     [V2] mot=0 "تَبَارَكَ"   -> omis
      //     [V2] mot=1..6              -> omis
      // c'est-a-dire l'ouverture de la sourate, que le recitant n'a JAMAIS eu
      // a dire puisqu'il a commence au verset 49.
      //
      // CAUSE : le Decideur declare `omis` un mot jamais atteste des lors
      // qu'assez de mots POSTERIEURS sont definitifs. Avec une entree au mot
      // 577, les 577 premiers remplissent cette condition mecaniquement. Et
      // comme les trous comptent ces mots, le souffleur part sur un
      // « passage non entendu » qui n'a jamais ete attendu.
      //
      // `nonJugeables` existe deja pour exactement ca (la Bismillah non
      // recitee) : il suffisait de le remplir. Ces mots sortent alors des
      // verdicts ET du calcul des trous (cf. `ChaineRecitation.sautEntre`).
      await _verifier.v2Activer(true, cibleV2,
          mode: 'PRIERE',
          depart: anchor,
          nonJugeables: [for (var i = 0; i < anchor; i++) i]);
      if (anchor > 0) {
        DiagnosticLog.log('Priere',
            'mots 0..${anchor - 1} declares NON JUGEABLES : entree en cours de '
            'sourate, ils n\'ont jamais eu a etre recites');
      }
      DiagnosticLog.log('Priere',
          'cible v2 posee : ${cibleV2.length} mots (sourate '
          '${match.surahNumber}) -- le localisateur peut desormais retrouver '
          'l\'imam ou qu\'il en soit, le saut ne bloque pas');
    }
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

  /// Identification (Shazam) pendant [PrayerPhase.detectingTarget] --
  /// réécrite le 2026-08-02 autour du nouveau scoring par vote de décalage
  /// (`QuranVerseLocatorService._rankCandidates`, principe Shazam : hachage
  /// combinatoire de paires + vote sur le décalage d'alignement). REMPLACE
  /// `_tryIdentifyTargetTwoStep` (gardée plus bas en commentaire) : ce
  /// scoring ne se dilue plus quand la requête grossit (vote de décalage, pas
  /// fraction sur la longueur totale de la requête), donc plus besoin de
  /// fenêtres fixes ni de bookkeeping de consommation -- on rescore
  /// simplement le texte "sûr" accumulé depuis le début à CHAQUE nouveau
  /// texte reconnu (appelé par `_onStructured`, cf. `probeChanged`).
  ///
  /// Décision utilisateur (2026-08-02) : dès qu'UN SEUL candidat dépasse le
  /// seuil de confiance -- même dès le tout premier appel, sans attendre
  /// confirmation sur une fenêtre supplémentaire -- il est accepté
  /// IMMÉDIATEMENT. S'il reste plusieurs candidats au-dessus du seuil
  /// (ambigu), on attend le prochain texte reconnu pour les départager,
  /// plutôt que de trancher au hasard entre eux.
  ///
  /// ⚠️ `_kMinIdentifyConfidence` (0.70) date de l'ANCIEN scoring
  /// (fraction de recouvrement ordonné) -- le nouveau score (fraction de
  /// PAIRES votant pour le décalage gagnant) n'a pas la même distribution de
  /// valeurs typiques. Valeur reprise telle quelle faute de mesure device
  /// disponible au moment de l'écriture ; à RECALIBRER sur de vrais logs
  /// avant de considérer ce chantier validé (cf. SUIVI_PRIERE.md §4).
  // ── PILOTE DU CYCLE DE PRIERE, SUR LE DECODAGE LIBRE (2026-08-07) ───────
  //
  // Remplace le pilotage par `_onStructured` (texte de la v1), mesure quasi
  // muet sur ce mode. La v2 rend, fenetre par fenetre, ce qu'elle entend sans
  // aucune cible -- exactement ce qu'il faut pour reconnaitre un takbir puis
  // identifier la sourate.
  //
  // TROIS PHASES, ET UNE SEULE FAIT APPEL A L'IDENTIFICATION :
  //   standby         : on attend le takbir ou Al-Fatiha ;
  //   detectingTarget : Al-Fatiha finie -> on identifie la sourate. C'est ICI,
  //                     et NULLE PART AILLEURS, que « Shazam » tourne ;
  //   target          : la sourate est connue -> plus jamais d'identification,
  //                     seulement la localisation a l'interieur de ce texte.
  //
  // Specification utilisateur : « oublie le Shazam, il va se declencher au
  // debut, et peut-etre plusieurs fois, pour bien cibler la sourate. Mais
  // apres, c'est juste se localiser parce qu'il ne va pas changer de sourate. »
  // La phase `target` sort donc immediatement, sans meme accumuler du texte.
  static const _kFenetresLibresGardees = 6;
  final _libreRecent = <String>[];

  void _onDecodageLibrePriere(String texte) {
    if (!_dynamicTargetDiscovery) return;
    if (texte.trim().isEmpty) return;

    // Un takbir renvoie en attente, quelle que soit la phase : c'est la
    // frontiere entre deux cycles (nouvelle rak'ah, ruku', sujud). Meme regle
    // qu'avant, meme fonction -- seule la SOURCE du texte change.
    //
    // BUG CORRIGE (2026-08-07, lecture de code -- jamais exerce sur un log
    // reel, aucun takbir n'a encore ete prononce dans une session de test) :
    // cette branche n'appelait QUE `resetTrackingToStart()`, qui remet les
    // mots/l'ancre a zero mais NE TOUCHE PAS `state.prayerPhase`. La phase
    // restait donc bloquee sur `target`/`fatiha`, et comme le detecteur de
    // Fatiha ne tourne que si `prayerPhase == standby`, la rak'ah suivante
    // n'aurait plus jamais ete reconnue. Le detecteur v1 (`_onStructured`)
    // appelle bien `_enterPrayerStandby()`, mais le log dit lui-meme que la
    // v1 est "quasi muette" pendant la priere -- ce chemin v2 est celui qui
    // tourne reellement. `_enterPrayerStandby()` AVANT `resetTrackingToStart()`
    // : il lit `_anchorExp`/`_currentTargetSurah` courants pour la continuite
    // entre rak'ah (cf. commentaire des champs `_lastTargetSurahForContinuation`)
    // -- les inverser memoriserait toujours la position 0.
    if (_hasTakbir(texte)) {
      DiagnosticLog.log('Priere', 'takbir entendu ("$texte") -- retour en '
          'attente, la cible precedente ne vaut plus');
      _libreRecent.clear();
      _enterPrayerStandby();
      resetTrackingToStart();
      return;
    }

    // SOURATE DEJA IDENTIFIEE : on ne cherche plus rien, mais on reste a
    // l'ecoute pour reconnaitre un silence prolonge (cf.
    // `_armTargetSilenceStandbyTimer`) -- tout texte non vide prouve que le
    // recitateur parle encore, donc repousse l'echeance.
    if (state.prayerPhase == PrayerPhase.target) {
      _armTargetSilenceStandbyTimer();
      return;
    }

    _libreRecent.add(texte);
    while (_libreRecent.length > _kFenetresLibresGardees) {
      _libreRecent.removeAt(0);
    }
    final probe = _libreRecent.join(' ');

    if (state.prayerPhase == PrayerPhase.detectingTarget) {
      // Plusieurs tentatives sont normales et voulues : chaque nouvelle
      // fenetre enrichit la requete jusqu'a ce qu'un candidat soit unique.
      unawaited(_tryIdentifyTarget(probe));
    }
  }

  /// Passage probablement saute : on le SOUFFLE, on ne le juge pas.
  ///
  /// « Il va juste reciter les mots qu'il pense qu'il y a un oubli, donc il
  /// faut poursuivre le Coran, mais apres, il faut debloquer le saut. [...]
  /// Au lieu d'attendre l'ancre comme dans les autres modes, juste on repete.
  /// [...] Meme quand le saut est detecte on lance le souffleur, mais apres
  /// c'est l'aligneur, on ne force pas a suivre. »
  ///
  /// CE QU'ON NE FAIT PAS, ET C'EST L'ESSENTIEL : aucun recul d'ancre, aucune
  /// attente qu'il repete, aucun replacement d'autorite sur les mots souffles.
  /// La chaine a deja garde la bande et suivi le recitateur la ou il est ; ce
  /// signal ne sert qu'a lui faire entendre le passage.
  void _onSautPresume(({int de, int a}) bornes) {
    if (!_dynamicTargetDiscovery) return;
    if (state.prayerPhase != PrayerPhase.target) return;
    final premier = bornes.de + 1;
    final dernier = bornes.a - 1;
    if (premier < 0 || dernier < premier || dernier >= state.words.length) return;
    DiagnosticLog.log('Priere',
        'passage non entendu : mots $premier..$dernier '
        '("${state.words.sublist(premier, dernier + 1).map((w) => w.display).join(" ")}") '
        '-- souffle avec son contexte (2 mots avant, 3 apres), PAS juge : '
        'aucune ancre ne recule, rien n\'attend qu\'il le repete, et '
        'l\'aligneur reste libre de se replacer ou il veut');
    _sautPresumeCtrl.add((de: premier, a: dernier));
  }

  final _sautPresumeCtrl = StreamController<({int de, int a})>.broadcast();

  /// Passage a souffler (mode priere). L'ecran s'y abonne pour jouer l'audio
  /// du recitateur sur ces mots. Aucun verdict n'y est attache.
  Stream<({int de, int a})> get sautASouffler => _sautPresumeCtrl.stream;

  bool _faisceauFatihaEnCours = false;

  /// Al-Fatiha a-t-elle commence ? Repond par le VOTE de paires plutot que
  /// par un jeton exact (cf. l'appelant pour la mesure qui l'impose).
  Future<void> _verifierDebutFatihaParFaisceau(String probe) async {
    if (_faisceauFatihaEnCours || probe.isEmpty) return;
    if (state.prayerPhase != PrayerPhase.standby) return;
    _faisceauFatihaEnCours = true;
    try {
      final matches = await QuranVerseLocatorService.instance
          .locateTopMatches(probe, minScore: _kMinIdentifyConfidence);
      if (state.prayerPhase != PrayerPhase.standby) return;
      final fatiha = matches.where((m) => m.surahNumber == 1).toList();
      if (fatiha.isEmpty) return;
      final m = fatiha.first;
      if (m.votes < _kVotesMinIdentification) {
        DiagnosticLog.log('Priere',
            'debut Al-Fatiha : ${m.votes} vote(s) seulement '
            '(< $_kVotesMinIdentification) -- on attend');
        return;
      }
      // On ne cherche pas le DEBUT, on cherche OU IL EN EST : l'ancre se pose
      // au verset reconnu, pas au mot 0.
      var depart = 0;
      for (final v in _fatihaVerses ?? const <Verse>[]) {
        if (v.ayahNumber < m.ayahNumber) {
          depart += ArabicNormalizer.splitExpectedWords(v.textUthmani).length;
        }
      }
      DiagnosticLog.log('Priere',
          'Al-Fatiha REPEREE par faisceau a 1:${m.ayahNumber} '
          '(${m.votes} vote(s)) -- entree au mot $depart, on ne reclame pas '
          'le debut (le detecteur exact avait echoue : mot deforme)');
      await _beginFatihaPhase(departMot: depart);
    } catch (e) {
      DiagnosticLog.log('Priere', 'faisceau Al-Fatiha : echec $e');
    } finally {
      _faisceauFatihaEnCours = false;
    }
  }

  Future<void> _tryIdentifyTarget(String cleanedProbe) async {
    if (_targetLookupInFlight) return;
    _targetLookupInFlight = true;
    try {
      final matches = await QuranVerseLocatorService.instance.locateTopMatches(
          cleanedProbe,
          minScore: _kMinIdentifyConfidence);
      if (state.prayerPhase != PrayerPhase.detectingTarget) return;
      // Bismillah/fin d'Al-Fatiha résiduelle (cf. §3.6 du journal) : jamais
      // un candidat exploitable à ce stade, quel que soit son score.
      final candidates = matches.where((m) => m.surahNumber != 1).toList();
      if (candidates.isEmpty) {
        DiagnosticLog.log('Priere',
            'identification : AUCUN candidat >= $_kMinIdentifyConfidence sur '
            '"${cleanedProbe.length > 90 ? "${cleanedProbe.substring(0, 90)}..." : cleanedProbe}" '
            '(${matches.length} match(s) bruts, tous ecartes) -- on reessaiera '
            'au prochain texte reconnu');
        return;
      }
      // ── PRIORISER, PLUTOT QUE D'EXIGER L'UNICITE (2026-08-07) ─────────
      //
      // Demande utilisateur : « si on descend la barre, il y en aura plusieurs
      // qui vont respecter. Mais il faut avoir un ordre [...] les prioriser,
      // la meilleure qui va sortir. »
      //
      // L'ancienne regle refusait des qu'il y avait DEUX candidats. Combinee a
      // un seuil quatre fois trop haut (cf. _kMinIdentifyConfidence), elle
      // rendait l'identification quasi impossible. Et elle etait mal fondee :
      // la mesure montre que le bon verset est PREMIER a chaque fois -- ce
      // n'est pas l'unicite qui le distingue, c'est son AVANCE sur le second.
      //
      // On prend donc le meilleur des que son avance depasse
      // _kEcartMinSurSecond. Un peloton serre (avance insuffisante) reste
      // refuse : c'est le seul cas ou attendre plus de texte vaut mieux que
      // deviner.
      //
      // ANCIEN CODE, conserve (convention projet) :
      //   if (candidates.length > 1) { ... return; }
      //   final only = candidates.single;
      final meilleur = candidates.first;
      final second = candidates.length > 1 ? candidates[1] : null;
      final avance = second == null || second.confidence <= 0
          ? double.infinity
          : meilleur.confidence / second.confidence;
      // Pas assez de PAIRES votantes : on ne tranche pas, quelle que soit
      // l'avance (cf. `_kVotesMinIdentification`).
      if (meilleur.votes < _kVotesMinIdentification) {
        DiagnosticLog.log('Priere',
            'identification : seulement ${meilleur.votes} paire(s) votante(s) '
            'pour ${meilleur.surahNumber}:${meilleur.ayahNumber} '
            '(< $_kVotesMinIdentification) -- trop peu de matiere, on attend '
            'que la recitation en donne davantage');
        return;
      }
      if (avance < _kEcartMinSurSecond) {
        DiagnosticLog.log('Priere',
            'identification : peloton serre, avance ${avance.toStringAsFixed(2)}x '
            '< ${_kEcartMinSurSecond}x '
            '(${candidates.take(3).map((m) => "${m.surahNumber}:${m.ayahNumber}="
                "${m.confidence.toStringAsFixed(3)}").join(", ")}) '
            '-- on attend plus de texte pour departager');
        return;
      }
      DiagnosticLog.log('Priere',
          'identification : RETENU ${meilleur.surahNumber}:${meilleur.ayahNumber} '
          '${meilleur.votes} vote(s), score ${meilleur.confidence.toStringAsFixed(3)}'
          '${second == null ? " (seul candidat)" : ", second "
              "${second.surahNumber}:${second.ayahNumber} "
              "${second.confidence.toStringAsFixed(3)}, avance "
              "${avance.toStringAsFixed(2)}x"}');
      await _beginIdentifiedTargetPhase(meilleur);
    } catch (e) {
      DiagnosticLog.log('Priere', 'identification : ECHEC technique : $e');
    } finally {
      _targetLookupInFlight = false;
    }
  }

  // ANCIENNE APPROCHE "deux temps" (2026-07-19, demande utilisateur "il faut
  // afficher le premier puis le confirmer ; sinon recherche 4-6 mots suivant,
  // je trouve actuellement la méthode lourde") -- REMPLACÉE le 2026-08-02
  // par `_tryIdentifyTarget` ci-dessus (cf. commentaire des champs
  // `_provisionalMatch`/`_detectWordsConsumed`, plus haut, pour le pourquoi).
  // Gardée en commentaire, pas supprimée (convention projet) :
  //
  // Future<void> _tryIdentifyTargetTwoStep(String cleanedProbe) async {
  //   if (_targetLookupInFlight) return;
  //   final allWords = cleanedProbe
  //       .split(RegExp(r'\s+'))
  //       .where((w) => w.isNotEmpty)
  //       .toList();
  //   _targetLookupInFlight = true;
  //   try {
  //     if (_provisionalMatch == null) {
  //       final remaining = allWords.skip(_detectWordsConsumed).toList();
  //       if (remaining.length < _kProvisionalWindowWords) return;
  //       final windowWords = remaining.take(_kProvisionalWindowWords).toList();
  //       final matches = await QuranVerseLocatorService.instance.locateTopMatches(
  //           windowWords.join(' '),
  //           minScore: _kProvisionalMinConfidence);
  //       QuranMatch? picked;
  //       for (final m in matches) {
  //         if (m.surahNumber == 1) continue; // bismillah/fin Fatiha résiduelle
  //         picked = m;
  //         break;
  //       }
  //       // Avance TOUJOURS (trouvé ou pas) -- ne jamais retenter la MÊME
  //       // fenêtre indéfiniment, cf. "sinon recherche 4-6 mots suivant".
  //       _detectWordsConsumed += _kProvisionalWindowWords;
  //       if (picked != null) {
  //         _provisionalMatch = picked;
  //         DiagnosticLog.log('Prière', 'candidat PROVISOIRE ${picked.surahNumber}:'
  //             '${picked.ayahNumber} (confiance ${picked.confidence.toStringAsFixed(2)}) '
  //             '-- en attente de confirmation');
  //       } else {
  //         debugPrint('[Prière] aucun candidat sur cette fenêtre de '
  //             '$_kProvisionalWindowWords mots -- fenêtre suivante');
  //       }
  //       return;
  //     }
  //
  //     // Un candidat provisoire existe déjà -- chercher la fenêtre de
  //     // CONFIRMATION (mots reconnus JUSTE APRÈS la fenêtre provisoire).
  //     final remaining = allWords.skip(_detectWordsConsumed).toList();
  //     if (remaining.length < _kConfirmWindowWords) return;
  //     final confirmWindow = remaining.take(_kConfirmWindowWords).toList();
  //     final provisional = _provisionalMatch!;
  //     final continuation = await QuranVerseLocatorService.instance
  //         .continuationWords(provisional.surahNumber, provisional.ayahNumber,
  //             _kConfirmWindowWords + 15); // marge -- offset exact dans le verset inconnu
  //     final score = QuranVerseLocatorService.instance
  //         .scoreWordWindows(confirmWindow, continuation);
  //     if (score >= _kConfirmMinConfidence) {
  //       DiagnosticLog.log('Prière', 'candidat ${provisional.surahNumber}:'
  //           '${provisional.ayahNumber} CONFIRMÉ (score continuation '
  //           '${score.toStringAsFixed(2)})');
  //       _provisionalMatch = null;
  //       _detectWordsConsumed = 0;
  //       await _beginIdentifiedTargetPhase(provisional);
  //     } else {
  //       DiagnosticLog.log('Prière', 'confirmation échouée pour '
  //           '${provisional.surahNumber}:${provisional.ayahNumber} '
  //           '(score ${score.toStringAsFixed(2)} < $_kConfirmMinConfidence) -- '
  //           'la fenêtre de confirmation devient le nouvel essai');
  //       // NE PAS avancer _detectWordsConsumed ici : au prochain appel,
  //       // `remaining` (donc `confirmWindow` et la suite) redevient la
  //       // PREMIÈRE fenêtre d'un nouvel essai -- rien n'est perdu, rien n'est
  //       // réessayé deux fois.
  //       _provisionalMatch = null;
  //     }
  //   } catch (e) {
  //     debugPrint('[Prière] échec identification en deux temps : $e');
  //   } finally {
  //     _targetLookupInFlight = false;
  //   }
  // }

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
    // ANCRE : fonction PROPRE a la recitation (cloisonnement 2026-08-05).
    // `locate()` est reglee pour IDENTIFIER un passage inconnu -- plus
    // permissive depuis la correction du Shazam, donc plus encline a trouver
    // ET a se tromper. Acceptable pour afficher un verset ; pas pour deplacer
    // l'ancre, ou une erreur ne se voit pas et ne se rattrape pas.
    QuranVerseLocatorService.instance.localiserPourAncre(probe).then((match) {
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
  /// Index des mots que l'app ne juge JAMAIS -- la Bismillah insérée en tête
  /// de sourate (décision projet 2026-07-20, `isBasmala`).
  ///
  /// La chaîne v2 en a besoin pour ne PAS les compter dans un saut : sans ça,
  /// franchir une frontière de sourate ressemble à un saut de 4 mots, et
  /// l'ancre reste bloquée pour de bon (défaut mesuré le 2026-08-06 —
  /// « pause puis play pour passer à une autre sourate, rien ne se passe »).
  /// Dart en est la seule autorité : détecter la Bismillah sur le texte
  /// confondrait celle qui est insérée avec le verset 1:1 d'Al-Fatiha, qui
  /// lui est bien récité.
  /// « صدق الله العظيم » — texte source de la phrase de fin optionnelle.
  /// Cf. `phraseFinRecitationProvider` pour le pourquoi et pour la raison du
  /// défaut désactivé. Vide tant que le réglage n'est pas activé.
  static const _kPhraseFinTexte = 'صَدَقَ ٱللَّهُ ٱلْعَظِيمُ';

  /// Mots de la phrase de fin, dans la MÊME forme que `RecitedWord
  /// .alignTarget` (`normalizeTraining`) -- sinon la chaîne ne pourrait pas
  /// les apparier. Liste vide = réglage désactivé, comportement d'origine
  /// strictement inchangé.
  List<String> _motsPhraseFin = const [];

  /// Branché sur `phraseFinRecitationProvider` par l'écran (même patron que
  /// `setSensitivity`). Ne prend effet qu'à la session SUIVANTE : la cible est
  /// posée au démarrage, la changer en cours de récitation décalerait tous les
  /// index de mots déjà jugés.
  void setPhraseFin(bool actif) {
    _motsPhraseFin = actif
        ? ArabicNormalizer.splitExpectedWords(_kPhraseFinTexte)
            .map(ArabicNormalizer.normalizeTraining)
            .toList()
        : const [];
  }

  /// L'état courant, lisible SANS passer par `ref`.
  ///
  /// Existe pour `dispose()` côté écran (2026-08-14) : `ref` n'y est plus
  /// fiable (`Bad state: Cannot use "ref" after the widget was disposed`),
  /// alors que la clôture d'archive doit lire l'état LE PLUS RÉCENT --
  /// c'est-à-dire après `stopContinuous()`, donc après le dernier `build()`.
  /// Ce notifier n'est pas `autoDispose` : il survit à l'écran qui le pilote.
  RecitationSessionState get etatCourant => state;

  static List<int> _indicesNonJuges(List<RecitedWord> mots, {int decalage = 0}) {
    final out = <int>[];
    for (var i = 0; i < mots.length; i++) {
      if (mots[i].isBasmala) out.add(decalage + i);
    }
    return out;
  }

  /// texte à réciter derrière.
  Future<void> extendWords(String moreArabicText) async {
    final newWords = _wordsFromText(moreArabicText);
    if (newWords.isEmpty) return;
    state = state.copyWith(words: [...state.words, ...newWords]);
    final cible = newWords.map((w) => w.alignTarget).toList();
    await _verifier.extendAlignmentTarget(cible,
        refMinFrames: _refMinFrames(newWords));
    // v2 A SA PROPRE CIBLE, cf. v2ExtendTarget : sans cet appel, la chaîne
    // qui pilote vraiment l'écran restait figée à sa taille de départ pour
    // toute la session (2026-08-05).
    await _verifier.v2ExtendTarget(cible,
        nonJugeables: _indicesNonJuges(newWords,
            decalage: state.words.length - newWords.length));
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
    final cible = newWords.map((w) => w.alignTarget).toList();
    await _verifier.extendAlignmentTarget(cible,
        refMinFrames: _refMinFrames(newWords));
    // v2 A SA PROPRE CIBLE, cf. v2ExtendTarget : sans cet appel, la chaîne
    // qui pilote vraiment l'écran restait figée à sa taille de départ pour
    // toute la session (2026-08-05).
    await _verifier.v2ExtendTarget(cible,
        nonJugeables: _indicesNonJuges(newWords,
            decalage: state.words.length - newWords.length));
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
    _v2Sub = _verifier.v2Statuses.listen(_onV2);
    // `cancel()` AVANT de réabonner : ce bloc existe sur DEUX chemins de
    // démarrage (start / startContinuous). Sans ça, un écran rouvert cumulait
    // les abonnements -- mesure 2026-08-01 : le même décrochage arrivait TROIS
    // fois en 5 ms, donc trois corrections enchaînées et l'ancre reculait de
    // trois crans (7 -> 6 -> 5 -> 4).
    _decrochageSub?.cancel();
    _decrochageSub = _verifier.decrochage.listen(_onDecrochageV2);
    // Forme fidèle à l'entraînement (PAS `strict`, qui fusionne des lettres
    // que le modèle a appris à distinguer — cf. normalizeTraining).
    final cible = state.words.map((w) => w.alignTarget).toList();
    // start() est le mode VERSET UNIQUE : jamais de session de
    // reference, cf. la doc de startControle/startTest -- ce mode n'est
    // atteint que via la lecture normale d'un verset.
    await _verifier.v2Activer(true, cible,
        mode: 'CTL', nonJugeables: _indicesNonJuges(state.words));
    await _verifier.start(cible, refMinFrames: _refMinFrames(state.words));
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Démarre une récitation continue (plusieurs versets/une sourate entière),
  /// segmentée automatiquement par détection de silence (VAD). [arabicText]
  /// doit couvrir tout le fragment à réciter (setup() l'a déjà découpé en mots).
  /// Segments figés de la session : clip audio + plage de mots couverte.
  /// Renseigné UNIQUEMENT en session de référence, c'est la matière première de
  /// [ReferenceTimingExtractor] -- et c'est la correspondance que l'app connaît
  /// en direct alors qu'une analyse hors ligne devrait la deviner.
  final List<ReferenceSegment> _referenceSegments = [];
  List<ReferenceSegment> get referenceSegments =>
      List.unmodifiable(_referenceSegments);

  /// Vrai pendant une session de RÉFÉRENCE. Deux effets : l'audio est capturé
  /// même diagnostic éteint (c'est la matière première de la mesure de durées,
  /// pas de la trace -- décision utilisateur 2026-07-27), et les segments figés
  /// sont collectés ci-dessus.
  bool _referenceSession = false;

  /// Relevé COMPLET des réglages, en tête de chaque session (demande
  /// utilisateur 2026-07-28 : « je veux à chaque début de session le log de
  /// tous les paramètres de l'app, pour savoir ce qu'on teste »).
  ///
  /// CE QUE ÇA A COÛTÉ DE NE PAS L'AVOIR. Une journée entière d'analyses a été
  /// menée sur des logs `[GOP]` en croyant lire ce qui s'affichait à l'écran.
  /// En réalité `useGopScoring` était à false : le gop tournait en parallèle et
  /// se journalisait sans rien peindre, c'est le texte-diff qui pilotait
  /// l'affichage — et lui restait bloqué sur `بِسْمِ ٱللَّهِ` (défaut déjà
  /// documenté dans JudgementOptions). Le log annonçait 10 mots `correct`,
  /// l'écran n'en montrait aucun, et rien dans le fichier ne permettait de
  /// savoir lequel des deux moteurs était aux commandes.
  ///
  /// La ligne QUI COMPTE est `moteur=` : elle dit qui peint. Les autres
  /// évitent d'attribuer à un correctif ce qui vient d'un réglage.
  void _logParametresSession(bool referenceSession) {
    final rules = _activeRules.isEmpty
        ? 'aucune'
        : '${_activeRules.length}(${_activeRules.map((r) => r.key).join(",")})';
    DiagnosticLog.log('PARAMS', '--- debut de session ---');
    DiagnosticLog.log(
        'PARAMS',
        'moteur=${_useGopScoring ? "GOP (alignement force)" : "TEXTE-DIFF"} '
        '<- CELUI QUI PEINT L\'ECRAN | gop journalise en parallele dans les deux cas');
    DiagnosticLog.log(
        'PARAMS',
        'session=${referenceSession ? "REFERENCE" : "NORMALE"} '
        'correction=${referenceSession ? "desactivee" : "active"} '
        'ancreSansBlocage=$referenceSession '
        'modeConfiant=$_confidentMode');
    DiagnosticLog.log(
        'PARAMS',
        'preset=${_preset.name} strictHarakat=$_strictHarakat '
        'tolereConfusables=$_tolerateConfusables regles=$rules');
    DiagnosticLog.log(
        'PARAMS',
        'seuils gop: correct=${_gopCorrect.toStringAsFixed(2)} '
        'unclear=${_gopUnclear.toStringAsFixed(2)} '
        'trouAlignement(free)=${_freeConfident.toStringAsFixed(2)}');
    DiagnosticLog.log(
        'PARAMS',
        'cible=${state.words.length} mots '
        'diagnostic=${DiagnosticLog.enabled} '
        'build=${DiagnosticLog.buildTag}');
    DiagnosticLog.log('PARAMS', '--- fin des parametres ---');
  }

  /// ── CLOISONNEMENT CONTRÔLE / TEST (2026-08-05, demande utilisateur) ──────
  ///
  /// « Je parle pas du V1, je parle entre récitation normale et récitation de
  /// référence, je veux qu'ils soient cloisonnés, dupliquer les fonctions pour
  /// que chacune tourne dans un cas, chacune aura ses tests, je ne veux pas de
  /// régression -- on part sur deux copies distinctes, après je te demanderai
  /// de fusionner ce qui reste identique. »
  ///
  /// [startContinuous] est REMPLACÉE par deux points d'entrée qui ne PARTAGENT
  /// plus de branche conditionnelle sur `referenceSession` : [startControle]
  /// (usage réel, seul chemin atteint par l'écran) et [startTest] (recette
  /// uniquement, atteint par `autoDemarrer`). Chacune peut désormais être
  /// modifiée sans risque de faire dévier l'autre -- c'est le sens même du
  /// cloisonnement demandé.
  ///
  /// ⚠️ CE QUI RESTE PARTAGÉ, ET POURQUOI CE N'EST PAS UN OUBLI. `_referenceSession`
  /// reste un champ interne lu plus loin (`_onAligned`, `_onV2`, la capture de
  /// clips) : dupliquer TOUT le fichier pour isoler ces quelques lectures
  /// aurait exigé de copier ~4000 lignes de logique de jugement -- le risque de
  /// régression que cette demande vise justement à éliminer. Cette première
  /// étape sépare le POINT D'ENTRÉE, le lieu où les deux modes divergent le
  /// plus et où une divergence de code a le moins de conséquences si elle est
  /// mal faite. La suite (isoler `_onAligned`/`_onV2` par mode) est un chantier
  /// à part, plus profond, non fait ici -- à cadrer séparément.
  Future<void> startControle() => _startInterne(referenceSession: false);

  /// Chemin RECETTE UNIQUEMENT (`autoDemarrer` dans l'écran karaoké). Ne jamais
  /// appeler depuis un geste utilisateur normal : ce mode ne corrige rien, cf.
  /// la doc de [_startInterne].
  Future<void> startTest() => _startInterne(referenceSession: true);

  Future<void> _startInterne({required bool referenceSession}) async {
    if (state.words.isEmpty || state.isActive) return;
    _referenceSession = referenceSession;
    // Marqueur de log CTL/REF (cf. DiagnosticLog.modeSession) : pose au plus
    // pres du debut reel de la session, avant toute ligne qui pourrait etre
    // ecrite pendant ce demarrage.
    DiagnosticLog.modeSession = referenceSession ? 'REF' : 'CTL';
    _referenceSegments.clear();
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
    _v2Sub = _verifier.v2Statuses.listen(_onV2);
    // `cancel()` AVANT de réabonner : ce bloc existe sur DEUX chemins de
    // démarrage (start / startContinuous). Sans ça, un écran rouvert cumulait
    // les abonnements -- mesure 2026-08-01 : le même décrochage arrivait TROIS
    // fois en 5 ms, donc trois corrections enchaînées et l'ancre reculait de
    // trois crans (7 -> 6 -> 5 -> 4).
    _decrochageSub?.cancel();
    _decrochageSub = _verifier.decrochage.listen(_onDecrochageV2);
    // ── Diagnostic : WAV + journal, ICI et pas dans un écran (2026-07-25) ──
    // Avant, la capture des WAV était activée par KaraokeRecitationScreen
    // uniquement. Conséquence mesurée le 2026-07-25 : deux tests de suite
    // lancés depuis un AUTRE écran ont produit un log complet mais AUCUN
    // audio (`capture de clips desactivee`), donc impossible de vérifier ce
    // que le modèle avait réellement entendu — exactement l'information qui
    // manquait pour conclure. La capture est une propriété de « une session de
    // récitation tourne », pas d'un écran : elle appartient donc ici, sur le
    // chemin que TOUS les écrans empruntent.
    // L'ancre ne doit jamais caler en session de REFERENCE : la correction y
    // est desactivee, donc le report d'un mot non place ne sera JAMAIS rattrape
    // (demande utilisateur : « l'ancre doit faire +1 en cas d'erreur, elle ne
    // doit pas s'arreter dans ce mode »).
    _logParametresSession(referenceSession);
    await _verifier.setNeverBlockAnchor(referenceSession);
    await _applyDiagnosticCapture();
    // Forme fidèle à l'entraînement — cible de l'alignement forcé GOP.
    // La v2 reçoit LA MÊME cible : sans cet appel elle ne s'active jamais et
    // la session mesure la v1 en croyant mesurer la v2 (constaté le
    // 2026-07-30 : 0 ligne [V2] dans une session étiquetée v2).
    // ── LA PHRASE DE FIN, EN QUEUE DE CIBLE (2026-08-14) ──────────────────
    //
    // Cf. `phraseFinRecitationProvider` pour le POURQUOI complet (le dernier
    // mot d'une sourate ne peut jamais obtenir sa 2e observation) et pour la
    // raison du défaut à `false`.
    //
    // Elle n'est ajoutée qu'à la cible de la CHAÎNE, jamais à `state.words` :
    // le texte affiché reste strictement coranique, et `_onV2` ignore déjà
    // tout verdict dont l'index dépasse `words.length`. Les indices sont en
    // plus déclarés non jugeables -- ceinture et bretelles.
    //
    // ⚠️ Ne vaut QUE parce que l'enchaînement s'arrête désormais à la fin de
    // la sourate (`_maybeExtendNextPage`, même jour) : tant que la cible
    // débordait sur les sourates suivantes, le dernier mot récité n'était pas
    // le dernier de la cible et cette phrase n'aurait servi à rien.
    final motsCoran = state.words.map((w) => w.alignTarget).toList();
    final cibleChaine = [...motsCoran, ..._motsPhraseFin];
    await _verifier.v2Activer(true, cibleChaine,
        mode: referenceSession ? 'REF' : 'CTL',
        nonJugeables: [
          ..._indicesNonJuges(state.words),
          for (var i = 0; i < _motsPhraseFin.length; i++) motsCoran.length + i,
        ]);
    await _verifier.start(
      cibleChaine,
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
    // L'AUDIO d'une session de référence est capturé même diagnostic éteint
    // (décision utilisateur 2026-07-27) : c'est la matière première dont
    // [ReferenceTimingExtractor] déduit les durées, pas de la trace de debug.
    // Sans ça la fonctionnalité n'existerait qu'en mode debug.
    if (!on && !_referenceSession) {
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

    // ── CE MODE TOURNE SUR LA v1, ET IL DOIT LE DIRE (corrigé 2026-08-06) ──
    //
    // DÉFAUT : « Suivre une prière » était SILENCIEUSEMENT MORT dès qu'une
    // récitation normale avait eu lieu dans la même exécution de l'app.
    //
    // Mécanisme, vérifié ligne à ligne :
    //   1. `startContinuous`/`start` appellent `v2Activer(true, cible)` ;
    //      côté natif, `v2Actif` et `v2Mots` sont des champs @Volatile du
    //      plugin qui SURVIVENT à la fin de la session (rien ne les remet à
    //      zéro à l'arrêt).
    //   2. `startPrayerFollow` n'appelait aucun `v2Activer` : il héritait donc
    //      de l'état laissé par la session précédente.
    //   3. Au premier bloc PCM, `FastConformerCtcPlugin` calcule
    //      `v1Coupee = v2Actif && v2Mots.isNotEmpty()` -> VRAI. Le
    //      `BufferedTranscriber` n'est alors ni instancié ni alimenté.
    //   4. Or ce mode vit ENTIÈREMENT sur la v1 : `_onStructured` (takbir,
    //      Al-Fatiha, rattrapage Shazam) et `_onAligned` (jugement). Il ne
    //      s'abonne pas à `v2Statuses` -- et il ne peut pas : la v2 exige une
    //      cible fixe, alors qu'ici la sourate se découvre en cours de route.
    //   5. Résultat : aucun texte reconnu ne remonte, le takbir n'est jamais
    //      détecté, Al-Fatiha jamais reconnue, Shazam jamais interrogé.
    //      L'écran reste en `standby` indéfiniment, sans la moindre erreur.
    //
    // LA CAUSE N'EST PAS « il manquait un appel » : c'est qu'une session
    // pouvait démarrer SANS DÉCLARER le moteur dont elle a besoin, et hériter
    // de celui d'avant. Les deux autres points d'entrée le déclaraient déjà ;
    // celui-ci était le seul trou. L'invariant est maintenant complet — tout
    // chemin qui ouvre une session dit quel moteur il veut — ce qui supprime
    // la classe entière « le mode X ne marche que si le mode Y n'a pas tourné
    // avant ».
    // ── LE SUIVI DE PRIERE PASSE SUR LA v2 (2026-08-07) ────────────────────
    //
    // POURQUOI LA v1 NE POUVAIT PAS FAIRE CE TRAVAIL. Le correctif de la
    // veille (déclarer le moteur au démarrage) a bien remis la v1 en marche —
    // vérifié sur device, `v1Coupee=false`, `bufferedExiste=true` — et a
    // révélé le vrai obstacle : sur 101 s d'audio (1 264 blocs PCM), la v1 a
    // produit `""` presque partout, avec pour seuls fragments `"يَقْ"`, `"ٱ"`,
    // `"ٱللَّهُ ٱلْعَـٰلَمِينَ"`, `"ٱلْعَـٰـٰ"`, `"ٱلْكُ"`. `_onStructured` n'a donc
    // jamais eu de texte à examiner : ZÉRO ligne de phase de prière sur toute
    // la session. Ce n'est pas un réglage à ajuster — la mesure de référence
    // du projet donne v1 10,10 % de mots non verts contre v2 2,03 % sur le
    // même flux.
    //
    // CE QUE LA v2 APPORTE ICI, ET QUE CE MODE DEMANDE EXACTEMENT.
    // Elle ne fait pas d'alignement forcé sur une cible imposée : elle décode
    // LIBREMENT puis LOCALISE. C'est visible dans ses propres traces --
    //     f=19 bande=inconnue entendu="قُلْ هُوَ ٱللَّهُ أَحَدٌ"
    // Ce texte-là est la matière de l'identification de sourate, et il est
    // produit sans qu'aucune cible existe. Il ne remontait simplement pas
    // jusqu'ici (calculé, journalisé, jamais transmis).
    //
    // MODE `PRIERE` (cf. ChaineRecitation.sautLibre), spécification
    // utilisateur du 2026-08-07 : « il ne faut pas utiliser le localiseur de
    // l'application de récitation qui refuse le saut. Là, les sauts seront
    // autorisés pour que l'aligneur suive — si des mots ne sont pas détectés,
    // ou plusieurs, ou il y a un problème de voix, qu'on arrive à suivre. »
    // Le trou n'est plus un motif de rejet ; il est signalé pour souffler le
    // passage, et la bande est gardée.
    //
    // CIBLE VIDE AU DÉPART : rien n'est encore connu, c'est l'identification
    // qui tranche. « Il va se déclencher au début, et peut-être plusieurs
    // fois, pour bien cibler la sourate. Mais après, c'est juste se localiser
    // parce qu'il ne va pas changer de sourate. »
    await _verifier.v2Activer(true, const [], mode: 'PRIERE');
    DiagnosticLog.log('Priere',
        'chaine v2 en mode PRIERE : decodage libre + localisation, saut '
        'autorise (jamais refuse), cible vide -- l\'identification de sourate '
        'la remplira. La v1 reste coupee : mesuree quasi muette sur ce mode '
        '(1264 blocs PCM, texte vide presque partout).');

    // ── LE MODE PRIERE N'ECRIVAIT AUCUN AUDIO (corrige 2026-08-07) ────────
    //
    // Demande utilisateur : « verifie selon ce que tu recois comme WAV brut ».
    // Il n'y en avait aucun : `[BufferedTranscriber] capture de clips
    // desactivee` sur toutes les sessions de priere, et le dernier dossier de
    // capture datait de la veille. Impossible, donc, de confronter un verdict
    // au son reellement recu -- alors que c'est l'instrument qui tranche
    // (skill `analyse-session-recitation` : « le log dit ce que la chaine a
    // CONCLU ; le balayage du brut dit ce que le modele RECOIT »).
    //
    // Ce jour meme, son absence m'a fait affirmer qu'un mot n'avait jamais ete
    // emis alors qu'il l'etait : sans le brut, il ne restait que le log et un
    // grep mal outille.
    //
    // Meme famille que le moteur oublie plus haut : `startContinuous` arme la
    // capture (`_applyDiagnosticCapture`), `startPrayerFollow` ne le faisait
    // pas. Troisieme trou du meme genre sur ce point d'entree.
    await _applyDiagnosticCapture();
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
    // Les verdicts de la v2 peignent l'écran, comme en récitation normale.
    _v2Sub = _verifier.v2Statuses.listen(_onV2);
    // Le décodage libre pilote le CYCLE : takbir, puis identification de la
    // sourate de la rak'ah. Il n'existe que sur ce chemin.
    _libreSub = _verifier.v2DecodageLibre.listen(_onDecodageLibrePriere);
    // Un passage sauté : on le souffle, on ne le juge pas, on n'attend rien.
    _sautSub = _verifier.v2SautPresume.listen(_onSautPresume);
    // ── LE DECROCHAGE N'ETAIT ECOUTE PAR PERSONNE (corrigé 2026-08-07) ────
    //
    // MESURE (session 18:01) : `[v2] DECROCHAGE` = 2 occurrences cote natif,
    // `[CTL][Decrochage]` = 0 cote Dart. Le signal partait, rien ne le
    // recevait -- donc la bascule « decrochage pendant la Fatiha = il est
    // passe a la sourate » (v129) ne pouvait JAMAIS s'executer, et
    // l'identification n'a jamais ete lancee alors que le recitant etait
    // manifestement ailleurs (`entendu="أَمْ تَحْسَبُ أَنَّ أَكْثَرَهُمْ
    // يَسْمَعُونَ"`, Al-Furqan 25:44).
    //
    // ⚠️ QUATRIEME OUBLI DU MEME POINT D'ENTREE dans la journee.
    // `startPrayerFollow` a successivement omis : de declarer son moteur, de
    // poser sa cible v2, d'armer sa capture audio, et maintenant d'ecouter le
    // decrochage. A chaque fois `startContinuous` le faisait et lui non, et a
    // chaque fois le defaut etait SILENCIEUX.
    //
    // Ce n'est plus une serie de coincidences, c'est un defaut de conception :
    // rien n'oblige un point d'entree a faire ce que fait le chemin
    // principal. Tant que les trois `start*` resteront trois listes
    // d'abonnements ecrites a la main, un cinquieme oubli viendra.
    _decrochageSub = _verifier.decrochage.listen(_onDecrochageV2);
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
    // ── LES LETTRES DOUBLEES FAISAIENT RATER LE TAKBIR (2026-08-07) ──────
    //
    // MESURE (session du 09:43:48) : le modele a ecrit `أَكْكْبَرَ بِسْمِ` --
    // un ك DOUBLE, et aucun `الله`. Normalise, `اككبر` ne vaut ni `اكبر` ni
    // ne s'y termine : le takbir n'a pas ete detecte, alors qu'il avait bien
    // ete prononce et grossierement entendu.
    // Verifie sur toute la session, diacritiques retirees des deux cotes :
    // `اكبر` apparait 4 fois, `الله اكبر` (les deux ensemble) JAMAIS.
    //
    // Meme famille que le mot de cloture d'Al-Fatiha juste au-dessus : un
    // detecteur qui exige le jeton EXACT face a un modele qui rogne un
    // article ou double une lettre. On replie donc les lettres consecutives
    // identiques avant de comparer -- `اككبر` devient `اكبر`. Ce repli ne
    // peut pas fabriquer de faux positif : aucun mot du Coran ne devient
    // `اكبر` par simple degemination.
    String degemine(String t) {
      final b = StringBuffer();
      for (var i = 0; i < t.length; i++) {
        if (i == 0 || t[i] != t[i - 1]) b.write(t[i]);
      }
      return b.toString();
    }
    bool porte(String t, String cible) {
      final d = degemine(t);
      return d == cible || d.endsWith(cible);
    }
    final hasAllah = tokens.any((t) => porte(t, _takbirWords[0]));
    final hasAkbar = tokens.any((t) => porte(t, _takbirWords[1]));
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
    // ── LE TAKBIR REND SA LIBERTE A LA v2 (2026-08-07) ────────────────────
    // Nouveau cycle : la sourate de la rak'ah precedente ne vaut plus rien.
    // On repasse cible VIDE pour que la chaine redecode librement -- c'est
    // ainsi que l'identification pourra travailler sur la rak'ah suivante.
    // Garde par `_dynamicTargetDiscovery` : ce chemin est aussi emprunte hors
    // priere, ou toucher a la cible v2 serait une regression.
    if (_dynamicTargetDiscovery) {
      unawaited(_verifier.v2Activer(true, const [], mode: 'PRIERE'));
    }
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
          } else if (probe.isNotEmpty) {
            // ── LE DETECTEUR EXACT NE SUFFIT PAS (mesure 2026-08-07) ──────
            //
            // `_looksLikeFatihaStart` exige la paire ADJACENTE exacte
            // `الحمد لله` (ou `بسم الله`). Session 17:48 : le recitant dit
            // bien Al-Fatiha -- la v1 transcrit `ٱلرَّحْمَـٰنِ مَلِكِ يَوْمِ
            // ٱلدِّينِ`, `إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينِ` -- mais
            // l'ouverture est sortie deformee : `ٱلْمِدِي` au lieu de
            // `ٱلْحَمْدُ`. La paire n'existe donc pas, la phase reste en
            // attente, et TOUT le mecanisme d'alignement force sur la Fatiha
            // (v128) ne s'installe jamais.
            //
            // QUATRIEME OCCURRENCE DU MEME DEFAUT dans la journee : article
            // rogne (`ضالين`), lettre doublee (`أككبر`), syllabe soudee
            // (`الضالينم`), et maintenant mot deforme. Un detecteur qui
            // reclame un jeton exact a un modele causal ne tient pas.
            //
            // On ajoute donc un FAISCEAU a cote du jeton : le localisateur
            // vote sur des PAIRES de mots (tolerantes aux trous), et s'il
            // designe la sourate 1 avec assez de votes, c'est qu'Al-Fatiha
            // est en cours. Meme plancher que l'identification de sourate --
            // c'est la meme question posee au meme moteur.
            //
            // Le detecteur exact reste en premier : quand il marche, il est
            // instantane et gratuit.
            unawaited(_verifierDebutFatihaParFaisceau(
                _lastWords(probe, _kRecentWindowWords)));
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
              // ── PLUS ON RECITE, PLUS IL DOIT TROUVER (2026-08-07) ────────
              //
              // Demande utilisateur, apres une session ou il a recite
              // longtemps sans que la sourate soit jamais identifiee : « j'ai
              // recite longtemps ; s'il n'arrive pas au debut, il doit
              // retenter ».
              //
              // LA CAUSE EST DEJA ECRITE DANS CE FICHIER, quelques lignes
              // plus haut : la requete ACCUMULE tout le texte sur depuis la
              // fin d'Al-Fatiha, et le score est une FRACTION (paires votant
              // pour le decalage gagnant / paires de la requete). Une requete
              // qui grossit DILUE donc un match par ailleurs excellent -- le
              // meme raisonnement avait deja fait abandonner l'approche « une
              // seule requete entiere » le 2026-07-19. Il a survecu ici.
              // Consequence mesurable : plus l'imam recite, MOINS on peut
              // l'identifier. Exactement l'inverse du comportement voulu.
              //
              // On BORNE donc la requete aux derniers mots des qu'elle
              // depasse la fenetre : elle porte alors le passage que l'imam
              // est en train de dire, son score ne se dilue plus, et chaque
              // nouveau bout de recitation est une NOUVELLE CHANCE de
              // trancher -- c'est cela, « retenter ». En dessous de la
              // fenetre, rien ne change : on soumet tout ce qu'on a.
              //
              // UNE SEULE requete, pas deux : `_targetLookupInFlight` fait
              // sortir immediatement tout appel concurrent, donc soumettre la
              // fenetre PUIS l'accumulation ne lancerait jamais la seconde --
              // elle aurait l'air d'exister sans jamais tourner.
              final mots = probe.split(RegExp(r'\s+'))
                  .where((t) => t.isNotEmpty).toList();
              final requete = mots.length > _kMotsFenetreIdentification
                  ? mots.sublist(mots.length - _kMotsFenetreIdentification)
                      .join(' ')
                  : probe;
              unawaited(_tryIdentifyTarget(requete));
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
  /// Verdicts de la chaîne v2 : des STATUTS déjà décidés, pas des scores.
  ///
  /// Aucun seuil n'est appliqué ici — la v2 porte sa propre couche de décision
  /// (deux preuves indépendantes, monotonie, aucun verdict sans preuve
  /// acoustique). Dart ne fait que peindre.
  ///
  /// `omis` n'est PAS une couleur : c'est « le récitateur est passé outre, et
  /// on peut le prouver ». Il est rendu comme `skipped`, jamais comme `error` —
  /// condamner un mot non prononcé serait un verdict sans preuve.
  void _onV2(List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})> changements) {
    var dernierJuge = -1;
    for (final c in changements) {
      DiagnosticLog.log('V2',
          'mot=${c.index} "${state.words.length > c.index ? state.words[c.index].display : "?"}" '
          '-> ${c.statut} | ${c.trace}');
    }
    if (!_v2PiloteAffichage) return;
    final words = [...state.words];
    var touche = false;
    final nouveauxEchecs = <int>[];
    final nouveauxNonVerts = <int>[];
    final nouveauxVerrouilles = <int>[];
    for (final c in changements) {
      if (c.index < 0 || c.index >= words.length) continue;
      final definitif = c.statut.startsWith('definitif:');
      final WordStatus? statut = switch (c.statut) {
        'definitif:vert' || 'provisoire:vert' => WordStatus.correct,
        'definitif:orange' || 'provisoire:orange' => WordStatus.unclear,
        'definitif:rouge' || 'provisoire:rouge' => WordStatus.error,
        'omis' => WordStatus.skipped,
        // ── « DIT, MAIS PAS À SA PLACE » (2026-08-11) ────────────────────────
        //
        // Défaut fermé : le récitateur disait les groupes d'un verset DANS LE
        // DÉSORDRE (« pour AB CD EF, j'ai dit AB EF CD ») et tout ressortait
        // vert. Côté Kotlin, `Statut.Deplace` établit que le mot a bien été
        // prononcé, mais que son audio arrive après celui d'un mot qui le suit
        // dans le texte, sans aucune lecture antérieure qui l'aurait mis à sa
        // place (cf. Decideur.OrdreTemporel pour le discriminant
        // inversion / répétition légitime).
        //
        // POURQUOI `unclear` (orange), ET PAS AUTRE CHOSE :
        //  - PAS `error` : rien ne dit que la PRONONCIATION est fautive, et la
        //    règle projet est explicite -- « un mot hors de sa place ne doit
        //    pas devenir rouge par le gop ». Rouge accuserait de la mauvaise
        //    faute.
        //  - PAS `skipped` : ce rendu est `underline = true` SANS AUCUN FOND,
        //    et un mot sans couleur a déjà été jugé pénible par l'utilisateur
        //    (défaut corrigé le 2026-08-04 sur `omis`). Il affirmerait en plus
        //    « vous n'avez pas dit ce mot », alors qu'il l'a dit.
        //  - PAS `correct` : c'est précisément le défaut qu'on ferme.
        //  Reste `unclear` : visible (orange), non accusatoire, et surtout
        //  TAPPABLE (`karaoke_recitation_screen._openWordHelp` n'ouvre la fiche
        //  que sur `error`/`unclear`) -- l'utilisateur peut donc réécouter ce
        //  qu'il a dit et comprendre, ce que `skipped` ne permet pas.
        //
        // ⚠️ LIMITE ASSUMÉE ET NOMMÉE : à l'écran, « pas à sa place » et
        // « articulation approximative » portent aujourd'hui la MÊME couleur.
        // Les distinguer demande un `WordStatus` de plus, donc une couleur et
        // un libellé traduits (3 langues) dans tous les écrans qui peignent un
        // mot -- c'est une décision d'IHM à arbitrer, pas à prendre au passage
        // dans un correctif de la chaîne. La distinction est en attendant
        // lisible dans le journal (`[V2] ... -> deplace`).
        'deplace' => WordStatus.unclear,
        _ => null, // `inconnu` : aucune preuve, donc aucune couleur
      };
      if (statut == null) continue;
      // ── LA BISMILLAH N'EST JAMAIS JUGÉE (2026-08-06) ─────────────────────
      //
      // Demande utilisateur répétée depuis longtemps, restée sans effet sur ce
      // chemin : « je veux qu'elle ne soit pas jugée et qu'elle soit
      // facilement mise en vert ».
      //
      // POURQUOI ELLE NE L'ÉTAIT PLUS. Les garde-fous `isBasmala` existent
      // bien (cf. `_onAligned`, plus bas) mais vivent tous dans la v1. La
      // chaîne v2 ne connaît PAS la Bismillah -- aucune occurrence côté
      // Kotlin -- donc depuis qu'elle pilote l'affichage, ces protections ont
      // cessé de s'appliquer sans que personne le décide. Même famille de
      // régression que le contrôle tajwid juste en dessous.
      //
      // MESURE (session v61 du 2026-08-06) : mots 0 `بِسْمِ` et 1 `ٱللَّهِ`
      // déclarés `omis` -- le verdict le plus grave -- avec gop -16,70 et
      // -18,71 et `entendu=""`. Or le projet a établi dès le 2026-07-20 que le
      // modèle est structurellement mal calibré sur ces 4 mots (récités ~44 %
      // plus vite dans le corpus, trois pistes d'entraînement, même échec) :
      // ce n'est pas une faute du récitant, et le condamner est faux.
      //
      // On force donc `correct`, jamais un verdict négatif. C'est une
      // EXEMPTION ASSUMÉE et bornée à 4 mots, pas une tolérance ajoutée au
      // jugement : ces mots ne sont pas mieux jugés, ils ne sont plus jugés
      // du tout -- décision utilisateur du 2026-07-20, reconduite ici.
      final estBasmala = words[c.index].isBasmala;
      // ── LA BISMILLAH SE VALIDE EN BLOC, ET SEULEMENT SI ON L'A DITE ──────
      //                                        (2026-08-14, décision utilisateur)
      //
      // « qu'elle ne se mette en vert que lorsqu'elle est attendue, et pour sa
      // validation, soit la plus tolérante : on la valide en entier ; ça règle
      // qu'elle soit déjà validée à l'avance. »
      //
      // Avant : `statut` était écrasé par `correct` dès qu'un verdict arrivait,
      // et l'écran la peignait en vert dès le démarrage de la capture -- donc
      // acquise avant d'avoir été prononcée.
      //
      // Maintenant, DEUX règles distinctes, à ne pas confondre :
      //  1. TOLÉRANCE MAXIMALE : un seul de ses mots entendu suffit à valider
      //     LE BLOC ENTIER. Le modèle est structurellement mal calibré sur ces
      //     4 mots (récités ~44 % plus vite dans le corpus, trois pistes
      //     d'entraînement, même échec -- décision 2026-07-20), donc exiger un
      //     verdict par mot reviendrait à la condamner sur un défaut connu du
      //     modèle. Le bloc est celui des `isBasmala` CONTIGUS autour du mot :
      //     une session enchaînée en contient un par sourate, et valider la
      //     Bismillah d'Al-Fil ne doit rien dire de celle de Quraysh.
      //  2. JAMAIS DE VERDICT NÉGATIF : sans preuve, elle reste `pending`
      //     (aucune couleur), jamais rouge ni orange. Elle n'entre toujours pas
      //     dans le score (`_compterMots` l'exclut déjà) : ne pas l'avoir dite
      //     ne coûte rien, l'avoir dite ne rapporte rien -- elle informe, elle
      //     ne juge pas.
      //
      // `c.heard` est la preuve acoustique : ce que le modèle a réellement
      // décodé sur les frames du mot. Vide = rien n'a été entendu là, et
      // `omis` est exclu explicitement (c'est le verdict « le récitateur est
      // passé outre », l'inverse d'une preuve).
      if (estBasmala) {
        if (c.statut != 'omis' && c.heard.trim().isNotEmpty) {
          var d = c.index, f = c.index;
          while (d > 0 && words[d - 1].isBasmala) d--;
          while (f + 1 < words.length && words[f + 1].isBasmala) f++;
          var bascule = 0;
          for (var j = d; j <= f; j++) {
            if (words[j].status == WordStatus.correct) continue;
            words[j] = words[j].copyWith(status: WordStatus.correct);
            bascule++;
          }
          if (bascule > 0) {
            touche = true;
            DiagnosticLog.log('V2bismillah',
                'entendue au mot ${c.index} ("${c.heard}") -> bloc $d..$f '
                'validé en entier ($bascule mot(s))');
          }
        }
        // Jamais de statut négatif sur la Bismillah, et rien d'autre à faire :
        // pas de verrouillage, pas d'échec à signaler, pas de correction.
        continue;
      }
      var statutBase = statut;
      // ── LE PRESET REDEVIENT EFFECTIF (2026-08-14) ────────────────────────
      //
      // Défaut trouvé en répondant à la question « strictHarakat, ce n'est pas
      // lié au mode enfant ? » : `_relaxJudged` porte LES DEUX indulgences
      // (harakat souples, lettres confusables) et vit dans `_onAligned`, donc
      // dans la v1. Depuis `_v2PiloteAffichage = true`, il ne s'exécute plus.
      // La chaîne v2 ne reçoit aucun réglage de preset (cf.
      // `FastConformerCtcPlugin`, où `Decideur` n'est construit qu'avec `k` et
      // `nonJugeables`), donc les TROIS presets jugeaient à l'identique : le
      // mode enfant était aussi sévère que le mode tajwid. Même famille de
      // régression que la Bismillah et le contrôle tajwid ci-dessus -- une
      // protection écrite en v1 qui cesse d'agir sans que personne le décide.
      //
      // Le relâchement est appliqué ICI, côté Dart, et pas porté en Kotlin :
      // il a besoin d'`ArabicNormalizer` (squelette, similarité, classes de
      // confusables), tout un pan de code déjà écrit et éprouvé. Le porter
      // aurait dupliqué la normalisation arabe dans un second langage.
      //
      // ⚠️ CE QU'IL NE FAUT SURTOUT PAS RELÂCHER, et pourquoi :
      //  - `omis` / `deplace` : ce ne sont pas des verdicts de PRONONCIATION.
      //    Relâcher `omis` validerait un mot que le récitateur n'a pas dit --
      //    exactement ce que l'app existe pour détecter. D'où le test sur
      //    `c.statut` brut, et non sur `statutBase` : après le switch, un
      //    `deplace` est devenu `unclear` et ne se distingue plus d'un orange
      //    de prononciation.
      //  - un mot sans texte entendu : `_relaxJudged` le dit lui-même (« un
      //    mot jamais prononcé reste rouge quel que soit le preset »). Sans
      //    audio, le squelette entendu est vide et la similarité n'a aucun
      //    sens.
      //
      // Placé AVANT le contrôle de tajwid (juste en dessous) : un mot relâché
      // redevient candidat à ce contrôle, et non l'inverse -- sans quoi le
      // preset enfant effacerait un verdict de tajwid. En mode enfant
      // `activeRules` est vide, donc ce contrôle y est de toute façon inerte.
      final relachable = !estBasmala &&
          (c.statut.endsWith(':orange') || c.statut.endsWith(':rouge')) &&
          c.heard.trim().isNotEmpty;
      if (relachable) {
        final avant = statutBase;
        statutBase = _relaxJudged(
            statutBase, words[c.index], ArabicNormalizer.normalize(c.heard));
        if (statutBase != avant) {
          DiagnosticLog.log('V2preset',
              'mot=${c.index} "${words[c.index].display}" ${avant.name} -> '
              '${statutBase.name} | strictHarakat=$_strictHarakat '
              'tolereConfusables=$_tolerateConfusables entendu="${c.heard}"');
        }
      }
      //
      // Ce contrôle existait depuis le 2026-07-20 (« le mode tajwid vérifie
      // enfin le tajwid ») mais vivait dans `_onAligned`, donc dans la v1. Il
      // a CESSÉ DE S'EXÉCUTER le jour où la v2 a pris l'affichage, sans que
      // personne le décide : la v1 ne décode plus (0 ligne [GOP] dans les
      // sessions du 2026-08-04), et le Decideur de la v2 ne connaît que le gop
      // et l'attestation. Constat utilisateur qui l'a révélé : une session en
      // preset tajwid, récitée SANS appliquer les règles, sortait 31 mots
      // verts sur 34 et aucune correction.
      //
      // CE QUI CHANGE PAR RAPPORT À LA v1, et pourquoi ce n'est pas un simple
      // portage. La v1 jugeait sur UNE passe, d'où son mécanisme de report
      // (`deferredTajwid`) quand une règle de jonction dépendait d'un voisin
      // pas encore arrivé. La v2 accumule les observations : on exige donc la
      // MÊME preuve que pour une lettre — le mot doit avoir été vu deux fois
      // ENTIÈREMENT DANS LA FENÊTRE (`tajwidFiable`, k=2 côté Kotlin), et les
      // règles détectées sont l'UNION de ces observations, pas la dernière.
      //
      // MESURE QUI L'IMPOSE (device 2026-07-23, déjà au dossier) : le même mot
      // `يَرَهُۥٓ`, sur le MÊME audio, sortait `emises=` vide sur une passe puis
      // `emises=madda_normal` sur la suivante selon le découpage du buffer. Une
      // règle vit sur une DURÉE ; coupée au bord d'une fenêtre elle disparaît.
      // Conclure sur une seule observation, c'est tirer à pile ou face — et
      // accuser le récitateur sur ce tirage.
      //
      // `unrealizedRulesFor` filtre déjà par les règles ACTIVES du preset :
      // en mode adulte aucune règle n'est active, donc ce bloc est inerte et
      // le jugement des lettres reste strictement inchangé (décision
      // utilisateur 2026-07-20 : « en mode adulte, ne pas faire l'idgham ou la
      // qalqala, ça ne fait pas une erreur ; avec mode tajweed, oui »).
      // `statutBase` et non `statut` : la Bismillah est déjà forcée à
      // `correct` plus haut, et le contrôle tajwid ci-dessous ne doit pas la
      // redégrader (elle n'est PAS jugée, tajwid compris).
      var statutFinal = statutBase;
      // Log SYSTÉMATIQUE attendu/détecté (2026-08-16, demande utilisateur) --
      // distinct de `V2tajwid` ci-dessous, qui n'écrit qu'en cas d'écart. Sans
      // cette ligne, un mot dont toutes les règles sont correctement
      // détectées ne laisse AUCUNE trace : impossible de savoir, log en main,
      // si le contrôle a seulement jamais tourné (`tajwidFiable=false`) ou
      // s'il a tourné et n'a rien trouvé à redire. `attendues` filtre déjà par
      // `_activeRules` (mêmes règles que `unrealizedRulesFor`) -- ne logue
      // rien pour un mot que le preset ne juge de toute façon pas.
      final attendues = c.index >= 0 && c.index < words.length
          ? words[c.index]
              .expectedRules
              .where(_activeRules.contains)
              .toList()
          : const <TajwidRule>[];
      if (attendues.isNotEmpty) {
        DiagnosticLog.log('V2tajwidDetail',
            'mot=${c.index} "${c.index < words.length ? words[c.index].display : "?"}" '
            'statut=${statutBase.name} tajwidFiable=${c.tajwidFiable} '
            'attendues=${attendues.map((r) => r.key).join(",")} '
            'detectees=${c.detectedRules.map((r) => r.key).join(",")}');
      }
      if (!estBasmala && statutBase == WordStatus.correct && c.tajwidFiable) {
        final manquantes = unrealizedRulesFor(c.index, c.detectedRules);
        if (manquantes.isNotEmpty) {
          statutFinal = WordStatus.unclear;
          DiagnosticLog.log('V2tajwid',
              'mot=${c.index} règle(s) ATTENDUE(S) et NON DÉTECTÉE(S) : '
              '${manquantes.map((r) => r.key).join(",")} '
              '| détectées=${c.detectedRules.map((r) => r.key).join(",")}');
        }
      }
      // ── LE TAJWID NE COMPTE JAMAIS COMME UN ÉCHEC (2026-08-16, demande
      // utilisateur) ────────────────────────────────────────────────────────
      //
      // « on va pas contrôler tajwid deux fois [...] adulte et tajwid c'est
      // pareil sans impact du tajwid, tajwid vient en fin pour trancher » --
      // le jugement de PRONONCIATION (lettres/harakat, `statutBase`) doit
      // être identique entre les presets ; le tajwid n'intervient qu'APRÈS,
      // pour la COULEUR affichée (`statutFinal`), jamais pour compter comme
      // un échec.
      //
      // BUG TROUVÉ PAR L'UTILISATEUR : `_judge` recevait `statutFinal` à la
      // fois pour la couleur ET pour `isNegative` (qui alimente `newErrors`
      // -> `wordFailed` -> le souffleur -> `_motsOublies`). Un mot PARFAITEMENT
      // récité (statutBase=correct) mais dégradé à `unclear` par le seul
      // manque d'une règle tajwid comptait donc comme un demi-échec au même
      // titre qu'une vraie faute de prononciation -- deux mots ainsi dégradés
      // de suite déclenchaient le souffleur et marquaient "oublié" un
      // récitateur qui n'avait RIEN oublié. Mesuré en direct (2026-08-16,
      // session propre, app relancée) : mots 4 et 16 marqués oubliés alors
      // que leur seul défaut était une règle de tajwid manquante.
      final degradeParTajwidSeul =
          statutBase == WordStatus.correct && statutFinal == WordStatus.unclear;
      // ── `omis` NE VERROUILLE PLUS (2026-08-04) ──────────────────────────
      //
      // DEFAUT CONSTATE PAR L'UTILISATEUR, ecran a l'appui : des mots
      // s'affichaient SANS AUCUNE COULEUR (rendu de `WordStatus.skipped` :
      // `underline = true`, aucun fond) alors que la v2 les avait finalement
      // juges VERTS. Verifie dans le log de la session : huit mots suivent ce
      // trajet, par exemple
      //     mot=76 `إِلَّآ`  : omis -> provisoire:vert -> definitif:vert
      //     mot=18 `بِمَآ`   : omis -> provisoire:vert -> definitif:vert
      //     mot=17 `يُؤْمِنُونَ`: omis -> definitif:vert
      //
      // MECANISME : `omis` appelait `_judge(lock: true)`, donc le mot devenait
      // `skipped` ET verrouille. La correction que la v2 emettait deux
      // fenetres plus tard tombait alors sur `if (words[i].locked) return;` et
      // etait jetee EN SILENCE. La chaine se corrigeait, l'ecran ne l'
      // apprenait jamais -- et l'app continuait d'afficher une ACCUSATION
      // (« tu n'as pas dit ce mot ») que sa propre couche de decision avait
      // dementie. C'est le contraire du socle : dire vrai.
      //
      // POURQUOI NE PAS VERROUILLER EST LE BON CORRECTIF, et non un
      // assouplissement : `Statut.Omis` n'est JAMAIS memorise dans
      // `Decideur.definitifs[]` -- seules les COULEURS y entrent (VERT,
      // ORANGE, ROUGE). La v2 le recalcule donc a chaque fenetre : il est
      // revisable PAR CONCEPTION. C'etait Dart qui le figeait, contre le
      // dessin de la couche qui le produit. Les statuts reellement finaux sont
      // ceux prefixes `definitif:`, et eux continuent de verrouiller.
      //
      // ── LA CORRECTION NE PARTAIT JAMAIS EN v2 (corrigé 2026-08-06) ─────
      //
      // Ce commentaire disait : « aucun risque de déclencher la correction
      // automatique au passage [...] et `_onV2` n'en passe pas ». L'intention
      // était juste — ne pas corriger sur un négatif PROVISOIRE — mais l'effet
      // réel était total : `newErrors` n'étant jamais fourni, `_judge` ne
      // remplissait rien, et `_wordFailedCtrl` n'était alimenté QUE par
      // `_onAligned`, c'est-à-dire par la chaîne v1 -- morte depuis que la v2
      // pilote l'écran (instrumentation `[V1]` : 1 ligne sur toute une
      // session).
      //
      // MESURE (session utilisateur du 2026-08-06, An-Nisâ' 1-4, v85,
      // `correction=active`) : DEUX mots `definitif:rouge` et
      // `wordFailed` = 0 occurrence. La correction automatique était donc
      // structurellement impossible, et tous les réglages de ses conditions
      // portaient sur une branche que rien n'atteignait.
      //
      // Le garde-fou reste entier : `_judge` n'ajoute à `newErrors` que si
      // `lock && isNegative` -- un rouge PROVISOIRE ne déclenche toujours
      // rien, ce qui était bien l'intention d'origine.
      final etaitVerrouille = words[c.index].locked;
      _judge(words, c.index, statutFinal, lock: definitif,
          // `null` quand la seule cause de `unclear` est le tajwid : ce mot
          // ne doit jamais alimenter `newErrors` (-> wordFailed -> souffleur
          // -> `_motsOublies`), cf. le commentaire "LE TAJWID NE COMPTE
          // JAMAIS COMME UN ÉCHEC" ci-dessus.
          newErrors: degradeParTajwidSeul ? null : nouveauxEchecs,
          heard: c.heard.isEmpty ? null : c.heard,
          detectedRules: c.detectedRules.isEmpty ? null : c.detectedRules);
      // Instrumenté le 2026-08-16 (`V2tajwidWrite`, retiré depuis) pour savoir
      // ce que `_judge` écrivait réellement quand le violet n'apparaissait pas.
      // Résultat : l'écriture était CORRECTE (`status=unclear locked=true` avec
      // les bonnes règles) -- le défaut était en aval, à l'affichage. Inutile
      // de ré-instrumenter ici, cette couche est innocentée.
      // Archive du Coach : TOUT verdict definitif non vert, y compris ceux que
      // la correction automatique ne declenchera pas (cf. `wordLockedNonGreen`).
      // `etaitVerrouille` evite le doublon quand la v2 reconfirme un mot deja
      // fige ; on n'archive que la PREMIERE fois.
      if (definitif && !etaitVerrouille && words[c.index].locked) {
        nouveauxVerrouilles.add(c.index);
        if (statutFinal != WordStatus.correct) {
          nouveauxNonVerts.add(c.index);
        }
      }
      // ── FIN D'AL-FATIHA LUE A L'ANCRE (2026-08-07) ────────────────────
      //
      // Maintenant que la v2 recoit Al-Fatiha comme cible (cf.
      // `_beginFatihaPhase`), sa fin se constate par la POSITION : le dernier
      // mot vient d'etre juge. C'est un signal de position, pas de vocabulaire
      // -- il ne peut pas etre mis en echec par un article rogne ou une
      // syllabe soudee, les trois defauts rencontres aujourd'hui.
      //
      // Le detecteur lexical (`_looksLikeFatihaEnd`) et le repli Shazam
      // RESTENT EN PLACE : ils couvrent le cas ou la v2 ne verrouille pas le
      // dernier mot (recitant qui enchaine sans pause, fenetre tronquee). Ce
      // chemin-ci est le plus direct, pas le seul.
      // ── ON N'EXIGE PAS LE DERNIER MOT (2026-08-07) ────────────────────
      //
      // Demande utilisateur : « il faut faire un mecanisme de relancer Shazam
      // une fois juste apres la fin ; la on est presque sur la fin, meme si
      // ad-dallin n'est pas reconnu, on est vers la fin ».
      //
      // MESURE QUI L'IMPOSE (session 17:26) : les mots 22 a 27 sont tous
      // `definitif:vert` avec des gop a 0,00 -- la Fatiha est manifestement
      // finie. Le mot 28 `ٱلضَّآلِّينَ`, lui, n'a JAMAIS ete verrouille : il
      // tombe systematiquement au BORD de la bande (`f=5 bande=22..28
      // interieurs=5/7`), et le Decideur ne fige que sur une observation
      // interieure. Attendre ce mot precis, c'est attendre celui qui a le
      // moins de chances d'arriver.
      //
      // Une TOLERANCE d'un mot suffit : atteindre l'avant-dernier prouve
      // qu'on est a la fin. C'est encore un signal de POSITION, jamais de
      // vocabulaire -- la lecon du jour.
      if (_dynamicTargetDiscovery &&
          state.prayerPhase == PrayerPhase.fatiha &&
          definitif &&
          c.index >= words.length - 1 - _kToleranceFinFatiha) {
        DiagnosticLog.log('Priere',
            'fin d\'Al-Fatiha lue A L\'ANCRE : mot ${c.index} juge sur '
            '${words.length} -- on ne reclame pas le dernier, bascule vers '
            'l\'identification');
        _beginTargetDetection();
      }
      if (c.index > dernierJuge) dernierJuge = c.index;
      touche = true;
    }
    if (touche) {
      // AVANCER LE MOT COURANT — sans ça l'écran ne défile plus.
      //
      // RÉGRESSION TROUVÉE PAR L'UTILISATEUR le 2026-07-31 : « l'affichage se
      // bloque au verset 18, normalement c'est dynamique pour recharger la
      // suite ». Elle ne datait PAS du correctif du jour : le défilement suit
      // le mot marqué `WordStatus.current`
      // (karaoke_recitation_screen.dart, `indexWhere(... == current)`), or
      // c'est la v1 qui le posait sur son ancre. Depuis que la v1 est coupée
      // quand la v2 pilote (cd131a9), plus personne ne le posait : l'écran
      // restait figé là où la v1 s'était arrêtée.
      //
      // MÊME FAMILLE QUE LES CLIPS AUDIO PERDUS : couper la v1 a emporté
      // plusieurs choses qu'elle portait SEULE, et dont l'inventaire n'avait
      // pas été fait. Le symptôme ne ressemble pas à une erreur — rien ne
      // plante, l'écran cesse simplement de suivre.
      // PREMIER CORRECTIF, INSUFFISANT (2026-07-31) : il ne posait `current`
      // que si le mot `dernierJuge + 1` etait encore `pending`. Or la v2 juge
      // par BANDES et RECULE quand le recitateur repete — ce mot est donc
      // tres souvent deja juge. Aucun mot ne recevait alors `current`,
      // `indexWhere` rendait -1, et l'ecran restait fige exactement comme
      // avant. Signale par l'utilisateur : « ta correction de suivi d'ecran ne
      // marche pas, toujours bloque ».
      // On cherche donc le premier mot ENCORE NON JUGE a partir de la, ce qui
      // est la definition de « la ou en est le recitateur ». Et si tout est
      // juge jusqu'au bout, on se rabat sur le dernier mot juge : l'ecran doit
      // suivre meme en fin de sourate.
      var cible = -1;
      for (var i = dernierJuge + 1; i < words.length; i++) {
        if (words[i].status == WordStatus.pending) { cible = i; break; }
      }
      // Pas de repli sur le dernier mot juge : un mot qui porte deja un
      // verdict ne peut pas devenir `current` sans ecraser sa couleur. En fin
      // de sourate il n'y a donc plus rien a suivre, et c'est correct.
      if (cible >= 0) {
        for (var i = 0; i < words.length; i++) {
          if (i != cible && words[i].status == WordStatus.current) {
            words[i] = words[i].copyWith(status: WordStatus.pending);
          }
        }
        // `current` n'ecrase JAMAIS un verdict : un mot vert/rouge/orange garde
        // sa couleur, il est seulement suivi par le defilement.
        if (words[cible].status == WordStatus.pending) {
          words[cible] = words[cible].copyWith(status: WordStatus.current);
        }
      }
      state = state.copyWith(words: words);
      // Emis APRES la mise a jour de l'etat : l'ecran karaoke lit
      // `recitationProvider` dans `_onWordFailed`, il doit y voir le mot
      // deja verrouille.
      for (final i in nouveauxEchecs) _wordFailedCtrl.add(i);
      for (final i in nouveauxNonVerts) _nonVertCtrl.add(i);
      for (final i in nouveauxVerrouilles) _wordLockedCtrl.add(i);
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

  /// Vide les traces fines (Dart + natif) dans le fichier de log — UNIQUEMENT
  /// en fin de session : c'est une écriture volumineuse, et la faire pendant la
  /// récitation fausserait la latence qu'on cherche justement à mesurer (cf.
  /// DiagnosticLog.trace).
  /// Vidage explicite depuis l'UI, sur la **pause manuelle**.
  ///
  /// Pourquoi il a fallu l'ajouter (2026-07-27) : une session s'est terminée
  /// sur `pauseCapture()` et pas sur `stop()`, donc [_flushTraces] n'a jamais
  /// tourné. Or c'est exactement cette session qui montrait deux trous de
  /// 11,2 s sans aucune passe de transcription -- et la seule trace capable de
  /// dire ce qui tenait la chaîne (`feed … busy=…`, une ligne par bloc PCM)
  /// est restée en mémoire, perdue à la fermeture. Le log ne permettait plus
  /// que des hypothèses.
  ///
  /// La pause manuelle est le geste par lequel un test se termine réellement :
  /// c'est là qu'il faut écrire, pas seulement à l'arrêt. Ne pas brancher ça
  /// sur les pauses techniques (souffleur, lecture d'un mot) : elles sont
  /// fréquentes et sur un chemin sensible à la latence.
  Future<void> flushTraces() => _flushTraces();

  Future<void> _flushTraces() async {
    final n = DiagnosticLog.flushTrace();
    final m = await _verifier.flushNativeTrace();
    if (n > 0 || m > 0) {
      DiagnosticLog.log('Trace', 'vidée : $n lignes Dart + $m lignes natives');
    }
  }

  void _cleanup() {
    // Retire le marqueur CTL/REF (cf. DiagnosticLog.modeSession) : ICI, pas à
    // chaque site de stop, parce que TOUS les chemins d'arrêt (bouton, fin de
    // file, dispose) passent par `_cleanup` -- un retrait dupliqué à chaque
    // site serait le même risque d'oubli que le marqueur existe pour éviter.
    DiagnosticLog.modeSession = null;
    _tokenSub?.cancel();
    _levelSub?.cancel();
    _rawSub?.cancel();
    _structSub?.cancel();
    _pendingSub?.cancel();
    _v2Sub?.cancel();
    _libreSub?.cancel();
    _sautSub?.cancel();
    _decrochageSub?.cancel();
    // Mode continu : ce chemin ne passe PAS par stop(), il lui faut son propre
    // flush (idempotent, no-op si rien n'a change).
    unawaited(WordDurationStore.instance.flush());
    unawaited(_flushTraces());
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
    _v2Sub?.cancel();
    _libreSub?.cancel();
    _sautSub?.cancel();
    _decrochageSub?.cancel();
      // Ecriture GROUPEE des durees apprises pendant la session : `record()`
      // est appele sur chaque mot valide (des dizaines par session), on ne veut
      // pas un acces disque par mot. Sans effet si rien n'a change.
      unawaited(WordDurationStore.instance.flush());
      unawaited(_flushTraces());
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

    // FERMER LA CHAÎNE v2 (2026-08-06) : dernière analyse de la queue d'audio,
    // hors grille. La grille de fenêtres cesse d'avancer dès que le récitateur
    // se tait, donc SANS cet appel les derniers mots prononcés restent
    // `provisoire` -- donc NON VERTS -- à jamais. Mesuré : mot `تَنْهَرْ` à
    // gop 0,00 et texte exact, resté non vert parce que la session s'est
    // arrêtée juste après lui. `ChaineRecitation.terminer()` existait depuis
    // le début pour ça, mais n'était appelé que par le banc WAV.
    //
    // Placé APRÈS `stop()` : la queue doit être complète avant d'être
    // analysée. ⚠️ Ces statuts ne remontent PAS par le chemin habituel (la
    // réponse de `feed()`, qui ne sera plus appelée) : c'est
    // `FastConformerCtcVerifier.v2Terminer` qui les réinjecte lui-même dans
    // le flux, pour que `_onV2` les applique comme les autres.
    await _verifier.v2Terminer();

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
    _v2Sub?.cancel();
    _libreSub?.cancel();
    _sautSub?.cancel();
    _decrochageSub?.cancel();
    _detectingTargetFallbackTimer?.cancel();
    _wordFailedCtrl.close();
    _nonVertCtrl.close();
    _wordLockedCtrl.close();
    _sautPresumeCtrl.close();
    _decrochageCtrl.close();

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
