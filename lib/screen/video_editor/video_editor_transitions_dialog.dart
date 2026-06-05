import 'dart:math' show sqrt, sin, pi;

import 'package:flutter/material.dart';

import 'video_editor_model.dart';

// ── Transition metadata ────────────────────────────────────────────────────────

class _TransitionItem {
  final TransitionType type;
  final String label;
  final IconData icon;
  const _TransitionItem(this.type, this.label, this.icon);
}

class _TransitionCategory {
  final String name;
  final Color circleColor;
  final List<_TransitionItem> items;
  const _TransitionCategory(this.name, this.circleColor, this.items);
}

const _kCategories = [
  _TransitionCategory('BASIC', Color(0xFF383838), [
    _TransitionItem(TransitionType.none,        'None',        Icons.block),
    _TransitionItem(TransitionType.checkerboard,'Checker',     Icons.grid_on),
    _TransitionItem(TransitionType.wipeLeft,    'Left',        Icons.chevron_left),
    _TransitionItem(TransitionType.wipeRight,   'Right',       Icons.chevron_right),
    _TransitionItem(TransitionType.wipeUp,      'Up',          Icons.expand_less),
    _TransitionItem(TransitionType.wipeDown,    'Down',        Icons.expand_more),
    _TransitionItem(TransitionType.circleFade,  'Circle',      Icons.circle_outlined),
  ]),
  _TransitionCategory('SUPER', Color(0xFF7A6235), [
    _TransitionItem(TransitionType.superZoomIn,  'Zoom In',   Icons.zoom_in),
    _TransitionItem(TransitionType.superZoomOut, 'Zoom Out',  Icons.zoom_out),
    _TransitionItem(TransitionType.superRotate,  'Rotate',    Icons.rotate_right),
    _TransitionItem(TransitionType.superBlur,    'Blur',      Icons.blur_on),
    _TransitionItem(TransitionType.superFlash,   'Flash',     Icons.flash_on),
    _TransitionItem(TransitionType.superSpin,    'Spin',      Icons.refresh),
    _TransitionItem(TransitionType.superPush,    'Push',      Icons.open_with),
  ]),
  _TransitionCategory('GLITCH', Color(0xFF1C4545), [
    _TransitionItem(TransitionType.glitchRgb,     'RGB',      Icons.color_lens_outlined),
    _TransitionItem(TransitionType.glitchScan,    'Scan',     Icons.linear_scale),
    _TransitionItem(TransitionType.glitchPixel,   'Pixel',    Icons.apps),
    _TransitionItem(TransitionType.glitchGhost,   'Ghost',    Icons.layers_outlined),
    _TransitionItem(TransitionType.glitchStripe,  'Stripe',   Icons.view_week),
    _TransitionItem(TransitionType.glitchZap,     'Zap',      Icons.electric_bolt),
    _TransitionItem(TransitionType.glitchFlicker, 'Flicker',  Icons.brightness_high),
  ]),
  _TransitionCategory('DISSOLVE', Color(0xFF4A1E1E), [
    _TransitionItem(TransitionType.dissolvePixel,   'Pixel',   Icons.blur_circular),
    _TransitionItem(TransitionType.dissolveRadial,  'Radial',  Icons.radar),
    _TransitionItem(TransitionType.dissolveSpiral,  'Spiral',  Icons.cyclone),
    _TransitionItem(TransitionType.dissolveDrop,    'Drop',    Icons.water_drop_outlined),
    _TransitionItem(TransitionType.dissolveSmear,   'Smear',   Icons.brush_outlined),
    _TransitionItem(TransitionType.dissolveShatter, 'Shatter', Icons.broken_image_outlined),
    _TransitionItem(TransitionType.dissolveStar,    'Star',    Icons.star_outline),
  ]),
  _TransitionCategory('SLICE', Color(0xFF1A3A55), [
    _TransitionItem(TransitionType.sliceVertical,   'Vert',    Icons.vertical_split),
    _TransitionItem(TransitionType.sliceHorizontal, 'Horiz',   Icons.horizontal_split),
    _TransitionItem(TransitionType.sliceBar,        'Bar',     Icons.equalizer_rounded),
    _TransitionItem(TransitionType.sliceRoll,       'Roll',    Icons.view_carousel_outlined),
    _TransitionItem(TransitionType.sliceFan,        'Fan',     Icons.flip),
    _TransitionItem(TransitionType.sliceRadial,     'Radial',  Icons.pie_chart_outline),
    _TransitionItem(TransitionType.sliceRipple,     'Ripple',  Icons.waves),
  ]),
  _TransitionCategory('LIGHT', Color(0xFF3A1A5A), [
    _TransitionItem(TransitionType.lightFlare,   'Flare',   Icons.flare),
    _TransitionItem(TransitionType.lightBloom,   'Bloom',   Icons.wb_sunny_outlined),
    _TransitionItem(TransitionType.lightPulse,   'Pulse',   Icons.radio_button_unchecked),
    _TransitionItem(TransitionType.lightGlow,    'Glow',    Icons.brightness_high_outlined),
    _TransitionItem(TransitionType.lightBurst,   'Burst',   Icons.auto_awesome_outlined),
    _TransitionItem(TransitionType.lightShimmer, 'Shimmer', Icons.star_border_purple500),
    _TransitionItem(TransitionType.lightFade,    'Fade',    Icons.filter_none),
  ]),
  _TransitionCategory('FILM', Color(0xFF4A2D14), [
    _TransitionItem(TransitionType.filmBurn,     'Burn',     Icons.local_fire_department_outlined),
    _TransitionItem(TransitionType.filmLeader,   'Leader',   Icons.movie_outlined),
    _TransitionItem(TransitionType.filmFlicker,  'Flicker',  Icons.highlight_outlined),
    _TransitionItem(TransitionType.filmScratch,  'Scratch',  Icons.line_style),
    _TransitionItem(TransitionType.filmLens,     'Lens',     Icons.camera_outlined),
    _TransitionItem(TransitionType.filmFlash,    'Flash',    Icons.flash_auto),
    _TransitionItem(TransitionType.filmAperture, 'Aperture', Icons.lens_blur),
  ]),
  _TransitionCategory('DISTORT', Color(0xFF1A2A55), [
    _TransitionItem(TransitionType.distortSwirl,  'Swirl',  Icons.cyclone),
    _TransitionItem(TransitionType.distortWave,   'Wave',   Icons.waves),
    _TransitionItem(TransitionType.distortBarrel, 'Barrel', Icons.vignette),
    _TransitionItem(TransitionType.distortPinch,  'Pinch',  Icons.compress),
    _TransitionItem(TransitionType.distortMirror, 'Mirror', Icons.flip_outlined),
    _TransitionItem(TransitionType.distortRipple, 'Ripple', Icons.water),
    _TransitionItem(TransitionType.distortTwirl,  'Twirl',  Icons.rotate_left),
  ]),
  _TransitionCategory('RIPPED PAPER', Color(0xFF3D1A55), [
    _TransitionItem(TransitionType.ripTear,    'Tear',    Icons.content_cut_outlined),
    _TransitionItem(TransitionType.ripRip,     'Rip',     Icons.receipt_long_outlined),
    _TransitionItem(TransitionType.ripCrumple, 'Crumple', Icons.description_outlined),
    _TransitionItem(TransitionType.ripFold,    'Fold',    Icons.book_outlined),
    _TransitionItem(TransitionType.ripPeel,    'Peel',    Icons.tab_outlined),
    _TransitionItem(TransitionType.ripSlide,   'Slide',   Icons.arrow_right_alt),
    _TransitionItem(TransitionType.ripBurn,    'Burn',    Icons.whatshot_outlined),
  ]),
];

