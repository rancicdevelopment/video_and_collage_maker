import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'video_editor_model.dart';

// ── Preset key colours ────────────────────────────────────────────────────────

const _kKeyColors = [
  (name: 'Green',   color: Color(0xFF00FF00)),
  (name: 'Blue',    color: Color(0xFF0000FF)),
  (name: 'White',   color: Color(0xFFFFFFFF)),
  (name: 'Black',   color: Color(0xFF000000)),
  (name: 'Red',     color: Color(0xFFFF0000)),
  (name: 'Cyan',    color: Color(0xFF00FFFF)),
  (name: 'Magenta', color: Color(0xFFFF00FF)),
];

const _kChromaAccent = Color(0xFF00D26A);

// ── Public API ────────────────────────────────────────────────────────────────

void showVeChromakeyDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function(TimelineTrack) onConfirm,
  required void Function() onCancel,
  double? maxHeight,
}) {
  showModalBottomSheet<TimelineTrack>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: (_) => _VeChromakeySheet(
      track:        track,
      onLiveUpdate: onLiveUpdate,
    ),
  ).then((finalTrack) {
    if (finalTrack != null) {
      onConfirm(finalTrack);
    } else {
      onCancel();
    }
  });
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _VeChromakeySheet extends StatefulWidget {
  final TimelineTrack track;
  final void Function(TimelineTrack) onLiveUpdate;

  const _VeChromakeySheet({
    required this.track,
    required this.onLiveUpdate,
  });

  @override
  State<_VeChromakeySheet> createState() => _VeChromakeySheetState();
}

class _VeChromakeySheetState extends State<_VeChromakeySheet> {
  late bool   _enabled;
  late Color  _keyColor;
  late double _similarity;
  late double _blend;

  // Preview state
  Uint8List? _previewBytes;
  bool _isGeneratingPreview = false;
  String? _lastPreviewKey;

  @override
  void initState() {
    super.initState();
    _enabled    = widget.track.chromakeyEnabled;
    _keyColor   = widget.track.chromakeyColor;
    _similarity = widget.track.chromakeySimilarity;
    _blend      = widget.track.chromakeyBlend;
    _schedulePreview();
  }

  @override
  void dispose() {
    // Clean up temp preview files
    getTemporaryDirectory().then((dir) {
      for (final name in [
        'ck_raw_${widget.track.id}.png',
        'ck_prev_${widget.track.id}.png',
      ]) {
        try { File('${dir.path}/$name').deleteSync(); } catch (_) {}
      }
    });
    super.dispose();
  }

  void _livePreview() {
    widget.onLiveUpdate(widget.track.copyWith(
      chromakeyEnabled:    _enabled,
      chromakeyColor:      _keyColor,
      chromakeySimilarity: _similarity,
      chromakeyBlend:      _blend,
    ));
    _schedulePreview();
  }

  void _schedulePreview() {
    if (!_enabled) {
      // Show raw frame when disabled
      _generateRawPreview();
      return;
    }
    final rh = (_keyColor.r * 255).round().toRadixString(16).padLeft(2, '0');
    final gh = (_keyColor.g * 255).round().toRadixString(16).padLeft(2, '0');
    final bh = (_keyColor.b * 255).round().toRadixString(16).padLeft(2, '0');
    final key = '$rh$gh$bh-${_similarity.toStringAsFixed(3)}-${_blend.toStringAsFixed(3)}';
    if (key == _lastPreviewKey) return;
    _lastPreviewKey = key;
    _generateChromakeyPreview(
      colorHex: '0x$rh$gh$bh',
      similarity: _similarity,
      blend: _blend,
    );
  }

