import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:gal/gal.dart';
import 'package:waveform_extractor/waveform_extractor.dart';

import '../export_settings/export_settings_screen.dart';
import '../media_picker/media_picker_screen.dart';
import '../../ad/app_open_ad_manager.dart';
import 'video_crop_screen.dart';
import 'video_editor_constants.dart';
import 'video_editor_eq_sheet.dart';
import 'video_editor_model.dart';
import 'video_editor_painters.dart';
import 'video_editor_track_block.dart';
import '../../ad/banner_ad_widget.dart';
import '../../data/draft_manager.dart';
import 'video_editor_blend_layer.dart';
import 'video_editor_chromakey_dialog.dart';
import 'video_editor_filters_dialog.dart';
import 'video_editor_glow_shadow_dialog.dart';
import 'video_editor_mask_dialog.dart';
import 'video_editor_param_dialogs.dart';
import 'video_editor_text_dialog.dart';
import 'video_editor_voice_dialog.dart';
import 'video_editor_record_sheet.dart';
import 'video_editor_transitions_dialog.dart';
import '../camera/camera_screen.dart';

part 'video_editor_fullscreen_preview.dart';


class VideoEditorScreen extends StatefulWidget {
  final DraftProject? draft;

  /// Pre-load these files when opening a fresh project (e.g. from camera).
  final List<PickedMediaFile>? initialMedia;

  /// Pre-load a single audio file as the first track (e.g. from voice recorder).
  final String? initialAudioPath;