// ── Transition overlay (live preview) ─────────────────────────────────────────

/// Visual effect category used for preview rendering.
enum _OverlayEffect {
  none,
  fade,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  circleReveal,
  checkerboard,
  zoomIn,
  zoomOut,
  flash,
  glitch,
  sliceV,
  sliceH,
}

_OverlayEffect _effectFor(TransitionType t) {
  switch (t) {
    case TransitionType.none:
      return _OverlayEffect.none;
    case TransitionType.checkerboard:
      return _OverlayEffect.checkerboard;
    case TransitionType.wipeLeft:
      return _OverlayEffect.wipeLeft;
    case TransitionType.wipeRight:
      return _OverlayEffect.wipeRight;
    case TransitionType.wipeUp:
      return _OverlayEffect.wipeUp;
    case TransitionType.wipeDown:
      return _OverlayEffect.wipeDown;
    case TransitionType.circleFade:
    case TransitionType.dissolveRadial:
    case TransitionType.filmAperture:
    case TransitionType.filmLens:
      return _OverlayEffect.circleReveal;
    case TransitionType.superZoomIn:
    case TransitionType.distortBarrel:
      return _OverlayEffect.zoomIn;
    case TransitionType.superZoomOut:
    case TransitionType.distortPinch:
      return _OverlayEffect.zoomOut;
    case TransitionType.superFlash:
    case TransitionType.lightFlare:
    case TransitionType.lightBloom:
    case TransitionType.lightBurst:
    case TransitionType.lightGlow:
    case TransitionType.lightShimmer:
    case TransitionType.filmFlash:
    case TransitionType.filmBurn:
      return _OverlayEffect.flash;
    case TransitionType.glitchRgb:
    case TransitionType.glitchScan:
    case TransitionType.glitchPixel:
    case TransitionType.glitchGhost:
    case TransitionType.glitchStripe:
    case TransitionType.glitchZap:
    case TransitionType.glitchFlicker:
    case TransitionType.distortSwirl:
    case TransitionType.distortTwirl:
      return _OverlayEffect.glitch;
    case TransitionType.sliceVertical:
    case TransitionType.sliceBar:
    case TransitionType.sliceRadial:
    case TransitionType.ripTear:
    case TransitionType.ripRip:
    case TransitionType.ripPeel:
    case TransitionType.ripSlide:
      return _OverlayEffect.sliceV;
    case TransitionType.sliceHorizontal:
    case TransitionType.sliceRoll:
    case TransitionType.sliceFan:
    case TransitionType.sliceRipple:
    case TransitionType.ripCrumple:
    case TransitionType.ripFold:
    case TransitionType.ripBurn:
      return _OverlayEffect.sliceH;
    default:
      return _OverlayEffect.fade;
  }
}

