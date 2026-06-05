import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'video_editor_model.dart';

// ── Filter presets ─────────────────────────────────────────────────────────────
// (name, brightness, contrast, saturation, temperature)
const _kFilterPresets = [
  ('None',      0.0,   1.0,  1.0,   0.0 ),
  ('Warm',      0.05,  1.1,  1.15,  0.65),
  ('Cool',     -0.03,  1.05, 1.0,  -0.55),
  ('Vivid',     0.05,  1.25, 1.6,   0.0 ),
  ('Muted',     0.0,   0.85, 0.45,  0.0 ),
  ('Bright',    0.18,  1.1,  1.0,   0.0 ),
  ('Dark',     -0.15,  1.15, 1.0,   0.0 ),
  ('Grayscale', 0.0,   1.0,  0.0,   0.0 ),
  ('Dramatic',  0.0,   1.5,  0.6,   0.0 ),
];

// ── LUT export ─────────────────────────────────────────────────────────────────

/// Generates a 33-point 3D LUT in Adobe .cube format and shares it.
/// Only brightness / contrast / saturation / hue / temperature are encoded —
/// spatial effects (blur, vignette, grain) cannot be represented in a LUT.
Future<void> exportVeLut({
  required String trackTitle,
  required double brightness,
  required double contrast,
  required double saturation,
  required double hue,
  required double temperature,
}) async {
  const lutSize = 33;
  final matrix = buildTrackColorMatrix(
    brightness:  brightness,
    contrast:    contrast,
    saturation:  saturation,
    temperature: temperature,
    hue:         hue,
  );

  final buf = StringBuffer()
    ..writeln('TITLE "${trackTitle.replaceAll('"', "'")}"')
    ..writeln('# Exported from Video Editor')
    ..writeln('# Filters: brightness=$brightness  contrast=$contrast'
        '  saturation=$saturation  hue=${hue.round()}°')
    ..writeln('# Note: blur / vignette / grain are not included in LUTs.')
    ..writeln('LUT_3D_SIZE $lutSize')
    ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
    ..writeln('DOMAIN_MAX 1.0 1.0 1.0')
    ..writeln();

  for (var bi = 0; bi < lutSize; bi++) {
    for (var gi = 0; gi < lutSize; gi++) {
      for (var ri = 0; ri < lutSize; ri++) {
        final r = ri / (lutSize - 1) * 255.0;
        final g = gi / (lutSize - 1) * 255.0;
        final b = bi / (lutSize - 1) * 255.0;

        final rOut = (matrix[0]*r  + matrix[1]*g  + matrix[2]*b  + matrix[4])
            .clamp(0.0, 255.0) / 255.0;
        final gOut = (matrix[5]*r  + matrix[6]*g  + matrix[7]*b  + matrix[9])
            .clamp(0.0, 255.0) / 255.0;
        final bOut = (matrix[10]*r + matrix[11]*g + matrix[12]*b + matrix[14])
            .clamp(0.0, 255.0) / 255.0;

        buf.writeln('${rOut.toStringAsFixed(6)} '
            '${gOut.toStringAsFixed(6)} '
            '${bOut.toStringAsFixed(6)}');
      }
    }
  }

  final tmpDir = await getTemporaryDirectory();
  final safeName = trackTitle
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  final file = File(p.join(tmpDir.path, '${safeName}_filter.cube'));
  await file.writeAsString(buf.toString());

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/octet-stream')],
    subject: '$trackTitle — filter LUT',
  );
}

// ── Filters bottom sheet ───────────────────────────────────────────────────────

