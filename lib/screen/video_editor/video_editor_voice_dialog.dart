import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'video_editor_model.dart';

// ── Voice effect model ────────────────────────────────────────────────────────

class _VoiceEffect {
  final int      index;
  final String   label;
  final IconData icon;
  final Color    bgColor;
  final Color    iconColor;

  /// FFmpeg -af filter string. Null = passthrough (Normal).
  final String? filter;

  const _VoiceEffect({
    required this.index,
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.iconColor,
    this.filter,
  });
}

const _kEffects = <_VoiceEffect>[
  _VoiceEffect(
    index:     0,
    label:     'Normal',
    icon:      Icons.graphic_eq,
    bgColor:   Color(0xFF2A2A2E),
    iconColor: Color(0xFF9E9E9E),
  ),
  _VoiceEffect(
    index:     1,
    label:     'Hall',
    icon:      Icons.account_balance,
    bgColor:   Color(0xFF2D1B69),
    iconColor: Color(0xFFB39DDB),
    filter:    'aecho=0.8:0.88:60:0.4',
  ),
  _VoiceEffect(
    index:     2,
    label:     'Girl',
    icon:      Icons.face_3,
    bgColor:   Color(0xFF004D40),
    iconColor: Color(0xFF80CBC4),
    filter:    'asetrate=55125,aresample=44100',
  ),
  _VoiceEffect(
    index:     3,
    label:     'Woman',
    icon:      Icons.face_4,
    bgColor:   Color(0xFF4A1942),
    iconColor: Color(0xFFCE93D8),
    filter:    'asetrate=49392,aresample=44100',
  ),
  _VoiceEffect(
    index:     4,
    label:     'Boy',
    icon:      Icons.face_6,
    bgColor:   Color(0xFF0D3349),
    iconColor: Color(0xFF81D4FA),
    filter:    'asetrate=38808,aresample=44100',
  ),
  _VoiceEffect(
    index:     5,
    label:     'Multiple',
    icon:      Icons.people,
    bgColor:   Color(0xFF3E2723),
    iconColor: Color(0xFFFFCC80),
    filter:    'aecho=0.8:0.88:40|70|100:0.3|0.2|0.1',
  ),
  _VoiceEffect(
    index:     6,
    label:     'Robot',
    icon:      Icons.smart_toy,
    bgColor:   Color(0xFF004D40),
    iconColor: Color(0xFF4DD0E1),
    filter:    'tremolo=f=20:d=0.9,aecho=0.9:0.7:6:0.6',
  ),
  _VoiceEffect(
    index:     7,
    label:     'Alien',
    icon:      Icons.auto_awesome,
    bgColor:   Color(0xFF1A237E),
    iconColor: Color(0xFF80CBC4),
    filter:    'asetrate=66150,aresample=44100,aecho=0.6:0.5:5:0.7',
  ),
  _VoiceEffect(
    index:     8,
    label:     'Foreigner',
    icon:      Icons.language,
    bgColor:   Color(0xFF3E2723),
    iconColor: Color(0xFFFFB74D),
    filter:    'asetrate=33075,aresample=44100,aecho=0.7:0.7:80:0.3',
  ),
];

const _kVoiceAccent = Color(0xFF1E88E5);

// ── Public API ────────────────────────────────────────────────────────────────

Future<void> showVeVoiceDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(TimelineTrack) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VeVoiceSheet(
      track:        track,
      onLiveUpdate: onLiveUpdate,
    ),
  );
  if (confirmed == true) {
    onConfirm();
  } else {
    onCancel();
  }
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _VeVoiceSheet extends StatefulWidget {
  final TimelineTrack track;
  final void Function(TimelineTrack) onLiveUpdate;

  const _VeVoiceSheet({
    required this.track,
    required this.onLiveUpdate,
  });

  @override
  State<_VeVoiceSheet> createState() => _VeVoiceSheetState();
}

class _VeVoiceSheetState extends State<_VeVoiceSheet> {
  // ── Selection ─────────────────────────────────────────────────────────────
  late int _selectedIdx;

  // ── Audio preview ─────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying     = false;
  bool _isProcessing  = false;

  /// Cached temp file paths: effectIndex → mp3 path.
  final Map<int, String> _cache = {};

