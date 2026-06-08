import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min, pi, cos, sin;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'package:video_thumbnail/video_thumbnail.dart';

import 'collage_models.dart';
import '../../data/collage_draft_manager.dart';
import '../../service/export_progress_state.dart';
import '../../service/export_service_manager.dart';
import '../export_result/export_result_screen.dart';

class CollagePreviewScreen extends StatefulWidget {
  final List<CollageCellData> cells;
  final List<Rect> cellRects; // normalized 0..1
  final Map<int, VideoPlayerController> videoControllers;

  // Per-cell repeat flags (true = loop)
  final List<bool>? cellRepeating;

  // Canvas appearance
  final Color bgColor;
  final double borderGap;

  // Background audio
  final String? audioPath;
  final Duration audioTrimStart;
  final Duration audioTrimEnd;
  final double audioVolume;

  // Export dimensions
  final int outW;
  final int outH;

  // Export encoding settings (provided by CollageExportSettingsScreen)
  final int fps;
  final int crf;
  final String format;   // output container extension: 'mp4', 'mov', 'mkv'
  final bool faststart;  // movflags +faststart (MP4/MOV)

  // Per-cell FFmpeg vf filter strings (null = no filter)
  final List<String?>? cellFilterVf;

  // Per-cell ColorFilter for live preview (null = no filter)
  final List<ColorFilter?>? cellColorFilters;

  // Per-cell playback speed (1.0 = normal)
  final List<double>? cellSpeeds;

  // Per-cell audio volume (1.0 = full, 0.0 = muted)
  final List<double>? cellVolumes;

  // Per-cell rotation (0-3 × 90° CW) and flip flags from the editor.
  final List<int>? cellRotSteps;
  final List<bool>? cellFlipH;
  final List<bool>? cellFlipV;

  // Per-cell continuous transforms from the editor (pinch-zoom, free-rotate, pan).
  // cellNormOffsetX/Y are pan offsets normalized to [fraction of cell width/height]
  // so they are resolution-independent between the Flutter canvas and FFmpeg output.
  final List<double>? cellScales;
  final List<double>? cellAngles;
  final List<double>? cellNormOffsetX;
  final List<double>? cellNormOffsetY;

  /// Draft id used to update the thumbnail after a successful export.
  final String? draftId;

  const CollagePreviewScreen({
    super.key,
    required this.cells,
    required this.cellRects,
    required this.videoControllers,
    this.cellRepeating,
    this.bgColor = Colors.black,
    this.borderGap = 1.0,
    this.audioPath,
    this.audioTrimStart = Duration.zero,
    this.audioTrimEnd = Duration.zero,
    this.audioVolume = 1.0,
    this.outW = 720,
    this.outH = 1280,
    this.fps = 30,
    this.crf = 23,
    this.format = 'mp4',
    this.faststart = false,
    this.cellFilterVf,
    this.cellColorFilters,
    this.cellSpeeds,
    this.cellVolumes,
    this.cellRotSteps,
    this.cellFlipH,
    this.cellFlipV,
    this.cellScales,
    this.cellAngles,
    this.cellNormOffsetX,
    this.cellNormOffsetY,
    this.draftId,
  });

  @override
  State<CollagePreviewScreen> createState() => _CollagePreviewScreenState();
}

