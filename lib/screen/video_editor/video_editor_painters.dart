import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ── Curved text painter ───────────────────────────────────────────────────────
/// Draws [text] along a circular arc.
/// [curve] > 0 → rainbow (bows upward); [curve] < 0 → frown (bows downward).
/// Magnitude controls tightness: ±1.0 = semicircle, ±0.25 = gentle arc.
/// Can be used directly on a [Canvas] via [paint] — no widget tree required —
/// which makes it suitable for off-screen PNG rendering during FFmpeg export.
class VeCurvedTextPainter extends CustomPainter {
  final String text;
  final TextStyle fillStyle;
  final TextStyle? outlineStyle; // null if no outline
  final double curve; // -1.0 .. 1.0; 0.0 = straight (unused here)

  const VeCurvedTextPainter({
    required this.text,
    required this.fillStyle,
    this.outlineStyle,
    required this.curve,
  });

  List<TextPainter> _layoutChars(TextStyle style) {
    return text.characters.map((ch) {
      final tp = TextPainter(
        text: TextSpan(text: ch, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    }).toList();
  }

  void _drawLayer(Canvas canvas, Size size, List<TextPainter> painters) {
    if (painters.isEmpty) return;
    final totalWidth = painters.fold(0.0, (s, tp) => s + tp.width);
    if (totalWidth == 0) return;
    final charHeight = painters.first.height;
    final absCurve = curve.abs().clamp(0.001, 1.0);
    final arcAngle = absCurve * pi;           // subtended angle in radians
    final radius   = totalWidth / arcAngle;   // arc_length = radius × angle
    final isRainbow = curve > 0;              // true → bows upward

    // Circle centre in widget-local coordinates
    final cx = size.width / 2;
    final cy = isRainbow
        ? size.height / 2 + radius - charHeight / 2   // centre below text row
        : size.height / 2 - radius + charHeight / 2;  // centre above text row

    final halfArc    = arcAngle / 2;
    final startAngle = isRainbow
        ? -pi / 2 - halfArc   // span centred on "12 o'clock"
        : pi / 2  - halfArc;  // span centred on "6 o'clock"

    double cumWidth = 0.0;
    for (final tp in painters) {
      final t = (cumWidth + tp.width / 2) / totalWidth; // 0..1 along arc
      final charAngle  = startAngle + t * arcAngle;

      canvas.save();
      canvas.translate(
        cx + radius * cos(charAngle),
        cy + radius * sin(charAngle),
      );
      // Align character tangent to the circle
      canvas.rotate(isRainbow ? charAngle + pi / 2 : charAngle - pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();

      cumWidth += tp.width;
    }
    for (final tp in painters) tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;
    if (outlineStyle != null) _drawLayer(canvas, size, _layoutChars(outlineStyle!));
    _drawLayer(canvas, size, _layoutChars(fillStyle));
  }

  @override
  bool shouldRepaint(VeCurvedTextPainter old) =>
      old.text != text ||
      old.fillStyle != fillStyle ||
      old.outlineStyle != outlineStyle ||
      old.curve != curve;
}

// ── Audio waveform painter ────────────────────────────────────────────────────

class VeWaveformPainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  final double trimStartFraction;
  final double trimEndFraction;
  final double volume;
  final double fadeInFraction;
  final double fadeOutFraction;

  const VeWaveformPainter({
    required this.bars,
    required this.color,
    this.trimStartFraction = 0.0,
    this.trimEndFraction = 0.0,
    this.volume = 1.0,
    this.fadeInFraction = 0.0,
    this.fadeOutFraction = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final startIdx = (trimStartFraction * bars.length).floor();
    final endIdx = bars.length - (trimEndFraction * bars.length).floor();
    if (startIdx >= endIdx) return;
    final visibleBars = bars.sublist(startIdx, endIdx);

    final barCount = visibleBars.length;
    final barW = (size.width / barCount).clamp(1.0, double.infinity);
    final gap = (barW * 0.3).clamp(0.0, 3.0);
    final actualW = (barW - gap).clamp(1.0, barW);
    final cx = size.height / 2;

    final barPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final pos = barCount > 1 ? i / (barCount - 1) : 1.0;

      double fadeMult = 1.0;
      if (fadeInFraction > 0 && pos < fadeInFraction) {
        fadeMult *= pos / fadeInFraction;
      }
      if (fadeOutFraction > 0 && pos > (1.0 - fadeOutFraction)) {
        fadeMult *= (1.0 - pos) / fadeOutFraction;
      }

      final amp = visibleBars[i] * volume.clamp(0.0, 2.0) * fadeMult;
      final barH = (amp * cx * 1.8).clamp(0.5, size.height - 4);
      final x = i * barW + gap / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + actualW / 2, cx),
            width: actualW,
            height: barH,
          ),
          const Radius.circular(2),
        ),
        barPaint,
      );
    }

    _drawFadeEnvelope(canvas, size, cx);
  }

  void _drawFadeEnvelope(Canvas canvas, Size size, double cx) {
    const edgeMargin = 2.5;

    final fillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    if (fadeInFraction > 0) {
      final endX = fadeInFraction * size.width;
      canvas.drawPath(
        (Path()
          ..moveTo(0, 0)
          ..lineTo(endX, 0)
          ..lineTo(0, cx)
          ..close()),
        fillPaint,
      );
      canvas.drawPath(
        (Path()
          ..moveTo(0, size.height)
          ..lineTo(0, cx)
          ..lineTo(endX, size.height)
          ..close()),
        fillPaint,
      );
      canvas.drawLine(Offset(0, cx), Offset(endX, edgeMargin), linePaint);
      canvas.drawLine(
          Offset(0, cx), Offset(endX, size.height - edgeMargin), linePaint);
      canvas.drawCircle(Offset(0, cx), 2.5, dotPaint);
      canvas.drawLine(
        Offset(endX, 0),
        Offset(endX, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 0.8,
      );
    }

    if (fadeOutFraction > 0) {
      final startX = (1.0 - fadeOutFraction) * size.width;
      canvas.drawPath(
        (Path()
          ..moveTo(startX, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, cx)
          ..close()),
        fillPaint,
      );
      canvas.drawPath(
        (Path()
          ..moveTo(startX, size.height)
          ..lineTo(size.width, cx)
          ..lineTo(size.width, size.height)
          ..close()),
        fillPaint,
      );
      canvas.drawLine(
          Offset(startX, edgeMargin), Offset(size.width, cx), linePaint);
      canvas.drawLine(
          Offset(startX, size.height - edgeMargin),
          Offset(size.width, cx),
          linePaint);
      canvas.drawCircle(Offset(size.width, cx), 2.5, dotPaint);
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(VeWaveformPainter old) =>
      old.bars != bars ||
      old.color != color ||
      old.trimStartFraction != trimStartFraction ||
      old.trimEndFraction != trimEndFraction ||
      old.volume != volume ||
      old.fadeInFraction != fadeInFraction ||
      old.fadeOutFraction != fadeOutFraction;
}

// ── Time ruler painter ────────────────────────────────────────────────────────

class VeRulerPainter extends CustomPainter {
  final double totalSeconds;
  final double pps;

  const VeRulerPainter({required this.totalSeconds, required this.pps});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0D1623),
    );

    final linePaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;

    const textStyle = TextStyle(color: Colors.white54, fontSize: 10);

    double interval = 120;
    if (pps > 3.0) {
      interval = 10;
    } else if (pps > 1.5) {
      interval = 30;
    } else if (pps > 0.6) {
      interval = 60;
    }

    // Major ticks + labels
    double t = 0;
    while (t <= totalSeconds + interval) {
      final x = t * pps;
      canvas.drawLine(
        Offset(x, size.height * 0.6),
        Offset(x, size.height),
        linePaint,
      );
      final int totalSec = t.toInt();
      final String label = totalSec >= 60
          ? '${totalSec ~/ 60}:${(totalSec % 60).toString().padLeft(2, '0')}'
          : '${totalSec}s';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 2));
      t += interval;
    }

    // Minor ticks
    final minor = interval / 4;
    double tm = minor;
    while (tm <= totalSeconds) {
      if (tm % interval != 0) {
        final x = tm * pps;
        canvas.drawLine(
          Offset(x, size.height * 0.75),
          Offset(x, size.height),
          Paint()
            ..color = Colors.white12
            ..strokeWidth = 0.5,
        );
      }
      tm += minor;
    }
  }

  @override
  bool shouldRepaint(VeRulerPainter old) =>
      old.totalSeconds != totalSeconds || old.pps != pps;
}