/// Shows the color-grading filters bottom sheet for a video or image track.
/// [onLiveUpdate] is called on every slider / preset change for live preview.
/// [onConfirm] is called when Apply is pressed (caller pushes undo snapshot).
/// [onCancel] is called when the sheet is dismissed without applying (caller
/// restores the track to its original values).
void showVeFiltersDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
}) {
  double brightness       = track.brightness;
  double contrast         = track.contrast;
  double saturation       = track.saturation;
  double hue              = track.hue;
  double vignetteStrength = track.vignetteStrength;
  double blurRadius       = track.blurRadius;
  double grainStrength    = track.grainStrength;
  double temperature      = track.temperature;
  int selectedPreset      = -1;
  bool applied            = false;

  void livePreview() {
    onLiveUpdate(track.copyWith(
      brightness:       brightness,
      contrast:         contrast,
      saturation:       saturation,
      hue:              hue,
      vignetteStrength: vignetteStrength,
      blurRadius:       blurRadius,
      grainStrength:    grainStrength,
      temperature:      temperature,
    ));
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void applyPreset(int i) {
          final preset = _kFilterPresets[i];
          brightness       = preset.$2;
          contrast         = preset.$3;
          saturation       = preset.$4;
          temperature      = preset.$5;
          hue              = 0.0;
          vignetteStrength = 0.0;
          blurRadius       = 0.0;
          grainStrength    = 0.0;
          selectedPreset   = i;
          livePreview();
        }

        Widget filterSlider({
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
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(display(value),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  activeTrackColor: const Color(0xFF00C8FF),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFF00C8FF),
                  overlayColor: const Color(0x2200C8FF),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  onChanged: (v) {
                    setS(() {
                      onChanged(v);
                      selectedPreset = -1;
                    });
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
              const Text('Filters',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              // Preset chips
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kFilterPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final isSelected = selectedPreset == i;
                    final accentColor = i == 1
                        ? const Color(0xFFFF8C42)  // Warm
                        : i == 2
                            ? const Color(0xFF5BB8FF)  // Cool
                            : const Color(0xFF00C8FF);
                    return GestureDetector(
                      onTap: () => setS(() => applyPreset(i)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor
                              : const Color(0xFF1E3050),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? accentColor : Colors.white24,
                          ),
                        ),
                        child: Text(
                          _kFilterPresets[i].$1,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),
              filterSlider(
                label: 'Brightness',
                value: brightness,
                min: -1.0,
                max: 1.0,
                display: (v) => '${v >= 0 ? '+' : ''}${(v * 100).round()}%',
                onChanged: (v) => brightness = v,
              ),
              filterSlider(
                label: 'Contrast',
                value: contrast,
                min: 0.0,
                max: 2.0,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => contrast = v,
              ),
              filterSlider(
                label: 'Saturation',
                value: saturation,
                min: 0.0,
                max: 2.0,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => saturation = v,
              ),
              filterSlider(
                label: 'Hue',
                value: hue,
                min: -180.0,
                max: 180.0,
                display: (v) => '${v >= 0 ? '+' : ''}${v.round()}°',
                onChanged: (v) => hue = v,
              ),
              filterSlider(
                label: 'Temperature',
                value: temperature,
                min: -1.0,
                max: 1.0,
                display: (v) => v == 0.0
                    ? 'Neutral'
                    : v > 0
                        ? '+${(v * 100).round()}% Warm'
                        : '${(v * 100).round()}% Cool',
                onChanged: (v) => temperature = v,
              ),
              filterSlider(
                label: 'Vignette',
                value: vignetteStrength,
                min: 0.0,
                max: 1.0,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => vignetteStrength = v,
              ),
              filterSlider(
                label: 'Blur',
                value: blurRadius,
                min: 0.0,
                max: 20.0,
                display: (v) => v == 0.0 ? 'Off' : v.toStringAsFixed(1),
                onChanged: (v) => blurRadius = v,
              ),
              filterSlider(
                label: 'Grain',
                value: grainStrength,
                min: 0.0,
                max: 1.0,
                display: (v) => v == 0.0 ? 'Off' : '${(v * 100).round()}%',
                onChanged: (v) => grainStrength = v,
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 15),
                  label: const Text('Export as .cube LUT'),
                  style: TextButton.styleFrom(
                    foregroundColor: brightness != 0.0 || contrast != 1.0 ||
                            saturation != 1.0 || hue != 0.0 ||
                            temperature != 0.0
                        ? const Color(0xFF00C8FF)
                        : Colors.white24,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: brightness != 0.0 || contrast != 1.0 ||
                          saturation != 1.0 || hue != 0.0 ||
                          temperature != 0.0
                      ? () => exportVeLut(
                            trackTitle:  track.title,
                            brightness:  brightness,
                            contrast:    contrast,
                            saturation:  saturation,
                            hue:         hue,
                            temperature: temperature,
                          )
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setS(() {
                        brightness       = 0.0;
                        contrast         = 1.0;
                        saturation       = 1.0;
                        hue              = 0.0;
                        vignetteStrength = 0.0;
                        blurRadius       = 0.0;
                        grainStrength    = 0.0;
                        temperature      = 0.0;
                        selectedPreset   = 0;
                        livePreview();
                      }),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Reset'),
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
                        backgroundColor: const Color(0xFF00C8FF),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  ).then((_) {
    if (!applied) onCancel();
  });
}
