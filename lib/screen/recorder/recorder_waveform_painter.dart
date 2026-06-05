import 'package:flutter/material.dart';

class RecorderWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double selectionStart;
  final double selectionEnd;
  final double playbackPos;
  final double visibleStart;
  final double visibleEnd;
  final Color trimColor;
  final Color playColor;
  final Duration totalDuration;

  const RecorderWaveformPainter({
    required this.amplitudes,
    required this.selectionStart,
    required this.selectionEnd,
    required this.playbackPos,
    required this.visibleStart,
    required this.visibleEnd,
    this.trimColor = const Color(0xFF4FC3F7),
    this.playColor = const Color(0xFFF5A623),
    this.totalDuration = Duration.zero,
  });

  static const _rulerH = 28.0;
  static const _handleR = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final visibleRange = visibleEnd - visibleStart;
    if (visibleRange <= 0) return;

    final waveTop = _rulerH;
    final waveH = size.height - waveTop;

    _drawRuler(canvas, size, visibleRange);
    _drawBars(canvas, size, waveTop, waveH, visibleRange);

    double normToX(double norm) =>
        ((norm - visibleStart) / visibleRange * size.width)
            .clamp(0.0, size.width);

    // Start handle
    if (selectionStart >= visibleStart - 0.01 &&
        selectionStart <= visibleEnd + 0.01) {
      _drawHandle(canvas, size, normToX(selectionStart), waveTop, isStart: true);
    }

    // End handle
    if (selectionEnd >= visibleStart - 0.01 &&
        selectionEnd <= visibleEnd + 0.01) {
      _drawHandle(canvas, size, normToX(selectionEnd), waveTop, isStart: false);
    }

    // Playback line + teardrop
    if (playbackPos > 0 &&
        playbackPos >= visibleStart &&
        playbackPos <= visibleEnd) {
      _drawPlayback(canvas, size, normToX(playbackPos), waveTop);
    }
  }

  void _drawRuler(Canvas canvas, Size size, double visibleRange) {
    // Ruler background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, _rulerH),
      Paint()..color = const Color(0xFF0A0A0A),
    );

    final totalSecs = totalDuration.inMilliseconds / 1000.0;
    if (totalSecs <= 0) return;

    final visibleSecs = totalSecs * visibleRange;

    // Pick a "nice" tick interval
    double tickInterval = 1;
    if (visibleSecs > 120) {
      tickInterval = 30;
    } else if (visibleSecs > 60) {
      tickInterval = 10;
    } else if (visibleSecs > 20) {
      tickInterval = 5;
    } else if (visibleSecs > 8) {
      tickInterval = 2;
    }

    final visStartSecs = visibleStart * totalSecs;
    final visEndSecs = visibleEnd * totalSecs;

    final firstTick = (visStartSecs / tickInterval).ceil() * tickInterval;

    for (double t = firstTick; t <= visEndSecs + 0.001; t += tickInterval) {
      final norm = t / totalSecs;
      final x = (norm - visibleStart) / visibleRange * size.width;

      // Tick mark
      canvas.drawLine(
        Offset(x, _rulerH - 7),
        Offset(x, _rulerH),
        Paint()
          ..color = Colors.white38
          ..strokeWidth = 1.0,
      );

      // Label
      String label;
      final sec = t.round();
      if (sec >= 60 && sec % 60 == 0) {
        label = '${sec ~/ 60}m';
      } else if (sec >= 60) {
        label = '${sec ~/ 60}m${sec % 60}s';
      } else {
        label = '${sec}s';
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Keep label within canvas bounds
      final lx = (x - tp.width / 2).clamp(2.0, size.width - tp.width - 2);
      tp.paint(canvas, Offset(lx, 5));
    }
  }

  void _drawBars(Canvas canvas, Size size, double waveTop, double waveH,
      double visibleRange) {
    if (amplitudes.isEmpty) return;

    const barW = 2.0;
    const gap = 1.5;
    const step = barW + gap;
    final numBars = (size.width / step).floor();
    final totalW = numBars * step;
    final offsetX = (size.width - totalW) / 2;
    final centerY = waveTop + waveH / 2;

    final unselPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = barW
      ..strokeCap = StrokeCap.round;

    final selPaint = Paint()
      ..color = trimColor
      ..strokeWidth = barW
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < numBars; i++) {
      final normInVisible = i / numBars;
      final normGlobal = visibleStart + normInVisible * visibleRange;
      final ampIdx =
          (normGlobal * amplitudes.length).clamp(0, amplitudes.length - 1).toInt();
      final amp = amplitudes[ampIdx];
      final barH = amp * (waveH / 2) * 0.9;
      final x = offsetX + i * step;

      final inSel = normGlobal >= selectionStart && normGlobal <= selectionEnd;
      canvas.drawLine(
        Offset(x, centerY - barH),
        Offset(x, centerY + barH),
        inSel ? selPaint : unselPaint,
      );
    }
  }

  void _drawHandle(Canvas canvas, Size size, double x, double waveTop,
      {required bool isStart}) {
    // Vertical line through entire waveform area
    canvas.drawLine(
      Offset(x, waveTop),
      Offset(x, size.height),
      Paint()
        ..color = trimColor
        ..strokeWidth = 2.0,
    );

    // Circle: start → top, end → bottom
    final cy = isStart
        ? waveTop + _handleR + 2
        : size.height - _handleR - 2;
    final cx = x;

    // Shadow ring
    canvas.drawCircle(
      Offset(cx, cy),
      _handleR + 2,
      Paint()..color = Colors.black38,
    );

    // Filled circle
    canvas.drawCircle(
      Offset(cx, cy),
      _handleR,
      Paint()..color = trimColor,
    );

    // Chevron (< or >)
    const arm = 6.0;
    final chevPath = Path();
    if (isStart) {
      chevPath.moveTo(cx + arm * 0.5, cy - arm);
      chevPath.lineTo(cx - arm * 0.5, cy);
      chevPath.lineTo(cx + arm * 0.5, cy + arm);
    } else {
      chevPath.moveTo(cx - arm * 0.5, cy - arm);
      chevPath.lineTo(cx + arm * 0.5, cy);
      chevPath.lineTo(cx - arm * 0.5, cy + arm);
    }
    canvas.drawPath(
      chevPath,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawPlayback(Canvas canvas, Size size, double x, double waveTop) {
    final paint = Paint()..color = playColor..strokeWidth = 2.0;

    // Vertical line
    canvas.drawLine(Offset(x, waveTop), Offset(x, size.height - 10), paint);

    // Teardrop circle at bottom
    canvas.drawCircle(
      Offset(x, size.height - 10),
      9,
      Paint()..color = playColor,
    );
  }

  @override
  bool shouldRepaint(covariant RecorderWaveformPainter old) {
    return old.amplitudes != amplitudes ||
        old.selectionStart != selectionStart ||
        old.selectionEnd != selectionEnd ||
        old.playbackPos != playbackPos ||
        old.visibleStart != visibleStart ||
        old.visibleEnd != visibleEnd ||
        old.totalDuration != totalDuration;
  }
}