// ── Row stripe background painter ────────────────────────────────────────────

class VeRowStripesPainter extends CustomPainter {
  /// One entry per track – the full row height (track + gap).
  final List<double> rowHeights;
  final Color colorEven;
  final Color colorOdd;

  const VeRowStripesPainter({
    required this.rowHeights,
    required this.colorEven,
    required this.colorOdd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double y = 0;
    for (int i = 0; i < rowHeights.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, rowHeights[i]),
        Paint()..color = i.isEven ? colorEven : colorOdd,
      );
      y += rowHeights[i];
    }
  }

  @override
  bool shouldRepaint(VeRowStripesPainter old) {
    if (old.colorEven != colorEven || old.colorOdd != colorOdd) return true;
    if (old.rowHeights.length != rowHeights.length) return true;
    for (int i = 0; i < rowHeights.length; i++) {
      if (old.rowHeights[i] != rowHeights[i]) return true;
    }
    return false;
  }
}

// ── Dashed rect border painter ───────────────────────────────────────────────

class VeDashedRectPainter extends CustomPainter {
  final Color color;
  const VeDashedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const double dash = 6.0;
    const double gap = 6.0;
    const double r = 6.0;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(r));
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    double distance = 0.0;
    while (distance < metric.length) {
      final end = (distance + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), paint);
      distance += dash + gap;
    }
  }

  @override
  bool shouldRepaint(VeDashedRectPainter old) => old.color != color;
}