class _CollagePreviewScreenState extends State<CollagePreviewScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int get _outW => widget.outW;
  int get _outH => widget.outH;
  static const _kOrange = Color(0xFFB8860B);
  static const _kPurple = Color(0xFF7B35C8);

  bool _playing = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // Preview mode
  _PreviewMode _previewMode = _PreviewMode.parallel;
  int _seqIdx = 0;
  Timer? _seqTimer;
  final Set<int> _manualPlaying = {};

  // Background audio preview
  AudioPlayer? _bgAudioPlayer;
  Timer? _bgAudioStopTimer;

  // Export state
  _ExportState _exportState = _ExportState.idle;
  double _exportProgress = 0.0;
  String? _exportError;

  // Save-button bounce animation
  late final AnimationController _saveBounceCtrl;
  late final Animation<double> _saveBounceAnim;

  // Per-cell audio presence (populated by _probeAudioStreams before export)
  final Map<int, bool> _cellHasAudio = {};

  /// rotationCorrection (degrees) per cell, snapshotted before the
  /// VideoPlayerControllers are disposed so that _cellGeoVf can still read
  /// it when building FFmpeg arguments (controllers are cleared before export).
  final Map<int, int> _rotCorrSnapshot = {};

  // Seek state
  bool _isSeeking = false;
  double _seekFraction = 0.0;

  double _cellSpeed(int i) {
    if (widget.cellSpeeds == null || i >= widget.cellSpeeds!.length) return 1.0;
    final s = widget.cellSpeeds![i];
    return s > 0 ? s : 1.0;
  }

  Duration _effectiveDuration(int i) {
    final cell = widget.cells[i];
    Duration raw;
    if (cell.trimEnd > Duration.zero) {
      raw = cell.trimEnd - cell.trimStart;
    } else if (cell.duration > Duration.zero) {
      raw = cell.duration;
    } else {
      raw = const Duration(seconds: 3);
    }
    final speed = _cellSpeed(i);
    return speed == 1.0
        ? raw
        : Duration(microseconds: (raw.inMicroseconds / speed).round());
  }

  List<int> get _seqEligible {
    final result = <int>[];
    for (int i = 0; i < widget.cells.length; i++) {
      if (!widget.cells[i].isEmpty) result.add(i);
    }
    return result;
  }

  Duration get _totalDuration {
    if (_previewMode == _PreviewMode.sequential) {
      Duration sum = Duration.zero;
      for (final i in _seqEligible) {
        sum += _effectiveDuration(i);
      }
      return sum == Duration.zero ? const Duration(seconds: 10) : sum;
    }
    Duration max = Duration.zero;
    for (int i = 0; i < widget.cells.length; i++) {
      final cell = widget.cells[i];
      final raw = cell.trimEnd > Duration.zero
          ? cell.trimEnd - cell.trimStart
          : cell.duration;
      final speed = _cellSpeed(i);
      final effective = speed == 1.0
          ? raw
          : Duration(microseconds: (raw.inMicroseconds / speed).round());
      if (effective > max) max = effective;
    }
    return max == Duration.zero ? const Duration(seconds: 10) : max;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saveBounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _saveBounceAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _saveBounceCtrl, curve: Curves.elasticOut),
    );
    _saveBounceCtrl.value = 1.0; // start at rest (end value)
    if (_previewMode != _PreviewMode.manual) {
      // Delay until after the first frame so VideoPlayer widgets are built
      // and the controllers from the editor have settled after _pauseAll().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playAll();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Pause all cell videos when app goes to background.
      for (final vc in widget.videoControllers.values) {
        vc.pause();
      }
      _bgAudioPlayer?.pause();
      _timer?.cancel();
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveBounceCtrl.dispose();
    _timer?.cancel();
    _seqTimer?.cancel();
    _bgAudioStopTimer?.cancel();
    _bgAudioPlayer?.stop();
    _bgAudioPlayer?.dispose();
    // Pause media directly — do NOT call _pauseAll() here because that calls
    // setState(), which is illegal during dispose() even when mounted is true.
    for (final vc in widget.videoControllers.values) {
      vc.pause();
    }
    super.dispose();
  }

  void _startProgressTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final next = _elapsed + const Duration(milliseconds: 100);
      if (next >= _totalDuration) {
        setState(() {
          _elapsed = _totalDuration;
          _playing = false;
        });
        _pauseAll();
        _timer?.cancel();
      } else {
        setState(() => _elapsed = next);
      }
    });
  }

  Future<void> _playAll() async {
    if (!mounted) return;
    switch (_previewMode) {
      case _PreviewMode.parallel:
        // Seek all controllers to their trim start in parallel, then play
        // simultaneously. Each controller wrapped in its own try-catch so a
        // single bad controller can't abort the whole Future.wait chain.
        await Future.wait(
          widget.videoControllers.entries.map((entry) async {
            try {
              if (entry.key < widget.cells.length) {
                final cell = widget.cells[entry.key];
                await entry.value.setLooping(true);
                await entry.value.seekTo(cell.trimStart);
              }
            } catch (_) {}
          }),
        );
        if (!mounted) return;
        for (final vc in widget.videoControllers.values) {
          vc.play();
        }
        _startProgressTimer();
        if (mounted && !_playing) setState(() => _playing = true);
        _playBgAudio();
      case _PreviewMode.sequential:
        _seqIdx = 0;
        _elapsed = Duration.zero;
        _startProgressTimer();
        if (mounted && !_playing) setState(() => _playing = true);
        _playSeqCurrent();
        _playBgAudio();
      case _PreviewMode.manual:
        break;
    }
  }

  void _playSeqCurrent() {
    final eligible = _seqEligible;
    if (eligible.isEmpty) return;
    if (_seqIdx >= eligible.length) _seqIdx = 0;

    final cellIdx = eligible[_seqIdx];
    final vc = widget.videoControllers[cellIdx];
    final cell = widget.cells[cellIdx];

    // Pause all other cells
    for (final entry in widget.videoControllers.entries) {
      if (entry.key != cellIdx) entry.value.pause();
    }
    if (vc != null) {
      vc.seekTo(cell.trimStart);
      vc.play();
    }

    _seqTimer?.cancel();
    _seqTimer = Timer(_effectiveDuration(cellIdx), () {
      if (!mounted || !_playing) return;
      vc?.pause();
      _seqIdx = (_seqIdx + 1) % eligible.length;
      _playSeqCurrent();
    });
  }

  void _pauseAll() {
    _seqTimer?.cancel();
    for (final vc in widget.videoControllers.values) {
      vc.setLooping(false);
      vc.pause();
    }
    _timer?.cancel();
    _bgAudioStopTimer?.cancel();
    _bgAudioPlayer?.pause();
    if (mounted) setState(() { _playing = false; _manualPlaying.clear(); });
  }

  void _toggleCellPlay(int index) {
    final vc = widget.videoControllers[index];
    if (vc == null) return;
    if (_manualPlaying.contains(index)) {
      vc.pause();
      setState(() => _manualPlaying.remove(index));
    } else {
      vc.play();
      setState(() => _manualPlaying.add(index));
    }
  }

  void _setPreviewMode(_PreviewMode mode) {
    if (_playing) _pauseAll();
    _seqTimer?.cancel();
    setState(() {
      _previewMode = mode;
      _seqIdx = 0;
      _elapsed = Duration.zero;
      _manualPlaying.clear();
    });
  }

  Future<void> _playBgAudio() async {
    if (widget.audioPath == null) return;
    _bgAudioStopTimer?.cancel();
    _bgAudioPlayer ??= AudioPlayer();
    await _bgAudioPlayer!.setSource(DeviceFileSource(widget.audioPath!));
    await _bgAudioPlayer!.setVolume(widget.audioVolume);
    await _bgAudioPlayer!.seek(widget.audioTrimStart);
    await _bgAudioPlayer!.resume();
    final trimLen = widget.audioTrimEnd > widget.audioTrimStart
        ? widget.audioTrimEnd - widget.audioTrimStart
        : _totalDuration;
    _bgAudioStopTimer = Timer(trimLen, () => _bgAudioPlayer?.pause());
  }

  void _togglePlay() {
    if (_previewMode == _PreviewMode.manual) return;
    if (_playing) {
      _pauseAll();
    } else {
      // Set _playing immediately to prevent double-tap launching two _playAll()
      // calls concurrently (async _playAll would otherwise see _playing=false
      // on both taps and start two competing Future.wait seek chains).
      if (_elapsed >= _totalDuration) {
        setState(() { _playing = true; _elapsed = Duration.zero; });
      } else {
        setState(() => _playing = true);
      }
      _playAll();
    }
  }

  // ── Seek ───────────────────────────────────────────────────────────────────

  Future<void> _seekTo(double fraction) async {
    if (_previewMode == _PreviewMode.manual) return;
    final wasPlaying = _playing;
    if (wasPlaying) _pauseAll();

    final targetUs =
        (_totalDuration.inMicroseconds * fraction.clamp(0.0, 1.0)).round();
    final target = Duration(microseconds: targetUs);

    switch (_previewMode) {
      case _PreviewMode.parallel:
        for (final entry in widget.videoControllers.entries) {
          final i = entry.key;
          if (i >= widget.cells.length) continue;
          final cell = widget.cells[i];
          final effDurUs = _effectiveDuration(i).inMicroseconds;
          if (effDurUs == 0) continue;
          final posUs = effDurUs > 0 ? targetUs % effDurUs : 0;
          final seekPos = cell.trimStart + Duration(microseconds: posUs);
          try { await entry.value.seekTo(seekPos); } catch (_) {}
        }
      case _PreviewMode.sequential:
        Duration offset = Duration.zero;
        for (final idx in _seqEligible) {
          final dur = _effectiveDuration(idx);
          if (target <= offset + dur) {
            final posInCell = target - offset;
            final cell = widget.cells[idx];
            final seekPos = cell.trimStart + posInCell;
            try {
              await widget.videoControllers[idx]?.seekTo(seekPos);
            } catch (_) {}
            for (final e in widget.videoControllers.entries) {
              if (e.key != idx) {
                try { e.value.pause(); } catch (_) {}
              }
            }
            break;
          }
          offset += dur;
        }
      case _PreviewMode.manual:
        break;
    }

    setState(() => _elapsed = target);

    if (wasPlaying) {
      setState(() => _playing = true);
      _startProgressTimer();
      _playBgAudio();
      for (final vc in widget.videoControllers.values) {
        try { vc.play(); } catch (_) {}
      }
    }
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  /// Probes each video cell for the presence of an audio stream.
  /// Results are stored in [_cellHasAudio] before building FFmpeg args.
  Future<void> _probeAudioStreams(List<int> nonEmpty) async {
    for (final i in nonEmpty) {
      final cell = widget.cells[i];
      if (!cell.isVideo || cell.filePath == null) {
        _cellHasAudio[i] = false;
        continue;
      }
      try {
        final session = await FFprobeKit.getMediaInformation(cell.filePath!);
        final streams = session.getMediaInformation()?.getStreams() ?? [];
        _cellHasAudio[i] = streams.any((s) => s.getType() == 'audio');
      } catch (_) {
        _cellHasAudio[i] = false;
      }
    }
  }

  double _cellVol(int i) {
    if (widget.cellVolumes == null || i >= widget.cellVolumes!.length) return 1.0;
    final v = widget.cellVolumes![i];
    return v >= 0 ? v : 1.0;
  }

  /// Returns the atempo filter chain string (with leading comma) for [speed].
  /// atempo works in the 0.5–2.0 range; values outside are chained.
  String _audioTempoStr(double speed) {
    if (speed == 1.0) return '';
    if (speed >= 0.5 && speed <= 2.0) {
      return ',atempo=${speed.toStringAsFixed(6)}';
    }
    if (speed < 0.5) {
      final second = (speed / 0.5).clamp(0.5, 1.0);
      return ',atempo=0.500000,atempo=${second.toStringAsFixed(6)}';
    }
    // speed > 2.0
    final second = (speed / 2.0).clamp(1.0, 2.0);
    return ',atempo=2.000000,atempo=${second.toStringAsFixed(6)}';
  }

  String _bgHex() {
    final r = (widget.bgColor.r * 255).round();
    final g = (widget.bgColor.g * 255).round();
    final b = (widget.bgColor.b * 255).round();
    return '0x'
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  List<String> _audioArgs(int videoInputCount, String durSec) {
    final hasAudio = widget.audioPath != null;
    if (!hasAudio) return [];
    final trimStartSec =
        (widget.audioTrimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
    final trimEnd = widget.audioTrimEnd > widget.audioTrimStart
        ? widget.audioTrimEnd - widget.audioTrimStart
        : Duration(milliseconds: (double.parse(durSec) * 1000).round());
    final trimDurSec =
        (trimEnd.inMilliseconds / 1000.0).toStringAsFixed(3);
    return ['-ss', trimStartSec, '-t', trimDurSec, '-i', widget.audioPath!];
  }

  // ── Rotation / flip helpers ───────────────────────────────────────────────

  int _cellRot(int i) =>
      (widget.cellRotSteps != null && i < widget.cellRotSteps!.length)
          ? widget.cellRotSteps![i] % 4
          : 0;
  bool _cellFH(int i) =>
      (widget.cellFlipH != null && i < widget.cellFlipH!.length)
          ? widget.cellFlipH![i]
          : false;
  bool _cellFV(int i) =>
      (widget.cellFlipV != null && i < widget.cellFlipV!.length)
          ? widget.cellFlipV![i]
          : false;

  double _cellUserScale(int i) =>
      (widget.cellScales != null && i < widget.cellScales!.length)
          ? widget.cellScales![i]
          : 1.0;

  double _cellUserAngle(int i) =>
      (widget.cellAngles != null && i < widget.cellAngles!.length)
          ? widget.cellAngles![i]
          : 0.0;

  double _cellNormOffX(int i) =>
      (widget.cellNormOffsetX != null && i < widget.cellNormOffsetX!.length)
          ? widget.cellNormOffsetX![i]
          : 0.0;

  double _cellNormOffY(int i) =>
      (widget.cellNormOffsetY != null && i < widget.cellNormOffsetY!.length)
          ? widget.cellNormOffsetY![i]
          : 0.0;

  /// FFmpeg vf filter string (without leading/trailing comma) that applies the
  /// discrete 90°-step rotation and flip for cell [i].  Returns empty string if
  /// no transform is needed.
  ///
  /// When [isVideo] is true, the native rotation embedded in the video's
  /// container metadata is folded in.  FFmpeg does NOT apply autorotate inside
  /// filter_complex the way VideoPlayer's RotatedBox does, so we disable it
  /// explicitly (-noautorotate on the input) and replicate it here instead.
  ///
  /// Operation order matches the Flutter live-preview chain exactly:
  ///   VideoPlayer → RotatedBox(nativeRot) → Transform( M = R_user · S_flip )
  /// where M·p = R_user·(S_flip·p), i.e. flip is applied BEFORE user rotation.
  /// FFmpeg equivalent: (1) native rotate  (2) user flip  (3) user rotate.
  String _cellGeoVf(int i, {bool isVideo = false}) {
    // Use the snapshot captured before controllers were disposed.
    // widget.videoControllers is cleared before FFmpeg args are built, so
    // reading it directly here would always return 0 (wrong rotation).
    final nativeRot = isVideo
        ? (_rotCorrSnapshot[i] ?? 0) ~/ 90
        : 0;
    final userRot = _cellRot(i);
    final fH = _cellFH(i);
    final fV = _cellFV(i);
    final parts = <String>[];

    // Step 1 — native rotation (replicates VideoPlayer's Transform.rotate)
    switch (nativeRot % 4) {
      case 1: parts.add('transpose=1'); break; // 90° CW
      case 2: parts.add('hflip,vflip'); break; // 180°
      case 3: parts.add('transpose=2'); break; // 270° CW
    }

    // Step 2 — user flip in the native-corrected frame
    if (fH) parts.add('hflip');
    if (fV) parts.add('vflip');

    // Step 3 — user rotation (after flip, matching M = R·S in Flutter)
    switch (userRot % 4) {
      case 1: parts.add('transpose=1'); break; // 90° CW
      case 2: parts.add('hflip,vflip'); break; // 180°
      case 3: parts.add('transpose=2'); break; // 270° CW
    }

    return parts.join(',');
  }

  /// Builds the FFmpeg scale+crop filter string for cell [i] targeting a cell
  /// of [w]×[h] pixels, incorporating user zoom (cellScales), free-angle
  /// rotation (cellAngles), and pan (cellNormOffsetX/Y).
  ///
  /// When all user transforms are identity (scale=1, angle=0, pan=0) this
  /// produces the same output as the previous hard-coded filter.
  String _cellScaleCrop(int i, int w, int h) {
    final userS = _cellUserScale(i);
    final userA = _cellUserAngle(i);
    final normOffX = _cellNormOffX(i);
    final normOffY = _cellNormOffY(i);

    // Cover scale for the user's free-rotation angle (discrete rotation is
    // already applied by _cellGeoVf before this filter runs).
    final abscos = cos(userA).abs();
    final abssin = sin(userA).abs();
    final ar = (h > 0 && w > 0) ? w / h : 1.0;
    final maxAR = ar > 1.0 ? ar : 1.0 / ar;
    final cs = abscos + maxAR * abssin; // always ≥ 1; equals 1 when angle=0

    // Total scale factor: user zoom × rotation-cover.
    final totalS = userS * cs;

    // Scale targets: next multiple of 32 strictly above w*totalS and h*totalS.
    // This guarantees crop safety and 32-byte NEON alignment (Samsung bug).
    final int newScaleW, newScaleH;
    if (totalS <= 1.0) {
      // No zoom: keep the existing formula (next multiple of 32 above w/h).
      newScaleW = (w ~/ 32 + 1) * 32;
      newScaleH = (h ~/ 32 + 1) * 32;
    } else {
      final neededW = (w * totalS).ceil();
      final neededH = (h * totalS).ceil();
      newScaleW = (neededW ~/ 32 + 1) * 32;
      newScaleH = (neededH ~/ 32 + 1) * 32;
    }

    // Optional free-angle rotation filter (after scale, keeps frame size).
    // fillcolor=black fills the corners exposed by rotation; since we have
    // over-scaled above, these corners fall outside the final crop region.
    final hasUserAngle = userA.abs() > 1e-6;
    final rotateStr = hasUserAngle
        ? 'rotate=${userA.toStringAsFixed(6)}:ow=iw:oh=ih:fillcolor=black,'
        : '';

    // Pan offsets in FFmpeg output pixels.
    // Positive normOff → content shifts in that direction (same convention as
    // the Flutter editor's _cellMatrix translate), so the crop window shifts
    // in the opposite direction to expose more of that side.
    final panX = (normOffX * w).round();
    final panY = (normOffY * h).round();

    // Crop: centered minus pan, clamped to valid range.
    final String cropStr;
    if (panX == 0 && panY == 0) {
      cropStr = 'crop=$w:$h'; // default center crop, identical to previous code
    } else {
      cropStr = 'crop=$w:$h'
          ':max(0,min(iw-$w,(iw-$w)/2-$panX))'
          ':max(0,min(ih-$h,(ih-$h)/2-$panY))';
    }

    return 'scale=$newScaleW:$newScaleH'
        ':force_original_aspect_ratio=increase'
        ':force_divisible_by=32,'
        '$rotateStr$cropStr,setsar=1';
  }

  // ── Parallel / Manual export ───────────────────────────────────────────────

  List<String> _buildParallelArgs(List<int> nonEmpty, String outPath) {
    final durSec =
        (_totalDuration.inMilliseconds / 1000.0).toStringAsFixed(3);

    // -hwaccel none forces software decode so FFmpeg outputs standard yuv420p
    // frames.  Without it ffmpeg-kit may use Android MediaCodec (hardware) which
    // produces nv12 frames; converting nv12→yuv420p inside libswscale triggers
    // the same NEON overflow on non-16-aligned source widths.
    //
    // For un-trimmed video cells that need looping we use -stream_loop N on the
    // input instead of the in-graph `loop` filter.  -stream_loop re-reads the
    // demuxer N additional times (total = N+1 passes) without ever buffering
    // frames in RAM — unlike loop=-1:size=K which pre-allocates K frames
    // (~1-3 MB each) before it can output anything.  For a 3-min 1080p clip
    // that means 10,860 frames × 3 MB ≈ 33 GB → Android OOM kill.
    //
    // -stream_loop cannot replace the loop filter for TRIMMED clips because
    // `trim=start=S:end=E` only matches the original PTS window [S,E].
    // Subsequent demuxer iterations emit PTS in [D+S,D+E], [2D+S,2D+E] …
    // which lie outside [S,E] and are dropped, producing a dead-end stream.
    // Trimmed clips therefore still use the in-graph loop filter — but their
    // trimmed segment is typically short so the buffer cost is small.
    //
    // -noautorotate: disable FFmpeg's automatic metadata-rotation correction
    // for video inputs.  VideoPlayer corrects via RotatedBox; we replicate it
    // explicitly in the filter graph via _cellGeoVf so the two are in sync.

    // Pre-compute which cells qualify for -stream_loop (un-trimmed video cells
    // that are shorter than the total output duration).
    final streamLoopCells = <int>{};
    for (final i in nonEmpty) {
      final cell = widget.cells[i];
      if (!cell.isVideo) continue;
      final hasTrim = cell.trimEnd > Duration.zero;
      if (!hasTrim && _effectiveDuration(i) < _totalDuration) {
        streamLoopCells.add(i);
      }
    }

    final inputArgs = <String>[];
    for (final i in nonEmpty) {
      final cell = widget.cells[i];
      if (cell.isVideo) {
        if (streamLoopCells.contains(i)) {
          // How many additional passes does the demuxer need to cover durSec?
          final effMs = _effectiveDuration(i).inMilliseconds;
          final loops = (_totalDuration.inMilliseconds / effMs).ceil() + 1;
          inputArgs.addAll(['-stream_loop', '$loops', '-noautorotate', '-hwaccel', 'none', '-i', cell.filePath!]);
        } else {
          inputArgs.addAll(['-noautorotate', '-hwaccel', 'none', '-i', cell.filePath!]);
        }
      } else {
        inputArgs.addAll(['-hwaccel', 'none', '-i', cell.filePath!]);
      }
    }

    final scaleFilters = <String>[];
    final overlayChain = <String>[];
    String currentLabel = 'base';

    for (int ni = 0; ni < nonEmpty.length; ni++) {
      final i = nonEmpty[ni];
      final cell = widget.cells[i];
      final rect = widget.cellRects[i];
      final gap = widget.borderGap;
      final x = (rect.left * _outW + gap).round();
      final y = (rect.top * _outH + gap).round();
      // libx264 and libswscale require even dimensions — force to nearest even.
      final wRaw = (rect.width * _outW - gap * 2).clamp(2, _outW.toDouble()).toInt();
      final hRaw = (rect.height * _outH - gap * 2).clamp(2, _outH.toDouble()).toInt();
      final w = wRaw % 2 == 0 ? wRaw : wRaw - 1;
      final h = hRaw % 2 == 0 ? hRaw : hRaw - 1;

      final vf = (widget.cellFilterVf != null && i < widget.cellFilterVf!.length)
          ? widget.cellFilterVf![i] : null;
      final vfSuffix = (vf != null && vf.isNotEmpty) ? ',$vf' : '';
      final speed    = _cellSpeed(i);
      final speedStr = speed.toStringAsFixed(6);
      final hasTrim  = cell.isVideo && cell.trimEnd > Duration.zero;
      final trimS    = (cell.trimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
      final trimE    = (cell.trimEnd.inMilliseconds   / 1000.0).toStringAsFixed(3);

      // Discrete rotation + flip: user-set rotation combined with the native
      // metadata rotation (see _cellGeoVf). Applied before scale so that the
      // cover-mode scale+crop operates on the already-rotated content.
      final geo = _cellGeoVf(i, isVideo: cell.isVideo);
      final geoPrefix = geo.isNotEmpty ? '$geo,' : '';

      // scale+crop filter incorporating user zoom, free-angle rotation and pan.
      final scaleCrop = _cellScaleCrop(i, w, h);

      // Apply the in-graph loop filter only for TRIMMED clips that are shorter
      // than the total output.  Un-trimmed looping clips use -stream_loop on
      // the input (see inputArgs above) and need no loop filter here.
      //
      // loopSize is sized by widget.fps (not a hardcoded 60) so the ring buffer
      // holds exactly the frames in one effective-duration pass at the output
      // frame rate.  For a 5-second trimmed clip at 30 fps that is only
      // (5+1)×30 = 180 frames ≈ 250 MB — far safer than the old 60-fps formula
      // which allocated 10,860 frames for a 3-minute clip (≈ 33 GB → OOM).
      final needsLoop = cell.isVideo &&
          _effectiveDuration(i) < _totalDuration &&
          !streamLoopCells.contains(i);
      final loopSize  = needsLoop
          ? min(32767, max(2, (_effectiveDuration(i).inSeconds + 1) * widget.fps))
          : 0;
      final loopStr   = needsLoop ? 'loop=-1:size=$loopSize,' : '';

      // Pipeline: [trim] → [speed] → [loop if needed] → cut to durSec → geo → scale/crop
      //
      // format=yuv420p is placed BEFORE geo/scale so that libswscale always
      // receives a uniform pixel format.  Geo (rotate/flip) is applied BEFORE
      // scale+crop so that the cover fill targets the rotated content's aspect.
      if (!cell.isVideo) {
        // Image / still: a single frame must be looped for the full duration.
        // One frame ≈ 1.35 MB — the 32767-slot ring buffer has negligible cost.
        scaleFilters.add(
          '[$ni:v]loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (hasTrim && speed != 1.0) {
        scaleFilters.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=(PTS-STARTPTS)/$speedStr,'
          '$loopStr'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (hasTrim) {
        scaleFilters.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=PTS-STARTPTS,'
          '$loopStr'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (speed != 1.0) {
        scaleFilters.add(
          '[$ni:v]setpts=(PTS-STARTPTS)/$speedStr,'
          '$loopStr'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else {
        scaleFilters.add(
          '[$ni:v]$loopStr'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      }

      final isLast = ni == nonEmpty.length - 1;
      final outLabel = isLast ? 'out' : 'oc$ni';
      overlayChain.add('[$currentLabel][vs$ni]overlay=$x:$y[$outLabel]');
      currentLabel = outLabel;
    }

    final baseFilter =
        'color=${_bgHex()}:size=${_outW}x$_outH:duration=$durSec[base]';
    final filterParts = [baseFilter, ...scaleFilters, ...overlayChain];

    // ── Cell audio filters (parallel: each cell plays for its natural length) ──
    final cellAudioLabels = <String>[];
    for (int ni = 0; ni < nonEmpty.length; ni++) {
      final i = nonEmpty[ni];
      final cell = widget.cells[i];
      if (!cell.isVideo || _cellHasAudio[i] != true) continue;
      final speed = _cellSpeed(i);
      final vol = _cellVol(i);
      final hasTrim = cell.trimEnd > Duration.zero;
      final trimS = (cell.trimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
      final trimE = (cell.trimEnd.inMilliseconds / 1000.0).toStringAsFixed(3);
      final tempo = _audioTempoStr(speed);
      final volStr = vol.toStringAsFixed(4);
      final label = 'ca$ni';
      if (hasTrim) {
        filterParts.add(
          '[$ni:a]atrim=start=$trimS:end=$trimE,asetpts=PTS-STARTPTS$tempo,volume=$volStr[$label]',
        );
      } else {
        filterParts.add(
          '[$ni:a]asetpts=PTS-STARTPTS$tempo,volume=$volStr[$label]',
        );
      }
      cellAudioLabels.add('[$label]');
    }

    // Mix cell audio streams → cellMixLabel
    String? cellMixLabel;
    if (cellAudioLabels.length == 1) {
      cellMixLabel = cellAudioLabels.first;
    } else if (cellAudioLabels.length > 1) {
      filterParts.add(
        '${cellAudioLabels.join('')}amix=inputs=${cellAudioLabels.length}:duration=longest:normalize=0[camix]',
      );
      cellMixLabel = '[camix]';
    }

    final hasBgAudio = widget.audioPath != null;
    final audioIn = _audioArgs(nonEmpty.length, durSec);
    final bgAudioIdx = nonEmpty.length;

    // Determine final audio label / mapping strategy
    String? finalAudioLabel;
    if (cellMixLabel != null && hasBgAudio) {
      // Mix cell audio with background audio (apply bg volume in filter)
      final bgVolStr = widget.audioVolume.toStringAsFixed(4);
      filterParts.add('[$bgAudioIdx:a]volume=$bgVolStr[bgvol]');
      filterParts.add('$cellMixLabel[bgvol]amix=inputs=2:normalize=0[faudio]');
      finalAudioLabel = '[faudio]';
    } else if (cellMixLabel != null) {
      finalAudioLabel = cellMixLabel;
    }
    // else: hasBgAudio only → fallback to legacy -map bgAudioIdx:a below

    final filterComplex = filterParts.join(';');
    final hasAnyAudio = finalAudioLabel != null || hasBgAudio;

    return [
      // Global thread limits must come before any -i input.
      // -threads 1        → encoder/decoder thread count
      // -filter_threads 1 → filter graph (libavutil) thread pool
      // Without these, libswscale spawns worker threads and crashes with
      // SEGV_ACCERR when two threads write to adjacent buffer pages.
      '-threads', '1',
      '-filter_threads', '1',
      ...inputArgs,
      ...audioIn,
      '-filter_complex', filterComplex,
      '-map', '[out]',
      if (finalAudioLabel != null) ...['-map', finalAudioLabel],
      if (finalAudioLabel == null && hasBgAudio) ...['-map', '$bgAudioIdx:a'],
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-crf', widget.crf.toString(),
      '-preset', 'ultrafast',
      '-r', widget.fps.toString(),
      if (widget.faststart) ...['-movflags', '+faststart'],
      if (hasAnyAudio) ...['-c:a', 'aac', '-b:a', '128k'],
      if (finalAudioLabel == null && hasBgAudio) ...['-af', 'volume=${widget.audioVolume}'],
      '-t', durSec,
      '-y', outPath,
    ];
  }

  // ── Sequential export ──────────────────────────────────────────────────────
  //
  // One input per cell. Each clip is positioned at its cumulative time offset
  // using setpts. The canvas overlay uses enable='between(t,start,end)' so
  // only the active cell is visible at any moment; other cell areas show the
  // background colour.  Total output duration = sum of all clip durations.

  List<String> _buildSequentialArgs(List<int> nonEmpty, String outPath) {
    // Per-cell effective durations in seconds
    double totalSec = 0;
    final dursSec = <int, double>{};
    for (final i in nonEmpty) {
      dursSec[i] = _effectiveDuration(i).inMicroseconds / 1000000.0;
      totalSec += dursSec[i]!;
    }
    if (totalSec == 0) totalSec = 10.0;
    final totalDurSec = totalSec.toStringAsFixed(3);

    // One input per cell — software decode forced (same reason as parallel mode).
    // -noautorotate disables metadata-rotation correction for video inputs;
    // _cellGeoVf folds the native rotation in explicitly so preview and export
    // stay in sync.
    final inputArgs = <String>[];
    for (final i in nonEmpty) {
      if (widget.cells[i].isVideo) {
        inputArgs.addAll(['-noautorotate', '-hwaccel', 'none', '-i', widget.cells[i].filePath!]);
      } else {
        inputArgs.addAll(['-hwaccel', 'none', '-i', widget.cells[i].filePath!]);
      }
    }

    final filterParts = <String>[];
    double offsetSec = 0;

    for (int ni = 0; ni < nonEmpty.length; ni++) {
      final i = nonEmpty[ni];
      final cell = widget.cells[i];
      final rect = widget.cellRects[i];
      final gap = widget.borderGap;
      // libx264 and libswscale require even dimensions — force to nearest even.
      final wRaw = (rect.width * _outW - gap * 2).clamp(2, _outW.toDouble()).toInt();
      final hRaw = (rect.height * _outH - gap * 2).clamp(2, _outH.toDouble()).toInt();
      final w = wRaw % 2 == 0 ? wRaw : wRaw - 1;
      final h = hRaw % 2 == 0 ? hRaw : hRaw - 1;

      final durSec  = dursSec[i]!.toStringAsFixed(3);
      final offsetStr = offsetSec.toStringAsFixed(3);

      final vf = (widget.cellFilterVf != null && i < widget.cellFilterVf!.length)
          ? widget.cellFilterVf![i] : null;
      final vfSuffix = (vf != null && vf.isNotEmpty) ? ',$vf' : '';
      final speed    = _cellSpeed(i);
      final speedStr = speed.toStringAsFixed(6);
      final hasTrim  = cell.isVideo && cell.trimEnd > Duration.zero;
      final trimS    = (cell.trimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
      final trimE    = (cell.trimEnd.inMilliseconds   / 1000.0).toStringAsFixed(3);
      final geo      = _cellGeoVf(i, isVideo: cell.isVideo);
      final geoPrefix = geo.isNotEmpty ? '$geo,' : '';

      // scale+crop filter incorporating user zoom, free-angle rotation and pan.
      final scaleCrop = _cellScaleCrop(i, w, h);

      // Build per-cell filter: decode → trim/speed → geo → scale/crop → time-offset
      // format=yuv420p BEFORE geo/scale, 32-aligned target, crop to exact dimensions.
      if (!cell.isVideo) {
        // Image / GIF: loop for the slot duration then place at offset
        filterParts.add(
          '[$ni:v]loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (hasTrim && speed != 1.0) {
        filterParts.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=(PTS-STARTPTS)/$speedStr+$offsetStr/TB,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (hasTrim) {
        filterParts.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else if (speed != 1.0) {
        filterParts.add(
          '[$ni:v]setpts=(PTS-STARTPTS)/$speedStr+$offsetStr/TB,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      } else {
        filterParts.add(
          '[$ni:v]setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          '$geoPrefix$scaleCrop$vfSuffix[vs$ni]',
        );
      }

      // ── Cell audio for this slot (sequential) ─────────────────────────────
      // Audio is trimmed, speed-adjusted, then delayed to start at the slot's
      // time offset.  adelay values are in milliseconds, one per channel.
      if (cell.isVideo && _cellHasAudio[i] == true) {
        final speed = _cellSpeed(i);
        final vol = _cellVol(i);
        final hasTrimA = cell.trimEnd > Duration.zero;
        final aTrimS = (cell.trimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
        final aTrimE = (cell.trimEnd.inMilliseconds / 1000.0).toStringAsFixed(3);
        final tempo = _audioTempoStr(speed);
        final volStr = vol.toStringAsFixed(4);
        final delayMs = (offsetSec * 1000).round();
        final delayStr = '$delayMs|$delayMs';
        if (hasTrimA) {
          filterParts.add(
            '[$ni:a]atrim=start=$aTrimS:end=$aTrimE,asetpts=PTS-STARTPTS$tempo,adelay=$delayStr,volume=$volStr[sca$ni]',
          );
        } else {
          filterParts.add(
            '[$ni:a]asetpts=PTS-STARTPTS$tempo,adelay=$delayStr,volume=$volStr[sca$ni]',
          );
        }
      }

      offsetSec += dursSec[i]!;
    }

    // Canvas: background base + per-cell overlay active only during its slot.
    // When a cell is not enabled the overlay passes the base straight through,
    // so that area shows the background colour.
    filterParts.add(
      'color=${_bgHex()}:size=${_outW}x$_outH:duration=$totalDurSec[base]',
    );
    String currentLabel = 'base';
    double off2 = 0;
    for (int ni = 0; ni < nonEmpty.length; ni++) {
      final i = nonEmpty[ni];
      final rect = widget.cellRects[i];
      final gap  = widget.borderGap;
      final x    = (rect.left * _outW + gap).round();
      final y    = (rect.top  * _outH + gap).round();
      final startStr = off2.toStringAsFixed(3);
      final endStr   = (off2 + dursSec[i]!).toStringAsFixed(3);
      final isLast   = ni == nonEmpty.length - 1;
      final outLabel = isLast ? 'out' : 'oc$ni';
      filterParts.add(
        "[$currentLabel][vs$ni]overlay=$x:$y:enable='between(t,$startStr,$endStr)'[$outLabel]",
      );
      currentLabel = outLabel;
      off2 += dursSec[i]!;
    }

    // ── Mix cell audio labels ─────────────────────────────────────────────
    final cellAudioLabels = <String>[];
    for (int ni = 0; ni < nonEmpty.length; ni++) {
      final i = nonEmpty[ni];
      if (widget.cells[i].isVideo && _cellHasAudio[i] == true) {
        cellAudioLabels.add('[sca$ni]');
      }
    }

    String? cellMixLabel;
    if (cellAudioLabels.length == 1) {
      cellMixLabel = cellAudioLabels.first;
    } else if (cellAudioLabels.length > 1) {
      filterParts.add(
        '${cellAudioLabels.join('')}amix=inputs=${cellAudioLabels.length}:duration=longest:normalize=0[scamix]',
      );
      cellMixLabel = '[scamix]';
    }

    final hasBgAudio = widget.audioPath != null;
    final audioIn = _audioArgs(nonEmpty.length, totalDurSec);
    final bgAudioIdx = nonEmpty.length;

    String? finalAudioLabel;
    if (cellMixLabel != null && hasBgAudio) {
      final bgVolStr = widget.audioVolume.toStringAsFixed(4);
      filterParts.add('[$bgAudioIdx:a]volume=$bgVolStr[sbgvol]');
      filterParts.add('$cellMixLabel[sbgvol]amix=inputs=2:normalize=0[sfaudio]');
      finalAudioLabel = '[sfaudio]';
    } else if (cellMixLabel != null) {
      finalAudioLabel = cellMixLabel;
    }

    final filterComplex = filterParts.join(';');
    final hasAnyAudio = finalAudioLabel != null || hasBgAudio;

    return [
      '-threads', '1',
      '-filter_threads', '1',
      ...inputArgs,
      ...audioIn,
      '-filter_complex', filterComplex,
      '-map', '[out]',
      if (finalAudioLabel != null) ...['-map', finalAudioLabel],
      if (finalAudioLabel == null && hasBgAudio) ...['-map', '$bgAudioIdx:a'],
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-crf', widget.crf.toString(),
      '-preset', 'ultrafast',
      '-r', widget.fps.toString(),
      if (widget.faststart) ...['-movflags', '+faststart'],
      if (hasAnyAudio) ...['-c:a', 'aac', '-b:a', '128k'],
      if (finalAudioLabel == null && hasBgAudio) ...['-af', 'volume=${widget.audioVolume}'],
      '-t', totalDurSec,
      '-y', outPath,
    ];
  }

  Future<void> _exportCollage() async {
    if (_exportState == _ExportState.exporting) return;

    // Collect non-empty cells
    final nonEmpty = <int>[];
    for (int i = 0; i < widget.cells.length; i++) {
      if (!widget.cells[i].isEmpty) nonEmpty.add(i);
    }
    if (nonEmpty.isEmpty) {
      setState(() {
        _exportState = _ExportState.error;
        _exportError = 'No media in cells';
      });
      return;
    }

    setState(() {
      _exportState = _ExportState.exporting;
      _exportProgress = 0.0;
      _exportError = null;
    });
    ExportProgressState.instance.start();
    _pauseAll();

    // Dispose VideoPlayerControllers to release the hardware HEVC/AVC decoder
    // before FFmpeg runs. Both video_player and FFmpeg compete for the same
    // MediaCodec hardware decoder; keeping controllers alive causes a SIGSEGV
    // (SEGV_ACCERR) in FFmpeg's thread pool at ~20% progress.
    //
    // Order matters to avoid "Bad state: No active player" errors:
    //  1. Copy controllers to a local map and clear the shared map FIRST
    //     (synchronous, no await) so the next rebuild sees an empty map.
    //  2. Call setState to mark the widget dirty and schedule a rebuild.
    //  3. Wait for that frame to finish – VideoPlayer widgets are now gone.
    //  4. Only then dispose the native resources.
    // Snapshot rotationCorrection BEFORE clearing the controller map.
    // _buildParallelArgs / _buildSequentialArgs call _cellGeoVf which needs
    // these values, but those builders run after the controllers are disposed.
    for (final entry in widget.videoControllers.entries) {
      _rotCorrSnapshot[entry.key] = entry.value.value.rotationCorrection;
    }

    final controllersToDispose =
        Map<int, VideoPlayerController>.from(widget.videoControllers);
    final controllerKeys = List<int>.unmodifiable(controllersToDispose.keys);
    widget.videoControllers.clear();
    if (mounted) setState(() {});
    if (mounted) await WidgetsBinding.instance.endOfFrame;
    for (final vc in controllersToDispose.values) {
      await vc.dispose();
    }

    // Flag set to true when we navigate to ExportResultScreen so that the
    // finally block skips reinitialising controllers while that screen is open.
    // Reinit is deferred until after the user pops back (see success path below)
    // to avoid having ExportResultScreen's VideoPlayer and the cell controllers
    // all initialise simultaneously — that causes OOM / MediaCodec contention.
    bool exportNavigated = false;

    try {
      // Request gallery access
      final hasAccess = await Gal.requestAccess(toAlbum: true);
      if (!hasAccess && mounted) {
        setState(() {
          _exportState = _ExportState.error;
          _exportError = 'Gallery access denied';
        });
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final outPath =
          '${tmpDir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.${widget.format}';

      // Probe each video cell for audio streams so the FFmpeg filter graph
      // can map only inputs that actually have audio (avoids "no such stream" errors).
      await _probeAudioStreams(nonEmpty);

      // Start foreground service so the OS keeps our process alive
      // even if the user switches to another app during export.
      await ExportServiceManager.start();

      // Animate a fake progress bar (FFmpegKit doesn't expose per-frame progress
      // via executeWithArguments, so we approach 90% asymptotically).
      _startFakeProgress();

      final args = _previewMode == _PreviewMode.sequential
          ? _buildSequentialArgs(nonEmpty, outPath)
          : _buildParallelArgs(nonEmpty, outPath);

      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();

      // Cancel the fake-progress timer BEFORE stopping the service so it
      // cannot fire after stopExportService and inadvertently restart the
      // service via an ACTION_UPDATE startService() call.
      _fakeProgressTimer?.cancel();

      // Always stop the foreground service when FFmpeg finishes.
      await ExportServiceManager.stop();

      if (!mounted) return;

      if (ReturnCode.isSuccess(rc)) {
        // Navigate to ExportResultScreen which handles gallery save + sharing.
        // Do NOT delete the temp file here — ExportResultScreen owns its lifetime.
        if (mounted) {
          setState(() {
            _exportState = _ExportState.idle;
            _exportProgress = 0.0;
          });
          ExportProgressState.instance.finish();
          // Mark before push so finally block skips reinit while the result
          // screen is open (prevents OOM from simultaneous decoder allocation).
          exportNavigated = true;
          // Generate and persist thumbnail from the exported video.
          await _updateDraftThumbnail(outPath);
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExportResultScreen(videoPath: outPath),
            ),
          );
          // User has returned from ExportResultScreen — clean up temp file then
          // reinitialise controllers so the preview is usable again.
          try { File(outPath).deleteSync(); } catch (_) {}
          if (mounted) {
            for (final i in controllerKeys) {
              final cell = widget.cells[i];
              if (!cell.isEmpty && cell.isVideo) {
                final vc = VideoPlayerController.file(File(cell.filePath!));
                try {
                  await vc.initialize();
                  vc.setLooping(false);
                  widget.videoControllers[i] = vc;
                } catch (_) {}
              }
            }
            setState(() {});
          }
        }
      } else {
        final logs = await session.getLogs();
        final lastLog =
            logs.isNotEmpty ? logs.last.getMessage() : 'Unknown error';
        ExportProgressState.instance.finish();
        setState(() {
          _exportState = _ExportState.error;
          _exportError = lastLog;
        });
      }
    } catch (e) {
      await ExportServiceManager.stop();
      ExportProgressState.instance.finish();
      if (mounted) {
        setState(() {
          _exportState = _ExportState.error;
          _exportError = e.toString();
        });
      }
    } finally {
      // Reinitialise video controllers on error / exception paths.
      // Skipped on success because reinit already happened above (after the
      // user returned from ExportResultScreen) to prevent OOM.
      if (mounted && !exportNavigated) {
        for (final i in controllerKeys) {
          final cell = widget.cells[i];
          if (!cell.isEmpty && cell.isVideo) {
            final vc = VideoPlayerController.file(File(cell.filePath!));
            try {
              await vc.initialize();
              vc.setLooping(false);
              widget.videoControllers[i] = vc;
            } catch (_) {}
          }
        }
        setState(() {});
      }
    }
  }

  /// Extracts a frame from [videoPath] at t=0 and updates the collage draft's
  /// thumbnailPath. No-op if [widget.draftId] is null.
  Future<void> _updateDraftThumbnail(String videoPath) async {
    final id = widget.draftId;
    if (id == null) return;
    try {
      final draft = await CollageDraftManager.instance.load(id);
      if (draft == null) return;

      final dir = await getTemporaryDirectory();
      final destPath = '${dir.path}/collage_thumb_$id.jpg';

      final result = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: destPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        maxWidth: 400,
        quality: 80,
      );
      if (result == null) return;
      final thumbFile = File(result);
      if (!thumbFile.existsSync() || thumbFile.lengthSync() == 0) return;

      await CollageDraftManager.instance.save(
        draft.copyWith(thumbnailPath: result),
      );
    } catch (_) {
      // Thumbnail generation is non-fatal.
    }
  }

  Timer? _fakeProgressTimer;

  void _startFakeProgress() {
    _fakeProgressTimer?.cancel();
    _fakeProgressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _exportState != _ExportState.exporting) {
        _fakeProgressTimer?.cancel();
        return;
      }
      // Approach 0.9 asymptotically — real completion sets it to 1.0
      final next = _exportProgress + (0.9 - _exportProgress) * 0.08;
      setState(() => _exportProgress = next);
      // Keep global progress state and the notification in sync.
      ExportProgressState.instance.update(next);
      ExportServiceManager.updateProgress(next);
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  String get _elapsedStr {
    final s = _elapsed.inSeconds;
    final totalS = _totalDuration.inSeconds;
    String fmt(int secs) =>
        '${(secs ~/ 60).toString().padLeft(2, '0')}:'
        '${(secs % 60).toString().padLeft(2, '0')}';
    return '${fmt(s)} / ${fmt(totalS)}';
  }

  String _fmtSeekPos(double fraction) {
    final seekUs =
        (_totalDuration.inMicroseconds * fraction.clamp(0.0, 1.0)).round();
    final seekS = Duration(microseconds: seekUs).inSeconds;
    final totalS = _totalDuration.inSeconds;
    String fmt(int secs) =>
        '${(secs ~/ 60).toString().padLeft(2, '0')}:'
        '${(secs % 60).toString().padLeft(2, '0')}';
    return '${fmt(seekS)} / ${fmt(totalS)}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalDuration.inMilliseconds > 0
        ? (_elapsed.inMilliseconds / _totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    // Compute ring size at the screen level — always large regardless of
    // how inner layout constraints propagate through the widget tree.
    final ringSize = MediaQuery.of(context).size.shortestSide * 0.55;

    final exporting = _exportState == _ExportState.exporting;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main content column ────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),

                // Canvas is letterboxed to the exact output aspect ratio so
                // the preview matches the exported video.
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      final targetAR = widget.outW / widget.outH;
                      final availW   = constraints.maxWidth;
                      final availH   = constraints.maxHeight;
                      final double canvasW;
                      final double canvasH;
                      if (availW / availH > targetAR) {
                        canvasH = availH;
                        canvasW = availH * targetAR;
                      } else {
                        canvasW = availW;
                        canvasH = availW / targetAR;
                      }
                      return Center(
                        child: SizedBox(
                          width:  canvasW,
                          height: canvasH,
                          child:  _buildCanvas(canvasW, canvasH),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // Time labels + seek bar + play button row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Play / Pause button
                      GestureDetector(
                        onTap: (exporting ||
                                _previewMode == _PreviewMode.manual)
                            ? null
                            : _togglePlay,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Icon(
                            _previewMode == _PreviewMode.manual
                                ? Icons.touch_app_outlined
                                : _playing
                                    ? Icons.pause
                                    : Icons.play_arrow,
                            color: _previewMode == _PreviewMode.manual
                                ? Colors.white30
                                : Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Seek slider + time label
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                thumbColor: _kOrange,
                                activeTrackColor: _kOrange,
                                inactiveTrackColor: const Color(0xFF333333),
                                overlayColor: _kOrange.withValues(alpha: 0.25),
                                trackShape: const RectangularSliderTrackShape(),
                              ),
                              child: Slider(
                                value: _isSeeking ? _seekFraction : progress,
                                min: 0,
                                max: 1,
                                onChangeStart: _previewMode == _PreviewMode.manual
                                    ? null
                                    : (v) {
                                        setState(() {
                                          _isSeeking = true;
                                          _seekFraction = progress;
                                        });
                                        if (_playing) _pauseAll();
                                      },
                                onChanged: _previewMode == _PreviewMode.manual
                                    ? null
                                    : (v) => setState(() => _seekFraction = v),
                                onChangeEnd: _previewMode == _PreviewMode.manual
                                    ? null
                                    : (v) {
                                        setState(() => _isSeeking = false);
                                        _seekTo(v);
                                      },
                              ),
                            ),
                            Text(
                              _isSeeking
                                  ? _fmtSeekPos(_seekFraction)
                                  : _elapsedStr,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _buildPreviewModeSection(),
                const SizedBox(height: 10),
                _buildExportSection(),
                const SizedBox(height: 14),
              ],
            ),

            // ── Full-screen export overlay ─────────────────────────────────
            // Lives at the SafeArea Stack level so it covers the ENTIRE screen,
            // not just the canvas Expanded area.
            IgnorePointer(
              ignoring: !exporting,
              child: AnimatedOpacity(
                opacity: exporting ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black87,
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: AnimatedScale(
                      scale: exporting ? 1.0 : 0.65,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutBack,
                      child: SizedBox(
                        width:  ringSize,
                        height: ringSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Positioned.fill gives tight constraints so the
                            // indicator fills the full SizedBox (not 36dp default).
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                value: _exportProgress < 0.05
                                    ? null
                                    : _exportProgress,
                                strokeWidth: ringSize * 0.07,
                                color: _kOrange,
                                backgroundColor: const Color(0xFF333333),
                              ),
                            ),
                            Text(
                              '${(_exportProgress * 100).toInt()}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: ringSize * 0.22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewModeSection() {
    const cards = [
      (
        mode: _PreviewMode.parallel,
        label: 'Parallel',
        desc: 'All clips at once · loop to longest',
      ),
      (
        mode: _PreviewMode.sequential,
        label: 'Sequential',
        desc: 'One after another · single timeline',
      ),
      (
        mode: _PreviewMode.manual,
        label: 'Manual',
        desc: 'Tap each clip individually to play',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: const Text(
            'Play mode',
            style: TextStyle(
              color: Color(0xFF9B7FD4),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: cards.map((c) {
              final active = _previewMode == c.mode;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _setPreviewMode(c.mode),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(
                              colors: [Color(0xFF7B3FCC), Color(0xFFAB5FD8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: active ? null : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(14),
                      border: active
                          ? null
                          : Border.all(
                              color: const Color(0xFF333333), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.label,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.desc,
                          style: TextStyle(
                            color: active ? Colors.white60 : Colors.white30,
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Preview',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
          // Placeholder to center the title
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    switch (_exportState) {
      case _ExportState.idle:
        return _buildSaveButton();

      case _ExportState.exporting:
        return _buildExportingIndicator();

      case _ExportState.error:
        return _buildErrorState();
    }
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Main save button with bounce on tap
          ScaleTransition(
            scale: _saveBounceAnim,
            child: GestureDetector(
              onTap: () {
                _saveBounceCtrl.forward(from: 0.0);
                _exportCollage();
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kPurple, Color(0xFF9B55E8)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_alt_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Save to Gallery',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Video will be saved to your gallery',
            style: TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildExportingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: _exportProgress < 0.05 ? null : _exportProgress,
                    strokeWidth: 2.5,
                    color: _kOrange,
                    backgroundColor: const Color(0xFF444444),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Exporting… ${(_exportProgress * 100).toInt()}%',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _exportProgress,
              backgroundColor: const Color(0xFF333333),
              color: _kOrange,
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade700, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _exportError ?? 'Export failed',
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _exportCollage,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Try again',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Canvas ─────────────────────────────────────────────────────────────────

  Widget _buildCanvas(double canvasW, double canvasH) {
    final gap = widget.borderGap;
    return Stack(
      children: [
        Container(color: widget.bgColor),
        ...List.generate(widget.cells.length, (i) {
          final normRect = widget.cellRects[i];
          final cell = widget.cells[i];
          if (cell.isEmpty) return const SizedBox();

          final left = normRect.left * canvasW + gap;
          final top = normRect.top * canvasH + gap;
          final width = normRect.width * canvasW - gap * 2;
          final height = normRect.height * canvasH - gap * 2;

          Widget content = ClipRect(child: _buildCellContent(i, cell));

          if (_previewMode == _PreviewMode.manual) {
            final isPlaying = _manualPlaying.contains(i);
            content = GestureDetector(
              onTap: () => _toggleCellPlay(i),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  if (!isPlaying)
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 24),
                      ),
                    ),
                ],
              ),
            );
          }

          return Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: content,
          );
        }),
      ],
    );
  }

  Widget _buildCellContent(int index, CollageCellData cell) {
    final cf = (widget.cellColorFilters != null &&
            index < widget.cellColorFilters!.length)
        ? widget.cellColorFilters![index]
        : null;
    final rot = _cellRot(index);
    final fH  = _cellFH(index);
    final fV  = _cellFV(index);

    Widget wrap(Widget media) =>
        cf != null ? ColorFiltered(colorFilter: cf, child: media) : media;

    // Apply the full cell transform matching the editor's _cellMatrix:
    //   translate(pan) → scale(userZoom × coverScale) → rotateZ(fullAngle) → flip
    // coverScale ensures the content keeps filling the cell after rotation.
    Widget applyGeo(Widget w, double cellW, double cellH) {
      final userAngle = _cellUserAngle(index);
      final userS     = _cellUserScale(index);
      final normOffX  = _cellNormOffX(index);
      final normOffY  = _cellNormOffY(index);
      final fullAngle = userAngle + rot * pi / 2;

      final hasTransform = fullAngle != 0.0 || fH || fV ||
          userS != 1.0 || normOffX != 0.0 || normOffY != 0.0;
      if (!hasTransform) return w;

      final abscos = cos(fullAngle).abs();
      final abssin = sin(fullAngle).abs();
      final ar     = (cellH > 0 && cellW > 0) ? cellW / cellH : 1.0;
      final maxAR  = ar > 1.0 ? ar : 1.0 / ar;
      final cScale = abscos + maxAR * abssin; // always ≥ 1; equals 1 at 0°/180°

      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(normOffX * cellW, normOffY * cellH)
          ..scale(userS * cScale)
          ..rotateZ(fullAngle)
          ..scale(fH ? -1.0 : 1.0, fV ? -1.0 : 1.0),
        child: w,
      );
    }

    if (cell.isVideo) {
      if (widget.videoControllers.containsKey(index)) {
        final vc = widget.videoControllers[index]!;
        // Use raw frame dimensions so the Android SurfaceTexture matches
        // the encoded frame size — no squishing. VideoPlayer applies
        // Transform.rotate internally for rotationCorrection.
        return wrap(LayoutBuilder(
          builder: (context, constraints) => applyGeo(
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width:  vc.value.size.width,
                height: vc.value.size.height,
                child: VideoPlayer(vc),
              ),
            ),
            constraints.maxWidth,
            constraints.maxHeight,
          ),
        ));
      }
      // Controller not available (disposed before export) — show black placeholder
      return wrap(Container(color: Colors.black));
    }
    // Image: FittedBox(cover, clipBehavior: none) scales the image to cover
    // the cell but does NOT clip overflow, so applyGeo's translate can pan
    // into the natural overflow area without exposing black edges.
    return wrap(LayoutBuilder(
      builder: (context, constraints) => applyGeo(
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.none,
          child: Image.file(File(cell.filePath!)),
        ),
        constraints.maxWidth,
        constraints.maxHeight,
      ),
    ));
  }
}

enum _ExportState { idle, exporting, error }

enum _PreviewMode { parallel, sequential, manual }