  Future<void> _generateRawPreview() async {
    if (!widget.track.isVideo) return;
    final cacheKey = 'raw';
    if (_lastPreviewKey == cacheKey) return;
    _lastPreviewKey = cacheKey;

    if (mounted) setState(() => _isGeneratingPreview = true);
    try {
      final tmpDir  = await getTemporaryDirectory();
      final outPath = '${tmpDir.path}/ck_raw_${widget.track.id}.png';
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss', '0.5',
        '-i', widget.track.filePath,
        '-vf', 'scale=480:-2',
        '-frames:v', '1',
        outPath,
      ]);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && mounted) {
        final bytes = await File(outPath).readAsBytes();
        setState(() => _previewBytes = bytes);
      }
    } catch (_) {}
    if (mounted) setState(() => _isGeneratingPreview = false);
  }

  Future<void> _generateChromakeyPreview({
    required String colorHex,
    required double similarity,
    required double blend,
  }) async {
    if (!widget.track.isVideo) return;
    if (mounted) setState(() => _isGeneratingPreview = true);
    try {
      final tmpDir  = await getTemporaryDirectory();
      final outPath = '${tmpDir.path}/ck_prev_${widget.track.id}.png';
      final sim = similarity.toStringAsFixed(3);
      final bld = blend.toStringAsFixed(3);

      // Extract one frame with chromakey applied and save as PNG.
      // Transparent areas (removed colour) are encoded in the PNG alpha channel
      // and rendered over the dark container background in Flutter.
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss', '0.5',
        '-i', widget.track.filePath,
        '-vf', 'scale=480:-2,format=yuv420p,chromakey=color=$colorHex:similarity=$sim:blend=$bld',
        '-frames:v', '1',
        outPath,
      ]);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && mounted) {
        final bytes = await File(outPath).readAsBytes();
        setState(() => _previewBytes = bytes);
      }
    } catch (e) {
      debugPrint('Chromakey preview error: $e');
    }
    if (mounted) setState(() => _isGeneratingPreview = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111E2F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 20 + MediaQuery.of(context).viewInsets.bottom),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),

          // Title + toggle row
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Green Screen',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    Text('Removes the selected colour from the video (Chroma Key)',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                activeColor: _kChromaAccent,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  _livePreview();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Live preview frame ─────────────────────────────────────────────
          if (widget.track.isVideo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 140,
                width: double.infinity,
                // Dark checkered-like background makes transparency obvious
                color: const Color(0xFF1A1A2E),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Dark gray behind the image so transparent areas show clearly
                    if (_previewBytes != null && !_isGeneratingPreview)
                      Image.memory(
                        _previewBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    if (_isGeneratingPreview)
                      const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kChromaAccent),
                      )
                    else if (_previewBytes == null)
                      const Icon(Icons.image_not_supported_outlined,
                          color: Colors.white24, size: 36),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Preview: removed pixels appear dark'
                  : 'Preview: original frame (effect disabled)',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],

          // Key colour presets
          const Text('Key colour',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kKeyColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _kKeyColors[i];
                final isSel = _keyColor.toARGB32() == c.color.toARGB32();
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _keyColor = c.color;
                      _enabled  = true;
                    });
                    _livePreview();
                  },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: c.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white24,
                        width: isSel ? 2.5 : 1.0,
                      ),
                    ),
                    child: isSel
                        ? Icon(Icons.check,
                            color: c.color.computeLuminance() > 0.4
                                ? Colors.black
                                : Colors.white,
                            size: 18)
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          _ckSlider(
            label: 'Similarity',
            value: _similarity,
            min: 0.01,
            max: 0.50,
            divisions: 49,
            display: (v) => '${(v * 100).round()}%',
            onChanged: (v) {
              setState(() => _similarity = v);
              _livePreview();
            },
          ),
          _ckSlider(
            label: 'Edge softness',
            value: _blend,
            min: 0.0,
            max: 0.20,
            divisions: 20,
            display: (v) => v == 0.0 ? 'Sharp' : '${(v * 100).round()}%',
            onChanged: (v) {
              setState(() => _blend = v);
              _livePreview();
            },
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _enabled    = false;
                      _similarity = 0.10;
                      _blend      = 0.0;
                    });
                    _livePreview();
                  },
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
                  onPressed: () => Navigator.pop(
                    context,
                    widget.track.copyWith(
                      chromakeyEnabled:    _enabled,
                      chromakeyColor:      _keyColor,
                      chromakeySimilarity: _similarity,
                      chromakeyBlend:      _blend,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kChromaAccent,
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
  }

  Widget _ckSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
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
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:   _kChromaAccent,
            inactiveTrackColor: Colors.white12,
            thumbColor:         _kChromaAccent,
            overlayColor:       _kChromaAccent.withValues(alpha: 0.15),
            trackHeight:        3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
