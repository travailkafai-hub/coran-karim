import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/cascade_explanation.dart';
import '../models/verse.dart';
import '../providers/app_settings_provider.dart';
import '../services/quran_api.dart';
import '../services/explanation_tts_service.dart';
import '../services/quran_sciences_service.dart';
import '../services/recitation_error_log_service.dart';
// `services/tutor_llm_service.dart` a été retiré le 2026-08-10, avec les
// paquets flutter_gemma / flutter_gemma_litertlm : ~90 Mo de bibliothèques
// natives par architecture pour un modèle qui n'a jamais été livré.
// Cf. `_loadGemmaFallback` plus bas pour le détail et ce que ça libère.
import '../theme/app_theme.dart';

/// Ouvre la feuille d'explication Coach IA pour un verset (ou un mot précis
/// dedans) — point d'entrée partagé (onglet "مدرّبي", barre d'action du
/// Mushaf, et tap sur un mot dans le Mushaf — demande utilisateur
/// 2026-07-10).
///
/// Source de l'explication (demande utilisateur 2026-07-12,
/// WORD_AYAH_EXPLANATION_PLAN.md) : d'ABORD la cascade offline
/// (`QuranSciencesService`, texte de tafsir déjà écrit/sourcé, paliers
/// synthétique -> érudit, zéro génération) -- le tuteur Gemma (LLM) ne sert
/// de repli QUE si les données offline ne sont pas déployées sur cet
/// appareil ou n'ont rien pour ce verset/cette langue.
///
/// [focusWord] : mot précis à expliquer (registre SENS, ex. tap sur un mot
/// pendant la lecture) — prioritaire sur le journal d'erreurs. [focusWordIndex] :
/// sa position 0-based dans le découpage de la sourate (nécessaire pour lever
/// toute ambiguïté quand le même mot apparaît plusieurs fois dans un verset,
/// cf. `QuranSciencesService.explainWord`).
/// [useErrorLog] : si true (défaut, onglet Coach IA), le journal d'erreurs
/// de récitation pour cette aya oriente l'explication Gemma (repli) vers le
/// registre MÉMORISATION. Le Mushaf passe `false` : lire un verset n'est pas
/// une session de révision d'erreur, même si ce verset a été raté par ailleurs.
void showCoachExplanation(
  BuildContext context, {
  required int surahNumber,
  required int ayahNumber,
  required String title,
  String? focusWord,
  int? focusWordIndex,
  String? testMistakenWord,
  bool useErrorLog = true,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => CoachExplanationSheet(
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      title: title,
      focusWord: focusWord,
      focusWordIndex: focusWordIndex,
      testMistakenWord: testMistakenWord,
      useErrorLog: useErrorLog,
    ),
  );
}

class CoachExplanationSheet extends ConsumerStatefulWidget {
  final int surahNumber;
  final int ayahNumber;
  final String title;
  final String? focusWord;
  final int? focusWordIndex;
  // Mot fixe utilisé uniquement par le bouton "Tester le Coach IA" (pas
  // d'erreur réelle journalisée pour ce verset de démo).
  final String? testMistakenWord;
  final bool useErrorLog;
  const CoachExplanationSheet({
    super.key,
    required this.surahNumber,
    required this.ayahNumber,
    required this.title,
    this.focusWord,
    this.focusWordIndex,
    this.testMistakenWord,
    this.useErrorLog = true,
  });

  @override
  ConsumerState<CoachExplanationSheet> createState() =>
      _CoachExplanationSheetState();
}

class _CoachExplanationSheetState extends ConsumerState<CoachExplanationSheet> {
  static const _kLangLabels = {'ar': 'العربية', 'fr': 'Français', 'en': 'English'};

  CascadeExplanation? _cascade;
  int _expandedTier = 1;
  String? _gemmaExplanation; // repli, seulement si _cascade reste null
  String? _error;
  bool _loading = true;

  final _tts = ExplanationTtsService.instance;

  @override
  void initState() {
    super.initState();
    _tts.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _load();
  }

  @override
  void dispose() {
    _tts.stop();
    _tts.onStateChanged = null;
    super.dispose();
  }

  /// Texte lu à voix haute : les paliers actuellement visibles (ce qui est à
  /// l'écran) pour une explication en cascade, sinon le repli Gemma. Le
  /// nettoyage par langue (retrait des citations arabes en fr/en, notes, etc.)
  /// est fait dans ExplanationTtsService.cleanForTts.
  String _readableText() {
    if (_cascade != null) {
      final buf = StringBuffer();
      for (var t = 1; t <= _expandedTier; t++) {
        for (final src in _cascade!.tier(t) ?? const []) {
          buf.writeln(src.text);
        }
      }
      return buf.toString();
    }
    return _gemmaExplanation ?? '';
  }

