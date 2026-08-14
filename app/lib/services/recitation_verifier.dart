import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'diagnostic_log.dart';
import 'fastconformer_verifier.dart';
import 'streaming_wav_capture.dart';
import '../models/judgement_options.dart' show TajwidRule;

// ── Public types ─────────────────────────────────────────────────────────────

class RecognizedToken {
  final String text;
  final double confidence;
  const RecognizedToken(this.text, {this.confidence = 1.0});
}

/// Normalisation arabe tolérante aux harakat / variantes orthographiques.
class ArabicNormalizer {
  static final _harakat = RegExp(r'[ً-ٰٟؐ-ؚۖ-ۭـ]');

  static String _collapseVariants(String t) {
    // Variantes orthographiques du script Uthmani — MÊMES mappings que la
    // normalisation du corpus d'entraînement (prepare_nemo_data.normalize_text,
    // 2026-07-05) : le modèle écrit "الرَّحْمَانِ" (alif normal) là où le texte
    // de l'app contient "ٱلرَّحْمَـٰنِ" (wasla + dagger alif + tatweel). Sans ces
    // mappings côté comparaison, le MÊME mot bien récité ressort orange/rouge.
    t = t
        .replaceAll('ٱ', 'ا')  // alif wasla -> alif
        // Rasm ancien à "waw muet" (وٰ) porteur du petit alif suscrit —
        // audit du Coran entier 2026-07-10 (184 occurrences, 30 formes :
        // الصلاة، الحياة، الزكاة، الربا، الغداة، النجاة، مشكاة، مناة...).
        // Le waw ne se prononce pas (seul le petit alif porte le son "aa"),
        // mais rester "و" + alif normal (via la règle suivante seule)
        // laisse une lettre en trop face à toute transcription standard
        // ("صلواه" au lieu de "صلاه") -- écart mesuré de 0.80 à 0.875 de
        // similarité squelette, jamais "correct", parfois carrément rouge,
        // même prononcé parfaitement. Il faut retirer le waw ET le petit
        // alif ensemble (pas juste convertir ce dernier), d'où cette règle
        // AVANT la conversion générique du dagger alif ci-dessous.
        .replaceAll('وٰ', 'ا')
        .replaceAll('ٰ', 'ا')  // dagger alif (voyelle longue suscrite) -> alif
        .replaceAll('ۥ', 'و')  // petit waw -> waw
        .replaceAll('ۦ', 'ي')  // petit yeh -> yeh
        .replaceAll('ٔ', 'ء')  // hamza suscrite combinante -> hamza
        .replaceAll('ٓ', '')   // maddah combinante (portée par la lettre de base)
        .replaceAll('ـ', '')   // tatweel (allongement purement visuel)
        .replaceAll('۞', '')   // marque de rub el hizb
        .replaceAll('۩', '')   // marque de sajda
        // Marques d'annotation de lecture (waqf/sukun/imala/iqlab) — vérifiées
        // ABSENTES du vocabulaire du modèle une par une (0/1024 tokens,
        // 2026-07-09, cf. benchmark scratchpad check_vocab_gap.py sur un
        // échantillon de 1546 versets) : le modèle ne peut STRUCTURELLEMENT
        // jamais les produire, quelle que soit la prononciation. Sans ce
        // strip, tout mot portant l'une de ces marques reste bloqué en
        // "unclear" indéfiniment en mode strict (bug réel constaté sur
        // "لَيُنۢبَذَنَّ", sourate Al-Humazah -- ۢ était le seul déjà traité).
        .replaceAll('ۢ', '')   // petit meem suscrit (iqlab)
        .replaceAll('ۖ', '')   // waqf "صلى" (petite ligature sad-lam-alef maksura)
        .replaceAll('ۗ', '')   // waqf "قلى" (petite ligature qaf-lam-alef maksura)
        .replaceAll('ۘ', '')   // waqf "م" (arrêt obligatoire)
        .replaceAll('ۙ', '')   // waqf "لا" (pas d'arrêt)
        .replaceAll('ۚ', '')   // waqf "ج" (arrêt permis)
        .replaceAll('ۛ', '')   // waqf (l'un des deux/trois points d'arrêt optionnels)
        .replaceAll('ۜ', '')   // waqf "س"/saktah (pause brève sans reprendre son souffle)
        .replaceAll('۟', '')   // sukun (variante rond)
        .replaceAll('۠', '')   // sukun (variante rectangulaire)
        .replaceAll('ۧ', '')   // imalah (indication de nuance vocalique)
        .replaceAll('ۭ', '');  // petit meem souscrit (ikhfa/iqlab, variante basse)
    t = t
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
    t = t.replaceAll(RegExp(r'[^؀-ۿ\s]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalisation "squelette" (sans harakat) — tolérante au bruit ASR,
  /// utilisée uniquement pour ALIGNER le mot reconnu sur sa position dans
  /// le verset (pas pour juger si la prononciation est correcte).
  /// _collapseVariants d'ABORD : le dagger alif (ٰ) doit devenir un alif
  /// AVANT le retrait des harakat, sinon il est supprimé comme diacritique et
  /// "رحمٰن" (attendu) ne matche plus "رحمان" (sortie modèle).
  static String normalize(String input) {
    return _collapseVariants(input).replaceAll(_harakat, '');
  }

  /// Normalisation stricte (garde les harakat) — utilisée pour juger si le
  /// mot reconnu est réellement correct. Une voyelle courte différente
  /// (ex: رَبِّ vs رَبُّ) doit compter comme une erreur, pas un match.
  static String normalizeStrict(String input) {
    return _collapseVariants(input);
  }

  /// Normalisation "fidèle à l'entraînement" — DOIT matcher EXACTEMENT la
  /// normalisation du texte réellement vu par le modèle CTC actuellement
  /// déployé (ici epoch09, tokenizer tajweed_bpe_v1 -- préserve wasla/
  /// dagger-alif/sajda/waqf comme tokens distincts, contrairement à pcd).
  /// Seul le rub-el-hizb (aucune valeur phonétique) et le BOM sont retirés.
  ///
  /// Canonicalise aussi l'ordre harakat+shadda -> shadda+harakat (ordre appris
  /// à l'entraînement, vérifié 100% shadda-premier sur les manifests réels,
  /// 2026-07-16) : "لَّ" peut s'écrire shadda(0651)+voyelle OU voyelle+shadda --
  /// visuellement identiques, chaînes différentes, échec de lookup silencieux
  /// sinon.
  static String normalizeTraining(String input) {
    var t = input;
    t = t.replaceAll('۞', '');    // rub el hizb -> supprime (aucune valeur phonetique)
    t = t.replaceAll('﻿', '');    // BOM eventuel
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    // Canonicalise l'ordre harakat+shadda -> shadda+harakat :
    // une harakat courte (fathatan/dammatan/kasratan/fatha/damma/kasra/sukun
    // -- PAS le shadda U+0651 lui-même) suivie du shadda devient shadda+harakat.
    t = t.replaceAllMapped(
        RegExp('[ًٌٍَُِْ]' 'ّ'),
        (m) => 'ّ' '${m[0]![0]}');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Découpe le texte coranique attendu (`text_uthmani`) en mots récitables,
  /// en filtrant les signes d'annotation isolés par des espaces (marques de
  /// waqf comme ۚ ۖ ۗ...) qui ne sont PAS de vrais mots à prononcer. Bug réel
  /// constaté 2026-07-06 (sourate 110, verset 3) : un tel signe, séparé par
  /// un espace dans `text_uthmani` mais COLLÉ au mot précédent dans
  /// `text_uthmani_tajweed`, désynchronisait le nombre de mots entre les
  /// deux représentations (décalant tout l'affichage tajwid à partir de ce
  /// point, jusqu'à faire apparaître le dernier mot en double) ET créait un
  /// "mot" fantôme dans la liste à réciter : `normalize("ۚ")` est vide (ce
  /// n'est que harakat/marques), donc `similarity()` renvoyait TOUJOURS 0
  /// contre n'importe quel mot reconnu -> échec automatique dès que la
  /// récitation atteignait ce point. À utiliser PARTOUT où `text_uthmani`
  /// est découpé en mots (jamais un `.split` direct), pour que la liste de
  /// mots à réciter reste alignée avec `tajweedSpansPerWord` (qui, lui,
  /// fusionne déjà naturellement ces marques au mot précédent).
  static List<String> splitExpectedWords(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && normalize(w).isNotEmpty)
      .toList();

  static double similarity(String a, String b) {
    a = normalize(a);
    b = normalize(b);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final d = _levenshtein(a, b);
    return 1 - d / max(a.length, b.length);
  }

  /// Compare deux mots normalisés (strict) en tolérant un alef initial manquant
  /// côté reconnu. Rustine TEMPORAIRE : le checkpoint FastConformer actuellement
  /// déployé a été entraîné avant la correction du vocabulaire BPE (alef wasla
  /// "ٱ" absent des 1024 tokens, cf. SKILL.md 2026-07-05) — il transcrit "<unk>"
  /// à la place de l'alef de "ال", que `_collapseVariants` efface entièrement
  /// (hors bloc Unicode arabe), faisant "manquer" une lettre côté reconnu même
  /// quand la prononciation était correcte. À retirer une fois le modèle
  /// ré-entraîné avec le texte normalisé déployé sur le téléphone.
  static bool matchesTolerant(String recognizedStrict, String expectedStrict) {
    if (recognizedStrict == expectedStrict) return true;
    const alefLike = ['ا', 'ٱ', 'أ', 'إ', 'آ'];
    if (alefLike.contains(expectedStrict.isEmpty ? '' : expectedStrict[0]) &&
        expectedStrict.substring(1) == recognizedStrict) {
      return true;
    }
    // Waqf (pause) : la voyelle courte finale tombe naturellement quand le
    // récitant marque un arrêt (fin de verset ou simple respiration) --
    // constat réel 2026-07-10 (sourate 106, "وَالصَّيْفِ" récité en fin de verset
    // ressort "وَالصَّيْف" : squelette identique, seule la harakat finale est
    // absente). Le texte de référence porte toujours la forme "connectée"
    // (wasl) ; une lecture en pause qui abandonne SEULEMENT sa toute
    // dernière harakat doit compter comme correcte, pas "unclear".
    if (expectedStrict.isNotEmpty &&
        _harakat.hasMatch(expectedStrict[expectedStrict.length - 1]) &&
        expectedStrict.substring(0, expectedStrict.length - 1) ==
            recognizedStrict) {
      return true;
    }
    // Bavure de frontière avec le mot précédent : en mode continu, la fin du
    // mot précédent peut déborder dans la fenêtre de transcription de celui-
    // ci (ex. "دُ لِلَّهِ" pour "لِلَّهِ", "نِ ٱلرَّحِيمِ" pour "ٱلرَّحِيمِ") --
    // observé sur device 2026-07-16 avec le modèle tajweed epoch09. Le mot
    // attendu EST bien présent, juste précédé d'un fragment parasite court --
    // borné à quelques caractères pour ne pas accepter un préfixe non lié.
    const maxBleedPrefix = 4;
    if (recognizedStrict.length > expectedStrict.length &&
        recognizedStrict.length - expectedStrict.length <= maxBleedPrefix &&
        recognizedStrict.endsWith(expectedStrict)) {
      return true;
    }
    return false;
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      var prev = dp[0];
      dp[0] = i;
      for (var j = 1; j <= n; j++) {
        final tmp = dp[j];
        dp[j] = min(
          min(dp[j] + 1, dp[j - 1] + 1),
          prev + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
        prev = tmp;
      }
    }
    return dp[n];
  }
}

// ── Interface ────────────────────────────────────────────────────────────────

abstract class RecitationVerifier {
  Stream<RecognizedToken> get tokens;
  Stream<double> get soundLevel;

  /// Texte brut transcrit par le modèle (avant découpage en mots) — debug/visualisation.
  Stream<String> get rawTranscript;

  /// Transcript structuré du mode continu : `committed` = segments figés
  /// (append-only, plus jamais révisés par une re-transcription), `preview` =
  /// segment courant (encore révisable). Le scoring s'ANCRE sur committed —
  /// re-partir du mot 0 à chaque mise à jour calait dès qu'une re-transcription
  /// perdait le début du texte (curseur bloqué, test réel 2026-07-05).
  Stream<({String committed, String preview})> get structuredTranscript;

  /// Nombre de segments audio en attente/en cours de transcription (mode continu).
  Stream<int> get pendingSegments;

  /// Le récitateur s'est écarté du texte attendu (2026-08-01, chaîne v2).
  /// Distinct de tout verdict par mot : ici ce n'est pas un mot qui est faux,
  /// c'est la récitation qui a quitté le texte. Ne s'émet jamais sur un
  /// simple silence. La valeur portée est le dernier mot DÉFINITIF au moment
  /// du décrochage (-1 si aucun) : c'est de là qu'il faut reprendre.
  Stream<int> get decrochage;

  /// Décodage libre de la dernière fenêtre v2 (mode prière) : le texte que le
  /// modèle entend, SANS cible imposée. Base de l'identification de sourate.
  /// Vide par défaut -- une implémentation sans v2 n'a rien à en dire.
  Stream<String> get v2DecodageLibre => const Stream.empty();

  /// Passage probablement sauté (mode prière) : les mots `de + 1 .. a - 1`
  /// n'ont pas été entendus. PAS un verdict -- de quoi souffler le passage.
  Stream<({int de, int a})> get v2SautPresume => const Stream.empty();

  /// Chemin d'un WAV stable (survit à la transcription, contrairement aux
  /// segments temporaires normalement supprimés aussitôt) contenant le DERNIER
  /// enregistrement transcrit — utilisé pour l'empreinte vocale (comparaison
  /// audio-à-audio, voir voice_fingerprint_service.dart). Null tant qu'aucune
  /// transcription n'a eu lieu dans la session courante.
  String? get lastAudioPath;

  /// Passes d'alignement forcé GOP (cf. ForcedAligner.kt, refonte 2026-07-11) :
  /// le texte attendu est connu d'avance, chaque passe d'inférence aligne de
  /// force les mots restants sur les log-probs du modèle et émet un score par
  /// mot (gop = forced − free). C'est la source de jugement PRIMAIRE du scoring
  /// quand [alignmentActive] est vrai — le diff textuel flou historique ne sert
  /// plus que de repli.
  Stream<AlignPayload> get alignedWords;

  /// Verdicts de la chaîne v2 (branchée en parallèle de la v1) : des STATUTS
  /// déjà décidés, pas des scores — la couche de décision vit côté natif.
  /// Vide par défaut : une implémentation qui ne porte pas la v2 n'a rien à
  /// faire de plus.
  Stream<List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})>> get v2Statuses =>
      const Stream.empty();

  /// Active la v2 sur [mots]. No-op par défaut.
  ///
  /// [mode] : 'CTL' (contrôle) ou 'REF' (référence) -- cloisonnement
  /// contrôle/test (REFONTE_IHM.md §14). Défaut 'CTL' : un appelant qui ne
  /// précise rien obtient le comportement de l'usage réel, jamais celui de la
  /// recette par accident.
  Future<void> v2Activer(bool actif, List<String> mots,
      {String mode = 'CTL',
      List<int> nonJugeables = const [],
      int depart = -1}) async {}

  /// Agrandit la cible v2 EN COURS DE SESSION, SANS recréer la chaîne (donc
  /// sans perdre l'ancre ni les mots déjà verrouillés) -- 2026-08-05. Même
  /// rôle que [extendAlignmentTarget] mais côté v2 (v1 et v2 ont chacun leur
  /// propre cible native, cf. le commentaire de v2SetTarget). No-op par
  /// défaut. Words = formes `alignTarget`, PAS les formes training du v1.
  Future<void> v2ExtendTarget(List<String> mots,
      {List<int> nonJugeables = const []}) async {}

  /// LA VOIX DU RÉCITATEUR sur les mots [motDebut]..[motFin] (inclus), en WAV.
  /// C'est l'audio EXACT qui a servi à juger ces mots. `null` si l'audio n'est
  /// plus disponible. No-op par défaut.
  /// Recule l'ancre v2 au mot donne (decrochage/erreur) sans recreer la
  /// chaine. Rend faux si la v2 ne tourne pas. No-op par defaut.
  Future<bool> v2ReculerAncre(int mot) async => false;

  Future<String?> v2ExtraitVoix(int motDebut, int motFin) async => null;

  /// FERME la session v2 (dernière analyse de la queue d'audio). Sans elle les
  /// derniers mots prononcés restent PROVISOIRES. No-op par défaut.
  Future<void> v2Terminer() async {}

  /// Active/désactive le BLOC DE FUSION de la v2 (mesure). No-op par défaut.
  Future<void> v2SetFusion(bool actif,
      {int preuves = 2,
      double pas = 4.0,
      double largeur = 4.0,
      double maxBloc = 10.0,
      double maxFusion = 18.0}) async {}

  /// Vrai si l'alignement forcé est actif pour la session courante (cible
  /// déclarée + modèle chargé). Faux → le scoring doit retomber sur le diff
  /// textuel historique.
  bool get alignmentActive;

  /// Vrai si le modèle chargé expose une TÊTE TAJWID (architecture à deux
  /// têtes, 2026-07-22 — cf. FastConformerVerifier.hasRuleHead).
  ///
  /// ⚠️ Sur un modèle à une seule tête, aucune règle n'est jamais détectée :
  /// conclure « règle non réalisée » dans ce cas ferait passer orange TOUS les
  /// mots porteurs d'une règle. Toujours tester ceci avant de juger le tajwid.
  bool get hasRuleHead;

  /// Détail explicite du dernier échec de chargement du modèle (nom du modèle
  /// attendu, fichier manquant, chemin) -- nul si chargé ou jamais tenté.
  /// Cf. FastConformerVerifier.dernierEchecChargement pour pourquoi ce champ
  /// existe (2026-08-09, demande utilisateur : messages d'erreur explicites).
  String? get dernierEchecChargementModele;

  /// Repositionne l'ancre d'alignement natif (correction/recul) — la prochaine
  /// passe compare l'audio au mot [index], pas à la suite du texte.
  Future<void> setAlignmentAnchor(int index);

  /// Remplace ENTIÈREMENT la cible d'alignement forcé (contrairement à
  /// [extendAlignmentTarget], qui ajoute à la suite de la cible actuelle SANS
  /// y toucher) — utilisé pour basculer vers un texte complètement différent
  /// EN COURS de session sans la redémarrer (mode "réciteur confiant" prière,
  /// 2026-07-18 : bascule Al-Fatiha <-> sourate suivie entre deux temps de la
  /// salât, cf. RecitationNotifier._beginFatihaPhase/_beginTargetPhase).
  /// [trainingWords] = formes fidèles à l'entraînement (mêmes que
  /// `RecitedWord.training`). Retourne true si l'alignement est actif pour
  /// cette nouvelle cible (modèle chargé + tokenisation OK).
  /// [refMinFrames] (parallèle à [trainingWords], null par mot sans référence)
  /// = plancher de durée de référence en frames, cf. WordTimingService /
  /// ForcedAligner.combinedMinFrames.
  Future<bool> replaceAlignmentTarget(List<String> trainingWords, int anchor,
      {List<int?>? refMinFrames});

  /// Étend la cible d'alignement forcé avec des mots supplémentaires (formes
  /// STRICTES d'entraînement), à la SUITE de la cible actuelle — SANS toucher
  /// l'ancre en cours. Utilisé pour enchaîner sur la sourate suivante sans
  /// interrompre la session (demande utilisateur 2026-07-11) : la récitation
  /// continue exactement où elle en était, juste avec plus de texte derrière.
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords,
      {List<int?>? refMinFrames});

  /// Active/désactive la capture de clips VÉRIFIÉS CORRECTS pour le futur
  /// mini-LoRA de personnalisation vocale (FONCTIONNALITES_FUTURES.md,
  /// "Personnalisation voix -- niveau 3", implémenté 2026-07-12). [dir] =
  /// null désactive. N'écrit rien tant que non activé -- zéro coût hors
  /// session de référence.
  Future<void> setClipCapture(String? dir);

  /// Coupe/rétablit le journal de diagnostic natif (cf.
  /// DiagnosticLog.enabled). Piloté par le même réglage utilisateur que le
  /// côté Dart — cf. FastConformerVerifier.setLogEnabled.
  Future<void> setLogEnabled(bool enabled);

  /// Vide la trace fine NATIVE (accumulée en mémoire, cf. DiagnosticLog.trace)
  /// dans le fichier de log. À appeler uniquement HORS récitation. Retourne le
  /// nombre de lignes écrites.
  Future<int> flushNativeTrace();

  /// WAV rejoué à la place du micro (recette déterministe). Null = micro.
  set wavRejoue(String? v);

  /// Alignement forcé ONE-SHOT sur un WAV complet (pas de streaming, pas de
  /// segmentation, `isFinal=true`). Utilisé par [ReferenceTimingExtractor]
  /// pour mesurer les durées après coup sur des clips recollés — c'est le VRAI
  /// aligneur de production, rien n'est réimplémenté.
  Future<AlignPayload?> alignFile(String wavPath);

  /// Cf. FastConformerVerifier.setNeverBlockAnchor — à pousser AVANT [start].
  Future<void> setNeverBlockAnchor(bool value);

  /// [continuous] : enregistrement continu segmenté par détection de silence
  /// (VAD énergie), pour réciter plusieurs versets/une sourate entière sans
  /// interaction manuelle entre chaque verset.
  Future<void> start(List<String> expectedWords,
      {bool continuous = false, List<int?>? refMinFrames});

  /// Suppression de bruit du micro (cf. noiseSuppressProvider). Poussé AVANT
  /// [start] : la valeur est lue au moment d'ouvrir le flux, la changer en
  /// cours de session n'a aucun effet.
  set noiseSuppress(bool value);
  Future<void> stop();

  /// Numero de la session actuellement demarree (0 = aucune) -- capturer
  /// juste apres start(), repasser a [stopIfCurrentSession] au dispose.
  int get sessionGeneration;

  /// Le micro est-il actuellement DÉTENU par une capture continue ?
  ///
  /// Ajouté le 2026-08-10 pour `GardeMicro` (cf. `services/garde_micro.dart`).
  /// C'est la seule question qu'un garde extérieur a besoin de poser, et elle
  /// doit être posée à celui qui tient réellement la ressource — pas à un
  /// écran, pas au notifier : `recitationVerifierProvider` n'est pas
  /// autoDispose, cette instance survit aux écrans qui la pilotent.
  ///
  /// ⚠️ Vrai pendant une PAUSE : `pause()` ne rend pas le micro, seul `stop()`
  /// le rend (Android garde l'`AudioRecord` vivant, donc son indicateur de
  /// confidentialité allumé). C'est voulu — décision utilisateur 2026-08-10 :
  /// la pause conserve le micro, seule la SORTIE le relâche.
  bool get captureEnCours;

  /// Comme stop()+resetBuffer(), mais NE FAIT RIEN si [expectedGeneration]
  /// ne correspond plus a la session actuelle (une session plus recente a
  /// deja demarre entre-temps). A utiliser depuis un nettoyage fire-and-
  /// forget (ex. dispose()) pour ne jamais saboter une session qui a deja
  /// pris le relais (cf. Finding #1, revue de code 2026-07-16 : ce nettoyage
  /// etait auparavant un simple stop()+resetBuffer() sans garde, capable de
  /// tuer une session flambant neuve sur reouverture rapide de l'ecran).
  Future<void> stopIfCurrentSession(int expectedGeneration);

  /// Suspend/reprend la capture micro SANS arrêter la session (mots/score
  /// conservés) — utilisé par la correction automatique (demande utilisateur
  /// 2026-07-05) : on coupe l'écoute le temps de jouer la prononciation
  /// correcte, puis on reprend exactement où on en était.
  Future<void> pauseCapture();
  Future<void> resumeCapture();

  /// À appeler juste après [pauseCapture] quand la pause peut durer (bouton
  /// pause de l'utilisateur, pas la pause courte de la correction auto) :
  /// force un dernier verdict sur les mots encore en attente, pour que la
  /// série/le décompte Coach ne perdent pas la fin de la récitation si
  /// l'utilisateur quitte l'écran sans avoir repris.
  ///
  /// Attend d'abord que tout envoi de bloc PCM déjà en vol ait fini d'être
  /// transmis à la chaîne (même attente que [resetBuffer]) avant d'appeler
  /// [v2Terminer] : sans ça, `v2Terminer()` pourrait trancher avant que les
  /// tout derniers blocs captés juste avant la pause n'aient atteint le
  /// natif, et couper le dernier mot au lieu de le juger.
  ///
  /// Non destructif (cf. doc de [v2Terminer]) : sûr à appeler avant une
  /// reprise, ne libère ni le micro ni aucun buffer nécessaire à la suite.
  Future<void> finaliserPourPause();

  /// Pause LOGICIELLE instantanée : la chaîne (transcription, alignement,
  /// jugement) s'arrête net, mais le micro matériel n'est PAS touché.
  ///
  /// Pourquoi ça existe (mesuré 2026-07-25) : sur ce téléphone les appels du
  /// plugin `record` sont pathologiquement lents -- `isRecording()` a mis
  /// **3,6 s** et `pause()` **6,4 s** (jusqu'à 24 s observé) sur une seule
  /// correction. Or la chaîne est déjà arrêtée dès que `_appPaused` est posé,
  /// de façon synchrone : attendre le matériel n'apporte RIEN et retardait de
  /// ~10 s le moment où le réciteur entend sa correction et où l'ancre revient
  /// sur le mot raté. Dans un chemin où seul compte « ne plus juger », on
  /// utilise donc cette version.
  ///
  /// Aucune course pause/resume possible : rien n'est en vol côté plateforme.
  void pauseCaptureSoft();

  /// Pendant de [pauseCaptureSoft].
  void resumeCaptureSoft();

  /// Pause destinée à encadrer une LECTURE AUDIO (correction, souffleur) :
  /// arrête la chaîne **instantanément** (comme [pauseCaptureSoft]) ET suspend
  /// le micro matériel, mais **sans attendre** que le natif ait fini.
  ///
  /// Pourquoi les deux à la fois (régression mesurée le 2026-07-25) : j'avais
  /// d'abord retiré la pause matérielle du chemin de correction, pour supprimer
  /// 6,4 s d'attente. Résultat sur device -- le micro reste actif pendant que
  /// le haut-parleur joue la correction, la lecture perturbe l'enregistrement
  /// Android, et **le flux PCM ne revient jamais** : dernier bloc à
  /// `17:23:50.473`, plus rien après la reprise, l'utilisateur ne pouvait plus
  /// continuer. La pause matérielle ne servait donc pas seulement à « ne plus
  /// juger » : elle **protégeait l'intégrité de l'enregistrement**.
  ///
  /// D'où cette forme : on garde la pause matérielle (intégrité) mais on ne
  /// l'attend pas (réactivité). L'appelant enchaîne immédiatement sur le recul
  /// d'ancre et la lecture ; [resumeCaptureAfterPlayback] attend l'atterrissage
  /// avant de reprendre, ce qui élimine aussi la course pause/resume.
  void pauseCaptureForPlayback();

  /// Reprise après [pauseCaptureForPlayback] : attend que la pause lancée en
  /// tâche de fond ait ATTERRI (sinon `resume()` pourrait s'exécuter avant la
  /// pause et le micro resterait coupé), puis relance micro et chaîne.
  Future<void> resumeCaptureAfterPlayback();

  /// Vide le buffer de ré-transcription (texte figé + aperçu) SANS arrêter la
  /// session — à appeler entre pauseCapture()/resumeCapture() lors d'une
  /// correction automatique (demande utilisateur 2026-07-06) : sans ça, de
  /// l'audio déjà dans le buffer avant la pause (pas encore figé) peut
  /// ressurgir après la reprise et contaminer la nouvelle tentative — le mot
  /// semble "déjà rejugé" avant même que le réciteur ait fini de répéter.
  Future<void> resetBuffer();

  void dispose();

  /// S'assure que le modèle ASR est chargé, SANS démarrer de session
  /// (idempotent, sûr à appeler plusieurs fois). Ajouté pour le moteur de
  /// répétition incrémentale du Coach (demande utilisateur 2026-07-24,
  /// "éviter qu'il parle dans le vide") : [start] ne bloque pas sur le
  /// chargement, il le lance en fire-and-forget en interne -- ce point
  /// d'entrée permet à l'UI d'attendre explicitement AVANT de signaler
  /// "à toi" et de lancer l'écoute automatique.
  Future<bool> ensureModelLoaded();

  /// Charge le moteur utilisé par une récitation CONTINUE sans ouvrir le
  /// micro. Le graphe causal streaming est prioritaire ; le modèle bufferisé
  /// reste le repli prévu par [start].
  ///
  /// Ce contrat permet à l'UI d'attendre le vrai moteur, d'afficher son compte
  /// à rebours, puis seulement d'appeler [start] et d'annoncer « Go » une fois
  /// la capture effectivement ouverte.
  Future<bool> ensureContinuousModelLoaded();
}

// ── ASR on-device ────────────────────────────────────────────────────────────
// FastConformer CTC (notre modèle, cf. benchmark/models/fastconformer-quran-pcd)
// est le SEUL moteur utilisé ici — pas whisper.cpp. Concept cible "karaoké" à un
// seul modèle qui vérifie le texte connu en continu (pas une transcription libre
// qu'on diff après coup). whisper.cpp reste disponible ailleurs dans le projet
// (modèle de production actuel, ~11% WER) mais n'est pas utilisé par CETTE classe
// pendant que le training du modèle maison est en cours.

const String _kAsrVersion = 'ASR-v46-causal-stateful';

class WhisperOnnxVerifier implements RecitationVerifier {
  WhisperOnnxVerifier({
    AudioRecorder? recorder,
    FastConformerVerifier? fastConformer,
  })  : _recorder = recorder ?? AudioRecorder(),
        _fastConformer = fastConformer ?? FastConformerVerifier();

