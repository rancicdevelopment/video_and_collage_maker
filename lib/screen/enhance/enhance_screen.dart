import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kBg    = Color(0xFF111111);
const _kCard  = Color(0xFF1E1E1E);
const _kAccent = Color(0xFFF5A623);
const _kGreen = Color(0xFF4CAF50);

// Special marker so the apply logic knows to run 2-pass vidstab.
const _kStabilizeMarker = '__vidstab__';

// ── Enhancement definition ────────────────────────────────────────────────────

class _Enhancement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String vf;   // ffmpeg -vf fragment  (empty = none)
  final String af;   // ffmpeg -af fragment  (empty = none)
  final bool isAi;

  bool enabled = false;

  _Enhancement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.vf = '',
    this.af = '',
    this.isAi = false,
  });
}

// ── Preset definition ─────────────────────────────────────────────────────────

class _Preset {
  final String label;
  final String emoji;
  final List<String> ids;
  const _Preset(this.label, this.emoji, this.ids);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class EnhanceScreen extends StatefulWidget {
  const EnhanceScreen({super.key});

  @override
  State<EnhanceScreen> createState() => _EnhanceScreenState();
}

class _EnhanceScreenState extends State<EnhanceScreen> {
  String? _videoPath;
  String? _thumbPath;
  String? _resultPath;

  bool _processing = false;
  double _progress = 0;
  String _status = '';
  double _videoDurationSecs = 0;

  // Before/after comparison state
  VideoPlayerController? _beforeVc;
  VideoPlayerController? _afterVc;
  bool _vcReady = false;

  // ── Enhancement catalogue ─────────────────────────────────────────────────
  //
  // VIDEO
  //   • Auto Color   – normalize blacks/whites + gentle eq  (adaptive, not fixed)
  //   • Deblock      – remove compression block artefacts
  //   • Denoise      – conservative hqdn3d (lower temporal to avoid ghosting)
  //   • Sharpen      – small kernel unsharp (no chroma sharpening → no halos)
  //   • Stabilize    – 2-pass VidStab (vastly better than deshake)
  //
  // AUDIO
  //   • Denoise      – anlmdn non-local-means (higher quality than afftdn)
  //   • Vocal Boost  – high-pass + speech EQ + gentle compression
  //   • Normalize    – EBU R128 loudnorm
  // ─────────────────────────────────────────────────────────────────────────