/// Full-canvas overlay rendered on top of the incoming track.
/// [progress] 0.0 = outgoing fully visible, 1.0 = fully revealed (incoming).
/// [outgoingChild] — previous track's content.  Falls back to solid black when null.
class VeTransitionOverlay extends StatelessWidget {
  final TransitionType type;
  final double progress;
  final Widget? outgoingChild;

  const VeTransitionOverlay({
    super.key,
    required this.type,
    required this.progress,
    this.outgoingChild,
  });

  @override
  Widget build(BuildContext context) {
    final eff = _effectFor(type);
    if (eff == _OverlayEffect.none) return const SizedBox.shrink();

    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final out = outgoingChild ?? Container(color: Colors.black);

    switch (eff) {
      case _OverlayEffect.none:
        return const SizedBox.shrink();

      // ── Cross-dissolve ───────────────────────────────────────────────────
      case _OverlayEffect.fade:
        return Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: out);

      // ── Wipe effects — clip the outgoing to its shrinking region ─────────
      case _OverlayEffect.wipeLeft:
        // Outgoing occupies RIGHT side; incoming enters from left.
        return LayoutBuilder(builder: (_, c) => ClipRect(
          clipper: _EdgeClipper(
              left: c.maxWidth * p, top: 0,
              right: c.maxWidth, bottom: c.maxHeight),
          child: out,
        ));

      case _OverlayEffect.wipeRight:
        // Outgoing occupies LEFT side; incoming enters from right.
        return LayoutBuilder(builder: (_, c) => ClipRect(
          clipper: _EdgeClipper(
              left: 0, top: 0,
              right: c.maxWidth * (1 - p), bottom: c.maxHeight),
          child: out,
        ));

      case _OverlayEffect.wipeUp:
        // Outgoing occupies BOTTOM side; incoming enters from top.
        return LayoutBuilder(builder: (_, c) => ClipRect(
          clipper: _EdgeClipper(
              left: 0, top: c.maxHeight * p,
              right: c.maxWidth, bottom: c.maxHeight),
          child: out,
        ));

      case _OverlayEffect.wipeDown:
        // Outgoing occupies TOP side; incoming enters from bottom.
        return LayoutBuilder(builder: (_, c) => ClipRect(
          clipper: _EdgeClipper(
              left: 0, top: 0,
              right: c.maxWidth, bottom: c.maxHeight * (1 - p)),
          child: out,
        ));

      // ── Circle reveal — outgoing shows OUTSIDE the expanding circle ──────
      case _OverlayEffect.circleReveal:
        return ClipPath(
          clipper: _CircleRevealClipper(p),
          child: out,
        );

      // ── Checkerboard — outgoing fades square by square ───────────────────
      case _OverlayEffect.checkerboard:
        return outgoingChild != null
            ? _CheckerboardOutgoing(progress: p, child: out)
            : CustomPaint(
                painter: _CheckerboardPainter(p),
                child: const SizedBox.expand(),
              );

      // ── Zoom — outgoing scales away ──────────────────────────────────────
      case _OverlayEffect.zoomIn:
        return IgnorePointer(
          child: Opacity(
            opacity: (1.0 - p).clamp(0.0, 1.0),
            child: Transform.scale(scale: 1.0 + p * 0.5, child: out),
          ),
        );

      case _OverlayEffect.zoomOut:
        return IgnorePointer(
          child: Opacity(
            opacity: (1.0 - p).clamp(0.0, 1.0),
            child: Transform.scale(scale: (1.0 - p * 0.35).clamp(0.5, 1.0), child: out),
          ),
        );

      // ── Flash — outgoing fades out then white flash ───────────────────────
      case _OverlayEffect.flash:
        if (p < 0.35) {
          final outAlpha = (1.0 - p / 0.35).clamp(0.0, 1.0);
          final wAlpha   = (p / 0.35).clamp(0.0, 1.0);
          return Stack(children: [
            Opacity(opacity: outAlpha, child: out),
            Opacity(opacity: wAlpha,   child: Container(color: Colors.white)),
          ]);
        } else {
          final wAlpha = (1.0 - (p - 0.35) / 0.65).clamp(0.0, 1.0);
          return Opacity(opacity: wAlpha, child: Container(color: Colors.white));
        }

      // ── Glitch — outgoing with RGB-shift artifacts ────────────────────────
      case _OverlayEffect.glitch:
        return outgoingChild != null
            ? _GlitchOutgoing(progress: p, child: out)
            : CustomPaint(painter: _GlitchPainter(p), child: const SizedBox.expand());

      // ── Slice — outgoing strips slide off in alternating directions ───────
      case _OverlayEffect.sliceV:
        return outgoingChild != null
            ? _SliceOutgoing(progress: p, vertical: true,  child: out)
            : CustomPaint(painter: _SliceVPainter(p), child: const SizedBox.expand());

      case _OverlayEffect.sliceH:
        return outgoingChild != null
            ? _SliceOutgoing(progress: p, vertical: false, child: out)
            : CustomPaint(painter: _SliceHPainter(p), child: const SizedBox.expand());
    }
  }
}