// ── Empty slot / file-card placeholder painter ───────────────────────────────
///
/// Tiles small "document" cards (rounded rect + dog-ear corner + image-outline
/// icon) across the full row width, mimicking how filmstrip frames look on a
/// real video track but empty.

class VeEmptySlotPainter extends CustomPainter {
  final Color cardColor;
  final Color iconColor;

  const VeEmptySlotPainter({
    required this.cardColor,
    required this.iconColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double padding = 3.0;
    final double h = size.height - padding * 2;
    final double cardW = h * 0.72; // slightly portrait, like a document
    const double gap = 4.0;
    final double foldSize = h * 0.22;
    const double r = 4.0;

    final bgPaint = Paint()..color = cardColor;
    final strokePaint = Paint()
      ..color = iconColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double x = padding;
    while (x + cardW <= size.width - padding) {
      final top = padding;
      final left = x;
      final right = left + cardW;
      final bottom = top + h;

      // ── Document shape (clip top-right corner) ──────────────────────────
      final docPath = Path()
        ..moveTo(left + r, top)
        ..lineTo(right - foldSize, top)
        ..lineTo(right, top + foldSize)
        ..lineTo(right, bottom - r)
        ..arcToPoint(Offset(right - r, bottom),
            radius: const Radius.circular(r))
        ..lineTo(left + r, bottom)
        ..arcToPoint(Offset(left, bottom - r),
            radius: const Radius.circular(r))
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top),
            radius: const Radius.circular(r))
        ..close();

      canvas.drawPath(docPath, bgPaint);

      // ── Dog-ear fold triangle ───────────────────────────────────────────
      final foldPaint = Paint()
        ..color = iconColor.withOpacity(0.08)
        ..style = PaintingStyle.fill;
      final foldPath = Path()
        ..moveTo(right - foldSize, top)
        ..lineTo(right, top + foldSize)
        ..lineTo(right - foldSize, top + foldSize)
        ..close();
      canvas.drawPath(foldPath, foldPaint);
      // fold edge line
      canvas.drawLine(
        Offset(right - foldSize, top),
        Offset(right, top + foldSize),
        strokePaint,
      );

      // ── Image placeholder icon (centered in lower ~60% of card) ────────
      final iconAreaTop = top + h * 0.22;
      final iconAreaBottom = bottom - h * 0.22;
      final iconAreaH = iconAreaBottom - iconAreaTop;
      final iconAreaLeft = left + cardW * 0.15;
      final iconAreaRight = right - cardW * 0.15;
      final iconRect =
          Rect.fromLTRB(iconAreaLeft, iconAreaTop, iconAreaRight, iconAreaBottom);

      // outer rounded rect frame
      canvas.drawRRect(
          RRect.fromRectAndRadius(iconRect, const Radius.circular(2.5)),
          strokePaint);

      // sun circle (top-left of icon)
      final sunR = iconAreaH * 0.18;
      final sunCx = iconRect.left + iconAreaH * 0.28;
      final sunCy = iconRect.top + iconAreaH * 0.32;
      canvas.drawCircle(Offset(sunCx, sunCy), sunR, strokePaint);

      // mountain path
      final mPaint = Paint()
        ..color = iconColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final mountainPath = Path()
        ..moveTo(iconRect.left + 1, iconRect.bottom - 1)
        ..lineTo(iconRect.left + iconAreaH * 0.38,
            iconRect.bottom - iconAreaH * 0.35)
        ..lineTo(iconRect.left + iconAreaH * 0.62,
            iconRect.bottom - iconAreaH * 0.18)
        ..lineTo(iconRect.right - iconAreaH * 0.22,
            iconRect.bottom - iconAreaH * 0.42)
        ..lineTo(iconRect.right - 1, iconRect.bottom - 1);
      canvas.drawPath(mountainPath, mPaint);

      x += cardW + gap;
    }
  }

  @override
  bool shouldRepaint(VeEmptySlotPainter old) =>
      old.cardColor != cardColor || old.iconColor != iconColor;
}