  const VideoEditorScreen({super.key, this.draft, this.initialMedia, this.initialAudioPath});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    with WidgetsBindingObserver {
  // ── Tracks ────────────────────────────────────────────────────────────────
  List<TimelineTrack> _tracks = [];
  int? _selectedIndex;
  double _overlayBaseScale = 1.0;
  double _overlayBaseRotation = 0.0;
  Offset? _canvasTapDownPosition;

  // Actual rendered size of the selected text widget (pre-scale, pre-rotation).
  // Measured via GlobalKey after each frame so button corners are exact.
  final GlobalKey _textOverlayKey = GlobalKey();
  Size _textOverlaySize = Size.zero;
  String? _measuredTrackId;

  // ── Undo / redo ───────────────────────────────────────────────────────────
  final List<List<TimelineTrack>> _undoStack = [];
  final List<List<TimelineTrack>> _redoStack = [];

  // ── Timeline zoom / scroll ────────────────────────────────────────────────
  double _pps = kVeDefaultPPS;
  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _vScrollCtrl = ScrollController();
  // Mirrors _vScrollCtrl for the fixed labels panel (NeverScrollablePhysics).
  final ScrollController _labelsScrollCtrl = ScrollController();

  // ── Playhead ──────────────────────────────────────────────────────────────
  Duration _playheadPos = Duration.zero;

  // ── Audio playback ────────────────────────────────────────────────────────
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, StreamSubscription<void>> _audioSubs = {};
  final Map<String, Timer> _audioTimers = {};

  // Voice-effect preview: maps trackId → processed audio file path.
  // Used by both audio tracks (replaces source) and video tracks (separate
  // AudioPlayer while the VideoPlayerController is muted).
  final Map<String, String> _voicePreviewPaths = {};
  bool _voicePreviewGenerating = false;

  // Chromakey preview: processed video (chromakey over black bg) keyed by track.id.
  final Map<String, String> _chromakeyPreviewPaths = {};
  bool _chromakeyPreviewGenerating = false;

  // Stabilizer preview: 2-pass VidStab processed clip, keyed by track.id.
  final Map<String, String> _stabPreviewPaths = {};
  bool _stabPreviewGenerating = false;

  // Reverse preview: reversed clip for in-editor preview, keyed by track.id.
  final Map<String, String> _reversePreviewPaths = {};
  bool _reversePreviewGenerating = false;

  // ── Transition preview ────────────────────────────────────────────────────
  Timer? _transitionAnimTimer;
  double _transitionAnimProgress = 0.0;
  bool _transitionPreviewActive = false;
  TransitionType _transitionPreviewType = TransitionType.none;

  // ── Video playback ────────────────────────────────────────────────────────
  // One VideoPlayerController per video track (keyed by track.id).
  // Hard cap prevents OOM when many 4K HEVC clips overlap simultaneously.
  // Each c2.qti.hevc.decoder at 3840×2160 uses ~80 MB of native buffer memory;
  // the Android Java heap is clamped at 256 MB, so 4 is a safe maximum.
  static const int _kMaxVideoControllers = 4;
  final Map<String, VideoPlayerController> _videoControllers = {};
  // IDs of tracks currently active in the preview (video + image), used to
  // detect changes so setState is called when tracks enter/leave the window.
  List<String> _previewActiveTrackIds = [];
  // Current visual fade opacity for each video/image track (keyed by track.id).
  final Map<String, double> _videoFadeOpacity = {};
  // Track IDs for which play() has been issued in the current play session.
  // Cleared at the start of every _startAllFromPos call so that any controller
  // that finishes initialising after _startAllFromPos returns is detected as
  // "not yet started" and is immediately seeked + played by _updatePreviewController.
  final Set<String> _playStartedIds = {};
  // Consecutive timer ticks on which a controller was found to be stalled
  // (should be playing but isn't).  Used to debounce stall-recovery restarts
  // so we don't hammer play() every 16 ms on every stalled clip.
  final Map<String, int> _videoStallTick = {};
  // Last volume value sent to each VideoPlayerController / AudioPlayer.
  // Used to skip redundant setVolume() native calls on every 16 ms tick,
  // which were causing audio stuttering with 2-3 simultaneous video overlays.
  final Map<String, double> _lastVideoVolume = {};
  final Map<String, double> _lastAudioVolume = {};

  // ── Master clock ──────────────────────────────────────────────────────────
  bool _isPlaying = false;
  bool _recordingMuted = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _uiTimer;
  Duration _playheadStartPos = Duration.zero;
  int _playGen = 0;
  static const Duration _kTimerInterval = Duration(milliseconds: 16);

  // ── Track drag (horizontal) ───────────────────────────────────────────────
  int? _trackDragIndex;
  bool _trackDragActive = false;
  bool _playheadDragActive = false;
  bool _rulerScrubActive = false;
  double _trackDragStartX = 0;
  Duration _trackDragOriginalOffset = Duration.zero;

  // ── Track collapse ────────────────────────────────────────────────────────
  final Set<String> _collapsedTracks = {};
  final Set<int> _collapsedEmptyRows = {};

  // ── Row reorder (vertical drag) ───────────────────────────────────────────
  int? _rowReorderIdx;
  bool _rowReorderActive = false;
  double _rowReorderAccumDy = 0;

  // ── Trim drag ─────────────────────────────────────────────────────────────
  int? _trimTrackIndex;
  bool _trimActive = false;
  bool _trimHandleDown = false;

  // ── Pinch-to-zoom ─────────────────────────────────────────────────────────
  final Map<int, Offset> _activePointers = {};
  double _pinchStartDistance = 0;
  double _pinchStartPps = kVeDefaultPPS;
  double _pinchAnchorSecs = 0.0;
  double _pinchAnchorViewportX = 0.0;
  bool _pinchActive = false;

  // ── Tap-to-seek ───────────────────────────────────────────────────────────
  Offset? _seekTapViewportPos;
  bool _seekTapValid = false;

  // ── Save ──────────────────────────────────────────────────────────────────
  // ignore: prefer_final_fields
  bool _isSaving = false;

  // ── Draft ─────────────────────────────────────────────────────────────────
  late String _draftId;
  Timer? _draftSaveTimer;

  // ── AdMob banner ──────────────────────────────────────────────────────────

  // ── Preview panel resize ──────────────────────────────────────────────────
  double _previewHeight = kVePreviewMinHeight;

  // ─────────────────────────────────────────────────────────────────────────
  //  Init / dispose
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vScrollCtrl.addListener(_syncLabelsScroll);

    final draft = widget.draft;
    if (draft != null) {
      _draftId = draft.id;
      if (draft.tracks.isNotEmpty) {
        _tracks = List.of(draft.tracks);
        // Regenerate thumbnails and waveforms for loaded tracks.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final t in _tracks) {
            if (t.isVideo) _extractThumbnails(t.id, t.filePath);
            if (t.isAudio) _extractWaveform(t.id, t.filePath);
          }
        });
      }
    } else {
      _draftId = DraftManager.instance.create().id;
    }

    // Load media captured from the camera (or any external source).
    if (widget.initialMedia != null && widget.initialMedia!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadInitialMedia(widget.initialMedia!);
      });
    }

    // Pre-load a single audio file (e.g. from voice recorder).
    if (widget.initialAudioPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addAudioFromPath(widget.initialAudioPath!);
      });
    }
  }

  void _syncLabelsScroll() {
    if (!_labelsScrollCtrl.hasClients) return;
    final maxE = _labelsScrollCtrl.position.maxScrollExtent;
    _labelsScrollCtrl.jumpTo(_vScrollCtrl.offset.clamp(0.0, maxE));
  }

  /// Loads a list of already-captured/selected files directly into the
  /// timeline without opening the media-picker UI.  Used by the camera flow.
  Future<void> _loadInitialMedia(List<PickedMediaFile> picks) async {
    if (picks.isEmpty || !mounted) return;
    const kImageDuration = Duration(seconds: 30);

    _pushUndo();

    for (final pick in picks) {
      if (pick.isVideo) {
        Duration duration = pick.duration;
        if (duration == Duration.zero) {
          try {
            final tmp = VideoPlayerController.file(File(pick.path));
            await tmp.initialize();
            duration = tmp.value.duration;
            await tmp.dispose();
          } catch (_) {}
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
        );

        final isFirst = _tracks.isEmpty;
        setState(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }

        _getOrInitVideoController(track).then((_) {
          if (mounted) {
            setState(() {});
            _updatePreviewForSeek(_playheadPos);
          }
        });

        await _extractThumbnails(track.id, pick.path);
      } else {
        // Image track
        final track = TimelineTrack(
          id: TimelineTrack.generateId(),
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          trackType: TrackType.image,
          duration: kImageDuration,
          startOffset: _playheadPos,
          color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        );

        final isFirst = _tracks.isEmpty;
        setState(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isPlaying) {
        _uiTimer?.cancel();
        _stopwatch.stop();
        _pauseAllAudio();
        for (final vc in _videoControllers.values) {
          vc.pause();
        }
        setState(() => _isPlaying = false);
      }
      // Auto-save draft when app goes to background.
      if (_tracks.isNotEmpty) _saveDraftNow();
    }
  }

  // ── Draft save helpers ────────────────────────────────────────────────────

  /// Schedule a debounced auto-save (1.5 s after last track change).
  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 1500), _saveDraftNow);
  }

  Future<void> _saveDraftNow() async {
    if (_tracks.isEmpty) return;
    final thumb = _tracks
        .firstWhere(
          (t) => t.isVideo || t.isImage,
          orElse: () => _tracks.first,
        )
        .thumbnailPaths
        .isNotEmpty
        ? _tracks
            .firstWhere(
              (t) => t.isVideo || t.isImage,
              orElse: () => _tracks.first,
            )
            .thumbnailPaths
            .first
        : null;

    final draft = DraftProject(
      id: _draftId,
      title: widget.draft?.title ??
          'Project ${DateTime.now().day}/${DateTime.now().month}',
      createdAt: widget.draft?.createdAt ?? DateTime.now(),
      modifiedAt: DateTime.now(),
      tracks: _tracks,
      thumbnailPath: thumb,
    );
    await DraftManager.instance.save(draft);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftSaveTimer?.cancel();
    _transitionAnimTimer?.cancel();

    _hScrollCtrl.dispose();
    _vScrollCtrl.dispose();
    _labelsScrollCtrl.dispose();
    _uiTimer?.cancel();
    _stopwatch.stop();
    _cancelAudioTimers();
    for (final sub in _audioSubs.values) {
      sub.cancel();
    }
    for (final pl in _audioPlayers.values) {
      pl.dispose();
    }
    for (final vc in _videoControllers.values) {
      vc.dispose();
    }
    for (final path in _voicePreviewPaths.values) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    for (final path in _chromakeyPreviewPaths.values) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    for (final path in _stabPreviewPaths.values) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    for (final path in _reversePreviewPaths.values) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Audio player management
  // ─────────────────────────────────────────────────────────────────────────

  AudioPlayer _getAudioPlayer(String trackId) {
    return _audioPlayers.putIfAbsent(trackId, () {
      final player = AudioPlayer();
      player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
        iOS: AudioContextIOS(options: {AVAudioSessionOptions.mixWithOthers}),
      ));
      _audioSubs[trackId] = player.onPlayerComplete.listen((_) {
        player.setVolume(0.0);
      });
      return player;
    });
  }

  void _releaseAudioPlayer(String trackId) {
    _audioTimers.remove(trackId)?.cancel();
    _audioSubs.remove(trackId)?.cancel();
    _audioPlayers.remove(trackId)?.dispose();
  }

  void _cancelAudioTimers() {
    for (final t in _audioTimers.values) {
      t.cancel();
    }
    _audioTimers.clear();
  }

  void _stopAllAudio() {
    _cancelAudioTimers();
    for (final pl in _audioPlayers.values) {
      pl.stop();
    }
  }

  void _pauseAllAudio() {
    _cancelAudioTimers();
    for (final pl in _audioPlayers.values) {
      pl.pause();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Video controller management
  // ─────────────────────────────────────────────────────────────────────────

  Future<VideoPlayerController?> _getOrInitVideoController(
      TimelineTrack track) async {
    if (!track.isVideo) return null;
    if (_videoControllers.containsKey(track.id)) {
      return _videoControllers[track.id];
    }
    if (!File(track.filePath).existsSync()) return null;

    // Step 1: evict controllers for tracks that are NOT at the current playhead
    // and NOT within the lookahead window (upcoming clips we pre-initialized).
    // Keeping a short lookahead window prevents thrashing: a pre-initialized
    // future clip's controller won't be evicted when another init is requested.
    const kEvictLookahead = Duration(seconds: 8);
    final toEvict = _videoControllers.keys.where((id) {
      final t = _tracks.where((t) => t.id == id).firstOrNull;
      if (t == null) return true;
      // Keep clips currently overlapping the playhead.
      if (_playheadPos >= t.startOffset && _playheadPos < t.endTime) {
        return false;
      }
      // Keep upcoming clips within the lookahead window (pre-initialized).
      if (t.startOffset > _playheadPos &&
          t.startOffset - _playheadPos <= kEvictLookahead) {
        return false;
      }
      return true;
    }).toList();
    for (final id in toEvict) {
      _releaseVideoController(id);
    }

    // Step 2: if we're still at the cap, all remaining controllers are for
    // tracks genuinely overlapping the playhead — don't add another to avoid OOM.
    if (_videoControllers.length >= _kMaxVideoControllers) return null;

    // Priority: reverse preview → stabilizer preview → chromakey preview → raw file.
    final revPath  = _reversePreviewPaths[track.id];
    final stabPath = _stabPreviewPaths[track.id];
    final ckPath   = _chromakeyPreviewPaths[track.id];
    final videoFilePath = (revPath != null && File(revPath).existsSync())
        ? revPath
        : (stabPath != null && File(stabPath).existsSync())
            ? stabPath
            : (ckPath != null && File(ckPath).existsSync())
                ? ckPath
                : track.filePath;

    final controller = VideoPlayerController.file(
      File(videoFilePath),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _videoControllers[track.id] = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0.0); // volume set at playback start
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('VideoController init failed for "${track.title}": $e');
      _videoControllers.remove(track.id);
      _playStartedIds.remove(track.id);
      controller.dispose();
      return null;
    }

    // If playback is active when this controller finishes initialising (e.g.
    // the controller was still being set up when the user pressed Play and was
    // therefore skipped by _startAllFromPos), seek it to the current position
    // and start it immediately so it doesn't show a frozen frame.
    if (mounted && _isPlaying && !_playStartedIds.contains(track.id)) {
      final idx = _tracks.indexOf(track);
      if (idx >= 0 &&
          _playheadPos >= track.startOffset &&
          _playheadPos < track.endTime) {
        final capturedGen = _playGen;
        _playStartedIds.add(track.id);
        final seekPos = _filePosFor(idx, _playheadPos);
        await controller.seekTo(seekPos);
        if (mounted && _isPlaying && _playGen == capturedGen) {
          await controller.setVolume(_muteVol(track.volume.clamp(0.0, 1.0)));
          await controller.play();
        }
      }
    }

    return _videoControllers[track.id];
  }

  void _releaseVideoController(String trackId) {
    _videoControllers.remove(trackId)?.dispose();
    _previewActiveTrackIds.remove(trackId);
    _playStartedIds.remove(trackId);
  }

  /// Update the preview to reflect all video and image tracks covering [pos].
  ///
  /// For video tracks: lazily initializes controllers that have entered the
  /// playhead range and triggers seek+play when a controller becomes ready
  /// while playback is active.
  /// For image tracks: no controller is needed — they're rendered directly by
  /// _buildPreviewContent from the file path.
  ///
  /// Calls setState when the set of active track IDs changes so the UI rebuilds.
  void _updatePreviewController(Duration pos) {
    final newIds = <String>[];
    for (final t in _tracks) {
      if (!t.isVideo && !t.isImage) continue;
      if (pos < t.startOffset || pos >= t.endTime) continue;

      newIds.add(t.id);

      if (t.isImage) continue; // No controller needed for images.

      // Video track: ensure its controller is initialised.
      final vc = _videoControllers[t.id];
      if (vc != null && vc.value.isInitialized) {
        // Already ready — nothing to do.
        // (Play is started by _getOrInitVideoController when init completes,
        // or by _startAllFromPos for controllers that were already initialised.)
      } else if (vc == null) {
        // Lazily init the controller for this track; evicts stale ones first.
        // Play is handled inside _getOrInitVideoController when init completes.
        _getOrInitVideoController(t).then((_) {
          if (!mounted) return;
          // Refresh the active-track list once the controller is ready.
          _updatePreviewController(_playheadPos);
        });
      }
    }

    if (newIds.join(',') == _previewActiveTrackIds.join(',')) return;

    _previewActiveTrackIds = newIds;
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Undo / Redo
  // ─────────────────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(List.from(_tracks));
    _redoStack.clear();
    _scheduleDraftSave();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(_tracks));
    setState(() {
      _tracks = _undoStack.removeLast();
      _selectedIndex = null;
    });
    _scheduleDraftSave();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(_tracks));
    setState(() {
      _tracks = _redoStack.removeLast();
      _selectedIndex = null;
    });
    _scheduleDraftSave();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Timeline helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Actual end of all clip content — playhead cannot go past this.
  Duration get _contentEndTime {
    if (_tracks.isEmpty) return Duration.zero;
    Duration max = Duration.zero;
    for (final t in _tracks) {
      if (t.endTime > max) max = t.endTime;
    }
    return max;
  }

  Duration get _totalDuration {
    if (_tracks.isEmpty) return const Duration(minutes: 5);
    return _contentEndTime + const Duration(seconds: 30);
  }

  double _secondsToX(double secs) => secs * _pps;
  double _xToSeconds(double x) => x / _pps;

  bool _isCollapsed(TimelineTrack t) => _collapsedTracks.contains(t.id);

  void _toggleAllTracks() {
    setState(() {
      final trackAllCollapsed = _tracks.isEmpty || _tracks.every(_isCollapsed);
      final emptyAllCollapsed = _collapsedEmptyRows.length == 10;
      final allCollapsed = trackAllCollapsed && emptyAllCollapsed;
      if (allCollapsed) {
        _collapsedTracks.clear();
        _collapsedEmptyRows.clear();
      } else {
        _collapsedTracks.addAll(_tracks.map((t) => t.id));
        _collapsedEmptyRows.addAll(
          List.generate(10, (i) => _tracks.length + i),
        );
      }
    });
  }

  double _trackHeightFor(TimelineTrack t) {
    if (_isCollapsed(t)) return kVeCollapsedTrackHeight;
    return (t.isVideo || t.isText || t.isImage) ? kVeVideoTrackHeight : kVeAudioTrackHeight;
  }

  double _rowHeightFor(TimelineTrack t) =>
      _trackHeightFor(t) + kVeTrackGap;

  // ignore: unused_element
  double _topOffsetForRow(int index) {
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _rowHeightFor(_tracks[i]);
    }
    return offset;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Snackbar
  // ─────────────────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: TextStyle(color: error ? Colors.white : Colors.black)),
      backgroundColor:
          error ? Colors.red.shade800 : const Color(0xFF17FD92),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Export
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _exportVideo() async {
    if (_tracks.isEmpty) {
      _snack('Add some tracks before exporting', error: true);
      return;
    }

    await _stopPlayback();

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportSettingsScreen(tracks: List.unmodifiable(_tracks)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Asset loading: thumbnails + waveforms
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _extractThumbnails(String trackId, String videoPath) async {
    if (!File(videoPath).existsSync()) return;
    const thumbCount = 12;
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) return;
    final duration = _tracks[idx].duration.inMilliseconds;
    if (duration <= 0) return;

    final tmpDir = await getTemporaryDirectory();
    final paths = <String>[];

    for (int i = 0; i < thumbCount; i++) {
      final timeMs = (duration * i / (thumbCount - 1)).round();
      final outPath = '${tmpDir.path}/thumb_${trackId}_$i.jpg';
      try {
        final path = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: outPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: timeMs,
          maxHeight: 200,
          quality: 90,
        );
        if (path != null) paths.add(path);
      } catch (e) {
        debugPrint('Thumbnail extraction failed at ${timeMs}ms: $e');
      }
    }

    if (!mounted) return;
    final currentIdx = _tracks.indexWhere((t) => t.id == trackId);
    if (currentIdx == -1) return;
    setState(() {
      _tracks[currentIdx] =
          _tracks[currentIdx].copyWith(thumbnailPaths: paths);
    });
  }

  Future<void> _extractWaveform(String trackId, String audioPath) async {
    if (!File(audioPath).existsSync()) return;
    try {
      final result = await WaveformExtractor()
          .extractWaveform(audioPath, useCache: false);
      final rawSamples = result.waveformData;
      if (rawSamples.isEmpty || !mounted) return;

      final bars = rawSamples.length < 200 ? rawSamples.length : 200;
      if (bars == 0) return;
      final samplesPer = (rawSamples.length / bars).ceil().clamp(1, rawSamples.length);

      final processed = <double>[];
      for (int i = 0; i < bars; i++) {
        final start = i * samplesPer;
        final end = min(start + samplesPer, rawSamples.length);
        int peak = 0;
        for (int j = start; j < end; j++) {
          if (rawSamples[j].abs() > peak) peak = rawSamples[j].abs();
        }
        processed.add(peak.toDouble());
      }

      double globalPeak = processed.reduce(max);
      if (globalPeak == 0) globalPeak = 1;
      final normalized =
          processed.map((v) => (v / globalPeak).clamp(0.01, 1.0)).toList();

      if (!mounted) return;
      final idx = _tracks.indexWhere((t) => t.id == trackId);
      if (idx == -1) return;
      setState(() {
        _tracks[idx] = _tracks[idx].copyWith(waveformBars: normalized);
      });
    } catch (e) {
      debugPrint('Waveform extraction error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Playback
  // ─────────────────────────────────────────────────────────────────────────

  Duration _filePosFor(int i, Duration timelinePos) {
    final t = _tracks[i];
    if (timelinePos <= t.startOffset) return t.trimStart;
    final elapsed = timelinePos - t.startOffset;
    final fileElapsed =
        Duration(microseconds: (elapsed.inMicroseconds * t.speed).round());
    final candidate = t.trimStart + fileElapsed;
    final maxPos = t.duration - t.trimEnd;
    return candidate > maxPos ? t.trimStart : candidate;
  }

  Future<void> _startAllFromPos(Duration pos) async {
    _stopAllAudio();
    for (final vc in _videoControllers.values) {
      vc.pause();
    }
    _uiTimer?.cancel();

    // Pre-compute fade opacity at the starting position so there is no
    // single-frame flash before the first timer tick arrives.
    _syncFadeOpacityAt(pos);

    final gen = ++_playGen;
    // New play session — clear the set so controllers that finish initialising
    // after this point are detected as "not yet started" by _updatePreviewController.
    _playStartedIds.clear();
    _videoStallTick.clear();
    _lastVideoVolume.clear();
    _lastAudioVolume.clear();
    _playheadStartPos = pos;
    _stopwatch.reset();
    _stopwatch.start();

    _uiTimer = Timer.periodic(_kTimerInterval, (timer) {
      if (!mounted || _playGen != gen) {
        timer.cancel();
        return;
      }
      final newPos = _playheadStartPos + _stopwatch.elapsed;
      final contentEnd = _contentEndTime;
      if (newPos >= contentEnd) {
        timer.cancel();
        _stopwatch.stop();
        _stopAllAudio();
        for (final vc in _videoControllers.values) {
          vc.pause();
        }
        if (mounted) {
          setState(() {
            _playheadPos = contentEnd;
            _isPlaying = false;
          });
        }
        return;
      }

      // Per-audio-track: stop ended clips + apply fades
      for (final track in _tracks) {
        if (!track.isAudio) continue;
        final pl = _audioPlayers[track.id];
        if (pl == null) continue;

        if (newPos > track.endTime) {
          if (pl.state == PlayerState.playing) {
            pl.setVolume(0.0);
            pl.stop();
          }
          continue;
        }

        if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) continue;
        if (pl.state != PlayerState.playing) continue;

        final elapsed = newPos - track.startOffset;
        if (elapsed < Duration.zero) continue;
        final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
        final elapsedSecs = elapsed.inMicroseconds / 1e6;
        final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);

        double fade = 1.0;
        if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
          final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
          final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        final newAudioVol = (track.volume * fade).clamp(0.0, 2.0);
        final lastAudioVol = _lastAudioVolume[track.id];
        if (lastAudioVol == null || (newAudioVol - lastAudioVol).abs() > 0.005) {
          _lastAudioVolume[track.id] = newAudioVol;
          pl.setVolume(_muteVol(newAudioVol));
        }
      }

      // Per-video-track: stop ended clips + apply volume/fades
      for (final track in _tracks) {
        if (!track.isVideo && !track.isImage) continue;

        if (track.isImage) {
          // Image tracks have no controller — just update fade opacity.
          if (newPos > track.endTime || newPos < track.startOffset) {
            _videoFadeOpacity.remove(track.id);
          } else if (track.fadeInSecs > 0 || track.fadeOutSecs > 0) {
            final elapsed = newPos - track.startOffset;
            final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
            final elapsedSecs = elapsed.inMicroseconds / 1e6;
            final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);
            double fade = 1.0;
            if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
              final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
              fade *= t * t * (3.0 - 2.0 * t);
            }
            if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
              final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
              fade *= t * t * (3.0 - 2.0 * t);
            }
            _videoFadeOpacity[track.id] = fade;
          } else {
            _videoFadeOpacity.remove(track.id);
          }
          continue;
        }

        final vc = _videoControllers[track.id];
        if (vc == null || !vc.value.isInitialized) continue;

        // Stop clips that have passed their end time.
        if (newPos > track.endTime) {
          if (vc.value.isPlaying) {
            vc.setVolume(0.0);
            vc.pause();
          }
          continue;
        }

        // Stall recovery: if the controller was started but stopped playing
        // unexpectedly (e.g. audio-focus conflict when two clips overlap, or a
        // platform-level stall), restart it after a debounce so we don't
        // hammer play() on every 16 ms tick.
        // Use a longer threshold (25 ticks ≈ 400 ms) to avoid a ping-pong
        // effect where multiple overlapping video controllers repeatedly steal
        // audio focus from each other, which causes audible stuttering.
        if (!vc.value.isPlaying) {
          if (_playStartedIds.contains(track.id)) {
            final stall = (_videoStallTick[track.id] ?? 0) + 1;
            _videoStallTick[track.id] = stall;
            if (stall >= 25) { // ~400 ms threshold
              _videoStallTick.remove(track.id);
              final hasVoiceAudio = track.voiceEffectIndex > 0 &&
                  _voicePreviewPaths.containsKey(track.id);
              final vol = hasVoiceAudio ? 0.0 : track.volume.clamp(0.0, 1.0);
              _lastVideoVolume[track.id] = vol;
              vc.setVolume(_muteVol(vol));
              vc.play(); // fire-and-forget
            }
          }
          continue;
        }
        _videoStallTick.remove(track.id);

        if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) {
          _videoFadeOpacity.remove(track.id);
          continue;
        }

        final elapsed = newPos - track.startOffset;
        if (elapsed < Duration.zero) continue;
        final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
        final elapsedSecs = elapsed.inMicroseconds / 1e6;
        final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);

        double fade = 1.0;
        if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
          final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
          final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        // Mute the VideoPlayerController when a voice-preview audio player
        // is handling audio for this track.
        final hasVoiceAudio = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        final newVideoVol =
            hasVoiceAudio ? 0.0 : (track.volume * fade).clamp(0.0, 1.0);
        final lastVideoVol = _lastVideoVolume[track.id];
        if (lastVideoVol == null || (newVideoVol - lastVideoVol).abs() > 0.005) {
          _lastVideoVolume[track.id] = newVideoVol;
          vc.setVolume(_muteVol(newVideoVol));
        }
        _videoFadeOpacity[track.id] = fade;
      }

      setState(() => _playheadPos = newPos);
      _updatePreviewController(newPos);

      // Lookahead: pre-initialize controllers for video clips that are about
      // to start, so the controller is warm when the clip's time arrives.
      // Fire-and-forget; _getOrInitVideoController handles the cap and eviction.
      const kTimerLookahead = Duration(seconds: 5);
      for (final t in _tracks) {
        if (!t.isVideo) continue;
        if (_videoControllers.containsKey(t.id)) continue;
        if (t.startOffset <= newPos) continue; // already started or passed
        if (t.startOffset - newPos > kTimerLookahead) continue; // too far away
        _getOrInitVideoController(t); // fire-and-forget
      }
    });

    // Start audio tracks
    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isAudio) continue;
      if (pos > track.endTime) continue;

      final delay = track.startOffset - pos;
      final player = _getAudioPlayer(track.id);

      // Use voice-processed preview file if available, else original.
      final audioPath = _voicePreviewPaths[track.id] ?? track.filePath;

      if (delay <= Duration.zero) {
        try {
          final filePos = _filePosFor(i, pos);
          await player.setVolume(_muteVol(track.volume));
          await player.setPlaybackRate(track.speed);
          await player.play(DeviceFileSource(audioPath));
          if (_playGen != gen) return;
          await player.seek(filePos);
          if (_playGen != gen) return;
        } catch (e) {
          debugPrint('Audio play failed for "${track.title}": $e');
        }
      } else {
        final capturedId   = track.id;
        final capturedPath = audioPath;
        final capturedTrim = track.trimStart;
        final capturedVol  = track.volume;
        final capturedSpd  = track.speed;
        _audioTimers[capturedId] = Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          try {
            final pl = _getAudioPlayer(capturedId);
            await pl.setVolume(_muteVol(capturedVol));
            await pl.setPlaybackRate(capturedSpd);
            await pl.play(DeviceFileSource(capturedPath));
            if (_playGen != gen) return;
            await pl.seek(capturedTrim);
          } catch (e) {
            debugPrint('Delayed audio play failed for "$capturedId": $e');
          }
        });
      }
    }

    // Start voice-audio players for video tracks that have a voice effect.
    // The VideoPlayerController is muted (volume forced to 0 below) and a
    // separate AudioPlayer plays the FFmpeg-processed audio in its place.
    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isVideo) continue;
      if (track.voiceEffectIndex == 0) continue;
      final voicePath = _voicePreviewPaths[track.id];
      if (voicePath == null || !File(voicePath).existsSync()) continue;
      if (pos > track.endTime) continue;

      final delay  = track.startOffset - pos;
      final player = _getAudioPlayer('${track.id}_va');

      if (delay <= Duration.zero) {
        try {
          final filePos = _filePosFor(i, pos);
          await player.setVolume(_muteVol(track.volume));
          await player.play(DeviceFileSource(voicePath));
          if (_playGen != gen) return;
          await player.seek(filePos);
          if (_playGen != gen) return;
        } catch (e) {
          debugPrint('Video voice-audio play failed for "${track.title}": $e');
        }
      } else {
        final capturedId   = '${track.id}_va';
        final capturedPath = voicePath;
        final capturedTrim = _filePosFor(i, track.startOffset);
        final capturedVol  = track.volume;
        _audioTimers[capturedId] = Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          try {
            final pl = _getAudioPlayer(capturedId);
            await pl.setVolume(_muteVol(capturedVol));
            await pl.play(DeviceFileSource(capturedPath));
            if (_playGen != gen) return;
            await pl.seek(capturedTrim);
          } catch (e) {
            debugPrint('Delayed video voice-audio failed for "$capturedId": $e');
          }
        });
      }
    }

    // Start video tracks
    // Collect clips for immediate start and handle delayed ones separately.
    // For immediate clips: seek all in parallel, then play all in parallel so
    // that overlapping clips start as synchronised as possible.
    final immediateEntries = <({VideoPlayerController vc, Duration clipPos, double vol})>[];

    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isVideo) continue;
      if (pos > track.endTime) continue;

      final delay = track.startOffset - pos;

      if (delay <= Duration.zero) {
        // Immediate clip — must be initialized already to play right now.
        final vc = _videoControllers[track.id];
        if (vc == null || !vc.value.isInitialized) continue;
        // Mark as started so _updatePreviewController won't restart it.
        _playStartedIds.add(track.id);
        final hasVoicePlayer = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        immediateEntries.add((
          vc: vc,
          clipPos: _filePosFor(i, pos),
          vol: hasVoicePlayer ? 0.0 : _muteVol(track.volume.clamp(0.0, 1.0)),
        ));
      } else {
        // Delayed clip — set up a timer regardless of whether the controller
        // is initialized yet.  Also kick off initialization now (fire-and-
        // forget) so the controller is warm by the time the timer fires.
        final capturedTrack = track;
        final capturedI = i;
        final hasVoicePlayerD = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        final capturedVol =
            hasVoicePlayerD ? 0.0 : track.volume.clamp(0.0, 1.0);
        // Pre-initialize so it's ready when the delay elapses.
        _getOrInitVideoController(capturedTrack);
        Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          // Controller should already be initialized from the pre-init above.
          // If not (e.g., it was evicted or init failed), try once more.
          var ctrl = _videoControllers[capturedTrack.id];
          if (ctrl == null || !ctrl.value.isInitialized) {
            ctrl = await _getOrInitVideoController(capturedTrack);
          }
          if (ctrl == null || !ctrl.value.isInitialized) return;
          if (!mounted || !_isPlaying || _playGen != gen) return;
          // Mark as started before seeking so _updatePreviewController won't
          // also try to start this controller concurrently.
          _playStartedIds.add(capturedTrack.id);
          await ctrl.seekTo(_filePosFor(capturedI, _playheadPos));
          if (!mounted || !_isPlaying || _playGen != gen) return;
          await ctrl.setVolume(_muteVol(capturedVol));
          if (!mounted || !_isPlaying || _playGen != gen) return;
          await ctrl.play();
        });
      }
    }

    if (immediateEntries.isNotEmpty) {
      // Seek all overlapping clips in parallel.
      await Future.wait(
        immediateEntries.map((e) => e.vc.seekTo(e.clipPos)),
      );
      if (_playGen != gen) return;
      // Reset the stopwatch right before play() so that seek latency is not
      // counted as elapsed playback time — otherwise the playhead jumps ahead
      // of the actual video frames, causing visible sync drift or frozen frames.
      _stopwatch.reset();
      _stopwatch.start();
      // Set volume and play all overlapping clips in parallel.
      await Future.wait(
        immediateEntries.map((e) async {
          await e.vc.setVolume(_muteVol(e.vol));
          await e.vc.play();
        }),
      );
      if (_playGen != gen) return;
    }

    _updatePreviewController(pos);
  }

  /// Returns the current fade opacity for [trackId] in the preview panel.
  /// Uses the cached value from [_videoFadeOpacity] if available, otherwise
  /// computes it live so the build method never falls back to 1.0 by default.
  double _previewFadeOpacity(String? trackId) {
    if (trackId == null) return 1.0;
    final cached = _videoFadeOpacity[trackId];
    if (cached != null) return cached;
    final track = _tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return 1.0;
    return _computeFadeOpacity(track, _playheadPos);
  }

  /// Computes the fade opacity [0..1] for [track] at playhead position [pos].
  double _computeFadeOpacity(TimelineTrack track, Duration pos) {
    if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) return 1.0;
    final elapsed = pos - track.startOffset;
    if (elapsed < Duration.zero) return 1.0;
    final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
    final elapsedSecs = elapsed.inMicroseconds / 1e6;
    final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);
    double fade = 1.0;
    if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
      final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
      fade *= t * t * (3.0 - 2.0 * t);
    }
    if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
      final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
      fade *= t * t * (3.0 - 2.0 * t);
    }
    return fade;
  }

  /// Pre-populates [_videoFadeOpacity] for all video tracks at position [pos]
  /// so the preview shows the correct opacity immediately (no flash).
  void _syncFadeOpacityAt(Duration pos) {
    for (final track in _tracks) {
      if (!track.isVideo) continue;
      final fade = _computeFadeOpacity(track, pos);
      if (fade < 1.0) {
        _videoFadeOpacity[track.id] = fade;
      } else {
        _videoFadeOpacity.remove(track.id);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      _uiTimer?.cancel();
      _stopwatch.stop();
      _pauseAllAudio();
      for (final vc in _videoControllers.values) {
        vc.pause();
      }
      // Do NOT clear _videoFadeOpacity — keep the current fade so the
      // preview stays at the correct opacity while paused.
      setState(() => _isPlaying = false);
    } else {
      if (_tracks.isEmpty) return;
      _syncFadeOpacityAt(_playheadPos);
      setState(() => _isPlaying = true);
      await _startAllFromPos(_playheadPos);
    }
  }

  Future<void> _stopPlayback() async {
    _uiTimer?.cancel();
    _stopwatch.stop();
    _stopAllAudio();
    for (final vc in _videoControllers.values) {
      vc.pause();
    }
    _syncFadeOpacityAt(_playheadPos);
    setState(() => _isPlaying = false);
  }

  /// Returns 0 when recording is active (all audio muted for clean capture).
  double _muteVol(double v) => _recordingMuted ? 0.0 : v;

  // ─────────────────────────────────────────────────────────────────────────
  //  Seek
  // ─────────────────────────────────────────────────────────────────────────

  void _seekVisualOnly(Duration newPos) {
    final end = _contentEndTime;
    final clamped = newPos.isNegative
        ? Duration.zero
        : (end > Duration.zero && newPos > end ? end : newPos);
    _playheadStartPos = clamped;
    if (_stopwatch.isRunning) _stopwatch.reset();
    _syncFadeOpacityAt(clamped);
    setState(() => _playheadPos = clamped);
    _updatePreviewForSeek(clamped);
  }

  void _applySeek(Duration newPos) {
    final end = _contentEndTime;
    final clamped = newPos.isNegative
        ? Duration.zero
        : (end > Duration.zero && newPos > end ? end : newPos);
    setState(() => _playheadPos = clamped);
    _updatePreviewForSeek(clamped);
    if (!_isPlaying) return;
    _startAllFromPos(clamped);
  }

  void _updatePreviewForSeek(Duration pos) {
    _updatePreviewController(pos);
    // Seek video controllers to show correct frame at new position.
    // Use _filePosFor so that trimStart and playback speed are respected.
    for (int i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      if (!track.isVideo) continue;
      final vc = _videoControllers[track.id];
      if (vc == null || !vc.value.isInitialized) continue;
      if (pos >= track.startOffset && pos < track.endTime) {
        vc.seekTo(_filePosFor(i, pos));
      }
    }
  }

  Duration _contentXToDuration(double contentX) {
    final maxSecs = _contentEndTime.inMilliseconds / 1000.0;
    final secs = (contentX / _pps).clamp(0.0, maxSecs > 0 ? maxSecs : _totalDuration.inSeconds.toDouble());
    return Duration(milliseconds: (secs * 1000).round());
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Zoom
  // ─────────────────────────────────────────────────────────────────────────

  void _autoZoomToFit() {
    // Zoom so the actual content (without trailing buffer) fills ~80% of screen
    double contentSecs = 0;
    for (final t in _tracks) {
      final end = t.endTime.inMilliseconds / 1000.0;
      if (end > contentSecs) contentSecs = end;
    }
    if (contentSecs <= 0) return;
    final screenW = MediaQuery.of(context).size.width;
    final targetPps = (screenW * 0.80 / contentSecs).clamp(kVeMinPPS, kVeMaxPPS);
    if (_hScrollCtrl.hasClients) {
      _hScrollCtrl.jumpTo(0);
    }
    setState(() => _pps = targetPps);
  }

  void _zoomAtViewportX(double newPps, double viewportX) {
    final clamped = newPps.clamp(kVeMinPPS, kVeMaxPPS);
    if (clamped == _pps) return;
    final anchorSecs =
        (viewportX + (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0)) /
            _pps;
    if (_hScrollCtrl.hasClients) {
      final viewW = _hScrollCtrl.position.viewportDimension;
      final newMax =
          (_totalDuration.inSeconds.toDouble() * clamped + 60 - viewW)
              .clamp(0.0, double.infinity);
      final target =
          (anchorSecs * clamped - viewportX).clamp(0.0, newMax);
      _hScrollCtrl.jumpTo(target);
    }
    setState(() => _pps = clamped);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Pinch-to-zoom + tap-to-seek
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns true if the given viewport position lands on a track block.
  /// Used to suppress cursor seek when the user taps a track rather than
  /// empty timeline space.
  bool _isTapOnTrackBlock(Offset viewportPos) {
    // Taps inside the ruler never hit a track block.
    if (viewportPos.dy <= kVeRulerHeight) return false;

    final contentX = viewportPos.dx +
        (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
    final contentY = (viewportPos.dy - kVeRulerHeight) +
        (_vScrollCtrl.hasClients ? _vScrollCtrl.offset : 0.0);

    double rowTop = 0;
    for (final track in _tracks) {
      final rowH = _rowHeightFor(track);
      if (contentY >= rowTop && contentY < rowTop + rowH) {
        final startX =
            _secondsToX(track.startOffset.inMilliseconds / 1000.0);
        final minW = (_pps * 2.0).clamp(2.0, 40.0);
        final trackW =
            _secondsToX(track.effectiveDuration.inMilliseconds / 1000.0)
                .clamp(minW, double.infinity);
        if (contentX >= startX && contentX <= startX + trackW) {
          return true;
        }
      }
      rowTop += rowH;
    }
    return false;
  }

  void _onPinchDown(PointerDownEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_activePointers.length == 1) {
      _seekTapViewportPos = e.localPosition;
      // Suppress seek when the finger lands directly on a track block;
      // seek only on empty space or via explicit playhead/ruler drag.
      _seekTapValid = !_isTapOnTrackBlock(e.localPosition);
    } else {
      _seekTapValid = false;
      _seekTapViewportPos = null;
    }
    if (_activePointers.length == 2) {
      _pinchActive = true;
      final pts = _activePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartPps = _pps;
      _pinchAnchorViewportX = (pts[0].dx + pts[1].dx) / 2;
      _pinchAnchorSecs =
          (_pinchAnchorViewportX +
                  (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0)) /
              _pps;
    }
    setState(() {});
  }

  void _onPinchMove(PointerMoveEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_seekTapValid && _seekTapViewportPos != null) {
      if ((e.localPosition - _seekTapViewportPos!).distance > 12) {
        _seekTapValid = false;
      }
    }
    if (_activePointers.length == 2 && _pinchStartDistance > 0) {
      final pts = _activePointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final newPps =
          (_pinchStartPps * dist / _pinchStartDistance)
              .clamp(kVeMinPPS, kVeMaxPPS);
      if (newPps != _pps && _hScrollCtrl.hasClients) {
        final viewW = _hScrollCtrl.position.viewportDimension;
        final newMax =
            (_totalDuration.inSeconds.toDouble() * newPps + 60 - viewW)
                .clamp(0.0, double.infinity);
        final target =
            (_pinchAnchorSecs * newPps - _pinchAnchorViewportX)
                .clamp(0.0, newMax);
        _hScrollCtrl.jumpTo(target);
        setState(() => _pps = newPps);
      } else if (newPps != _pps) {
        setState(() => _pps = newPps);
      }
    }
  }

  void _onPinchUp(PointerUpEvent e) {
    if (_seekTapValid &&
        _activePointers.length == 1 &&
        !_trimActive &&
        !_trimHandleDown &&
        !_trackDragActive &&
        !_playheadDragActive) {
      final contentX = e.localPosition.dx +
          (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
      _applySeek(_contentXToDuration(contentX));
    }
    _seekTapValid = false;
    _seekTapViewportPos = null;
    _activePointers.remove(e.pointer);
    if (_activePointers.isEmpty) {
      _pinchActive = false;
      _pinchStartDistance = 0;
    } else if (_activePointers.length < 2) {
      _pinchStartDistance = 0;
      if (_activePointers.length == 1) _pinchStartPps = _pps;
    }
    setState(() {});
  }

  void _onPinchCancel(PointerCancelEvent e) {
    _seekTapValid = false;
    _seekTapViewportPos = null;
    _activePointers.remove(e.pointer);
    _pinchStartDistance = 0;
    if (_activePointers.isEmpty) _pinchActive = false;
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Auto-scroll
  // ─────────────────────────────────────────────────────────────────────────

  void _autoScrollToPlayhead(double secs) {
    if (!_hScrollCtrl.hasClients) return;
    const edgePad = 40.0;
    final playheadX = secs * _pps;
    final offset = _hScrollCtrl.offset;
    final viewW = _hScrollCtrl.position.viewportDimension;
    final maxScroll = _hScrollCtrl.position.maxScrollExtent;

    if (playheadX < offset + edgePad) {
      _hScrollCtrl
          .jumpTo((playheadX - edgePad).clamp(0.0, maxScroll));
    } else if (playheadX > offset + viewW - edgePad) {
      _hScrollCtrl
          .jumpTo((playheadX - viewW + edgePad).clamp(0.0, maxScroll));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Add tracks
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _addVideoTrack() => _openMediaPicker(initialTab: 0);


  /// Opens the custom gallery picker and adds the returned files as tracks.
  /// [initialTab]: 0 = VIDEO, 1 = PHOTO, 2 = ALL
  Future<void> _openMediaPicker({int initialTab = 0}) async {
    await _stopPlayback();
    if (!mounted) return;

    final picks = await Navigator.push<List<PickedMediaFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(initialTab: initialTab),
        fullscreenDialog: true,
      ),
    );
    if (picks == null || picks.isEmpty || !mounted) return;

    _pushUndo();
    const kImageDuration = Duration(seconds: 30);

    for (final pick in picks) {
      if (pick.isVideo) {
        // Get accurate duration via a temporary controller.
        Duration duration = pick.duration;
        if (duration == Duration.zero) {
          try {
            final tmp = VideoPlayerController.file(File(pick.path));
            await tmp.initialize();
            duration = tmp.value.duration;
            await tmp.dispose();
          } catch (_) {}
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
        );

        final isFirst = _tracks.isEmpty;
        setState(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }

        _getOrInitVideoController(track).then((_) {
          if (mounted) {
            setState(() {});
            _updatePreviewForSeek(_playheadPos);
          }
        });

        await _extractThumbnails(track.id, pick.path);
      } else {
        // Image track
        final track = TimelineTrack(
          id: TimelineTrack.generateId(),
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          trackType: TrackType.image,
          duration: kImageDuration,
          startOffset: _playheadPos,
          color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        );

        final isFirst = _tracks.isEmpty;
        setState(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }
      }
    }
  }

  Future<void> _addAudioTrack() async {
    await _stopPlayback();
    if (!mounted) return;

    AppOpenAdManager.instance.suppressNextResume();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    _pushUndo();
    for (final file in result.files) {
      if (file.path == null) continue;
      final path = file.path!;

      // Attempt to get audio duration
      Duration duration = const Duration(minutes: 3);
      try {
        final tmpPlayer = AudioPlayer();
        await tmpPlayer.setSourceDeviceFile(path);
        final dur = await tmpPlayer.getDuration();
        if (dur != null) duration = dur;
        await tmpPlayer.dispose();
      } catch (e) {
        debugPrint('Failed to get audio duration for $path: $e');
      }

      final track = TimelineTrack.fromFile(
        filePath: path,
        title: p.basenameWithoutExtension(path),
        duration: duration,
        trackType: TrackType.audio,
        colorIndex: _tracks.length,
        startOffset: _playheadPos,
      );

      final isFirstTrack = _tracks.isEmpty;
      setState(() {
        _tracks.add(track);
        _selectedIndex = _tracks.length - 1;
      });

      if (isFirstTrack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoZoomToFit();
        });
      }

      _extractWaveform(track.id, path);
    }
  }

  /// Adds an audio track from a known file path without showing a file picker.
  /// Used when navigating from the voice recorder preview.
  Future<void> _addAudioFromPath(String path) async {
    if (!File(path).existsSync()) return;
    await _stopPlayback();
    if (!mounted) return;

    Duration duration = const Duration(minutes: 3);
    try {
      final tmpPlayer = AudioPlayer();
      await tmpPlayer.setSourceDeviceFile(path);
      final dur = await tmpPlayer.getDuration();
      if (dur != null) duration = dur;
      await tmpPlayer.dispose();
    } catch (e) {
      debugPrint('Failed to get audio duration for $path: $e');
    }

    final track = TimelineTrack.fromFile(
      filePath: path,
      title: p.basenameWithoutExtension(path),
      duration: duration,
      trackType: TrackType.audio,
      colorIndex: _tracks.length,
      startOffset: Duration.zero,
    );

    _pushUndo();
    setState(() {
      _tracks.add(track);
      _selectedIndex = _tracks.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoZoomToFit();
    });

    _extractWaveform(track.id, path);
  }

  Future<void> _openRecorder() async {
    await _stopPlayback();
    if (!mounted) return;

    final startPos = _playheadPos;

    // Start playback muted so the user can record over the video
    setState(() {
      _isPlaying = true;
      _recordingMuted = true;
    });
    _startAllFromPos(startPos); // fire-and-forget

    final path = await showVeRecordSheet(
      context: context,
      startOffset: startPos,
    );

    // Tear down muted playback
    setState(() => _recordingMuted = false);
    await _stopPlayback();
    if (!mounted) return;

    if (path != null) {
      await _addAudioFromPath(path);
      // Reposition the new track so it starts where recording began
      if (_tracks.isNotEmpty) {
        final idx = _tracks.length - 1;
        setState(() {
          _tracks[idx] = _tracks[idx].copyWith(startOffset: startPos);
        });
      }
    }
  }

  Future<void> _openCameraRecorder() async {
    await _stopPlayback();
    if (!mounted) return;
    AppOpenAdManager.instance.suppressNextResume();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          onCapture: (picked) => _loadInitialMedia([picked]),
        ),
      ),
    );
  }

  Future<void> _addImageTrack() => _openMediaPicker(initialTab: 1);

  Future<void> _addTextTrack() async {
    await _stopPlayback();
    if (!mounted) return;
    _showTextEditDialog(isNew: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Track operations
  // ─────────────────────────────────────────────────────────────────────────

  void _deleteTrack() {
    if (_selectedIndex == null) return;
    _pushUndo();
    final track = _tracks[_selectedIndex!];
    _releaseAudioPlayer(track.id);
    _releaseVideoController(track.id);
    setState(() {
      _tracks.removeAt(_selectedIndex!);
      _selectedIndex = _tracks.isEmpty
          ? null
          : (_selectedIndex! - 1).clamp(0, _tracks.length - 1);
    });
  }

  void _splitTrack() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    final splitAt = _playheadPos - track.startOffset;
    if (splitAt <= Duration.zero || splitAt >= track.effectiveDuration) {
      _snack('Move playhead inside the track to split.', error: true);
      return;
    }
    _pushUndo();
    _releaseAudioPlayer(track.id);
    _releaseVideoController(track.id);
    final ts = DateTime.now().microsecondsSinceEpoch;
    final left = track.copyWith(
      id: '${ts}_L',
      trimEnd: track.trimEnd + (track.effectiveDuration - splitAt),
    );
    final right = track.copyWith(
      id: '${ts}_R',
      startOffset: track.startOffset + splitAt,
      trimStart: track.trimStart + splitAt,
    );
    setState(() {
      _tracks..removeAt(idx)..insert(idx, right)..insert(idx, left);
      _selectedIndex = idx;
    });
    // Re-init controllers for the new split tracks
    if (right.isVideo) {
      _getOrInitVideoController(right);
      _extractThumbnails(right.id, right.filePath);
    } else {
      _extractWaveform(right.id, right.filePath);
    }
    if (left.isVideo) {
      _getOrInitVideoController(left);
      _extractThumbnails(left.id, left.filePath);
    } else {
      _extractWaveform(left.id, left.filePath);
    }
  }

  void _trimTrack() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    final relPos = _playheadPos - track.startOffset;
    if (relPos <= Duration.zero || relPos >= track.effectiveDuration) {
      _snack('Move playhead inside the track to trim.', error: true);
      return;
    }
    _pushUndo();
    setState(() {
      _tracks[idx] = track.copyWith(
        trimEnd: track.trimEnd + (track.effectiveDuration - relPos),
      );
    });
  }

  void _duplicateTrack() {
    if (_selectedIndex == null) return;
    _pushUndo();
    final src = _tracks[_selectedIndex!];
    final dup = src.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startOffset: src.endTime,
    );
    setState(() {
      _tracks.insert(_selectedIndex! + 1, dup);
      _selectedIndex = _selectedIndex! + 1;
    });
    if (dup.isVideo) {
      _getOrInitVideoController(dup);
    }
  }

  Future<void> _extractAudio() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir = await getTemporaryDirectory();
    final outName = '${p.basenameWithoutExtension(track.filePath)}_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final outPath = p.join(tmpDir.path, outName);

    // Show progress indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Extracting audio...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    // FFmpeg: extract audio only, no re-encode if possible
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', track.filePath,
      '-vn',
      '-c:a', 'libmp3lame', '-q:a', '2',
      outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close dialog

    if (!ReturnCode.isSuccess(rc)) {
      _snack('Audio extraction failed.', error: true);
      return;
    }

    // Get duration of extracted audio
    Duration duration = track.effectiveDuration;
    try {
      final tmpPlayer = AudioPlayer();
      await tmpPlayer.setSourceDeviceFile(outPath);
      final dur = await tmpPlayer.getDuration();
      if (dur != null) duration = dur;
      await tmpPlayer.dispose();
    } catch (_) {}

    _pushUndo();
    final audioTrack = TimelineTrack.fromFile(
      filePath: outPath,
      title: '${p.basenameWithoutExtension(track.filePath)} (audio)',
      duration: duration,
      trackType: TrackType.audio,
      colorIndex: _tracks.length,
      startOffset: track.startOffset,
    );

    setState(() {
      // Mute the source video track so its embedded audio doesn't double up
      _tracks[_selectedIndex!] = _tracks[_selectedIndex!].copyWith(volume: 0.0);
      _tracks.insert(_selectedIndex! + 1, audioTrack);
      _selectedIndex = _selectedIndex! + 1;
    });

    _extractWaveform(audioTrack.id, outPath);
    _snack('Audio extracted successfully.');
  }

  Future<void> _exportFrame() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    // Calculate the time within the source video file at the current playhead.
    // Timeline position relative to track start, scaled by speed, plus trim offset.
    final relativeMs =
        (_playheadPos - track.startOffset).inMilliseconds.clamp(0, track.effectiveDuration.inMilliseconds);
    final sourceMs = (relativeMs * track.speed + track.trimStart.inMilliseconds).toInt();
    final seekSec = sourceMs / 1000.0;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir = await getTemporaryDirectory();
    final outName =
        '${p.basenameWithoutExtension(track.filePath)}_frame_${DateTime.now().millisecondsSinceEpoch}.png';
    final outPath = p.join(tmpDir.path, outName);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Extracting frame...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', seekSec.toStringAsFixed(3),
      '-i', track.filePath,
      '-frames:v', '1',
      '-q:v', '1',
      outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!ReturnCode.isSuccess(rc)) {
      _snack('Frame extraction failed.', error: true);
      return;
    }

    try {
      await Gal.putImage(outPath, album: 'Video Editor');
    } catch (e) {
      _snack('Frame extracted but could not save to gallery.', error: true);
      return;
    }

    if (!mounted) return;
    _snack('Frame saved to gallery.');
  }

  void _moveTrackUp() {
    if (_selectedIndex == null || _selectedIndex! <= 0 || _tracks.length < 2) return;
    _pushUndo();
    final idx = _selectedIndex!;
    setState(() {
      final tmp = _tracks.removeAt(idx);
      _tracks.insert(idx - 1, tmp);
      _selectedIndex = idx - 1;
    });
  }

  void _moveTrackDown() {
    if (_selectedIndex == null ||
        _selectedIndex! >= _tracks.length - 1 ||
        _tracks.length < 2) return;
    _pushUndo();
    final idx = _selectedIndex!;
    setState(() {
      final tmp = _tracks.removeAt(idx);
      _tracks.insert(idx + 1, tmp);
      _selectedIndex = idx + 1;
    });
  }

  void _rotateTrack() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    setState(() {
      _tracks[_selectedIndex!] =
          track.copyWith(rotation: (track.rotation + 90) % 360);
    });
  }

  void _mirrorTrack() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    setState(() {
      _tracks[_selectedIndex!] = track.copyWith(mirrorH: !track.mirrorH);
    });
  }

  // ── Play Backwards ─────────────────────────────────────────────────────
  Future<void> _reverseTrack() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;
    if (_reversePreviewGenerating) return;
    _pushUndo();
    final updated = track.copyWith(playBackwards: !track.playBackwards);
    setState(() {
      _tracks[_selectedIndex!] = updated;
    });
    await _generateReversePreview(updated);
  }

  // ── Freeze Frame — extract current frame and insert as image track ─────
  Future<void> _freezeFrame() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    // Ask user for freeze duration.
    double freezeSecs = 3.0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF111E2F),
          title: const Text('Freeze Frame',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Duration of the frozen frame:',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Duration',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${freezeSecs.toStringAsFixed(1)}s',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              Slider(
                value: freezeSecs,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                activeColor: const Color(0xFF00C8FF),
                inactiveColor: Colors.white12,
                onChanged: (v) => setS(() => freezeSecs = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C8FF),
                  foregroundColor: Colors.black),
              child: const Text('Freeze'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // Calculate source timestamp.
    final relMs = (_playheadPos - track.startOffset)
        .inMilliseconds
        .clamp(0, track.effectiveDuration.inMilliseconds);
    final sourceMs =
        (relMs * track.speed + track.trimStart.inMilliseconds).toInt();
    final seekSec = sourceMs / 1000.0;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir  = await getTemporaryDirectory();
    final outPath = p.join(tmpDir.path,
        'freeze_${track.id}_${DateTime.now().millisecondsSinceEpoch}.png');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(width: 16),
          Text('Ekstrakcija kadra…',
              style: TextStyle(color: Colors.white)),
        ]),
      ),
    );

    final session = await FFmpegKit.executeWithArguments([
      '-y', '-ss', seekSec.toStringAsFixed(3),
      '-i', track.filePath,
      '-frames:v', '1', '-q:v', '1', outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!ReturnCode.isSuccess(rc) || !File(outPath).existsSync()) {
      _snack('Ekstrakcija kadra nije uspjela.', error: true);
      return;
    }

    // Insert frozen image track right at the current playhead position.
    _pushUndo();
    final frozenTrack = TimelineTrack(
      id:          TimelineTrack.generateId(),
      filePath:    outPath,
      title:       'Frozen frame',
      trackType:   TrackType.image,
      duration:    Duration(milliseconds: (freezeSecs * 1000).round()),
      startOffset: _playheadPos,
      color:       const Color(0xFF00C8FF),
      overlayScale: track.overlayScale,
      overlayX:     track.overlayX,
      overlayY:     track.overlayY,
    );
    setState(() {
      // Insert directly above the source video track.
      final insertAt = (_selectedIndex! + 1).clamp(0, _tracks.length);
      _tracks.insert(insertAt, frozenTrack);
    });
    _snack('Frozen frame added to the timeline.');
  }

  // ── Voice Effect ───────────────────────────────────────────────────────

  static String _voiceFilterFor(int index) {
    switch (index) {
      case 1: return 'aecho=0.8:0.88:60:0.4';
      case 2: return 'asetrate=55125,aresample=44100';
      case 3: return 'asetrate=49392,aresample=44100';
      case 4: return 'asetrate=38808,aresample=44100';
      case 5: return 'aecho=0.8:0.88:40|70|100:0.3|0.2|0.1';
      case 6: return 'tremolo=f=20:d=0.9,aecho=0.9:0.7:6:0.6';
      case 7: return 'asetrate=66150,aresample=44100,aecho=0.6:0.5:5:0.7';
      case 8: return 'asetrate=33075,aresample=44100,aecho=0.7:0.7:80:0.3';
      default: return '';
    }
  }

  Future<void> _generateVoicePreview(TimelineTrack track) async {
    if (track.voiceEffectIndex == 0) {
      _voicePreviewPaths.remove(track.id);
      return;
    }
    final filter = _voiceFilterFor(track.voiceEffectIndex);
    if (filter.isEmpty) return;

    final tmpDir = await getTemporaryDirectory();
    // Key includes effect index so switching effects regenerates the file.
    final outPath =
        '${tmpDir.path}/ve_vp_${track.id}_${track.voiceEffectIndex}.aac';

    // Reuse cached file if it already exists for this track+effect combo.
    if (File(outPath).existsSync()) {
      if (mounted) setState(() => _voicePreviewPaths[track.id] = outPath);
      return;
    }

    // Remove any stale preview for a different effect on the same track.
    if (mounted) setState(() {
      _voicePreviewPaths.remove(track.id);
      _voicePreviewGenerating = true;
    });

    // Process only the first 30 s — fast enough to finish in 2-3 s.
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', track.filePath,
      '-vn',
      '-t', '30',
      '-af', filter,
      '-c:a', 'aac',
      '-b:a', '128k',
      outPath,
    ]);
    final rc = await session.getReturnCode();
    if (mounted) setState(() {
      _voicePreviewGenerating = false;
      if (ReturnCode.isSuccess(rc)) {
        _voicePreviewPaths[track.id] = outPath;
      } else {
        debugPrint('Voice preview gen failed for ${track.title}');
      }
    });
  }

  // ── Chroma Key video preview generation ───────────────────────────────────
  // Processes the first 30 s of the track with the chromakey filter applied
  // over a black background, stores the result in _chromakeyPreviewPaths, and
  // reinitialises the VideoPlayerController so the editor preview shows the effect.
  Future<void> _generateChromakeyPreview(TimelineTrack track) async {
    if (!track.chromakeyEnabled || !track.isVideo) {
      // Effect removed — release preview and reinit with original file.
      _chromakeyPreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final c   = track.chromakeyColor;
    final rh  = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final gh  = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final bh  = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    final sim = track.chromakeySimilarity.toStringAsFixed(3);
    final bld = track.chromakeyBlend.toStringAsFixed(3);

    final tmpDir  = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/ck_video_${track.id}.mp4';

    if (mounted) setState(() {
      _chromakeyPreviewPaths.remove(track.id);
      _chromakeyPreviewGenerating = true;
    });

    // Split input into background (black fill) + chromakeyed overlay, composite.
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '30',
      '-i', track.filePath,
      '-filter_complex',
      '[0:v]split[orig][copy];'
      '[orig]chromakey=color=0x$rh$gh$bh:similarity=$sim:blend=$bld[ck];'
      '[copy]drawbox=x=0:y=0:w=iw:h=ih:color=black@1:t=fill[bg];'
      '[bg][ck]overlay=format=auto[out]',
      '-map', '[out]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'copy',
      outPath,
    ]);

    final rc = await session.getReturnCode();
    if (mounted) {
      setState(() {
        _chromakeyPreviewGenerating = false;
        if (ReturnCode.isSuccess(rc)) {
          _chromakeyPreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Chromakey preview gen failed for ${track.title}');
        }
      });
      // Force the controller to reinit using the processed video.
      _releaseVideoController(track.id);
    }
  }

  // ── Stabilizer video preview generation ──────────────────────────────────
  // 2-pass VidStab on the full track (capped at 60 s for speed). Stores the
  // processed clip in _stabPreviewPaths and reinitialises the controller so
  // the editor preview shows the stabilised result immediately after toggle.
  Future<void> _generateStabPreview(TimelineTrack track) async {
    if (!track.isStabilized || !track.isVideo) {
      // Stabilization removed — release preview and reinit with original.
      _stabPreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final tmpDir  = await getTemporaryDirectory();
    final trfPath = '${tmpDir.path}/stab_${track.id}.trf';
    final outPath = '${tmpDir.path}/stab_video_${track.id}.mp4';

    if (mounted) setState(() {
      _stabPreviewPaths.remove(track.id);
      _stabPreviewGenerating = true;
    });

    // Pass 1: analyse camera motion.
    final pass1 = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '60',
      '-i', track.filePath,
      '-vf', 'vidstabdetect=stepsize=6:shakiness=8:accuracy=9:result=$trfPath',
      '-f', 'null', '/dev/null',
    ]);

    final rc1 = await pass1.getReturnCode();
    if (!mounted || !ReturnCode.isSuccess(rc1)) {
      if (mounted) setState(() => _stabPreviewGenerating = false);
      debugPrint('Stabilizer pass-1 failed for ${track.title}');
      return;
    }

    // Pass 2: apply stabilisation + mild sharpening to compensate for crop.
    final pass2 = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '60',
      '-i', track.filePath,
      '-vf',
      'vidstabtransform=input=$trfPath:zoom=1:smoothing=10'
      ',unsharp=5:5:-0.8:3:3:-0.4',
      '-map', '0:v',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'copy',
      outPath,
    ]);

    final rc2 = await pass2.getReturnCode();
    if (mounted) {
      setState(() {
        _stabPreviewGenerating = false;
        if (ReturnCode.isSuccess(rc2)) {
          _stabPreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Stabilizer pass-2 failed for ${track.title}');
        }
      });
      // Force controller to reinit using the stabilised clip.
      _releaseVideoController(track.id);
    }
  }

  // Runs FFmpeg `reverse` on the trimmed segment (capped at 60 s for speed),
  // stores the result in _reversePreviewPaths, and reinitialises the controller
  // so the preview shows the reversed clip immediately after toggle.
  Future<void> _generateReversePreview(TimelineTrack track) async {
    if (!track.playBackwards || !track.isVideo) {
      // Reverse removed — release preview and reinit with original file.
      _reversePreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final tmpDir  = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/reverse_video_${track.id}.mp4';

    if (mounted) setState(() {
      _reversePreviewPaths.remove(track.id);
      _reversePreviewGenerating = true;
    });

    final ts = track.trimStart.inMicroseconds / 1e6;
    final rawDur = track.duration - track.trimStart - track.trimEnd;
    // Cap at 60 s so the preview renders quickly on mobile.
    final capSecs = (rawDur.inMicroseconds / 1e6).clamp(0.1, 60.0);

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', ts.toStringAsFixed(3),
      '-t',  capSecs.toStringAsFixed(3),
      '-i',  track.filePath,
      '-vf', 'reverse',
      '-an',             // skip audio — avoids areverse errors on silent clips
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      outPath,
    ]);

    final rc = await session.getReturnCode();
    if (mounted) {
      setState(() {
        _reversePreviewGenerating = false;
        if (ReturnCode.isSuccess(rc)) {
          _reversePreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Reverse preview failed for ${track.title}');
        }
      });
      // Force controller to reinit using the reversed clip.
      _releaseVideoController(track.id);
    }
  }

  void _showVoiceDialog() {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isAudio && !track.isVideo) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeVoiceDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        // Kick off preview audio generation so playback uses the effect.
        _generateVoicePreview(_tracks[idx]);
      },
      onCancel: () {
        setState(() => _tracks[idx] = snapshot[idx]);
        _voicePreviewPaths.remove(track.id);
      },
    );
  }

  // ── Chroma Key / Green Screen ──────────────────────────────────────────
  void _showChromakeyDialog() {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeChromakeyDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
      onConfirm: (finalTrack) {
        _undoStack.add(snapshot);
        setState(() => _tracks[idx] = finalTrack);
        _stopPlayback();
        _generateChromakeyPreview(finalTrack);
      },
      onCancel: () {
        setState(() => _tracks[idx] = snapshot[idx]);
        _chromakeyPreviewPaths.remove(track.id);
        _releaseVideoController(track.id);
      },
    );
  }

  // ── Stabilizer ─────────────────────────────────────────────────────────
  void _toggleStabilizer() {
    if (_selectedIndex == null) return;
    if (_stabPreviewGenerating) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;
    _pushUndo();
    final newTrack = track.copyWith(isStabilized: !track.isStabilized);
    setState(() {
      _tracks[_selectedIndex!] = newTrack;
    });
    _stopPlayback();
    // Kick off 2-pass VidStab preview (or release preview if toggled off).
    _generateStabPreview(newTrack);
  }

  /// Called from the vertical drag handle on each row.
  /// [dy] is the raw pointer delta from this move event.
  void _onRowReorderMove(double dy) {
    if (!_rowReorderActive || _rowReorderIdx == null) return;
    _rowReorderAccumDy += dy;
    final curr = _rowReorderIdx!;

    if (_rowReorderAccumDy < 0 && curr > 0) {
      final threshold = _rowHeightFor(_tracks[curr - 1]) / 2;
      if (_rowReorderAccumDy.abs() >= threshold) {
        final consumed = _rowHeightFor(_tracks[curr - 1]);
        setState(() {
          final tmp = _tracks.removeAt(curr);
          _tracks.insert(curr - 1, tmp);
          _rowReorderIdx = curr - 1;
          if (_selectedIndex == curr) _selectedIndex = curr - 1;
        });
        _rowReorderAccumDy += consumed;
      }
    } else if (_rowReorderAccumDy > 0 && curr < _tracks.length - 1) {
      final threshold = _rowHeightFor(_tracks[curr + 1]) / 2;
      if (_rowReorderAccumDy >= threshold) {
        final consumed = _rowHeightFor(_tracks[curr + 1]);
        setState(() {
          final tmp = _tracks.removeAt(curr);
          _tracks.insert(curr + 1, tmp);
          _rowReorderIdx = curr + 1;
          if (_selectedIndex == curr) _selectedIndex = curr + 1;
        });
        _rowReorderAccumDy -= consumed;
      }
    }
  }

  Future<void> _showEqSheet() async {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isAudio) return;

    await _stopPlayback();
    if (!mounted) return;

    await showVeEqSheet(
      context: context,
      track: track,
      onApplied: (tempPath, gains) {
        _pushUndo();
        _releaseAudioPlayer(track.id);
        final savedOriginal = track.preEqFilePath ?? track.filePath;
        final updated = track.copyWith(
          filePath: tempPath,
          duration: track.effectiveDuration,
          trimStart: Duration.zero,
          trimEnd: Duration.zero,
          eqApplied: true,
          preEqFilePath: savedOriginal,
          eqGains: gains,
        );
        setState(() => _tracks[idx] = updated);
        _extractWaveform(updated.id, tempPath);
      },
      onRestored: () {
        _pushUndo();
        final origPath = track.preEqFilePath!;
        _releaseAudioPlayer(track.id);
        final restored = track.copyWith(
          filePath: origPath,
          duration: track.duration,
          trimStart: Duration.zero,
          trimEnd: Duration.zero,
          eqApplied: false,
          preEqFilePath: null,
          eqGains: null,
        );
        setState(() => _tracks[idx] = restored);
        _extractWaveform(restored.id, origPath);
      },
    );
  }

  void _showVolumeDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeVolumeDialog(
      context: context,
      track: track,
      onSetVolume: (v) {
        if (track.isVideo) _videoControllers[track.id]?.setVolume(v.clamp(0.0, 1.0));
        else _audioPlayers[track.id]?.setVolume(v);
      },
      onApply: (v) {
        _pushUndo();
        setState(() => _tracks[idx] = _tracks[idx].copyWith(volume: v));
        if (track.isVideo) _videoControllers[track.id]?.setVolume(v.clamp(0.0, 1.0));
        else _audioPlayers[track.id]?.setVolume(v);
      },
    );
  }

  void _showSpeedDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeSpeedDialog(
      context: context,
      track: track,
      onSetSpeed: (v) {
        if (track.isVideo) _videoControllers[track.id]?.setPlaybackSpeed(v);
        else _audioPlayers[track.id]?.setPlaybackRate(v);
      },
      onApply: (v) {
        _pushUndo();
        setState(() => _tracks[idx] = _tracks[idx].copyWith(speed: v));
        if (track.isVideo) _videoControllers[track.id]?.setPlaybackSpeed(v);
        else _audioPlayers[track.id]?.setPlaybackRate(v);
      },
    );
  }

  void _showFadeDialog({required bool isFadeIn}) {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeFadeDialog(
      context: context,
      track: track,
      isFadeIn: isFadeIn,
      onLiveUpdate: (v) => setState(() {
        _tracks[idx] = isFadeIn
            ? _tracks[idx].copyWith(fadeInSecs: v)
            : _tracks[idx].copyWith(fadeOutSecs: v);
      }),
      onConfirm: _pushUndo,
      onCancel: () => setState(() => _tracks[idx] = track),
    );
  }

  void _showOpacityDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    showVeOpacityDialog(
      context: context,
      track: track,
      onLiveUpdate: (v) =>
          setState(() => _tracks[idx] = _tracks[idx].copyWith(opacity: v)),
      onConfirm: _pushUndo,
      onCancel: () => setState(() => _tracks[idx] = track),
    );
  }

  // ── Filters bottom sheet ─────────────────────────────────────────────────
  void _showFiltersDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeFiltersDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        setState(() {});
        _stopPlayback();
      },
      onCancel: () => setState(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Filters bottom sheet — see video_editor_filters_dialog.dart ─────────────

  // ── Shadow / glow — see video_editor_glow_shadow_dialog.dart ──────────────
  void _showGlowShadowDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeGlowShadowDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        setState(() {});
        _stopPlayback();
      },
      onCancel: () => setState(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Mask — see video_editor_mask_dialog.dart ──────────────────────────────
  void _showMaskDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeMaskDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        setState(() {});
        _stopPlayback();
      },
      onCancel: () => setState(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Transition dialog ────────────────────────────────────────────────────
  void _showTransitionDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);

    // Start looping transition preview animation
    _transitionAnimTimer?.cancel();
    setState(() {
      _transitionPreviewActive = true;
      _transitionPreviewType = track.transitionInType;
      _transitionAnimProgress = 0.0;
    });

    int ticks = 0;
    _transitionAnimTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        ticks++;
        // Loop: 0→1 over 1.4s, then hold at 0 for 0.2s before repeating
        final raw = (ticks * 16 / 1400.0) % 1.2;
        final progress = (raw / 1.0).clamp(0.0, 1.0);
        if (mounted) setState(() => _transitionAnimProgress = progress);
      },
    );

    showVeTransitionsDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) {
        setState(() {
          _tracks[idx] = t;
          _transitionPreviewType = t.transitionInType;
        });
      },
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        setState(() {});
      },
      onCancel: () => setState(() => _tracks[idx] = snapshot[idx]),
    ).then((_) {
      _transitionAnimTimer?.cancel();
      _transitionAnimTimer = null;
      if (mounted) {
        setState(() {
          _transitionPreviewActive = false;
          _transitionAnimProgress = 0.0;
          _transitionPreviewType = TransitionType.none;
        });
      }
    });
  }

  // ── Open crop screen ─────────────────────────────────────────────────────
  void _openCropScreen() {
    final idx = _selectedIndex;
    if (idx == null) return;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoCropScreen(
        track: track,
        onApply: (cx, cy, cw, ch, rot) {
          if (!mounted) return;
          setState(() {
            _tracks[idx] = _tracks[idx].copyWith(
              cropX: cx,
              cropY: cy,
              cropW: cw,
              cropH: ch,
              cropRotation: rot,
            );
          });
        },
      ),
    ));
  }

  /// Max height for bottom sheet popups — stays below the video preview panel.
  double get _sheetMaxHeight {
    final mq = MediaQuery.of(context);
    const double kBannerH = 50;
    return (mq.size.height - mq.padding.top - kToolbarHeight - kBannerH - _previewHeight)
        .clamp(200.0, double.infinity);
  }

  void _showTextEditDialog({required bool isNew}) {
    final existingIdx = isNew ? null : _selectedIndex;
    if (!isNew && existingIdx == null) return;

    if (isNew) {
      final snapshot = List<TimelineTrack>.from(_tracks);
      final isFirstTrack = _tracks.isEmpty;
      final newTrack = TimelineTrack(
        id: TimelineTrack.generateId(),
        filePath: '',
        title: 'Text',
        trackType: TrackType.text,
        duration: const Duration(seconds: 30),
        startOffset: _playheadPos,
        color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        textContent: '',
        fontSize: 48.0,
        textColor: Colors.white,
        textBgColor: Colors.black,
        textBgOpacity: 0.0,
        textBold: false,
        textItalic: false,
        overlayX: 0.0,
        overlayY: 0.0,
      );
      setState(() {
        _tracks.add(newTrack);
        _selectedIndex = _tracks.length - 1;
      });
      final trackIdx = _tracks.length - 1;
      if (isFirstTrack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoZoomToFit();
        });
      }
      showVeTextEditDialog(
        context: context,
        baseTrack: newTrack,
        maxHeight: _sheetMaxHeight,
        onLiveUpdate: (t) => setState(() => _tracks[trackIdx] = t),
        onConfirm: () {
          _undoStack.add(snapshot);
          setState(() {});
        },
        onCancel: () => setState(() {
          _tracks.removeLast();
          _selectedIndex = _tracks.isEmpty ? null : _tracks.length - 1;
        }),
      );
    } else {
      final idx = existingIdx!;
      final snapshot = List<TimelineTrack>.from(_tracks);
      showVeTextEditDialog(
        context: context,
        baseTrack: _tracks[idx],
        maxHeight: _sheetMaxHeight,
        onLiveUpdate: (t) => setState(() => _tracks[idx] = t),
        onConfirm: () {
          _undoStack.add(snapshot);
          setState(() {});
        },
        onCancel: () => setState(() => _tracks[idx] = snapshot[idx]),
      );
    }
  }
  void _showScaleDialog() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    showVeScaleDialog(
      context: context,
      track: track,
      onApply: (v) {
        _pushUndo();
        final idx = _selectedIndex!;
        setState(() => _tracks[idx] = _tracks[idx].copyWith(overlayScale: v));
      },
    );
  }
  void _resetOverlayPosition() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    setState(() {
      _tracks[_selectedIndex!] = _tracks[_selectedIndex!].copyWith(
        overlayX: 0.0,
        overlayY: 0.0,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _confirmDiscard() async {
    if (_tracks.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: const Text('Save project?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to save this project as a draft before leaving?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard',
                style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save Draft',
                style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result == 'save') {
      await _saveDraftNow();
      if (mounted) Navigator.of(context).pop(true);
    } else if (result == 'discard') {
      Navigator.of(context).pop(false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  static const Color _bgColor = Color(0xFF0D1623);
  static const Color _surfaceColor = Color(0xFF111E2F);
  static const Color _onSurface = Colors.white;

  @override
  Widget build(BuildContext context) {
    final timelineW = _totalDuration.inSeconds.toDouble() * _pps;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      backgroundColor: _bgColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Feature banner (shimmer → content) ────────────────────────
          _buildBanner(),
          // ── Video preview ──────────────────────────────────────────────
          _buildPreviewPanel(),
          // ── Labels panel + Timeline ───────────────────────────────────
          Expanded(
            child: Row(
              children: [
                SizedBox(width: _kLabelPanelW, child: _buildLabelsPanel()),
                Expanded(child: _buildTimeline(timelineW)),
              ],
            ),
          ),
          // ── Add bar ───────────────────────────────────────────────────
          _buildAddBar(),
          // ── Bottom toolbar ────────────────────────────────────────────
          _buildBottomToolbar(),
        ],
      ),
    ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _bgColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: _onSurface),
        onPressed: _confirmDiscard,
      ),
      title: const Text(
        'Video Editor',
        style: TextStyle(
            color: _onSurface, fontWeight: FontWeight.w600, fontSize: 17),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.undo,
            color: _undoStack.isEmpty
                ? _onSurface.withValues(alpha: 0.3)
                : _onSurface,
          ),
          onPressed: _undoStack.isEmpty ? null : _undo,
        ),
        IconButton(
          icon: Icon(
            Icons.redo,
            color: _redoStack.isEmpty
                ? _onSurface.withValues(alpha: 0.3)
                : _onSurface,
          ),
          onPressed: _redoStack.isEmpty ? null : _redo,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _isSaving
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: _onSurface, strokeWidth: 2),
                  ),
                )
              : ElevatedButton(
                  onPressed: _exportVideo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B5BD6),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    minimumSize: const Size(60, 36),
                  ),
                  child: const Text('EXPORT',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ),
        ),
      ],
    );
  }

  // ── AdMob banner ──────────────────────────────────────────────────────────

  Widget _buildBanner() => const BannerAdWidget();

  // ── Preview panel ─────────────────────────────────────────────────────────

  Widget _buildPreviewPanel() {
    return Container(
      height: _previewHeight,
      color: Colors.black,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Video content — constrained to 16:9 so the preview exactly
          // represents the exported result (FFmpeg always outputs 16:9).
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRect(child: _buildPreviewContent()),
            ),
          ),
            // Playhead time overlay
            Positioned(
              bottom: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(_playheadPos),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
            // Total duration overlay (right side)
            Positioned(
              bottom: 10,
              right: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(_totalDuration),
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
            // Fullscreen button (bottom-right corner)
            Positioned(
              bottom: 6,
              right: 6,
              child: GestureDetector(
                onTap: _showFullscreenPreview,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.fullscreen,
                      color: Colors.white70, size: 20),
                ),
              ),
            ),
            // Resize handle at bottom — gesture only on this strip
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  setState(() {
                    _previewHeight = (_previewHeight + d.delta.dy)
                        .clamp(kVePreviewMinHeight, 320.0);
                  });
                },
                child: Container(
                  height: 16,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  void _showFullscreenPreview() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => _FullscreenPreviewOverlay(editorState: this),
    ).whenComplete(() {
      // Reset measured text size — fullscreen uses a different canvas size so
      // the measurement taken there would corrupt button positions in the editor.
      if (mounted) setState(() { _textOverlaySize = Size.zero; _measuredTrackId = null; });
    });
  }

  Widget _buildPreviewContent() {
    return LayoutBuilder(builder: (context, constraints) {
      final cw = constraints.maxWidth;
      final ch = constraints.maxHeight;
      return _buildPreviewLayers(cw, ch);
    });
  }

  /// Returns the content widget of the most recent video/image track that
  /// ended at or before [incoming.startOffset], to be used as the outgoing
  /// frame during a transition.  Returns null when there is no such track.
  Widget? _buildOutgoingContent(TimelineTrack incoming) {
    // Find the last video/image track that STARTS before the incoming track.
    // Using startOffset (not endTime) avoids missing adjacent clips where
    // endTime == incoming.startOffset due to Duration precision.
    TimelineTrack? prev;
    for (final t in _tracks) {
      if (t.id == incoming.id) continue;
      if (!t.isVideo && !t.isImage) continue;
      if (t.startOffset >= incoming.startOffset) continue;
      if (prev == null || t.startOffset > prev.startOffset) prev = t;
    }
    if (prev == null) return null;

    if (prev.isVideo) {
      final vc = _videoControllers[prev.id];

      // Prefer the live VideoPlayerController — it holds the exact last frame
      // that was playing, so there is no visible freeze or snap at the
      // transition start.  The thumbnail is only a fallback for when the
      // controller is not yet initialised.
      if (vc != null && vc.value.isInitialized) {
        Widget w = AspectRatio(
          aspectRatio: vc.value.aspectRatio,
          child: VideoPlayer(vc),
        );
        if (prev.hasColorMatrix) {
          w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
        }
        if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
        return Container(color: Colors.black, child: Center(child: w));
      }

      // Fallback: last filmstrip thumbnail.
      final thumb = prev.thumbnailPaths.isNotEmpty
          ? prev.thumbnailPaths.last
          : null;
      if (thumb != null) {
        Widget w = Image.file(File(thumb), fit: BoxFit.cover);
        if (prev.hasColorMatrix) {
          w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
        }
        if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
        return Container(color: Colors.black, child: Center(child: w));
      }
      return null;
    }

    if (prev.isImage) {
      // Images in the live preview use BoxFit.contain — match that here.
      Widget w = Image.file(File(prev.filePath), fit: BoxFit.contain,
          cacheWidth: 1920);
      if (prev.hasColorMatrix) {
        w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
      }
      if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
      return Container(color: Colors.black, child: Center(child: w));
    }

    return null;
  }

  Widget _buildPreviewLayers(double cw, double ch, {bool interactive = true}) {
    // Build the preview by iterating _tracks in order so that z-ordering
    // matches the timeline (first track = bottom layer, last = top layer).
    final layers = <Widget>[];
    for (final t in _tracks) {
      if (_playheadPos < t.startOffset || _playheadPos >= t.endTime) continue;

      Widget? content;
      if (t.isVideo) {
        final vc = _videoControllers[t.id];
        if (vc == null || !vc.value.isInitialized) continue;
        final fadeOpacity = _previewFadeOpacity(t.id);
        Widget videoWidget = AspectRatio(
          aspectRatio: vc.value.aspectRatio,
          child: VideoPlayer(vc),
        );
        if (t.hasColorMatrix) {
          videoWidget = ColorFiltered(
            colorFilter: t.colorFilter,
            child: videoWidget,
          );
        }
        if (t.blurRadius > 0.0) {
          videoWidget = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: t.blurRadius,
              sigmaY: t.blurRadius,
              tileMode: TileMode.clamp,
            ),
            child: videoWidget,
          );
        }
        Widget rotatedVideo = _applyRotationForPreview(t.rotation, videoWidget);
        if (t.mirrorH) {
          rotatedVideo = Transform.scale(scaleX: -1.0, child: rotatedVideo);
        }
        if (t.hasShadow) {
          rotatedVideo = DecoratedBox(
            decoration: BoxDecoration(boxShadow: [t.boxShadow]),
            child: rotatedVideo,
          );
        }
        Widget videoContent = Center(child: rotatedVideo);
        if (t.grainStrength > 0.0 || t.vignetteStrength > 0.0) {
          videoContent = Stack(children: [
            videoContent,
            if (t.grainStrength > 0.0)
              Positioned.fill(
                child: VeGrainOverlay(strength: t.grainStrength),
              ),
            if (t.vignetteStrength > 0.0)
              Positioned.fill(child: _buildVignetteOverlay(t.vignetteStrength)),
          ]);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: videoContent,
        );
      } else if (t.isImage) {
        final fadeOpacity = _previewFadeOpacity(t.id);
        Widget imageWidget = Image.file(
          File(t.filePath),
          fit: BoxFit.contain,
          cacheWidth: 1920,
        );
        if (t.hasColorMatrix) {
          imageWidget = ColorFiltered(
            colorFilter: t.colorFilter,
            child: imageWidget,
          );
        }
        if (t.blurRadius > 0.0) {
          imageWidget = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: t.blurRadius,
              sigmaY: t.blurRadius,
              tileMode: TileMode.clamp,
            ),
            child: imageWidget,
          );
        }
        Widget rotatedImage = _applyRotationForPreview(t.rotation, imageWidget);
        if (t.mirrorH) {
          rotatedImage = Transform.scale(scaleX: -1.0, child: rotatedImage);
        }
        if (t.hasShadow) {
          rotatedImage = DecoratedBox(
            decoration: BoxDecoration(boxShadow: [t.boxShadow]),
            child: rotatedImage,
          );
        }
        Widget imageContent = Center(child: rotatedImage);
        if (t.grainStrength > 0.0 || t.vignetteStrength > 0.0) {
          imageContent = Stack(children: [
            imageContent,
            if (t.grainStrength > 0.0)
              Positioned.fill(
                child: VeGrainOverlay(strength: t.grainStrength),
              ),
            if (t.vignetteStrength > 0.0)
              Positioned.fill(child: _buildVignetteOverlay(t.vignetteStrength)),
          ]);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: imageContent,
        );
      }
      else if (t.isText) {
        final fadeOpacity = _previewFadeOpacity(t.id);
        final blendMode =
            kVeTextBlendModes[t.textBlendModeIndex.clamp(0, kVeTextBlendModes.length - 1)].mode;
        final isTextSelected = interactive &&
            _selectedIndex != null &&
            _tracks[_selectedIndex!].id == t.id;
        Widget textW = Center(child: _buildTextWidget(t, selected: isTextSelected));
        if (blendMode != BlendMode.srcOver) {
          textW = VeBlendLayer(blendMode: blendMode, child: textW);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: textW,
        );
      }
      if (content == null) continue;

      // Apply crop for video/image tracks.
      if (t.hasCrop && !t.isText) {
        content = _applyCropForPreview(content, t);
      }

      // Apply mask for video/image tracks (after crop, before overlay transforms).
      if (t.hasMask && !t.isText) {
        content = _applyMaskForPreview(content, t);
      }

      // Status badges — shown as small overlay labels in the preview corner.
      if (!t.isText) {
        final badges = <Widget>[];
        if (t.playBackwards) {
          badges.add(_previewBadge('⏪ REVERSE', Colors.orange));
        }
        if (t.isStabilized) {
          badges.add(_previewBadge('⚡ STABILIZED', const Color(0xFF00C8FF)));
        }
        if (t.chromakeyEnabled) {
          badges.add(_previewBadge('🎬 GREEN SCR', const Color(0xFF00D26A)));
        }
        if (t.voiceEffectIndex > 0) {
          const names = ['', 'HALL', 'GIRL', 'WOMAN', 'BOY', 'MULTIPLE', 'ROBOT', 'ALIEN', 'FOREIGNER'];
          final n = names[t.voiceEffectIndex.clamp(0, names.length - 1)];
          badges.add(_previewBadge('🎙 $n', const Color(0xFF1E88E5)));
        }
        if (badges.isNotEmpty) {
          content = Stack(children: [
            content,
            Positioned(
              top: 6, left: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: badges,
              ),
            ),
          ]);
        }
      }

      // Apply overlay scale + position transforms.
      // overlayScale < 1.0 shrinks the clip; overlayX/Y shift the center.
      // canvasScale maps the reference canvas height to the actual canvas height
      // so that text/overlay sizes are consistent across all preview sizes and export.
      final isSelected = interactive &&
          _selectedIndex != null &&
          _tracks[_selectedIndex!].id == t.id;
      final canvasScale = t.isText ? ch / kVeRefCanvasH : 1.0;
      final transformedContent = Transform.translate(
        offset: Offset(t.overlayX * cw / 2, t.overlayY * ch / 2),
        child: Transform.scale(
          scale: t.overlayScale * canvasScale,
          child: content,
        ),
      );

      Widget layer;
      if (isSelected) {
        // Selected track: pan (1 finger) moves, pinch (2 fingers) scales+rotates.
        // Tap detection is done in onScaleEnd (no movement/scale = tap) so that
        // onTap never competes with ScaleGestureRecognizer and causes delay.
        layer = Positioned.fill(
          key: ValueKey('drag_${t.id}'),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (details) {
              _canvasTapDownPosition = details.localFocalPoint;
              if (_selectedIndex == null) return;
              final idx = _selectedIndex!;
              _overlayBaseScale = _tracks[idx].overlayScale;
              _overlayBaseRotation = _tracks[idx].textRotation;
            },
            onScaleUpdate: (details) {
              if (_selectedIndex == null) return;
              final idx = _selectedIndex!;
              if (details.pointerCount == 1) {
                // Single finger: pan
                final dx = details.focalPointDelta.dx / (cw / 2);
                final dy = details.focalPointDelta.dy / (ch / 2);
                setState(() {
                  _tracks[idx] = _tracks[idx].copyWith(
                    overlayX: (_tracks[idx].overlayX + dx).clamp(-1.0, 1.0),
                    overlayY: (_tracks[idx].overlayY + dy).clamp(-1.0, 1.0),
                  );
                });
              } else {
                // Two fingers: pinch to scale + rotate
                final newScale = (_overlayBaseScale * details.scale).clamp(0.2, 5.0);
                final newRotation = _overlayBaseRotation + details.rotation * 180.0 / pi;
                setState(() {
                  _tracks[idx] = _tracks[idx].copyWith(
                    overlayScale: newScale,
                    textRotation: newRotation,
                  );
                });
              }
            },
            onScaleEnd: (details) {
              // If focal point barely moved and scale/rotation unchanged → treat as tap.
              final tapPos = _canvasTapDownPosition;
              if (tapPos == null) return;
              final moved = details.velocity.pixelsPerSecond.distance;
              if (moved > 200) return; // was a real drag/fling, not a tap
              // Check if scale or rotation changed (two-finger gesture).
              if (_selectedIndex != null) {
                final cur = _tracks[_selectedIndex!];
                final scaleDiff = (cur.overlayScale - _overlayBaseScale).abs();
                final rotDiff   = (cur.textRotation - _overlayBaseRotation).abs();
                if (scaleDiff > 0.05 || rotDiff > 2.0) return; // pinch gesture
              }
              // Looks like a tap — find which text track is at tapPos.
              for (int i = _tracks.length - 1; i >= 0; i--) {
                final track = _tracks[i];
                if (!track.isText) continue;
                final tcx = cw / 2 + track.overlayX * cw / 2;
                final tcy = ch / 2 + track.overlayY * ch / 2;
                final charCount =
                    track.textContent.isEmpty ? 4 : track.textContent.length.clamp(1, 40);
                final halfW = (track.fontSize * 0.52 * charCount * 0.5 +
                        track.textPaddingH + 8.0) *
                    track.overlayScale;
                final halfH = (track.fontSize * 0.65 + track.textPaddingV + 8.0) *
                    track.overlayScale;
                final aRad = track.textRotation * pi / 180.0;
                final cosA = cos(aRad);
                final sinA = sin(aRad);
                final dx = tapPos.dx - tcx;
                final dy = tapPos.dy - tcy;
                final localX =  dx * cosA + dy * sinA;
                final localY = -dx * sinA + dy * cosA;
                if (localX.abs() <= halfW && localY.abs() <= halfH) {
                  setState(() => _selectedIndex = i);
                  return;
                }
              }
              // Tapped on empty space — deselect.
              setState(() => _selectedIndex = null);
            },
            child: transformedContent,
          ),
        );
      } else if (t.isText) {
        // Unselected text: single tap on canvas selects it.
        final tidx = _tracks.indexOf(t);
        layer = Positioned.fill(
          key: ValueKey('tap_${t.id}'),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _selectedIndex = tidx),
            child: transformedContent,
          ),
        );
      } else {
        layer = Positioned.fill(
          key: ValueKey(t.id),
          child: transformedContent,
        );
      }
      layers.add(layer);
    }

    if (layers.isEmpty) {
      return Center(
        child: _tracks.any((t) => t.isVideo || t.isImage || t.isText)
            ? const SizedBox.shrink()
            : Text(
                'Add a video, image or text track to preview',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 13),
              ),
      );
    }

    // ── Playback transition overlays ──────────────────────────────────────
    // For each track with an active IN-transition, render it as an outgoing
    // layer on top of the incoming track content.
    for (final t in _tracks) {
      if (!t.isVideo && !t.isImage) continue;
      if (t.transitionInType == TransitionType.none) continue;
      if (_playheadPos < t.startOffset) continue;
      final transDuration = Duration(
        microseconds: (t.transitionInDuration * 1e6).round(),
      );
      final transEnd = t.startOffset + transDuration;
      if (_playheadPos >= transEnd) continue;

      final elapsed =
          (_playheadPos - t.startOffset).inMicroseconds.toDouble();
      final totalUs = transDuration.inMicroseconds.toDouble();
      final progress =
          totalUs > 0 ? (elapsed / totalUs).clamp(0.0, 1.0) : 1.0;

      layers.add(Positioned.fill(
        key: ValueKey('trans_${t.id}'),
        child: VeTransitionOverlay(
          type: t.transitionInType,
          progress: progress,
          outgoingChild: _buildOutgoingContent(t),
        ),
      ));
    }

    // ── Dialog transition preview overlay (looping, shown while dialog open)
    if (_transitionPreviewActive &&
        _transitionPreviewType != TransitionType.none &&
        _selectedIndex != null) {
      final previewTrack = _tracks[_selectedIndex!];
      layers.add(Positioned.fill(
        key: const ValueKey('_transition_overlay'),
        child: VeTransitionOverlay(
          type: _transitionPreviewType,
          progress: _transitionAnimProgress,
          outgoingChild: _buildOutgoingContent(previewTrack),
        ),
      ));
    }

    // ── Canvas-level selection controls for the selected text track ────────
    // Buttons are placed here (not inside the text widget) so they are always
    // within the canvas hit-test bounds and receive tap events correctly.
    if (interactive && _selectedIndex != null) {
      final sel = _tracks[_selectedIndex!];
      if (sel.isText) {
        // Text centre in canvas coordinates (canvas origin = top-left).
        final cx = cw / 2 + sel.overlayX * cw / 2;
        final cy = ch / 2 + sel.overlayY * ch / 2;
        const btnSize = 28.0;
        const btnR = btnSize / 2;

        // Reset measured size when a different track is selected.
        if (_measuredTrackId != sel.id) {
          _textOverlaySize = Size.zero;
          _measuredTrackId = sel.id;
        }
        // Schedule a post-frame measurement so buttons stay exact after every change.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final rb = _textOverlayKey.currentContext?.findRenderObject() as RenderBox?;
          if (rb == null || !rb.hasSize) return;
          final s = rb.size;
          if ((s.width  - _textOverlaySize.width).abs()  > 0.5 ||
              (s.height - _textOverlaySize.height).abs() > 0.5) {
            setState(() { _textOverlaySize = s; _measuredTrackId = sel.id; });
          }
        });

        // Use measured size if available; fall back to estimation on first frame.
        // The total visual scale = overlayScale * canvasScale (same as Transform.scale above).
        const pad = 8.0; // VeTextSelectionPainter._pad
        final double btnCanvasScale = ch / kVeRefCanvasH;
        final double totalScale = sel.overlayScale * btnCanvasScale;
        final double halfW, halfH;
        if (_textOverlaySize != Size.zero) {
          halfW = (_textOverlaySize.width  / 2 + pad) * totalScale;
          halfH = (_textOverlaySize.height / 2 + pad) * totalScale;
        } else {
          final charCount = sel.textContent.isEmpty ? 4 : sel.textContent.length.clamp(1, 40);
          halfW = (sel.fontSize * 0.52 * charCount * 0.5 + sel.textPaddingH + pad) * totalScale;
          halfH = (sel.fontSize * 0.65 + sel.textPaddingV + pad) * totalScale;
        }

        // Rotate a corner offset around the text centre to follow textRotation.
        final angleRad = sel.textRotation * pi / 180.0;
        final cosA = cos(angleRad);
        final sinA = sin(angleRad);
        Offset rotatedCorner(double dx, double dy) {
          return Offset(
            cx + dx * cosA - dy * sinA,
            cy + dx * sinA + dy * cosA,
          );
        }

        final topRightPt    = rotatedCorner( halfW, -halfH);
        final bottomRightPt = rotatedCorner( halfW,  halfH);
        final bottomLeftPt  = rotatedCorner(-halfW,  halfH);

        // X (delete): top-right corner of the bounding box
        final xLeft    = topRightPt.dx - btnR;
        final xTop     = topRightPt.dy - btnR;

        // Edit (pencil): bottom-right corner
        final editLeft = bottomRightPt.dx - btnR;
        final editTop  = bottomRightPt.dy - btnR;

        // Resize (drag): bottom-left corner
        final rzLeft   = bottomLeftPt.dx - btnR;
        final rzTop    = bottomLeftPt.dy - btnR;

        const kBtnBg = Color(0xFF424242);
        const kBtnFg = Colors.white;

        layers.add(
          Positioned.fill(
            key: const ValueKey('_text_sel_btns'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Delete (X) — top-right corner
                Positioned(
                  left: xLeft,
                  top: xTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.close_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onTap: _deleteTrack,
                  ),
                ),
                // Edit (pencil) — bottom-right corner
                Positioned(
                  left: editLeft,
                  top: editTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.edit_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onTap: () => _showTextEditDialog(isNew: false),
                  ),
                ),
                // Resize (drag) — bottom-left corner
                Positioned(
                  left: rzLeft,
                  top: rzTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.open_in_full_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onPanUpdate: (details) {
                      // Bottom-left corner: drag toward bottom-left = grow,
                      // toward top-right = shrink → use -dx + dy.
                      final delta = -details.delta.dx + details.delta.dy;
                      if (_selectedIndex != null) {
                        setState(() {
                          final t = _tracks[_selectedIndex!];
                          final newSize =
                              (t.fontSize + delta * 0.5).clamp(8.0, 200.0);
                          _tracks[_selectedIndex!] =
                              t.copyWith(fontSize: newSize);
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Stack(children: layers);
  }

  /// Wraps [child] in the correct rotation widget so that layout bounds change
  /// Radial vignette overlay (transparent centre → dark edges).
  Widget _buildVignetteOverlay(double strength) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.0,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: strength * 0.85),
              ],
              stops: const [0.4, 1.0],
            ),
          ),
        ),
      );

  // ── Text widget renderer ─────────────────────────────────────────────────

  Widget _buildTextWidget(TimelineTrack t, {bool selected = false}) {
    final hasBg = t.textBgOpacity > 0.0;
    final hasOutline = t.textOutlineWidth > 0.0;
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
    final textAlign = const [TextAlign.left, TextAlign.center, TextAlign.right][t.textAlignIndex.clamp(0, 2)];

    final shadowList = <Shadow>[
      if (t.hasShadow)
        Shadow(
          color: t.shadowColor.withValues(alpha: t.shadowOpacity),
          blurRadius: t.shadowRadius,
          offset: Offset(t.shadowOffsetX, t.shadowOffsetY),
        ),
      // Glow: layered concentric shadows at offset (0,0) for smooth spread
      if (t.textGlowRadius > 0) ...[
        Shadow(color: t.textGlowColor.withValues(alpha: 0.9),
            blurRadius: t.textGlowRadius * 0.4),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.7),
            blurRadius: t.textGlowRadius * 0.7),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.5),
            blurRadius: t.textGlowRadius),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.25),
            blurRadius: t.textGlowRadius * 1.6),
      ],
    ];
    List<Shadow>? shadows = shadowList.isEmpty ? null : shadowList;

    TextDecoration? decoration;
    if (t.textUnderline && t.textStrikethrough) {
      decoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
    } else if (t.textUnderline) {
      decoration = TextDecoration.underline;
    } else if (t.textStrikethrough) {
      decoration = TextDecoration.lineThrough;
    }

    TextStyle baseStyle(bool forOutline) => TextStyle(
          fontSize: t.fontSize,
          fontWeight: t.textBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: t.textItalic ? FontStyle.italic : FontStyle.normal,
          fontFamily: t.fontFamily,
          height: t.lineHeight,
          letterSpacing: t.letterSpacing,
          decoration: decoration,
          decorationColor: forOutline ? t.textOutlineColor : t.textColor,
          decorationThickness: 2.0,
          foreground: forOutline
              ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = t.textOutlineWidth * 2
                ..strokeJoin = StrokeJoin.round
                ..color = t.textOutlineColor)
              : null,
          // When gradient is on, use white so ShaderMask colorises it fully
          color: forOutline ? null : (t.textGradientEnabled ? Colors.white : t.textColor),
          shadows: forOutline ? null : shadows,
        );

    Widget fillText = Text(displayText, textAlign: textAlign, style: baseStyle(false));

    // Apply gradient via ShaderMask (srcIn = use text alpha as mask)
    if (t.textGradientEnabled) {
      final rad = t.textGradientAngle * pi / 180.0;
      fillText = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-cos(rad), -sin(rad)),
          end:   Alignment( cos(rad),  sin(rad)),
          colors: [t.textGradientColor1, t.textGradientColor2],
        ).createShader(bounds),
        child: fillText,
      );
    }

    Widget textContent;
    if (t.textPathCurve.abs() > 0.01) {
      // Curved text — render each character along a circular arc
      final approxCharW = t.fontSize * 0.65;
      final curveW = (approxCharW * displayText.length.clamp(1, 60) + 80)
          .clamp(140.0, 900.0);
      final curveH = t.fontSize * 4.0;
      Widget curveWidget = SizedBox(
        width: curveW,
        height: curveH,
        child: CustomPaint(
          painter: VeCurvedTextPainter(
            text: displayText,
            fillStyle: baseStyle(false),
            outlineStyle: hasOutline ? baseStyle(true) : null,
            curve: t.textPathCurve,
          ),
        ),
      );
      // Gradient still works — ShaderMask over the CustomPaint widget
      if (t.textGradientEnabled) {
        final rad = t.textGradientAngle * pi / 180.0;
        curveWidget = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-cos(rad), -sin(rad)),
            end:   Alignment( cos(rad),  sin(rad)),
            colors: [t.textGradientColor1, t.textGradientColor2],
          ).createShader(bounds),
          child: curveWidget,
        );
      }
      textContent = curveWidget;
    } else {
      textContent = hasOutline
          ? Stack(
              alignment: Alignment.center,
              children: [
                Text(displayText, textAlign: textAlign, style: baseStyle(true)),
                fillText,
              ],
            )
          : fillText;
    }

    final hasPadding = t.textPaddingH > 0 || t.textPaddingV > 0;
    Widget result = Container(
      key: selected ? _textOverlayKey : null,
      padding: (hasBg || hasPadding)
          ? EdgeInsets.symmetric(
              horizontal: hasPadding ? t.textPaddingH : 14,
              vertical:   hasPadding ? t.textPaddingV : 8,
            )
          : EdgeInsets.zero,
      decoration: hasBg
          ? BoxDecoration(
              color: t.textBgColor.withValues(alpha: t.textBgOpacity),
              borderRadius: BorderRadius.circular(t.textBgRadius),
            )
          : null,
      child: textContent,
    );
    // Selection overlay: dashed border + move hint icon (visual only).
    // NOTE: interactive buttons (X, edit) are rendered at canvas level
    // in _buildPreviewLayers so they remain within hit-test bounds.
    if (selected) {
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          // Dashed rounded-rect border drawn outside the widget bounds.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: const VeTextSelectionPainter()),
            ),
          ),
          // The actual text content.
          result,
          // ── Move hint — top-left (purely visual, gesture is on outer GD) ──
          Positioned(
            top: -22,
            left: -22,
            child: IgnorePointer(
              child: _VeTextCtrlBtn(
                icon: Icons.open_with_rounded,
                iconColor: Colors.white,
                bgColor: const Color(0xFF424242),
              ),
            ),
          ),
        ],
      );
    }

    if (t.textRotation != 0.0) {
      result = Transform.rotate(
        angle: t.textRotation * pi / 180.0,
        child: result,
      );
    }
    return result;
  }

  /// along with the visual rotation — matching what FFmpeg does (rotate first,
  /// then scale to fit the canvas).
  /// • 90° / 270° use [RotatedBox] which swaps width ↔ height in layout.
  /// • 180° uses [Transform.rotate] since dimensions don't change.
  Widget _applyRotationForPreview(int degrees, Widget child) {
    if (degrees == 0) return child;
    if (degrees == 180) return Transform.rotate(angle: pi, child: child);
    return RotatedBox(quarterTurns: degrees ~/ 90, child: child);
  }

  /// Applies the mask shape / feathering defined by [t.maskShapeIndex] etc.
  /// Hard clip (feather=0) uses [ClipPath]; feathered clip blurs the clipped result
  /// using [ImageFiltered] with [TileMode.decal] so the transparent boundary softens.
  Widget _applyMaskForPreview(Widget child, TimelineTrack t) {
    if (!t.hasMask) return child;

    Widget masked = ClipPath(
      clipper: VeMaskClipper(
        shapeIndex: t.maskShapeIndex,
        scale:      t.maskScale,
        inverted:   t.maskInverted,
      ),
      child: child,
    );

    if (t.maskFeather > 0) {
      final sigma = t.maskFeather * 22.0;
      masked = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: masked,
      );
    }

    return masked;
  }

  /// Small label badge shown in the preview corner to indicate active effects.
  Widget _previewBadge(String label, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
      );

  /// Applies the track's cropX/Y/W/H to the preview widget.
  /// Crop fractions are relative to the full display area (consistent with
  /// how the crop screen defines them).
  Widget _applyCropForPreview(Widget child, TimelineTrack t) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final fullW = w / t.cropW;
          final fullH = h / t.cropH;
          final tx = -(t.cropX / t.cropW) * w;
          final ty = -(t.cropY / t.cropH) * h;
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: fullW,
            minHeight: 0,
            maxHeight: fullH,
            child: Transform.translate(
              offset: Offset(tx, ty),
              child: SizedBox(
                width: fullW,
                height: fullH,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Labels panel ──────────────────────────────────────────────────────────

  static const double _kLabelPanelW = 54.0;

  // ── Transition label row (left panel) ────────────────────────────────────
  Widget _buildTransitionLabelRow() {
    return SizedBox(
      height: kVeTransitionRowHeight + kVeTrackGap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, kVeTrackGap / 2, 0, kVeTrackGap / 2),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0xFF1E3050), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              // Placeholder drag area (same width as real rows for alignment)
              const SizedBox(
                width: 22,
                child: Center(
                  child: Icon(Icons.swap_horiz_rounded,
                      color: Color(0xFF00C8FF), size: 15),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  'Transitions',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Transition timeline row ───────────────────────────────────────────────
  Widget _buildTransitionTimelineRow({
    required int trackIdx,
    required TimelineTrack track,
  }) {
    return SizedBox(
      height: kVeTransitionRowHeight + kVeTrackGap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, kVeTrackGap / 2, 0, kVeTrackGap / 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0, left: 0, right: 0, height: 1,
              child: Container(color: const Color(0xFF1E3050)),
            ),
            _buildTransitionIcon(trackIdx, track),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitionIcon(int trackIdx, TimelineTrack track) {
    final x = _secondsToX(track.startOffset.inMilliseconds / 1000.0);
    final hasTransition = track.transitionInType != TransitionType.none;
    const double iconSize = 30.0;

    // Check if there is a preceding video/image track to transition from.
    final hasPredecessor = _tracks.any((t) =>
        t.id != track.id &&
        (t.isVideo || t.isImage) &&
        t.startOffset < track.startOffset);

    // Only show the button when there is a clip before this one,
    // OR when a transition is already set (so it can be cleared).
    if (!hasPredecessor && !hasTransition) return const SizedBox.shrink();

    // Clamp so the icon never extends left of the visible area.
    final left = (x - iconSize / 2).clamp(0.0, double.maxFinite);

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: iconSize,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _selectedIndex = trackIdx);
            _showTransitionDialog();
          },
          child: Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasTransition
                  ? const Color(0xFF00C8FF).withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: hasTransition
                    ? const Color(0xFF00C8FF)
                    : Colors.white.withValues(alpha: 0.22),
                width: hasTransition ? 1.5 : 1.0,
              ),
            ),
            child: Icon(
              hasTransition
                  ? Icons.swap_horiz_rounded
                  : Icons.add_rounded,
              color: hasTransition
                  ? const Color(0xFF00C8FF)
                  : Colors.white.withValues(alpha: 0.35),
              size: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabelsPanel() {
    return Container(
      width: _kLabelPanelW,
      color: const Color(0xFF0B1621),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Matches ruler height so rows stay aligned – houses collapse-all button
          Container(
            height: kVeRulerHeight,
            decoration: const BoxDecoration(
              color: Color(0xFF0D1623),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E3050), width: 1),
                right: BorderSide(color: Color(0xFF1E3050), width: 1),
              ),
            ),
            child: Center(
              child: GestureDetector(
                onTap: _toggleAllTracks,
                child: Tooltip(
                  message: (_tracks.every(_isCollapsed) && _collapsedEmptyRows.length == 10)
                      ? 'Expand all'
                      : 'Collapse all',
                  child: Icon(
                    (_tracks.every(_isCollapsed) && _collapsedEmptyRows.length == 10)
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _labelsScrollCtrl,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  for (final e in _tracks.asMap().entries) ...[
                    _buildLabelRow(e.key, e.value),
                    if (e.value.isVideo || e.value.isImage)
                      _buildTransitionLabelRow(),
                  ],
                  ...List.generate(10, (i) => _buildEmptyLabelRow(_tracks.length + i + 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelRow(int index, TimelineTrack track) {
    final isSelected = _selectedIndex == index;
    final isReordering = _rowReorderActive && _rowReorderIdx == index;
    final collapsed = _isCollapsed(track);
    final rowH = _rowHeightFor(track);

    // Wrap tap detection over the full row height (including gap),
    // but the visible card sits only within the track area (respecting gap).
    return ClipRect(
      key: ValueKey('label_${track.id}'),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: rowH,
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: Padding(
          // Match the kVeTrackGap / 2 offset used by track blocks in the timeline.
          padding: EdgeInsets.fromLTRB(0, kVeTrackGap / 2, 0, kVeTrackGap / 2),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border(
                right: const BorderSide(color: Color(0xFF1E3050), width: 1),
                left: isSelected
                    ? BorderSide(
                        color: track.isVideo
                            ? const Color(0xFFFF6B6B)
                            : track.isText
                                ? const Color(0xFFFFD740)
                                : const Color(0xFF00C8FF),
                        width: 2,
                      )
                    : BorderSide.none,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                // ── Vertical reorder drag handle ──────────────────────
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _pushUndo();
                    _rowReorderIdx = index;
                    _rowReorderAccumDy = 0;
                    setState(() {
                      _selectedIndex = index;
                      _rowReorderActive = true;
                    });
                  },
                  onPointerMove: (e) => _onRowReorderMove(e.delta.dy),
                  onPointerUp: (_) {
                    _rowReorderIdx = null;
                    setState(() => _rowReorderActive = false);
                  },
                  onPointerCancel: (_) {
                    _rowReorderIdx = null;
                    setState(() => _rowReorderActive = false);
                  },
                  child: SizedBox(
                    width: 22,
                    height: double.infinity,
                    child: Center(
                      child: Icon(
                        Icons.drag_indicator,
                        color: Colors.white.withValues(
                            alpha: isReordering ? 0.9 : 0.3),
                        size: 16,
                      ),
                    ),
                  ),
                ),
                // ── Track type icon + name ────────────────────────────
                // OverflowBox lets the Column render at its natural size so
                // the RenderFlex never asserts during the height animation.
                // The outer ClipRect handles the visual clipping.
                Expanded(
                  child: OverflowBox(
                    maxHeight: double.infinity,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!collapsed) ...[
                          Icon(
                            track.isVideo
                                ? Icons.videocam_rounded
                                : track.isImage
                                    ? Icons.photo_library_rounded
                                    : track.isText
                                        ? Icons.title_rounded
                                        : Icons.music_note_rounded,
                            color: track.isVideo
                                ? const Color(0xFFFF6B6B).withValues(alpha: 0.85)
                                : track.isImage
                                    ? const Color(0xFF69F0AE).withValues(alpha: 0.85)
                                    : track.isText
                                        ? const Color(0xFFFFD740).withValues(alpha: 0.85)
                                        : const Color(0xFF00C8FF).withValues(alpha: 0.85),
                            size: 12,
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          track.title,
                          style: TextStyle(
                            color: Colors.white.withValues(
                                alpha: isSelected ? 0.9 : 0.55),
                            fontSize: 9,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            height: 1.2,
                          ),
                          maxLines: collapsed ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Expand / collapse button ──────────────────────────
                GestureDetector(
                  onTap: () => setState(() {
                    if (collapsed) {
                      _collapsedTracks.remove(track.id);
                    } else {
                      _collapsedTracks.add(track.id);
                    }
                  }),
                  child: SizedBox(
                    width: 16,
                    height: double.infinity,
                    child: Center(
                      child: Icon(
                        collapsed
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  // ── Timeline ──────────────────────────────────────────────────────────────

  Widget _buildTimeline(double timelineW) {
    final lockScroll = _trimActive ||
        _trackDragActive ||
        _playheadDragActive ||
        _rulerScrubActive ||
        _rowReorderActive ||
        _activePointers.length >= 2 ||
        (_pinchActive && _activePointers.isNotEmpty);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableH = constraints.maxHeight;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPinchDown,
          onPointerMove: _onPinchMove,
          onPointerUp: _onPinchUp,
          onPointerCancel: _onPinchCancel,
          child: SingleChildScrollView(
            controller: _hScrollCtrl,
            scrollDirection: Axis.horizontal,
            physics: lockScroll
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: SizedBox(
              width: timelineW + 60,
              height: availableH,
              child: Stack(children: [
                // Track rows (vertically scrollable)
                Positioned(
                  top: kVeRulerHeight,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SingleChildScrollView(
                    controller: _vScrollCtrl,
                    scrollDirection: Axis.vertical,
                    physics: lockScroll
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    child: Stack(children: [
                      // Row stripe background
                      Positioned.fill(
                        child: CustomPaint(
                          painter: VeRowStripesPainter(
                            rowHeights: [
                              for (final t in _tracks) ...[
                                _rowHeightFor(t),
                                if (t.isVideo || t.isImage)
                                  kVeTransitionRowHeight + kVeTrackGap,
                              ],
                              ...List.generate(10, (i) {
                                final idx = _tracks.length + i;
                                return (_collapsedEmptyRows.contains(idx)
                                    ? kVeCollapsedTrackHeight
                                    : kVeVideoTrackHeight) + kVeTrackGap;
                              }),
                            ],
                            colorEven: const Color(0xFF131F30),
                            colorOdd: const Color(0xFF0F1A28),
                          ),
                        ),
                      ),
                      // Track rows
                      Column(
                        children: [
                          for (final e in _tracks.asMap().entries) ...[
                            _buildTrackRow(e.key, e.value),
                            if (e.value.isVideo || e.value.isImage)
                              _buildTransitionTimelineRow(
                                  trackIdx: e.key, track: e.value),
                          ],
                          ...List.generate(10, (i) => _buildEmptyTrackRow(_tracks.length + i)),
                        ],
                      ),
                    ]),
                  ),
                ),
                // Time ruler (pinned at top) – drag to scrub
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: kVeRulerHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) =>
                        setState(() => _rulerScrubActive = true),
                    onHorizontalDragUpdate: (details) {
                      final contentX = details.localPosition.dx +
                          (_hScrollCtrl.hasClients
                              ? _hScrollCtrl.offset
                              : 0.0);
                      _seekVisualOnly(_contentXToDuration(contentX));
                    },
                    onHorizontalDragEnd: (_) {
                      setState(() => _rulerScrubActive = false);
                      _applySeek(_playheadPos);
                    },
                    onHorizontalDragCancel: () =>
                        setState(() => _rulerScrubActive = false),
                    onTapUp: (details) {
                      final contentX = details.localPosition.dx +
                          (_hScrollCtrl.hasClients
                              ? _hScrollCtrl.offset
                              : 0.0);
                      _applySeek(_contentXToDuration(contentX));
                    },
                    child: CustomPaint(
                      painter: VeRulerPainter(
                        totalSeconds:
                            _totalDuration.inSeconds.toDouble(),
                        pps: _pps,
                      ),
                    ),
                  ),
                ),
                // Playhead
                _buildPlayhead(),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayhead() {
    const double kHitPad = 20.0;
    const double totalW = kVePlayheadWidth + kHitPad * 2;
    final lineX = _secondsToX(_playheadPos.inMilliseconds / 1000.0);
    final leftEdge = (lineX - kHitPad).clamp(0.0, double.infinity);
    final lineOffset = lineX - leftEdge;

    return Positioned(
      top: 0,
      bottom: 0,
      left: leftEdge,
      width: totalW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) =>
            setState(() => _playheadDragActive = true),
        onHorizontalDragUpdate: (details) {
          final maxSecs = _contentEndTime.inMilliseconds / 1000.0;
          final newSecs =
              (_playheadPos.inMilliseconds / 1000.0 +
                      details.delta.dx / _pps)
                  .clamp(0.0, maxSecs);
          _seekVisualOnly(
              Duration(milliseconds: (newSecs * 1000).round()));
          _autoScrollToPlayhead(newSecs);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _playheadDragActive = false);
          if (_isPlaying) _startAllFromPos(_playheadPos);
        },
        onHorizontalDragCancel: () =>
            setState(() => _playheadDragActive = false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: lineOffset,
              top: 0,
              bottom: 0,
              width: kVePlayheadWidth,
              child: Container(
                color: const Color(0xFFFF4D4D),
                alignment: Alignment.topCenter,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4D4D),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(int index, TimelineTrack track) {
    final isSelected = _selectedIndex == index;
    final collapsed = _isCollapsed(track);
    final startX = _secondsToX(track.startOffset.inMilliseconds / 1000.0);
    final trackH = _trackHeightFor(track);
    final rowH = _rowHeightFor(track);
    final minW = (_pps * 2.0).clamp(2.0, 40.0);
    final trackW = _secondsToX(track.effectiveDuration.inMilliseconds / 1000.0)
        .clamp(minW, double.infinity);

    const double kDragHandleH = 18.0;

    return ClipRect(
      key: ValueKey(track.id),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: rowH,
      child: Stack(children: [
        // ── Track block ────────────────────────────────────────────────
        Positioned(
          left: startX,
          top: kVeTrackGap / 2,
          width: trackW,
          height: trackH,
          child: GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: VeTrackBlock(
              track: track,
              isSelected: isSelected,
              isCollapsed: collapsed,
              width: trackW,
              height: trackH,
              onTrimLeftStart: (_) {
                _trimHandleDown = true;
                _pushUndo();
                _trimTrackIndex = index;
                setState(() => _trimActive = true);
              },
              onTrimLeftUpdate: (deltaPx) {
                if (_trimTrackIndex != index) return;
                final curr = _tracks[index];
                final secsDelta = _xToSeconds(deltaPx);
                final maxTrim =
                    (curr.duration - curr.trimEnd).inMilliseconds /
                            1000.0 -
                        0.5;
                final newTrimSecs =
                    (curr.trimStart.inMilliseconds / 1000.0 +
                            secsDelta)
                        .clamp(0.0, maxTrim);
                final change = newTrimSecs -
                    curr.trimStart.inMilliseconds / 1000.0;
                setState(() {
                  _tracks[index] = curr.copyWith(
                    trimStart: Duration(
                        milliseconds: (newTrimSecs * 1000).round()),
                    startOffset: curr.startOffset +
                        Duration(
                            milliseconds: (change * 1000).round()),
                  );
                });
              },
              onTrimLeftEnd: (_) {
                _trimHandleDown = false;
                _trimTrackIndex = null;
                setState(() => _trimActive = false);
              },
              onTrimRightStart: (_) {
                _trimHandleDown = true;
                _pushUndo();
                _trimTrackIndex = index;
                setState(() => _trimActive = true);
              },
              onTrimRightUpdate: (deltaPx) {
                if (_trimTrackIndex != index) return;
                final curr = _tracks[index];
                final secsDelta = _xToSeconds(-deltaPx);
                final maxTrim =
                    (curr.duration - curr.trimStart).inMilliseconds /
                            1000.0 -
                        0.5;
                // Images and text have no source duration limit — allow
                // extending beyond the original 5 s by letting trimEnd go
                // negative.
                final minTrim =
                    (curr.isImage || curr.isText) ? double.negativeInfinity : 0.0;
                final newTrimSecs =
                    (curr.trimEnd.inMilliseconds / 1000.0 + secsDelta)
                        .clamp(minTrim, maxTrim);
                setState(() {
                  _tracks[index] = curr.copyWith(
                    trimEnd: Duration(
                        milliseconds: (newTrimSecs * 1000).round()),
                  );
                });
              },
              onTrimRightEnd: (_) {
                _trimHandleDown = false;
                _trimTrackIndex = null;
                setState(() => _trimActive = false);
              },
            ),
          ),
        ),

        // ── Drag handle strip (top of block) ──────────────────────────
        Positioned(
          left: startX + kVeHandleWidth,
          top: kVeTrackGap / 2,
          width: (trackW - kVeHandleWidth * 2).clamp(0.0, double.infinity),
          height: kDragHandleH,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _trackDragIndex = index;
              _trackDragStartX = e.position.dx;
              _trackDragOriginalOffset = track.startOffset;
              setState(() {
                _selectedIndex = index;
                _trackDragActive = true;
              });
            },
            onPointerMove: (e) {
              if (_trackDragIndex != index) return;
              final dx = e.position.dx - _trackDragStartX;
              final newSecs = (_trackDragOriginalOffset.inMilliseconds /
                          1000.0 +
                      _xToSeconds(dx))
                  .clamp(0.0, double.infinity);
              setState(() {
                _tracks[index] = _tracks[index].copyWith(
                  startOffset: Duration(
                      milliseconds: (newSecs * 1000).round()),
                );
              });
            },
            onPointerUp: (_) {
              if (_trackDragIndex == index) {
                _pushUndo();
                _trackDragIndex = null;
                setState(() => _trackDragActive = false);
                if (_isPlaying) _startAllFromPos(_playheadPos);
              }
            },
            onPointerCancel: (_) {
              _trackDragIndex = null;
              setState(() => _trackDragActive = false);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.drag_handle,
                  color: _onSurface.withValues(alpha: 0.55),
                  size: 14,
                ),
              ),
            ),
          ),
        ),

      ]),
    ),
    );
  }

  // ── Empty placeholder rows ────────────────────────────────────────────────

  Widget _buildEmptyTrackRow(int index) {
    final collapsed = _collapsedEmptyRows.contains(index);
    final rowH = collapsed
        ? kVeCollapsedTrackHeight + kVeTrackGap
        : kVeVideoTrackHeight + kVeTrackGap;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: rowH,
    );
  }

  Widget _buildEmptyLabelRow(int number) {
    // number is 1-based display label; index in _collapsedEmptyRows uses 0-based
    // track index passed from List.generate, which is _tracks.length + i.
    final rowIndex = number - 1; // matches the index passed to _buildEmptyTrackRow
    final collapsed = _collapsedEmptyRows.contains(rowIndex);
    final rowH = collapsed
        ? kVeCollapsedTrackHeight + kVeTrackGap
        : kVeVideoTrackHeight + kVeTrackGap;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: rowH,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, kVeTrackGap / 2, 0, kVeTrackGap / 2),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0xFF1E3050), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              // ── Drag handle (disabled) ────────────────────────────
              SizedBox(
                width: 22,
                height: double.infinity,
                child: Center(
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.white.withValues(alpha: 0.08),
                    size: 16,
                  ),
                ),
              ),
              // ── Row number ────────────────────────────────────────
              Expanded(
                child: Center(
                  child: Text(
                    '$number.',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.18),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ),
              ),
              // ── Expand/collapse ───────────────────────────────────
              GestureDetector(
                onTap: () => setState(() {
                  if (collapsed) {
                    _collapsedEmptyRows.remove(rowIndex);
                  } else {
                    _collapsedEmptyRows.add(rowIndex);
                  }
                }),
                child: SizedBox(
                  width: 16,
                  height: double.infinity,
                  child: Center(
                    child: AnimatedRotation(
                      turns: collapsed ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  // ── Add bar ───────────────────────────────────────────────────────────────

  Widget _buildAddBar() {
    return Container(
      height: 50,
      color: _surfaceColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Add Video
          GestureDetector(
            onTap: _addVideoTrack,
            child: const Icon(Icons.videocam_rounded,
                color: Color(0xFFFF6B6B), size: 22),
          ),
          // Add Image
          GestureDetector(
            onTap: _addImageTrack,
            child: const Icon(Icons.image_rounded,
                color: Color(0xFF7FD97F), size: 22),
          ),
          // Separator
          Container(width: 1, height: 28, color: Colors.white24),
          // Skip to start
          GestureDetector(
            onTap: () => _applySeek(Duration.zero),
            child: const Icon(Icons.skip_previous,
                color: Colors.white70, size: 22),
          ),
          // Rewind 10s
          GestureDetector(
            onTap: () => _applySeek(
                _playheadPos - const Duration(seconds: 10)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.fast_rewind,
                    color: Colors.white70, size: 22),
                const Positioned(
                  bottom: 0,
                  child: Text('10',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                          height: 1)),
                ),
              ],
            ),
          ),
          // Play / Pause
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                  color: Color(0xFF4D4D4D),
                  shape: BoxShape.circle),
              child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 18),
            ),
          ),
          // Forward 10s
          GestureDetector(
            onTap: () => _applySeek(
                _playheadPos + const Duration(seconds: 10)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.fast_forward,
                    color: Colors.white70, size: 22),
                const Positioned(
                  bottom: 0,
                  child: Text('10',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                          height: 1)),
                ),
              ],
            ),
          ),

          // Separator
          Container(width: 1, height: 28, color: Colors.white24),
          // Zoom out
          GestureDetector(
            onTap: () {
              final phViewX = _secondsToX(
                      _playheadPos.inMilliseconds / 1000.0) -
                  (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
              _zoomAtViewportX(_pps / kVeZoomStep, phViewX);
            },
            child: const Icon(Icons.remove_circle_outline,
                color: Colors.white54, size: 22),
          ),
          // Zoom in
          GestureDetector(
            onTap: () {
              final phViewX = _secondsToX(
                      _playheadPos.inMilliseconds / 1000.0) -
                  (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
              _zoomAtViewportX(_pps * kVeZoomStep, phViewX);
            },
            child: const Icon(Icons.add_circle_outline,
                color: Colors.white54, size: 22),
          ),
        ],
      ),
    );
  }



  // ── Bottom toolbar ────────────────────────────────────────────────────────

  Widget _buildBottomToolbar() {
    final selIsVideoOrImage = _selectedIndex != null &&
        (_tracks[_selectedIndex!].isVideo || _tracks[_selectedIndex!].isImage);
    return Container(
      height: 62,
      color: _surfaceColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          _toolBtn(Icons.music_note_rounded, 'Add Audio', _addAudioTrack,
              overrideEnabled: true),
          _toolBtn(Icons.mic_rounded, 'Record', _openRecorder,
              overrideEnabled: true),
          _toolBtn(Icons.videocam_rounded, 'Camera', _openCameraRecorder,
              overrideEnabled: true),
          _toolBtn(Icons.title_rounded, 'Add Text', _addTextTrack,
              overrideEnabled: true),
          _toolBtn(Icons.vertical_split, 'Split', _splitTrack),
          _toolBtn(Icons.delete_outline, 'Delete', _deleteTrack),
          _toolBtn(Icons.content_cut, 'Trim', _trimTrack),
          _toolBtn(Icons.volume_up_outlined, 'Volume', _showVolumeDialog),
          _toolBtn(Icons.trending_up, 'Fade In',
              () => _showFadeDialog(isFadeIn: true)),
          _toolBtn(Icons.trending_down, 'Fade Out',
              () => _showFadeDialog(isFadeIn: false)),
          _toolBtn(Icons.speed, 'Speed', _showSpeedDialog),
          _toolBtn(
            Icons.equalizer_rounded,
            'Equalizer',
            _showEqSheet,
            overrideEnabled: _selectedIndex != null &&
                _tracks[_selectedIndex!].isAudio,
          ),
          _toolBtn(Icons.opacity, 'Opacity', _showOpacityDialog,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.tune, 'Filters', _showFiltersDialog,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.flare_outlined, 'Glow', _showGlowShadowDialog,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.vignette_outlined, 'Mask', _showMaskDialog,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(
            Icons.swap_horiz_rounded,
            'Transition',
            _showTransitionDialog,
            overrideEnabled: selIsVideoOrImage,
            isActive: _selectedIndex != null &&
                _tracks[_selectedIndex!].transitionInType != TransitionType.none,
          ),
          _toolBtn(
            Icons.text_fields_rounded,
            'Edit Text',
            () => _showTextEditDialog(isNew: false),
            overrideEnabled: _selectedIndex != null &&
                _tracks[_selectedIndex!].isText,
          ),
          _toolBtn(Icons.crop_rounded, 'Crop', _openCropScreen,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.photo_size_select_large_outlined, 'Scale', _showScaleDialog,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.center_focus_strong_outlined, 'Reset Position', _resetOverlayPosition,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.rotate_90_degrees_cw_outlined, 'Rotate', _rotateTrack,
              overrideEnabled: selIsVideoOrImage),
          _toolBtn(Icons.flip_outlined, 'Mirror', _mirrorTrack,
              overrideEnabled: selIsVideoOrImage,
              isActive: _selectedIndex != null && _tracks[_selectedIndex!].mirrorH),
          _reverseToolBtn(_selectedIndex != null && _tracks[_selectedIndex!].isVideo),
          _toolBtn(Icons.pause_circle_outline, 'Freeze', _freezeFrame,
              overrideEnabled: _selectedIndex != null &&
                  _tracks[_selectedIndex!].isVideo),
          _voiceToolBtn(),
          _greenScreenToolBtn(selIsVideoOrImage),
          _stabToolBtn(_selectedIndex != null &&
              _tracks[_selectedIndex!].isVideo),
          _toolBtn(Icons.copy_outlined, 'Duplicate', _duplicateTrack),
          _toolBtn(
            Icons.audiotrack_outlined,
            'Extract Audio',
            _extractAudio,
            overrideEnabled: _selectedIndex != null &&
                _tracks[_selectedIndex!].isVideo,
          ),
          _toolBtn(
            Icons.image_outlined,
            'Export Frame',
            _exportFrame,
            overrideEnabled: _selectedIndex != null &&
                _tracks[_selectedIndex!].isVideo,
          ),
          _toolBtn(
            Icons.arrow_upward,
            'Move Up',
            _moveTrackUp,
            overrideEnabled: _selectedIndex != null && _selectedIndex! > 0,
          ),
          _toolBtn(
            Icons.arrow_downward,
            'Move Down',
            _moveTrackDown,
            overrideEnabled: _selectedIndex != null &&
                _selectedIndex! < _tracks.length - 1,
          ),
        ]),
      ),
    );
  }

  Widget _greenScreenToolBtn(bool enabled) {
    return GestureDetector(
      onTap: (enabled && !_chromakeyPreviewGenerating) ? _showChromakeyDialog : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _chromakeyPreviewGenerating
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _onSurface.withValues(alpha: 0.75),
                    )
                  : Icon(
                      Icons.blur_circular_outlined,
                      color: enabled
                          ? _onSurface
                          : _onSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Green Screen',
              style: TextStyle(
                color: enabled
                    ? _onSurface.withValues(alpha: 0.75)
                    : _onSurface.withValues(alpha: 0.22),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _reverseToolBtn(bool enabled) {
    final isActive = _selectedIndex != null &&
        _tracks[_selectedIndex!].isVideo &&
        _tracks[_selectedIndex!].playBackwards;
    return GestureDetector(
      onTap: (enabled && !_reversePreviewGenerating) ? _reverseTrack : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _reversePreviewGenerating
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF00C8FF).withValues(alpha: 0.85),
                    )
                  : Icon(
                      Icons.fast_rewind_rounded,
                      color: isActive
                          ? const Color(0xFF00C8FF)
                          : enabled
                              ? _onSurface
                              : _onSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Reverse',
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF00C8FF)
                    : enabled
                        ? _onSurface.withValues(alpha: 0.75)
                        : _onSurface.withValues(alpha: 0.22),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _stabToolBtn(bool enabled) {
    final isActive = _selectedIndex != null &&
        _tracks[_selectedIndex!].isStabilized;
    return GestureDetector(
      onTap: (enabled && !_stabPreviewGenerating) ? _toggleStabilizer : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _stabPreviewGenerating
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF00C8FF).withValues(alpha: 0.85),
                    )
                  : Icon(
                      Icons.videocam_outlined,
                      color: isActive
                          ? const Color(0xFF00C8FF)
                          : enabled
                              ? _onSurface
                              : _onSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Stabilize',
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF00C8FF)
                    : enabled
                        ? _onSurface.withValues(alpha: 0.75)
                        : _onSurface.withValues(alpha: 0.22),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _voiceToolBtn() {
    final enabled = _selectedIndex != null &&
        (_tracks[_selectedIndex!].isAudio || _tracks[_selectedIndex!].isVideo);
    return GestureDetector(
      onTap: (enabled && !_voicePreviewGenerating) ? _showVoiceDialog : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _voicePreviewGenerating
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _onSurface.withValues(alpha: 0.75),
                    )
                  : Icon(
                      Icons.record_voice_over_outlined,
                      color: enabled
                          ? _onSurface
                          : _onSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Voice',
              style: TextStyle(
                color: enabled
                    ? _onSurface.withValues(alpha: 0.75)
                    : _onSurface.withValues(alpha: 0.22),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(
      IconData icon, String label, VoidCallback? onTap,
      {bool? overrideEnabled, bool isActive = false}) {
    final enabled = overrideEnabled ?? (_selectedIndex != null);
    final activeColor = const Color(0xFF00C8FF);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: !enabled
                  ? _onSurface.withValues(alpha: 0.25)
                  : isActive
                      ? activeColor
                      : _onSurface,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: !enabled
                    ? _onSurface.withValues(alpha: 0.22)
                    : isActive
                        ? activeColor
                        : _onSurface.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