// ── Helper clipper for rect-based wipe effects ─────────────────────────────────

class _EdgeClipper extends CustomClipper<Rect> {
  final double left, top, right, bottom;
  const _EdgeClipper(
      {required this.left, required this.top,
       required this.right, required this.bottom});

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        left.clamp(0, size.width),
        top.clamp(0, size.height),
        right.clamp(0, size.width),
        bottom.clamp(0, size.height),
      );

  @override
  bool shouldReclip(_EdgeClipper o) =>
      left != o.left || top != o.top || right != o.right || bottom != o.bottom;
}

// ── Checkerboard outgoing — shows outgoing inside the squares still visible ────

class _CheckerboardOutgoing extends StatelessWidget {
  final double progress;
  final Widget child;
  const _CheckerboardOutgoing({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      const cols = 10;
      final rows = (cols * c.maxHeight / c.maxWidth).ceil();
      final cw = c.maxWidth / cols;
      final ch = c.maxHeight / rows;

      // Build a clip path covering all still-visible checker squares
      final path = Path();
      for (var r = 0; r < rows; r++) {
        for (var cc = 0; cc < cols; cc++) {
          final delay = ((r + cc) / (rows + cols)) * 0.5;
          final localP = ((progress - delay) / 0.6).clamp(0.0, 1.0);
          if (localP >= 1.0) continue; // square gone
          final shrink = localP * (cw / 2);
          path.addRect(Rect.fromLTWH(
            cc * cw + shrink, r * ch + shrink,
            (cw - shrink * 2).clamp(0, cw),
            (ch - shrink * 2).clamp(0, ch),
          ));
        }
      }

      return ClipPath(
        clipper: _PathClipper(path),
        child: child,
      );
    });
  }
}

