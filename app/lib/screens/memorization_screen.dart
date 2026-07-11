import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';

class MemorizationScreen extends StatefulWidget {
  final Verse verse;

  const MemorizationScreen({super.key, required this.verse});

  @override
  State<MemorizationScreen> createState() => _MemorizationScreenState();
}

class _MemorizationScreenState extends State<MemorizationScreen>
    with SingleTickerProviderStateMixin {
  _MicState _micState = _MicState.idle;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Demo feedback state
  List<_WordResult>? _results;
  double _score = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _toggleMic() {
    setState(() {
      if (_micState == _MicState.idle || _micState == _MicState.done) {
        _micState = _MicState.listening;
        _results = null;
      } else if (_micState == _MicState.listening) {
        _micState = _MicState.processing;
        Future.delayed(const Duration(milliseconds: 1200), _showDemoResults);
      }
    });
  }

  void _showDemoResults() {
    // Demo: simulate Whisper feedback on verse words
    final words = widget.verse.textUthmani.split(' ');
    final results = <_WordResult>[];
    for (int i = 0; i < words.length; i++) {
      final status = i == 2
          ? _WordStatus.error
          : i == 4
              ? _WordStatus.tajwid
              : _WordStatus.correct;
      results.add(_WordResult(word: words[i], status: status));
    }
    final correct = results.where((r) => r.status == _WordStatus.correct).length;
    setState(() {
      _results = results;
      _score = correct / results.length;
      _micState = _MicState.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text('Mode mémorisation',
            style: GoogleFonts.fraunces(fontSize: 18, color: AppColors.cream)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Verse card
            _VerseCard(verse: widget.verse),
            const SizedBox(height: 24),
            // Mic button
            _MicButton(
              state: _micState,
              pulseAnim: _pulseAnim,
              onTap: _toggleMic,
            ),
            const SizedBox(height: 8),
            Text(
              _micState == _MicState.idle
                  ? 'Appuie pour réciter'
                  : _micState == _MicState.listening
                      ? 'Écoute en cours…'
                      : _micState == _MicState.processing
                          ? 'Analyse…'
                          : 'Récitation analysée',
              style: GoogleFonts.manrope(
                fontSize: 13, color: AppColors.inkLight,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            // Word-by-word feedback
            if (_results != null) ...[
              _FeedbackCard(results: _results!, score: _score),
              const SizedBox(height: 16),
              _AiCoachBubble(score: _score),
            ],
          ],
        ),
      ),
    );
  }
}

enum _MicState { idle, listening, processing, done }

class _MicButton extends StatelessWidget {
  final _MicState state;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _MicButton({
    required this.state, required this.pulseAnim, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isListening = state == _MicState.listening;
    final isProcessing = state == _MicState.processing;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) {
          return Transform.scale(
            scale: isListening ? pulseAnim.value : 1.0,
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isListening)
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brass.withAlpha(40),
                ),
              ),
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening
                    ? AppColors.brass
                    : state == _MicState.done
                        ? AppColors.green700
                        : AppColors.green800,
                boxShadow: [
                  BoxShadow(
                    color: (isListening ? AppColors.brass : AppColors.green800)
                        .withAlpha(80),
                    blurRadius: 16, spreadRadius: 2,
                  ),
                ],
              ),
              child: isProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: AppColors.cream, strokeWidth: 2.5))
                  : Icon(
                      isListening ? Icons.stop_rounded : Icons.mic,
                      color: AppColors.cream, size: 34),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  final Verse verse;
  const _VerseCard({required this.verse});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.green100),
      ),
      child: Column(
        children: [
          Text(
            '${verse.surahNumber}:${verse.ayahNumber}',
            style: GoogleFonts.manrope(
              fontSize: 11, color: AppColors.green700,
              fontWeight: FontWeight.w600, letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            verse.textUthmani,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: GoogleFonts.scheherazadeNew(
              fontSize: 26, height: 2.1, color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

enum _WordStatus { correct, error, tajwid }

class _WordResult {
  final String word;
  final _WordStatus status;
  const _WordResult({required this.word, required this.status});
}

class _FeedbackCard extends StatelessWidget {
  final List<_WordResult> results;
  final double score;

  const _FeedbackCard({required this.results, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Analyse mot à mot',
                  style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.inkLight,
                  )),
              // Score ring
              _ScoreRing(score: score),
            ],
          ),
          const SizedBox(height: 12),
          // Word chips
          Wrap(
            spacing: 6, runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: results.map((r) => _WordChip(result: r)).toList(),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              _Legend(color: const Color(0xFF1a7a5e), label: 'Correct'),
              const SizedBox(width: 12),
              _Legend(color: Colors.red, label: 'Erreur'),
              const SizedBox(width: 12),
              _Legend(color: Colors.orange, label: 'Tajwid'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  final _WordResult result;
  const _WordChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color text;
    switch (result.status) {
      case _WordStatus.correct:
        bg = const Color(0xFFd4f0e8); text = const Color(0xFF0d5c3a);
      case _WordStatus.error:
        bg = const Color(0xFFffe0e0); text = Colors.red.shade800;
      case _WordStatus.tajwid:
        bg = const Color(0xFFfff3e0); text = Colors.orange.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result.word,
        textDirection: TextDirection.rtl,
        style: GoogleFonts.scheherazadeNew(fontSize: 18, color: text),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = pct >= 90
        ? AppColors.green700
        : pct >= 70
            ? AppColors.brass
            : Colors.red.shade600;
    return SizedBox(
      width: 52, height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 4,
            backgroundColor: AppColors.cream300,
            color: color,
          ),
          Text('$pct%',
              style: GoogleFonts.manrope(
                fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.manrope(fontSize: 10, color: AppColors.inkLight)),
      ],
    );
  }
}

class _AiCoachBubble extends StatelessWidget {
  final double score;
  const _AiCoachBubble({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final msg = pct >= 90
        ? 'Excellent ! Récitation quasi-parfaite. Continue ainsi pour consolider la mémorisation.'
        : pct >= 70
            ? 'Bonne récitation. Fais attention aux mots surlignés en orange (tajwid) et rouge (erreur).'
            : 'Continue à t\'entraîner. Répète ce verset plusieurs fois avant de passer au suivant.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brass,
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.green900, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.cream, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
