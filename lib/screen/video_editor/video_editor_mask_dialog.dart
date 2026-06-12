import 'package:flutter/material.dart';

import 'video_editor_model.dart';
import 'video_editor_painters.dart';

// ── Mask shape metadata ───────────────────────────────────────────────────────

const _kMaskShapes = [
  (index: 0, name: 'Bez maske'),
  (index: 1, name: 'Krug'),
  (index: 2, name: 'Pravougaonik'),
  (index: 3, name: 'Srce'),
  (index: 4, name: 'Zvezda'),
  (index: 5, name: 'Trougao'),
  (index: 6, name: 'Dijamant'),
];

const _kMaskAccent = Color(0xFFAA44FF);

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows the Maska (mask) editor bottom sheet.
/// [onLiveUpdate] is called on every change for live preview.
/// [onConfirm]   is called when the user taps Apply (caller pushes undo snapshot).
/// [onCancel]    is called when dismissed without applying (caller restores track).
void showVeMaskDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
  double? maxHeight,
}) {
  int    shapeIndex = track.maskShapeIndex;
  double scale      = track.maskScale;
  double feather    = track.maskFeather;
  bool   inverted   = track.maskInverted;
  bool   applied    = false;

  void livePreview() {
    onLiveUpdate(track.copyWith(
      maskShapeIndex: shapeIndex,
      maskScale:      scale,
      maskFeather:    feather,
      maskInverted:   inverted,
    ));
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        // ── Slider helper ────────────────────────────────────────────────────
        Widget maskSlider({
          required String label,
          required double value,
          required double min,
          required double max,
          required int divisions,
          required String Function(double) display,
          required void Function(double) onChanged,
          bool enabled = true,
        }) {
          return Opacity(
            opacity: enabled ? 1.0 : 0.35,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(display(value),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor:   _kMaskAccent,
                    inactiveTrackColor: Colors.white12,
                    thumbColor:         _kMaskAccent,
                    overlayColor:       _kMaskAccent.withValues(alpha: 0.15),
                    trackHeight:        3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    disabledActiveTrackColor:   Colors.white24,
                    disabledInactiveTrackColor: Colors.white12,
                    disabledThumbColor:         Colors.white24,
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: enabled
                        ? (v) {
                            setS(() => onChanged(v));
                            livePreview();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          );
        }

        // ── Shape selector ───────────────────────────────────────────────────
        Widget shapeSelector() {
          return SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _kMaskShapes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final shape = _kMaskShapes[i];
                final isSel = shapeIndex == shape.index;

                return GestureDetector(
                  onTap: () {
                    setS(() => shapeIndex = shape.index);
                    livePreview();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: isSel
                              ? _kMaskAccent.withValues(alpha: 0.18)
                              : const Color(0xFF1E3050),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? _kMaskAccent : Colors.white12,
                            width: isSel ? 2.0 : 1.0,
                          ),
                        ),
                        child: shape.index == 0
                            // "None" — show a slash icon
                            ? Icon(Icons.not_interested_outlined,
                                color: isSel ? _kMaskAccent : Colors.white38,
                                size: 22)
                            : CustomPaint(
                                painter: VeMaskShapePreviewPainter(
                                  shapeIndex: shape.index,
                                  selected: isSel,
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shape.name,
                        style: TextStyle(
                          color: isSel ? _kMaskAccent : Colors.white38,
                          fontSize: 9,
                          fontWeight: isSel
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }

        // ── Main sheet ───────────────────────────────────────────────────────
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111E2F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.fromLTRB(
            16, 12, 16,
            12 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title
              const Text('Mask',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Sakrij dijelove klipa kroz oblik maske',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 14),

              // Shape selector
              shapeSelector(),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 12),

              // Sliders (disabled when no shape selected)
              maskSlider(
                label: 'Size',
                value: scale,
                min: 0.1,
                max: 1.5,
                divisions: 28,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => scale = v,
                enabled: shapeIndex > 0,
              ),
              maskSlider(
                label: 'Edge softness',
                value: feather,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                display: (v) => v == 0.0 ? 'Sharp' : '${(v * 100).round()}%',
                onChanged: (v) => feather = v,
                enabled: shapeIndex > 0,
              ),
              const SizedBox(height: 8),

              // Invert toggle
              Opacity(
                opacity: shapeIndex > 0 ? 1.0 : 0.35,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Invert mask',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        Text(
                          inverted
                              ? 'Visible outside shape'
                              : 'Visible inside shape',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                    Switch(
                      value: inverted,
                      activeColor: _kMaskAccent,
                      onChanged: shapeIndex > 0
                          ? (v) {
                              setS(() => inverted = v);
                              livePreview();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setS(() {
                        shapeIndex = 0;
                        scale      = 1.0;
                        feather    = 0.0;
                        inverted   = false;
                        livePreview();
                      }),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Remove'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        livePreview();
                        applied = true;
                        onConfirm();
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kMaskAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
          ),
        );
      },
    ),
  ).then((_) {
    if (!applied) onCancel();
  });
}