class _PathClipper extends CustomClipper<Path> {
  final Path path;
  _PathClipper(this.path);
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(_PathClipper o) => true;
}

// ── Glitch outgoing — outgoing content with RGB-shift overlay ──────────────────

class _GlitchOutgoing extends StatelessWidget {
  final double progress;
  final Widget child;
  const _GlitchOutgoing({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    final alpha = (1.0 - progress * 1.3).clamp(0.0, 1.0);
    final shift = sin(progress * pi * 6) * 8 * (1 - progress);
    return Stack(children: [
      // Cyan ghost shifted right
      Opacity(
        opacity: (alpha * 0.4).clamp(0, 1),
        child: Transform.translate(offset: Offset(shift, 0), child: child),
      ),
      // Magenta ghost shifted left
      Opacity(
        opacity: (alpha * 0.4).clamp(0, 1),
        child: Transform.translate(offset: Offset(-shift, 0), child: child),
      ),
      // Main outgoing fading out
      Opacity(opacity: alpha, child: child),
    ]);
  }
}

// ── Slice outgoing — content strips slide off in alternating directions ─────────

class _SliceOutgoing extends StatelessWidget {
  final double progress;
  final bool vertical;
  final Widget child;
  const _SliceOutgoing(
      {required this.progress, required this.vertical, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      const numSlices = 8;
      final sliceDim =
          vertical ? c.maxWidth / numSlices : c.maxHeight / numSlices;

      return Stack(
        children: List.generate(numSlices, (i) {
          final delay = (i / numSlices) * 0.35;
          final localP = ((progress - delay) / 0.65).clamp(0.0, 1.0);
          final travel = vertical ? c.maxHeight : c.maxWidth;
          final offset = i.isEven ? -(localP * travel) : (localP * travel);

          final clipR = vertical
              ? Rect.fromLTWH(i * sliceDim, 0, sliceDim + 1, c.maxHeight)
              : Rect.fromLTWH(0, i * sliceDim, c.maxWidth, sliceDim + 1);

          return Positioned.fill(
            child: ClipRect(
              clipper: _EdgeClipper(
                left: clipR.left, top: clipR.top,
                right: clipR.right, bottom: clipR.bottom,
              ),
              child: Transform.translate(
                offset: vertical ? Offset(0, offset) : Offset(offset, 0),
                child: child,
              ),
            ),
          );
        }),
      );
    });
  }
}

