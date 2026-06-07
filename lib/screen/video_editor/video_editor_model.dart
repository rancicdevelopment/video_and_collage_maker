import 'dart:math';

import 'package:flutter/material.dart';

enum TrackType { video, audio, image, text }

// ── Transition types ──────────────────────────────────────────────────────────
enum TransitionType {
  // BASIC
  none,
  checkerboard,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  circleFade,
  // SUPER
  superZoomIn,
  superZoomOut,
  superRotate,
  superBlur,
  superFlash,
  superSpin,
  superPush,
  // GLITCH
  glitchRgb,
  glitchScan,
  glitchPixel,
  glitchGhost,
  glitchStripe,
  glitchZap,
  glitchFlicker,
  // DISSOLVE
  dissolvePixel,
  dissolveRadial,
  dissolveSpiral,
  dissolveDrop,
  dissolveSmear,
  dissolveShatter,
  dissolveStar,
  // SLICE
  sliceVertical,
  sliceHorizontal,
  sliceBar,
  sliceRoll,
  sliceFan,
  sliceRadial,
  sliceRipple,
  // LIGHT
  lightFlare,
  lightBloom,
  lightPulse,
  lightGlow,
  lightBurst,
  lightShimmer,
  lightFade,
  // FILM
  filmBurn,
  filmLeader,
  filmFlicker,
  filmScratch,
  filmLens,
  filmFlash,
  filmAperture,
  // DISTORT
  distortSwirl,
  distortWave,
  distortBarrel,
  distortPinch,
  distortMirror,
  distortRipple,
  distortTwirl,
  // RIPPED PAPER
  ripTear,
  ripRip,
  ripCrumple,
  ripFold,
  ripPeel,
  ripSlide,
  ripBurn,
}

// ── Color matrix helpers ──────────────────────────────────────────────────────

/// Multiplies two 4×5 ColorFilter matrices (flat row-major lists of 20 values).
/// Result = A applied after B  (i.e. first B, then A).
List<double> _mulMat(List<double> a, List<double> b) {
  final r = List<double>.filled(20, 0.0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      if (col == 4) {
        // Offset column: A_row * B_offsets + A_offset
        var s = a[row * 5 + 4];
        for (var k = 0; k < 4; k++) { s += a[row * 5 + k] * b[k * 5 + 4]; }
        r[row * 5 + 4] = s;
      } else {
        var s = 0.0;
        for (var k = 0; k < 4; k++) { s += a[row * 5 + k] * b[k * 5 + col]; }
        r[row * 5 + col] = s;
      }
    }
  }
  return r;
}

/// Builds a 4×5 color-filter matrix from per-track filter parameters.
/// brightness  : -1.0 (darkest) … 0.0 (unchanged) … 1.0 (brightest)
/// contrast    :  0.0 (flat gray) … 1.0 (unchanged) … 2.0 (high contrast)
/// saturation  :  0.0 (grayscale) … 1.0 (unchanged) … 2.0 (vivid)
/// hue         : -180 … 0 (unchanged) … 180 degrees
/// temperature : -1.0 (cool/blue) … 0.0 (neutral) … 1.0 (warm/orange)
List<double> buildTrackColorMatrix({
  double brightness   = 0.0,
  double contrast     = 1.0,
  double saturation   = 1.0,
  double hue          = 0.0,
  double temperature  = 0.0,
}) {
  // ── Saturation + contrast + brightness ──────────────────────────────────
  const rw = 0.2126, gw = 0.7152, bw = 0.0722;

  final sr  = rw + (1 - rw) * saturation;
  final sg  = gw + (1 - gw) * saturation;
  final sb  = bw + (1 - bw) * saturation;
  final srg = gw - gw * saturation;
  final srb = bw - bw * saturation;
  final sgr = rw - rw * saturation;
  final sgb = bw - bw * saturation;
  final sbr = rw - rw * saturation;
  final sbg = gw - gw * saturation;

  final baseOffset = 127.5 * (1.0 - contrast) + brightness * 255.0;

  // ── Color temperature: warm → +R −B, cool → −R +B ───────────────────────
  // Coefficients tuned for natural-looking warmth/coolness.
  final tempR = temperature * 255.0 *  0.12;
  final tempG = temperature * 255.0 *  0.04;
  final tempB = temperature * 255.0* -0.12;

  final scbMat = [
    sr  * contrast, srg * contrast, srb * contrast, 0.0, baseOffset + tempR,
    sgr * contrast, sg  * contrast, sgb * contrast, 0.0, baseOffset + tempG,
    sbr * contrast, sbg * contrast, sb  * contrast, 0.0, baseOffset + tempB,
    0.0,            0.0,            0.0,            1.0, 0.0,
  ];

  if (hue == 0.0) return scbMat;

  // ── Hue rotation (Haeberli method, luma-preserving) ─────────────────────
  // Reference weights matching Photoshop / CSS hue-rotate filter
  const hrw = 0.213, hgw = 0.715, hbw = 0.072;
  final rad = hue * pi / 180.0;
  final c = cos(rad);
  final s = sin(rad);

  final hueMat = [
    hrw + c*(1-hrw) + s*(-hrw),     hgw + c*(-hgw)  + s*(-hgw),     hbw + c*(-hbw)  + s*(1-hbw),    0.0, 0.0,
    hrw + c*(-hrw)  + s*(0.143),    hgw + c*(1-hgw) + s*(0.140),    hbw + c*(-hbw)  + s*(-0.283),   0.0, 0.0,
    hrw + c*(-hrw)  + s*(hrw-1),    hgw + c*(-hgw)  + s*(hgw),      hbw + c*(1-hbw) + s*(hbw),      0.0, 0.0,
    0.0,                             0.0,                             0.0,                             1.0, 0.0,
  ];

  // Apply saturation/contrast/brightness first, then hue rotation
  return _mulMat(hueMat, scbMat);
}

