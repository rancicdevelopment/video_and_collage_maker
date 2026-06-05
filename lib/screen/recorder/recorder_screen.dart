import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:waveform_extractor/waveform_extractor.dart';

import '../../ad/banner_ad_widget.dart';
import '../video_editor/video_editor_screen.dart';
import 'recorder_amplitude_bars.dart';
import 'recorder_constants.dart';
import 'recorder_nudge_button.dart';
import 'recorder_preview_button.dart';
import 'recorder_time_label.dart';
import 'recorder_waveform_painter.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class RecorderScreen extends StatefulWidget {
  /// When provided, pressing "Open in Editor" returns the processed audio path
  /// to the caller (via this callback + Navigator.pop) instead of pushing a
  /// standalone VideoEditorScreen. Used when launched from inside the editor.
  final void Function(String audioPath)? onAudioRecorded;

  const RecorderScreen({super.key, this.onAudioRecorded});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

enum _RecorderState { idle, recording, paused, preview }

class _RecorderScreenState extends State<RecorderScreen>
    with TickerProviderStateMixin {
  // ── Core ──────────────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  _RecorderState _state = _RecorderState.idle;
  String? _recordedPath;

  // ── Timer ────────────────────────────────────────────────────────────────
  Timer? _timer;
  int _elapsedMs = 0; // total elapsed ms (pauses excluded)

  // ── Amplitude ────────────────────────────────────────────────────────────
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _bars = List.filled(28, 0.05);

  // ── Pulse animation ───────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _pulseAnim =
      Tween(begin: 1.0, end: 1.18).animate(
    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
  );

  // ── Playback ─────────────────────────────────────────────────────────────
  bool _isPlaying = false;
  Duration _playPosition = Duration.zero;
  Duration _playDuration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  // ── Preview waveform ──────────────────────────────────────────────────────
  List<double> _previewAmplitudes = [];

  // ── Selection (normalized 0..1) ───────────────────────────────────────────
  double _startNorm = 0.0;
  double _endNorm   = 1.0;

  // Drag state
  bool _draggingStart = false;
  bool _draggingEnd   = false;
  double? _startDragX;
  double? _endDragX;
  static const double _handleHitWidth = 32.0;

  // ── Zoom ──────────────────────────────────────────────────────────────────
  double _zoomLevel = 1.0;
  static const double _zoomMin = 1.0;
  static const double _zoomMax = 8.0;

  double get _visibleStart {
    final window = 1.0 / _zoomLevel;
    final center = (_startNorm + _endNorm) / 2;
    return (center - window / 2).clamp(0.0, 1.0 - window);
  }
  double get _visibleEnd =>
      (_visibleStart + 1.0 / _zoomLevel).clamp(0.0, 1.0);

  // ── Loop playback ─────────────────────────────────────────────────────────
  Timer? _loopTimer;
  Timer? _autoPlayDebounce;
  bool _ignoringPositionFlicker = false;

  // ── Speed ─────────────────────────────────────────────────────────────────
  double _previewSpeed = 1.0;

  // ── Normalize ─────────────────────────────────────────────────────────────
  bool _normalize = false;

  // ── Export format ─────────────────────────────────────────────────────────
  String _exportFormat = 'original';

  // ── Saving state ──────────────────────────────────────────────────────────
  bool _isSaving = false;

  // ── Preview scroll ────────────────────────────────────────────────────────
  final _previewScrollCtrl = ScrollController();

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl.stop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _posSub?.cancel();
    _playerStateSub?.cancel();
    _loopTimer?.cancel();
    _autoPlayDebounce?.cancel();
    _recorder.dispose();
    _player.dispose();
    _pulseCtrl.dispose();
    _previewScrollCtrl.dispose();
    super.dispose();
  }

  // ── Recording ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission denied.');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen(_onAmplitude);

    _startTimer();
    _pulseCtrl.repeat(reverse: true);

    setState(() => _state = _RecorderState.recording);
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    _timer?.cancel();
    _pulseCtrl.stop();
    setState(() => _state = _RecorderState.paused);
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    _startTimer();
    _pulseCtrl.repeat(reverse: true);
    setState(() => _state = _RecorderState.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl.stop();

    final path = await _recorder.stop();
    if (path == null || !File(path).existsSync()) {
      setState(() {
        _state = _RecorderState.idle;
        _elapsedMs = 0;
      });
      return;
    }

    _recordedPath = path;
    await _initPlayer(path);
    _initPreviewState();
    setState(() => _state = _RecorderState.preview);
  }

  Future<void> _discardAndReset() async {
    _loopTimer?.cancel();
    _autoPlayDebounce?.cancel();
    await _player.stop();
    _posSub?.cancel();
    _playerStateSub?.cancel();
    if (_recordedPath != null) {
      await File(_recordedPath!)
          .delete()
          .catchError((_) => File(_recordedPath!));
      _recordedPath = null;
    }
    setState(() {
      _state = _RecorderState.idle;
      _elapsedMs = 0;
      _isPlaying = false;
      _playPosition = Duration.zero;
      _playDuration = Duration.zero;
      _previewAmplitudes = [];
      _startNorm = 0.0;
      _endNorm = 1.0;
      _zoomLevel = 1.0;
      _previewSpeed = 1.0;
      _normalize = false;
      _exportFormat = 'original';
      for (int i = 0; i < _bars.length; i++) {
        _bars[i] = 0.05;
      }
    });
  }

  // ── Timer ────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    final start = DateTime.now().millisecondsSinceEpoch - _elapsedMs;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        setState(() =>
            _elapsedMs = DateTime.now().millisecondsSinceEpoch - start);
      }
    });
  }

  // ── Amplitude ────────────────────────────────────────────────────────────

  void _onAmplitude(Amplitude amp) {
    const minDb = -60.0;
    final normalised = ((amp.current - minDb) / (-minDb)).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _bars.length - 1; i++) {
        _bars[i] = _bars[i + 1];
      }
      _bars[_bars.length - 1] = math.max(0.05, normalised);
    });
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  Future<void> _initPlayer(String path) async {
    _posSub?.cancel();
    _playerStateSub?.cancel();

    await _player.setSourceDeviceFile(path);
    final dur = await _player.getDuration();
    _playDuration = dur ?? Duration.zero;

    _posSub = _player.onPositionChanged.listen((pos) {
      if (!mounted || _ignoringPositionFlicker) return;
      setState(() => _playPosition = pos);
    });
    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
      if (s == PlayerState.completed) {
        if (mounted) setState(() => _playPosition = Duration.zero);
      }
    });
  }

  // ── Save / Share ─────────────────────────────────────────────────────────

  Future<void> _share() async {
    final src = _recordedPath;
    if (src == null) return;
    await Share.shareXFiles([XFile(src)], text: 'Audio recording');
  }

  Future<void> _openInEditor() async {
    final src = _recordedPath;
    if (src == null || !mounted || _isSaving) return;
    _stopPreview();
    if (!mounted) return;

    setState(() => _isSaving = true);

    String editorPath = src;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final dest = p.join(docs.path, 'voice_rec_$ts.m4a');

      final needsProcessing = _startNorm > 0.001 ||
          _endNorm < 0.999 ||
          _normalize ||
          (_previewSpeed - 1.0).abs() > 0.01;

      if (!needsProcessing) {
        await File(src).copy(dest);
        editorPath = dest;
      } else {
        final startS = _playDuration.inMilliseconds * _startNorm / 1000;
        final durS   =
            _playDuration.inMilliseconds * (_endNorm - _startNorm) / 1000;

        // Build audio filter chain
        final filters = <String>[];
        if ((_previewSpeed - 1.0).abs() > 0.01) {
          filters.add('atempo=${_previewSpeed.toStringAsFixed(4)}');
        }
        if (_normalize) {
          filters.add('loudnorm');
        }
        final filterArg =
            filters.isNotEmpty ? ' -af "${filters.join(',')}"' : '';

        final cmd =
            '-y -i "$src" -ss $startS -t $durS -codec:a aac -b:a 128k$filterArg "$dest"';

        final session = await FFmpegKit.execute(cmd);
        final rc      = await session.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          editorPath = dest;
        } else {
          // FFmpeg failed — fall back to plain copy
          await File(src).copy(dest);
          editorPath = dest;
        }
      }
    } catch (_) {
      // Any error: use original path
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (widget.onAudioRecorded != null) {
      // Caller (e.g. video editor) handles adding the audio — just pop back.
      Navigator.pop(context);
      widget.onAudioRecorded!(editorPath);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(initialAudioPath: editorPath),
      ),
    );
  }

  // ── Preview init ─────────────────────────────────────────────────────────

  void _initPreviewState() {
    _startNorm = 0.0;
    _endNorm = 1.0;
    _zoomLevel = 1.0;
    _previewSpeed = 1.0;
    _normalize = false;
    _exportFormat = 'original';
    _previewAmplitudes = List.filled(150, 0.01);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_previewScrollCtrl.hasClients) _previewScrollCtrl.jumpTo(0);
    });
    _loadRealWaveform();
  }

  Future<void> _loadRealWaveform() async {
    final path = _recordedPath;
    if (path == null || !File(path).existsSync()) return;
    try {
      final result =
          await WaveformExtractor().extractWaveform(path, useCache: false);
      final rawSamples = result.waveformData;
      if (rawSamples.isEmpty || !mounted) return;

      final bars = rawSamples.length < 150 ? rawSamples.length : 150;
      if (bars == 0) return;
      final samplesPerBar = (rawSamples.length / bars).ceil().clamp(1, rawSamples.length);

      final processed = <double>[];
      for (int i = 0; i < bars; i++) {
        final start = i * samplesPerBar;
        final end = math.min(start + samplesPerBar, rawSamples.length);
        int peak = 0;
        for (int j = start; j < end; j++) {
          if (rawSamples[j].abs() > peak) peak = rawSamples[j].abs();
        }
        processed.add(peak.toDouble());
      }

      double globalPeak = processed.reduce(math.max);
      if (globalPeak == 0) globalPeak = 1;
      if (!mounted) return;
      setState(() {
        _previewAmplitudes =
            processed.map((v) => (v / globalPeak).clamp(0.01, 1.0)).toList();
      });
    } catch (_) {
      // keep flat line on error
    }
  }

  // ── Selection helpers ─────────────────────────────────────────────────────

  Duration _fromNorm(double norm) => Duration(
      milliseconds: (_playDuration.inMilliseconds * norm).round());

  double get _playbackPositionNorm {
    if (_playDuration.inMilliseconds == 0) return 0;
    return (_playPosition.inMilliseconds / _playDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  double get _minGap =>
      _playDuration.inMilliseconds > 0 ? 0.005 : 0.01;

  // ── Waveform interaction ──────────────────────────────────────────────────

  Future<void> _onWaveformTapUp(TapUpDetails d, double waveWidth) async {
    final x = d.localPosition.dx;
    final visibleRange = _visibleEnd - _visibleStart;
    final startPx = ((_startNorm - _visibleStart) / visibleRange) * waveWidth;
    final endPx   = ((_endNorm   - _visibleStart) / visibleRange) * waveWidth;
    if ((x - startPx).abs() <= _handleHitWidth) return;
    if ((x - endPx).abs()   <= _handleHitWidth) return;

    final norm = (_visibleStart + (x / waveWidth) * visibleRange)
        .clamp(0.0, 1.0);
    final pos = _fromNorm(norm);
    setState(() => _playPosition = pos);
    if (_isPlaying) await _player.seek(pos);
  }

  void _onPanDown(DragDownDetails d, double waveWidth) {
    final x = d.localPosition.dx;
    final visibleRange = _visibleEnd - _visibleStart;
    final startPx = ((_startNorm - _visibleStart) / visibleRange) * waveWidth;
    final endPx   = ((_endNorm   - _visibleStart) / visibleRange) * waveWidth;
    if ((x - startPx).abs() <= _handleHitWidth) {
      setState(() { _draggingStart = true; _startDragX = x; });
    } else if ((x - endPx).abs() <= _handleHitWidth) {
      setState(() { _draggingEnd = true; _endDragX = x; });
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double waveWidth) {
    final dx = d.delta.dx;
    final visibleRange = _visibleEnd - _visibleStart;
    if (_draggingStart) {
      _startDragX = (_startDragX ?? 0) + dx;
      final norm = (_visibleStart + _startDragX! / waveWidth * visibleRange)
          .clamp(0.0, _endNorm - _minGap);
      setState(() => _startNorm = norm);
      _autoPlayFromStart();
    } else if (_draggingEnd) {
      _endDragX = (_endDragX ?? 0) + dx;
      final norm = (_visibleStart + _endDragX! / waveWidth * visibleRange)
          .clamp(_startNorm + _minGap, 1.0);
      setState(() => _endNorm = norm);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _draggingStart = false;
      _draggingEnd   = false;
      _startDragX    = null;
      _endDragX      = null;
    });
  }

  // ── Loop playback ─────────────────────────────────────────────────────────

  void _autoPlayFromStart() {
    _autoPlayDebounce?.cancel();
    _autoPlayDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _stopPreview();
      _startPreviewFrom(_startNorm);
    });
  }

  void _startPreviewFrom(double startNorm) async {
    if (!mounted) return;
    final startPos = _fromNorm(startNorm);
    final endPos   = _fromNorm(_endNorm);
    final segment  = endPos - startPos;
    if (segment <= Duration.zero) return;

    _ignoringPositionFlicker = true;
    setState(() { _isPlaying = true; _playPosition = startPos; });
    await _player.setPlaybackRate(_previewSpeed);
    await _player.play(DeviceFileSource(_recordedPath!), position: startPos);
    Future.delayed(const Duration(milliseconds: 150),
        () => _ignoringPositionFlicker = false);

    _loopTimer?.cancel();
    _loopTimer = Timer(
      Duration(
          milliseconds:
              (segment.inMilliseconds / _previewSpeed).round()),
      () { if (mounted && _isPlaying) _startPreviewFrom(_startNorm); },
    );
  }

  void _stopPreview() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _player.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _togglePreview() async {
    if (_isPlaying) {
      _stopPreview();
    } else {
      _startPreviewFrom(
          _playbackPositionNorm.clamp(_startNorm, _endNorm));
    }
  }

  // ── Nudge ─────────────────────────────────────────────────────────────────

  void _nudgeStart(int stepMs) {
    if (_playDuration.inMilliseconds == 0) return;
    final delta = stepMs / _playDuration.inMilliseconds;
    setState(() {
      _startNorm = (_startNorm + delta).clamp(0.0, _endNorm - _minGap);
    });
    _autoPlayFromStart();
  }

  void _nudgeEnd(int stepMs) {
    if (_playDuration.inMilliseconds == 0) return;
    final delta = stepMs / _playDuration.inMilliseconds;
    setState(() {
      _endNorm = (_endNorm + delta).clamp(_startNorm + _minGap, 1.0);
    });
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────

  void _zoomIn() => setState(() =>
      _zoomLevel = (_zoomLevel * 2).clamp(_zoomMin, _zoomMax));

  void _zoomOut() => setState(() =>
      _zoomLevel = (_zoomLevel / 2).clamp(_zoomMin, _zoomMax));

  // ── Speed ─────────────────────────────────────────────────────────────────

  void _setPreviewSpeed(double speed) async {
    setState(() => _previewSpeed = speed);
    if (_isPlaying) await _player.setPlaybackRate(speed);
  }

  // ── Save with processing ──────────────────────────────────────────────────

  Future<void> _saveToFiles() async {
    final src = _recordedPath;
    if (src == null || _isSaving) return;

    setState(() => _isSaving = true);
    _stopPreview();

    try {
      final docs = await getApplicationDocumentsDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final needsProcessing = _startNorm > 0.001 ||
          _endNorm < 0.999 ||
          _normalize ||
          _exportFormat != 'original';

      if (!needsProcessing) {
        final dest = p.join(docs.path, 'Recording_$ts.m4a');
        await File(src).copy(dest);
        _showSnack('Saved to app files.');
      } else {
        final ext    = _exportFormat == 'original' ? 'm4a' : _exportFormat;
        final dest   = p.join(docs.path, 'Recording_$ts.$ext');
        final startS = _playDuration.inMilliseconds * _startNorm / 1000;
        final durS   =
            _playDuration.inMilliseconds * (_endNorm - _startNorm) / 1000;
        final normFilter = _normalize ? ' -af "loudnorm"' : '';
        final cmd =
            '-y -i "$src" -ss $startS -t $durS${_buildCodecArgs(ext)}$normFilter "$dest"';

        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          _showSnack('Saved to app files.');
        } else {
          _showSnack('Save failed.');
        }
      }
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _buildCodecArgs(String ext) {
    switch (ext) {
      case 'mp3':  return ' -codec:a libmp3lame -q:a 2';
      case 'wav':  return ' -codec:a pcm_s16le';
      case 'm4a':  return ' -codec:a aac -b:a 128k';
      case 'aac':  return ' -codec:a aac -b:a 128k';
      case 'ogg':  return ' -codec:a libvorbis -q:a 4';
      default:     return ' -c copy';
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDuration(int ms) {
    final s      = ms ~/ 1000;
    final m      = s ~/ 60;
    final sec    = s % 60;
    final centis = (ms % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')}.'
        '${centis.toString().padLeft(2, '0')}';
  }

  String _formatDurMills(Duration d) {
    final m   = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s   = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final dec = (d.inMilliseconds.remainder(1000) / 100).floor();
    return '$m:$s.$dec';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: AppBar(
        backgroundColor: kRecBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _state == _RecorderState.preview
              ? 'Recording Preview'
              : 'Voice Recorder',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_state == _RecorderState.preview) ...[
            TextButton(
              onPressed: _discardAndReset,
              child: const Text('New',
                  style: TextStyle(
                      color: Colors.white54, fontWeight: FontWeight.w500)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveToFiles,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRecAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(60, 36),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('SAVE',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const BannerAdWidget(),
            Expanded(
              child: switch (_state) {
                _RecorderState.preview => _buildPreview(),
                _ => _buildRecorder(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Recorder view ─────────────────────────────────────────────────────────

  Widget _buildRecorder() {
    final isIdle      = _state == _RecorderState.idle;
    final isRecording = _state == _RecorderState.recording;
    final isPaused    = _state == _RecorderState.paused;

    return Column(
      children: [
        const Spacer(),

        // ── Timer ──────────────────────────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: Text(
            _formatDuration(_elapsedMs),
            style: TextStyle(
              color: isRecording ? kRecRed : Colors.white54,
              fontSize: 46,
              fontWeight: FontWeight.w200,
              letterSpacing: 2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Recording status label ─────────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isRecording)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                      color: kRecRed, shape: BoxShape.circle),
                ),
              Text(
                isRecording
                    ? 'Recording'
                    : isPaused
                        ? 'Paused'
                        : '',
                style: TextStyle(
                  color: isRecording ? kRecRed : Colors.white38,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // ── Amplitude bars ─────────────────────────────────────────────────
        SizedBox(
          height: 72,
          child: AnimatedOpacity(
            opacity: isRecording ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: RecorderAmplitudeBars(bars: _bars),
          ),
        ),

        const SizedBox(height: 48),

        // ── Main record button ─────────────────────────────────────────────
        ScaleTransition(
          scale: isRecording
              ? _pulseAnim
              : const AlwaysStoppedAnimation(1.0),
          child: GestureDetector(
            onTap: isIdle
                ? _startRecording
                : isRecording
                    ? _pauseRecording
                    : isPaused
                        ? _resumeRecording
                        : null,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording
                    ? kRecRed
                    : isPaused
                        ? Colors.white12
                        : kRecRed.withValues(alpha: 0.85),
                boxShadow: isRecording
                    ? [
                        BoxShadow(
                          color: kRecRed.withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isIdle
                    ? Icons.mic
                    : isRecording
                        ? Icons.pause
                        : Icons.mic,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // ── Secondary controls ─────────────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: (isRecording || isPaused) ? _stopRecording : null,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: const Icon(Icons.stop_rounded,
                      color: Colors.white70, size: 28),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Idle hint ──────────────────────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: const Text(
            'Tap to start recording',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),

        const Spacer(),
      ],
    );
  }

  // ── Preview view ──────────────────────────────────────────────────────────

  bool get _canScrollDown {
    if (!_previewScrollCtrl.hasClients) return false;
    try {
      return _previewScrollCtrl.offset <
          _previewScrollCtrl.position.maxScrollExtent - 24;
    } catch (_) {
      return false;
    }
  }

  void _scrollToBottom() {
    if (!_previewScrollCtrl.hasClients) return;
    _previewScrollCtrl.animateTo(
      _previewScrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Widget _buildPreview() {
    final startDur = _fromNorm(_startNorm);
    final endDur   = _fromNorm(_endNorm);
    final selDur   = endDur - startDur;

    return Column(
      children: [
        // ── Scrollable content ───────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _previewScrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── File title ───────────────────────────────────────────
                    Center(
                      child: Text(
                        _recordedPath != null
                            ? p.basenameWithoutExtension(_recordedPath!)
                            : 'Recording',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Waveform + handles ───────────────────────────────────
                    LayoutBuilder(builder: (ctx, constraints) {
                      final waveWidth = constraints.maxWidth;
                      return Column(
                        children: [
                          GestureDetector(
                            onPanDown:   (d) => _onPanDown(d, waveWidth),
                            onPanUpdate: (d) => _onPanUpdate(d, waveWidth),
                            onPanEnd:    _onPanEnd,
                            onTapUp:     (d) => _onWaveformTapUp(d, waveWidth),
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: kRecCard,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: CustomPaint(
                                painter: RecorderWaveformPainter(
                                  amplitudes:     _previewAmplitudes,
                                  selectionStart: _startNorm,
                                  selectionEnd:   _endNorm,
                                  playbackPos:    _playbackPositionNorm,
                                  visibleStart:   _visibleStart,
                                  visibleEnd:     _visibleEnd,
                                  totalDuration:  _playDuration,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RecorderTimeLabel(
                                  label: 'Start',
                                  time: _formatDurMills(startDur),
                                  color: kRecAccent),
                              Text(
                                'Duration: ${_formatDurMills(selDur)}',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                              RecorderTimeLabel(
                                  label: 'End',
                                  time: _formatDurMills(endDur),
                                  color: kRecAccent,
                                  rightAlign: true),
                            ],
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),

                    // ── Zoom controls ────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Zoom:',
                            style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.zoom_out,
                              color: Colors.white54, size: 22),
                          onPressed: _zoomLevel > _zoomMin ? _zoomOut : null,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${_zoomLevel.toStringAsFixed(1)}x',
                            style: const TextStyle(color: kRecAccent, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.zoom_in,
                              color: Colors.white54, size: 22),
                          onPressed: _zoomLevel < _zoomMax ? _zoomIn : null,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // ── Nudge + Play row ─────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Text('Start',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                            const SizedBox(height: 6),
                            Row(children: [
                              RecorderNudgeButton(
                                  icon: Icons.remove,
                                  onNudge: () => _nudgeStart(-500)),
                              const SizedBox(width: 8),
                              RecorderNudgeButton(
                                  icon: Icons.add,
                                  onNudge: () => _nudgeStart(500)),
                            ]),
                          ],
                        ),
                        GestureDetector(
                          onTap: _togglePreview,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: kRecAccent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying ? Icons.stop : Icons.play_arrow,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            const Text('End',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                            const SizedBox(height: 6),
                            Row(children: [
                              RecorderNudgeButton(
                                  icon: Icons.remove,
                                  onNudge: () => _nudgeEnd(-500)),
                              const SizedBox(width: 8),
                              RecorderNudgeButton(
                                  icon: Icons.add,
                                  onNudge: () => _nudgeEnd(500)),
                            ]),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Normalize ────────────────────────────────────────────
                    InkWell(
                      onTap: () => setState(() => _normalize = !_normalize),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _normalize
                              ? kRecAccent.withValues(alpha: 0.12)
                              : kRecCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _normalize ? kRecAccent : Colors.white12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _normalize,
                                onChanged: (v) =>
                                    setState(() => _normalize = v ?? false),
                                activeColor: kRecAccent,
                                checkColor: Colors.black,
                                side: BorderSide(
                                    color: _normalize
                                        ? kRecAccent
                                        : Colors.white38,
                                    width: 1.5),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Normalize',
                                    style: TextStyle(
                                        color: _normalize
                                            ? kRecAccent
                                            : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                const Text('Boost volume to maximum level',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Playback speed ───────────────────────────────────────
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('Speed:',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: kRecSpeeds.map((s) {
                        final selected = s == _previewSpeed;
                        return GestureDetector(
                          onTap: () => _setPreviewSpeed(s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: selected ? kRecAccent : kRecCard,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      selected ? kRecAccent : Colors.white12),
                            ),
                            child: Text(
                              '${s}x',
                              style: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // ── Export format ────────────────────────────────────────
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('Export format:',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: kRecExportFormats.map((fmt) {
                        final selected = fmt == _exportFormat;
                        return GestureDetector(
                          onTap: () => setState(() => _exportFormat = fmt),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected ? kRecAccent : kRecCard,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      selected ? kRecAccent : Colors.white12),
                            ),
                            child: Text(
                              fmt == 'original' ? 'Original' : fmt.toUpperCase(),
                              style: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Scroll-to-bottom button ────────────────────────────────────
              Positioned(
                bottom: 12,
                right: 16,
                child: AnimatedBuilder(
                  animation: _previewScrollCtrl,
                  builder: (ctx, child) {
                    final show = _canScrollDown;
                    return AnimatedOpacity(
                      opacity: show ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: !show,
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: _scrollToBottom,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kRecCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: kRecAccent.withValues(alpha: 0.6),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: kRecAccent,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Pinned action buttons ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: kRecBg,
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: RecorderPreviewButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _share,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RecorderPreviewButton(
                  icon: _isSaving
                      ? Icons.hourglass_empty
                      : Icons.video_library_outlined,
                  label: _isSaving ? 'Processing…' : 'Open in Editor',
                  onTap: _isSaving ? null : _openInEditor,
                  accent: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
