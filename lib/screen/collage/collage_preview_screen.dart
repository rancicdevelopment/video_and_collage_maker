import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'collage_models.dart';
import '../../service/export_service_manager.dart';

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

  // Per-cell FFmpeg vf filter strings (null = no filter)
  final List<String?>? cellFilterVf;

  // Per-cell ColorFilter for live preview (null = no filter)
  final List<ColorFilter?>? cellColorFilters;

  // Per-cell playback speed (1.0 = normal)
  final List<double>? cellSpeeds;

  // Per-cell audio volume (1.0 = full, 0.0 = muted)
  final List<double>? cellVolumes;

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
    this.cellFilterVf,
    this.cellColorFilters,
    this.cellSpeeds,
    this.cellVolumes,
  });

  @override
  State<CollagePreviewScreen> createState() => _CollagePreviewScreenState();
}

class _CollagePreviewScreenState extends State<CollagePreviewScreen> {
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

  // Per-cell audio presence (populated by _probeAudioStreams before export)
  final Map<int, bool> _cellHasAudio = {};

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
    if (_previewMode != _PreviewMode.manual) {
      // Delay until after the first frame so VideoPlayer widgets are built
      // and the controllers from the editor have settled after _pauseAll().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playAll();
      });
    }
  }

  @override
  void dispose() {
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

  // ── Parallel / Manual export ───────────────────────────────────────────────

  List<String> _buildParallelArgs(List<int> nonEmpty, String outPath) {
    final durSec =
        (_totalDuration.inMilliseconds / 1000.0).toStringAsFixed(3);

    // Plain inputs — no -stream_loop. Looping is done inside filter_complex
    // via the `loop` filter applied AFTER trim so the trimmed segment loops,
    // not the whole file. (-stream_loop with trim only passes frames from the
    // first iteration because trim matches PTS in [S,E] and subsequent loop
    // iterations produce PTS in [D+S,D+E], [2D+S,2D+E] … outside [S,E].)
    // -hwaccel none forces software decode so FFmpeg outputs standard yuv420p
    // frames.  Without it ffmpeg-kit may use Android MediaCodec (hardware) which
    // produces nv12 frames; converting nv12→yuv420p inside libswscale triggers
    // the same NEON overflow on non-16-aligned source widths.
    final inputArgs = <String>[];
    for (final i in nonEmpty) {
      inputArgs.addAll(['-hwaccel', 'none', '-i', widget.cells[i].filePath!]);
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

      // Round the scale TARGET up to the next multiple of 16 so that
      // libswscale's NEON kernels (which write in 16-pixel blocks) never
      // write past the end of the allocated output buffer.  On Android 16
      // devices (e.g. Samsung Galaxy S24) the allocator places hardware guard
      // pages immediately after each allocation; any overshoot causes a
      // SIGSEGV (SEGV_ACCERR, code 2) at the page boundary.  The trailing
      // crop=w:h trims the extra pixels introduced by the alignment padding.
      final scaleW = ((w + 15) ~/ 16) * 16;
      final scaleH = ((h + 15) ~/ 16) * 16;

      final vf = (widget.cellFilterVf != null && i < widget.cellFilterVf!.length)
          ? widget.cellFilterVf![i] : null;
      final vfSuffix = (vf != null && vf.isNotEmpty) ? ',$vf' : '';
      final speed    = _cellSpeed(i);
      final speedStr = speed.toStringAsFixed(6);
      final hasTrim  = cell.isVideo && cell.trimEnd > Duration.zero;
      final trimS    = (cell.trimStart.inMilliseconds / 1000.0).toStringAsFixed(3);
      final trimE    = (cell.trimEnd.inMilliseconds   / 1000.0).toStringAsFixed(3);

      // Pipeline: [trim] → [speed] → loop(-1,32767) → cut to durSec → scale/crop
      // loop(-1,32767) buffers ≤32767 frames then replays them indefinitely;
      // the trailing trim=end=durSec + setpts caps the stream at output length.
      //
      // format=yuv420p is placed BEFORE scale so that libswscale always receives
      // a uniform pixel format.  scale uses $scaleW:$scaleH (16-aligned) and
      // crop trims back to the exact $w:$h cell dimensions.
      if (!cell.isVideo) {
        scaleFilters.add(
          '[$ni:v]loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (hasTrim && speed != 1.0) {
        scaleFilters.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=(PTS-STARTPTS)/$speedStr,'
          'loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (hasTrim) {
        scaleFilters.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=PTS-STARTPTS,'
          'loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (speed != 1.0) {
        scaleFilters.add(
          '[$ni:v]setpts=(PTS-STARTPTS)/$speedStr,'
          'loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else {
        scaleFilters.add(
          '[$ni:v]loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
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
      if (hasAnyAudio) ...['-c:a', 'aac', '-b:a', '128k'],
      // Volume for standalone background audio (cell audio already has vol in filter)
      if (finalAudioLabel == null && hasBgAudio) ...['-af', 'volume=${widget.audioVolume}'],
      '-preset', 'ultrafast',
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

    // One input per cell — software decode forced (same reason as parallel mode)
    final inputArgs = <String>[];
    for (final i in nonEmpty) {
      inputArgs.addAll(['-hwaccel', 'none', '-i', widget.cells[i].filePath!]);
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

      // 16-aligned scale target — see _buildParallelArgs for full explanation.
      final scaleW = ((w + 15) ~/ 16) * 16;
      final scaleH = ((h + 15) ~/ 16) * 16;

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

      // Build per-cell filter: decode → trim/speed → scale/crop → time-offset
      // setpts formula: (normalised_PTS / optional_speed) + offset_in_TB_units
      // format=yuv420p BEFORE scale, 16-aligned target, crop to exact dimensions.
      if (!cell.isVideo) {
        // Image / GIF: loop for the slot duration then place at offset
        filterParts.add(
          '[$ni:v]loop=-1:size=32767,'
          'trim=end=$durSec,setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (hasTrim && speed != 1.0) {
        filterParts.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=(PTS-STARTPTS)/$speedStr+$offsetStr/TB,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (hasTrim) {
        filterParts.add(
          '[$ni:v]trim=start=$trimS:end=$trimE,'
          'setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else if (speed != 1.0) {
        filterParts.add(
          '[$ni:v]setpts=(PTS-STARTPTS)/$speedStr+$offsetStr/TB,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
        );
      } else {
        filterParts.add(
          '[$ni:v]setpts=PTS-STARTPTS+$offsetStr/TB,'
          'format=yuv420p,'
          'scale=$scaleW:$scaleH:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1$vfSuffix[vs$ni]',
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
      if (hasAnyAudio) ...['-c:a', 'aac', '-b:a', '128k'],
      if (finalAudioLabel == null && hasBgAudio) ...['-af', 'volume=${widget.audioVolume}'],
      '-preset', 'ultrafast',
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
    final controllersToDispose =
        Map<int, VideoPlayerController>.from(widget.videoControllers);
    final controllerKeys = List<int>.unmodifiable(controllersToDispose.keys);
    widget.videoControllers.clear();
    if (mounted) setState(() {});
    if (mounted) await WidgetsBinding.instance.endOfFrame;
    for (final vc in controllersToDispose.values) {
      await vc.dispose();
    }

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
          '${tmpDir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.mp4';

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
        await Gal.putVideo(outPath, album: 'Video Editor');

        // Clean up temp file
        try {
          File(outPath).deleteSync();
        } catch (_) {}

        setState(() {
          _exportState = _ExportState.done;
          _exportProgress = 1.0;
        });
      } else {
        final logs = await session.getLogs();
        final lastLog =
            logs.isNotEmpty ? logs.last.getMessage() : 'Unknown error';
        setState(() {
          _exportState = _ExportState.error;
          _exportError = lastLog;
        });
      }
    } catch (e) {
      await ExportServiceManager.stop();
      if (mounted) {
        setState(() {
          _exportState = _ExportState.error;
          _exportError = e.toString();
        });
      }
    } finally {
      // Reinitialise video controllers so the user can preview or export again.
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
      // Keep the foreground-service notification in sync with fake progress.
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

  @override
  Widget build(BuildContext context) {
    final progress = _totalDuration.inMilliseconds > 0
        ? (_elapsed.inMilliseconds / _totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),

            // Canvas fills whatever space remains after the fixed controls.
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) => _buildCanvas(
                  constraints.maxWidth,
                  constraints.maxHeight,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Time label + seek bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _elapsedStr,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF333333),
                      color: _kOrange,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Play / Pause
            Center(
              child: GestureDetector(
                onTap: (_exportState == _ExportState.exporting ||
                        _previewMode == _PreviewMode.manual)
                    ? null
                    : _togglePlay,
                child: Container(
                  width: 50,
                  height: 50,
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
                    size: 26,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Preview mode cards
            _buildPreviewModeSection(),

            const SizedBox(height: 10),

            // Export section
            _buildExportSection(),

            const SizedBox(height: 14),
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

      case _ExportState.done:
        return _buildDoneState();

      case _ExportState.error:
        return _buildErrorState();
    }
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Main save button
          GestureDetector(
            onTap: _exportCollage,
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

  Widget _buildDoneState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade700, width: 1),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.greenAccent, size: 22),
                SizedBox(width: 10),
                Text(
                  'Saved to Gallery!',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _exportState = _ExportState.idle;
              _exportProgress = 0.0;
            }),
            child: const Text('Export again',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
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

    Widget wrap(Widget media) =>
        cf != null ? ColorFiltered(colorFilter: cf, child: media) : media;

    if (cell.isVideo) {
      if (widget.videoControllers.containsKey(index)) {
        final vc = widget.videoControllers[index]!;
        return wrap(FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: vc.value.size.width,
            height: vc.value.size.height,
            child: VideoPlayer(vc),
          ),
        ));
      }
      // Controller not available (disposed before export) — show black placeholder
      return wrap(Container(color: Colors.black));
    }
    return wrap(Image.file(File(cell.filePath!), fit: BoxFit.cover));
  }
}

enum _ExportState { idle, exporting, done, error }

enum _PreviewMode { parallel, sequential, manual }