const List<Color> kVeTrackColors = [
  Color(0xFF7B6CF6), // purple
  Color(0xFFE8A020), // orange
  Color(0xFF2CB67D), // teal-green
  Color(0xFFE05C7B), // pink-red
  Color(0xFF5BC4D0), // cyan
  Color(0xFFD4A017), // gold
];

class TimelineTrack {
  final String id;
  final String filePath;
  final String title;
  final TrackType trackType;
  final Duration duration;
  final Duration startOffset;
  final Duration trimStart;
  final Duration trimEnd;
  final double volume;   // 0.0–2.0
  final double speed;    // 0.5–2.0
  final double fadeInSecs;
  final double fadeOutSecs;
  final double opacity;      // 0.0–1.0 (video/image tracks)
  final int rotation;        // 0, 90, 180, 270 degrees (video/image tracks only)
  final bool mirrorH;        // horizontal flip / mirror (video/image tracks only)
  final double overlayScale; // 0.1–1.0 (1.0 = full canvas)
  final double overlayX;     // -1.0–1.0 (0.0 = centered)
  final double overlayY;     // -1.0–1.0 (0.0 = centered)
  final Color color;
  // Audio tracks: normalised 0..1 amplitude bars
  final List<double> waveformBars;
  // Video tracks: extracted thumbnail file paths (filmstrip)
  final List<String> thumbnailPaths;
  // True while thumbnail/waveform extraction is still in progress (transient, never serialised)
  final bool thumbnailsLoading;
  // EQ: true when FFmpeg-baked EQ is applied to this audio track
  final bool eqApplied;
  // EQ: original file path before EQ was applied (null = EQ never applied)
  final String? preEqFilePath;
  // EQ: saved 10-band gain values (null = never opened / all flat)
  final List<double>? eqGains;
  // Visual filters (video/image tracks only)
  final double brightness;       // -1.0 … 0.0 (default) … 1.0
  final double contrast;         //  0.0 … 1.0 (default) … 2.0
  final double saturation;       //  0.0 … 1.0 (default) … 2.0
  final double hue;              // -180 … 0.0 (default) … 180 degrees
  final double vignetteStrength; //  0.0 (none/default) … 1.0 (strong)
  final double blurRadius;       //  0.0 (none/default) … 20.0 (heavy blur)
  final double grainStrength;    //  0.0 (none/default) … 1.0 (heavy grain)
  final double temperature;      // -1.0 (cool/blue) … 0.0 (neutral) … 1.0 (warm/orange)
  // Shadow / glow (video/image tracks only)
  final double shadowRadius;     //  0.0 (none/default) … 25.0 (heavy)
  final double shadowOpacity;    //  0.0 … 1.0 (default 0.6)
  final Color  shadowColor;      // default Colors.black
  final double shadowOffsetX;    // -20.0 … 20.0 (0 = centered/glow)
  final double shadowOffsetY;    // -20.0 … 20.0 (0 = centered/glow)
  // Text / title overlay (text tracks only)
  final String textContent;      // the text string to display
  final double fontSize;         // 10 … 120
  final Color  textColor;        // default white
  final Color  textBgColor;      // box background color, default black
  final double textBgOpacity;    // 0.0 (none) … 1.0 (opaque)
  final bool   textBold;
  final bool   textItalic;
  final String? fontFamily;        // null = system default
  final Color  textOutlineColor;  // outline/stroke color, default black
  final double textOutlineWidth;  // 0.0 (none) … 8.0
  final int    textAlignIndex;    // 0=left, 1=center, 2=right
  final double letterSpacing;     // -5.0 … 20.0 (0.0 = default)
  final double lineHeight;        // 0.8 … 3.0   (1.2 = default)
  final bool   textUnderline;     // underline decoration
  final bool   textStrikethrough; // strikethrough decoration
  final int    textCaseIndex;     // 0=none, 1=UPPER, 2=lower, 3=Capitalize
  final double textPaddingH;      // horizontal padding 0 … 60
  final double textPaddingV;      // vertical padding   0 … 60
  final double textBgRadius;      // background border radius 0 … 60
  final int    textBlendModeIndex; // index into _kTextBlendModes (0 = normal)
  final double textRotation;       // -180 … 180 degrees (0 = no rotation)
  final double textGlowRadius;       // 0.0 (none) … 30.0 — glow spread
  final Color  textGlowColor;        // glow color, default white
  final double textPathCurve;        // -1.0 (down) … 0.0 (straight) … 1.0 (up)
  final bool   textGradientEnabled;  // use gradient instead of solid color
  final Color  textGradientColor1;   // gradient start color
  final Color  textGradientColor2;   // gradient end color
  final double textGradientAngle;    // 0 = L→R, 90 = T→B, degrees
  // Crop (video/image tracks only)
  final double cropX;           // 0.0–1.0  left edge fraction (default 0.0)
  final double cropY;           // 0.0–1.0  top edge fraction  (default 0.0)
  final double cropW;           // 0.0–1.0  width fraction     (default 1.0)
  final double cropH;           // 0.0–1.0  height fraction    (default 1.0)
  final double cropRotation;    // -45 … 45 degrees            (default 0.0)
  // Mask (video/image tracks only)
  final int    maskShapeIndex;  // 0=none 1=circle 2=rect 3=heart 4=star 5=triangle 6=diamond
  final double maskScale;       // 0.1–1.5  (1.0 = fills clip)
  final double maskFeather;     // 0.0 (hard) … 1.0 (very soft)
  final bool   maskInverted;    // invert: show outside shape, hide inside
  // Play Backwards (video only)
  final bool   playBackwards;   // reverse video (and audio) during export
  // Voice / Audio Effect (audio + video tracks)
  final int    voiceEffectIndex; // 0=none 1=chipmunk 2=deep 3=robot 4=echo
  // Chroma Key / Green Screen (video/image only)
  final bool   chromakeyEnabled;
  final Color  chromakeyColor;       // key colour to remove (default green)
  final double chromakeySimilarity;  // 0.01–0.50
  final double chromakeyBlend;       // 0.00–0.20 (soft edge)
  // Stabilizer (video only)
  final bool   isStabilized;         // apply deshake during export
  // Transition (video/image only) — applied at the IN point of this clip
  final TransitionType transitionInType;    // type of transition (default = none)
  final double         transitionInDuration; // seconds (0.3–2.0, default 0.5)

