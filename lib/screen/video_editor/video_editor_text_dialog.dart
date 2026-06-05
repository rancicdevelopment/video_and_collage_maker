import 'dart:math';

import 'package:flutter/material.dart';

import 'video_editor_glow_shadow_dialog.dart' show kVeShadowColors;
import 'video_editor_blend_layer.dart' show kVeTextBlendModes;
import 'video_editor_model.dart';

// ── Text style constants ───────────────────────────────────────────────────────
const _kTextColors = [
  (name: 'White',   color: Color(0xFFFFFFFF)),
  (name: 'Black',   color: Color(0xFF000000)),
  (name: 'Yellow',  color: Color(0xFFFFE433)),
  (name: 'Orange',  color: Color(0xFFFF8C00)),
  (name: 'Red',     color: Color(0xFFFF3333)),
  (name: 'Pink',    color: Color(0xFFFF69B4)),
  (name: 'Cyan',    color: Color(0xFF00E5FF)),
  (name: 'Green',   color: Color(0xFF44FF88)),
  (name: 'Purple',  color: Color(0xFFBB86FC)),
  (name: 'Blue',    color: Color(0xFF448AFF)),
  (name: 'Teal',    color: Color(0xFF1DE9B6)),
  (name: 'Gold',    color: Color(0xFFFFD700)),
];

const _kOutlineColors = [
  (name: 'Black',   color: Color(0xFF000000)),
  (name: 'White',   color: Color(0xFFFFFFFF)),
  (name: 'Red',     color: Color(0xFFFF3333)),
  (name: 'Blue',    color: Color(0xFF448AFF)),
  (name: 'Yellow',  color: Color(0xFFFFE433)),
  (name: 'Purple',  color: Color(0xFFBB86FC)),
  (name: 'Gold',    color: Color(0xFFFFD700)),
  (name: 'Green',   color: Color(0xFF44FF88)),
];

const _kBgColors = [
  (name: 'Black',   color: Color(0xFF000000)),
  (name: 'White',   color: Color(0xFFFFFFFF)),
  (name: 'Navy',    color: Color(0xFF0A1628)),
  (name: 'Red',     color: Color(0xFFCC1F1F)),
  (name: 'Yellow',  color: Color(0xFFFFE433)),
  (name: 'Purple',  color: Color(0xFF6B21A8)),
  (name: 'Green',   color: Color(0xFF166534)),
  (name: 'Orange',  color: Color(0xFFEA580C)),
];

const _kFonts = [
  (label: 'Default',   family: null as String?),
  (label: 'Serif',     family: 'serif'),
  (label: 'Mono',      family: 'monospace'),
  (label: 'Cursive',   family: 'cursive'),
  (label: 'Georgia',   family: 'Georgia'),
  (label: 'Courier',   family: 'Courier'),
  (label: 'Palatino',  family: 'Palatino'),
  (label: 'Trebuchet', family: 'Trebuchet MS'),
];

