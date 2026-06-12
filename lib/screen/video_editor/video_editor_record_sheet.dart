import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows a bottom sheet that records audio while the editor plays the video
/// muted in the background.
///
/// Returns the path of the recorded .m4a file when the user taps Stop, or null
/// if the sheet was dismissed without a recording.
Future<String?> showVeRecordSheet({
  required BuildContext context,
  required Duration startOffset,
  double? maxHeight,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: (_) => _VeRecordSheet(startOffset: startOffset),
  );
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _VeRecordSheet extends StatefulWidget {
  final Duration startOffset;
  const _VeRecordSheet({required this.startOffset});

  @override
  State<_VeRecordSheet> createState() => _VeRecordSheetState();
}

class _VeRecordSheetState extends State<_VeRecordSheet> {
  static const _kBg = Color(0xFF0D1623);
  static const _kRecRed = Color(0xFFE53935);
  static const _kSampleMs = 80; // amplitude poll interval

  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  Timer? _sampleTimer;
  Timer? _uiTimer;

  final List<double> _amps = [];
  String? _outputPath;
  bool _started = false;
  bool _stopping = false;
  String? _error;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _uiTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Recording ─────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) setState(() => _error = 'Microphone permission denied.');
        return;
      }

      final dir = await getTemporaryDirectory();
      _outputPath =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
        path: _outputPath!,
      );

      _stopwatch.start();

      // Amplitude sampler — drives the live waveform
      _sampleTimer =
          Timer.periodic(const Duration(milliseconds: _kSampleMs), (_) async {
        final amp = await _recorder.getAmplitude();
        if (!mounted) return;
        // Map dB range (-60..0) to 0..1; silence < -60 dB → 0
        final norm = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        setState(() => _amps.add(norm));
      });

      // Separate lightweight timer keeps the elapsed-time label smooth
      _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });

      if (mounted) setState(() => _started = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start recording: $e');
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _sampleTimer?.cancel();
    _uiTimer?.cancel();
    _stopwatch.stop();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) Navigator.pop(context, _outputPath);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final ms = d.inMilliseconds;
    final min = ms ~/ 60000;
    final sec = (ms ~/ 1000) % 60;
    final frac = (ms % 1000) ~/ 100;
    return '${min.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')}.$frac';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header row ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RecDot(active: _started && !_stopping),
              const SizedBox(width: 8),
              Text(
                'REC',
                style: TextStyle(
                  color: _kRecRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _fmt(_stopwatch.elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('start',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text(
                    _fmt(widget.startOffset),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Waveform ────────────────────────────────────────────────────────
          _error != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                )
              : SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _WaveformPainter(amps: _amps, color: _kRecRed),
                  ),
                ),
          const SizedBox(height: 24),

          // ── Stop button ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _stopping ? null : _stop,
              icon: const Icon(Icons.stop_rounded, size: 24),
              label: const Text(
                'STOP',
                style: TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kRecRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Blinking REC dot ──────────────────────────────────────────────────────────

class _RecDot extends StatefulWidget {
  final bool active;
  const _RecDot({required this.active});

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.active
              ? const Color(0xFFE53935)
                  .withValues(alpha: 0.4 + _ctrl.value * 0.6)
              : Colors.white24,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Live waveform painter ─────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> amps;
  final Color color;

  const _WaveformPainter({required this.amps, required this.color});

  static const _barW = 3.0;
  static const _gap = 2.5;
  static const _step = _barW + _gap;

  @override
  void paint(Canvas canvas, Size size) {
    // Background centre line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = Colors.white10
        ..strokeWidth = 1,
    );

    if (amps.isEmpty) return;

    final maxBars = (size.width / _step).floor();
    final startIdx = amps.length > maxBars ? amps.length - maxBars : 0;
    final visible = amps.sublist(startIdx);

    // Bars anchored to the right; newest bar is at the cursor
    final totalW = visible.length * _step;
    final originX = size.width - totalW;

    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < visible.length; i++) {
      final a = visible[i];
      final h = (a * (size.height - 8)).clamp(2.0, size.height - 8);
      final x = originX + i * _step;
      final y = (size.height - h) / 2;
      // Fade older bars to 40% opacity
      final ageFade = 0.4 + 0.6 * (i / visible.length);
      paint.color = Color.lerp(
        color.withValues(alpha: 0.25 * ageFade),
        color.withValues(alpha: ageFade),
        a,
      )!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }

    // Cursor — vertical line at the right edge
    canvas.drawLine(
      Offset(size.width - 1, 0),
      Offset(size.width - 1, size.height),
      Paint()
        ..color = Colors.white38
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.amps.length != amps.length;
}