// ── Film grain / noise ────────────────────────────────────────────────────────

/// Draws randomised film-grain noise onto a canvas.
/// [strength] 0.0–1.0 controls grain density and opacity.
/// [seed] is the random seed — change it each frame for animated grain.
class VeGrainPainter extends CustomPainter {
  final double strength;
  final int seed;

  const VeGrainPainter({required this.strength, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || size.isEmpty) return;
    final rng = Random(seed);
    final paint = Paint();

    // Particle count: proportional to area × strength (capped for perf)
    final count = (size.width * size.height * strength * 0.07)
        .round()
        .clamp(0, 10000);

    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      // Film grain: mostly dark specks with occasional bright halation
      final v = rng.nextBool()
          ? rng.nextInt(70)           // dark grain
          : 185 + rng.nextInt(71);   // light grain
      paint.color = Color.fromARGB(
        (strength * 190).round().clamp(0, 255),
        v, v, v,
      );
      canvas.drawCircle(Offset(x, y), 0.85, paint);
    }
  }

  @override
  bool shouldRepaint(VeGrainPainter old) =>
      old.seed != seed || old.strength != strength;
}

/// Animated film-grain overlay widget (~24 fps grain refresh).
/// Wraps itself in a [RepaintBoundary] so repaints don't propagate upward.
class VeGrainOverlay extends StatefulWidget {
  final double strength;
  const VeGrainOverlay({super.key, required this.strength});

  @override
  State<VeGrainOverlay> createState() => _VeGrainOverlayState();
}

class _VeGrainOverlayState extends State<VeGrainOverlay> {
  late final Ticker _ticker;
  int _seed = 42;
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((elapsed) {
      // Refresh grain at ~24 fps (every 41 ms)
      final tick = elapsed.inMilliseconds ~/ 41;
      if (tick != _lastTick) {
        _lastTick = tick;
        if (mounted) setState(() => _seed = tick & 0xFFFF);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            painter: VeGrainPainter(
              strength: widget.strength,
              seed: _seed,
            ),
            size: Size.infinite,
          ),
        ),
      );
}

// ── Text selection dashed-border painter ─────────────────────────────────────

/// Draws an animated dashed rounded rectangle border around the selected text
/// overlay. The border extends [pad] pixels outside the widget's layout bounds
/// so it clears any background box or glow effects.
class VeTextSelectionPainter extends CustomPainter {
  const VeTextSelectionPainter();

  static const double _pad = 8.0;
  static const double _dashW = 7.0;
  static const double _dashS = 4.0;
  static const double _r = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      -_pad, -_pad,
      size.width + _pad * 2, size.height + _pad * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_r));
    final path = Path()..addRRect(rrect);

    // Shadow pass (black, slightly thicker) for contrast on any background.
    _drawDashed(canvas, path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.55)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    // White pass on top.
    _drawDashed(canvas, path,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 0.9
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < m.length) {
        final len = draw ? _dashW : _dashS;
        if (draw) {
          canvas.drawPath(
            m.extractPath(dist, (dist + len).clamp(0, m.length)),
            paint,
          );
        }
        dist += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(VeTextSelectionPainter old) => false;
}