  const TimelineTrack({
    required this.id,
    required this.filePath,
    required this.title,
    required this.trackType,
    required this.duration,
    this.startOffset = Duration.zero,
    this.trimStart = Duration.zero,
    this.trimEnd = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.fadeInSecs = 0.0,
    this.fadeOutSecs = 0.0,
    this.opacity = 1.0,
    this.rotation = 0,
    this.mirrorH = false,
    this.overlayScale = 1.0,
    this.overlayX = 0.0,
    this.overlayY = 0.0,
    required this.color,
    this.waveformBars = const [],
    this.thumbnailPaths = const [],
    this.thumbnailsLoading = false,
    this.eqApplied = false,
    this.preEqFilePath,
    this.eqGains,
    this.brightness       = 0.0,
    this.contrast         = 1.0,
    this.saturation       = 1.0,
    this.hue              = 0.0,
    this.vignetteStrength = 0.0,
    this.blurRadius       = 0.0,
    this.grainStrength    = 0.0,
    this.temperature      = 0.0,
    this.shadowRadius     = 0.0,
    this.shadowOpacity    = 0.6,
    this.shadowColor      = Colors.black,
    this.shadowOffsetX    = 0.0,
    this.shadowOffsetY    = 0.0,
    this.textContent      = '',
    this.fontSize         = 48.0,
    this.textColor        = Colors.white,
    this.textBgColor      = Colors.black,
    this.textBgOpacity    = 0.0,
    this.textBold         = false,
    this.textItalic       = false,
    this.fontFamily,
    this.textOutlineColor = Colors.black,
    this.textOutlineWidth = 0.0,
    this.textAlignIndex   = 1,
    this.letterSpacing    = 0.0,
    this.lineHeight       = 1.2,
    this.textUnderline     = false,
    this.textStrikethrough = false,
    this.textCaseIndex     = 0,
    this.textPaddingH       = 0.0,
    this.textPaddingV       = 0.0,
    this.textBgRadius       = 8.0,
    this.textBlendModeIndex    = 0,
    this.textRotation          = 0.0,
    this.textGlowRadius        = 0.0,
    this.textGlowColor         = Colors.white,
    this.textPathCurve         = 0.0,
    this.textGradientEnabled   = false,
    this.textGradientColor1    = Colors.yellow,
    this.textGradientColor2    = Colors.pink,
    this.textGradientAngle     = 0.0,
    this.cropX                 = 0.0,
    this.cropY                 = 0.0,
    this.cropW                 = 1.0,
    this.cropH                 = 1.0,
    this.cropRotation          = 0.0,
    this.maskShapeIndex        = 0,
    this.maskScale             = 1.0,
    this.maskFeather           = 0.0,
    this.maskInverted          = false,
    this.playBackwards         = false,
    this.voiceEffectIndex      = 0,
    this.chromakeyEnabled      = false,
    this.chromakeyColor        = const Color(0xFF00FF00),
    this.chromakeySimilarity   = 0.10,
    this.chromakeyBlend        = 0.0,
    this.isStabilized          = false,
    this.transitionInType      = TransitionType.none,
    this.transitionInDuration  = 0.5,
  });