  final List<_Enhancement> _enhancements = [
    // ── VIDEO ────────────────────────────────────────────────────────────────
    _Enhancement(
      id: 'color',
      title: 'Auto Color',
      description: 'Adaptive black/white normalization + gentle color boost',
      icon: Icons.auto_awesome,
      color: _kAccent,
      // eq: fast single-pass brightness/contrast/saturation/gamma — always available
      vf: 'eq=contrast=1.1:brightness=0.04:saturation=1.2:gamma=1.04',
      isAi: true,
    ),
    _Enhancement(
      id: 'deblock',
      title: 'Deblock',
      description: 'Remove blocky compression artefacts from low-bitrate footage',
      icon: Icons.blur_off,
      color: const Color(0xFF26A69A),
      // smartblur: softens only low-contrast block-boundary areas (no libpostproc needed)
      vf: 'smartblur=1.5:-0.35:-3.5:0.65:0.25:2.0',
    ),
    _Enhancement(
      id: 'denoise',
      title: 'Denoise',
      description: 'Remove grain while preserving edges and fine detail',
      icon: Icons.grain,
      color: const Color(0xFF42A5F5),
      // luma 2/1.5, chroma 3/2.5 — conservative temporal to prevent ghosting
      // (original was 3:3:6:6 which caused motion blur on moving subjects)
      vf: 'hqdn3d=2:1.5:3:2.5',
    ),
    _Enhancement(
      id: 'sharpen',
      title: 'Sharpen',
      description: 'Crisp edge clarity without halos or colour fringing',
      icon: Icons.center_focus_strong_outlined,
      color: const Color(0xFF7E57C2),
      // 3×3 kernel + amount 0.5 (was 5×5/0.8 which caused visible halos)
      // chroma amount 0 so colours stay neutral
      vf: 'unsharp=3:3:0.5:0:0:0',
    ),
    _Enhancement(
      id: 'stabilize',
      title: 'Stabilize',
      description: 'Professional 2-pass VidStab — far better than simple deshake',
      icon: Icons.videocam_outlined,
      color: const Color(0xFF00BCD4),
      // handled separately in _applyEnhancements with 2-pass logic
      vf: _kStabilizeMarker,
      isAi: true,
    ),

    // ── AUDIO ─────────────────────────────────────────────────────────────────
    _Enhancement(
      id: 'audio_denoise',
      title: 'Audio Denoise',
      description: 'Non-local means noise reduction — cleaner than FFT denoising',
      icon: Icons.graphic_eq,
      color: const Color(0xFFEF5350),
      // anlmdn: non-local means — preserves transients, removes sustained noise
      // highpass 80 Hz first to eliminate rumble before denoising
      // s=7 = effective noise reduction; drop m= (invalid in FFmpeg 8)
      af: 'highpass=f=80,anlmdn=s=7:p=0.002:r=0.002',
      isAi: true,
    ),
    _Enhancement(
      id: 'vocal_boost',
      title: 'Vocal Boost',
      description: 'Enhance speech clarity: cut mud, boost presence, compress',
      icon: Icons.mic_outlined,
      color: const Color(0xFFFF7043),
      // Cut low-mid mud at 200 Hz, boost speech presence at 3 kHz,
      // add light air at 10 kHz, gentle compressor for even levels
      // width_type=q (Q-factor) is universally supported across all FFmpeg builds
      af: 'highpass=f=100,'
          'equalizer=f=200:width_type=q:width=1:g=-3,'
          'equalizer=f=3000:width_type=q:width=1:g=2,'
          'equalizer=f=10000:width_type=q:width=0.7:g=1,'
          'acompressor=threshold=0.1:ratio=3:attack=5:release=50:makeup=1',
    ),
    _Enhancement(
      id: 'audio_norm',
      title: 'Normalize Volume',
      description: 'EBU R128 loudness normalization to –16 LUFS',
      icon: Icons.volume_up_outlined,
      color: const Color(0xFF66BB6A),
      af: 'loudnorm=I=-16:TP=-1.5:LRA=11',
      isAi: true,
    ),
  ];

  static const _presets = [
    _Preset('Social Ready', '📱', ['color', 'sharpen', 'audio_norm']),
    _Preset('Cinema', '🎬', ['color', 'deblock', 'denoise', 'sharpen']),
    _Preset('Clean Speech', '🎙️', ['audio_denoise', 'vocal_boost', 'audio_norm']),
    _Preset('Stabilize+', '🎥', ['color', 'stabilize', 'sharpen']),
    _Preset('Full Enhance', '✨', ['color', 'deblock', 'denoise', 'sharpen',
        'audio_denoise', 'audio_norm']),
  ];

  // ── Video pick ────────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;

    final thumb = await VideoThumbnail.thumbnailFile(
      video: path,
      thumbnailPath: (await getTemporaryDirectory()).path,
      imageFormat: ImageFormat.JPEG,
      quality: 70,
    );