const _kTextStylePresets = [
  (
    label: 'Plain',
    bold: false,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Bold',
    bold: true,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Shadow',
    bold: false,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 8.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Outline',
    bold: true,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 3.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Box',
    bold: false,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.85,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Yellow',
    bold: true,
    italic: false,
    textColor: Color(0xFFFFE433),
    outlineWidth: 2.5,
    outlineColor: Color(0xFF000000),
    shadowRadius: 6.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Neon',
    bold: true,
    italic: false,
    textColor: Color(0xFF00E5FF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.0,
    bgColor: Color(0xFF000000),
  ),
  (
    label: 'Purple',
    bold: true,
    italic: false,
    textColor: Color(0xFFFFFFFF),
    outlineWidth: 0.0,
    outlineColor: Color(0xFF000000),
    shadowRadius: 0.0,
    bgOpacity: 0.9,
    bgColor: Color(0xFF6B21A8),
  ),
];

// ── Text edit dialog ───────────────────────────────────────────────────────────

/// Shows the full-featured text-editing bottom sheet.
///
/// [baseTrack] — the track to edit (for a new track this is the pre-created
/// placeholder already added to the timeline by the caller).
/// [onLiveUpdate] — called on every property change so the preview stays live.
/// [onConfirm] — called when the user presses ✓ (caller pushes undo snapshot).
/// [onCancel] — called when the sheet is dismissed without confirming (caller
/// restores the track list to its pre-dialog state).
void showVeTextEditDialog({
  required BuildContext context,
  required TimelineTrack baseTrack,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
  double? maxHeight,
}) {
  String textContent       = baseTrack.textContent;
  double fontSize          = baseTrack.fontSize;
  Color  textColor         = baseTrack.textColor;
  Color  textBgColor       = baseTrack.textBgColor;
  double textBgOpacity     = baseTrack.textBgOpacity;
  bool   textBold          = baseTrack.textBold;
  bool   textItalic        = baseTrack.textItalic;
  double overlayX          = baseTrack.overlayX;
  double overlayY          = baseTrack.overlayY;
  String? fontFamily       = baseTrack.fontFamily;
  Color  textOutlineColor  = baseTrack.textOutlineColor;
  double textOutlineWidth  = baseTrack.textOutlineWidth;
  int    textAlignIndex    = baseTrack.textAlignIndex;
  double letterSpacing     = baseTrack.letterSpacing;
  double lineHeight        = baseTrack.lineHeight;
  bool   textUnderline     = baseTrack.textUnderline;
  bool   textStrikethrough = baseTrack.textStrikethrough;
  int    textCaseIndex     = baseTrack.textCaseIndex;
  double textOpacity       = baseTrack.opacity;
  double textPaddingH      = baseTrack.textPaddingH;
  double textPaddingV      = baseTrack.textPaddingV;
  double textBgRadius      = baseTrack.textBgRadius;
  int    textBlendModeIndex = baseTrack.textBlendModeIndex;
  double textRotation      = baseTrack.textRotation;
  double textGlowRadius    = baseTrack.textGlowRadius;
  Color  textGlowColor     = baseTrack.textGlowColor;
  bool   textGradientEnabled  = baseTrack.textGradientEnabled;
  Color  textGradientColor1   = baseTrack.textGradientColor1;
  Color  textGradientColor2   = baseTrack.textGradientColor2;
  double textGradientAngle    = baseTrack.textGradientAngle;
  double textPathCurve        = baseTrack.textPathCurve;
  double shadowRadius  = baseTrack.shadowRadius;
  double shadowOpacity = baseTrack.shadowOpacity;
  Color  shadowColor   = baseTrack.shadowColor;
  double shadowOffsetX = baseTrack.shadowOffsetX;
  double shadowOffsetY = baseTrack.shadowOffsetY;

  final textController = TextEditingController(text: textContent);
  bool applied = false;
  int activeTab = 0;

  void livePreview() {
    onLiveUpdate(baseTrack.copyWith(
      textContent:         textController.text,
      fontSize:            fontSize,
      textColor:           textColor,
      textBgColor:         textBgColor,
      textBgOpacity:       textBgOpacity,
      textBold:            textBold,
      textItalic:          textItalic,
      overlayX:            overlayX,
      overlayY:            overlayY,
      fontFamily:          fontFamily,
      textOutlineColor:    textOutlineColor,
      textOutlineWidth:    textOutlineWidth,
      textAlignIndex:      textAlignIndex,
      letterSpacing:       letterSpacing,
      lineHeight:          lineHeight,
      textUnderline:       textUnderline,
      textStrikethrough:   textStrikethrough,
      textCaseIndex:       textCaseIndex,
      opacity:             textOpacity,
      textPaddingH:        textPaddingH,
      textPaddingV:        textPaddingV,
      textBgRadius:        textBgRadius,
      textBlendModeIndex:  textBlendModeIndex,
      textRotation:        textRotation,
      textGlowRadius:      textGlowRadius,
      textGlowColor:       textGlowColor,
      textGradientEnabled: textGradientEnabled,
      textGradientColor1:  textGradientColor1,
      textGradientColor2:  textGradientColor2,
      textGradientAngle:   textGradientAngle,
      textPathCurve:       textPathCurve,
      shadowRadius:        shadowRadius,
      shadowOpacity:       shadowOpacity,
      shadowColor:         shadowColor,
      shadowOffsetX:       shadowOffsetX,
      shadowOffsetY:       shadowOffsetY,
      title: textController.text.isEmpty
          ? 'Text'
          : textController.text.split('\n').first,
    ));
  }

  const accent  = Color(0xFF7C5CBF);
  const surface = Color(0xFF16213E);
  const tabLabels = [
    'Style', 'Font', 'Color', 'Outline', 'Shadow', 'Background', 'Blend'
  ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: maxHeight != null
        ? BoxConstraints(maxHeight: maxHeight)
        : null,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        // ── slider helper ──────────────────────────────────────────────
        Widget buildSlider({
          required String label,
          required double value,
          required double min,
          required double max,
          required String displayVal,
          required void Function(double) onChanged,
        }) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12)),
                  Text(displayVal,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: accent,
                  overlayColor: accent.withValues(alpha: 0.2),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  onChanged: (v) {
                    setS(() => onChanged(v));
                    livePreview();
                  },
                ),
              ),
            ],
          );
        }

        // ── color swatch row ───────────────────────────────────────────
        Widget buildColorRow(
          List<({String name, Color color})> palette,
          Color selected,
          void Function(Color) onSelect,
        ) {
          return SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final c = palette[i];
                final isSel = selected.toARGB32() == c.color.toARGB32();
                return GestureDetector(
                  onTap: () {
                    setS(() => onSelect(c.color));
                    livePreview();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSel ? accent : Colors.white24,
                        width: isSel ? 2.5 : 1.0,
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.5),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                    child: isSel
                        ? Icon(Icons.check,
                            color: c.color.computeLuminance() > 0.4
                                ? Colors.black
                                : Colors.white,
                            size: 14)
                        : null,
                  ),
                );
              },
            ),
          );
        }

        // ── tab content ────────────────────────────────────────────────
        Widget tabContent;
        switch (activeTab) {
          // ── 0: Style ─────────────────────────────────────────────────
          case 0:
            tabContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _styleToggle(
                    label: 'B',
                    active: textBold,
                    bold: true,
                    onTap: () {
                      setS(() => textBold = !textBold);
                      livePreview();
                    },
                  ),
                  const SizedBox(width: 6),
                  _styleToggle(
                    label: 'I',
                    active: textItalic,
                    italic: true,
                    onTap: () {
                      setS(() => textItalic = !textItalic);
                      livePreview();
                    },
                  ),
                  const SizedBox(width: 6),
                  _styleToggle(
                    label: 'U',
                    active: textUnderline,
                    underline: true,
                    onTap: () {
                      setS(() => textUnderline = !textUnderline);
                      livePreview();
                    },
                  ),
                  const SizedBox(width: 6),
                  _styleToggle(
                    label: 'S',
                    active: textStrikethrough,
                    strikethrough: true,
                    onTap: () {
                      setS(() => textStrikethrough = !textStrikethrough);
                      livePreview();
                    },
                  ),
                  const SizedBox(width: 10),
                  ...List.generate(3, (i) {
                    const icons = [
                      Icons.format_align_left,
                      Icons.format_align_center,
                      Icons.format_align_right,
                    ];
                    final isActive = textAlignIndex == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setS(() => textAlignIndex = i);
                          livePreview();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive ? accent : const Color(0xFF1E1D30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isActive ? accent : Colors.white24),
                          ),
                          child: Icon(icons[i],
                              size: 18,
                              color: isActive
                                  ? Colors.white
                                  : Colors.white54),
                        ),
                      ),
                    );
                  }),
                ]),
                const SizedBox(height: 8),
                const SizedBox(height: 10),
                Row(children: [
                  ...[('AA', 1), ('aa', 2), ('Aa', 3)].map((e) {
                    final isActive = textCaseIndex == e.$2;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setS(() =>
                              textCaseIndex = isActive ? 0 : e.$2);
                          livePreview();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isActive ? accent : const Color(0xFF1E1D30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive ? accent : Colors.white24,
                            ),
                          ),
                          child: Text(
                            e.$1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ]),
                const SizedBox(height: 12),
                buildSlider(
                  label: 'Opacity',
                  value: textOpacity,
                  min: 0.0,
                  max: 1.0,
                  displayVal: '${(textOpacity * 100).round()}%',
                  onChanged: (v) => textOpacity = v,
                ),
                buildSlider(
                  label: 'Letter Spacing',
                  value: letterSpacing,
                  min: -5.0,
                  max: 20.0,
                  displayVal: letterSpacing == 0.0
                      ? 'Default'
                      : '${letterSpacing > 0 ? '+' : ''}${letterSpacing.toStringAsFixed(1)}',
                  onChanged: (v) => letterSpacing = v,
                ),
                buildSlider(
                  label: 'Line Height',
                  value: lineHeight,
                  min: 0.8,
                  max: 3.0,
                  displayVal: lineHeight.toStringAsFixed(2),
                  onChanged: (v) => lineHeight = v,
                ),
                buildSlider(
                  label: 'Text Curve',
                  value: textPathCurve,
                  min: -1.0,
                  max: 1.0,
                  displayVal: textPathCurve == 0.0
                      ? 'Straight'
                      : textPathCurve > 0
                          ? '+${(textPathCurve * 100).round()}%'
                          : '${(textPathCurve * 100).round()}%',
                  onChanged: (v) => textPathCurve = v,
                ),
                const SizedBox(height: 4),
                const Text('Presets',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _kTextStylePresets.map((p) {
                    return GestureDetector(
                      onTap: () {
                        setS(() {
                          textBold         = p.bold;
                          textItalic       = p.italic;
                          textColor        = p.textColor;
                          textOutlineWidth = p.outlineWidth;
                          textOutlineColor = p.outlineColor;
                          shadowRadius     = p.shadowRadius;
                          shadowOpacity    = p.shadowRadius > 0 ? 0.7 : 0.6;
                          shadowOffsetX    = p.shadowRadius > 0 ? 3.0 : 0.0;
                          shadowOffsetY    = p.shadowRadius > 0 ? 3.0 : 4.0;
                          shadowColor      = Colors.black;
                          textBgOpacity    = p.bgOpacity;
                          if (p.bgOpacity > 0) textBgColor = p.bgColor;
                        });
                        livePreview();
                      },
                      child: _buildStylePresetCell(p, fontSize),
                    );
                  }).toList(),
                ),
              ],
            );
            break;

          // ── 1: Font ───────────────────────────────────────────────────
          case 1:
            tabContent = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _kFonts.map((f) {
                final isSel = fontFamily == f.family;
                return GestureDetector(
                  onTap: () {
                    setS(() => fontFamily = f.family);
                    livePreview();
                  },
                  child: Container(
                    width: 80,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSel
                          ? accent.withValues(alpha: 0.25)
                          : surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? accent : Colors.white12,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Aa',
                          style: TextStyle(
                            fontFamily: f.family,
                            fontSize: 22,
                            color: isSel ? accent : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.label,
                          style: TextStyle(
                            fontSize: 9,
                            color: isSel ? accent : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
            break;

          // ── 2: Color ──────────────────────────────────────────────────
          case 2:
            tabContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Text Color',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 10),
                buildColorRow(
                    _kTextColors, textColor, (c) => textColor = c),
                const Divider(color: Colors.white12, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gradient',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    GestureDetector(
                      onTap: () {
                        setS(
                            () => textGradientEnabled =
                                !textGradientEnabled);
                        livePreview();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          color: textGradientEnabled
                              ? accent
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: textGradientEnabled
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ],
                ),
                if (textGradientEnabled) ...[
                  const SizedBox(height: 14),
                  const Text('Start Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(_kTextColors, textGradientColor1,
                      (c) => textGradientColor1 = c),
                  const SizedBox(height: 12),
                  const Text('End Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(_kTextColors, textGradientColor2,
                      (c) => textGradientColor2 = c),
                  const SizedBox(height: 4),
                  buildSlider(
                    label: 'Angle',
                    value: textGradientAngle,
                    min: 0,
                    max: 360,
                    displayVal: '${textGradientAngle.round()}°',
                    onChanged: (v) => textGradientAngle = v,
                  ),
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    final rad = textGradientAngle * pi / 180.0;
                    return Container(
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          begin: Alignment(-cos(rad), -sin(rad)),
                          end: Alignment(cos(rad), sin(rad)),
                          colors: [textGradientColor1, textGradientColor2],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
            break;

          // ── 3: Outline ────────────────────────────────────────────────
          case 3:
            tabContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSlider(
                  label: 'Outline Width',
                  value: textOutlineWidth,
                  min: 0,
                  max: 8,
                  displayVal: textOutlineWidth == 0
                      ? 'None'
                      : '${textOutlineWidth.toStringAsFixed(1)}px',
                  onChanged: (v) => textOutlineWidth = v,
                ),
                if (textOutlineWidth > 0) ...[
                  const SizedBox(height: 12),
                  const Text('Outline Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(_kOutlineColors, textOutlineColor,
                      (c) => textOutlineColor = c),
                ],
              ],
            );
            break;

          // ── 4: Shadow ─────────────────────────────────────────────────
          case 4:
            tabContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSlider(
                  label: 'Blur',
                  value: shadowRadius,
                  min: 0,
                  max: 20,
                  displayVal: shadowRadius == 0
                      ? 'None'
                      : shadowRadius.toStringAsFixed(1),
                  onChanged: (v) => shadowRadius = v,
                ),
                if (shadowRadius > 0) ...[
                  buildSlider(
                    label: 'Opacity',
                    value: shadowOpacity,
                    min: 0,
                    max: 1,
                    displayVal: '${(shadowOpacity * 100).round()}%',
                    onChanged: (v) => shadowOpacity = v,
                  ),
                  buildSlider(
                    label: 'Offset X',
                    value: shadowOffsetX,
                    min: -20,
                    max: 20,
                    displayVal: shadowOffsetX.toStringAsFixed(1),
                    onChanged: (v) => shadowOffsetX = v,
                  ),
                  buildSlider(
                    label: 'Offset Y',
                    value: shadowOffsetY,
                    min: -20,
                    max: 20,
                    displayVal: shadowOffsetY.toStringAsFixed(1),
                    onChanged: (v) => shadowOffsetY = v,
                  ),
                  const SizedBox(height: 4),
                  const Text('Shadow Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(
                      kVeShadowColors, shadowColor, (c) => shadowColor = c),
                  const SizedBox(height: 4),
                ],
                const Divider(color: Colors.white12, height: 20),
                buildSlider(
                  label: 'Glow Radius',
                  value: textGlowRadius,
                  min: 0,
                  max: 30,
                  displayVal: textGlowRadius == 0
                      ? 'None'
                      : textGlowRadius.toStringAsFixed(1),
                  onChanged: (v) => textGlowRadius = v,
                ),
                if (textGlowRadius > 0) ...[
                  const SizedBox(height: 4),
                  const Text('Glow Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(
                      _kTextColors, textGlowColor, (c) => textGlowColor = c),
                ],
              ],
            );
            break;

          // ── 6: Blend ──────────────────────────────────────────────────
          case 6:
            tabContent = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(kVeTextBlendModes.length, (i) {
                final bm = kVeTextBlendModes[i];
                final isSel = textBlendModeIndex == i;
                return GestureDetector(
                  onTap: () {
                    setS(() => textBlendModeIndex = i);
                    livePreview();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 76,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSel
                          ? accent.withValues(alpha: 0.25)
                          : const Color(0xFF1E1D30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? accent : Colors.white12,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      bm.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSel ? FontWeight.w600 : FontWeight.normal,
                        color: isSel ? accent : Colors.white60,
                      ),
                    ),
                  ),
                );
              }),
            );
            break;

          // ── 5: Background ─────────────────────────────────────────────
          default:
            tabContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSlider(
                  label: 'Opacity',
                  value: textBgOpacity,
                  min: 0,
                  max: 1,
                  displayVal: textBgOpacity == 0
                      ? 'None'
                      : '${(textBgOpacity * 100).round()}%',
                  onChanged: (v) => textBgOpacity = v,
                ),
                if (textBgOpacity > 0) ...[
                  const SizedBox(height: 12),
                  const Text('Background Color',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 10),
                  buildColorRow(
                      _kBgColors, textBgColor, (c) => textBgColor = c),
                  const SizedBox(height: 4),
                ],
                buildSlider(
                  label: 'Border Radius',
                  value: textBgRadius,
                  min: 0,
                  max: 60,
                  displayVal: '${textBgRadius.round()}px',
                  onChanged: (v) => textBgRadius = v,
                ),
                buildSlider(
                  label: 'Padding Horizontal',
                  value: textPaddingH,
                  min: 0,
                  max: 60,
                  displayVal:
                      textPaddingH == 0 ? 'None' : '${textPaddingH.round()}px',
                  onChanged: (v) => textPaddingH = v,
                ),
                buildSlider(
                  label: 'Padding Vertical',
                  value: textPaddingV,
                  min: 0,
                  max: 60,
                  displayVal:
                      textPaddingV == 0 ? 'None' : '${textPaddingV.round()}px',
                  onChanged: (v) => textPaddingV = v,
                ),
              ],
            );
            break;
        }

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF12111F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── text field + confirm / cancel ──────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            maxLines: 2,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Enter your text…',
                              hintStyle:
                                  const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF1E1D30),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) {
                              setS(() {});
                              livePreview();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            applied = true;
                            livePreview();
                            onConfirm();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 22),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1D30),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white54, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── tab bar ────────────────────────────────────────────
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: tabLabels.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final isSel = activeTab == i;
                        return GestureDetector(
                          onTap: () => setS(() => activeTab = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel ? accent : const Color(0xFF1E1D30),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? accent : Colors.white12,
                              ),
                            ),
                            child: Text(
                              tabLabels[i],
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white54,
                                fontSize: 13,
                                fontWeight: isSel
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── tab content ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    child: tabContent,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ).then((_) {
    Future.delayed(const Duration(milliseconds: 350), textController.dispose);
    if (!applied) onCancel();
  });
}