  @override
  void initState() {
    super.initState();
    _selectedIdx = widget.track.voiceEffectIndex;
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    for (final path in _cache.values) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  // ── Effect selection ──────────────────────────────────────────────────────

  Future<void> _selectEffect(int idx) async {
    if (idx == _selectedIdx && _isPlaying) {
      // Tap again → toggle play/pause.
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    await _player.stop();
    setState(() {
      _selectedIdx = idx;
      _isPlaying   = false;
    });

    widget.onLiveUpdate(widget.track.copyWith(voiceEffectIndex: idx));

    // Play preview automatically.
    await _playPreview(idx);
  }

  Future<void> _playPreview(int idx) async {
    final effect = _kEffects[idx];

    // Normal — play original directly (no processing).
    if (effect.filter == null) {
      final path = widget.track.filePath;
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _isPlaying = true);
      return;
    }

    // Check cache.
    if (_cache.containsKey(idx)) {
      final cached = _cache[idx]!;
      if (File(cached).existsSync()) {
        await _player.play(DeviceFileSource(cached));
        if (mounted) setState(() => _isPlaying = true);
        return;
      }
    }

    // Process with FFmpeg (first 12 s clip for fast preview).
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final tmpDir = await getTemporaryDirectory();
      final outPath =
          '${tmpDir.path}/ve_voice_${idx}_${DateTime.now().millisecondsSinceEpoch}.aac';

      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i', widget.track.filePath,
        '-vn',
        '-t', '12',
        '-af', effect.filter!,
        '-c:a', 'aac',
        '-b:a', '128k',
        outPath,
      ]);

      if (!mounted) return;

      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        _cache[idx] = outPath;
        await _player.play(DeviceFileSource(outPath));
        if (mounted) setState(() => _isPlaying = true);
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint('Voice preview FFmpeg error: $logs');
      }
    } catch (e) {
      debugPrint('Voice preview error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Play / pause toggle ───────────────────────────────────────────────────

  Future<void> _togglePlayPause() async {
    if (_isProcessing) return;
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _playPreview(_selectedIdx);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111E2F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 20 + MediaQuery.of(context).viewInsets.bottom),
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

          // Title row + play/pause
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voice Changer',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Tap an effect to hear a preview',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              // Play / pause / spinner
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _kVoiceAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: _kVoiceAccent.withValues(alpha: 0.4)),
                  ),
                  child: _isProcessing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kVoiceAccent,
                          ),
                        )
                      : Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: _kVoiceAccent,
                          size: 22,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Effect grid ────────────────────────────────────────────────
          _buildEffectsGrid(),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _player.stop();
                    setState(() {
                      _selectedIdx = 0;
                      _isPlaying   = false;
                    });
                    widget.onLiveUpdate(
                        widget.track.copyWith(voiceEffectIndex: 0));
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
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kVoiceAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEffectsGrid() {
    const columns = 4;
    final rows = <Widget>[];

    for (int i = 0; i < _kEffects.length; i += columns) {
      final rowEffects = _kEffects.sublist(
        i,
        (i + columns).clamp(0, _kEffects.length),
      );
      rows.add(Row(
        children: [
          for (int j = 0; j < columns; j++)
            Expanded(
              child: j < rowEffects.length
                  ? _effectCell(rowEffects[j])
                  : const SizedBox(),
            ),
        ],
      ));
      if (i + columns < _kEffects.length) rows.add(const SizedBox(height: 14));
    }

    return Column(children: rows);
  }

  Widget _effectCell(_VoiceEffect effect) {
    final isSel  = _selectedIdx == effect.index;
    final isThis = isSel && _isProcessing;

    return GestureDetector(
      onTap: () => _selectEffect(effect.index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(
                    color: effect.bgColor,
                    shape: BoxShape.circle,
                    border: isSel
                        ? Border.all(color: _kVoiceAccent, width: 2.5)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: effect.bgColor.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: isThis
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kVoiceAccent),
                        )
                      : Icon(effect.icon, color: effect.iconColor, size: 26),
                ),
                if (isSel && !isThis)
                  Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                      color: _kVoiceAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 13),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              effect.label,
              style: TextStyle(
                color: isSel ? _kVoiceAccent : Colors.white54,
                fontSize: 10,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
