import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/recitation_state.dart';
import '../models/verse.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart';
import '../services/fastconformer_verifier.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import 'tajweed_text.dart';

/// Règles tajwid affichables : classe quran.com -> (couleur, nom, explication).
/// Les couleurs répliquent celles de tajweed_text.dart (source de vérité
/// visuelle : le texte coloré au-dessus de la légende).
class _TajwidRule {
  final Color color;
  final String name;
  final String explanation;
  const _TajwidRule(this.color, this.name, this.explanation);
}

// Couleurs et noms de classe IDENTIQUES à tajweed_text.dart (source de vérité
// unique — voir _classColors là-bas pour la provenance exacte et la note de
// correction 2026-07-06 : orthographes de classe réelles + teintes plus
// vives). Gris de référence défini une seule fois pour le tri ci-dessous.
const _kGray = Color(0xFF77766C);

const _kRules = <String, _TajwidRule>{
  'madda_necessary': _TajwidRule(Color(0xFFA13420), 'Madd — 6 temps (obligatoire)',
      'Allongement obligatoire de 6 temps (madd lâzim).'),
  'madda_obligatory': _TajwidRule(Color(0xFFE8391F), 'Madd — 4 ou 5 temps (obligatoire)',
      'Allongement obligatoire de 4 à 5 temps.'),
  'madda_permissible': _TajwidRule(Color(0xFFEB7A1E), 'Madd — 2, 4 ou 6 temps (permis)',
      'Allongement de 2, 4 ou 6 temps selon l\'école de lecture.'),
  'madda_normal': _TajwidRule(Color(0xFFEB7A1E), 'Madd — 2, 4 ou 6 temps (permis)',
      'Allongement de 2, 4 ou 6 temps selon l\'école de lecture.'),
  'ghunnah': _TajwidRule(Color(0xFF2E9E4F), 'Ghunna / Ikhfâ\'',
      'Son nasal tenu environ 2 temps (noûn/mîm doublé), ou dissimulation avec nasalisation.'),
  'ikhafa': _TajwidRule(Color(0xFF2E9E4F), 'Ikhfâ\' (dissimulation)',
      'Le noûn sâkin/tanwîn se prononce "caché", entre le noûn et la lettre suivante, avec nasalisation.'),
  'ikhafa_shafawi': _TajwidRule(Color(0xFF2E9E4F), 'Ikhfâ\' shafawî',
      'Le mîm sâkin devant bâ\' se prononce légèrement dissimulé, avec nasalisation.'),
  'idgham_ghunnah': _TajwidRule(Color(0xFF2E9E4F), 'Idghâm avec ghunna',
      'Le noûn sâkin/tanwîn s\'assimile à la lettre suivante (ي ن م و) avec nasalisation.'),
  'idgham_shafawi': _TajwidRule(Color(0xFF2E9E4F), 'Idghâm shafawî',
      'Le mîm sâkin s\'assimile au mîm suivant, avec nasalisation.'),
  'iqlab': _TajwidRule(Color(0xFF2E9E4F), 'Iqlâb (conversion)',
      'Le noûn sâkin/tanwîn devient mîm devant la lettre bâ\', avec nasalisation.'),
  'idgham_wo_ghunnah': _TajwidRule(_kGray, 'Idghâm sans ghunna',
      'Le noûn sâkin/tanwîn s\'assimile complètement à la lettre suivante (ل ر), sans nasalisation.'),
  'idgham_mutajanisayn': _TajwidRule(_kGray, 'Idghâm mutajânisayn',
      'Deux lettres de même point d\'articulation : la première s\'assimile à la seconde.'),
  'idgham_mutaqaribayn': _TajwidRule(_kGray, 'Idghâm mutaqâribayn',
      'Deux lettres proches : la première s\'assimile à la seconde.'),
  'qalaqah': _TajwidRule(Color(0xFF0091EA), 'Qalqala (rebond)',
      'Rebond sonore sur ق ط ب ج د quand elles portent un soukoûn.'),
  'ham_wasl': _TajwidRule(_kGray, 'Hamzat al-wasl',
      'Ne se prononce qu\'en début de lecture — s\'élide quand on enchaîne depuis le mot précédent.'),
  'laam_shamsiyah': _TajwidRule(_kGray, 'Lâm solaire',
      'Le lâm de "ال" ne se prononce pas : la lettre suivante est doublée à la place.'),
  'slnt': _TajwidRule(_kGray, 'Lettre muette',
      'S\'écrit mais ne se prononce pas.'),
};

