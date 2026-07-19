import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import '../data/voice_calibration_words.dart';
import '../services/voice_lora_clip_service.dart';
import '../theme/app_theme.dart';

/// Calibration voix personnelle par mots confusables (FONCTIONNALITES_FUTURES.md
/// section 8ter, 2026-07-14) : demande explicitement à l'utilisateur de dire
/// chaque mot [kVoiceCalibrationPairs] deux fois -- correctement, puis en
/// substituant DÉLIBÉRÉMENT la lettre confusable (ex: ص au lieu de س) -- pour
/// nourrir le mini-LoRA personnel (`finetune_fastconformer_lora.py`, niveau 3,
/// PC-assisté, déjà en place depuis le 2026-07-12) avec des exemples où le
/// texte associé au clip EST ce qui a été réellement prononcé, jamais le texte
/// canonique -- même principe que la capture de clips de récitation vérifiés
/// (`VoiceLoraClipService`), réutilisée ici telle quelle.
///
/// Contexte : constat réel le 2026-07-14 (substitution ص/س sur Sourate An-Nas,
/// gop=0.00 partout, aucune détection) -- le modèle actuel ne distingue pas
/// ces lettres car il n'a jamais vu, à l'entraînement, de prononciation
/// volontairement fautive. Cette calibration ne corrige QUE la sensibilité de
/// CET utilisateur (adaptateur LoRA personnel, base gelée) -- complémentaire
/// à une éventuelle refonte du modèle de base (§8bis), pas un substitut.
class VoiceCalibrationScreen extends StatefulWidget {
  const VoiceCalibrationScreen({super.key});

  @override
  State<VoiceCalibrationScreen> createState() =>
      _VoiceCalibrationScreenState();
}

enum _Step { introCorrect, introWrong, done }

class _VoiceCalibrationScreenState extends State<VoiceCalibrationScreen> {
  final _recorder = AudioRecorder();
  final _clipService = VoiceLoraClipService();

  int _pairIndex = 0;
  _Step _step = _Step.introCorrect;
  bool _recording = false;
  bool _saving = false;
  String? _tempDir;
  final List<({String path, String text})> _captured = [];

  CalibrationPair get _pair => kVoiceCalibrationPairs[_pairIndex];
  bool get _lastPair => _pairIndex == kVoiceCalibrationPairs.length - 1;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _record(String textToSave) async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return;
    _tempDir ??= await _clipService.newTempCaptureDir();
    final path =
        '$_tempDir/calib_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    setState(() => _recording = true);
  }

  Future<void> _stopAndAdvance(String textToSave) async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path == null) return;
    _captured.add((path: path, text: textToSave));
    setState(() {
      if (_step == _Step.introCorrect) {
        _step = _Step.introWrong;
      } else {
        if (_lastPair) {
          _step = _Step.done;
        } else {
          _pairIndex++;
          _step = _Step.introCorrect;
        }
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final tmp = _tempDir;
    final saved =
        tmp != null ? await _clipService.commitClips(_captured, tmp) : 0;
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '$saved clip${saved > 1 ? "s" : ""} de calibration enregistré${saved > 1 ? "s" : ""} — exporte-les depuis Réglages pour personnaliser le modèle.'),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    final tmp = _tempDir;
    if (tmp != null) await _clipService.discardTempDir(tmp);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        title: Text('Calibration voix',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, color: AppColors.ink)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.ink),
          onPressed: _recording ? null : _cancel,
        ),
      ),
      body: SafeArea(
        child: _step == _Step.done ? _buildDone() : _buildStep(),
      ),
    );
  }

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.green700, size: 64),
            const SizedBox(height: 16),
            Text('Calibration terminée !',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
                '${_captured.length} clips enregistrés. Ils rejoignent tes clips vérifiés — exporte-les depuis Réglages pour lancer la personnalisation.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 13, color: AppColors.inkLight)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    final pair = _pair;
    final isWrong = _step == _Step.introWrong;
    final word = isWrong ? pair.wrong : pair.correct;
    final textToSave = word;
    final progress =
        (_pairIndex + (isWrong ? 0.5 : 0)) / kVoiceCalibrationPairs.length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.cream300,
            color: AppColors.green700,
          ),
          const SizedBox(height: 8),
          Text(
              'Mot ${_pairIndex + 1}/${kVoiceCalibrationPairs.length} — ${pair.reference}',
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isWrong ? AppColors.tajwidIkhfaa.withOpacity(0.08) : AppColors.green50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Text(word,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.scheherazadeNew(
                      fontSize: 44,
                      color: isWrong ? AppColors.tajwidIkhfaa : AppColors.ink)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isWrong
                ? 'Dis ce mot en remplaçant EXPRÈS le "${pair.targetLetter}" par un "${pair.confusedLetter}" — une faute volontaire, pas une vraie récitation.'
                : 'Dis ce mot correctement, comme d\'habitude.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isWrong ? AppColors.tajwidIkhfaa : AppColors.green700),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _recording
                ? _stopAndAdvance(textToSave)
                : _record(textToSave),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording ? Colors.red : AppColors.green700,
                boxShadow: [
                  BoxShadow(
                      color: (_recording ? Colors.red : AppColors.green700)
                          .withOpacity(0.3),
                      blurRadius: 16,
                      spreadRadius: 2),
                ],
              ),
              child: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_recording ? 'Enregistrement… touche pour arrêter' : 'Touche pour enregistrer',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