// ── Mask clipper & shape painter ──────────────────────────────────────────────

/// Shape index constants for mask feature.
/// 0 = none, 1 = circle, 2 = rectangle, 3 = heart, 4 = star, 5 = triangle, 6 = diamond.

/// [CustomClipper] that clips its child to a shape defined by [shapeIndex].
/// [scale] controls the size of the shape relative to the widget bounds (1.0 = fills).
/// When [inverted] is true the clip is the complement of the shape (show outside, hide inside).
class VeMaskClipper extends CustomClipper<Path> {
  final int shapeIndex;
  final double scale;
  final bool inverted;

  const VeMaskClipper({
    required this.shapeIndex,
    this.scale = 1.0,
    this.inverted = false,
  });

  /// Builds a path for [shapeIndex] that fits inside [rect].
  static Path buildShapePath(Rect rect, int shapeIndex) {
    switch (shapeIndex) {
      case 1:
        return _circlePath(rect);
      case 2:
        return _rectPath(rect);
      case 3:
        return _heartPath(rect);
      case 4:
        return _starPath(rect);
      case 5:
        return _trianglePath(rect);
      case 6:
        return _diamondPath(rect);
      default:
        return Path()..addRect(rect);
    }
  }

  @override
  Path getClip(Size size) {
    // Round shapes use shortest side so they stay non-oval.
    final short = min(size.width, size.height) * scale;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final Rect rect;
    if (shapeIndex == 2) {
      // Rectangle preserves clip aspect ratio.
      rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width * scale,
        height: size.height * scale,
      );
    } else {
      rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: short,
        height: short,
      );
    }

    final shapePath = buildShapePath(rect, shapeIndex);

    if (inverted) {
      return Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        shapePath,
      );
    }
    return shapePath;
  }

  @override
  bool shouldReclip(VeMaskClipper old) =>
      old.shapeIndex != shapeIndex ||
      old.scale != scale ||
      old.inverted != inverted;

  // ── Shape helpers ────────────────────────────────────────────────────────────

  static Path _circlePath(Rect rect) => Path()..addOval(rect);

  static Path _rectPath(Rect rect) => Path()
    ..addRRect(RRect.fromRectAndRadius(
        rect, Radius.circular(rect.shortestSide * 0.12)));

  static Path _heartPath(Rect rect) {
    final cx = rect.center.dx;
    final t = rect.top;
    final b = rect.bottom;
    final l = rect.left;
    final r = rect.right;
    final h = rect.height;
    final w = rect.width;

    return Path()
      ..moveTo(cx, t + h * 0.28)
      // Right bump
      ..cubicTo(cx + w * 0.12, t, r, t + h * 0.15, r, t + h * 0.38)
      // Right lower
      ..cubicTo(r, t + h * 0.62, cx + w * 0.22, t + h * 0.78, cx, b)
      // Left lower
      ..cubicTo(cx - w * 0.22, t + h * 0.78, l, t + h * 0.62, l, t + h * 0.38)
      // Left bump
      ..cubicTo(l, t + h * 0.15, cx - w * 0.12, t, cx, t + h * 0.28)
      ..close();
  }

  static Path _starPath(Rect rect) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final outerR = rect.shortestSide / 2;
    final innerR = outerR * 0.42;
    const n = 5;
    final path = Path();
    for (int i = 0; i < n * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = (i * pi / n) - pi / 2;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  static Path _trianglePath(Rect rect) {
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
  }

  static Path _diamondPath(Rect rect) {
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
  }
}

/// Mini shape preview painter used inside the mask dialog shape selector.
class VeMaskShapePreviewPainter extends CustomPainter {
  final int shapeIndex;
  final bool selected;

  const VeMaskShapePreviewPainter({
    required this.shapeIndex,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 6.0;
    final rect = Rect.fromLTWH(
        padding, padding, size.width - padding * 2, size.height - padding * 2);
    final path = VeMaskClipper.buildShapePath(rect, shapeIndex);
    canvas.drawPath(
      path,
      Paint()
        ..color = selected ? const Color(0xFFAA44FF) : Colors.white54
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(VeMaskShapePreviewPainter old) =>
      old.shapeIndex != shapeIndex || old.selected != selected;
}