// ── Custom painters ────────────────────────────────────────────────────────────

class _CircleRevealClipper extends CustomClipper<Path> {
  final double progress;
  _CircleRevealClipper(this.progress);

  @override
  Path getClip(Size size) {
    // 10 % extra so the circle fully covers every corner well before
    // progress reaches 1.0, eliminating corner colour bleed-through.
    final maxRadius =
        sqrt(size.width * size.width + size.height * size.height) / 2 * 1.10;
    final radius = maxRadius * progress;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: radius,
      ));
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(_CircleRevealClipper o) => progress != o.progress;
}

class _CheckerboardPainter extends CustomPainter {
  final double progress;
  _CheckerboardPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 10;
    final rows = (cols * size.height / size.width).ceil();
    final cw = size.width / cols;
    final ch = size.height / rows;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final isBlack = (r + c) % 2 == 0;
        // Each checker disappears at a slightly staggered time
        final delay = ((r + c) / (rows + cols)) * 0.5;
        final localP = ((progress - delay) / 0.6).clamp(0.0, 1.0);
        final alpha = isBlack
            ? (1.0 - localP).clamp(0.0, 1.0)
            : (1.0 - (localP * 0.7)).clamp(0.0, 1.0);
        if (alpha <= 0) continue;
        final paint = Paint()
          ..color = Colors.black.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(c * cw, r * ch, cw + 1, ch + 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter o) => progress != o.progress;
}

class _SliceVPainter extends CustomPainter {
  final double progress;
  _SliceVPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const numSlices = 8;
    final sliceW = size.width / numSlices;
    final paint = Paint()..color = Colors.black;
    for (var i = 0; i < numSlices; i++) {
      final delay = (i / numSlices) * 0.4;
      final localP = ((progress - delay) / 0.6).clamp(0.0, 1.0);
      final dy = i.isEven
          ? -(localP * (size.height + 10))
          : (localP * (size.height + 10));
      canvas.drawRect(
        Rect.fromLTWH(i * sliceW, dy, sliceW + 1, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SliceVPainter o) => progress != o.progress;
}

class _SliceHPainter extends CustomPainter {
  final double progress;
  _SliceHPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const numSlices = 7;
    final sliceH = size.height / numSlices;
    final paint = Paint()..color = Colors.black;
    for (var i = 0; i < numSlices; i++) {
      final delay = (i / numSlices) * 0.4;
      final localP = ((progress - delay) / 0.6).clamp(0.0, 1.0);
      final dx = i.isEven
          ? -(localP * (size.width + 10))
          : (localP * (size.width + 10));
      canvas.drawRect(
        Rect.fromLTWH(dx, i * sliceH, size.width, sliceH + 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SliceHPainter o) => progress != o.progress;
}

class _GlitchPainter extends CustomPainter {
  final double progress;
  _GlitchPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final blackAlpha = (1.0 - progress * 1.6).clamp(0.0, 1.0);

    // Draw horizontal scan noise bars
    final numBars = 6;
    for (var i = 0; i < numBars; i++) {
      final t = (progress * 3 + i * 0.37) % 1.0;
      final y = (i / numBars + t * 0.15) % 1.0 * size.height;
      final barH = size.height * 0.04;
      final barAlpha = (1.0 - progress).clamp(0.0, 1.0) * 0.6;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, barH),
        Paint()..color = Colors.black.withValues(alpha: barAlpha),
      );
    }

    // Cyan/magenta channel shift lines
    if (progress < 0.7) {
      final shiftX = sin(progress * pi * 4) * 12 * (1.0 - progress);
      final cAlpha = (0.3 * (1 - progress * 1.5)).clamp(0.0, 0.3);
      canvas.drawRect(
        Rect.fromLTWH(shiftX, 0, size.width, size.height),
        Paint()
          ..color = const Color(0xFF00FFFF).withValues(alpha: cAlpha)
          ..blendMode = BlendMode.srcOver,
      );
      canvas.drawRect(
        Rect.fromLTWH(-shiftX, 0, size.width, size.height),
        Paint()
          ..color = const Color(0xFFFF00FF).withValues(alpha: cAlpha)
          ..blendMode = BlendMode.srcOver,
      );
    }

    // Main black fade
    if (blackAlpha > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: blackAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_GlitchPainter o) => progress != o.progress;
}

// ── Dialog ─────────────────────────────────────────────────────────────────────

Future<void> showVeTransitionsDialog({
  required BuildContext context,
  required TimelineTrack track,
  required ValueChanged<TimelineTrack> onLiveUpdate,
  required VoidCallback onConfirm,
  required VoidCallback onCancel,
}) {
  bool applied = false;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return _TransitionSheet(
        selectedType: track.transitionInType,
        duration: track.transitionInDuration,
        onLiveUpdate: (t, d) => onLiveUpdate(track.copyWith(
          transitionInType: t,
          transitionInDuration: d,
        )),
        onConfirm: () {
          applied = true;
          onConfirm();
          Navigator.of(ctx).pop();
        },
        onCancel: () {
          onCancel();
          Navigator.of(ctx).pop();
        },
      );
    },
  ).then((_) {
    if (!applied) onCancel();
  });
}

