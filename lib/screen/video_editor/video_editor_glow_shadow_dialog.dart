import 'package:flutter/material.dart';

import 'video_editor_model.dart';

// ── Shadow / glow preset colors ───────────────────────────────────────────────
const kVeShadowColors = [
  (name: 'Black',   color: Color(0xFF000000)),
  (name: 'White',   color: Color(0xFFFFFFFF)),
  (name: 'Gold',    color: Color(0xFFFFD700)),
  (name: 'Orange',  color: Color(0xFFFF6B00)),
  (name: 'Red',     color: Color(0xFFFF2D2D)),
  (name: 'Blue',    color: Color(0xFF2D7FFF)),
  (name: 'Cyan',    color: Color(0xFF00E5FF)),
  (name: 'Purple',  color: Color(0xFFBB2DFF)),
];

// ── Glow / drop-shadow bottom sheet ──────────────────────────────────────────

/// Shows the shadow / glow editor for a video or image track.
/// [onLiveUpdate] is called on every change for live preview.
/// [onConfirm] is called when Apply is pressed (caller pushes undo snapshot).
/// [onCancel] is called when dismissed without applying (caller restores track).
void showVeGlowShadowDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
  double? maxHeight,
}) {
  double radius  = track.shadowRadius;
  double opacity = track.shadowOpacity;
  Color  color   = track.shadowColor;
  double offsetX = track.shadowOffsetX;
  double offsetY = track.shadowOffsetY;
  bool   applied = false;

  void livePreview() {
    onLiveUpdate(track.copyWith(
      shadowRadius:  radius,
      shadowOpacity: opacity,
      shadowColor:   color,
      shadowOffsetX: offsetX,
      shadowOffsetY: offsetY,
    ));
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget glowSlider({
          required String label,
          required double value,
          required double min,
          required double max,
          required String Function(double) display,
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
                          color: Colors.white70, fontSize: 13)),
                  Text(display(value),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  activeTrackColor: const Color(0xFFFF8C42),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFFFF8C42),
                  overlayColor: const Color(0x22FF8C42),
                  trackHeight: 3,
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

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111E2F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Shadow / Glow',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Offset = 0 → Glow  |  Offset ≠ 0 → Drop shadow',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 14),
              const Text('Color',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kVeShadowColors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = kVeShadowColors[i];
                    final isSel = color.toARGB32() == c.color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        setS(() => color = c.color);
                        livePreview();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.white24,
                            width: isSel ? 2.5 : 1.0,
                          ),
                        ),
                        child: isSel
                            ? Icon(
                                Icons.check,
                                color: c.color.computeLuminance() > 0.4
                                    ? Colors.black
                                    : Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 12),
              glowSlider(
                label: 'Radius',
                value: radius,
                min: 0.0,
                max: 25.0,
                display: (v) => v == 0.0 ? 'Off' : v.toStringAsFixed(1),
                onChanged: (v) => radius = v,
              ),
              glowSlider(
                label: 'Opacity',
                value: opacity,
                min: 0.0,
                max: 1.0,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => opacity = v,
              ),
              glowSlider(
                label: 'Offset X',
                value: offsetX,
                min: -20.0,
                max: 20.0,
                display: (v) =>
                    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}px',
                onChanged: (v) => offsetX = v,
              ),
              glowSlider(
                label: 'Offset Y',
                value: offsetY,
                min: -20.0,
                max: 20.0,
                display: (v) =>
                    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}px',
                onChanged: (v) => offsetY = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setS(() {
                        radius  = 0.0;
                        opacity = 0.6;
                        color   = Colors.black;
                        offsetX = 0.0;
                        offsetY = 0.0;
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
                        backgroundColor: const Color(0xFFFF8C42),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
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