  Duration get effectiveDuration {
    final trimmed = duration - trimStart - trimEnd;
    if (trimmed.isNegative) return Duration.zero;
    final us = (trimmed.inMicroseconds / speed).round();
    return Duration(microseconds: us < 0 ? 0 : us);
  }

  Duration get endTime => startOffset + effectiveDuration;

  bool get isVideo => trackType == TrackType.video;
  bool get isAudio => trackType == TrackType.audio;
  bool get isImage => trackType == TrackType.image;
  bool get isText  => trackType == TrackType.text;

  /// True when color-matrix filter (brightness/contrast/saturation/hue) is active.
  bool get hasColorMatrix =>
      brightness != 0.0 || contrast != 1.0 ||
      saturation != 1.0 || hue != 0.0 || temperature != 0.0;

  /// True when any visual filter (including vignette/blur) differs from default.
  bool get hasFilter =>
      hasColorMatrix || vignetteStrength != 0.0 ||
      blurRadius != 0.0 || grainStrength != 0.0;

  /// True when shadow/glow effect is active.
  bool get hasShadow => shadowRadius > 0.0 && shadowOpacity > 0.0;

  /// BoxShadow for this track's shadow/glow effect.
  BoxShadow get boxShadow => BoxShadow(
        color: shadowColor.withValues(alpha: shadowOpacity),
        blurRadius: shadowRadius,
        spreadRadius: shadowRadius * 0.25,
        offset: Offset(shadowOffsetX, shadowOffsetY),
      );

  /// ColorFilter matrix for this track's visual filter settings.
  ColorFilter get colorFilter => ColorFilter.matrix(buildTrackColorMatrix(
        brightness:  brightness,
        contrast:    contrast,
        saturation:  saturation,
        hue:         hue,
        temperature: temperature,
      ));