class _TransitionSheet extends StatefulWidget {
  final TransitionType selectedType;
  final double duration;
  final void Function(TransitionType, double) onLiveUpdate;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _TransitionSheet({
    required this.selectedType,
    required this.duration,
    required this.onLiveUpdate,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_TransitionSheet> createState() => _TransitionSheetState();
}

class _TransitionSheetState extends State<_TransitionSheet> {
  late TransitionType _selected;
  late double _duration;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedType;
    _duration = widget.duration;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111E2F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),

          // ── Header row ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.done_all,
                      color: Colors.white60, size: 22),
                ),
                const Expanded(
                  child: Text(
                    'Transition',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onConfirm,
                  icon: const Icon(Icons.check,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
          ),

          // ── Duration slider ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                const Text('Duration',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF00C8FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF00C8FF),
                      overlayColor: const Color(0xFF00C8FF).withValues(alpha: 0.2),
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _duration,
                      min: 0.3,
                      max: 2.0,
                      onChanged: _selected == TransitionType.none
                          ? null
                          : (v) {
                              setState(() => _duration = v);
                              widget.onLiveUpdate(_selected, v);
                            },
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${_duration.toStringAsFixed(1)}s',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF00C8FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── Category list ─────────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.40,
            ),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              shrinkWrap: true,
              itemCount: _kCategories.length,
              itemBuilder: (ctx, ci) {
                final cat = _kCategories[ci];
                return _buildCategoryRow(cat);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(_TransitionCategory cat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(left: 16, top: 14, right: 16, bottom: 6),
          child: Text(
            cat.name,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 76,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cat.items.length,
            itemBuilder: (ctx, i) {
              final item = cat.items[i];
              final isSelected = _selected == item.type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TransitionButton(
                  item: item,
                  circleColor: cat.circleColor,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() => _selected = item.type);
                    widget.onLiveUpdate(item.type, _duration);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TransitionButton extends StatelessWidget {
  final _TransitionItem item;
  final Color circleColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _TransitionButton({
    required this.item,
    required this.circleColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2.5)
                  : Border.all(color: Colors.white12, width: 1),
            ),
            child: Icon(
              item.icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 9,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
