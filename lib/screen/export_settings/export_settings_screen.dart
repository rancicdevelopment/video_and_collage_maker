import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../export_result/export_result_screen.dart';
import '../video_editor/video_editor_constants.dart';
import '../video_editor/video_editor_model.dart';
import '../video_editor/video_editor_painters.dart';
import '../../service/app_settings.dart';
import '../../service/export_service_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Progress state shared with the dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressInfo {
  final double value; // 0.0–1.0
  final Duration? eta;
  const _ProgressInfo(this.value, this.eta);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data classes
// ─────────────────────────────────────────────────────────────────────────────

class _ResolutionOption {
  final String label;
  final String sublabel;
  final int width;
  final int height;
  const _ResolutionOption(this.label, this.sublabel, this.width, this.height);
}

class _FormatOption {
  final String label;
  final String ext;
  // null = libx264, otherwise explicit codec
  final String? videoCodec;
  final String? audioCodec; // null = aac
  final bool faststart;
  const _FormatOption(this.label, this.ext,
      {this.videoCodec, this.audioCodec, this.faststart = false});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class ExportSettingsScreen extends StatefulWidget {
  final List<TimelineTrack> tracks;
  const ExportSettingsScreen({super.key, required this.tracks});

  @override
  State<ExportSettingsScreen> createState() => _ExportSettingsScreenState();
}

class _ExportSettingsScreenState extends State<ExportSettingsScreen> {
  // ── Options ──────────────────────────────────────────────────────────────
  static const _resolutions = [
    _ResolutionOption('480p', 'SD', 854, 480),
    _ResolutionOption('720p', 'HD', 1280, 720),
    _ResolutionOption('1080p', 'FHD', 1920, 1080),
    _ResolutionOption('2K', '2K', 2560, 1440),
    _ResolutionOption('4K', '4K', 3840, 2160),
  ];

  static const _frameRates = [24, 25, 30, 50, 60];

  // (display name, description, CRF for x264 / VP9)
  static const _qualities = [
    ('Recommended', 'Balanced size &\nquality', 23),
    ('High', 'Crisp detail, larger\nfile', 18),
    ('Ultra', 'Maximum quality', 14),
  ];

  static const _formats = [
    _FormatOption('MP4', 'mp4', faststart: true),
    _FormatOption('MOV', 'mov', faststart: true),
    _FormatOption('MKV', 'mkv'),
    _FormatOption('WebM', 'webm',
        videoCodec: 'libvpx-vp9', audioCodec: 'libopus'),
    _FormatOption('GIF', 'gif', videoCodec: 'gif', audioCodec: ''),
  ];

  // ── State ─────────────────────────────────────────────────────────────────
  late int _selectedResolution; // from AppSettings
  late int _selectedFrameRate;  // from AppSettings
  int _selectedQuality = 0;    // Recommended
  int _selectedFormat = 0;     // MP4
  bool _isExporting = false;

  // ── Scroll ────────────────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();
  bool _showScrollHint = false;