  final _tokenCtrl = StreamController<RecognizedToken>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();
  final _rawCtrl = StreamController<String>.broadcast();
  final _structCtrl =
      StreamController<({String committed, String preview})>.broadcast();
  final _alignCtrl = StreamController<AlignPayload>.broadcast();
  /// Flux SÉPARÉ de la v2 : aucune couche du chemin v1 ne le lit.
  final _decrochageCtrl = StreamController<int>.broadcast();
  final _v2Ctrl =
      StreamController<List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})>>.broadcast();
  final AudioRecorder _recorder;
  Timer? _levelTimer;

  final FastConformerVerifier _fastConformer;

  String? _lastAudioPath;

  bool _alignmentActive = false;
  int _lastAlignSeq = -1;
  bool _usingCausalStreaming = false;
  Future<void> _continuousFeedTail = Future.value();
  String? _clipCaptureDir;
  StreamingWavCapture? _streamingWavCapture;

  // ── Verrou de session (bug corrige 2026-07-16, revue de code, Finding #1) ──
  // recitationVerifierProvider N'EST PAS autoDispose : CETTE instance survit
  // aux notifiers (autoDispose, eux) qui la pilotent tour a tour. Le nettoyage
  // fire-and-forget de RecitationNotifier.dispose() (stop()+resetBuffer(),
  // necessairement fire-and-forget car dispose() est synchrone) n'avait aucune
  // synchronisation contre une NOUVELLE session demarree entre-temps -- si
  // l'utilisateur quitte puis rouvre vite l'ecran karaoke, le stop() de
  // l'ANCIENNE session peut s'executer APRES que la NOUVELLE ait deja appele
  // _recorder.startStream(), tuant silencieusement le nouvel enregistrement,
  // ou son resetBuffer() peut arriver apres le resetBuffered() de la nouvelle
  // session et vider un buffer qui contient deja de l'audio frais.
  //
  // Fix : un verrou serialise (FIFO, cf. _serialized) autour de start() ET du
  // nettoyage de dispose -- garantit qu'ils ne s'executent JAMAIS en meme
  // temps, quel que soit l'ordre. Un numero de generation, incremente a
  // chaque start(), permet en plus au nettoyage d'une session PERIMEE de se
  // transformer en no-op s'il s'execute apres qu'une nouvelle session a deja
  // demarre (plutot que de stop()/resetBuffer() une session qui n'est plus la
  // sienne).
  int _generation = 0;
  Future<void> _sessionLock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _sessionLock;
    final completer = Completer<void>();
    _sessionLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Numero de la session actuellement demarree (0 = aucune). Un notifier
  /// capture cette valeur juste apres son propre start() ; au dispose, il la
  /// repasse a [stopIfCurrentSession] pour que le nettoyage ne s'applique
  /// QUE si aucune session plus recente n'a pris le relais depuis.
  int get sessionGeneration => _generation;

  /// `_pcmSub` est l'abonnement au flux PCM : il n'existe QUE entre
  /// `startStream()` et `stop()`. C'est donc l'image exacte de « le micro est
  /// détenu », et non une variable d'intention qu'on pourrait oublier de
  /// remettre à jour.
  @override
  bool get captureEnCours => _pcmSub != null;

  @override
  Stream<RecognizedToken> get tokens => _tokenCtrl.stream;
  @override
  Stream<double> get soundLevel => _levelCtrl.stream;
  @override
  Stream<String> get rawTranscript => _rawCtrl.stream;
  @override
  Stream<({String committed, String preview})> get structuredTranscript =>
      _structCtrl.stream;
  @override
  Stream<AlignPayload> get alignedWords => _alignCtrl.stream;
  @override
  bool get alignmentActive => _alignmentActive;
  @override
  bool get hasRuleHead => _fastConformer.hasRuleHead;

  @override
  String? get dernierEchecChargementModele =>
      _fastConformer.dernierEchecChargement;
  @override
  String? get lastAudioPath => _lastAudioPath;

  @override
  Future<void> setAlignmentAnchor(int index) =>
      _fastConformer.setAlignmentAnchor(index);

  @override
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords,
          {List<int?>? refMinFrames}) =>
      _fastConformer.extendAlignmentTarget(moreTrainingWords,
          refMinFrames: refMinFrames);

  @override
  Future<bool> replaceAlignmentTarget(List<String> trainingWords, int anchor,
      {List<int?>? refMinFrames}) async {
    _alignmentActive = await _fastConformer
        .setAlignmentTarget(trainingWords, anchor, refMinFrames: refMinFrames);
    return _alignmentActive;
  }

  @override
  Future<void> setClipCapture(String? dir) async {
    _clipCaptureDir = dir;
    await _fastConformer.setClipCapture(dir);
    if (dir == null) await _closeStreamingWavCapture();
  }

  @override
  Future<void> setLogEnabled(bool enabled) => _fastConformer.setLogEnabled(enabled);

  @override
  Future<int> flushNativeTrace() => _fastConformer.flushNativeTrace();

  @override
  Future<AlignPayload?> alignFile(String wavPath) =>
      _fastConformer.alignFile(wavPath);

  @override
  Future<void> setNeverBlockAnchor(bool value) =>
      _fastConformer.setNeverBlockAnchor(value);

  // ── Segmentation continue (VAD énergie) ──────────────────────────────────
  // dBFS en dessous duquel on considère qu'il y a silence (seuil à ajuster
  // selon la sensibilité du micro — point de réglage principal).
  static const double _kSilenceDbfs = -45.0;
  static const int _kSilenceCutMs = 700;   // silence soutenu -> on coupe
  static const int _kMinSegmentMs = 1200;  // segment mini avant d'autoriser une coupure
  static const int _kMaxSegmentMs = 25000; // coupure forcée (contexte encodeur ~30s)

  bool _continuous = false;
  bool _sessionEnding = false;
  String? _currentSegmentPath;
  DateTime? _segmentStart;
  DateTime? _silenceStart;

  final List<String> _queue = [];
  final _pendingCtrl = StreamController<int>.broadcast();
  bool _draining = false;

  @override
  Stream<int> get pendingSegments => _pendingCtrl.stream;

  StreamSubscription<Uint8List>? _pcmSub;

  /// Chemin d'un WAV rejoue a la place du micro (recette deterministe).
  /// Null = micro normal. Pose par l'ecran de recette via l'intent.
  String? _wavRejoue;
  set wavRejoue(String? v) => _wavRejoue = v;

  /// Rejoue un WAV 16 kHz mono en blocs de 80 ms a la cadence TEMPS REEL --
  /// mêmes tailles et même rythme que `record`, pour que la segmentation, les
  /// pauses detectees et la latence soient celles d'une vraie session. Rejouer
  /// plus vite fausserait tout ce qui depend du temps.
  Stream<Uint8List> _fluxDepuisFichier(String chemin) async* {
    final octets = await File(chemin).readAsBytes();
    const enTete = 44;            // WAV canonique ecrit par WavWriter
    const bloc = 2560;            // 1280 echantillons = 80 ms a 16 kHz 16 bits
    for (var i = enTete; i + 2 <= octets.length; i += bloc) {
      final fin = i + bloc <= octets.length ? i + bloc : octets.length;
      yield Uint8List.fromList(octets.sublist(i, fin));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    DiagnosticLog.log('ASR', 'SOURCE DETERMINISTE : fin du fichier');
  }

  // Garde-fou cote app (2026-07-16, cf. bug reel constate : "j'ai fait pause
  // mais il continue") -- _recorder.pause() est un appel platform-channel
  // async qui peut mettre plusieurs secondes (jusqu'a 23,8s observe sur
  // device) avant que le natif arrete reellement le micro. Le listener PCM
  // ci-dessous, lui, traitait INCONDITIONNELLEMENT chaque bloc recu pendant
  // ce delai (aucun check isPaused) -- alignement/GOP continuaient a tourner
  // sur de l'audio arrivant pendant une pause "en cours". Ce flag est mis a
  // jour de facon SYNCHRONE (avant tout await), independamment de la latence
  // du native, pour que le pipeline s'arrete immediatement du point de vue
  // de l'app, meme si le micro physique met du temps a suivre.
  bool _appPaused = false;

  bool _noiseSuppress = false;
  @override
  set noiseSuppress(bool value) => _noiseSuppress = value;

  @override
  Future<void> start(List<String> expectedWords,
      {bool continuous = false, List<int?>? refMinFrames}) {
    return _serialized(() => _startLocked(expectedWords,
        continuous: continuous, refMinFrames: refMinFrames));
  }

  Future<void> _startLocked(List<String> expectedWords,
      {bool continuous = false, List<int?>? refMinFrames}) async {
    _generation++;
    final hasPerm = await _recorder.hasPermission();
    debugPrint(
        '[ASR] [$_kAsrVersion] start() | perm=$hasPerm | mots=${expectedWords.length} | continu=$continuous | generation=$_generation');
    if (!hasPerm) return;

    _continuous = continuous;
    _sessionEnding = false;
    _alignmentActive = false;
    _lastAlignSeq = -1;

    if (continuous) {
      await _startStreamingCapture(expectedWords, refMinFrames);
      return;
    }

    _rawCtrl.add('⏳ Chargement FastConformer CTC…');
    unawaited(_fastConformer.ensureLoaded().then((ok) async {
      if (ok) {
        // [expectedWords] = formes STRICTES (normalizeStrict : harakat
        // conservées, même normalisation que le corpus d'entraînement) — la
        // cible de l'alignement forcé GOP. false → repli diff textuel.
        // Liste VIDE (demande utilisateur 2026-07-18, "Shazam coranique" :
        // écoute libre sans texte attendu connu à l'avance) -- pas de cible
        // à aligner, ne pas tenter setAlignmentTarget du tout : un target
        // vide n'a aucun sens pour l'alignement forcé et pouvait perturber
        // la transcription libre elle-même (constat réel : segments tronqués/
        // dégradés observés en test alors que alignement forcé actif=true
        // sur une cible vide).
        if (expectedWords.isNotEmpty) {
          _alignmentActive = await _fastConformer
              .setAlignmentTarget(expectedWords, 0, refMinFrames: refMinFrames);
          DiagnosticLog.log('ASR', 'alignement forcé actif = $_alignmentActive');
        }
      }
      _rawCtrl.add(ok
          ? '✅ FastConformer chargé — en écoute'
          : '❌ FastConformer introuvable (modèle/vocab absents sur le device)');
    }));
    await _beginSegment();

    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amp = await _recorder.getAmplitude();
        _levelCtrl.add(((amp.current + 60) / 60).clamp(0.0, 1.0));
      } catch (_) {}
    });
  }

  int _chunkCount = 0;

  /// Flux continu (karaoké) : capture PCM16 brute en direct. Le checkpoint
  /// causal entraîné utilise en priorité son export cache-aware ; l'ancien
  /// BufferedTranscriber reste un rollback explicite si l'ONNX stateful ou ses
  /// métadonnées ne sont pas présents sur le device.
  ///
  /// Historique : le premier essai cache-aware avait été abandonné parce que
  /// le checkpoint PCD utilisait des convolutions non causales et sortait du
  /// blank en flux. Cette conclusion reste vraie pour CE checkpoint ancien,
  /// mais ne s'applique pas au nouveau modèle entraîné causalement.
  Future<void> _startStreamingCapture(
      List<String> expectedWords, List<int?>? refMinFrames) async {
    await _closeStaleContinuousCapture();
    _chunkCount = 0;
    _pcmQueued = 0;
    _pendingPcm.clear();
    _feedInFlight = false;
    DiagnosticLog.traceReset();
    unawaited(_fastConformer.resetNativeTrace());
    _continuousFeedTail = Future.value();
    _rawCtrl.add('⏳ Chargement FastConformer…');
    final causalOk = await _fastConformer.ensureStreamingLoaded();
    final ok = causalOk || await _fastConformer.ensureLoaded();
    _usingCausalStreaming = causalOk;
    _rawCtrl.add(ok
        ? causalOk
            ? '✅ Causal chargé — en écoute (lookahead 1,04 s)'
            : '✅ Repli bufferisé chargé — en écoute'
        : '❌ Modèle introuvable (modèle/vocab absents sur le device)');
    if (!ok) return;
    // Moteur prêt -- `alignmentActive` marque désormais "le moteur peut
    // aligner", pas "une cible est actuellement fixée" (2026-07-18, "Suivre
    // une prière" : session démarrée SANS sourate connue, cf.
    // RecitationNotifier.startPrayerFollow). Une cible VIDE ne doit PAS être
    // envoyée à setAlignmentTarget -- même bug déjà corrigé pour le mode
    // segment unique (Shazam coranique, cf. _startLocked ci-dessus) : un
    // target vide dégrade/tronque la transcription libre elle-même, alors
    // que cette session doit justement pouvoir écouter librement (standby en
    // attente d'Al-Fatiha) avant qu'une cible existe.
    _alignmentActive = true;
    if (expectedWords.isNotEmpty) {
      await _fastConformer
          .setAlignmentTarget(expectedWords, 0, refMinFrames: refMinFrames);
      DiagnosticLog.log('ASR',
          'alignement forcé actif = $_alignmentActive (cible=${expectedWords.length} mots)');
    } else {
      DiagnosticLog.log('ASR',
          'alignement forcé actif = $_alignmentActive (cible vide au départ)');
    }
    if (_usingCausalStreaming) {
      await _fastConformer.resetStreaming();
    } else {
      await _fastConformer.resetBuffered();
    }

    await _openStreamingWavCapture();
    DiagnosticLog.log('ASR', 'Appel _recorder.startStream()…');
    try {
      final hasPerm = await _recorder.hasPermission();
      DiagnosticLog.log('ASR', 'hasPermission (juste avant startStream) = $hasPerm');

      // ── SOURCE DETERMINISTE POUR LA RECETTE (2026-07-28) ────────────────
      // Le banc a deux telephones passe par haut-parleur -> micro, donc chaque
      // passe differe : point de depart du recitateur, niveau, bruit de piece.
      // Mesure : le MEME binaire sur la MEME sourate donne 1,4 % puis 4,3 % de
      // mots non verts, et les passes vont de 0,0 % a 10,9 %. La variance du
      // banc depasse l'effet qu'on cherche a mesurer -- dans ces conditions
      // tout « gain » annonce est du bruit, et on ajuste sur la mesure au lieu
      // de traiter une cause.
      //
      // En rejouant un FICHIER, chaque passe devient identique au bit pres et
      // la seule variable est le code. Le flux emprunte EXACTEMENT le meme
      // chemin que le micro (memes blocs de 80 ms, meme cadence temps reel,
      // meme aval) : on ne mesure donc pas un chemin de test different.
      final Stream<Uint8List> stream;
      if (_wavRejoue != null) {
        stream = _fluxDepuisFichier(_wavRejoue!);
        DiagnosticLog.log('ASR', 'SOURCE DETERMINISTE : $_wavRejoue');
      } else {
        // `noiseSuppress` : desactive par defaut (cf. noiseSuppressProvider pour
        // les trois raisons mesurees). Expose pour pouvoir trancher par une
        // comparaison A/B, pas pour etre allume a l'aveugle.
        stream = await _recorder.startStream(
          RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
              noiseSuppress: _noiseSuppress),
        );
      }
      DiagnosticLog.log('ASR',
          'capture ouverte | suppression de bruit = $_noiseSuppress');
      DiagnosticLog.log('ASR', 'startStream() a retourné un Stream — abonnement…');

      _pcmSub = stream.listen(
        (bytes) {
          if (_appPaused) return;
          _streamingWavCapture?.add(bytes);
          _chunkCount++;
          final chunkNumber = _chunkCount;
          if (_chunkCount == 1) {
            DiagnosticLog.log('ASR', 'PREMIER bloc PCM reçu ! ${bytes.length} octets');
          } else if (_chunkCount % 20 == 0) {
            DiagnosticLog.log('ASR', 'bloc PCM #$_chunkCount (${bytes.length} octets)');
          }
          _levelCtrl.add(_estimatePcmLevel(bytes));
          // TRACE (2026-07-27) : `enFile` = blocs recus mais pas encore passes
          // au natif. C'est LA grandeur qui manquait pour savoir si le retard
          // vient de la chaine d'alimentation ou d'ailleurs -- `bloc PCM #N`
          // etait journalise a la RECEPTION, donc aveugle a cette file.
          _pcmQueued++;
          DiagnosticLog.trace('recu', 'n=$chunkNumber enFile=$_pcmQueued');
          // ── GROUPAGE ADAPTATIF DU TRANSPORT (2026-07-27) ──────────────────
          // AVANT : un aller-retour MethodChannel PAR BLOC de 80 ms, serialise
          // par une chaine FIFO. Si l'aller-retour depasse 80 ms en moyenne --
          // il fait un saut par le thread principal, celui-la meme qui dessine
          // le karaoke -- la file grossit SANS BORNE.
          //
          // MESURE QUI L'IMPOSE (session du 16:56) : a la pause, ~35 s de blocs
          // etaient encore en attente. L'app a continue de figer QUATRE
          // segments pendant 45 s apres l'appui, buffer grossissant de 1 s a
          // 10 s alors qu'aucun audio n'arrivait plus. C'est la meme cause que
          // les 28,7 s de validations posterieures au dernier bloc et que les
          // retards de validation de 10 a 27 s. Verifie au passage : AUCUNE
          // perte d'audio a la capture (426,3 s de micro actif contre 425,6 s
          // recues, soit 0,2 % d'ecart) -- le defaut est entierement en aval.
          //
          // ICI : on accumule, et on n'envoie que lorsque la chaine est libre,
          // en un seul appel. Auto-regulant par construction : chaine rapide ->
          // paquets d'un bloc (comportement d'avant) ; chaine lente -> paquets
          // plus gros qui la font rattraper. Il ne peut JAMAIS y avoir plus
          // d'un appel en vol, donc plus d'accumulation possible.
          //
          // On groupe le TRANSPORT, pas le TRAITEMENT : le natif redecoupe en
          // blocs de 80 ms (cf. feedBufferedAudio), donc le portier RMS et la
          // segmentation gardent exactement la granularite d'aujourd'hui.
          _pendingPcm.add(bytes);
          _pumpFeed();
        },
        onError: (e) => DiagnosticLog.log('ASR', 'Erreur sur le flux PCM : $e'),
        onDone: () => DiagnosticLog.log('ASR', 'Flux PCM terminé (onDone) — $_chunkCount blocs reçus au total'),
      );
    } catch (e, st) {
      await _closeStreamingWavCapture();
      DiagnosticLog.log('ASR', 'EXCEPTION dans _startStreamingCapture : $e\n$st');
      _rawCtrl.add('❌ Erreur démarrage capture audio : $e');
    }
  }

  /// `AudioRecorder.startStream()` ferme son ancien Stream Dart, mais ne
  /// garantit pas l'arrêt de la session native qui peut être encore PAUSÉE.
  /// Sur le Samsung de test, redémarrer dans cet état renvoyait un nouveau
  /// Stream sans jamais livrer un seul bloc PCM. Fermer explicitement
  /// l'ancienne capture avant le nouveau start rend chaque récitation
  /// indépendante.
  Future<void> _closeStaleContinuousCapture() async {
    final stale = _pcmSub;
    if (stale == null) {
      _appPaused = false;
      return;
    }
    _pcmSub = null;
    await stale.cancel();
    try {
      await _recorder.stop();
    } catch (e) {
      DiagnosticLog.log('ASR', 'arrêt ancien flux avant redémarrage échoué : $e');
    }
    await _continuousFeedTail;
    await _closeStreamingWavCapture();
    _appPaused = false;
    DiagnosticLog.log(
        'ASR', 'ancien flux fermé avant nouvelle capture continue');
  }

  /// Capture du flux micro BRUT, AVANT le portier RMS.
  ///
  /// ── POURQUOI ELLE EST INDISPENSABLE (2026-07-27) ──────────────────────────
  /// Les clips (`clip_*.wav`) ne contiennent QUE ce que le portier a GARDE.
  /// Tout ce qu'il ecarte n'existe nulle part -- donc ses decisions etaient
  /// INVERIFIABLES, et c'est exactement la question qui bloque le diagnostic :
  ///
  /// Mesure du 17:25, recitation CONTINUE d'un recitateur rejoue depuis un
  /// autre telephone : 220,8 s recues, 112,0 s ecrites dans les clips, donc
  /// **49 % ecartes**. Impossible de dire si ce sont de vraies pauses de
  /// murattal ou de la parole jetee a tort -- et trois mots
  /// (`تُنذِرْهُمْ`, `بِمُؤْمِنِينَ`, `يَكْذِبُونَ`), pourtant forcement
  /// prononces puisque la source est un enregistrement continu, restent
  /// introuvables meme en recollant tous les clips.
  ///
  /// Avec ce fichier, la question se tranche en superposant le flux brut et
  /// les clips : on voit ce qui a ete jete, et si ces mots s'y trouvent le
  /// suspect principal devient le PORTIER, avant meme la coupe.
  ///
  /// ── LA CONDITION QUI L'EMPECHAIT ──────────────────────────────────────────
  /// Elle etait conditionnee a `_usingCausalStreaming`, faux depuis que le
  /// streaming cache-aware est desactive (2026-07-27 matin) : le fichier
  /// n'etait donc PLUS JAMAIS ecrit, silencieusement. Le flux brut est utile
  /// quel que soit le chemin d'inference -- la condition est retiree.
  Future<void> _openStreamingWavCapture() async {
    await _closeStreamingWavCapture();
    if (_clipCaptureDir == null) return;
    final path =
        '$_clipCaptureDir/stream_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      _streamingWavCapture = await StreamingWavCapture.open(path);
      DiagnosticLog.log('ASR',
          'capture du flux BRUT (avant portier RMS) activee -> $path');
    } catch (e) {
      DiagnosticLog.log('ASR', 'capture du flux brut indisponible : $e');
    }
  }

  Future<void> _closeStreamingWavCapture() async {
    final capture = _streamingWavCapture;
    if (capture == null) return;
    _streamingWavCapture = null;
    try {
      final path = await capture.close();
      _lastAudioPath = path;
      DiagnosticLog.log('ASR', 'capture WAV causale finalisee -> $path');
    } catch (e) {
      DiagnosticLog.log('ASR', 'finalisation WAV causale echouee : $e');
    }
  }

  /// Blocs PCM recus mais pas encore remis au natif (cf. la chaine FIFO
  /// `_continuousFeedTail`). Trace seule, aucune decision ne s'appuie dessus.
  int _pcmQueued = 0;

  /// Audio recu et pas encore transmis au natif (cf. le groupage adaptatif
  /// dans le listener PCM). Vide des que la chaine est libre.
  final BytesBuilder _pendingPcm = BytesBuilder();
  bool _feedInFlight = false;

  /// Transmet tout l'audio en attente en UN appel, si la chaine est libre.
  /// Se rappelle a la fin de l'appel pour absorber ce qui est arrive pendant.
  void _pumpFeed() {
    if (_feedInFlight || _pendingPcm.isEmpty) return;
    final batch = _pendingPcm.takeBytes();
    final n = _chunkCount;
    _feedInFlight = true;
    _continuousFeedTail = _processContinuousChunk(batch, n)
        .catchError((Object e, StackTrace st) {
      DiagnosticLog.log('ASR', 'Erreur flux continu chunk=$n : $e\n$st');
    }).whenComplete(() {
      _feedInFlight = false;
      _pcmQueued = 0;
      _pumpFeed();
    });
  }

  Future<void> _processContinuousChunk(
      Uint8List bytes, int chunkNumber) async {
    DiagnosticLog.trace('feedEntree', 'n=$chunkNumber enFile=$_pcmQueued');
    final sw = Stopwatch()..start();
    final parts = _usingCausalStreaming
        ? await _fastConformer.feedCausalAudio(bytes)
        : await _fastConformer.feedBufferedAudio(bytes);
    _pcmQueued--;
    DiagnosticLog.trace('feedSortie',
        'n=$chunkNumber ms=${sw.elapsedMilliseconds} enFile=$_pcmQueued');
    if (parts != null &&
        (parts.committed.isNotEmpty || parts.preview.isNotEmpty)) {
      final display = [parts.committed, parts.preview]
          .where((s) => s.isNotEmpty)
          .join(' ');
      // Conditionne au meme interrupteur que le reste (2026-07-27) : c'etait la
      // SEULE ecriture restante du chemin audio a echapper au toggle -- un
      // debugPrint par 20 blocs (~1,6 s), sur l'isolate qui recoit le PCM.
      // Elle rendait invalide le test "meme situation sans log ?" que
      // l'interrupteur existe precisement pour permettre.
      if (DiagnosticLog.enabled && chunkNumber % 20 == 0) {
        debugPrint('[FastConformer] #$chunkNumber '
            'fige="${parts.committed}" apercu="${parts.preview}"');
      }
      _rawCtrl.add(display);
      _structCtrl.add(
          (committed: parts.committed, preview: parts.preview));
    }
    // Une même séquence est renvoyée sur les blocs PCM qui ne déclenchent pas
    // encore d'inférence ; la déduplication évite de rejouer son verdict.
    final align = parts?.align;
    if (align != null && align.seq != _lastAlignSeq) {
      _lastAlignSeq = align.seq;
      _alignCtrl.add(align);
    }
    // Chaîne v2, quand elle tourne en parallèle : ses changements de statut
    // partent sur un flux SÉPARÉ. Rien de ce qui précède n'en dépend — si la
    // v2 est éteinte ou tombe, la v1 se comporte exactement comme avant.
    final v2 = parts?.v2;
    if (v2 != null && v2.isNotEmpty) _v2Ctrl.add(v2);
    // DÉCROCHAGE (2026-08-01) : flux à part, pour la même raison que côté
    // Kotlin -- ce n'est pas un verdict sur un mot attendu, c'est un constat
    // sur la récitation entière. Rien de ce qui précède n'en dépend.
    if (parts?.v2Decrochage == true) {
      _decrochageCtrl.add(parts!.v2DecrochageMot);
    }
    // ── MODE PRIERE (2026-08-07) ────────────────────────────────────────────
    // Deux flux de plus, alimentés seulement quand la chaîne tourne en mode
    // PRIERE. Ils ne portent AUCUN verdict : le premier est du texte entendu
    // (pour identifier la sourate), le second des bornes de passage à
    // souffler. Rien de ce qui précède n'en dépend.
    final libre = parts?.v2Libre ?? '';
    if (libre.isNotEmpty) _libreCtrl.add(libre);
    final de = parts?.v2SautDe ?? -1;
    if (de >= 0) _sautCtrl.add((de: de, a: parts!.v2SautA));
  }

  final _libreCtrl = StreamController<String>.broadcast();
  final _sautCtrl = StreamController<({int de, int a})>.broadcast();

  /// Décodage libre de la dernière fenêtre v2, sans aucune cible imposée.
  /// C'est ce qui permet d'identifier la sourate en début de rak'ah.
  Stream<String> get v2DecodageLibre => _libreCtrl.stream;

  /// Bornes d'un passage que le récitateur semble avoir sauté (mode prière).
  /// Les mots `de + 1 .. a - 1` n'ont pas été entendus alors qu'il est déjà
  /// plus loin. PAS une accusation : de quoi lui souffler le passage.
  Stream<({int de, int a})> get v2SautPresume => _sautCtrl.stream;

  /// Changements de statut de la chaîne v2 (branchée en parallèle de la v1).
  /// Mesure de référence sur le même flux brut : v1 10,10 % de mots non verts,
  /// v2 2,03 %.
  Stream<List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})>> get v2Statuses => _v2Ctrl.stream;

  /// Le récitateur s'est écarté du texte (chaîne v2). Flux SÉPARÉ de
  /// [v2Statuses] : celui-ci parle de la récitation, pas d'un mot.
  Stream<int> get decrochage => _decrochageCtrl.stream;

  @override
  Future<void> v2Activer(bool actif, List<String> mots,
      {String mode = 'CTL',
      List<int> nonJugeables = const [],
      int depart = -1}) async {
    await _fastConformer.v2SetMode(mode);
    await _fastConformer.v2SetTarget(mots,
        nonJugeables: nonJugeables, depart: depart);
    await _fastConformer.v2SetEnabled(actif);
  }

  @override
  Future<void> v2ExtendTarget(List<String> mots,
          {List<int> nonJugeables = const []}) =>
      _fastConformer.v2ExtendTarget(mots, nonJugeables: nonJugeables);

  @override
  @override
  Future<bool> v2ReculerAncre(int mot) => _fastConformer.v2ReculerAncre(mot);

  Future<String?> v2ExtraitVoix(int motDebut, int motFin) =>
      _fastConformer.v2ExtraitVoix(motDebut, motFin);

  @override
  Future<void> v2SetFusion(bool actif,
          {int preuves = 2,
          double pas = 4.0,
          double largeur = 4.0,
          double maxBloc = 10.0,
          double maxFusion = 18.0}) =>
      _fastConformer.v2SetFusion(actif,
          preuves: preuves, pas: pas, largeur: largeur,
          maxBloc: maxBloc, maxFusion: maxFusion);

  @override
  Future<void> v2Terminer() async {
    // Les statuts de cette dernière passe ne remontent PAS par le chemin
    // habituel (la réponse de `feed()`, cf. `_v2Ctrl.add(v2)` plus haut) :
    // `feed` ne sera plus appelé, la capture est arrêtée. On les réinjecte
    // donc nous-mêmes dans le même flux, pour que `_onV2` les applique
    // exactement comme les autres.
    final finaux = await _fastConformer.v2Terminer();
    if (finaux.isEmpty) return;
    _v2Ctrl.add(finaux
        .map((e) => (
              index: e.index,
              statut: e.statut,
              trace: 'fermeture de session',
              heard: '',
              detectedRules: <TajwidRule>{},
              // false : pas de contrôle tajwid sur cette passe -- il exige
              // deux observations pleines, que la fermeture ne fournit pas.
              tajwidFiable: false,
            ))
        .toList());
  }

  /// Niveau approx (RMS -> pseudo-dBFS -> [0,1]) pour l'animation du halo,
  /// calculé directement sur le PCM reçu (pas d'API getAmplitude() en mode
  /// startStream — les deux mécanismes du package `record` sont distincts).
  double _estimatePcmLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final data = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    double sumSq = 0;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSq += s * s;
    }
    final rms = sqrt(sumSq / n);
    if (rms <= 0) return 0;
    final db = 20 * (log(rms) / ln10);
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  Future<void> _beginSegment() async {
    final tmp = await getTemporaryDirectory();
    _currentSegmentPath = '${tmp.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: _currentSegmentPath!,
    );
    _segmentStart = DateTime.now();
    _silenceStart = null;
  }

  /// Coupe le segment en cours (silence détecté ou durée max) et enchaîne
  /// immédiatement un nouvel enregistrement pour ne pas perdre la suite.
  Future<void> _cutAndRestart() async {
    final path = await _recorder.stop();
    DiagnosticLog.log('ASR', 'Segment coupé (silence/durée max) → $path');
    _enqueueIfValid(path);
    if (!_sessionEnding) await _beginSegment();
  }

  void _enqueueIfValid(String? path) {
    if (path == null) return;
    final size = File(path).existsSync() ? File(path).lengthSync() : 0;
    if (size == 0) return;
    _queue.add(path);
    _pendingCtrl.add(_queue.length);
    if (!_draining) _drainQueue();
  }

  /// Traite la file un segment à la fois, en tâche de fond — n'empêche pas
  /// l'utilisateur de continuer à réciter pendant la transcription.
  Future<void> _drainQueue() async {
    _draining = true;
    while (_queue.isNotEmpty) {
      final path = _queue.removeAt(0);
      await _transcribeAndEmit(path);
      _pendingCtrl.add(_queue.length);
    }
    _draining = false;
  }

  /// POC FastConformer CTC : SEUL modèle utilisé ici (whisper.cpp désactivé —
  /// voir échange utilisateur du 2026-07-04, concept "karaoké" à un seul
  /// modèle qui vérifie le texte connu en continu). Le scoring vert/rouge est
  /// géré par RecitationNotifier._realignFromFullText à partir du texte brut
  /// émis ici (pas d'émission de tokens individuels — voir même remarque dans
  /// le chemin streaming plus haut).
  Future<void> _transcribeAndEmit(String path) async {
    final loaded = await _fastConformer.ensureLoaded();
    if (!loaded) {
      debugPrint('[FastConformer] Modèle introuvable — segment ignoré');
      _rawCtrl.add('❌ Segment ignoré — modèle FastConformer non chargé');
      _deleteQuiet(path);
      return;
    }

    debugPrint('[FastConformer] → transcribe $path');
    final sw = Stopwatch()..start();
    try {
      final text = await _fastConformer.transcribe(path);
      debugPrint('[FastConformer] (${sw.elapsedMilliseconds} ms) : "$text"');
      if (text == null || text.isEmpty) {
        _rawCtrl.add('⚠️ (${sw.elapsedMilliseconds}ms) segment transcrit vide');
        return;
      }
      _rawCtrl.add(text);
      // Alignement forcé GOP one-shot sur ce même WAV (mode coach, segment
      // unique) : source de jugement primaire quand actif — le provider
      // ignore alors le diff textuel sur `text` ci-dessus.
      if (_alignmentActive) {
        final payload = await _fastConformer.alignFile(path);
        if (payload != null) _alignCtrl.add(payload);
      }
      await _saveStableCopy(path);
    } catch (e) {
      debugPrint('[FastConformer] Erreur decode segment : $e');
      _rawCtrl.add('❌ Erreur inférence CTC : $e');
    } finally {
      _deleteQuiet(path);
    }
  }

  /// Copie le segment vers un emplacement STABLE (survit à `_deleteQuiet(path)`
  /// juste après) — permet à l'UI d'utiliser l'audio de cette tentative une
  /// fois `finished`, ex. pour l'empreinte vocale (voir `lastAudioPath`).
  Future<void> _saveStableCopy(String path) async {
    try {
      final tmp = await getTemporaryDirectory();
      final stablePath = '${tmp.path}/last_recitation.wav';
      await File(path).copy(stablePath);
      _lastAudioPath = stablePath;
    } catch (e) {
      DiagnosticLog.log('ASR', 'Échec copie stable pour empreinte vocale : $e');
    }
  }

  void _deleteQuiet(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _levelTimer?.cancel();
    _levelCtrl.add(0);
    _sessionEnding = true;

    if (_continuous) {
      await _pcmSub?.cancel();
      _pcmSub = null;
      await _recorder.stop();
      await _continuousFeedTail;
      await _closeStreamingWavCapture();
      if (_usingCausalStreaming) {
        await _fastConformer.disposeStreaming();
        _usingCausalStreaming = false;
      }
      return;
    }

    // Coupe et met en file le dernier segment, PUIS attend que la file soit
    // vidée avant de retourner. Bug corrige le 2026-07-04 : sans ce await,
    // RecitationNotifier.stop() annule _rawSub/_tokenSub des que _verifier.stop()
    // retourne — hors _drainQueue() tourne en fire-and-forget (_enqueueIfValid
    // ne l'attend pas), donc la transcription qui arrive APRES coup (souvent
    // plusieurs centaines de ms plus tard) etait silencieusement perdue :
    // confirme sur device reel (logcat montrait la bonne transcription CTC,
    // "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ", mais l'ecran restait bloque sur
    // le message de chargement car plus personne n'ecoutait le stream).
    final path = await _recorder.stop();
    DiagnosticLog.log('ASR', '[$_kAsrVersion] stop() | dernier segment=$path');
    _enqueueIfValid(path);
    if (_draining) {
      await _pendingCtrl.stream.firstWhere((n) => n == 0);
    }
  }

  @override
  Future<void> stopIfCurrentSession(int expectedGeneration) {
    return _serialized(() async {
      if (_generation != expectedGeneration) {
        // Une session PLUS RECENTE a deja demarre (generation avancee)
        // depuis que l'appelant a capture expectedGeneration -- stop()/
        // resetBuffer() ici saboterait cette nouvelle session au lieu de
        // nettoyer la sienne. No-op : cf. Finding #1, revue de code
        // 2026-07-16.
        DiagnosticLog.log('ASR',
            'stopIfCurrentSession($expectedGeneration) ignore -- '
            'generation actuelle=$_generation (session perimee)');
        return;
      }
      await stop();
      await resetBuffer();
    });
  }

  @override
  void pauseCaptureSoft() {
    _appPaused = true;
    DiagnosticLog.log('ASR', 'pauseCaptureSoft() | chaine arretee (micro inchange)');
  }

  /// Pause matérielle lancée par [pauseCaptureForPlayback] et pas encore
  /// atterrie. Attendue par [resumeCaptureAfterPlayback] -- c'est ce qui rend
  /// le « ne pas attendre » sûr : la reprise ne peut jamais devancer la pause.
  Future<void>? _pausingForPlayback;

  @override
  void pauseCaptureForPlayback() {
    _appPaused = true; // synchrone : la chaine est arretee des cet instant
    DiagnosticLog.log('ASR', 'pauseCaptureForPlayback() | chaine arretee, '
        'pause micro lancee en tache de fond');
    _pausingForPlayback = _recorder.pause().catchError((Object e) {
      DiagnosticLog.log('ASR', 'pause micro (tache de fond) echouee : $e');
    });
  }

  @override
  Future<void> resumeCaptureAfterPlayback() async {
    final t0 = DateTime.now();
    try {
      await _pausingForPlayback; // la pause a atterri -> aucune course possible
    } catch (_) {
      // deja journalise par le catchError ci-dessus
    }
    _pausingForPlayback = null;
    try {
      await _recorder.resume();
    } catch (e) {
      DiagnosticLog.log('ASR', 'resume micro echoue : $e');
    }
    _appPaused = false;
    final ms = DateTime.now().difference(t0).inMilliseconds;
    DiagnosticLog.log('ASR', 'resumeCaptureAfterPlayback() | chaine relancee en ${ms}ms');
    // Verification NON bloquante : `isRecording()` peut couter plusieurs
    // secondes sur ce telephone (3,6 s mesure), on ne la met donc pas dans le
    // chemin -- mais on veut la trace, parce que "le micro n'est pas revenu"
    // est exactement le symptome "je n'arrive plus a continuer".
    unawaited(_recorder.isRecording().then((ok) {
      DiagnosticLog.log('ASR', ok
          ? 'controle post-correction : micro actif'
          : 'ALERTE controle post-correction : MICRO NON REPRIS');
    }).catchError((Object e) {
      DiagnosticLog.log('ASR', 'controle post-correction indisponible : $e');
    }));
  }

  @override
  void resumeCaptureSoft() {
    _appPaused = false;
    DiagnosticLog.log('ASR', 'resumeCaptureSoft() | chaine relancee');
  }

  @override
  Future<void> pauseCapture() async {
    _appPaused = true; // synchrone, avant tout await -- cf. commentaire _appPaused
    try {
      // `isRecording()` RETIRE du chemin (2026-07-25) : cet appel ne servait
      // qu'à enrichir la ligne de log, et il a coûté **3,6 s** sur une
      // correction reelle -- 3,6 s pour lire un booleen destine a un log. Les
      // deux lignes "apres pause" (deux appels plateforme de plus) sont
      // supprimees pour la meme raison. `pause()` est appele directement :
      // s'il n'y a rien a mettre en pause, le plugin ne fait rien.
      await _recorder.pause();
      DiagnosticLog.log('ASR', 'pauseCapture() | micro en pause');
    } catch (e) {
      DiagnosticLog.log('ASR', 'pauseCapture échec : $e');
    }
  }

  @override
  Future<void> finaliserPourPause() async {
    await _continuousFeedTail;
    await v2Terminer();
    DiagnosticLog.log('ASR', 'finaliserPourPause() | derniers mots tranches');
  }

  @override
  Future<void> resumeCapture() async {
    try {
      final wasPaused = await _recorder.isPaused();
      DiagnosticLog.log('ASR', 'resumeCapture() | isPaused=$wasPaused '
          'pcmSub actif=${_pcmSub != null} chunkCount avant=$_chunkCount');
      if (wasPaused) await _recorder.resume();
      _appPaused = false;
      DiagnosticLog.log('ASR', 'resumeCapture() | après resume : '
          'isRecording=${await _recorder.isRecording()} '
          'isPaused=${await _recorder.isPaused()}');
    } catch (e) {
      _appPaused = false; // ne pas rester bloque en silence sur une exception
      DiagnosticLog.log('ASR', 'resumeCapture échec : $e');
    }
  }

  @override
  Future<void> resetBuffer() async {
    await _continuousFeedTail;
    if (_usingCausalStreaming) {
      await _fastConformer.resetStreaming();
    } else {
      await _fastConformer.resetBuffered();
    }
  }

  @override
  Future<bool> ensureModelLoaded() => _fastConformer.ensureLoaded();

  @override
  Future<bool> ensureContinuousModelLoaded() async {
    final causalOk = await _fastConformer.ensureStreamingLoaded();
    return causalOk || await _fastConformer.ensureLoaded();
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    _pcmSub?.cancel();
    unawaited(_closeStreamingWavCapture());
    _recorder.dispose();
    unawaited(_fastConformer.dispose());
    unawaited(_fastConformer.disposeStreaming());
    _tokenCtrl.close();
    _levelCtrl.close();
    _rawCtrl.close();
    _pendingCtrl.close();
    _alignCtrl.close();
  }
}