/// Fiche d'aide affichée au tap sur un mot orange/rouge (Contrôle ou Karaoké) :
/// le verset complet coloré selon les règles de tajwid, la légende des règles
/// présentes, un bouton pour écouter le verset par le réciteur, et — si
/// [wordIndex] est fourni — une boucle de correction interactive (demande
/// utilisateur 2026-07-05) : écouter, se réenregistrer sur CE mot, valider.
void showTajwidHelpSheet(
  BuildContext context,
  WidgetRef ref, {
  required Verse verse,
  required List<Verse> playlist,
  String? focusWord,
  int? wordIndex,
  int? localWordIndex,
}) {
  // Règles réellement présentes dans CE verset (via les classes du HTML).
  // La vraie balise est `<tajweed class=X>` (attribut SANS guillemets, voir
  // tajweed_text.dart) — pas `<span class="X">` comme supposé initialement,
  // ce qui faisait que cette légende ne détectait jamais rien.
  final classes = RegExp(r'class=(?:"([^"]*)"|([^\s">]+))')
      .allMatches(verse.textUthmaniTajweed ?? '')
      .map((m) => m.group(1) ?? m.group(2) ?? '')
      .toSet();
  final rules = [
    for (final c in classes)
      if (_kRules.containsKey(c) && _kRules[c]!.color != _kGray)
        _kRules[c]!,
    // Règles "grises" (wasl, lâm solaire, muettes) en fin de liste.
    for (final c in classes)
      if (_kRules.containsKey(c) && _kRules[c]!.color == _kGray)
        _kRules[c]!,
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Verset ${verse.key}',
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.inkLight),
                ),
                if (focusWord != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.tajwidMadd.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      focusWord,
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.scheherazadeNew(
                          fontSize: 18, color: AppColors.ink),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: TajweedText(
                        textUthmani: verse.textUthmani,
                        textUthmaniTajweed: verse.textUthmaniTajweed,
                        fontSize: 26,
                      ),
                    ),
                    if (rules.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'RÈGLES DANS CE VERSET',
                        style: GoogleFonts.manrope(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkLight),
                      ),
                      const SizedBox(height: 8),
                      for (final r in rules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: r.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.manrope(
                                        fontSize: 12.5,
                                        height: 1.45,
                                        color: AppColors.ink),
                                    children: [
                                      TextSpan(
                                        text: '${r.name} — ',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      TextSpan(text: r.explanation),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (localWordIndex != null && focusWord != null) ...[
                      const SizedBox(height: 18),
                      _ListenRangeControl(
                        verse: verse,
                        localWordIndex: localWordIndex,
                      ),
                    ],
                    if (wordIndex != null && focusWord != null) ...[
                      const SizedBox(height: 18),
                      _CorrectionLoop(wordIndex: wordIndex, focusWord: focusWord),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Consumer(builder: (ctx2, ref2, _) {
              final reciter = ref2.watch(playerProvider).reciter;
              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    ref.read(playerProvider.notifier).play(verse, playlist);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'Écouter — ${reciter.nameFr}',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}

/// Choix de la portée (nombre de mots autour du mot tapé) pour l'écoute
/// manuelle du réciteur (demande utilisateur 2026-07-06) : quand la
/// correction automatique est désactivée, taper sur un mot rouge/orange doit
/// permettre de déclencher soi-même l'audio, avec un choix de portée — juste
/// ce mot, +le mot précédent (comportement par défaut de la correction
/// automatique), ou +le mot précédent ET le suivant.
class _ListenRangeControl extends ConsumerStatefulWidget {
  final Verse verse;
  final int localWordIndex;
  const _ListenRangeControl({required this.verse, required this.localWordIndex});

  @override
  ConsumerState<_ListenRangeControl> createState() => _ListenRangeControlState();
}

enum _Range { wordOnly, withPrevious, withBoth }

class _ListenRangeControlState extends ConsumerState<_ListenRangeControl> {
  _Range _range = _Range.withPrevious;
  bool _playing = false;

  (int, int) get _bounds => switch (_range) {
        _Range.wordOnly => (0, 0),
        _Range.withPrevious => (1, 0),
        _Range.withBoth => (1, 1),
      };

  Future<void> _play() async {
    setState(() => _playing = true);
    final reciter = ref.read(playerProvider).reciter;
    final (before, after) = _bounds;
    try {
      await WordCorrectionAudio.playWordRange(
        widget.verse,
        reciter,
        errorWordIndex: widget.localWordIndex,
        wordsBefore: before,
        wordsAfter: after,
      );
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream200,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÉCOUTER LA PRONONCIATION',
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.green700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Ce mot'),
                selected: _range == _Range.wordOnly,
                onSelected: (_) => setState(() => _range = _Range.wordOnly),
              ),
              ChoiceChip(
                label: const Text('+ mot précédent'),
                selected: _range == _Range.withPrevious,
                onSelected: (_) => setState(() => _range = _Range.withPrevious),
              ),
              ChoiceChip(
                label: const Text('+ précédent et suivant'),
                selected: _range == _Range.withBoth,
                onSelected: (_) => setState(() => _range = _Range.withBoth),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.green700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _playing ? null : _play,
              icon: Icon(
                _playing ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
                color: AppColors.green700,
              ),
              label: Text(
                _playing ? 'Lecture…' : 'Écouter',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: AppColors.green700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LoopState { idle, recording, analyzing, success, retry }

/// Boucle "réessaie ce mot" : enregistre un court passage, le transcrit
/// isolément (moteur FastConformer déjà chargé, mono-shot — pas le flux
/// bufferisé continu), compare au mot attendu, et si ça correspond, marque le
/// mot corrigé dans l'état de la récitation (verrouillé vert définitivement).
class _CorrectionLoop extends ConsumerStatefulWidget {
  final int wordIndex;
  final String focusWord;
  const _CorrectionLoop({required this.wordIndex, required this.focusWord});

  @override
  ConsumerState<_CorrectionLoop> createState() => _CorrectionLoopState();
}

class _CorrectionLoopState extends ConsumerState<_CorrectionLoop> {
  final _recorder = AudioRecorder();
  final _engine = FastConformerVerifier();
  _LoopState _state = _LoopState.idle;
  String? _heardText;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return;
    final ok = await _engine.ensureLoaded();
    if (!ok) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/word_retry_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    setState(() => _state = _LoopState.recording);
  }

  Future<void> _stopAndValidate() async {
    final path = await _recorder.stop();
    setState(() => _state = _LoopState.analyzing);
    if (path == null) {
      setState(() => _state = _LoopState.idle);
      return;
    }
    final text = await _engine.transcribe(path);
    try {
      await File(path).delete();
    } catch (_) {}

    final words = ref.read(recitationProvider).words;
    if (widget.wordIndex >= words.length) return;
    final expected = words[widget.wordIndex];

    final heardNorm = ArabicNormalizer.normalize(text ?? '');
    final matches = heardNorm.isNotEmpty &&
        ArabicNormalizer.similarity(heardNorm, expected.normalized) >= 0.75;

    setState(() {
      _heardText = (text == null || text.trim().isEmpty) ? '(rien entendu)' : text.trim();
      _state = matches ? _LoopState.success : _LoopState.retry;
    });

    if (matches) {
      ref.read(recitationProvider.notifier).markWordCorrected(widget.wordIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RÉESSAYER CE MOT',
            style: GoogleFonts.manrope(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.green700,
            ),
          ),
          const SizedBox(height: 8),
          if (_state == _LoopState.success)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Corrigé — entendu : "$_heardText"',
                      style: GoogleFonts.manrope(fontSize: 13, color: AppColors.green700)),
                ),
              ],
            )
          else ...[
            if (_state == _LoopState.retry)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Pas encore — entendu : "$_heardText". Réessaie, à ton rythme.',
                  style: GoogleFonts.manrope(fontSize: 12.5, color: const Color(0xFFb00020)),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                      color: _state == _LoopState.recording
                          ? const Color(0xFFb00020)
                          : AppColors.green700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _state == _LoopState.analyzing
                    ? null
                    : (_state == _LoopState.recording ? _stopAndValidate : _startRecording),
                icon: Icon(
                  _state == _LoopState.recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                  color: _state == _LoopState.recording ? const Color(0xFFb00020) : AppColors.green700,
                ),
                label: Text(
                  _state == _LoopState.analyzing
                      ? 'Analyse en cours…'
                      : (_state == _LoopState.recording
                          ? 'Terminer l\'enregistrement'
                          : 'S\'enregistrer sur ce mot'),
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: _state == _LoopState.recording
                          ? const Color(0xFFb00020)
                          : AppColors.green700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