  // Sentinel used in copyWith to distinguish "keep current value" from
  // "explicitly set to null" for nullable fields like preEqFilePath.
  static const Object _keep = Object();

  TimelineTrack copyWith({
    String? id,
    String? filePath,
    String? title,
    TrackType? trackType,
    Duration? duration,
    Duration? startOffset,
    Duration? trimStart,
    Duration? trimEnd,
    double? volume,
    double? speed,
    double? fadeInSecs,
    double? fadeOutSecs,
    double? opacity,
    int? rotation,
    bool? mirrorH,
    double? overlayScale,
    double? overlayX,
    double? overlayY,
    Color? color,
    List<double>? waveformBars,
    List<String>? thumbnailPaths,
    bool? thumbnailsLoading,
    bool? eqApplied,
    Object? preEqFilePath = _keep,
    Object? eqGains = _keep,
    double? brightness,
    double? contrast,
    double? saturation,
    double? hue,
    double? vignetteStrength,
    double? blurRadius,
    double? grainStrength,
    double? temperature,
    double? shadowRadius,
    double? shadowOpacity,
    Color?  shadowColor,
    double? shadowOffsetX,
    double? shadowOffsetY,
    String? textContent,
    double? fontSize,
    Color?  textColor,
    Color?  textBgColor,
    double? textBgOpacity,
    bool?   textBold,
    bool?   textItalic,
    Object? fontFamily = _keep,
    Color?  textOutlineColor,
    double? textOutlineWidth,
    int?    textAlignIndex,
    double? letterSpacing,
    double? lineHeight,
    bool?   textUnderline,
    bool?   textStrikethrough,
    int?    textCaseIndex,
    double? textPaddingH,
    double? textPaddingV,
    double? textBgRadius,
    int?    textBlendModeIndex,
    double? textRotation,
    double? textGlowRadius,
    Color?  textGlowColor,
    double? textPathCurve,
    bool?   textGradientEnabled,
    Color?  textGradientColor1,
    Color?  textGradientColor2,
    double? textGradientAngle,
    double? cropX,
    double? cropY,
    double? cropW,
    double? cropH,
    double? cropRotation,
    int?    maskShapeIndex,
    double? maskScale,
    double? maskFeather,
    bool?   maskInverted,
    bool?   playBackwards,
    int?    voiceEffectIndex,
    bool?   chromakeyEnabled,
    Color?  chromakeyColor,
    double? chromakeySimilarity,
    double? chromakeyBlend,
    bool?   isStabilized,
    TransitionType? transitionInType,
    double?         transitionInDuration,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      trackType: trackType ?? this.trackType,
      duration: duration ?? this.duration,
      startOffset: startOffset ?? this.startOffset,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      fadeInSecs: fadeInSecs ?? this.fadeInSecs,
      fadeOutSecs: fadeOutSecs ?? this.fadeOutSecs,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      mirrorH: mirrorH ?? this.mirrorH,
      overlayScale: overlayScale ?? this.overlayScale,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
      color: color ?? this.color,
      waveformBars: waveformBars ?? this.waveformBars,
      thumbnailPaths: thumbnailPaths ?? this.thumbnailPaths,
      thumbnailsLoading: thumbnailsLoading ?? this.thumbnailsLoading,
      eqApplied: eqApplied ?? this.eqApplied,
      preEqFilePath: identical(preEqFilePath, _keep)
          ? this.preEqFilePath
          : preEqFilePath as String?,
      eqGains: identical(eqGains, _keep)
          ? this.eqGains
          : eqGains as List<double>?,
      brightness:       brightness       ?? this.brightness,
      contrast:         contrast         ?? this.contrast,
      saturation:       saturation       ?? this.saturation,
      hue:              hue              ?? this.hue,
      vignetteStrength: vignetteStrength ?? this.vignetteStrength,
      blurRadius:       blurRadius       ?? this.blurRadius,
      grainStrength:    grainStrength    ?? this.grainStrength,
      temperature:      temperature      ?? this.temperature,
      shadowRadius:     shadowRadius     ?? this.shadowRadius,
      shadowOpacity:    shadowOpacity    ?? this.shadowOpacity,
      shadowColor:      shadowColor      ?? this.shadowColor,
      shadowOffsetX:    shadowOffsetX    ?? this.shadowOffsetX,
      shadowOffsetY:    shadowOffsetY    ?? this.shadowOffsetY,
      textContent:      textContent      ?? this.textContent,
      fontSize:         fontSize         ?? this.fontSize,
      textColor:        textColor        ?? this.textColor,
      textBgColor:      textBgColor      ?? this.textBgColor,
      textBgOpacity:    textBgOpacity    ?? this.textBgOpacity,
      textBold:         textBold         ?? this.textBold,
      textItalic:       textItalic       ?? this.textItalic,
      fontFamily:       identical(fontFamily, _keep)
          ? this.fontFamily
          : fontFamily as String?,
      textOutlineColor: textOutlineColor ?? this.textOutlineColor,
      textOutlineWidth: textOutlineWidth ?? this.textOutlineWidth,
      textAlignIndex:   textAlignIndex   ?? this.textAlignIndex,
      letterSpacing:      letterSpacing      ?? this.letterSpacing,
      lineHeight:         lineHeight         ?? this.lineHeight,
      textUnderline:      textUnderline      ?? this.textUnderline,
      textStrikethrough:  textStrikethrough  ?? this.textStrikethrough,
      textCaseIndex:      textCaseIndex      ?? this.textCaseIndex,
      textPaddingH:        textPaddingH        ?? this.textPaddingH,
      textPaddingV:        textPaddingV        ?? this.textPaddingV,
      textBgRadius:        textBgRadius        ?? this.textBgRadius,
      textBlendModeIndex:   textBlendModeIndex   ?? this.textBlendModeIndex,
      textRotation:         textRotation         ?? this.textRotation,
      textGlowRadius:       textGlowRadius       ?? this.textGlowRadius,
      textGlowColor:        textGlowColor        ?? this.textGlowColor,
      textPathCurve:        textPathCurve        ?? this.textPathCurve,
      textGradientEnabled:  textGradientEnabled  ?? this.textGradientEnabled,
      textGradientColor1:   textGradientColor1   ?? this.textGradientColor1,
      textGradientColor2:   textGradientColor2   ?? this.textGradientColor2,
      textGradientAngle:    textGradientAngle    ?? this.textGradientAngle,
      cropX:                cropX                ?? this.cropX,
      cropY:                cropY                ?? this.cropY,
      cropW:                cropW                ?? this.cropW,
      cropH:                cropH                ?? this.cropH,
      cropRotation:         cropRotation         ?? this.cropRotation,
      maskShapeIndex:       maskShapeIndex       ?? this.maskShapeIndex,
      maskScale:            maskScale            ?? this.maskScale,
      maskFeather:          maskFeather          ?? this.maskFeather,
      maskInverted:         maskInverted         ?? this.maskInverted,
      playBackwards:        playBackwards        ?? this.playBackwards,
      voiceEffectIndex:     voiceEffectIndex     ?? this.voiceEffectIndex,
      chromakeyEnabled:     chromakeyEnabled     ?? this.chromakeyEnabled,
      chromakeyColor:       chromakeyColor       ?? this.chromakeyColor,
      chromakeySimilarity:  chromakeySimilarity  ?? this.chromakeySimilarity,
      chromakeyBlend:       chromakeyBlend       ?? this.chromakeyBlend,
      isStabilized:         isStabilized         ?? this.isStabilized,
      transitionInType:     transitionInType     ?? this.transitionInType,
      transitionInDuration: transitionInDuration ?? this.transitionInDuration,
    );
  }

