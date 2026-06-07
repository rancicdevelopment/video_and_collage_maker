import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
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
part 'video_editor_mixin_playback.dart';
part 'video_editor_mixin_timeline.dart';
part 'video_editor_mixin_track_edit.dart';
part 'video_editor_mixin_effects.dart';
part 'video_editor_mixin_track_add.dart';
part 'video_editor_mixin_preview.dart';
part 'video_editor_mixin_build.dart';


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
      _pps = draft.pps.clamp(kVeMinPPS, kVeMaxPPS);
      _playheadPos = Duration(milliseconds: draft.playheadMs);
      if (draft.tracks.isNotEmpty) {
        // Filter out tracks whose source file is missing (keep text tracks —
        // they have filePath: '' by design, and content:// URIs are accepted).
        int removedCount = 0;
        for (final t in draft.tracks) {
          if (t.isText) {
            _tracks.add(t);
          } else if (t.filePath.startsWith('content://')) {
            _tracks.add(t); // Android media-store URI — accessible
          } else if (File(t.filePath).existsSync()) {
            _tracks.add(t);
          } else {
            removedCount++;
          }
        }
        if (removedCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _snack(
              '$removedCount track${removedCount > 1 ? 's were' : ' was'} '
              'removed — source file${removedCount > 1 ? 's' : ''} no longer found.',
              error: true,
            );
          });
        }
        // Regenerate thumbnails and waveforms for loaded tracks.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final t in _tracks) {
            if (t.isVideo) _extractThumbnails(t.id, t.filePath);
            if (t.isAudio) _extractWaveform(t.id, t.filePath);
          }
          // Scroll the timeline so the playhead is visible.
          if (_hScrollCtrl.hasClients) {
            final target = (_pps * _playheadPos.inMilliseconds / 1000.0 - 80.0)
                .clamp(0.0, _hScrollCtrl.position.maxScrollExtent);
            _hScrollCtrl.jumpTo(target);
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
      pps: _pps,
      playheadMs: _playheadPos.inMilliseconds,
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

  // ── setState wrapper (used by extension methods) ──────────────────────────
  // ignore: use_setstate_synchronously
  void _rebuild(VoidCallback fn) => setState(fn);

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final timelineW = _totalDuration.inSeconds.toDouble() * _pps;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: _kVeBgColor,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildBanner(),
            _buildPreviewPanel(),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: _kLabelPanelW, child: _buildLabelsPanel()),
                  Expanded(child: _buildTimeline(timelineW)),
                ],
              ),
            ),
            _buildAddBar(),
            _buildBottomToolbar(),
          ],
        ),
      ),
    );
  }
}
