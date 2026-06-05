import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_editor_model.dart';

// ── Theme constants (matches video editor dark theme) ─────────────────────────
const _kSurfaceColor = Color(0xFF111E2F);
const _kOnSurface    = Colors.white;
const _kDivider      = Color(0x1FFFFFFF); // white 12 %
const _kEqColor      = Color(0xFFFF9800); // orange accent

// ── EQ constants ──────────────────────────────────────────────────────────────
const List<int>    _kFreqs  = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const List<String> _kLabels = ['32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];
const double _kMinGain = -12.0;
const double _kMaxGain =  12.0;

const _kPresetNames = ['Flat', 'Bass', 'Treble', 'Vocal', 'Rock', 'Pop', 'Jazz', 'Classical'];
const _kPresetGains = <List<double>>[
  [ 0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0], // Flat
  [ 8.0,  6.0,  5.0,  3.0,  0.0,  0.0,  0.0,  0.0, -1.0, -2.0], // Bass
  [-2.0, -1.0,  0.0,  0.0,  0.0,  2.0,  4.0,  6.0,  7.0,  8.0], // Treble
  [-3.0, -2.0,  0.0,  3.0,  5.0,  6.0,  5.0,  3.0,  1.0, -1.0], // Vocal
  [ 6.0,  4.0,  2.0,  0.0, -2.0, -1.0,  2.0,  4.0,  6.0,  6.0], // Rock
  [-1.0,  1.0,  3.0,  5.0,  5.0,  4.0,  2.0,  0.0, -1.0, -2.0], // Pop
  [ 4.0,  3.0,  1.0,  2.0,  3.0,  0.0, -1.0,  0.0,  2.0,  3.0], // Jazz
  [ 0.0,  0.0,  0.0,  2.0,  0.0, -2.0, -3.0, -4.0, -4.0, -5.0], // Classical
];

/// Shows the EQ bottom sheet for [track].
/// [onApplied]  — called with the FFmpeg-processed temp file path and the
///               10-band gains that were applied (so they can be persisted).
/// [onRestored] — called when the user removes EQ (restores pre-EQ original).
Future<void> showVeEqSheet({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(String tempPath, List<double> gains) onApplied,
  VoidCallback? onRestored,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _VeEqSheet(
      track: track,
      onApplied: onApplied,
      onRestored: onRestored,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _VeEqSheet extends StatefulWidget {
  final TimelineTrack track;
  final void Function(String tempPath, List<double> gains) onApplied;
  final VoidCallback? onRestored;

  const _VeEqSheet({
    required this.track,
    required this.onApplied,
    this.onRestored,
  });

  @override
  State<_VeEqSheet> createState() => _VeEqSheetState();
}

class _VeEqSheetState extends State<_VeEqSheet> {
  // ── EQ state ───────────────────────────────────────────────────────────────
  late List<double> _gains;
  int? _activePreset;
  int  _cacheVer      = 0;

  // ── Preview playback ───────────────────────────────────────────────────────
  final AudioPlayer _player  = AudioPlayer();
  bool  _isPlaying            = false;
  bool  _playingProcessed     = false;
  String? _previewPath;
  String  _previewCacheKey    = '';
  bool  _isProcessingPreview  = false;

  // ── Applying ───────────────────────────────────────────────────────────────
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    // Restore previously saved gains, or detect matching preset, or default flat.
    final saved = widget.track.eqGains;
    if (saved != null && saved.length == 10) {
      _gains = List.of(saved);
      // Check if saved gains match any preset
      _activePreset = _detectPreset(_gains);
    } else {
      _gains = List.of(_kPresetGains[0]);
      _activePreset = 0; // Flat
    }
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() { _isPlaying = false; _playingProcessed = false; });
    });
  }

  /// Returns preset index if [gains] exactly match a preset, otherwise null.
  int? _detectPreset(List<double> gains) {
    for (int p = 0; p < _kPresetGains.length; p++) {
      bool match = true;
      for (int i = 0; i < 10; i++) {
        if ((gains[i] - _kPresetGains[p][i]).abs() > 0.01) {
          match = false;
          break;
        }
      }
      if (match) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _player.dispose();
    _cleanupPreview();
    super.dispose();
  }

  void _cleanupPreview() {
    if (_previewPath != null) {
      try { File(_previewPath!).deleteSync(); } catch (_) {}
      _previewPath = null;
    }
  }

  String _cacheKey() => _gains.map((g) => g.toStringAsFixed(1)).join(',');

  /// Builds an FFmpeg `equalizer=…` filter chain for non-zero bands.
  /// Returns null when all bands are flat (no processing needed).
  String? _buildEqFilter() {
    final parts = <String>[];
    for (int i = 0; i < 10; i++) {
      if (_gains[i].abs() < 0.05) continue;
      parts.add(
          'equalizer=f=${_kFreqs[i]}:width_type=o:width=1:g=${_gains[i].toStringAsFixed(2)}');
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  void _applyPreset(int index) {
    setState(() {
      _gains        = List.of(_kPresetGains[index]);
      _activePreset = index;
      _cacheVer++;
    });
    _cleanupPreview();
    _previewCacheKey = '';
  }

  void _updateBand(int i, double newGain) {
    final snapped = ((newGain.clamp(_kMinGain, _kMaxGain)) * 2).round() / 2.0;
    if (snapped == _gains[i]) return;
    setState(() { _gains[i] = snapped; _activePreset = null; _cacheVer++; });
    _cleanupPreview();
    _previewCacheKey = '';
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: TextStyle(color: error ? Colors.white : Colors.black)),
      backgroundColor: error ? Colors.redAccent : _kEqColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Preview (first 30 s with EQ applied) ─────────────────────────────────

  Future<void> _togglePreview(Duration startPosition) async {
    if (_isProcessingPreview || _isApplying) return;

    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() { _isPlaying = false; _playingProcessed = false; });
      return;
    }

    final key = _cacheKey();
    if (_previewPath != null &&
        File(_previewPath!).existsSync() &&
        _previewCacheKey == key) {
      await _player.play(DeviceFileSource(_previewPath!));
      if (startPosition > Duration.zero) await _player.seek(startPosition);
      if (mounted) setState(() { _isPlaying = true; _playingProcessed = true; });
      return;
    }

    _cleanupPreview();
    setState(() => _isProcessingPreview = true);

    try {
      final tmpDir  = await getTemporaryDirectory();
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(tmpDir.path, 'eq_prev_$ts.mp3');

      final trimStartSecs = widget.track.trimStart.inMilliseconds / 1000.0;
      final trimEndSecs   =
          (widget.track.duration - widget.track.trimEnd).inMilliseconds / 1000.0;
      final eqFilter = _buildEqFilter();

      final filterParts = <String>[
        'atrim=start=$trimStartSecs:end=$trimEndSecs',
        'asetpts=PTS-STARTPTS',
        if (eqFilter != null) eqFilter,
      ];
      final filter = '[0:a]${filterParts.join(',')}[out]';

      final args = <String>[
        '-y', '-i', widget.track.filePath,
        '-t', '30',
        '-filter_complex', filter,
        '-map', '[out]',
        '-c:a', 'libmp3lame', '-q:a', '2',
        outPath,
      ];

      final session = await FFmpegKit.executeWithArguments(args);
      final rc      = await session.getReturnCode();

      if (!mounted) {
        try { File(outPath).deleteSync(); } catch (_) {}
        return;
      }

      if (ReturnCode.isSuccess(rc) && File(outPath).existsSync()) {
        _previewPath     = outPath;
        _previewCacheKey = key;
        await _player.play(DeviceFileSource(outPath));
        if (startPosition > Duration.zero) await _player.seek(startPosition);
        if (mounted) setState(() { _isPlaying = true; _playingProcessed = true; });
      } else {
        final logs = await session.getAllLogsAsString();
        _showSnack('Preview failed.', error: true);
        debugPrint('FFmpeg EQ preview error: $logs');
      }
    } catch (e) {
      if (mounted) _showSnack('Preview error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isProcessingPreview = false);
    }
  }

  // ── Apply full-length EQ (or restore original) ────────────────────────────

  bool get _isFlat    => _buildEqFilter() == null;
  bool get _canRestore =>
      _isFlat && widget.track.eqApplied && widget.onRestored != null;

  Future<void> _applyToTrack() async {
    if (_isApplying || _isProcessingPreview) return;

    if (_canRestore) {
      widget.onRestored!();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    await _player.stop();
    setState(() { _isApplying = true; _isPlaying = false; _playingProcessed = false; });

    try {
      final tmpDir  = await getTemporaryDirectory();
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(tmpDir.path, 'eq_track_$ts.mp3');

      final trimStartSecs = widget.track.trimStart.inMilliseconds / 1000.0;
      final trimEndSecs   =
          (widget.track.duration - widget.track.trimEnd).inMilliseconds / 1000.0;
      final eqFilter = _buildEqFilter();

      final filterParts = <String>[
        'atrim=start=$trimStartSecs:end=$trimEndSecs',
        'asetpts=PTS-STARTPTS',
        if (eqFilter != null) eqFilter,
      ];
      final filter = '[0:a]${filterParts.join(',')}[out]';

      final args = [
        '-i', widget.track.filePath,
        '-filter_complex', filter,
        '-map', '[out]',
        '-c:a', 'libmp3lame', '-q:a', '2',
        outPath,
      ];

      final session = await FFmpegKit.executeWithArguments(args);
      final rc      = await session.getReturnCode();
      if (!mounted) return;

      if (ReturnCode.isSuccess(rc)) {
        widget.onApplied(outPath, List.of(_gains));
        if (mounted) Navigator.of(context).pop();
      } else {
        final logs = await session.getAllLogsAsString();
        _showSnack('EQ failed.', error: true);
        debugPrint('FFmpeg EQ error: $logs');
      }
    } catch (e) {
      if (mounted) _showSnack('EQ error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.97,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _kSurfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: _kOnSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Equalizer',
                      style: TextStyle(
                          color: _kOnSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                  Text(widget.track.title,
                      style: TextStyle(
                          color: _kOnSurface.withValues(alpha: 0.5),
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    color: _kOnSurface.withValues(alpha: 0.7)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(height: 1, color: _kDivider),
          // Scrollable body
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _buildCurvePanel(),
                const SizedBox(height: 12),
                _buildPresetChips(),
                const SizedBox(height: 10),
                _buildBandSliders(),
                const SizedBox(height: 14),
                _buildPreviewButton(),
                const SizedBox(height: 10),
                _buildApplyButton(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── EQ curve panel ────────────────────────────────────────────────────────

  Widget _buildCurvePanel() {
    final presetLabel =
        _activePreset != null ? _kPresetNames[_activePreset!] : 'Custom';
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: _kEqColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kEqColor.withValues(alpha: 0.30)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _EqCurvePainter(
              gains: _gains,
              color: _kEqColor,
              bars: widget.track.waveformBars,
            ),
          ),
        ),
        // Preset badge top-right
        Positioned(
          right: 8, top: 6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _kEqColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: _kEqColor.withValues(alpha: 0.45)),
            ),
            child: Text(presetLabel,
                style: const TextStyle(
                    color: _kEqColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        // EQ preview badge top-left
        if (_playingProcessed)
          Positioned(
            left: 8, top: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kEqColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('EQ PREVIEW',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
          ),
      ]),
    );
  }

  // ── Preset chips ──────────────────────────────────────────────────────────

  Widget _buildPresetChips() {
    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _kPresetNames.length,
        itemBuilder: (_, i) {
          final sel = _activePreset == i;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: GestureDetector(
              onTap: () => _applyPreset(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? _kEqColor.withValues(alpha: 0.20)
                      : _kOnSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: sel
                          ? _kEqColor
                          : _kOnSurface.withValues(alpha: 0.24),
                      width: 1.2),
                ),
                child: Text(_kPresetNames[i],
                    style: TextStyle(
                        color: sel
                            ? _kEqColor
                            : _kOnSurface.withValues(alpha: 0.54),
                        fontSize: 11,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 10-band sliders ───────────────────────────────────────────────────────

  Widget _buildBandSliders() {
    const kSliderH    = 120.0;
    const kLabelH     = 16.0;
    const kGainLabelH = 14.0;
    const kTotalH     = kSliderH + kLabelH + kGainLabelH + 4;

    return SizedBox(
      height: kTotalH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(
          10,
          (i) => Expanded(
            child: _BandSliderWidget(
              gain: _gains[i],
              label: _kLabels[i],
              sliderHeight: kSliderH,
              onChanged: (g) => _updateBand(i, g),
            ),
          ),
        ),
      ),
    );
  }

  // ── Preview bar ───────────────────────────────────────────────────────────

  Widget _buildPreviewButton() {
    return SizedBox(
      width: double.infinity,
      child: _AudioPreviewBar(
        waveformBars: widget.track.waveformBars,
        player:       _player,
        isProcessing: _isProcessingPreview,
        isPlaying:    _isPlaying,
        canPlay:      !_isApplying,
        cacheVersion: _cacheVer,
        onPlayPressed: _togglePreview,
      ),
    );
  }

  // ── Apply button ──────────────────────────────────────────────────────────

  Widget _buildApplyButton() {
    final isRemove = _canRestore;
    final btnColor = isRemove ? Colors.red.shade700 : const Color(0xFF5B5BD6);
    final btnLabel = isRemove ? 'Remove EQ' : 'Apply EQ';
    return SizedBox(
      width: double.infinity, height: 46,
      child: ElevatedButton(
        onPressed: (_isApplying || _isProcessingPreview) ? null : _applyToTrack,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          disabledBackgroundColor: btnColor.withValues(alpha: 0.35),
        ),
        child: _isApplying
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(btnLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }
}

// ── Band slider widget ─────────────────────────────────────────────────────────

class _BandSliderWidget extends StatelessWidget {
  final double gain;
  final String label;
  final double sliderHeight;
  final ValueChanged<double> onChanged;

  const _BandSliderWidget({
    required this.gain,
    required this.label,
    required this.sliderHeight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const kGainRange = _kMaxGain - _kMinGain;
    final gainText =
        gain >= 0 ? '+${gain.toStringAsFixed(0)}' : gain.toStringAsFixed(0);

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final pxPerDb = sliderHeight / kGainRange;
        onChanged(gain - d.delta.dy / pxPerDb);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 14,
          child: Text(gainText,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: gain.abs() > 0.1
                      ? _kEqColor
                      : _kOnSurface.withValues(alpha: 0.24),
                  fontSize: 9,
                  fontWeight: FontWeight.w600))),
        const SizedBox(height: 2),
        SizedBox(
          height: sliderHeight,
          child: CustomPaint(
              painter: _BandPainter(gain: gain),
              size: Size.infinite)),
        const SizedBox(height: 2),
        SizedBox(
          height: 16,
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _kOnSurface.withValues(alpha: 0.38), fontSize: 9))),
      ]),
    );
  }
}

// ── Band painter ───────────────────────────────────────────────────────────────

class _BandPainter extends CustomPainter {
  final double gain;
  const _BandPainter({required this.gain});

  @override
  void paint(Canvas canvas, Size size) {
    const kTrackW    = 2.0;
    const kThumbR    = 6.0;
    const kGainRange = _kMaxGain - _kMinGain;

    final cx      = size.width / 2;
    final norm    = (_kMaxGain - gain) / kGainRange;
    final thumbY  = norm * size.height;
    final centerY = size.height / 2;

    // Track
    canvas.drawLine(
      Offset(cx, kThumbR), Offset(cx, size.height - kThumbR),
      Paint()
        ..color      = _kOnSurface.withValues(alpha: 0.12)
        ..strokeWidth = kTrackW
        ..strokeCap   = StrokeCap.round);

    // 0 dB reference tick
    canvas.drawLine(
      Offset(cx - 6, centerY), Offset(cx + 6, centerY),
      Paint()..color = _kOnSurface.withValues(alpha: 0.20)..strokeWidth = 1);

    // Filled segment between center and thumb
    if (gain.abs() > 0.1) {
      canvas.drawLine(
        Offset(cx, centerY), Offset(cx, thumbY),
        Paint()
          ..color = gain > 0
              ? _kEqColor.withValues(alpha: 0.55)
              : _kOnSurface.withValues(alpha: 0.25)
          ..strokeWidth = kTrackW
          ..strokeCap   = StrokeCap.round);
    }

    // Thumb
    canvas.drawCircle(Offset(cx, thumbY), kThumbR,
        Paint()
          ..color = gain.abs() > 0.1
              ? _kEqColor
              : _kOnSurface.withValues(alpha: 0.4));

    if (gain.abs() > 0.1) {
      canvas.drawCircle(Offset(cx, thumbY), kThumbR * 0.38,
          Paint()..color = Colors.black.withValues(alpha: 0.4));
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.gain != gain;
}

// ── EQ curve painter ───────────────────────────────────────────────────────────

class _EqCurvePainter extends CustomPainter {
  final List<double> gains;
  final Color        color;
  final List<double> bars;

  const _EqCurvePainter({
    required this.gains,
    required this.color,
    required this.bars,
  });

  static double _freqToX(double freq, double width) {
    const logMin = 1.3010;
    const logMax = 4.3010;
    final logF = math.log(freq) / math.ln10;
    return ((logF - logMin) / (logMax - logMin)).clamp(0.0, 1.0) * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Waveform bars — dim background texture
    if (bars.isNotEmpty) {
      final barW = w / bars.length;
      final bp   = Paint()..color = _kOnSurface.withValues(alpha: 0.06);
      for (int i = 0; i < bars.length; i++) {
        final bh = (bars[i] * h * 0.75).clamp(0.0, h * 0.90);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(i * barW + barW * 0.1, (h - bh) / 2, barW * 0.8, bh),
            const Radius.circular(2)),
          bp);
      }
    }

    // 0 dB line
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2),
        Paint()..color = _kOnSurface.withValues(alpha: 0.12)..strokeWidth = 1);

    // ±6 dB guides
    final rp = Paint()..color = _kOnSurface.withValues(alpha: 0.06)..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, h / 2 * (1 - 6.0 / 12.0)),
        Offset(w, h / 2 * (1 - 6.0 / 12.0)),
        rp);
    canvas.drawLine(
        Offset(0, h / 2 * (1 + 6.0 / 12.0)),
        Offset(w, h / 2 * (1 + 6.0 / 12.0)),
        rp);

    // Band points
    final pts = <Offset>[];
    pts.add(Offset(0, h / 2 * (1 - gains[0] / 12.0)));
    for (int i = 0; i < 10; i++) {
      pts.add(Offset(
          _freqToX(_kFreqs[i].toDouble(), w), h / 2 * (1 - gains[i] / 12.0)));
    }
    pts.add(Offset(w, h / 2 * (1 - gains[9] / 12.0)));

    // Smooth cubic bezier
    final curvePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cpx = (pts[i + 1].dx - pts[i].dx) / 3;
      curvePath.cubicTo(
          pts[i].dx + cpx, pts[i].dy,
          pts[i + 1].dx - cpx, pts[i + 1].dy,
          pts[i + 1].dx, pts[i + 1].dy);
    }

    // Fill
    final fillPath = Path.from(curvePath)
      ..lineTo(w, h / 2)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.25),
              color.withValues(alpha: 0.05)
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Curve line
    canvas.drawPath(
        curvePath,
        Paint()
          ..color      = color.withValues(alpha: 0.90)
          ..strokeWidth = 2.0
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round
          ..strokeJoin  = StrokeJoin.round);

    // Band dots
    final dotPaint = Paint()..color = color;
    final dotBorderPaint = Paint()
      ..color       = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth  = 1.5
      ..style        = PaintingStyle.stroke;
    for (int i = 0; i < 10; i++) {
      if (gains[i].abs() > 0.1) {
        final x = _freqToX(_kFreqs[i].toDouble(), w);
        final y = h / 2 * (1 - gains[i] / 12.0);
        canvas.drawCircle(Offset(x, y), 4.5, dotPaint);
        canvas.drawCircle(Offset(x, y), 4.5, dotBorderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      old.gains != gains || old.color != color || old.bars != bars;
}

// ── Audio preview bar ──────────────────────────────────────────────────────────

class _AudioPreviewBar extends StatefulWidget {
  final List<double> waveformBars;
  final AudioPlayer  player;
  final bool isProcessing;
  final bool isPlaying;
  final bool canPlay;
  final int  cacheVersion;
  final void Function(Duration startPosition) onPlayPressed;

  const _AudioPreviewBar({
    required this.waveformBars,
    required this.player,
    required this.onPlayPressed,
    this.isProcessing  = false,
    this.isPlaying     = false,
    this.canPlay       = true,
    this.cacheVersion  = 0,
  });

  @override
  State<_AudioPreviewBar> createState() => _AudioPreviewBarState();
}

class _AudioPreviewBarState extends State<_AudioPreviewBar> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking    = false;

  final _waveformKey = GlobalKey();

  late StreamSubscription<Duration> _posSub;
  late StreamSubscription<Duration> _durSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.player.onPositionChanged.listen((pos) {
      if (!_isSeeking && mounted) setState(() => _position = pos);
    });
    _durSub = widget.player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  @override
  void didUpdateWidget(_AudioPreviewBar old) {
    super.didUpdateWidget(old);
    if (old.cacheVersion != widget.cacheVersion) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _posSub.cancel();
    _durSub.cancel();
    super.dispose();
  }

  double _waveformWidth() {
    final box = _waveformKey.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size.width : 200.0;
  }

  void _seekFromGesture(double dx) {
    if (_duration == Duration.zero) return;
    final frac   = (dx / _waveformWidth()).clamp(0.0, 1.0);
    final target = Duration(
        microseconds: (frac * _duration.inMicroseconds).round());
    setState(() => _position = target);
    if (widget.isPlaying) widget.player.seek(target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _duration.inMicroseconds > 0
        ? (_position.inMicroseconds / _duration.inMicroseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final canInteract = widget.canPlay && !widget.isProcessing;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _kEqColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kEqColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Play / Stop button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canInteract
                ? () => widget.onPlayPressed(_position)
                : null,
            child: SizedBox(
              width: 46,
              child: Center(
                child: widget.isProcessing
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: _kEqColor, strokeWidth: 2))
                    : Icon(
                        widget.isPlaying
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: canInteract
                            ? _kEqColor
                            : _kEqColor.withValues(alpha: 0.28),
                        size: 28),
              ),
            ),
          ),
          // Waveform + cursor
          Expanded(
            child: GestureDetector(
              key: _waveformKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seekFromGesture(d.localPosition.dx),
              onHorizontalDragStart: (d) {
                _isSeeking = true;
                _seekFromGesture(d.localPosition.dx);
              },
              onHorizontalDragUpdate: (d) =>
                  _seekFromGesture(d.localPosition.dx),
              onHorizontalDragEnd: (_) =>
                  setState(() => _isSeeking = false),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: _PreviewWaveformPainter(
                      bars:     widget.waveformBars,
                      fraction: fraction,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Time readout
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 6),
            child: Center(
              child: Text(
                '${_fmt(_position)}\n${_fmt(_duration)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kEqColor.withValues(alpha: 0.75),
                  fontSize: 9,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Preview waveform painter ───────────────────────────────────────────────────

class _PreviewWaveformPainter extends CustomPainter {
  final List<double> bars;
  final double       fraction;

  const _PreviewWaveformPainter({required this.bars, required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w == 0 || h == 0 || bars.isEmpty) return;

    final barW    = w / bars.length;
    final cursorX = (fraction * w).clamp(0.0, w);

    for (int i = 0; i < bars.length; i++) {
      final barH = (bars[i] * h * 0.88).clamp(2.0, h);
      final cx   = i * barW + barW / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * barW + barW * 0.1, (h - barH) / 2, barW * 0.8, barH),
          const Radius.circular(1)),
        Paint()
          ..color = cx <= cursorX
              ? _kEqColor.withValues(alpha: 0.85)
              : _kEqColor.withValues(alpha: 0.22),
      );
    }

    // Cursor line
    canvas.drawLine(
      Offset(cursorX, 0), Offset(cursorX, h),
      Paint()..color = Colors.white.withValues(alpha: 0.88)..strokeWidth = 1.5);

    // Cursor handle
    canvas.drawCircle(Offset(cursorX, h / 2), 4.0,
        Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cursorX, h / 2), 4.0,
        Paint()
          ..color      = _kEqColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth  = 1.5);
  }

  @override
  bool shouldRepaint(_PreviewWaveformPainter old) =>
      old.fraction != fraction || old.bars != bars;
}