  // ── Design ────────────────────────────────────────────────────────────────
  static const _red = Color(0xFFE53935);
  static const _chipUnselected = Color(0xFF2B2B2B);
  static const _sectionLabel = TextStyle(
    color: Color(0xFF888888),
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // ── Estimated size ────────────────────────────────────────────────────────
  double get _estimatedSizeMB {
    if (widget.tracks.isEmpty) return 0;
    final totalSecs = _totalSecs;
    if (totalSecs <= 0) return 0;
    final heightPx = _resolutions[_selectedResolution].height;
    final fmt = _formats[_selectedFormat];
    if (fmt.ext == 'gif') return heightPx * 0.03 * totalSecs; // rough GIF estimate
    final baseMbps = _baseBitrate(heightPx);
    final qualityMult = [1.0, 1.6, 2.5][_selectedQuality];
    final fpsMult = _frameRates[_selectedFrameRate] / 30.0;
    final webmMult = fmt.ext == 'webm' ? 0.7 : 1.0; // VP9 is ~30% smaller
    return baseMbps * qualityMult * fpsMult * webmMult * totalSecs / 8;
  }

  double get _totalSecs => widget.tracks
      .map((t) => t.endTime)
      .fold(Duration.zero, (a, b) => a > b ? a : b)
      .inMicroseconds /
      1e6;

  double _baseBitrate(int height) {
    if (height <= 480) return 2.0;
    if (height <= 720) return 5.0;
    if (height <= 1080) return 10.0;
    if (height <= 1440) return 20.0;
    return 50.0;
  }

  String _formatSize(double mb) {
    if (mb < 1000) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Pre-select the resolution and fps from Settings defaults.
    final s = AppSettings.instance;
    _selectedResolution = s.defaultResolutionIndex;
    _selectedFrameRate  = s.defaultFpsIndex;
    _scrollCtrl.addListener(_onScroll);
    // Show hint after first frame once we know scroll extent
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 8;
    if (atBottom != !_showScrollHint) {
      setState(() => _showScrollHint = !atBottom);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResolutionSection(),
                        _buildDivider(),
                        _buildFrameRateSection(),
                        _buildDivider(),
                        _buildQualitySection(),
                        _buildDivider(),
                        _buildFormatSection(),
                        _buildDivider(),
                        _buildSummarySection(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  // Scroll-to-bottom hint
                  if (_showScrollHint)
                    Positioned(
                      bottom: 10,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _scrollCtrl.animateTo(
                          _scrollCtrl.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6D00),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Export button pinned at the bottom, always visible
            _buildExportButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white, size: 26),
            ),
          ),
          const Text(
            'Export',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      const Divider(color: Color(0xFF252525), height: 1, thickness: 1);

  // ── Resolution ────────────────────────────────────────────────────────────

  Widget _buildResolutionSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resolution', style: _sectionLabel),
          const SizedBox(height: 14),
          Row(
            children: List.generate(_resolutions.length, (i) {
              final res = _resolutions[i];
              final sel = i == _selectedResolution;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedResolution = i),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i < _resolutions.length - 1 ? 7 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2D0808) : _chipUnselected,
                      borderRadius: BorderRadius.circular(12),
                      border: sel ? Border.all(color: _red, width: 2) : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(res.label,
                            style: TextStyle(
                                color: sel ? _red : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(res.sublabel,
                            style: const TextStyle(
                                color: Color(0xFF777777), fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Frame Rate ────────────────────────────────────────────────────────────

  Widget _buildFrameRateSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: Text('Frame Rate', style: _sectionLabel)),
          const SizedBox(height: 14),
          Row(
            children: List.generate(_frameRates.length, (i) {
              final fps = _frameRates[i];
              final sel = i == _selectedFrameRate;
              // GIF is capped at 30fps visually
              final disabled =
                  _formats[_selectedFormat].ext == 'gif' && fps > 30;
              return Expanded(
                child: GestureDetector(
                  onTap: disabled
                      ? null
                      : () => setState(() => _selectedFrameRate = i),
                  child: Opacity(
                    opacity: disabled ? 0.35 : 1,
                    child: Container(
                      margin: EdgeInsets.only(
                          right: i < _frameRates.length - 1 ? 7 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF2D0808) : _chipUnselected,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            sel ? Border.all(color: _red, width: 2) : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$fps',
                              style: TextStyle(
                                  color: sel ? _red : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('fps',
                              style: TextStyle(
                                  color: sel
                                      ? _red.withValues(alpha: 0.7)
                                      : const Color(0xFF777777),
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Quality ───────────────────────────────────────────────────────────────

  Widget _buildQualitySection() {
    final isGif = _formats[_selectedFormat].ext == 'gif';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quality', style: _sectionLabel),
          const SizedBox(height: 14),
          if (isGif)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _chipUnselected,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF888888), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GIF uses a fixed 256-colour palette — quality and size depend primarily on resolution.',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(_qualities.length, (i) {
                  final (name, desc, _) = _qualities[i];
                  final sel = i == _selectedQuality;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedQuality = i),
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i < _qualities.length - 1 ? 7 : 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF2D0808)
                              : _chipUnselected,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              sel ? Border.all(color: _red, width: 2) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              sel
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: sel ? _red : const Color(0xFF555555),
                              size: 20,
                            ),
                            const SizedBox(height: 8),
                            Text(name,
                                style: TextStyle(
                                    color: sel ? _red : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(desc,
                                style: const TextStyle(
                                    color: Color(0xFF777777), fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ── Format ────────────────────────────────────────────────────────────────

  Widget _buildFormatSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: Text('Format', style: _sectionLabel)),
          const SizedBox(height: 14),
          Row(
            children: List.generate(_formats.length, (i) {
              final fmt = _formats[i];
              final sel = i == _selectedFormat;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedFormat = i),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i < _formats.length - 1 ? 7 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2D0808) : _chipUnselected,
                      borderRadius: BorderRadius.circular(12),
                      border: sel ? Border.all(color: _red, width: 2) : null,
                    ),
                    child: Center(
                      child: Text(
                        fmt.label,
                        style: TextStyle(
                            color: sel ? _red : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  Widget _buildSummarySection() {
    final res = _resolutions[_selectedResolution];
    final fps = _frameRates[_selectedFrameRate];
    final (qualityName, _, _) = _qualities[_selectedQuality];
    final fmt = _formats[_selectedFormat];
    final isGif = fmt.ext == 'gif';
    final size = _estimatedSizeMB;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _summaryItem('Resolution', res.label,
                      align: CrossAxisAlignment.start)),
              Expanded(
                  child: _summaryItem('Frame rate', '$fps fps',
                      align: CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _summaryItem(
                      'Quality', isGif ? 'Palette' : qualityName,
                      align: CrossAxisAlignment.start)),
              Expanded(
                  child: _summaryItem('Format', fmt.label,
                      align: CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF252525), height: 1),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Estimated size',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
              const Spacer(),
              Text(_formatSize(size),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value,
      {required CrossAxisAlignment align}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Export button ─────────────────────────────────────────────────────────

  Widget _buildExportButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: GestureDetector(
        onTap: _isExporting ? null : _startExport,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6D00), Color(0xFFE53935)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Center(
            child: _isExporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text('Export',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Export logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startExport() async {
    setState(() => _isExporting = true);
    if (!mounted) return;

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final totalSecs = _totalSecs;

    // Start Android foreground service so FFmpeg survives app-backgrounding.
    // Fire-and-forget: the service will be running by the time FFmpeg starts.
    ExportServiceManager.start();

    // Progress notifier — updated from the FFmpegKit statistics callback
    final progressNotifier = ValueNotifier<_ProgressInfo>(const _ProgressInfo(0, null));

    // Show reactive progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(notifier: progressNotifier),
    );

    try {
      final videoTracks = widget.tracks.where((t) => t.isVideo).toList();

      final dir = await getTemporaryDirectory();
      final fmt = _formats[_selectedFormat];
      final outputPath = p.join(
          dir.path, 'export_${DateTime.now().millisecondsSinceEpoch}.${fmt.ext}');

      // Probe which video files have audio streams
      final Map<String, bool> hasAudio = {};
      for (final t in videoTracks) {
        final session = await FFprobeKit.getMediaInformation(t.filePath);
        final streams = session.getMediaInformation()?.getStreams() ?? [];
        hasAudio[t.id] = streams.any((s) => s.getType() == 'audio');
      }

      final res = _resolutions[_selectedResolution];
      final fps = _frameRates[_selectedFrameRate];
      final (_, _, crf) = _qualities[_selectedQuality];

      String command;
      if (fmt.ext == 'gif') {
        command = _buildGifCommand(
          outputPath: outputPath,
          width: res.width,
          height: res.height,
          frameRate: fps.clamp(1, 30),
          videoTracks: videoTracks,
        );
      } else {
        command = await _buildExportCommand(
          outputPath: outputPath,
          hasAudio: hasAudio,
          width: res.width,
          height: res.height,
          frameRate: fps,
          crf: crf,
          fmt: fmt,
          allTracks: widget.tracks,
        );
      }

      // Run export asynchronously with statistics callback for progress
      final completer = Completer<ReturnCode?>();
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final rc = await session.getReturnCode();
          completer.complete(rc);
        },
        null,
        (stats) {
          final processedMs = stats.getTime().toDouble();
          final speed = stats.getSpeed();
          final progress =
              (processedMs / (totalSecs * 1000)).clamp(0.0, 1.0);
          Duration? eta;
          if (speed > 0 && progress > 0.01 && progress < 0.99) {
            final remainingSecs =
                (totalSecs - processedMs / 1000) / speed;
            if (remainingSecs > 0) {
              eta = Duration(seconds: remainingSecs.ceil());
            }
          }
          progressNotifier.value = _ProgressInfo(progress, eta);
          // Keep the foreground-service notification in sync.
          ExportServiceManager.updateProgress(progress);
        },
      );

      final rc = await completer.future;

      if (!mounted) return;
      nav.pop(); // close progress dialog — do this BEFORE disposing notifier
      progressNotifier.dispose();
      await ExportServiceManager.stop();

      if (ReturnCode.isSuccess(rc)) {
        // Verify the file was actually written (non-zero size)
        final fileSize = File(outputPath).statSync().size;
        if (fileSize == 0) {
          setState(() => _isExporting = false);
          messenger.showSnackBar(const SnackBar(
              content: Text('Export produced an empty file — check FFmpeg logs',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red));
          return;
        }

        nav.pushReplacement(MaterialPageRoute(
          builder: (_) => ExportResultScreen(videoPath: outputPath),
        ));
      } else {
        setState(() => _isExporting = false);
        messenger.showSnackBar(const SnackBar(
            content: Text('Export failed',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        nav.pop();
        setState(() => _isExporting = false);
        messenger.showSnackBar(SnackBar(
            content: Text('Export error: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red));
      }
      progressNotifier.dispose();
      await ExportServiceManager.stop();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Text PNG renderer (off-screen, no widget tree required)
  // ─────────────────────────────────────────────────────────────────────────

  /// Renders a text track to a transparent PNG file and returns its absolute
  /// path, or null if rendering fails.
  ///
  /// Handles both **curved** paths (via [VeCurvedTextPainter]) and **straight**
  /// text that carries effects that drawtext cannot reproduce: rotation, glow,
  /// gradient, and outline with glow.  The resulting PNG is composited onto the
  /// video via FFmpeg's overlay filter.
  Future<String?> _renderTextToPng(TimelineTrack t, {required int exportWidth, required int exportHeight}) async {
    try {
      // Scale factor: maps the 16:9 reference canvas (kVeRefCanvasH × 16/9 = 320 wide)
      // to the export video width so that text size is pixel-perfect regardless of
      // the video's aspect ratio (landscape, portrait, square, etc.).
      // Using width (not height) ensures the text occupies the same fraction of the
      // video frame horizontally, matching the editor's 16:9 preview reference.
      final double refCanvasW = kVeRefCanvasH * (16.0 / 9.0); // 320.0
      final double canvasScale = exportWidth / refCanvasW;

      // ── Apply text case transform ─────────────────────────────────────
      final rawText = t.textContent.isEmpty ? 'Text' : t.textContent;
      final displayText = switch (t.textCaseIndex) {
        1 => rawText.toUpperCase(),
        2 => rawText.toLowerCase(),
        3 => rawText.splitMapJoin(
              RegExp(r'\S+'),
              onMatch: (m) {
                final w = m[0]!;
                return w[0].toUpperCase() + w.substring(1).toLowerCase();
              },
              onNonMatch: (s) => s,
            ),
        _ => rawText,
      };

      // ── Build shadow / glow list ──────────────────────────────────────
      final allShadows = _buildTextShadows(t);

      // ── Text decoration ───────────────────────────────────────────────
      final TextDecoration? decoration = (t.textUnderline && t.textStrikethrough)
          ? TextDecoration.combine(
              [TextDecoration.underline, TextDecoration.lineThrough])
          : t.textUnderline
              ? TextDecoration.underline
              : t.textStrikethrough
                  ? TextDecoration.lineThrough
                  : null;

      // ── Text alignment ────────────────────────────────────────────────
      final align = switch (t.textAlignIndex) {
        0 => TextAlign.left,
        2 => TextAlign.right,
        _ => TextAlign.center,
      };

      // ── Build fill TextStyle ──────────────────────────────────────────
      final TextStyle fillStyle;
      if (t.textGradientEnabled) {
        // Gradient colour is baked via a Paint shader; canvas bounds computed
        // below and the shader rect is updated after size is known.
        fillStyle = TextStyle(
          fontSize:           t.fontSize,
          fontWeight:         t.textBold   ? FontWeight.bold   : FontWeight.normal,
          fontStyle:          t.textItalic ? FontStyle.italic  : FontStyle.normal,
          fontFamily:         t.fontFamily,
          letterSpacing:      t.letterSpacing,
          height:             t.lineHeight,
          decoration:         decoration,
          decorationColor:    t.textColor,
          decorationThickness: 2.0,
          shadows:            allShadows,
          color:              Colors.white, // placeholder; overridden by shader below
        );
      } else {
        fillStyle = TextStyle(
          fontSize:           t.fontSize,
          fontWeight:         t.textBold   ? FontWeight.bold   : FontWeight.normal,
          fontStyle:          t.textItalic ? FontStyle.italic  : FontStyle.normal,
          fontFamily:         t.fontFamily,
          color:              t.textColor,
          letterSpacing:      t.letterSpacing,
          height:             t.lineHeight,
          decoration:         decoration,
          decorationColor:    t.textColor,
          decorationThickness: 2.0,
          shadows:            allShadows,
        );
      }

      // ── Build outline TextStyle (null when no outline) ────────────────
      final TextStyle? outlineStyle = t.textOutlineWidth > 0.0
          ? TextStyle(
              fontSize:           t.fontSize,
              fontWeight:         t.textBold   ? FontWeight.bold   : FontWeight.normal,
              fontStyle:          t.textItalic ? FontStyle.italic  : FontStyle.normal,
              fontFamily:         t.fontFamily,
              letterSpacing:      t.letterSpacing,
              height:             t.lineHeight,
              decoration:         decoration,
              decorationColor:    t.textOutlineColor,
              decorationThickness: 2.0,
              foreground: Paint()
                ..style       = PaintingStyle.stroke
                ..strokeWidth = t.textOutlineWidth * 2
                ..strokeJoin  = StrokeJoin.round
                ..color       = t.textOutlineColor,
            )
          : null;

      // ── Compute canvas size ───────────────────────────────────────────
      // Padding accounts for outline bleed, glow spread, and shadow offset.
      final effectPad = (t.textOutlineWidth +
              t.textGlowRadius * 1.6 +
              t.shadowRadius +
              max(t.shadowOffsetX.abs(), t.shadowOffsetY.abs()))
          .ceil()
          .toDouble() + 20.0;

      double canvasW, canvasH;
      Offset paintOrigin;   // top-left of straight text on canvas (pre-rotation)
      // Hoisted so both the measurement block and the drawing block can access them.
      double tw = 0, preW = 0, preH = 0;

      final isCurved = t.textPathCurve.abs() > 0.01;

      final padH = t.textPaddingH;
      final padV = t.textPaddingV;

      if (isCurved) {
        // Curved path: same heuristic as _buildTextWidget in the preview.
        // Expand by padding so any background box fits without clipping.
        canvasW = (t.fontSize * 0.65 * displayText.length.clamp(1, 60) + 80)
            .clamp(140.0, 900.0) + padH * 2;
        canvasH = t.fontSize * 4.0 + padV * 2;
        paintOrigin = Offset(padH, padV); // curved painter uses its own layout internally
      } else {
        // Straight text: measure via TextPainter then expand for padding + rotation.
        // Use unconstrained width to match the editor preview, where the Text widget
        // also has no explicit width constraint → text never wraps artificially.
        const refMaxW = double.infinity;
        final probe = TextPainter(
          text:          TextSpan(text: displayText, style: fillStyle),
          textDirection: TextDirection.ltr,
          textAlign:     align,
          maxLines:      null,
        )..layout(maxWidth: refMaxW);
        tw = probe.width;
        final th = probe.height;
        probe.dispose();

        // Pre-rotation rectangle including effect bleed and content padding
        preW = tw + effectPad * 2 + padH * 2;
        preH = th + effectPad * 2 + padV * 2;

        if (t.textRotation != 0.0) {
          final rad  = t.textRotation * pi / 180.0;
          final cosA = cos(rad).abs();
          final sinA = sin(rad).abs();
          // Bounding box of the rotated pre-rotation rectangle
          canvasW = preW * cosA + preH * sinA;
          canvasH = preW * sinA + preH * cosA;
        } else {
          canvasW = preW;
          canvasH = preH;
        }
        // Text is drawn at effectPad + padding offset (before any rotation transform)
        paintOrigin = Offset(effectPad + padH, effectPad + padV);
      }

      final size = Size(canvasW, canvasH);

      // ── Draw onto an off-screen canvas ────────────────────────────────
      // Scale the entire canvas by canvasScale so the output PNG is sized for
      // the actual export resolution (not preview logical pixels).
      final outW = canvasW * canvasScale;
      final outH = canvasH * canvasScale;
      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, outW, outH));
      canvas.scale(canvasScale, canvasScale);

      if (isCurved) {
        // Bake rotation around the curved canvas centre
        if (t.textRotation != 0.0) {
          canvas.translate(canvasW / 2, canvasH / 2);
          canvas.rotate(t.textRotation * pi / 180.0);
          canvas.translate(-canvasW / 2, -canvasH / 2);
        }
        // Background behind the curved text (fills the padded area)
        if (t.textBgOpacity > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, canvasW, canvasH),
              Radius.circular(t.textBgRadius),
            ),
            Paint()..color = t.textBgColor.withValues(alpha: t.textBgOpacity),
          );
        }
        // Translate by padding so the curved painter's coordinate origin shifts
        // into the padded area.
        canvas.translate(paintOrigin.dx, paintOrigin.dy);
        // For gradient on curved text, rebuild fillStyle with a real shader now
        // that we know the canvas size.
        final TextStyle resolvedFill = t.textGradientEnabled
            ? _gradientFillStyle(t, canvasW, canvasH, base: fillStyle)
            : fillStyle;
        VeCurvedTextPainter(
          text:         displayText,
          fillStyle:    resolvedFill,
          outlineStyle: outlineStyle,
          curve:        t.textPathCurve,
        ).paint(canvas, size);
      } else {
        // Bake rotation so the text centre stays at the bounding-box centre.
        // Pivot must be around the PRE-ROTATION text rect centre (preW/2, preH/2),
        // not the bounding-box centre (canvasW/2, canvasH/2).  The bounding box is
        // larger than the pre-rotation rect whenever rotation ≠ 0/180°, so using
        // the wrong pivot shifts the text off-centre in the PNG → wrong position in video.
        if (t.textRotation != 0.0) {
          canvas.translate(canvasW / 2, canvasH / 2);
          canvas.rotate(t.textRotation * pi / 180.0);
          canvas.translate(-preW / 2, -preH / 2);
        }

        // Background RRect behind the text (drawn in pre-rotation space).
        // After the pivot fix, canvas drawing coords are in the preW×preH rect,
        // so use preW/preH — not canvasW/canvasH which are the bounding-box dims.
        if (t.textBgOpacity > 0) {
          final bgW = preW - effectPad * 2;
          final bgH = preH - effectPad * 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(effectPad, effectPad, bgW, bgH),
              Radius.circular(t.textBgRadius),
            ),
            Paint()..color = t.textBgColor.withValues(alpha: t.textBgOpacity),
          );
        }

        // Rebuild gradient fill style in pre-rotation space (drawing coords = preW×preH).
        final TextStyle resolvedFill = t.textGradientEnabled
            ? _gradientFillStyle(t, preW, preH, base: fillStyle)
            : fillStyle;

        // Text layout width = natural probe width (tw), not derived from canvasW.
        // Using canvasW is wrong when text is rotated: rotation swaps canvasW/canvasH,
        // making canvasW equal to the text HEIGHT which would cause artificial wrapping.
        final layoutW = tw;

        // Draw outline layer first (so fill paints on top)
        if (outlineStyle != null) {
          final tp = TextPainter(
            text:          TextSpan(text: displayText, style: outlineStyle),
            textDirection: TextDirection.ltr,
            textAlign:     align,
            maxLines:      null,
          )..layout(maxWidth: layoutW);
          tp.paint(canvas, paintOrigin);
          tp.dispose();
        }

        // Draw fill layer
        final tp = TextPainter(
          text:          TextSpan(text: displayText, style: resolvedFill),
          textDirection: TextDirection.ltr,
          textAlign:     align,
          maxLines:      null,
        )..layout(maxWidth: layoutW);
        tp.paint(canvas, paintOrigin);
        tp.dispose();
      }

      // ── Encode to PNG and save to temp file ───────────────────────────
      final picture  = recorder.endRecording();
      final image    = await picture.toImage(outW.round(), outH.round());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose(); // release native raster memory immediately
      if (byteData == null) return null;

      final tmpDir = await getTemporaryDirectory();
      final file   = File(p.join(tmpDir.path, 'text_png_${t.id}.png'));
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file.path;
    } catch (e) {
      debugPrint('_renderTextToPng error: $e');
      return null;
    }
  }

  /// Renders the mask shape for [t] as a grayscale PNG at [w]×[h] pixels.
  /// White = visible area, Black = hidden area (inverted when [t.maskInverted]).
  /// Used by FFmpeg's alphamerge filter to apply the mask during export.
  Future<String?> _renderMaskToPng(TimelineTrack t, int w, int h) async {
    if (!t.hasMask) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

      // Build the shape path centred in the canvas.
      final short = min(w, h).toDouble() * t.maskScale;
      final cx    = w / 2.0;
      final cy    = h / 2.0;
      final Rect shapeRect;
      if (t.maskShapeIndex == 2) {
        // Rectangle: stretch to preserve clip aspect ratio.
        shapeRect = Rect.fromCenter(
          center: Offset(cx, cy),
          width:  w * t.maskScale,
          height: h * t.maskScale,
        );
      } else {
        // All other shapes: keep square based on shorter side.
        shapeRect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: short, height: short,
        );
      }

      final shapePath = VeMaskClipper.buildShapePath(shapeRect, t.maskShapeIndex);

      // Feather sigma (pixels).
      final sigma = t.maskFeather > 0
          ? t.maskFeather * min(w, h) * 0.08
          : 0.0;
      final MaskFilter? blur =
          sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sigma) : null;

      if (t.maskInverted) {
        // White background → show everywhere; black shape → hide shape area.
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white,
        );
        canvas.drawPath(
          shapePath,
          Paint()..color = Colors.black..maskFilter = blur,
        );
      } else {
        // Black background → hide everywhere; white shape → show shape area.
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.black,
        );
        canvas.drawPath(
          shapePath,
          Paint()..color = Colors.white..maskFilter = blur,
        );
      }

      final picture  = recorder.endRecording();
      final image    = await picture.toImage(w, h);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose(); // release native raster memory immediately
      if (byteData == null) return null;

      final tmpDir = await getTemporaryDirectory();
      final file   = File(p.join(tmpDir.path, 'mask_png_${t.id}.png'));
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file.path;
    } catch (e) {
      debugPrint('_renderMaskToPng error: $e');
      return null;
    }
  }

  /// Rebuilds [base] with a gradient [Paint.shader] covering [w]×[h].
  TextStyle _gradientFillStyle(
      TimelineTrack t, double w, double h, {required TextStyle base}) {
    final rad = t.textGradientAngle * pi / 180.0;
    return base.copyWith(
      color: null,
      foreground: Paint()
        ..shader = LinearGradient(
          begin: Alignment(-cos(rad), -sin(rad)),
          end:   Alignment( cos(rad),  sin(rad)),
          colors: [t.textGradientColor1, t.textGradientColor2],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  /// Returns combined drop-shadow + glow [Shadow] list for [t], or null when
  /// neither effect is active.
  List<Shadow>? _buildTextShadows(TimelineTrack t) {
    final list = <Shadow>[];
    if (t.shadowRadius > 0 && t.shadowOpacity > 0) {
      list.add(Shadow(
        color:      t.shadowColor.withValues(alpha: t.shadowOpacity),
        blurRadius: t.shadowRadius,
        offset:     Offset(t.shadowOffsetX, t.shadowOffsetY),
      ));
    }
    if (t.textGlowRadius > 0) {
      list.addAll([
        Shadow(color: t.textGlowColor.withValues(alpha: 0.9),
               blurRadius: t.textGlowRadius * 0.4),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.7),
               blurRadius: t.textGlowRadius * 0.7),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.5),
               blurRadius: t.textGlowRadius),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.25),
               blurRadius: t.textGlowRadius * 1.6),
      ]);
    }
    return list.isEmpty ? null : list;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FFmpeg command builders
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _buildExportCommand({
    required String outputPath,
    required Map<String, bool> hasAudio,
    required int width,
    required int height,
    required int frameRate,
    required int crf,
    required _FormatOption fmt,
    required List<TimelineTrack> allTracks,
  }) async {
    final totalSecs = _totalSecs;
    final isWebM = fmt.ext == 'webm';

    final inputs = StringBuffer();
    final filters = <String>[];
    final visualLabels = <String>[];
    final visualTracks = <TimelineTrack>[];
    final audioLabels = <String>[];
    final textTracks     = <TimelineTrack>[]; // straight text → drawtext
    final curvedTracks   = <TimelineTrack>[]; // curved text → PNG overlay

    // ── Pre-render mask PNGs (one per masked video/image track) ──────────────
    // Key: trackId  Value: PNG file path
    final maskPngPaths = <String, String>{};
    for (final t in allTracks) {
      if (!t.hasMask || (!t.isVideo && !t.isImage)) continue;
      final isOv = t.isImage || (t.isVideo && t.overlayScale < 0.999);
      final mW   = isOv ? (width  * t.overlayScale).round() : width;
      final mH   = isOv ? (height * t.overlayScale).round() : height;
      final mp   = await _renderMaskToPng(t, mW, mH);
      if (mp != null) maskPngPaths[t.id] = mp;
    }

    // ── Pass 1: VidStab motion analysis (one per stabilized video track) ─────
    // Generates a .trf transformation file per track that pass-2 (export) uses.
    final stabTrfPaths = <String, String>{}; // trackId → trf path
    final tmpDir = await getTemporaryDirectory();
    for (final t in allTracks) {
      if (!t.isStabilized || !t.isVideo) continue;
      debugPrint('VidStab pass-1: analysing motion for ${t.title}…');
      final trfPath = '${tmpDir.path}/export_stab_${t.id}.trf';
      final pass1 = await FFmpegKit.execute(
        '-y -i "${t.filePath}" '
        '-vf "vidstabdetect=stepsize=6:shakiness=8:accuracy=9:result=$trfPath" '
        '-f null /dev/null',
      );
      if (ReturnCode.isSuccess(await pass1.getReturnCode())) {
        stabTrfPaths[t.id] = trfPath;
      } else {
        debugPrint('VidStab pass-1 failed for ${t.title} — falling back to deshake');
      }
    }

    // Input 0: black background
    inputs.write(
        '-f lavfi -i "color=c=black:s=${width}x$height:r=$frameRate:d=$totalSecs" ');
    int idx = 1;
    int vIdx = 0; // visual (video/image) track counter
    int aIdx = 0; // audio-only track counter

    // ── Process all tracks in timeline order ──────────────────────────────
    for (final t in allTracks) {
      if (t.isText) {
        // Always use the PNG pre-render path for all text overlays.
        // drawtext requires a font file path that is unavailable on Android/iOS,
        // causing FFmpeg to fail. The PNG renderer handles every TextStyle
        // property correctly and produces pixel-perfect output on mobile.
        curvedTracks.add(t);
        continue;
      }
      if (t.isAudio) {
        // Audio-only track
        final ts = t.trimStart.inMicroseconds / 1e6;
        final rawDur = t.duration - t.trimStart - t.trimEnd;
        final rawDurSecs = rawDur.inMicroseconds / 1e6;
        final so = t.startOffset.inMicroseconds / 1e6;
        final effectiveDurSecs = rawDurSecs / t.speed;

        inputs.write('-ss $ts -t $rawDurSecs -i "${t.filePath}" ');

        final afade = StringBuffer(
            'asetpts=PTS-STARTPTS+$so/TB,${_buildAtempo(t.speed)},volume=${t.volume.toStringAsFixed(3)}');
        final vf = _buildVoiceFilter(t.voiceEffectIndex);
        if (vf.isNotEmpty) afade.write(',$vf');
        if (t.fadeInSecs > 0) {
          afade.write(
              ',afade=t=in:st=${so.toStringAsFixed(3)}:d=${t.fadeInSecs.toStringAsFixed(3)}');
        }
        if (t.fadeOutSecs > 0) {
          final fadeOutStart =
              (so + effectiveDurSecs - t.fadeOutSecs).clamp(so, so + effectiveDurSecs);
          afade.write(
              ',afade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${t.fadeOutSecs.toStringAsFixed(3)}');
        }
        filters.add('[$idx:a]${afade.toString()}[a$aIdx]');
        audioLabels.add('a$aIdx');
        aIdx++;
        idx++;
      } else if (t.isVideo) {
        final ts = t.trimStart.inMicroseconds / 1e6;
        final rawDur = t.duration - t.trimStart - t.trimEnd;
        final rawDurSecs = rawDur.inMicroseconds / 1e6;
        final so = t.startOffset.inMicroseconds / 1e6;
        final spd = t.speed.toStringAsFixed(4);
        final effectiveDurSecs = rawDurSecs / t.speed;
        // overlayScale < 1 means it should be shown as a positioned overlay.
        final isOverlay = t.overlayScale < 0.999;

        inputs.write('-ss $ts -t $rawDurSecs -i "${t.filePath}" ');

        // Mask input immediately after video input (so it is at idx+1).
        final hasMaskV = maskPngPaths.containsKey(t.id);
        if (hasMaskV) {
          inputs.write('-loop 1 -framerate $frameRate -t $totalSecs -i "${maskPngPaths[t.id]!}" ');
        }

        final vfilterParts = <String>[];
        // Reverse must be the very first filter (buffers and flips frame order).
        if (t.playBackwards) vfilterParts.add('reverse');
        final rot = _rotationFilter(t.rotation);
        if (rot.isNotEmpty) vfilterParts.add(rot);
        if (t.mirrorH) vfilterParts.add('hflip');

        // Crop filter (before scale so coordinates are in source pixels)
        if (t.hasCrop) {
          if (t.cropRotation != 0.0) {
            final rad = (t.cropRotation * 3.14159265 / 180.0).toStringAsFixed(6);
            vfilterParts.add('rotate=$rad:fillcolor=black:ow=rotw($rad):oh=roth($rad)');
          }
          final cx = t.cropX.toStringAsFixed(6);
          final cy = t.cropY.toStringAsFixed(6);
          final cw = t.cropW.toStringAsFixed(6);
          final ch = t.cropH.toStringAsFixed(6);
          vfilterParts.add('crop=iw*$cw:ih*$ch:iw*$cx:ih*$cy');
        }

        if (isOverlay) {
          final maxW = (width * t.overlayScale).round();
          final maxH = (height * t.overlayScale).round();
          vfilterParts.addAll([
            'setpts=(PTS-STARTPTS)/$spd+$so/TB',
            'scale=$maxW:$maxH:force_original_aspect_ratio=decrease',
            'format=yuv420p',
          ]);
        } else {
          vfilterParts.addAll([
            'setpts=(PTS-STARTPTS)/$spd+$so/TB',
            'scale=$width:$height:force_original_aspect_ratio=decrease',
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2',
            'format=yuv420p',
          ]);
        }

        // ── Visual filters ──────────────────────────────────────────────
        _addVisualFilters(vfilterParts, t, stabTrfPaths);

        if (t.fadeInSecs > 0) {
          vfilterParts.add(
              'fade=t=in:st=${so.toStringAsFixed(3)}:d=${t.fadeInSecs.toStringAsFixed(3)}:color=black');
        }
        if (t.fadeOutSecs > 0) {
          final fadeOutStart =
              (so + effectiveDurSecs - t.fadeOutSecs).clamp(so, so + effectiveDurSecs);
          vfilterParts.add(
              'fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${t.fadeOutSecs.toStringAsFixed(3)}:color=black');
        }
        final hasAlpha = t.opacity < 0.999;
        final label = 'vis$vIdx';

        if (hasMaskV) {
          // Mask is at idx+1 (added to inputs above).
          final maskIdx  = idx + 1;
          final preLabel = '${label}pm';
          // Convert to yuva420p for alphamerge (opacity applied after alphamerge).
          vfilterParts.add('format=yuva420p');
          filters.add('[$idx:v]${vfilterParts.join(',')}[$preLabel]');
          // alphamerge uses mask luminance as new alpha; then scale by opacity.
          final opacStr = hasAlpha ? ',colorchannelmixer=aa=${t.opacity.toStringAsFixed(3)}' : '';
          filters.add('[$preLabel][$maskIdx:v]alphamerge$opacStr[$label]');
        } else {
          if (hasAlpha) {
            vfilterParts.add('format=yuva420p');
            vfilterParts.add('colorchannelmixer=aa=${t.opacity.toStringAsFixed(3)}');
          }
          filters.add('[$idx:v]${vfilterParts.join(',')}[$label]');
        }
        visualLabels.add(label);
        visualTracks.add(t);

        // Audio from video file
        if (hasAudio[t.id] == true && t.volume > 0) {
          // areverse must come first (buffers and flips the audio segment).
          final afade = StringBuffer(t.playBackwards ? 'areverse,' : '');
          afade.write(
              'asetpts=PTS-STARTPTS+$so/TB,${_buildAtempo(t.speed)},volume=${t.volume.toStringAsFixed(3)}');
          final vf = _buildVoiceFilter(t.voiceEffectIndex);
          if (vf.isNotEmpty) afade.write(',$vf');
          if (t.fadeInSecs > 0) {
            afade.write(
                ',afade=t=in:st=${so.toStringAsFixed(3)}:d=${t.fadeInSecs.toStringAsFixed(3)}');
          }
          if (t.fadeOutSecs > 0) {
            final fadeOutStart =
                (so + effectiveDurSecs - t.fadeOutSecs).clamp(so, so + effectiveDurSecs);
            afade.write(
                ',afade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${t.fadeOutSecs.toStringAsFixed(3)}');
          }
          filters.add('[$idx:a]${afade.toString()}[va$vIdx]');
          audioLabels.add('va$vIdx');
        }

        if (hasMaskV) idx++; // extra input for the mask PNG
        idx++;
        vIdx++;
      } else if (t.isImage) {
        final so = t.startOffset.inMicroseconds / 1e6;
        final displayDurSecs = t.effectiveDuration.inMicroseconds / 1e6;

        inputs.write('-loop 1 -framerate $frameRate -t $displayDurSecs -i "${t.filePath}" ');

        // Mask input immediately after image input (so it is at idx+1).
        final hasMaskI = maskPngPaths.containsKey(t.id);
        if (hasMaskI) {
          inputs.write('-loop 1 -framerate $frameRate -t $totalSecs -i "${maskPngPaths[t.id]!}" ');
        }

        final vfilterParts = <String>[];
        final imgRot = _rotationFilter(t.rotation);
        if (imgRot.isNotEmpty) vfilterParts.add(imgRot);
        if (t.mirrorH) vfilterParts.add('hflip');

        // Crop filter (before scale)
        if (t.hasCrop) {
          if (t.cropRotation != 0.0) {
            final rad = (t.cropRotation * 3.14159265 / 180.0).toStringAsFixed(6);
            vfilterParts.add('rotate=$rad:fillcolor=black:ow=rotw($rad):oh=roth($rad)');
          }
          final cx = t.cropX.toStringAsFixed(6);
          final cy = t.cropY.toStringAsFixed(6);
          final cw = t.cropW.toStringAsFixed(6);
          final ch = t.cropH.toStringAsFixed(6);
          vfilterParts.add('crop=iw*$cw:ih*$ch:iw*$cx:ih*$cy');
        }

        final maxW = (width * t.overlayScale).round();
        final maxH = (height * t.overlayScale).round();
        vfilterParts.addAll([
          'setpts=PTS-STARTPTS+$so/TB',
          'scale=$maxW:$maxH:force_original_aspect_ratio=decrease',
          'format=yuv420p',
        ]);

        // ── Visual filters ──────────────────────────────────────────────
        _addVisualFilters(vfilterParts, t, stabTrfPaths);

        if (t.fadeInSecs > 0) {
          vfilterParts.add(
              'fade=t=in:st=${so.toStringAsFixed(3)}:d=${t.fadeInSecs.toStringAsFixed(3)}:color=black');
        }
        if (t.fadeOutSecs > 0) {
          final fadeOutStart =
              (so + displayDurSecs - t.fadeOutSecs).clamp(so, so + displayDurSecs);
          vfilterParts.add(
              'fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${t.fadeOutSecs.toStringAsFixed(3)}:color=black');
        }
        final hasAlphaImg = t.opacity < 0.999;
        final label = 'vis$vIdx';

        if (hasMaskI) {
          final maskIdx  = idx + 1;
          final preLabel = '${label}pm';
          vfilterParts.add('format=yuva420p');
          filters.add('[$idx:v]${vfilterParts.join(',')}[$preLabel]');
          final opacStr = hasAlphaImg ? ',colorchannelmixer=aa=${t.opacity.toStringAsFixed(3)}' : '';
          filters.add('[$preLabel][$maskIdx:v]alphamerge$opacStr[$label]');
          idx++; // extra input for the mask PNG
        } else {
          if (hasAlphaImg) {
            vfilterParts.add('format=yuva420p');
            vfilterParts.add('colorchannelmixer=aa=${t.opacity.toStringAsFixed(3)}');
          }
          filters.add('[$idx:v]${vfilterParts.join(',')}[$label]');
        }
        visualLabels.add(label);
        visualTracks.add(t);

        idx++;
        vIdx++;
      }
    }

    // ── Visual overlay chain (timeline order) ────────────────────────────
    // Each track overlays on top of the previous in the exact order they
    // appear in the timeline (first track = bottom layer, last = top layer).
    if (visualLabels.isEmpty) {
      filters.add('[0:v]copy[vout]');
    } else {
      var base = '0:v';
      for (int i = 0; i < visualLabels.length; i++) {
        final out = i == visualLabels.length - 1 ? 'vout' : 'vl$i';
        final track = visualTracks[i];
        final hasAlpha = track.opacity < 0.999 || track.chromakeyEnabled || track.hasMask;
        final isFullCanvas = track.isVideo && track.overlayScale >= 0.999;

        if (isFullCanvas) {
          // Full-canvas video: overlay at 0,0 (padded to canvas size).
          if (hasAlpha) {
            filters.add(
                '[$base][${visualLabels[i]}]overlay=format=auto:eof_action=pass[$out]');
          } else {
            filters.add(
                '[$base][${visualLabels[i]}]overlay=eof_action=pass[$out]');
          }
        } else {
          // Positioned overlay: center + overlayX/Y offset.
          // W,H = canvas size; w,h = overlay clip size (set by scale filter above).
          final ox = track.overlayX.toStringAsFixed(4);
          final oy = track.overlayY.toStringAsFixed(4);
          final fmtStr = hasAlpha ? ':format=auto' : '';

          if (track.hasShadow) {
            // ── Drop shadow / glow ──────────────────────────────────────────
            // 1. Split the overlay into original + shadow source
            // 2. Colorize shadow source to shadow color, blur it
            // 3. Composite shadow (at offset), then original on top
            final lbl = visualLabels[i];
            final origLbl = '${lbl}so';
            final shadSrcLbl = '${lbl}ss';
            final shadOutLbl = '${lbl}sh';
            final tmpOut = '${lbl}t';

            final sc = track.shadowColor;
            // r/g/b are 0-1 in Flutter 3.27+; geq expects 0-255
            final r = (sc.r * 255).round().toString();
            final g = (sc.g * 255).round().toString();
            final b = (sc.b * 255).round().toString();
            final sigmaStr = track.shadowRadius.toStringAsFixed(2);
            final opacStr = track.shadowOpacity.toStringAsFixed(3);
            final soxStr = track.shadowOffsetX.toStringAsFixed(1);
            final soyStr = track.shadowOffsetY.toStringAsFixed(1);

            // Split track into original and shadow copy
            filters.add('[$lbl]split=2[$origLbl][$shadSrcLbl]');
            // Build shadow: colorize to shadow color + blur + apply opacity
            filters.add(
              '[$shadSrcLbl]format=yuva420p,'
              "geq=r='$r*alpha(X\\,Y)/255':g='$g*alpha(X\\,Y)/255':b='$b*alpha(X\\,Y)/255':a='alpha(X\\,Y)*$opacStr',"
              'gblur=sigma=$sigmaStr'
              '[$shadOutLbl]'
            );
            // Overlay shadow at offset position
            final shx = '(W-w)/2+$ox*W/2+$soxStr';
            final shy = '(H-h)/2+$oy*H/2+$soyStr';
            filters.add(
                '[$base][$shadOutLbl]overlay=x=$shx:y=$shy:format=auto:eof_action=pass[$tmpOut]');
            // Overlay original on top
            filters.add(
                '[$tmpOut][$origLbl]overlay=x=(W-w)/2+$ox*W/2:y=(H-h)/2+$oy*H/2:eof_action=pass$fmtStr[$out]');
          } else {
            filters.add(
                '[$base][${visualLabels[i]}]overlay=x=(W-w)/2+$ox*W/2:y=(H-h)/2+$oy*H/2:eof_action=pass$fmtStr[$out]');
          }
        }
        base = out;
      }
    }

    // ── Text overlay pipeline ─────────────────────────────────────────────
    // [textBase] flows through curved-text PNG overlays then drawtext overlays.
    // It starts at 'vout' (the composited visual output) and is relabelled at
    // each step.  The final label is stored in [textFinalLabel].
    var textBase = 'vout';

    // ── 1. Complex text overlays (PNG pre-rendered, then overlaid) ──────────
    // Effects that FFmpeg's drawtext cannot reproduce (curved arc, rotation,
    // glow, gradient, blend modes) are rendered off-screen to a transparent PNG
    // and then composited via an overlay or blend filter.
    //
    // FFmpeg blend-mode names matching Flutter's BlendMode order in _kTextBlendModes:
    const ffmpegBlendModes = [
      'normal',     // 0 Normal    → not used (simple overlay path)
      'multiply',   // 1 Multiply
      'screen',     // 2 Screen
      'overlay',    // 3 Overlay
      'darken',     // 4 Darken
      'lighten',    // 5 Lighten
      'dodge',      // 6 Dodge
      'burn',       // 7 Burn
      'hardlight',  // 8 Hard Light
      'softlight',  // 9 Soft Light
      'difference', // 10 Difference
      'exclusion',  // 11 Exclusion
      'addition',   // 12 Add (Plus)
    ];

    int ctIdx = 0;
    for (final t in curvedTracks) {
      final pngPath = await _renderTextToPng(t, exportWidth: width, exportHeight: height);
      if (pngPath == null) continue; // render failed — skip silently

      final displayDurSecs = t.effectiveDuration.inMicroseconds / 1e6;
      final so = t.startOffset.inMicroseconds / 1e6;
      final ox = t.overlayX.toStringAsFixed(4);
      final oy = t.overlayY.toStringAsFixed(4);

      // Looped static PNG input — active only for the track's duration
      inputs.write('-loop 1 -t ${displayDurSecs.toStringAsFixed(4)} -i "$pngPath" ');

      final filterParts = <String>[
        'format=yuva420p',                                   // keep alpha
        'setpts=PTS-STARTPTS+${so.toStringAsFixed(4)}/TB',  // shift to start time
      ];
      // Apply overlayScale — Flutter preview uses Transform.scale; FFmpeg must
      // explicitly scale the PNG to match.
      if ((t.overlayScale - 1.0).abs() > 0.005) {
        final sc = t.overlayScale.toStringAsFixed(4);
        filterParts.add('scale=iw*$sc:ih*$sc:flags=lanczos');
      }
      if (t.opacity < 0.999) {
        filterParts.add('colorchannelmixer=aa=${t.opacity.toStringAsFixed(3)}');
      }

      final ctLabel  = 'ct$ctIdx';
      final ctOut    = 'vct$ctIdx';
      filters.add('[$idx:v]${filterParts.join(',')}[$ctLabel]');

      final blendIdx = t.textBlendModeIndex.clamp(0, ffmpegBlendModes.length - 1);
      if (blendIdx != 0) {
        // ── Blend-mode composite ──────────────────────────────────────────
        // Pad the PNG to the full canvas at the overlay position, blend it
        // against the base video, then mask the result back to text-only pixels.
        final ffMode      = ffmpegBlendModes[blendIdx];
        final paddedLbl   = 'ctpad$ctIdx';
        final blendedLbl  = 'ctbl$ctIdx';
        final maskLbl     = 'ctmsk$ctIdx';
        final maskedLbl   = 'ctmkd$ctIdx';
        final baseA       = 'ctbA$ctIdx';
        final baseB       = 'ctbB$ctIdx';

        final padX = '(($width-iw)/2+$ox*$width/2)';
        final padY = '(($height-ih)/2+$oy*$height/2)';

        // Pad PNG to full video canvas at the requested position
        filters.add(
          '[$ctLabel]pad=w=$width:h=$height:x=$padX:y=$padY'
          ':color=0x00000000,format=yuva420p[$paddedLbl]',
        );
        // Split base into two copies (one for blend, one for final composite)
        filters.add('[$textBase]split=2[$baseA][$baseB]');
        // Apply blend mode across the full frame
        filters.add('[$baseA][$paddedLbl]blend=all_mode=$ffMode:all_opacity=1.0[$blendedLbl]');
        // Extract the text alpha channel as a mask
        filters.add('[$paddedLbl]alphaextract[$maskLbl]');
        // Apply mask: only text pixels keep the blended result
        filters.add('[$blendedLbl][$maskLbl]alphamerge[$maskedLbl]');
        // Composite masked blend over the original base
        filters.add('[$baseB][$maskedLbl]overlay=format=auto:eof_action=pass[$ctOut]');
      } else {
        // ── Normal alpha composite ────────────────────────────────────────
        filters.add(
          '[$textBase][$ctLabel]overlay='
          'x=(W-w)/2+$ox*W/2:y=(H-h)/2+$oy*H/2'
          ':format=auto:eof_action=pass[$ctOut]',
        );
      }

      textBase = ctOut;
      ctIdx++;
      idx++;
    }

    // ── 2. Straight text overlays (drawtext) ─────────────────────────────────
    // Applied sequentially to [textBase], which may now be the output of the
    // curved-text overlay chain above.
    for (int ti = 0; ti < textTracks.length; ti++) {
      final t = textTracks[ti];
      final txtOut = 'vtx$ti';
      final so = t.startOffset.inMicroseconds / 1e6;
      final end = t.endTime.inMicroseconds / 1e6;

      // ── Apply case transform ───────────────────────────────────────────
      final rawDt = t.textContent.isEmpty ? 'Text' : t.textContent;
      final casedDt = switch (t.textCaseIndex) {
        1 => rawDt.toUpperCase(),
        2 => rawDt.toLowerCase(),
        3 => rawDt.splitMapJoin(RegExp(r'\S+'),
              onMatch: (m) {
                final w = m[0]!;
                return w[0].toUpperCase() + w.substring(1).toLowerCase();
              },
              onNonMatch: (s) => s),
        _ => rawDt,
      };
      final escapedText = _escapeDtText(casedDt);

      // ── Font colour ────────────────────────────────────────────────────
      final r = (t.textColor.r * 255).round();
      final g = (t.textColor.g * 255).round();
      final b = (t.textColor.b * 255).round();
      final fontAlpha   = t.textColor.a.toStringAsFixed(3);
      final fontColorHex =
          '0x${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';

      final fs        = (t.fontSize * t.overlayScale).round();
      final ox        = t.overlayX.toStringAsFixed(4);
      final oy        = t.overlayY.toStringAsFixed(4);
      final boldStr   = t.textBold   ? ':bold=1'   : '';
      final italicStr = t.textItalic ? ':italic=1' : '';

      // line_spacing = extra pixels between lines.
      // Flutter lineHeight is a multiplier (1.0 = tight), so:
      //   extra_px ≈ (lineHeight - 1.0) × fontSize
      // drawtext default is 0 extra pixels (≈ lineHeight 1.0).
      final lineSpacingPx = ((t.lineHeight - 1.0) * t.fontSize).round();
      final lineSpacingStr =
          lineSpacingPx != 0 ? ':line_spacing=$lineSpacingPx' : '';

      // Horizontal alignment: drawtext positions the left edge of the text,
      // so we shift x based on textAlignIndex (0=left, 1=center, 2=right).
      final dtPadH = t.textPaddingH.round().clamp(0, 120);
      final dtX = switch (t.textAlignIndex) {
        0 => '$dtPadH+$ox*w/2',                  // left-aligned with padding offset
        2 => 'w-text_w-$dtPadH+$ox*w/2',         // right-aligned with padding offset
        _ => '(w-text_w)/2+$ox*w/2',             // center (default)
      };

      var dtFilter =
          'drawtext=text=\'$escapedText\''
          ':fontsize=$fs'
          ':fontcolor=$fontColorHex@$fontAlpha'
          ':x=$dtX'
          ':y=(h-text_h)/2+$oy*h/2'
          ':alpha=${t.opacity.toStringAsFixed(3)}'
          ':enable=\'between(t,$so,$end)\''
          '$boldStr$italicStr$lineSpacingStr';

      // ── Outline (stroke) ───────────────────────────────────────────────
      // drawtext: borderw is total width in pixels; bordercolor supports @alpha.
      if (t.textOutlineWidth > 0.0) {
        final obR = (t.textOutlineColor.r * 255).round();
        final obG = (t.textOutlineColor.g * 255).round();
        final obB = (t.textOutlineColor.b * 255).round();
        final outlineHex =
            '0x${obR.toRadixString(16).padLeft(2, '0')}'
            '${obG.toRadixString(16).padLeft(2, '0')}'
            '${obB.toRadixString(16).padLeft(2, '0')}';
        dtFilter +=
            ':borderw=${t.textOutlineWidth.round()}'
            ':bordercolor=$outlineHex@${t.textOutlineColor.a.toStringAsFixed(3)}';
      }

      // ── Drop shadow ────────────────────────────────────────────────────
      // drawtext supports shadowx/shadowy/shadowcolor but NOT blur radius,
      // so this is a hard shadow.  Tracks with glow (blur) go to the PNG path.
      if (t.shadowRadius > 0 && t.shadowOpacity > 0) {
        final shR = (t.shadowColor.r * 255).round();
        final shG = (t.shadowColor.g * 255).round();
        final shB = (t.shadowColor.b * 255).round();
        final shadowHex =
            '0x${shR.toRadixString(16).padLeft(2, '0')}'
            '${shG.toRadixString(16).padLeft(2, '0')}'
            '${shB.toRadixString(16).padLeft(2, '0')}';
        dtFilter +=
            ':shadowx=${t.shadowOffsetX.toStringAsFixed(1)}'
            ':shadowy=${t.shadowOffsetY.toStringAsFixed(1)}'
            ':shadowcolor=$shadowHex@${t.shadowOpacity.toStringAsFixed(3)}';
      }

      // ── Background box ─────────────────────────────────────────────────
      if (t.textBgOpacity > 0.0) {
        final bgR = (t.textBgColor.r * 255).round();
        final bgG = (t.textBgColor.g * 255).round();
        final bgB = (t.textBgColor.b * 255).round();
        final bgHex =
            '0x${bgR.toRadixString(16).padLeft(2, '0')}'
            '${bgG.toRadixString(16).padLeft(2, '0')}'
            '${bgB.toRadixString(16).padLeft(2, '0')}';
        dtFilter +=
            ':box=1'
            ':boxcolor=$bgHex@${t.textBgOpacity.toStringAsFixed(3)}'
            ':boxborderw=${(t.textPaddingH.clamp(0, 60)).round()}';
      }

      filters.add('[$textBase]$dtFilter[$txtOut]');
      textBase = txtOut;
    }

    // ── Finalise text output label ────────────────────────────────────────────
    final hasAnyText = curvedTracks.isNotEmpty || textTracks.isNotEmpty;
    if (hasAnyText) {
      filters.add('[$textBase]copy[vout_final]');
    }

    // ── Audio mix ──────────────────────────────────────────────────────────
    final audioCodec = isWebM ? 'libopus' : 'aac';
    String audioArg;
    if (audioLabels.isEmpty) {
      audioArg = '-an';
    } else {
      if (audioLabels.length == 1) {
        filters.add('[${audioLabels[0]}]apad=whole_dur=$totalSecs[aout]');
      } else {
        final joined = audioLabels.map((l) => '[$l]').join('');
        filters.add(
            '${joined}amix=inputs=${audioLabels.length}:normalize=0:duration=longest[aout]');
      }
      audioArg = '-map "[aout]" -c:a $audioCodec -b:a 128k';
    }

    final filterComplex = filters.join(';');

    final videoCodecArgs = isWebM
        ? '-c:v libvpx-vp9 -crf $crf -b:v 0 -deadline realtime -cpu-used 4'
        : '-c:v libx264 -preset fast -crf $crf';

    final containerFlags =
        fmt.faststart ? '-movflags +faststart ' : '';

    final voutLabel = hasAnyText ? 'vout_final' : 'vout';
    final cmd = '${inputs.toString()}'
        '-filter_complex "$filterComplex" '
        '-map "[$voutLabel]" '
        '$audioArg '
        '$videoCodecArgs '
        '-r $frameRate '
        '$containerFlags'
        '-t $totalSecs '
        '-y "$outputPath"';
    debugPrint('=== FFmpeg export command ===\n$cmd');
    return cmd;
  }

  // Two-pass GIF: palette generation + dithering
  String _buildGifCommand({
    required String outputPath,
    required int width,
    required int height,
    required int frameRate,
    required List<TimelineTrack> videoTracks,
  }) {
    // For GIF we use the first video track only, scaled down
    // Full multi-track GIF would require compositing first; this is a
    // single-pass approach using the first video track.
    final track = videoTracks.isNotEmpty ? videoTracks.first : null;
    final input = track != null ? '"${track.filePath}"' : '-f lavfi -i "color=c=white"';
    final totalSecs = _totalSecs;
    final scale = 'scale=$width:$height:force_original_aspect_ratio=decrease';

    // Single-pass GIF using built-in palette (less optimal but simpler)
    return '-i $input '
        '-vf "$scale,fps=$frameRate,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse=dither=bayer" '
        '-loop 0 '
        '-t $totalSecs '
        '-y "$outputPath"';
  }

  /// Returns the FFmpeg filter string for the given rotation (empty if 0°).
  /// Must be placed BEFORE scale/pad so the rotated dimensions are used.
  String _rotationFilter(int degrees) {
    switch (degrees) {
      case 90:  return 'transpose=1';
      case 180: return 'vflip,hflip';
      case 270: return 'transpose=2';
      default:  return '';
    }
  }

  String _buildAtempo(double speed) {
    if (speed >= 0.5 && speed <= 2.0) return 'atempo=$speed';
    if (speed < 0.5) {
      return 'atempo=0.5,atempo=${(speed / 0.5).toStringAsFixed(4)}';
    }
    return 'atempo=2.0,atempo=${(speed / 2.0).toStringAsFixed(4)}';
  }

  /// Appends FFmpeg visual-filter fragments for brightness, contrast,
  /// saturation, hue, blur, vignette and grain to [parts].
  /// Call this after format=yuv420p and before fade/opacity filters.
  /// Escape text for FFmpeg drawtext filter.
  /// Characters that must be escaped: \, :, ', %, { }
  String _escapeDtText(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll('%', r'\%')
        .replaceAll('\n', r'\n');
  }

  void _addVisualFilters(List<String> parts, TimelineTrack t,
      [Map<String, String>? stabTrfPaths]) {
    // ── eq: brightness / contrast / saturation ───────────────────────────
    // FFmpeg eq ranges: brightness -1..1, contrast -1000..1000 (1=normal),
    // saturation 0..3 (1=normal) — our model ranges map directly.
    if (t.brightness != 0.0 || t.contrast != 1.0 || t.saturation != 1.0) {
      final b = t.brightness.toStringAsFixed(4);
      final c = t.contrast.toStringAsFixed(4);
      final s = t.saturation.toStringAsFixed(4);
      parts.add('eq=brightness=$b:contrast=$c:saturation=$s');
    }

    // ── hue rotation ─────────────────────────────────────────────────────
    if (t.hue != 0.0) {
      parts.add('hue=h=${t.hue.toStringAsFixed(2)}');
    }

    // ── color temperature ─────────────────────────────────────────────────
    // colorbalance values range -1..1; warm → +R −B, cool → −R +B.
    if (t.temperature != 0.0) {
      final rShift = ( t.temperature * 0.25).clamp(-1.0, 1.0).toStringAsFixed(4);
      final gShift = ( t.temperature * 0.06).clamp(-1.0, 1.0).toStringAsFixed(4);
      final bShift = (-t.temperature * 0.25).clamp(-1.0, 1.0).toStringAsFixed(4);
      parts.add('colorbalance='
          'rs=$rShift:gs=$gShift:bs=$bShift:'
          'rm=$rShift:gm=$gShift:bm=$bShift:'
          'rh=$rShift:gh=$gShift:bh=$bShift');
    }

    // ── Gaussian blur ─────────────────────────────────────────────────────
    if (t.blurRadius > 0.0) {
      parts.add('gblur=sigma=${t.blurRadius.toStringAsFixed(2)}');
    }

    // ── Vignette ──────────────────────────────────────────────────────────
    // FFmpeg vignette: pixel = pixel * cos(angle * r)^4
    // angle=0 → no effect, angle=PI/2 → edges black.
    if (t.vignetteStrength > 0.0) {
      final angle = (t.vignetteStrength * 1.5708).toStringAsFixed(4); // × PI/2
      parts.add('vignette=angle=$angle');
    }

    // ── Film grain / noise ────────────────────────────────────────────────
    // noise strength 0–50 mapped from grainStrength 0–1; allf=t for temporal.
    if (t.grainStrength > 0.0) {
      final strength = (t.grainStrength * 50).round();
      parts.add('noise=alls=$strength:allf=t');
    }

    // ── Chroma Key / Green Screen ─────────────────────────────────────────
    // chromakey operates on yuv420p input and outputs yuva420p (with alpha).
    if (t.chromakeyEnabled) {
      final c   = t.chromakeyColor;
      final rh  = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
      final gh  = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
      final bh  = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
      final sim = t.chromakeySimilarity.clamp(0.01, 0.50).toStringAsFixed(3);
      final bld = t.chromakeyBlend.clamp(0.0, 0.20).toStringAsFixed(3);
      parts.add('chromakey=color=0x$rh$gh$bh:similarity=$sim:blend=$bld');
    }

    // ── Video Stabilizer ──────────────────────────────────────────────────
    // Use 2-pass VidStab if the .trf was generated in the pre-pass; fall back
    // to deshake if the analysis failed (e.g. vidstab not in this FFmpeg build).
    if (t.isStabilized) {
      final trf = stabTrfPaths?[t.id];
      if (trf != null) {
        parts.add(
          'vidstabtransform=input=$trf:zoom=1:smoothing=10'
          ',unsharp=5:5:-0.8:3:3:-0.4',
        );
      } else {
        parts.add('deshake=x=-1:y=-1:w=-1:h=-1:edge=0:blocksize=8:contrast=125:search=5');
      }
    }
  }

  /// Returns the FFmpeg audio filter chain for the given voice effect index.
  /// Empty string when no effect (index = 0 = Normal).
  String _buildVoiceFilter(int index) {
    switch (index) {
      case 1: // Hall — reverb echo
        return 'aecho=0.8:0.88:60:0.4';
      case 2: // Girl — pitch up 25 %
        return 'asetrate=55125,aresample=44100';
      case 3: // Woman — pitch up 12 %
        return 'asetrate=49392,aresample=44100';
      case 4: // Boy — pitch down 12 %
        return 'asetrate=38808,aresample=44100';
      case 5: // Multiple — layered echoes
        return 'aecho=0.8:0.88:40|70|100:0.3|0.2|0.1';
      case 6: // Robot — tremolo + metallic echo
        return 'tremolo=f=20:d=0.9,aecho=0.9:0.7:6:0.6';
      case 7: // Alien — high pitch + short echo
        return 'asetrate=66150,aresample=44100,aecho=0.6:0.5:5:0.7';
      case 8: // Foreigner — low pitch + room echo
        return 'asetrate=33075,aresample=44100,aecho=0.7:0.7:80:0.3';
      default: // 0 = Normal
        return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ExportProgressDialog extends StatelessWidget {
  final ValueNotifier<_ProgressInfo> notifier;
  const _ExportProgressDialog({required this.notifier});

  String _fmtEta(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20))),
      content: ValueListenableBuilder<_ProgressInfo>(
        valueListenable: notifier,
        builder: (_, info, __) {
          final pct = (info.value * 100).toStringAsFixed(0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              // Circular progress with percentage in center
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: info.value > 0 ? info.value : null,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFF333333),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFE53935)),
                    ),
                    Text(
                      info.value > 0 ? '$pct%' : '…',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Linear progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: info.value > 0 ? info.value : null,
                  minHeight: 5,
                  backgroundColor: const Color(0xFF333333),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFFE53935)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Exporting video…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (info.eta != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${_fmtEta(info.eta!)} remaining',
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 12),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