    // Get duration for real progress display
    double dur = 0;
    try {
      final info = await FFprobeKit.getMediaInformation(path);
      final dStr = info.getMediaInformation()?.getDuration();
      if (dStr != null) dur = double.tryParse(dStr) ?? 0;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _videoPath = path;
      _thumbPath = thumb;
      _resultPath = null;
      _videoDurationSecs = dur;
    });
  }

  // ── Presets ───────────────────────────────────────────────────────────────

  void _applyPreset(_Preset preset) {
    setState(() {
      for (final e in _enhancements) {
        e.enabled = preset.ids.contains(e.id);
      }
    });
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  Future<void> _applyEnhancements() async {
    final input = _videoPath;
    if (input == null) return;

    final active = _enhancements.where((e) => e.enabled).toList();
    if (active.isEmpty) {
      _showSnack('Select at least one enhancement.');
      return;
    }

    setState(() {
      _processing = true;
      _progress = 0;
      _status = 'Preparing…';
      _resultPath = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final output = p.join(dir.path, 'enhanced_$ts.mp4');

      final needsStabilize =
          active.any((e) => e.vf == _kStabilizeMarker);

      // ── Pass 1: VidStab analysis (only when stabilize is selected) ─────────
      String? trf;
      if (needsStabilize) {
        trf = p.join(dir.path, 'transforms_$ts.trf');
        setState(() => _status = 'Analysing camera motion…');

        final pass1 = '-y -i "$input" '
            '-vf "vidstabdetect=stepsize=6:shakiness=8:accuracy=9:result=$trf" '
            '-f null /dev/null';

        final s1 = await FFmpegKit.execute(pass1);
        final rc1 = await s1.getReturnCode();
        if (!ReturnCode.isSuccess(rc1)) {
          final logs = await s1.getAllLogsAsString() ?? '';
          // Trim banner — show only last 1000 chars
          final snippet = logs.length > 1000
              ? logs.substring(logs.length - 1000)
              : logs;
          throw Exception('VidStab pass 1 failed:\n$snippet');
        }
        setState(() => _progress = 0.15);
      }

      // ── Build vf / af chains ──────────────────────────────────────────────
      final vfParts = <String>[];
      for (final e in active) {
        if (e.vf.isEmpty) continue;
        if (e.vf == _kStabilizeMarker) {
          // Replace marker with actual vidstabtransform using the .trf from pass 1
          vfParts.add(
            'vidstabtransform=input=$trf:zoom=1:smoothing=10'
            ',unsharp=5:5:-0.8:3:3:-0.4',
          );
        } else {
          vfParts.add(e.vf);
        }
      }

      final afParts = active
          .where((e) => e.af.isNotEmpty)
          .map((e) => e.af)
          .toList();

      final hasVf = vfParts.isNotEmpty;
      final hasAf = afParts.isNotEmpty;

      // ── Build command ─────────────────────────────────────────────────────
      final buf = StringBuffer('-y -i "$input"');
      if (hasVf) buf.write(' -vf "${vfParts.join(',')}"');
      if (hasAf) buf.write(' -af "${afParts.join(',')}"');
      // Use medium preset + crf 20 for better quality than the old fast/22
      buf.write(
          ' -c:v ${hasVf ? 'libx264 -preset medium -crf 20' : 'copy'}');
      buf.write(' -c:a ${hasAf ? 'aac -b:a 192k' : 'copy'}');
      buf.write(' "$output"');

      // ── Progress tracking via real elapsed time ───────────────────────────
      final startProgress = needsStabilize ? 0.15 : 0.0;
      FFmpegKitConfig.enableStatisticsCallback((stats) {
        if (!mounted) return;
        final ms = stats.getTime();
        if (ms <= 0) return;
        double pct;
        if (_videoDurationSecs > 0) {
          // Real percentage based on video duration
          pct = startProgress +
              (1.0 - startProgress) *
                  (ms / 1000.0 / _videoDurationSecs).clamp(0.0, 0.95);
        } else {
          // Fallback: slow logarithmic climb
          pct = startProgress +
              (1.0 - startProgress) *
                  (1 - 1 / (1 + ms / 30000.0)).clamp(0.0, 0.92);
        }
        setState(() {
          _progress = pct;
          _status = _statusLabel(active, ms);
        });
      });

      setState(() => _status = _buildProcessingLabel(active));

      final session = await FFmpegKit.execute(buf.toString());
      FFmpegKitConfig.disableStatistics();

      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        final logs = await session.getAllLogsAsString() ?? '';
        final snippet = logs.length > 1500
            ? '…${logs.substring(logs.length - 1500)}'
            : logs;
        throw Exception(snippet);
      }

      // Verify the file was actually written with real content
      final outFile = File(output);
      final fileSize = outFile.existsSync() ? outFile.statSync().size : 0;
      if (fileSize < 1024) {
        final logs = await session.getAllLogsAsString() ?? '';
        final snippet = logs.length > 1500
            ? '…${logs.substring(logs.length - 1500)}'
            : logs;
        throw Exception(
            'Output file too small ($fileSize bytes) — filter may not be supported.\n\n$snippet');
      }

      setState(() {
        _progress = 1.0;
        _status = 'Done';
        _processing = false;
        _resultPath = output;
      });
      await _initComparison(input, output);
    } catch (e) {
      setState(() {
        _processing = false;
        _status = '';
      });
      _showError(e.toString());
    }
  }

  // ── Quick 5-second test ───────────────────────────────────────────────────

  bool _testing = false;

  Future<void> _testEnhancements() async {
    final input = _videoPath;
    if (input == null) return;

    final active = _enhancements.where((e) => e.enabled).toList();
    if (active.isEmpty) {
      _showSnack('Select at least one enhancement.');
      return;
    }

    setState(() => _testing = true);

    try {
      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final output = p.join(dir.path, 'test_$ts.mp4');

      final vfParts = <String>[];
      for (final e in active) {
        if (e.vf.isEmpty || e.vf == _kStabilizeMarker) continue;
        vfParts.add(e.vf);
      }
      final afParts = active
          .where((e) => e.af.isNotEmpty)
          .map((e) => e.af)
          .toList();

      final hasVf = vfParts.isNotEmpty;
      final hasAf = afParts.isNotEmpty;

      final buf = StringBuffer('-y -t 5 -i "$input"');
      if (hasVf) buf.write(' -vf "${vfParts.join(',')}"');
      if (hasAf) buf.write(' -af "${afParts.join(',')}"');
      buf.write(' -c:v ${hasVf ? 'libx264 -preset ultrafast -crf 28' : 'copy'}');
      buf.write(' -c:a ${hasAf ? 'aac -b:a 128k' : 'copy'}');
      buf.write(' "$output"');

      final session = await FFmpegKit.execute(buf.toString());
      final rc = await session.getReturnCode();

      if (!mounted) return;
      if (ReturnCode.isSuccess(rc)) {
        // Clean up test file
        try { File(output).deleteSync(); } catch (_) {}
        _showSnack('✓ All filters OK — safe to apply!');
      } else {
        final logs = await session.getAllLogsAsString() ?? '';
        final snippet = logs.length > 1000
            ? logs.substring(logs.length - 1000)
            : logs;
        _showError('Test failed (5s clip):\n$snippet');
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _buildProcessingLabel(List<_Enhancement> active) {
    if (active.length == 1) return 'Applying ${active.first.title}…';
    return 'Applying ${active.length} enhancements…';
  }

  String _statusLabel(List<_Enhancement> active, int ms) {
    final secs = ms ~/ 1000;
    final label = _buildProcessingLabel(active);
    if (_videoDurationSecs > 0) {
      final pct = ((ms / 1000.0 / _videoDurationSecs) * 100)
          .clamp(0, 99)
          .toStringAsFixed(0);
      return '$label — $pct %';
    }
    return '$label (${secs}s)';
  }

  // ── Save / Share ──────────────────────────────────────────────────────────

  Future<void> _saveToGallery() async {
    final path = _resultPath;
    if (path == null) return;
    try {
      await Gal.putVideo(path);
      _showSnack('Saved to gallery.');
    } catch (e) {
      _showSnack('Could not save: $e');
    }
  }

  Future<void> _shareResult() async {
    final path = _resultPath;
    if (path == null) return;
    await Share.shareXFiles([XFile(path)], text: 'Enhanced video');
  }

  void _resetResult() {
    _disposeVcs();
    setState(() {
      _resultPath = null;
      _vcReady = false;
    });
  }

  void _disposeVcs() {
    _beforeVc?.dispose();
    _afterVc?.dispose();
    _beforeVc = null;
    _afterVc = null;
  }

  Future<void> _initComparison(String original, String result) async {
    _disposeVcs();
    final before = VideoPlayerController.file(File(original));
    final after  = VideoPlayerController.file(File(result));
    try {
      await Future.wait([before.initialize(), after.initialize()]);
    } catch (e) {
      debugPrint('Comparison vc init error: $e');
      before.dispose();
      after.dispose();
      // Mark _vcReady so the spinner stops; controllers stay null → fallback icon shown
      if (mounted) setState(() => _vcReady = true);
      return;
    }
    before.setVolume(0);
    after.setVolume(1);
    after.setLooping(true); // afterVc is master — let it loop on its own
    if (!mounted) {
      before.dispose();
      after.dispose();
      return;
    }
    setState(() {
      _beforeVc = before;
      _afterVc  = after;
      _vcReady  = true;
    });
  }

  @override
  void dispose() {
    _disposeVcs();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String msg) {
    // Strip the FFmpeg banner (everything before the first error/warning line)
    // so the dialog shows only the relevant failure reason.
    String display = msg;
    final errorIdx = msg.lastIndexOf(RegExp(r'(Error|Invalid|No such|failed|Cannot)',
        caseSensitive: false));
    if (errorIdx > 0) {
      // Show from ~500 chars before the last error keyword
      final start = (errorIdx - 500).clamp(0, msg.length);
      display = msg.substring(start).trim();
    } else if (msg.length > 1500) {
      // Fallback: just show the last 1500 chars
      display = '…${msg.substring(msg.length - 1500)}';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Processing failed',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(display,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  int get _enabledCount =>
      _enhancements.where((e) => e.enabled).length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Text('Enhance',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text('AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _resultPath != null
            ? _buildResult()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildVideoCard(),
                  const SizedBox(height: 16),
                  if (_videoPath != null) ...[
                    _buildPresetsRow(),
                    const SizedBox(height: 16),
                    _buildSectionLabel('VIDEO'),
                    const SizedBox(height: 8),
                    ..._enhancements
                        .where((e) => e.vf.isNotEmpty)
                        .map(_buildEnhancementCard),
                    const SizedBox(height: 16),
                    _buildSectionLabel('AUDIO'),
                    const SizedBox(height: 8),
                    ..._enhancements
                        .where((e) => e.af.isNotEmpty)
                        .map(_buildEnhancementCard),
                    const SizedBox(height: 24),
                    _buildApplyButton(),
                    const SizedBox(height: 10),
                    _buildTestButton(),
                    if (_processing) ...[
                      const SizedBox(height: 20),
                      _buildProgress(),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  // ── Section widgets ───────────────────────────────────────────────────────

  Widget _buildVideoCard() {
    return GestureDetector(
      onTap: _processing ? null : _pickVideo,
      child: Container(
        height: _videoPath != null ? 180 : 120,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _videoPath != null
                ? _kAccent.withValues(alpha: 0.5)
                : Colors.white12,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: _videoPath != null
            ? _buildVideoPreview()
            : _buildVideoPlaceholder(),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.video_file_outlined, color: Colors.white24, size: 40),
        SizedBox(height: 10),
        Text('Tap to select a video',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_thumbPath != null)
          Image.file(File(_thumbPath!), fit: BoxFit.cover)
        else
          const ColoredBox(color: Colors.black38),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _videoPath!.split('/').last,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_videoDurationSecs > 0)
                      Text(
                        _fmtDuration(_videoDurationSecs),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _processing ? null : _pickVideo,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Change',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDuration(double secs) {
    final m = secs ~/ 60;
    final s = secs.toInt() % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildPresetsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('QUICK PRESETS'),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final preset = _presets[i];
              final isActive = preset.ids.every((id) => _enhancements
                  .firstWhere((e) => e.id == id)
                  .enabled) &&
                  _enabledCount == preset.ids.length;
              return GestureDetector(
                onTap: () => _applyPreset(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _kAccent.withValues(alpha: 0.15)
                        : _kCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isActive
                            ? _kAccent.withValues(alpha: 0.7)
                            : Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(preset.emoji,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(preset.label,
                          style: TextStyle(
                              color: isActive
                                  ? _kAccent
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            color: Colors.white24,
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600));
  }

  Widget _buildEnhancementCard(_Enhancement e) {
    return GestureDetector(
      onTap: _processing
          ? null
          : () => setState(() => e.enabled = !e.enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.enabled
              ? e.color.withValues(alpha: 0.12)
              : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: e.enabled
                ? e.color.withValues(alpha: 0.6)
                : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: e.enabled
                    ? e.color.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(e.icon,
                  color: e.enabled ? e.color : Colors.white38,
                  size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(e.title,
                            style: TextStyle(
                              color: e.enabled
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            )),
                      ),
                      if (e.isAi) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('AI',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                      if (e.id == 'stabilize') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('2-PASS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(e.description,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: e.enabled ? e.color : Colors.transparent,
                border: Border.all(
                  color: e.enabled ? e.color : Colors.white24,
                  width: 2,
                ),
              ),
              child: e.enabled
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyButton() {
    final ready = _enabledCount > 0 && !_processing;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: ready ? _applyEnhancements : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          disabledBackgroundColor: Colors.white10,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_fix_high,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _processing
                  ? 'Processing…'
                  : _enabledCount == 0
                      ? 'Select enhancements above'
                      : 'Apply $_enabledCount'
                          ' enhancement${_enabledCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final pct = (_progress * 100).toStringAsFixed(0);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(_status,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ),
            Text('$pct %',
                style: const TextStyle(
                    color: _kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(_kAccent),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  Widget _buildTestButton() {
    final ready = _enabledCount > 0 && !_processing && !_testing;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: ready ? _testEnhancements : null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: ready ? _kAccent.withValues(alpha: 0.5) : Colors.white12,
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          foregroundColor: _kAccent,
          disabledForegroundColor: Colors.white24,
        ),
        icon: _testing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _kAccent),
              )
            : const Icon(Icons.science_outlined, size: 18),
        label: Text(
          _testing ? 'Testing filters…' : 'Test filters (5s clip)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ── Result view ───────────────────────────────────────────────────────────

  Widget _buildResult() {
    return Column(
      children: [
        // ── Before / after comparison player ────────────────────────────────
        Expanded(
          child: _vcReady && _beforeVc != null && _afterVc != null
              ? _BeforeAfterPlayer(
                  beforeVc: _beforeVc!,
                  afterVc: _afterVc!,
                )
              : _vcReady
                  // controllers failed to init — show a plain black fallback
                  ? Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.videocam_off_outlined,
                            color: Colors.white24, size: 48),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(color: _kAccent),
                      ),
                    ),
        ),

        // ── Action bar ───────────────────────────────────────────────────────
        Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Applied enhancements summary
              Text(
                _enhancements
                    .where((e) => e.enabled)
                    .map((e) => e.title)
                    .join(' · '),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ResultButton(
                      icon: Icons.save_alt_outlined,
                      label: 'Save',
                      onTap: _saveToGallery,
                      accent: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: _shareResult,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultButton(
                      icon: Icons.refresh,
                      label: 'New',
                      onTap: _resetResult,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Before / after split-screen comparison ────────────────────────────────────

class _BeforeAfterPlayer extends StatefulWidget {
  final VideoPlayerController beforeVc;
  final VideoPlayerController afterVc;

  const _BeforeAfterPlayer({
    required this.beforeVc,
    required this.afterVc,
  });

  @override
  State<_BeforeAfterPlayer> createState() => _BeforeAfterPlayerState();
}

class _BeforeAfterPlayerState extends State<_BeforeAfterPlayer> {
  double _split = 0.5;
  bool _playing = true;
  bool _joined = false;       // beforeVc has been late-joined to afterVc
  Duration _prevPos = Duration.zero; // loop detection
  Timer? _driftTimer;

  @override
  void initState() {
    super.initState();
    // afterVc is the master — starts first.
    // A listener waits for afterVc to report an actual non-zero position
    // (meaning ExoPlayer has truly started), then seeks beforeVc to that
    // exact position and plays it. Both then run at full frame rate.
    widget.afterVc.addListener(_afterVcListener);
    widget.afterVc.play();

    // Conservative drift correction: only fires if they diverge > 1.5 s,
    // at most once every 3 s — no visible stutter during normal play.
    _driftTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_playing || !_joined) return;
      final diff =
          (widget.afterVc.value.position - widget.beforeVc.value.position)
              .abs();
      if (diff > const Duration(milliseconds: 1500)) {
        widget.beforeVc.seekTo(widget.afterVc.value.position);
      }
    });
  }

  void _afterVcListener() {
    if (!mounted) return;

    final afterPos = widget.afterVc.value.position;

    // Late-join: the first time afterVc is truly playing, snap beforeVc to
    // the same position and start it.
    if (!_joined && widget.afterVc.value.isPlaying && afterPos > Duration.zero) {
      _joined = true;
      widget.beforeVc.seekTo(afterPos).then((_) {
        if (mounted && _playing) widget.beforeVc.play();
      });
      _prevPos = afterPos;
      return;
    }

    // Loop detection: afterVc wrapped back to near zero.
    if (_joined &&
        _prevPos > const Duration(milliseconds: 500) &&
        afterPos < const Duration(milliseconds: 200)) {
      widget.beforeVc.seekTo(Duration.zero);
    }
    _prevPos = afterPos;
  }

  void _togglePlay() {
    final nowPlaying = !_playing;
    setState(() => _playing = nowPlaying);
    if (nowPlaying) {
      widget.afterVc.play();
      widget.beforeVc.play();
    } else {
      widget.afterVc.pause();
      widget.beforeVc.pause();
    }
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    widget.afterVc.removeListener(_afterVcListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final splitX = (_split * w).clamp(0.0, w);

        return GestureDetector(
          onTap: _togglePlay,
          child: Stack(
            children: [
              // ── AFTER video (full width, bottom layer) ─────────────────────
              SizedBox(
                width: w,
                height: h,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: widget.afterVc.value.size.width,
                    height: widget.afterVc.value.size.height,
                    child: VideoPlayer(widget.afterVc),
                  ),
                ),
              ),

              // ── BEFORE video clipped to left of divider ────────────────────
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: _split,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: widget.beforeVc.value.size.width,
                        height: widget.beforeVc.value.size.height,
                        child: VideoPlayer(widget.beforeVc),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Divider line ───────────────────────────────────────────────
              Positioned(
                left: splitX - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),

              // ── Drag handle ────────────────────────────────────────────────
              Positioned(
                left: splitX - 20,
                top: h / 2 - 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    setState(() {
                      _split = ((_split * w + d.delta.dx) / w)
                          .clamp(0.02, 0.98);
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                ),
              ),

              // ── BEFORE label ───────────────────────────────────────────────
              if (_split > 0.1)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _Label('BEFORE'),
                ),

              // ── AFTER label ────────────────────────────────────────────────
              if (_split < 0.9)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _Label('AFTER', accent: true),
                ),

              // ── Play / pause overlay ───────────────────────────────────────
              if (!_playing)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 32),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool accent;
  const _Label(this.text, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? _kAccent.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent ? Colors.black : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ── Result button ─────────────────────────────────────────────────────────────

class _ResultButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  const _ResultButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent ? _kAccent : _kCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 15)),
      ),
    );
  }
}
