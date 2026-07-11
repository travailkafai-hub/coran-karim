import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

/// Coach IA — explique un mot/verset via Gemma 4 E2B fine-tuné (LoRA
/// "tutor-v6", Coran + hadith), embarqué on-device via LiteRT-LM.
///
/// Même convention que [FastConformerVerifier] : le modèle n'est pas
/// bundlé dans l'APK (trop gros, ~2,5 Go), il est déployé côté
/// app-support ; son absence n'est pas une erreur, juste "pas encore prêt"
/// (ensureLoaded()/explainVerse() renvoient false/null plutôt que de lever).
class TutorLlmService {
  TutorLlmService._();
  static final TutorLlmService instance = TutorLlmService._();

  static const _kModelSubdir = 'models/gemma-4-e2b-tutor';
  static const _kModelFile = 'model.litertlm';

  // 2026-07-10 : deux tours d'essai réels ont montré que trop s'écarter du
  // prompt système EXACT du dataset SFT (gemma_tutor_sft.jsonl) fait sortir
  // ce petit LoRA (r=16) de sa distribution d'entraînement -> répétitions en
  // boucle, hors-sujet. On garde donc le prompt système d'origine tel quel,
  // et on se contente d'AJOUTER la consigne anti-hallucination (les
  // citations bibliques/inventées observées au premier essai) plutôt que de
  // le réécrire entièrement.
  static const _systemInstruction =
      'Tu es un tuteur spécialisé en mémorisation et compréhension du Coran. '
      'Tu aides les apprenants francophones à comprendre le sens des versets, '
      'leur contexte et leur portée spirituelle. Tes réponses sont précises, '
      'bienveillantes et pédagogiques. '
      'Tu n\'inventes et ne cites jamais de référence, hadith ou source '
      'que le verset donné dans la question.';

  InferenceModel? _model;
  bool _loaded = false;

  Future<String> _modelPath() async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/$_kModelSubdir/$_kModelFile';
  }

  /// Charge/installe le modèle si nécessaire. Idempotent. Retourne false si
  /// le fichier n'est pas encore déployé sur l'appareil (pas une erreur).
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    final path = await _modelPath();
    if (!await File(path).exists()) {
      debugPrint('[TutorLlm] Modèle absent ($path) — ignoré');
      return false;
    }
    try {
      if (!FlutterGemma.hasActiveModel()) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        ).fromFile(path).install();
      }
      _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
      _loaded = true;
      debugPrint('[TutorLlm] Modèle chargé');
      return true;
    } catch (e) {
      debugPrint('[TutorLlm] Échec chargement modèle : $e');
      return false;
    }
  }

  /// Explique un verset. Deux registres distincts, sur demande explicite de
  /// l'utilisateur (2026-07-10 — la page de lecture partait sur "comment
  /// mémoriser" alors qu'on y veut le SENS) :
  /// - [focusWord] : un mot précis tapé par l'utilisateur (page de lecture
  ///   Mushaf) -> registre SENS ("Quel est le sens du mot « X » dans le
  ///   verset ..."), prioritaire sur [mistakenWords] si les deux sont fournis.
  /// - [mistakenWords] : mot(s) réellement ratés en récitation (onglet Coach
  ///   IA, alimenté par le journal d'erreurs) -> registre MÉMORISATION
  ///   ("Je mémorise le Coran... que j'ai du mal à retenir").
  /// Ni l'un ni l'autre -> sens général du verset.
  /// Retourne null en cas d'échec (modèle non chargé, erreur d'inférence).
  ///
  /// Les deux gabarits restent volontairement proches du dataset SFT
  /// (gemma_tutor_sft.jsonl : « Quel est le sens du verset X:Y : » et
  /// « Je mémorise le Coran. Explique-moi en français le verset X:Y : » sont
  /// tous deux des gabarits réellement entraînés) : un essai antérieur avec
  /// un prompt entièrement reformulé a fait sortir ce LoRA (r=16, peu de
  /// données) de sa distribution d'entraînement -> répétitions, hors-sujet.
  ///
  /// Passe par la Session brute (createSession), pas l'API Chat/Conversation
  /// haut-niveau : celle-ci échoue sur les .litertlm Gemma 4 E2B exportés via
  /// le flux public litert-torch (« Failed to start streaming (code: 13) »,
  /// bug connu upstream — cf. google-ai-edge/LiteRT-LM#2078). Une session
  /// neuve par appel : chaque explication est une question isolée, pas une
  /// conversation à historique.
  Future<String?> explainVerse({
    required int surahNumber,
    required int ayahNumber,
    required String verseText,
    List<String>? mistakenWords,
    String? focusWord,
  }) async {
    if (!await ensureLoaded()) return null;
    final String prompt;
    if (focusWord != null && focusWord.trim().isNotEmpty) {
      prompt = 'Quel est le sens du mot « ${focusWord.trim()} » dans le '
          'verset $surahNumber:$ayahNumber :\n$verseText';
    } else {
      final words = mistakenWords?.where((w) => w.trim().isNotEmpty).toSet();
      if (words != null && words.isNotEmpty) {
        prompt = 'Je mémorise le Coran. Explique-moi en français le verset '
            '$surahNumber:$ayahNumber, en particulier le(s) mot(s) '
            '${words.join('، ')} que j\'ai du mal à retenir :\n$verseText';
      } else {
        prompt = 'Quel est le sens du verset $surahNumber:$ayahNumber '
            ':\n$verseText';
      }
    }
    InferenceModelSession? session;
    try {
      // topK=1 (défaut du plugin) = décodage glouton pur -> boucles de
      // répétition observées au 2e essai. Un peu d'échantillonnage réel
      // (topK/topP) atténue ça, mais n'élimine pas complètement la
      // dégénérescence en répétition sur ce petit LoRA (r=16) quantifié
      // INT4 — aucun paramètre de pénalité de répétition n'est exposé par
      // flutter_gemma_litertlm (vérifié dans ses bindings FFI). Palliatif :
      // couper court avant que la boucle ne s'installe (observée après
      // ~2-3 phrases cohérentes dans les essais réels) plutôt que de
      // laisser tourner jusqu'à 300 tokens de répétition.
      session = await _model!.createSession(
        systemInstruction: _systemInstruction,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 120,
      );
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await session.getResponse();
      return _truncateToFirstParagraph(response);
    } catch (e) {
      debugPrint('[TutorLlm] Échec génération : $e');
      return null;
    } finally {
      await session?.close();
    }
  }

  // Palliatif emprunté au projet "Harcèlement" (détox Gemma 3 1B, mémoire
  // 2026-06 : "hallucinations après la première phrase (junk tokens)... couper
  // à la première phrase terminée suffit") — le MÊME motif s'observe ici :
  // le premier paragraphe est systématiquement cohérent, tout ce qui suit la
  // première ligne vide dégénère en répétition de variantes parenthétiques
  // ("(Pour les deux)...", "(autre formule)..."). Plutôt que de risquer
  // d'afficher la boucle, on ne garde que le premier paragraphe.
  String _truncateToFirstParagraph(String text) {
    final trimmed = text.trim();
    final idx = trimmed.indexOf('\n\n');
    return idx == -1 ? trimmed : trimmed.substring(0, idx).trim();
  }
}