// ── Simulateur (tests UI sans modèle) ────────────────────────────────────────

class MockRecitationVerifier implements RecitationVerifier {
  final _tokenCtrl = StreamController<RecognizedToken>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();
  Timer? _timer;
  Timer? _levelTimer;
  final _rng = Random();

  @override
  Stream<RecognizedToken> get tokens => _tokenCtrl.stream;
  @override
  Stream<double> get soundLevel => _levelCtrl.stream;
  @override
  Stream<String> get rawTranscript => const Stream.empty();
  @override
  Stream<({String committed, String preview})> get structuredTranscript =>
      const Stream.empty();
  @override
  Stream<int> get pendingSegments => const Stream.empty();
  @override
  Stream<int> get decrochage => const Stream.empty(); // pas de v2 en mock
  @override
  Stream<String> get v2DecodageLibre => const Stream.empty();
  @override
  Stream<({int de, int a})> get v2SautPresume => const Stream.empty();
  @override
  String? get lastAudioPath => null;
  @override
  Stream<AlignPayload> get alignedWords => const Stream.empty();

  @override
  Stream<List<({int index, String statut, String trace, String heard, Set<TajwidRule> detectedRules, bool tajwidFiable})>> get v2Statuses =>
      const Stream.empty();

  @override
  Future<void> v2Activer(bool actif, List<String> mots,
      {String mode = 'CTL',
      List<int> nonJugeables = const [],
      int depart = -1}) async {}
  @override
  Future<void> v2ExtendTarget(List<String> mots,
      {List<int> nonJugeables = const []}) async {}
  @override
  Future<String?> v2ExtraitVoix(int motDebut, int motFin) async => null;
  @override
  Future<bool> v2ReculerAncre(int mot) async => false;
  @override
  Future<void> v2Terminer() async {}
  @override
  Future<void> v2SetFusion(bool actif,
      {int preuves = 2,
      double pas = 4.0,
      double largeur = 4.0,
      double maxBloc = 10.0,
      double maxFusion = 18.0}) async {}
  @override
  bool get alignmentActive => false;
  @override
  // Mock : pas de modèle, donc pas de tête tajwid -- la vérification tajwid
  // reste inactive, ce qui est le comportement sûr (cf. unrealizedRulesFor).
  bool get hasRuleHead => false;
  @override
  String? get dernierEchecChargementModele => null;
  @override
  Future<void> setAlignmentAnchor(int index) async {}
  @override
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords,
      {List<int?>? refMinFrames}) async {}
  @override
  Future<bool> replaceAlignmentTarget(List<String> trainingWords, int anchor,
          {List<int?>? refMinFrames}) async =>
      false;

  @override
  Future<void> setClipCapture(String? dir) async {}

  @override
  Future<void> setLogEnabled(bool enabled) async {}
  @override
  Future<int> flushNativeTrace() async => 0;

  @override
  set wavRejoue(String? v) {}
  @override
  set noiseSuppress(bool value) {}
  @override
  Future<AlignPayload?> alignFile(String wavPath) async => null;
  @override
  Future<void> setNeverBlockAnchor(bool value) async {}

  int _generation = 0;
  @override
  int get sessionGeneration => _generation;

  /// Le mock ne détient jamais de micro.
  @override
  bool get captureEnCours => false;

  @override
  Future<void> stopIfCurrentSession(int expectedGeneration) async {
    if (_generation != expectedGeneration) return;
    await stop();
    await resetBuffer();
  }

  @override
  Future<void> start(List<String> expectedWords,
      {bool continuous = false, List<int?>? refMinFrames}) async {
    _generation++;
    var i = 0;
    _levelTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _levelCtrl.add(0.25 + _rng.nextDouble() * 0.75);
    });
    _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (i >= expectedWords.length) {
        t.cancel();
        return;
      }
      final roll = _rng.nextDouble();
      if (roll < 0.04) {
        // saut
      } else if (roll < 0.12) {
        _tokenCtrl.add(RecognizedToken('خطأ', confidence: 0.35));
      } else {
        _tokenCtrl.add(RecognizedToken(expectedWords[i], confidence: 0.92));
      }
      i++;
    });
  }

  @override
  Future<void> pauseCapture() async {}
  @override
  Future<void> finaliserPourPause() async {}
  @override
  void pauseCaptureSoft() {}
  @override
  void resumeCaptureSoft() {}
  @override
  void pauseCaptureForPlayback() {}
  @override
  Future<void> resumeCaptureAfterPlayback() async {}
  @override
  Future<void> resumeCapture() async {}
  @override
  Future<void> resetBuffer() async {}

  @override
  Future<bool> ensureModelLoaded() async => true;

  @override
  Future<bool> ensureContinuousModelLoaded() async => true;

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _levelTimer?.cancel();
    _levelCtrl.add(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levelTimer?.cancel();
    _tokenCtrl.close();
    _levelCtrl.close();
  }
}