  Future<void> _toggleSpeak() async {
    if (_tts.isSpeaking) {
      await _tts.stop();
    } else {
      await _tts.speak(_readableText(), ref.read(explanationLanguageProvider));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cascade = null;
      _gemmaExplanation = null;
      _expandedTier = 1;
    });
    final lang = ref.read(explanationLanguageProvider);
    try {
      CascadeExplanation? cascade;
      if (widget.focusWord != null) {
        cascade = await QuranSciencesService.instance.explainWord(
          widget.surahNumber,
          widget.ayahNumber,
          widget.focusWordIndex ?? -1,
          widget.focusWord!,
          lang,
        );
        // Pas de dictionnaire mot-à-mot dans cette langue (fréquent en
        // FR/EN, cf. plan) -- repli sur l'explication du VERSET entier,
        // toujours plus utile qu'un vide pur.
        cascade ??= await QuranSciencesService.instance
            .explainAyah(widget.surahNumber, widget.ayahNumber, lang);
      } else {
        cascade = await QuranSciencesService.instance
            .explainAyah(widget.surahNumber, widget.ayahNumber, lang);
      }
      if (!mounted) return;
      if (cascade != null) {
        setState(() {
          _cascade = cascade;
          _loading = false;
        });
        return;
      }
      // Repli Gemma : données offline absentes de l'appareil ou rien pour
      // ce verset/cette langue.
      await _loadGemmaFallback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Repli quand la cascade de tafsir n'a rien pour ce passage.
  ///
  /// ── LE TUTEUR GEMMA A ÉTÉ RETIRÉ (2026-08-10) ────────────────────────────
  ///
  /// Cette méthode appelait `TutorLlmService.instance.explainVerse(...)`, qui
  /// faisait tourner un modèle Gemma sur l'appareil. Retiré avec les paquets
  /// `flutter_gemma` et `flutter_gemma_litertlm`.
  ///
  /// POURQUOI. Le modèle n'a jamais été livré : `ensureLoaded()` cherchait un
  /// `.litertlm` dans le stockage privé, ne le trouvait pas, journalisait
  /// « Modèle absent — ignoré », et `explainVerse` rendait `null`. Aucun
  /// utilisateur n'a donc jamais vu une seule ligne produite par ce modèle.
  ///
  /// Ce qu'il coûtait quand même, mesuré sur l'APK release du 2026-08-10 :
  /// **~90 Mo de bibliothèques natives par architecture** — `libLiteRtLm.so`
  /// (24,8 Mo), quatre `libQnnHtpV*Skel.so` (42,4 Mo à elles seules), les deux
  /// accélérateurs LiteRT (15,7 Mo), `libGemmaModelConstraintProvider.so`,
  /// `libQnnSystem.so`. Plus de la moitié de la charge utile arm64, pour du
  /// code qui ne s'exécutait jamais.
  ///
  /// Ce que ça libère : le modèle ASR quantifié pourrait tenir dans le paquet
  /// lui-même au lieu d'un pack séparé (cf. PUBLICATION_PLAY.md §2.2).
  ///
  /// LA CASCADE DE TAFSIR, ELLE, RESTE (`QuranSciencesService`) : c'est la
  /// vraie source d'explications, du texte écrit et sourcé, et le jour où ses
  /// fichiers sont livrés cet écran fonctionne. Le message ci-dessous n'est
  /// donc pas un aveu d'échec, c'est l'état exact : rien de sourcé pour ce
  /// passage sur cet appareil.
  Future<void> _loadGemmaFallback() async {
    if (!mounted) return;
    setState(() {
      _gemmaExplanation =
          AppLocalizations.of(context)!.coachExplanationNoneAvailable;
      _loading = false;
    });
  }

  void _changeLanguage(String lang) {
    _tts.stop(); // ne pas continuer à lire l'ancienne langue
    ref.read(explanationLanguageProvider.notifier).set(lang);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final lang = ref.watch(explanationLanguageProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: GoogleFonts.scheherazadeNew(
                            fontSize: 20, color: AppColors.green900)),
                  ),
                  // Lecture vocale on-device (voix = langue choisie). Masqué
                  // tant que rien n'est chargé (pas de texte à lire).
                  if (!_loading && _error == null &&
                      (_cascade != null || _gemmaExplanation != null))
                    IconButton(
                      tooltip: _tts.isSpeaking ? t.coachExplanationStop : t.coachExplanationListen,
                      onPressed: _toggleSpeak,
                      icon: Icon(
                        _tts.isSpeaking
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        color: AppColors.green700,
                      ),
                    ),
                  _languageSelector(t, lang),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(t.coachExplanationError(_error!),
                    style: const TextStyle(color: AppColors.green700))
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.green700)),
                )
              else if (_cascade != null)
                _cascadeView(t, _cascade!)
              else
                Text(_gemmaExplanation ?? '',
                    style:
                        const TextStyle(color: AppColors.green900, height: 1.4)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageSelector(AppLocalizations t, String current) {
    return PopupMenuButton<String>(
      tooltip: t.coachExplanationLanguageTooltip,
      initialValue: current,
      onSelected: _changeLanguage,
      itemBuilder: (_) => _kLangLabels.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.green900.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_kLangLabels[current] ?? current,
              style: const TextStyle(color: AppColors.green900, fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18, color: AppColors.green900),
        ]),
      ),
    );
  }

  /// Cascade synthétique -> érudit : palier 1 toujours visible, un bouton
  /// "approfondir" dévoile le palier suivant (jamais tout d'un coup, cf. le
  /// plan). Source toujours citée, y compris au palier 1.
  Widget _cascadeView(AppLocalizations t, CascadeExplanation cascade) {
    final visibleTiers = [
      for (var tier = 1; tier <= _expandedTier; tier++)
        if (cascade.tier(tier) != null) tier
    ];
    final hasMore = _expandedTier < cascade.maxTier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cascade.root != null) ...[
          Text(t.coachExplanationRoot(cascade.root!),
              style: const TextStyle(
                  color: AppColors.brass,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 10),
        ],
        for (final tier in visibleTiers) ...[
          for (final src in cascade.tier(tier)!) ...[
            Text(src.source,
                style: const TextStyle(
                    color: AppColors.brass,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
            const SizedBox(height: 4),
            Text(src.text,
                style:
                    const TextStyle(color: AppColors.green900, height: 1.5)),
            const SizedBox(height: 14),
          ],
        ],
        if (hasMore)
          TextButton.icon(
            onPressed: () => setState(() => _expandedTier++),
            icon: const Icon(Icons.expand_more, color: AppColors.green700),
            label: Text(t.coachExplanationExpand,
                style: const TextStyle(color: AppColors.green700)),
          ),
      ],
    );
  }
}