// ── Style preset cell widget ───────────────────────────────────────────────────

Widget _buildStylePresetCell(dynamic p, double fontSize) {
  final textContent = p.label as String;
  final bold        = p.bold as bool;
  final italic      = p.italic as bool;
  final tc          = p.textColor as Color;
  final ow          = p.outlineWidth as double;
  final oc          = p.outlineColor as Color;
  final sr          = p.shadowRadius as double;
  final bgOp        = p.bgOpacity as double;
  final bgC         = p.bgColor as Color;

  final displayStyle = TextStyle(
    fontSize: 14,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: ow > 0 ? null : tc,
    shadows: sr > 0
        ? [
            Shadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: sr,
                offset: const Offset(2, 2))
          ]
        : null,
  );

  Widget textW = ow > 0
      ? Stack(
          alignment: Alignment.center,
          children: [
            Text(textContent,
                style: displayStyle.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = ow * 2
                    ..strokeJoin = StrokeJoin.round
                    ..color = oc,
                  color: null,
                  shadows: null,
                )),
            Text(textContent, style: displayStyle),
          ],
        )
      : Text(textContent, style: displayStyle);

  return Container(
    width: 78,
    height: 52,
    decoration: BoxDecoration(
      color: bgOp > 0
          ? bgC.withValues(alpha: bgOp)
          : const Color(0xFF1E1D30),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white12),
    ),
    alignment: Alignment.center,
    child: textW,
  );
}

// ── Style toggle button ────────────────────────────────────────────────────────

Widget _styleToggle({
  required String label,
  required bool active,
  bool bold = false,
  bool italic = false,
  bool underline = false,
  bool strikethrough = false,
  required VoidCallback onTap,
}) {
  const accent = Color(0xFF7C5CBF);
  TextDecoration? deco;
  if (underline) deco = TextDecoration.underline;
  if (strikethrough) deco = TextDecoration.lineThrough;

  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? accent : const Color(0xFF1E1D30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? accent : Colors.white24,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 15,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: deco,
            decorationColor: active ? Colors.white : Colors.white70,
            decorationThickness: 2.0,
          ),
        ),
      ),
    ),
  );
}
