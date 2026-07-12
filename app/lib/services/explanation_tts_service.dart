import 'package:flutter_tts/flutter_tts.dart';

/// Lecture vocale on-device des explications, par langue (fr/en/ar) — utilise
/// le moteur TTS natif du téléphone (Google TTS), gratuit et offline.
///
/// Version « par langue » (demande utilisateur 2026-07-12) : une seule voix,
/// celle de la langue de l'explication affichée. Limite assumée : les citations
/// coraniques en arabe intégrées dans un texte fr/en seront mal prononcées par
/// la voix fr/en — traitement du texte mixte prévu dans une itération ultérieure
/// (cf. WORD_AYAH_EXPLANATION_PLAN.md, réserve « texte mixte »).
class ExplanationTtsService {
  static ExplanationTtsService? _instance;
  static ExplanationTtsService get instance =>
      _instance ??= ExplanationTtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  bool _configured = false;

  ExplanationTtsService._();

  bool get isSpeaking => _speaking;

  static const _locales = {'ar': 'ar', 'fr': 'fr-FR', 'en': 'en-US'};

  /// Callback appelé quand la lecture démarre/s'arrête (pour rafraîchir l'état
  /// du bouton). Réassigné par le widget courant.
  void Function()? onStateChanged;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.setSpeechRate(0.45); // un peu plus lent : lecture pédagogique
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      _speaking = false;
      onStateChanged?.call();
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      onStateChanged?.call();
    });
    _tts.setErrorHandler((_) {
      _speaking = false;
      onStateChanged?.call();
    });
    _configured = true;
  }

  /// Lit [text] dans la voix de [lang] ('ar'/'fr'/'en'). Coupe toute lecture
  /// en cours d'abord. Sans effet si [text] est vide.
  Future<void> speak(String text, String lang) async {
    await _ensureConfigured();
    await _tts.stop();
    final cleaned = cleanForTts(text, lang);
    if (cleaned.isEmpty) return;
    await _tts.setLanguage(_locales[lang] ?? 'fr-FR');
    _speaking = true;
    onStateChanged?.call();
    await _tts.speak(cleaned);
  }

  // Plages de caractères arabes (lettres + présentation), pour isoler/retirer
  // l'arabe dans un texte latin (fr/en) et inversement.
  static final _arabicRun = RegExp(
      r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]+');
  static final _latinRun = RegExp(r'[A-Za-zÀ-ÿ]+');
  // Marqueurs de notes de bas de page « ١ », « 2 »… et références [sourate/آية].
  static final _footnote = RegExp(r'[«»][\s\d٠-٩]*[«»]');
  static final _bracketRef = RegExp(r'\[[^\]]*[/／][^\]]*\]');
  static final _ornaments = RegExp(r'[﴾﴿]');
  static final _multiSpace = RegExp(r'\s{2,}');

  /// Prépare le texte pour une lecture TTS propre dans [lang] :
  /// - fr/en : retire les citations coraniques en arabe (la voix latine les
  ///   prononcerait mal) et les ornements, ne garde que l'explication latine.
  /// - ar : retire les libellés/mots latins (ex. noms de sources translittérés)
  ///   pour éviter que la voix arabe ne butte dessus.
  /// - toutes langues : retire les marqueurs de notes «٢», les références
  ///   [sourate/آية], les ornements ﴿﴾, et normalise les espaces.
  static String cleanForTts(String text, String lang) {
    var t = text;
    t = t.replaceAll(_footnote, ' ');
    t = t.replaceAll(_bracketRef, ' ');
    t = t.replaceAll(_ornaments, ' ');
    if (lang == 'ar') {
      t = t.replaceAll(_latinRun, ' ');
    } else {
      t = t.replaceAll(_arabicRun, ' ');
    }
    t = t.replaceAll(_multiSpace, ' ').trim();
    return t;
  }

  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
    onStateChanged?.call();
  }
}