  /// True when a mask shape is active.
  bool get hasMask => maskShapeIndex > 0;

  /// True when the crop/rotation differs from the default (no crop applied).
  bool get hasCrop =>
      cropX != 0.0 || cropY != 0.0 || cropW != 1.0 ||
      cropH != 1.0 || cropRotation != 0.0;

  static String generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'title': title,
    'trackType': trackType.name,
    'duration': duration.inMicroseconds,
    'startOffset': startOffset.inMicroseconds,
    'trimStart': trimStart.inMicroseconds,
    'trimEnd': trimEnd.inMicroseconds,
    'volume': volume,
    'speed': speed,
    'fadeInSecs': fadeInSecs,
    'fadeOutSecs': fadeOutSecs,
    'opacity': opacity,
    'rotation': rotation,
    'mirrorH': mirrorH,
    'overlayScale': overlayScale,
    'overlayX': overlayX,
    'overlayY': overlayY,
    'color': color.toARGB32(),
    'eqApplied': eqApplied,
    'preEqFilePath': preEqFilePath,
    'eqGains': eqGains,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hue': hue,
    'vignetteStrength': vignetteStrength,
    'blurRadius': blurRadius,
    'grainStrength': grainStrength,
    'temperature': temperature,
    'shadowRadius': shadowRadius,
    'shadowOpacity': shadowOpacity,
    'shadowColor': shadowColor.toARGB32(),
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'textContent': textContent,
    'fontSize': fontSize,
    'textColor': textColor.toARGB32(),
    'textBgColor': textBgColor.toARGB32(),
    'textBgOpacity': textBgOpacity,
    'textBold': textBold,
    'textItalic': textItalic,
    'fontFamily': fontFamily,
    'textOutlineColor': textOutlineColor.toARGB32(),
    'textOutlineWidth': textOutlineWidth,
    'textAlignIndex': textAlignIndex,
    'letterSpacing': letterSpacing,
    'lineHeight': lineHeight,
    'textUnderline': textUnderline,
    'textStrikethrough': textStrikethrough,
    'textCaseIndex': textCaseIndex,
    'textPaddingH': textPaddingH,
    'textPaddingV': textPaddingV,
    'textBgRadius': textBgRadius,
    'textBlendModeIndex': textBlendModeIndex,
    'textRotation': textRotation,
    'textGlowRadius': textGlowRadius,
    'textGlowColor': textGlowColor.toARGB32(),
    'textPathCurve': textPathCurve,
    'textGradientEnabled': textGradientEnabled,
    'textGradientColor1': textGradientColor1.toARGB32(),
    'textGradientColor2': textGradientColor2.toARGB32(),
    'textGradientAngle': textGradientAngle,
    'cropX': cropX,
    'cropY': cropY,
    'cropW': cropW,
    'cropH': cropH,
    'cropRotation': cropRotation,
    'maskShapeIndex': maskShapeIndex,
    'maskScale': maskScale,
    'maskFeather': maskFeather,
    'maskInverted': maskInverted,
    'playBackwards': playBackwards,
    'voiceEffectIndex': voiceEffectIndex,
    'chromakeyEnabled': chromakeyEnabled,
    'chromakeyColor': chromakeyColor.toARGB32(),
    'chromakeySimilarity': chromakeySimilarity,
    'chromakeyBlend': chromakeyBlend,
    'isStabilized': isStabilized,
    'transitionInType': transitionInType.name,
    'transitionInDuration': transitionInDuration,
  };

  factory TimelineTrack.fromJson(Map<String, dynamic> j) => TimelineTrack(
    id: j['id'] as String,
    filePath: j['filePath'] as String,
    title: j['title'] as String,
    trackType: TrackType.values.byName(j['trackType'] as String),
    duration: Duration(microseconds: j['duration'] as int),
    startOffset: Duration(microseconds: j['startOffset'] as int),
    trimStart: Duration(microseconds: j['trimStart'] as int),
    trimEnd: Duration(microseconds: j['trimEnd'] as int),
    volume: (j['volume'] as num).toDouble(),
    speed: (j['speed'] as num).toDouble(),
    fadeInSecs: (j['fadeInSecs'] as num).toDouble(),
    fadeOutSecs: (j['fadeOutSecs'] as num).toDouble(),
    opacity: (j['opacity'] as num).toDouble(),
    rotation: j['rotation'] as int,
    mirrorH: j['mirrorH'] as bool? ?? false,
    overlayScale: (j['overlayScale'] as num).toDouble(),
    overlayX: (j['overlayX'] as num).toDouble(),
    overlayY: (j['overlayY'] as num).toDouble(),
    color: Color(j['color'] as int),
    eqApplied: j['eqApplied'] as bool,
    preEqFilePath: j['preEqFilePath'] as String?,
    eqGains: (j['eqGains'] as List<dynamic>?)
        ?.map((e) => (e as num).toDouble())
        .toList(),
    brightness: (j['brightness'] as num).toDouble(),
    contrast: (j['contrast'] as num).toDouble(),
    saturation: (j['saturation'] as num).toDouble(),
    hue: (j['hue'] as num).toDouble(),
    vignetteStrength: (j['vignetteStrength'] as num).toDouble(),
    blurRadius: (j['blurRadius'] as num).toDouble(),
    grainStrength: (j['grainStrength'] as num).toDouble(),
    temperature: (j['temperature'] as num).toDouble(),
    shadowRadius: (j['shadowRadius'] as num).toDouble(),
    shadowOpacity: (j['shadowOpacity'] as num).toDouble(),
    shadowColor: Color(j['shadowColor'] as int),
    shadowOffsetX: (j['shadowOffsetX'] as num).toDouble(),
    shadowOffsetY: (j['shadowOffsetY'] as num).toDouble(),
    textContent: j['textContent'] as String,
    fontSize: (j['fontSize'] as num).toDouble(),
    textColor: Color(j['textColor'] as int),
    textBgColor: Color(j['textBgColor'] as int),
    textBgOpacity: (j['textBgOpacity'] as num).toDouble(),
    textBold: j['textBold'] as bool,
    textItalic: j['textItalic'] as bool,
    fontFamily: j['fontFamily'] as String?,
    textOutlineColor: Color(j['textOutlineColor'] as int),
    textOutlineWidth: (j['textOutlineWidth'] as num).toDouble(),
    textAlignIndex: j['textAlignIndex'] as int,
    letterSpacing: (j['letterSpacing'] as num).toDouble(),
    lineHeight: (j['lineHeight'] as num).toDouble(),
    textUnderline: j['textUnderline'] as bool,
    textStrikethrough: j['textStrikethrough'] as bool,
    textCaseIndex: j['textCaseIndex'] as int,
    textPaddingH: (j['textPaddingH'] as num).toDouble(),
    textPaddingV: (j['textPaddingV'] as num).toDouble(),
    textBgRadius: (j['textBgRadius'] as num).toDouble(),
    textBlendModeIndex: j['textBlendModeIndex'] as int,
    textRotation: (j['textRotation'] as num).toDouble(),
    textGlowRadius: (j['textGlowRadius'] as num).toDouble(),
    textGlowColor: Color(j['textGlowColor'] as int),
    textPathCurve: (j['textPathCurve'] as num).toDouble(),
    textGradientEnabled: j['textGradientEnabled'] as bool,
    textGradientColor1: Color(j['textGradientColor1'] as int),
    textGradientColor2: Color(j['textGradientColor2'] as int),
    textGradientAngle: (j['textGradientAngle'] as num).toDouble(),
    cropX: (j['cropX'] as num).toDouble(),
    cropY: (j['cropY'] as num).toDouble(),
    cropW: (j['cropW'] as num).toDouble(),
    cropH: (j['cropH'] as num).toDouble(),
    cropRotation: (j['cropRotation'] as num).toDouble(),
    maskShapeIndex:      j['maskShapeIndex'] as int? ?? 0,
    maskScale:           (j['maskScale']  as num?)?.toDouble() ?? 1.0,
    maskFeather:         (j['maskFeather'] as num?)?.toDouble() ?? 0.0,
    maskInverted:        j['maskInverted'] as bool? ?? false,
    playBackwards:       j['playBackwards'] as bool? ?? false,
    voiceEffectIndex:    j['voiceEffectIndex'] as int? ?? 0,
    chromakeyEnabled:    j['chromakeyEnabled'] as bool? ?? false,
    chromakeyColor:      Color(j['chromakeyColor'] as int? ?? 0xFF00FF00),
    chromakeySimilarity: (j['chromakeySimilarity'] as num?)?.toDouble() ?? 0.10,
    chromakeyBlend:      (j['chromakeyBlend'] as num?)?.toDouble() ?? 0.0,
    isStabilized:        j['isStabilized'] as bool? ?? false,
    transitionInType:    j['transitionInType'] != null
        ? TransitionType.values.byName(j['transitionInType'] as String)
        : TransitionType.none,
    transitionInDuration: (j['transitionInDuration'] as num?)?.toDouble() ?? 0.5,
  );

  factory TimelineTrack.fromFile({
    required String filePath,
    required String title,
    required Duration duration,
    required TrackType trackType,
    required int colorIndex,
    Duration startOffset = Duration.zero,
    bool thumbnailsLoading = false,
  }) {
    return TimelineTrack(
      id: generateId(),
      filePath: filePath,
      title: title,
      trackType: trackType,
      duration: duration,
      startOffset: startOffset,
      color: kVeTrackColors[colorIndex % kVeTrackColors.length],
      thumbnailsLoading: thumbnailsLoading,
    );
  }
}
