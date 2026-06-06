import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

import '../../ad/app_open_ad_manager.dart';
import '../../ad/banner_ad_widget.dart';
import '../../data/collage_draft_manager.dart';
import 'collage_models.dart';
import 'collage_layout_picker.dart';
import 'collage_preview_screen.dart';
import '../media_picker/media_picker_screen.dart';
import '../camera/camera_screen.dart';

class CollageEditorScreen extends StatefulWidget {
  final CollageLayoutDef layout;

  /// Pre-picked media files to auto-fill cells on load.
  final List<PickedMediaFile>? initialPicks;

  /// Existing collage draft to restore (opened from home screen).
  final CollageDraft? draft;

  const CollageEditorScreen({super.key, required this.layout, this.initialPicks, this.draft});

  @override
  State<CollageEditorScreen> createState() => _CollageEditorScreenState();
}

class _CollageEditorScreenState extends State<CollageEditorScreen> {
  static const _kBg = Color(0xFF1A1A1A);
  static const _kOrange = Color(0xFFB8860B);
  static const _kRed = Color(0xFFCC2222);
  static const _kBorderWidth = 2.0;

  late List<CollageCellData> _cells;
  late List<double> _splitPositions; // adjustable split values

  int? _selectedCell;

  // Canvas dimensions (updated each build)
  double _canvasW = 0;
  double _canvasH = 0;

  // Video controllers keyed by cell index
  final Map<int, VideoPlayerController> _vcs = {};
  final Set<int> _playingCells = {}; // per-cell play state
  final Set<int> _pauseButtonVisible = {}; // pause button visibility per cell
  final Map<int, Timer> _pauseHideTimers = {};
  Duration _elapsed = Duration.zero;
  Timer? _playTimer;

  // Recent media strip
  List<AssetEntity> _recentAssets = [];

  // Drag state for dividers
  int? _draggingDivider; // index into _dividers
  List<_Divider> _dividers = [];

  // ── Canvas background ──────────────────────────────────────────────────────
  Color _bgColor = Colors.black;
  bool _showBgPanel = false;

  // ── Border (gap between cells) ─────────────────────────────────────────────
  double _borderGap = 2.0;
  bool _showBorderPanel = false;

  // ── Per-cell volume ────────────────────────────────────────────────────────
  late List<double> _cellVolumes;
  bool _showVolumePanel = false;

  // ── Per-cell trim ──────────────────────────────────────────────────────────
  bool _showTrimPanel = false;

  // ── Per-cell repeat ────────────────────────────────────────────────────────
  late List<bool> _cellRepeating;

  // ── Per-cell edit (rotate + flip) ─────────────────────────────────────────
  late List<int> _cellRotSteps;   // 0‥3 × 90° clockwise
  late List<bool> _cellFlipH;
  late List<bool> _cellFlipV;
  bool _showEditPanel = false;

  // ── Per-cell transform (pinch-zoom + free rotate + pan) ──────────────────
  late List<double> _cellScales;
  late List<double> _cellAngles;
  late List<double> _cellOffsetX; // pan offset in cell-local pixels
  late List<double> _cellOffsetY;
  int? _scalingCellIdx;
  double _gestureBaseScale = 1.0;
  double _gestureBaseAngle = 0.0;

  // ── Swap mode ─────────────────────────────────────────────────────────────
  bool _swapMode = false;
  int? _swapSourceIdx;

  // ── Drag-and-drop swap state ───────────────────────────────────────────────
  bool _dragMode = false;
  int? _dragSourceCellIdx;
  Offset? _dragCanvasNorm; // normalized 0..1 canvas position of finger
  int? _dragTargetCellIdx;

  // ── Text overlays ──────────────────────────────────────────────────────────
  final List<_TextOverlay> _textOverlays = [];
  int? _selectedTextIdx;
  final TextEditingController _textCtrl = TextEditingController();

  // ── Sticker overlays ───────────────────────────────────────────────────────
  final List<_StickerOverlay> _stickerOverlays = [];
  int? _selectedStickerIdx;
  bool _showStickerPanel = false;

  // ── GIF overlays ───────────────────────────────────────────────────────────
  final List<_GifOverlay> _gifOverlays = [];
  int? _selectedGifIdx;

  // ── Per-cell color filter ──────────────────────────────────────────────────
  late List<int> _cellFilterIdx;   // index into _kFilters; 0 = None
  bool _showFilterPanel = false;

  // ── Per-cell speed ─────────────────────────────────────────────────────────
  late List<double> _cellSpeeds;   // 0.25 / 0.5 / 1.0 / 1.5 / 2.0 / 3.0
  bool _showSpeedPanel = false;

  // ── Aspect ratio ───────────────────────────────────────────────────────────
  _CollageAspect _aspectRatio = _CollageAspect.portrait916;
  bool _showAspectPanel = false;

  // ── Overlay gesture base values (shared) ───────────────────────────────────
  double _overlayBaseScale = 1.0;
  double _overlayBaseRotation = 0.0;

  // ── Play mode ──────────────────────────────────────────────────────────────
  _PlayMode _playMode = _PlayMode.sync;
  bool _showPlayModePanel = false;
  int _seqIdx = 0;       // sequential: index into _seqEligible
  Timer? _seqTimer;      // sequential: fires when current clip ends

  // ── Background audio state ─────────────────────────────────────────────────
  String? _audioPath;
  Duration _audioDuration = Duration.zero;
  Duration _audioTrimStart = Duration.zero;
  Duration _audioTrimEnd = Duration.zero;
  double _audioVolume = 1.0;
  AudioPlayer? _bgAudioPlayer;
  bool _bgAudioPlaying = false;
  bool _showAudioPanel = false;

  // ── Draft persistence ──────────────────────────────────────────────────────
  late String _draftId;
  late String _draftTitle;

  // ── Artistic layout helpers ────────────────────────────────────────────────

  bool get _isArtistic => widget.layout.isArtistic &&
      kArtisticCellPaths.containsKey(widget.layout.id);

  double get _aspectMultiplier {
    switch (_aspectRatio) {
      case _CollageAspect.portrait916: return 16 / 9;
      case _CollageAspect.portrait34:  return 4 / 3;
      case _CollageAspect.square:      return 1.0;
      case _CollageAspect.landscape43: return 3 / 4;
      case _CollageAspect.landscape169:return 9 / 16;
    }
  }

  int? _hitTestArtistic(double nx, double ny) {
    final builders = kArtisticCellPaths[widget.layout.id];
    if (builders == null) return null;
    if (_canvasW == 0 || _canvasH == 0) return null;
    final pixelTap = Offset(nx * _canvasW, ny * _canvasH);
    for (int i = builders.length - 1; i >= 0; i--) {
      final path = builders[i](Size(_canvasW, _canvasH));
      if (path.contains(pixelTap)) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final n = widget.layout.cellCount;
    final d = widget.draft;

    // Initialise draft identity — create a new one if not restoring.
    if (d != null) {
      _draftId = d.id;
      _draftTitle = d.title;
    } else {
      final created = CollageDraftManager.instance.create(widget.layout.id);
      _draftId = created.id;
      _draftTitle = created.title;
    }

    // ── Cell data ────────────────────────────────────────────────────────────
    _cells = List.generate(n, (i) {
      if (d == null || i >= d.cells.length) return const CollageCellData();
      final cs = d.cells[i];
      return CollageCellData(
        filePath: cs.filePath,
        isVideo: cs.isVideo,
        duration: Duration(milliseconds: cs.durationMs),
        trimStart: Duration(milliseconds: cs.trimStartMs),
        trimEnd: Duration(milliseconds: cs.trimEndMs),
        volume: cs.volume,
      );
    });
    _cellVolumes   = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].volume    : 1.0);
    _cellRepeating = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].repeating : true);
    _cellRotSteps  = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].rotSteps  : 0);
    _cellFlipH     = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].flipH     : false);
    _cellFlipV     = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].flipV     : false);
    _cellScales    = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].scale     : 1.0);
    _cellAngles    = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].angle     : 0.0);
    _cellOffsetX   = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].offsetX   : 0.0);
    _cellOffsetY   = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].offsetY   : 0.0);
    _cellFilterIdx = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].filterIdx : 0);
    _cellSpeeds    = List.generate(n, (i) => (d != null && i < d.cells.length) ? d.cells[i].speed     : 1.0);

    // ── Canvas appearance ────────────────────────────────────────────────────
    if (d != null) {
      _bgColor   = Color(d.bgColorValue);
      _borderGap = d.borderGap;
      try { _aspectRatio = _CollageAspect.values.byName(d.aspectRatio); } catch (_) {}
      try { _playMode    = _PlayMode.values.byName(d.playMode);         } catch (_) {}
      _audioPath      = d.audioPath;
      _audioTrimStart = Duration(milliseconds: d.audioTrimStartMs);
      _audioTrimEnd   = Duration(milliseconds: d.audioTrimEndMs);
      _audioVolume    = d.audioVolume;
    }

    _computeDividers();

    // Restore saved divider positions (must happen after _computeDividers).
    if (d != null && d.dividerPositions.length == _dividers.length) {
      for (int i = 0; i < _dividers.length; i++) {
        _dividers[i] = _dividers[i].copyWith(position: d.dividerPositions[i]);
      }
    }

    // Restore overlays.
    if (d != null) {
      _textOverlays.addAll(d.textOverlays.map(_TextOverlay.fromJson));
      _stickerOverlays.addAll(d.stickerOverlays.map(_StickerOverlay.fromJson));
      _gifOverlays.addAll(d.gifOverlays.map(_GifOverlay.fromJson));
    }

    // Initialise VideoPlayerControllers for restored video cells.
    if (d != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initRestoredVcs());
    }

    _loadRecentAssets();
    if (widget.initialPicks != null && widget.initialPicks!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFillCells());
    }
  }

  Future<void> _initRestoredVcs() async {
    for (int i = 0; i < _cells.length; i++) {
      final cell = _cells[i];
      if (cell.isEmpty || !cell.isVideo) continue;
      final file = File(cell.filePath!);
      if (!file.existsSync()) continue;
      try {
        final vc = VideoPlayerController.file(file);
        await vc.initialize();
        vc.setLooping(_cellRepeating[i]);
        if (mounted) {
          setState(() => _vcs[i] = vc);
        } else {
          vc.dispose();
        }
      } catch (_) {}
    }
  }

  /// Captures current editor state as a [CollageDraft] and persists it.
  Future<void> _saveDraft() async {
    final cellStates = List.generate(_cells.length, (i) {
      final c = _cells[i];
      return CollageCellState(
        filePath: c.filePath,
        isVideo: c.isVideo,
        durationMs: c.duration.inMilliseconds,
        trimStartMs: c.trimStart.inMilliseconds,
        trimEndMs: c.trimEnd.inMilliseconds,
        volume: (i < _cellVolumes.length) ? _cellVolumes[i] : 1.0,
        rotSteps: (i < _cellRotSteps.length) ? _cellRotSteps[i] : 0,
        flipH: (i < _cellFlipH.length) ? _cellFlipH[i] : false,
        flipV: (i < _cellFlipV.length) ? _cellFlipV[i] : false,
        scale: (i < _cellScales.length) ? _cellScales[i] : 1.0,
        angle: (i < _cellAngles.length) ? _cellAngles[i] : 0.0,
        offsetX: (i < _cellOffsetX.length) ? _cellOffsetX[i] : 0.0,
        offsetY: (i < _cellOffsetY.length) ? _cellOffsetY[i] : 0.0,
        filterIdx: (i < _cellFilterIdx.length) ? _cellFilterIdx[i] : 0,
        speed: (i < _cellSpeeds.length) ? _cellSpeeds[i] : 1.0,
        repeating: (i < _cellRepeating.length) ? _cellRepeating[i] : true,
      );
    });

    final draft = CollageDraft(
      id: _draftId,
      title: _draftTitle,
      createdAt: widget.draft?.createdAt ?? DateTime.now(),
      modifiedAt: DateTime.now(),
      layoutId: widget.layout.id,
      cells: cellStates,
      dividerPositions: _dividers.map((dv) => dv.position).toList(),
      bgColorValue: _bgColor.toARGB32(),
      borderGap: _borderGap,
      aspectRatio: _aspectRatio.name,
      playMode: _playMode.name,
      audioPath: _audioPath,
      audioTrimStartMs: _audioTrimStart.inMilliseconds,
      audioTrimEndMs: _audioTrimEnd.inMilliseconds,
      audioVolume: _audioVolume,
      thumbnailPath: widget.draft?.thumbnailPath,
      textOverlays: _textOverlays.map((o) => o.toJson()).toList(),
      stickerOverlays: _stickerOverlays.map((o) => o.toJson()).toList(),
      gifOverlays: _gifOverlays.map((o) => o.toJson()).toList(),
    );
    await CollageDraftManager.instance.save(draft);
  }

  Future<void> _autoFillCells() async {
    final picks = widget.initialPicks!;
    for (int i = 0; i < picks.length && i < _cells.length; i++) {
      await _assignToCell(i, picks[i]);
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _seqTimer?.cancel();
    _textCtrl.dispose();
    for (final t in _pauseHideTimers.values) { t.cancel(); }
    for (final vc in _vcs.values) { vc.dispose(); }
    _bgAudioPlayer?.dispose();
    super.dispose();
  }

  // ── Cell transform matrix (pinch-scale + free-rotate + discrete-rotate + flip) ──

  Matrix4 _cellMatrix(int index, {double cellW = 1.0, double cellH = 1.0}) {
    final angle = _cellAngles[index] +
        _cellRotSteps[index] * math.pi / 2;
    final flipX = _cellFlipH[index] ? -1.0 : 1.0;
    final flipY = _cellFlipV[index] ? -1.0 : 1.0;
    // Minimum scale to cover the cell at the current rotation angle.
    // For a rectangle (W × H) rotated by θ, the correct cover scale is:
    //   |cosθ| + max(W/H, H/W) × |sinθ|
    // For a square this reduces to |cosθ|+|sinθ|, but for non-square cells
    // the aspect ratio multiplier ensures corners are never clipped.
    final abscos = math.cos(angle).abs();
    final abssin = math.sin(angle).abs();
    final ar = (cellH > 0 && cellW > 0) ? cellW / cellH : 1.0;
    final maxAspect = ar > 1.0 ? ar : 1.0 / ar;
    final coverScale = abscos + maxAspect * abssin; // always >= 1, equals 1 at 0°/90°/180°/270°
    // Order: translate (pan in screen space) → scale → rotate → flip
    return Matrix4.identity()
      ..translate(_cellOffsetX[index], _cellOffsetY[index])
      ..scale(_cellScales[index] * coverScale)
      ..rotateZ(angle)
      ..scale(flipX, flipY);
  }

  // Move divider di to newPos AND sync all linked dividers (same axis, same position).
  // Prevents any divider group from crossing another — keeps a minimum gap between groups.
  static const _kMinDivGap = 0.10;

  void _moveDivider(int di, double newPos) {
    final div = _dividers[di];
    // Use ORIGINAL layout position to identify linked dividers (not current dragged
    // position) so dividers never permanently merge when dragged near each other.
    final origLayoutPos = div.isVertical
        ? widget.layout.cells[div.cellA].right
        : widget.layout.cells[div.cellA].bottom;

    // Clamp newPos so this divider group stays at least _kMinDivGap away from
    // any neighbouring divider group on either side.
    double lo = 0.10, hi = 0.90;
    for (int d = 0; d < _dividers.length; d++) {
      final other = _dividers[d];
      if (other.isVertical != div.isVertical) continue;
      final otherOrigPos = other.isVertical
          ? widget.layout.cells[other.cellA].right
          : widget.layout.cells[other.cellA].bottom;
      if ((otherOrigPos - origLayoutPos).abs() < 0.02) continue; // same group
      if (otherOrigPos < origLayoutPos) {
        lo = math.max(lo, other.position + _kMinDivGap);
      } else {
        hi = math.min(hi, other.position - _kMinDivGap);
      }
    }
    newPos = newPos.clamp(lo, hi);

    setState(() {
      for (int d = 0; d < _dividers.length; d++) {
        final other = _dividers[d];
        final otherOrigPos = other.isVertical
            ? widget.layout.cells[other.cellA].right
            : widget.layout.cells[other.cellA].bottom;
        if (other.isVertical == div.isVertical &&
            (otherOrigPos - origLayoutPos).abs() < 0.02) {
          _dividers[d] = other.copyWith(position: newPos);
        }
      }
    });
  }

  // ── Divider computation ───────────────────────────────────────────────────

  void _computeDividers() {
    _dividers = [];
    if (_isArtistic) return; // No dividers for artistic layouts
    final cells = widget.layout.cells;
    for (int i = 0; i < cells.length; i++) {
      for (int j = i + 1; j < cells.length; j++) {
        final a = cells[i], b = cells[j];
        // Vertical divider: a.right == b.left with vertical overlap
        if ((a.right - b.left).abs() < 0.01) {
          final overlapTop = [a.top, b.top].reduce((x, y) => x > y ? x : y);
          final overlapBot = [a.bottom, b.bottom].reduce((x, y) => x < y ? x : y);
          if (overlapBot > overlapTop + 0.01) {
            _dividers.add(_Divider(
              isVertical: true,
              position: a.right,
              spanStart: overlapTop,
              spanEnd: overlapBot,
              cellA: i,
              cellB: j,
            ));
          }
        }
        // Horizontal divider: a.bottom == b.top with horizontal overlap
        if ((a.bottom - b.top).abs() < 0.01) {
          final overlapL = [a.left, b.left].reduce((x, y) => x > y ? x : y);
          final overlapR = [a.right, b.right].reduce((x, y) => x < y ? x : y);
          if (overlapR > overlapL + 0.01) {
            _dividers.add(_Divider(
              isVertical: false,
              position: a.bottom,
              spanStart: overlapL,
              spanEnd: overlapR,
              cellA: i,
              cellB: j,
            ));
          }
        }
      }
    }
  }

  // Current cell rects (adjusted by divider positions).
  List<Rect> get _currentCells {
    if (_dividers.isEmpty) return widget.layout.cells;
    final cells = List<Rect>.from(widget.layout.cells);
    for (final div in _dividers) {
      final orig = widget.layout.cells;
      if (div.isVertical) {
        final origPos = orig[div.cellA].right;
        final delta = div.position - origPos;
        if (delta.abs() > 0.001) {
          cells[div.cellA] = Rect.fromLTRB(
              cells[div.cellA].left, cells[div.cellA].top,
              div.position, cells[div.cellA].bottom);
          cells[div.cellB] = Rect.fromLTRB(
              div.position, cells[div.cellB].top,
              cells[div.cellB].right, cells[div.cellB].bottom);
        }
      } else {
        final origPos = orig[div.cellA].bottom;
        final delta = div.position - origPos;
        if (delta.abs() > 0.001) {
          cells[div.cellA] = Rect.fromLTRB(
              cells[div.cellA].left, cells[div.cellA].top,
              cells[div.cellA].right, div.position);
          cells[div.cellB] = Rect.fromLTRB(
              cells[div.cellB].left, div.position,
              cells[div.cellB].right, cells[div.cellB].bottom);
        }
      }
    }
    return cells;
  }

  // ── Media ─────────────────────────────────────────────────────────────────

  Future<void> _loadRecentAssets() async {
    AppOpenAdManager.instance.suppressNextResume();
    final status = await PhotoManager.requestPermissionExtend();
    if (!status.isAuth && status != PermissionState.limited) return;
    final filterOption = FilterOptionGroup(
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, onlyAll: true, filterOption: filterOption);
    if (albums.isEmpty) return;
    final assets = await albums.first.getAssetListRange(start: 0, end: 20);
    if (mounted) setState(() => _recentAssets = assets);
  }

  Future<void> _pickMediaForCell(int cellIndex) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SourcePickerSheet(),
    );
    if (source == null || !mounted) return;

    if (source == 'video' || source == 'photo') {
      final picks = await Navigator.push<List<PickedMediaFile>>(
        context,
        MaterialPageRoute(
          builder: (_) => MediaPickerScreen(
              initialTab: source == 'video' ? 0 : 1),
          fullscreenDialog: true,
        ),
      );
      if (picks == null || picks.isEmpty || !mounted) return;
      final pick = picks.first;
      await _assignToCell(cellIndex, pick);
    } else if (source == 'gif') {
      AppOpenAdManager.instance.suppressNextResume();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif'],
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final path = result.files.first.path;
      if (path == null || !mounted) return;
      final pick = PickedMediaFile(
        path: path,
        isVideo: false,
        duration: Duration.zero,
      );
      await _assignToCell(cellIndex, pick);
    } else if (source == 'camera') {
      PickedMediaFile? captured;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CameraScreen(
            onCapture: (file) => captured = file,
          ),
          fullscreenDialog: true,
        ),
      );
      if (captured == null || !mounted) return;
      await _assignToCell(cellIndex, captured!);
    }
  }

  Future<void> _pickGif() async {
    AppOpenAdManager.instance.suppressNextResume();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null || !mounted) return;
    final o = _GifOverlay(filePath: path);
    setState(() {
      _gifOverlays.add(o);
      _selectedGifIdx = _gifOverlays.length - 1;
      _selectedTextIdx = null;
      _selectedStickerIdx = null;
      _selectedCell = null;
    });
    _saveDraft();
  }

  void _previewGif(String filePath) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Animated GIF
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(filePath),
                gaplessPlayback: true,
                fit: BoxFit.contain,
              ),
            ),
            // Close button
            Positioned(
              top: -16,
              right: -16,
              child: GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFCC2222),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignToCell(int cellIndex, PickedMediaFile pick) async {
    _saveSnapshot();
    Duration duration = pick.duration;

    if (pick.isVideo && duration == Duration.zero) {
      try {
        final tmp = VideoPlayerController.file(File(pick.path),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
        await tmp.initialize();
        duration = tmp.value.duration;
        await tmp.dispose();
      } catch (_) {}
    }

    _vcs[cellIndex]?.dispose();
    _vcs.remove(cellIndex);

    if (pick.isVideo) {
      final vc = VideoPlayerController.file(File(pick.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await vc.initialize();
      vc.setLooping(true);
      _vcs[cellIndex] = vc;
    }

    setState(() {
      _cells[cellIndex] = CollageCellData(
        filePath: pick.path,
        isVideo: pick.isVideo,
        duration: duration,
      );
      // Reset transform when new media is assigned so it fits the cell cleanly
      _cellScales[cellIndex] = 1.0;
      _cellAngles[cellIndex] = 0.0;
      _cellOffsetX[cellIndex] = 0.0;
      _cellOffsetY[cellIndex] = 0.0;
      _selectedCell = null;
    });
    _saveDraft();
  }

  void _clearCell(int idx) {
    _saveSnapshot();
    _vcs[idx]?.pause();
    _vcs[idx]?.dispose();
    _vcs.remove(idx);
    setState(() {
      _cells[idx] = const CollageCellData();
      _playingCells.remove(idx);
      _pauseButtonVisible.remove(idx);
      _cellScales[idx] = 1.0;
      _cellAngles[idx] = 0.0;
      _cellOffsetX[idx] = 0.0;
      _cellOffsetY[idx] = 0.0;
      _cellRotSteps[idx] = 0;
      _cellFlipH[idx] = false;
      _cellFlipV[idx] = false;
      _cellFilterIdx[idx] = 0;
      _cellSpeeds[idx] = 1.0;
      _cellRepeating[idx] = true;
      _selectedCell = null;
    });
    _saveDraft();
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  bool get _anyPlaying => _playingCells.isNotEmpty;

  void _showPauseButton(int index) {
    _pauseHideTimers[index]?.cancel();
    setState(() => _pauseButtonVisible.add(index));
    _pauseHideTimers[index] = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _pauseButtonVisible.remove(index));
    });
  }

  void _toggleCellPlay(int index) {
    // Parallel mode: any cell tap = global play/pause for all cells
    if (_playMode == _PlayMode.sync) {
      _togglePlay();
      return;
    }
    final vc = _vcs[index];
    if (vc == null) return;
    if (_playingCells.contains(index)) {
      vc.pause();
      _pauseHideTimers[index]?.cancel();
      setState(() {
        _playingCells.remove(index);
        _pauseButtonVisible.remove(index);
      });
      if (_playingCells.isEmpty) _playTimer?.cancel();
    } else {
      vc.play();
      setState(() => _playingCells.add(index));
      _startTimerIfNeeded();
      _showPauseButton(index);
    }
  }

  void _startTimerIfNeeded() {
    if (_playTimer != null && _playTimer!.isActive) return;
    _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 100));
    });
  }

  void _togglePlay() {
    if (_playMode == _PlayMode.manual) return;
    if (_anyPlaying) {
      _pauseAll();
    } else {
      _playAll();
    }
  }

  // Non-empty cell indices in order — used by sequential mode
  List<int> get _seqEligible {
    final result = <int>[];
    for (int i = 0; i < _cells.length; i++) {
      if (!_cells[i].isEmpty) result.add(i);
    }
    return result;
  }

  Duration _effectiveDuration(int cellIdx) {
    final cell = _cells[cellIdx];
    Duration raw;
    if (cell.trimEnd > Duration.zero) {
      raw = cell.trimEnd - cell.trimStart;
    } else if (cell.duration > Duration.zero) {
      raw = cell.duration;
    } else {
      raw = const Duration(seconds: 3); // fallback for images
    }
    final speed = _cellSpeeds[cellIdx];
    if (speed == 1.0) return raw;
    return Duration(microseconds: (raw.inMicroseconds / speed).round());
  }

  Future<void> _playAll() async {
    switch (_playMode) {
      case _PlayMode.sync:
        // First seek ALL controllers to their start position, then play
        // them all simultaneously. Without await, seekTo races with play()
        // and only the first controller reliably starts from the right spot.
        await Future.wait(_vcs.entries.map((entry) async {
          final cellIdx = entry.key;
          final vc = entry.value;
          await vc.setLooping(true);
          await vc.seekTo(_cells[cellIdx].trimStart);
        }));
        for (final entry in _vcs.entries) {
          entry.value.play();
          _playingCells.add(entry.key);
        }
        _startTimerIfNeeded();
        if (mounted) setState(() {});
      case _PlayMode.sequential:
        _playSeqCurrent();
      case _PlayMode.manual:
        break;
    }
  }

  void _playSeqCurrent() {
    final eligible = _seqEligible;
    if (eligible.isEmpty) return;
    if (_seqIdx >= eligible.length) _seqIdx = 0;

    final cellIdx = eligible[_seqIdx];
    final vc = _vcs[cellIdx];
    final cell = _cells[cellIdx];

    if (vc != null) {
      vc.seekTo(cell.trimStart);
      vc.play();
    }
    _startTimerIfNeeded();
    setState(() => _playingCells.add(cellIdx));

    _seqTimer?.cancel();
    _seqTimer = Timer(_effectiveDuration(cellIdx), () {
      if (!mounted) return;
      vc?.pause();
      setState(() => _playingCells.remove(cellIdx));
      _seqIdx = (_seqIdx + 1) % eligible.length;
      _playSeqCurrent();
    });
  }

  void _pauseAll() {
    _seqTimer?.cancel();
    for (final vc in _vcs.values) {
      vc.pause();
    }
    _playTimer?.cancel();
    for (final t in _pauseHideTimers.values) { t.cancel(); }
    _pauseHideTimers.clear();
    setState(() {
      _playingCells.clear();
      _pauseButtonVisible.clear();
    });
  }

  void _setPlayMode(_PlayMode mode) {
    _saveSnapshot();
    if (_anyPlaying) _pauseAll();
    setState(() {
      _playMode = mode;
      _seqIdx = 0;
    });
    _saveDraft();
  }

  // ── Undo / redo ───────────────────────────────────────────────────────────

  static const int _kMaxHistory = 30;
  final List<_CollageSnapshot> _undoStack = [];
  final List<_CollageSnapshot> _redoStack = [];

  _CollageSnapshot _captureSnapshot() => _CollageSnapshot(
        cells: List.from(_cells),
        dividers: List.from(_dividers),
        bgColor: _bgColor,
        borderGap: _borderGap,
        cellVolumes: List.from(_cellVolumes),
        cellRepeating: List.from(_cellRepeating),
        cellRotSteps: List.from(_cellRotSteps),
        cellFlipH: List.from(_cellFlipH),
        cellFlipV: List.from(_cellFlipV),
        cellScales: List.from(_cellScales),
        cellAngles: List.from(_cellAngles),
        cellOffsetX: List.from(_cellOffsetX),
        cellOffsetY: List.from(_cellOffsetY),
        textOverlays: _textOverlays
            .map((o) => _TextOverlay(
                  text: o.text,
                  x: o.x,
                  y: o.y,
                  fontSize: o.fontSize,
                  color: o.color,
                  bgColor: o.bgColor,
                  bold: o.bold,
                  italic: o.italic,
                  shadow: o.shadow,
                  scale: o.scale,
                  rotation: o.rotation,
                ))
            .toList(),
        stickerOverlays: _stickerOverlays
            .map((o) => _StickerOverlay(
                  emoji: o.emoji,
                  x: o.x,
                  y: o.y,
                  scale: o.scale,
                  rotation: o.rotation,
                ))
            .toList(),
        gifOverlays: _gifOverlays
            .map((o) => _GifOverlay(
                  filePath: o.filePath,
                  x: o.x,
                  y: o.y,
                  scale: o.scale,
                  rotation: o.rotation,
                ))
            .toList(),
        cellFilterIdx: List.from(_cellFilterIdx),
        cellSpeeds: List.from(_cellSpeeds),
        aspectRatio: _aspectRatio,
        playMode: _playMode,
        audioPath: _audioPath,
        audioDuration: _audioDuration,
        audioTrimStart: _audioTrimStart,
        audioTrimEnd: _audioTrimEnd,
        audioVolume: _audioVolume,
      );

  void _saveSnapshot() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _kMaxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  Future<void> _applySnapshot(_CollageSnapshot snap) async {
    final prevCells = List<CollageCellData>.from(_cells);
    setState(() {
      _cells = List.from(snap.cells);
      _dividers = List.from(snap.dividers);
      _bgColor = snap.bgColor;
      _borderGap = snap.borderGap;
      _cellVolumes
        ..clear()
        ..addAll(snap.cellVolumes);
      _cellRepeating
        ..clear()
        ..addAll(snap.cellRepeating);
      _cellRotSteps
        ..clear()
        ..addAll(snap.cellRotSteps);
      _cellFlipH
        ..clear()
        ..addAll(snap.cellFlipH);
      _cellFlipV
        ..clear()
        ..addAll(snap.cellFlipV);
      _cellScales
        ..clear()
        ..addAll(snap.cellScales);
      _cellAngles
        ..clear()
        ..addAll(snap.cellAngles);
      _cellOffsetX
        ..clear()
        ..addAll(snap.cellOffsetX);
      _cellOffsetY
        ..clear()
        ..addAll(snap.cellOffsetY);
      _textOverlays
        ..clear()
        ..addAll(snap.textOverlays);
      _stickerOverlays
        ..clear()
        ..addAll(snap.stickerOverlays);
      _gifOverlays
        ..clear()
        ..addAll(snap.gifOverlays);
      _cellFilterIdx
        ..clear()
        ..addAll(snap.cellFilterIdx);
      _cellSpeeds
        ..clear()
        ..addAll(snap.cellSpeeds);
      _aspectRatio = snap.aspectRatio;
      _playMode = snap.playMode;
      _audioPath = snap.audioPath;
      _audioDuration = snap.audioDuration;
      _audioTrimStart = snap.audioTrimStart;
      _audioTrimEnd = snap.audioTrimEnd;
      _audioVolume = snap.audioVolume;
      _playingCells.clear();
      _selectedCell = null;
      _selectedTextIdx = null;
      _selectedStickerIdx = null;
      _selectedGifIdx = null;
      _swapMode = false;
      _swapSourceIdx = null;
      _dragMode = false;
      _dragSourceCellIdx = null;
    });
    await _syncControllersToSnapshot(prevCells);
  }

  Future<void> _syncControllersToSnapshot(
      List<CollageCellData> prevCells) async {
    for (int i = 0; i < _cells.length; i++) {
      final prevPath =
          i < prevCells.length ? prevCells[i].filePath : null;
      final newCell = _cells[i];
      if (prevPath == newCell.filePath) continue;

      _vcs[i]?.pause();
      _vcs[i]?.dispose();
      _vcs.remove(i);

      if (newCell.filePath != null && newCell.isVideo) {
        final vc = VideoPlayerController.file(File(newCell.filePath!),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
        await vc.initialize();
        vc.setLooping(true);
        if (mounted) setState(() => _vcs[i] = vc);
      }
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_captureSnapshot());
    _applySnapshot(_undoStack.removeLast());
    _saveDraft();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_captureSnapshot());
    _applySnapshot(_redoStack.removeLast());
    _saveDraft();
  }

  String get _elapsedStr {
    final s = _elapsed.inSeconds;
    final ms = (_elapsed.inMilliseconds % 1000) ~/ 100;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.$ms';
  }

  // ── Swap ──────────────────────────────────────────────────────────────────

  void _enterSwapMode(int sourceIdx) {
    setState(() {
      _swapMode = true;
      _swapSourceIdx = sourceIdx;
      _selectedCell = null;
    });
  }

  void _cancelSwapMode() {
    setState(() {
      _swapMode = false;
      _swapSourceIdx = null;
    });
  }

  void _doSwap(int src, int target) {
    if (src == target) {
      _cancelSwapMode();
      return;
    }
    _saveSnapshot();

    final tmpCell = _cells[src];
    _cells[src] = _cells[target];
    _cells[target] = tmpCell;

    final tmpScale = _cellScales[src];
    _cellScales[src] = _cellScales[target];
    _cellScales[target] = tmpScale;

    final tmpAngle = _cellAngles[src];
    _cellAngles[src] = _cellAngles[target];
    _cellAngles[target] = tmpAngle;

    final tmpOffX = _cellOffsetX[src];
    _cellOffsetX[src] = _cellOffsetX[target];
    _cellOffsetX[target] = tmpOffX;

    final tmpOffY = _cellOffsetY[src];
    _cellOffsetY[src] = _cellOffsetY[target];
    _cellOffsetY[target] = tmpOffY;

    final tmpVc = _vcs[src];
    if (_vcs.containsKey(target)) {
      _vcs[src] = _vcs[target]!;
    } else {
      _vcs.remove(src);
    }
    if (tmpVc != null) {
      _vcs[target] = tmpVc;
    } else {
      _vcs.remove(target);
    }

    setState(() {
      _swapMode = false;
      _swapSourceIdx = null;
      _selectedCell = target;
    });
    _saveDraft();
  }

  void _cancelDragMode() {
    setState(() {
      _dragMode = false;
      _dragSourceCellIdx = null;
      _dragCanvasNorm = null;
      _dragTargetCellIdx = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final canvasH = (screenW * _aspectMultiplier)
        .clamp(0.0, MediaQuery.of(context).size.height * 0.55);

    _canvasW = screenW;
    _canvasH = canvasH;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const BannerAdWidget(),
            _buildMediaStrip(),
            SizedBox(
              width: screenW,
              height: canvasH,
              child: _buildCanvas(screenW, canvasH),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: _buildBottomPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final canUndo = _undoStack.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _selectedCell != null
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                  onPressed: () => setState(() { _selectedCell = null; }),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
                  onPressed: () async {
                    await _saveDraft();
                    if (mounted) Navigator.pop(context);
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
          IconButton(
            icon: Icon(Icons.undo,
                color: canUndo ? Colors.white70 : Colors.white24, size: 22),
            onPressed: canUndo ? _undo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
          ),
          IconButton(
            icon: Icon(Icons.redo,
                color: canRedo ? Colors.white70 : Colors.white24, size: 22),
            onPressed: canRedo ? _redo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final ctrl = TextEditingController(text: _draftTitle);
                final result = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF2A2A2A),
                    title: const Text('Rename',
                        style: TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF7B35C8)),
                        ),
                      ),
                      onSubmitted: (v) {
                        final t = v.trim();
                        if (t.isNotEmpty) Navigator.pop(ctx, t);
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white54)),
                      ),
                      TextButton(
                        onPressed: () {
                          final t = ctrl.text.trim();
                          if (t.isNotEmpty) Navigator.pop(ctx, t);
                        },
                        child: const Text('Rename',
                            style: TextStyle(color: Color(0xFF7B35C8))),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (result != null && result != _draftTitle) {
                  setState(() => _draftTitle = result);
                  _saveDraft();
                }
              },
              child: Text(
                _draftTitle,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white70, size: 24),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Color(0xFFB8860B), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(_elapsedStr,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  letterSpacing: 1)),
          IconButton(
            icon: Icon(
              _playMode == _PlayMode.manual
                  ? Icons.touch_app_outlined
                  : _anyPlaying ? Icons.pause : Icons.play_arrow,
              color: _playMode == _PlayMode.manual
                  ? Colors.white30
                  : Colors.white70,
              size: 22,
            ),
            onPressed: _playMode == _PlayMode.manual ? null : _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          GestureDetector(
            onTap: _confirm,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7B35C8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    _pauseAll();
    await _stopBgAudio();
    await _saveDraft();

    // Compute export dimensions based on chosen aspect ratio.
    // Both dimensions must be even for libx264 / libswscale.
    const int baseW = 720; // already even
    final double mul = _aspectMultiplier;
    final int outHRaw = (baseW * mul).round();
    final int outH = outHRaw % 2 == 0 ? outHRaw : outHRaw - 1;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollagePreviewScreen(
          cells: _cells,
          cellRects: _currentCells,
          videoControllers: _vcs,
          cellRepeating: List.from(_cellRepeating),
          bgColor: _bgColor,
          borderGap: _borderGap,
          audioPath: _audioPath,
          audioTrimStart: _audioTrimStart,
          audioTrimEnd: _audioTrimEnd,
          audioVolume: _audioVolume,
          outW: baseW,
          outH: outH,
          cellSpeeds: List.from(_cellSpeeds),
          cellVolumes: List.from(_cellVolumes),
          cellFilterVf: List.generate(
            _cells.length,
            (i) {
              final fi = _cellFilterIdx[i];
              return (fi > 0 && fi < _kFilters.length)
                  ? _kFilters[fi].ffmpegVf
                  : null;
            },
          ),
          cellColorFilters: List.generate(
            _cells.length,
            (i) => _cellColorFilter(i),
          ),
          draftId: _draftId,
        ),
      ),
    );
  }

  // ── Media strip ───────────────────────────────────────────────────────────

  Widget _buildMediaStrip() {
    return Container(
      height: 64,
      color: const Color(0xFF111111),
      child: _recentAssets.isEmpty
          ? const SizedBox()
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: _recentAssets.length,
              itemBuilder: (_, i) => _StripThumb(
                asset: _recentAssets[i],
                onTap: () async {
                  if (_selectedCell == null) return;
                  final file = await _recentAssets[i].originFile;
                  if (file == null || !mounted) return;
                  await _assignToCell(
                    _selectedCell!,
                    PickedMediaFile(
                      path: file.path,
                      isVideo:
                          _recentAssets[i].type == AssetType.video,
                      duration: _recentAssets[i].videoDuration,
                    ),
                  );
                },
              ),
            ),
    );
  }

  // ── Canvas ────────────────────────────────────────────────────────────────

  Widget _buildCanvas(double canvasW, double canvasH) {
    final cells = _currentCells;

    // Outer Stack: canvas GD (handles cells) + overlays as siblings
    // so tapping an overlay doesn't bubble to the canvas GD.
    return Stack(
      children: [
        // ── Inner canvas: cell interaction ──────────────────────────
        GestureDetector(
          onTapUp: (d) {
            final nx = d.localPosition.dx / canvasW;
            final ny = d.localPosition.dy / canvasH;

            int? idx;
            if (_isArtistic) {
              idx = _hitTestArtistic(nx, ny);
            } else {
              for (int i = 0; i < cells.length; i++) {
                if (cells[i].contains(Offset(nx, ny))) {
                  idx = i;
                  break;
                }
              }
            }

            if (idx != null) {
              if (_swapMode) {
                _doSwap(_swapSourceIdx!, idx);
              } else {
                setState(() {
                  if (_selectedCell != idx) { _showVolumePanel = false; _showTrimPanel = false; _showEditPanel = false; _showFilterPanel = false; _showSpeedPanel = false; }
                  _selectedCell = idx;
                  _selectedTextIdx = null;
                  _selectedStickerIdx = null;
                  _selectedGifIdx = null;
                });
                if (_cells[idx].isEmpty) _pickMediaForCell(idx);
              }
              return;
            }

            if (_swapMode) {
              _cancelSwapMode();
            } else {
              setState(() {
                _selectedCell = null;
                _selectedTextIdx = null;
                _selectedStickerIdx = null;
                _selectedGifIdx = null;
                _showVolumePanel = false;
                _showTrimPanel = false;
                _showEditPanel = false;
                _showFilterPanel = false;
                _showSpeedPanel = false;
              });
            }
          },
          child: Stack(
            children: [
              Container(color: _bgColor),
              if (_isArtistic)
                ..._buildArtisticCells(canvasW, canvasH)
              else
                ...List.generate(cells.length,
                    (i) => _buildCellWidget(cells[i], i, canvasW, canvasH, cells)),
              if (!_isArtistic)
                ..._buildDraggableDividers(cells, canvasW, canvasH),
              if (_swapMode)
                Positioned.fill(
                  child: IgnorePointer(child: Container(color: Colors.black45)),
                ),
              if (_swapMode)
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swap_horiz, color: Colors.white, size: 36),
                      const SizedBox(height: 10),
                      const Text(
                        'Tap a cell to swap',
                        style: TextStyle(
                            color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _cancelSwapMode,
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              if (_dragMode && _dragSourceCellIdx != null && _dragCanvasNorm != null)
                Positioned(
                  left: _dragCanvasNorm!.dx * canvasW - 44,
                  top: _dragCanvasNorm!.dy * canvasH - 44,
                  width: 88,
                  height: 88,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.85,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.amber, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: _buildCellContent(
                              _dragSourceCellIdx!, _cells[_dragSourceCellIdx!]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ── Text overlays (siblings of canvas GD) ───────────────────
        ..._buildTextOverlayWidgets(canvasW, canvasH),
        // ── Sticker overlays ────────────────────────────────────────
        ..._buildStickerOverlayWidgets(canvasW, canvasH),
        // ── GIF overlays ─────────────────────────────────────────────
        ..._buildGifOverlayWidgets(canvasW, canvasH),
      ],
    );
  }

  // ── Overlay widget builders ───────────────────────────────────────────────

  List<Widget> _buildTextOverlayWidgets(double cw, double ch) {
    return List.generate(_textOverlays.length, (i) {
      final o = _textOverlays[i];
      final isSelected = _selectedTextIdx == i;
      return Positioned(
        left: o.x * cw,
        top: o.y * ch,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedTextIdx = i;
              _selectedStickerIdx = null;
              _selectedCell = null;
              _showVolumePanel = false;
              _showTrimPanel = false;
              _showEditPanel = false;
              // sync controller
              if (_textCtrl.text != o.text) {
                _textCtrl.text = o.text;
                _textCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: o.text.length));
              }
            }),
            onScaleStart: (_) {
              _saveSnapshot();
              _overlayBaseScale = o.scale;
              _overlayBaseRotation = o.rotation;
            },
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount == 1) {
                o.x = (o.x + d.focalPointDelta.dx / cw).clamp(0.02, 0.98);
                o.y = (o.y + d.focalPointDelta.dy / ch).clamp(0.02, 0.98);
              } else {
                o.scale = (_overlayBaseScale * d.scale).clamp(0.3, 5.0);
                o.rotation = _overlayBaseRotation + d.rotation;
              }
            }),
            onScaleEnd: (_) => _saveDraft(),
            child: Transform.rotate(
              angle: o.rotation,
              child: Transform.scale(
                scale: o.scale,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: o.bgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: isSelected
                        ? Border.all(
                            color: Colors.amber,
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignOutside)
                        : null,
                  ),
                  child: Text(
                    o.text.isEmpty ? 'Tap to edit' : o.text,
                    style: TextStyle(
                      fontSize: o.fontSize,
                      color: o.text.isEmpty ? Colors.white38 : o.color,
                      fontWeight: o.bold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: o.italic ? FontStyle.italic : FontStyle.normal,
                      shadows: o.shadow
                          ? [const Shadow(
                              color: Colors.black54,
                              offset: Offset(1, 1),
                              blurRadius: 3)]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildStickerOverlayWidgets(double cw, double ch) {
    return List.generate(_stickerOverlays.length, (i) {
      final o = _stickerOverlays[i];
      final isSelected = _selectedStickerIdx == i;
      return Positioned(
        left: o.x * cw,
        top: o.y * ch,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedStickerIdx = i;
              _selectedTextIdx = null;
              _selectedCell = null;
              _showVolumePanel = false;
              _showTrimPanel = false;
              _showEditPanel = false;
            }),
            onScaleStart: (_) {
              _saveSnapshot();
              _overlayBaseScale = o.scale;
              _overlayBaseRotation = o.rotation;
            },
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount == 1) {
                o.x = (o.x + d.focalPointDelta.dx / cw).clamp(0.02, 0.98);
                o.y = (o.y + d.focalPointDelta.dy / ch).clamp(0.02, 0.98);
              } else {
                o.scale = (_overlayBaseScale * d.scale).clamp(0.2, 4.0);
                o.rotation = _overlayBaseRotation + d.rotation;
              }
            }),
            onScaleEnd: (_) => _saveDraft(),
            child: Transform.rotate(
              angle: o.rotation,
              child: Transform.scale(
                scale: o.scale,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(
                            color: Colors.amber,
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignOutside),
                          borderRadius: BorderRadius.circular(8))
                      : null,
                  child: Text(o.emoji,
                      style: const TextStyle(fontSize: 48)),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildGifOverlayWidgets(double cw, double ch) {
    return List.generate(_gifOverlays.length, (i) {
      final o = _gifOverlays[i];
      final isSelected = _selectedGifIdx == i;
      return Positioned(
        left: o.x * cw,
        top: o.y * ch,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedGifIdx = i;
              _selectedTextIdx = null;
              _selectedStickerIdx = null;
              _selectedCell = null;
              _showVolumePanel = false;
              _showTrimPanel = false;
              _showEditPanel = false;
            }),
            onScaleStart: (_) {
              _saveSnapshot();
              _overlayBaseScale = o.scale;
              _overlayBaseRotation = o.rotation;
            },
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount == 1) {
                o.x = (o.x + d.focalPointDelta.dx / cw).clamp(0.02, 0.98);
                o.y = (o.y + d.focalPointDelta.dy / ch).clamp(0.02, 0.98);
              } else {
                o.scale = (_overlayBaseScale * d.scale).clamp(0.1, 5.0);
                o.rotation = _overlayBaseRotation + d.rotation;
              }
            }),
            onScaleEnd: (_) => _saveDraft(),
            child: Transform.rotate(
              angle: o.rotation,
              child: Transform.scale(
                scale: o.scale,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: isSelected
                          ? BoxDecoration(
                              border: Border.all(
                                color: Colors.amber,
                                width: 1.5,
                                strokeAlign: BorderSide.strokeAlignOutside),
                              borderRadius: BorderRadius.circular(4))
                          : null,
                      child: Image.file(
                        File(o.filePath),
                        width: 120,
                        gaplessPlayback: true,
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: -14,
                        right: -14,
                        child: GestureDetector(
                          onTap: () => _previewGif(o.filePath),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFF7B35C8),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Icon(
                              Icons.play_circle_outline,
                              color: Colors.white,
                              size: 18,
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
    });
  }

  // ── Artistic cell rendering ───────────────────────────────────────────────

  List<Widget> _buildArtisticCells(double canvasW, double canvasH) {
    final builders = kArtisticCellPaths[widget.layout.id];
    if (builders == null) return [];
    final size = Size(canvasW, canvasH);
    final widgets = <Widget>[];

    for (int index = 0; index < builders.length; index++) {
      final path = builders[index](size);
      final isSelected = _selectedCell == index;
      final isSwapSource = _swapMode && _swapSourceIdx == index;
      final isDragSource = _dragMode && _dragSourceCellIdx == index;
      final isDragTarget = _dragMode && _dragTargetCellIdx == index;
      final cell = _cells[index];

      widgets.add(
        Positioned(
          left: 0,
          top: 0,
          width: canvasW,
          height: canvasH,
          child: GestureDetector(
            onTap: () {
              if (_swapMode) {
                _doSwap(_swapSourceIdx!, index);
                return;
              }
              setState(() {
                if (_selectedCell == index) {
                  _selectedCell = null;
                } else {
                  _showVolumePanel = false;
                  _selectedCell = index;
                }
              });
              if (_selectedCell == index && cell.isEmpty) _pickMediaForCell(index);
            },
            onLongPressStart: (_swapMode || _dragMode || cell.isEmpty)
                ? null
                : (details) {
                    setState(() {
                      _dragMode = true;
                      _dragSourceCellIdx = index;
                      _dragCanvasNorm = Offset(
                        details.localPosition.dx / canvasW,
                        details.localPosition.dy / canvasH,
                      );
                      _dragTargetCellIdx = null;
                    });
                  },
            onLongPressMoveUpdate: (details) {
              if (!_dragMode || _dragSourceCellIdx != index) return;
              final nx = details.localPosition.dx / canvasW;
              final ny = details.localPosition.dy / canvasH;
              final targetIdx = _hitTestArtistic(nx, ny);
              setState(() {
                _dragCanvasNorm = Offset(nx, ny);
                _dragTargetCellIdx = targetIdx != index ? targetIdx : null;
              });
            },
            onLongPressEnd: (details) {
              if (!_dragMode || _dragSourceCellIdx != index) return;
              final src = _dragSourceCellIdx!;
              final tgt = _dragTargetCellIdx;
              _cancelDragMode();
              if (tgt != null) _doSwap(src, tgt);
            },
            onLongPressCancel: () {
              if (_dragMode && _dragSourceCellIdx == index) _cancelDragMode();
            },
            onScaleStart: (_swapMode || _dragMode || cell.isEmpty)
                ? null
                : (details) {
                    _saveSnapshot();
                    _scalingCellIdx = index;
                    _gestureBaseScale = _cellScales[index];
                    _gestureBaseAngle = _cellAngles[index];
                  },
            onScaleUpdate: (_swapMode || _dragMode || cell.isEmpty)
                ? null
                : (details) {
                    if (_scalingCellIdx != index) return;
                    setState(() {
                      if (details.pointerCount == 1) {
                        // Single finger → pan only
                        _cellOffsetX[index] += details.focalPointDelta.dx;
                        _cellOffsetY[index] += details.focalPointDelta.dy;
                      } else {
                        // Two fingers → zoom + rotate only (no pan accumulation)
                        _cellScales[index] =
                            (_gestureBaseScale * details.scale).clamp(0.5, 5.0);
                        _cellAngles[index] =
                            _gestureBaseAngle + details.rotation;
                      }
                    });
                  },
            onScaleEnd:
                (_swapMode || _dragMode || cell.isEmpty) ? null : (_) { _scalingCellIdx = null; _saveDraft(); },
            child: ClipPath(
              clipper: _PathClipper(path),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Cell content
                  LayoutBuilder(
                    builder: (context, constraints) => Transform(
                      alignment: Alignment.center,
                      transform: _cellMatrix(index,
                          cellW: constraints.maxWidth,
                          cellH: constraints.maxHeight),
                      child: _buildCellContent(index, cell),
                    ),
                  ),
                  // Selection stroke overlay
                  if (isSelected || isSwapSource || isDragSource || isDragTarget)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _PathStrokePainter(
                            path: path,
                            color: isDragSource
                                ? Colors.amber
                                : isDragTarget
                                    ? Colors.greenAccent
                                    : isSwapSource
                                        ? Colors.amber
                                        : _kRed,
                            strokeWidth: _kBorderWidth + (isDragSource || isDragTarget || isSwapSource ? 1 : 0),
                          ),
                        ),
                      ),
                    ),
                  // Dim overlay on drag source
                  if (isDragSource)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(color: Colors.black45),
                      ),
                    ),
                  // Green highlight on drag target
                  if (isDragTarget)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                            color: Colors.greenAccent.withValues(alpha: 0.15)),
                      ),
                    ),
                  // Reset position overlay – shown on selected cell with active transform
                  if (isSelected && !cell.isEmpty && (
                      _cellScales[index] != 1.0 ||
                      _cellAngles[index] != 0.0 ||
                      _cellOffsetX[index] != 0.0 ||
                      _cellOffsetY[index] != 0.0))
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () { setState(() {
                            _cellScales[index] = 1.0;
                            _cellAngles[index] = 0.0;
                            _cellOffsetX[index] = 0.0;
                            _cellOffsetY[index] = 0.0;
                          }); _saveDraft(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24, width: 0.5),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.restart_alt, color: Colors.white, size: 13),
                                SizedBox(width: 4),
                                Text('Reset position',
                                    style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Delete overlay – shown on selected non-empty cell
                  if (isSelected && !cell.isEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _clearCell(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, color: Colors.redAccent, size: 13),
                              SizedBox(width: 4),
                              Text('Remove',
                                  style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Cancel swap overlay – shown on the swap source cell
                  if (isSwapSource)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: GestureDetector(
                        onTap: _cancelSwapMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close, color: Colors.amber, size: 13),
                              SizedBox(width: 4),
                              Text('Cancel swap',
                                  style: TextStyle(color: Colors.amber, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Cancel drag overlay – shown on the drag source cell
                  if (isDragSource)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: GestureDetector(
                        onTap: _cancelDragMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pan_tool_outlined, color: Colors.amber, size: 13),
                              SizedBox(width: 4),
                              Text('Cancel drag',
                                  style: TextStyle(color: Colors.amber, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildCellWidget(
      Rect normRect, int index, double canvasW, double canvasH, List<Rect> cells) {
    final left = normRect.left * canvasW + _borderGap;
    final top = normRect.top * canvasH + _borderGap;
    final width = normRect.width * canvasW - _borderGap * 2;
    final height = normRect.height * canvasH - _borderGap * 2;
    final isSelected = _selectedCell == index;
    final isSwapSource = _swapMode && _swapSourceIdx == index;
    final isDragSource = _dragMode && _dragSourceCellIdx == index;
    final isDragTarget = _dragMode && _dragTargetCellIdx == index;
    final cell = _cells[index];

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () {
          if (_swapMode) {
            _doSwap(_swapSourceIdx!, index);
            return;
          }
          setState(() {
            if (_selectedCell == index) {
              _selectedCell = null;
            } else {
              _showVolumePanel = false;
              _selectedCell = index;
            }
          });
          if (_selectedCell == index && cell.isEmpty) _pickMediaForCell(index);
        },
        onLongPressStart: (_swapMode || _dragMode || cell.isEmpty)
            ? null
            : (details) {
                setState(() {
                  _dragMode = true;
                  _dragSourceCellIdx = index;
                  _dragCanvasNorm = Offset(
                    (left + details.localPosition.dx) / canvasW,
                    (top + details.localPosition.dy) / canvasH,
                  );
                  _dragTargetCellIdx = null;
                });
              },
        onLongPressMoveUpdate: (details) {
          if (!_dragMode || _dragSourceCellIdx != index) return;
          final nx = (left + details.localPosition.dx) / canvasW;
          final ny = (top + details.localPosition.dy) / canvasH;
          int? targetIdx;
          for (int i = 0; i < cells.length; i++) {
            if (i != index && cells[i].contains(Offset(nx, ny))) {
              targetIdx = i;
              break;
            }
          }
          setState(() {
            _dragCanvasNorm = Offset(nx, ny);
            _dragTargetCellIdx = targetIdx;
          });
        },
        onLongPressEnd: (details) {
          if (!_dragMode || _dragSourceCellIdx != index) return;
          final src = _dragSourceCellIdx!;
          final tgt = _dragTargetCellIdx;
          _cancelDragMode();
          if (tgt != null) _doSwap(src, tgt);
        },
        onLongPressCancel: () {
          if (_dragMode && _dragSourceCellIdx == index) _cancelDragMode();
        },
        onScaleStart: (_swapMode || _dragMode || cell.isEmpty)
            ? null
            : (details) {
                _saveSnapshot();
                _scalingCellIdx = index;
                _gestureBaseScale = _cellScales[index];
                _gestureBaseAngle = _cellAngles[index];
              },
        onScaleUpdate: (_swapMode || _dragMode || cell.isEmpty)
            ? null
            : (details) {
                if (_scalingCellIdx != index) return;
                setState(() {
                  if (details.pointerCount == 1) {
                    // Single finger → pan only
                    _cellOffsetX[index] += details.focalPointDelta.dx;
                    _cellOffsetY[index] += details.focalPointDelta.dy;
                  } else {
                    // Two fingers → zoom + rotate only (no pan accumulation)
                    _cellScales[index] =
                        (_gestureBaseScale * details.scale).clamp(0.5, 5.0);
                    _cellAngles[index] = _gestureBaseAngle + details.rotation;
                  }
                });
              },
        onScaleEnd: (_swapMode || _dragMode || cell.isEmpty) ? null : (_) { _scalingCellIdx = null; _saveDraft(); },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Cell content with border
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: isDragSource
                      ? Border.all(color: Colors.amber, width: _kBorderWidth + 1)
                      : isDragTarget
                          ? Border.all(color: Colors.greenAccent, width: _kBorderWidth + 1)
                          : isSwapSource
                              ? Border.all(color: Colors.amber, width: _kBorderWidth + 1)
                              : isSelected
                                  ? Border.all(color: _kRed, width: _kBorderWidth)
                                  : null,
                ),
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Transform(
                      alignment: Alignment.center,
                      transform: _cellMatrix(index,
                          cellW: constraints.maxWidth,
                          cellH: constraints.maxHeight),
                      child: _buildCellContent(index, cell),
                    ),
                  ),
                ),
              ),
            ),
            // Dim overlay on the drag source cell
            if (isDragSource)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.black45),
                ),
              ),
            // Green highlight overlay on drag target cell
            if (isDragTarget)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.greenAccent.withValues(alpha: 0.15)),
                ),
              ),
            // Reset position overlay – shown on selected cell with active transform
            if (isSelected && !cell.isEmpty && (
                _cellScales[index] != 1.0 ||
                _cellAngles[index] != 0.0 ||
                _cellOffsetX[index] != 0.0 ||
                _cellOffsetY[index] != 0.0))
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () { setState(() {
                      _cellScales[index] = 1.0;
                      _cellAngles[index] = 0.0;
                      _cellOffsetX[index] = 0.0;
                      _cellOffsetY[index] = 0.0;
                    }); _saveDraft(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restart_alt, color: Colors.white, size: 13),
                          SizedBox(width: 4),
                          Text('Reset position',
                              style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Delete overlay – shown on selected non-empty cell
            if (isSelected && !cell.isEmpty)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _clearCell(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.redAccent, size: 13),
                        SizedBox(width: 4),
                        Text('Remove',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            // Cancel swap overlay – shown on the swap source cell
            if (isSwapSource)
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: _cancelSwapMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, color: Colors.amber, size: 13),
                        SizedBox(width: 4),
                        Text('Cancel swap',
                            style: TextStyle(color: Colors.amber, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            // Cancel drag overlay – shown on the drag source cell
            if (isDragSource)
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: _cancelDragMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pan_tool_outlined, color: Colors.amber, size: 13),
                        SizedBox(width: 4),
                        Text('Cancel drag',
                            style: TextStyle(color: Colors.amber, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Returns a ColorFilter for the cell, or null if no filter is applied.
  ColorFilter? _cellColorFilter(int index) {
    final fi = _cellFilterIdx[index];
    if (fi <= 0 || fi >= _kFilters.length) return null;
    return _kFilters[fi].colorFilter;
  }

  Widget _buildCellContent(int index, CollageCellData cell) {
    if (cell.isEmpty) {
      return Container(
        color: const Color(0xFF555555),
        child: const Center(
          child: Icon(Icons.add, color: Colors.white38, size: 32),
        ),
      );
    }

    final cf = _cellColorFilter(index);

    Widget _filteredMedia(Widget media) =>
        cf != null ? ColorFiltered(colorFilter: cf, child: media) : media;

    if (cell.isVideo && _vcs.containsKey(index)) {
      final isPlaying = _playingCells.contains(index);
      final showPause = _pauseButtonVisible.contains(index);
      return Stack(
        fit: StackFit.expand,
        children: [
          // Media layer with filter
          GestureDetector(
            onTap: isPlaying ? () => _showPauseButton(index) : null,
            child: _filteredMedia(FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _vcs[index]!.value.size.width,
                height: _vcs[index]!.value.size.height,
                child: VideoPlayer(_vcs[index]!),
              ),
            )),
          ),
          // Play/pause controls (not filtered)
          if (!isPlaying)
            Center(
              child: GestureDetector(
                onTap: () => _toggleCellPlay(index),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          if (isPlaying)
            Center(
              child: AnimatedOpacity(
                opacity: showPause ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: showPause ? () => _toggleCellPlay(index) : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: const Icon(Icons.pause,
                        color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    // Image
    return _filteredMedia(
        Image.file(File(cell.filePath!), fit: BoxFit.cover));
  }

  // ── Draggable divider lines (always visible) ──────────────────────────────

  List<Widget> _buildDraggableDividers(
      List<Rect> cells, double cw, double ch) {
    if (_isArtistic) return [];
    final widgets = <Widget>[];
    final handled = <int>{};

    for (int di = 0; di < _dividers.length; di++) {
      final div = _dividers[di];

      final double dynSpanStart;
      final double dynSpanEnd;
      if (div.isVertical) {
        dynSpanStart = [cells[div.cellA].top, cells[div.cellB].top]
            .reduce((a, b) => a > b ? a : b);
        dynSpanEnd = [cells[div.cellA].bottom, cells[div.cellB].bottom]
            .reduce((a, b) => a < b ? a : b);
      } else {
        dynSpanStart = [cells[div.cellA].left, cells[div.cellB].left]
            .reduce((a, b) => a > b ? a : b);
        dynSpanEnd = [cells[div.cellA].right, cells[div.cellB].right]
            .reduce((a, b) => a < b ? a : b);
      }

      if (dynSpanEnd <= dynSpanStart + 0.001) continue;

      if (div.isVertical) {
        final lineTop = dynSpanStart * ch;
        final lineH = (dynSpanEnd - dynSpanStart) * ch;
        final lineX = div.position * cw;
        widgets.add(Positioned(
          left: lineX - 10,
          top: lineTop,
          width: 20,
          height: lineH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onPanStart: (_) => _saveSnapshot(),
            onPanUpdate: (d) => _moveDivider(
              di, (_dividers[di].position + d.delta.dx / cw).clamp(0.10, 0.90)),
            onPanEnd: (_) => _saveDraft(),
            child: Center(
              child: Container(
                width: 3, height: lineH,
                decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ));
      } else {
        final lineLeft = dynSpanStart * cw;
        final lineW = (dynSpanEnd - dynSpanStart) * cw;
        final lineY = div.position * ch;
        widgets.add(Positioned(
          left: lineLeft,
          top: lineY - 10,
          width: lineW,
          height: 20,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onPanStart: (_) => _saveSnapshot(),
            onPanUpdate: (d) => _moveDivider(
              di, (_dividers[di].position + d.delta.dy / ch).clamp(0.10, 0.90)),
            onPanEnd: (_) => _saveDraft(),
            child: Center(
              child: Container(
                width: lineW, height: 3,
                decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ));
      }

      if (handled.contains(di)) continue;

      final group = <int>[];
      for (int dj = di; dj < _dividers.length; dj++) {
        if (_dividers[dj].isVertical == div.isVertical &&
            (_dividers[dj].position - div.position).abs() < 0.02) {
          group.add(dj);
          handled.add(dj);
        }
      }

      if (div.isVertical) {
        final lineX = div.position * cw;
        final midY = (dynSpanStart + dynSpanEnd) / 2 * ch;
        widgets.add(_EdgeHandle(
          left: lineX - 14,
          top: midY - 14,
          isHoriz: false,
          onDrag: (dx, _) => _moveDivider(
            di, (_dividers[di].position + dx / cw).clamp(0.10, 0.90)),
        ));
      } else {
        final lineY = div.position * ch;
        final midX = (dynSpanStart + dynSpanEnd) / 2 * cw;
        widgets.add(_EdgeHandle(
          left: midX - 14,
          top: lineY - 14,
          isHoriz: true,
          onDrag: (_, dy) => _moveDivider(
            di, (_dividers[di].position + dy / ch).clamp(0.10, 0.90)),
        ));
      }
    }
    return widgets;
  }

  // ── Bottom panel ──────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    if (_showBgPanel) return _buildBgPanel();
    if (_showBorderPanel) return _buildBorderPanel();
    if (_showAspectPanel) return _buildAspectPanel();
    if (_showPlayModePanel) return _buildPlayModePanel();
    if (_showAudioPanel) return _buildAudioPanel();
    if (_showStickerPanel) return _buildStickerPanel();

    // Text overlay selected
    if (_selectedTextIdx != null &&
        _selectedTextIdx! < _textOverlays.length) {
      return _buildTextEditPanel(_selectedTextIdx!);
    }

    // Sticker overlay selected
    if (_selectedStickerIdx != null &&
        _selectedStickerIdx! < _stickerOverlays.length) {
      return _buildStickerEditPanel(_selectedStickerIdx!);
    }

    // GIF overlay selected
    if (_selectedGifIdx != null &&
        _selectedGifIdx! < _gifOverlays.length) {
      return _buildGifEditPanel(_selectedGifIdx!);
    }

    final cell =
        _selectedCell != null ? _cells[_selectedCell!] : null;

    if (_selectedCell != null && cell != null && !cell.isEmpty) {
      if (_showVolumePanel) return _buildVolumePanelForCell(_selectedCell!);
      if (_showTrimPanel) return _buildTrimPanelForCell(_selectedCell!);
      if (_showEditPanel) return _buildEditPanelForCell(_selectedCell!);
      if (_showFilterPanel) return _buildFilterPanel(_selectedCell!);
      if (_showSpeedPanel) return _buildSpeedPanel(_selectedCell!);
      return _buildClipPanel(cell, _selectedCell!);
    }

    return _buildMainToolbar();
  }

  Widget _buildMainToolbar() {
    final tools1 = [
      _ToolBtn(icon: Icons.grid_view, label: 'Layout',
          onTap: () => Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const CollageLayoutPicker()))),
      _ToolBtn(
        icon: Icons.image_outlined,
        label: 'Background',
        onTap: () => setState(() { _showBgPanel = true; _selectedCell = null; }),
        isHighlighted: _bgColor != Colors.black,
      ),
      _ToolBtn(
        icon: Icons.border_all_outlined,
        label: 'Border',
        onTap: () => setState(() { _showBorderPanel = true; _selectedCell = null; }),
        isHighlighted: _borderGap != 2.0,
      ),
      _ToolBtn(
        icon: _playMode == _PlayMode.sequential
            ? Icons.skip_next
            : _playMode == _PlayMode.manual
                ? Icons.touch_app_outlined
                : Icons.play_circle_outline,
        label: 'Play Mode',
        onTap: () => setState(() {
          _showPlayModePanel = true;
          _selectedCell = null;
        }),
        isHighlighted: _playMode != _PlayMode.sync,
      ),
      _ToolBtn(icon: Icons.music_note_outlined, label: 'Music',
          onTap: () => setState(() { _showAudioPanel = true; _selectedCell = null; })),
    ];
    final tools2 = [
      _ToolBtn(
        icon: Icons.text_fields,
        label: 'Text',
        onTap: () {
          final o = _TextOverlay();
          _saveSnapshot();
          setState(() {
            _textOverlays.add(o);
            _selectedTextIdx = _textOverlays.length - 1;
            _selectedCell = null;
            _selectedStickerIdx = null;
            _textCtrl.clear();
          });
          _saveDraft();
        },
        isHighlighted: _textOverlays.isNotEmpty,
      ),
      _ToolBtn(
        icon: Icons.emoji_emotions_outlined,
        label: 'Sticker',
        onTap: () => setState(() {
          _showStickerPanel = true;
          _selectedCell = null;
        }),
        isHighlighted: _stickerOverlays.isNotEmpty,
      ),
      _ToolBtn(
        icon: Icons.gif_box_outlined,
        label: 'GIF',
        onTap: _pickGif,
        isHighlighted: _gifOverlays.isNotEmpty,
      ),
      _ToolBtn(
        icon: Icons.aspect_ratio_outlined,
        label: 'Aspect',
        onTap: () => setState(() {
          _showAspectPanel = true;
          _selectedCell = null;
        }),
        isHighlighted: _aspectRatio != _CollageAspect.portrait916,
      ),
      _ToolBtn(icon: Icons.content_cut, label: 'Trim', onTap: () {}),
    ];

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolRow(tools1),
          _buildToolRow(tools2),
        ],
      ),
    );
  }

  Widget _buildToolRow(List<_ToolBtn> tools) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((t) => _buildToolIcon(t)).toList(),
      ),
    );
  }

  Widget _buildToolIcon(_ToolBtn t) {
    final disabled = t.onTap == null;
    final Color bgColor = t.isHighlighted
        ? const Color(0xFF3A2070)
        : const Color(0xFF2A2A2A);
    final Color iconColor = disabled
        ? Colors.white24
        : t.isHighlighted
            ? const Color(0xFFB880FF)
            : Colors.white70;
    final Color labelColor = disabled ? Colors.white24 : Colors.white54;

    return GestureDetector(
      onTap: t.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: t.isHighlighted
                  ? Border.all(color: const Color(0xFF7B35C8), width: 1.5)
                  : null,
            ),
            child: Icon(t.icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 4),
          Text(t.label,
              style: TextStyle(color: labelColor, fontSize: 10)),
        ],
      ),
    );
  }

  // ── Play Mode panel ────────────────────────────────────────────────────────

  Widget _buildPlayModePanel() {
    const cards = [
      (
        mode: _PlayMode.sync,
        label: 'Parallel',
        desc: 'All clips at once · loop to longest',
      ),
      (
        mode: _PlayMode.sequential,
        label: 'Sequential',
        desc: 'One after another · single timeline',
      ),
      (
        mode: _PlayMode.manual,
        label: 'Manual',
        desc: 'Tap each clip individually to play',
      ),
    ];

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Play mode',
              style: const TextStyle(
                color: Color(0xFF9B7FD4),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          const SizedBox(height: 16),
          // Mode cards
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Row(
              children: cards.map((c) {
                final active = _playMode == c.mode;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _setPlayMode(c.mode);
                      setState(() => _showPlayModePanel = false);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: active
                            ? const LinearGradient(
                                colors: [Color(0xFF7B3FCC), Color(0xFFAB5FD8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: active ? null : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.desc,
                            style: TextStyle(
                              color: active
                                  ? Colors.white70
                                  : Colors.white38,
                              fontSize: 12,
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
      ),
    );
  }

  // ── Background panel ───────────────────────────────────────────────────────

  static const _kBgSwatches = [
    // Row 1 — neutrals
    Colors.black,
    Color(0xFF1A1A1A),
    Color(0xFF333333),
    Color(0xFF555555),
    Color(0xFF888888),
    Color(0xFFBBBBBB),
    Color(0xFFDDDDDD),
    Colors.white,
    // Row 2 — warm / cool
    Color(0xFFCC2222),
    Color(0xFFE85A1A),
    Color(0xFFD4A000),
    Color(0xFF22AA44),
    Color(0xFF009977),
    Color(0xFF1166CC),
    Color(0xFF6633CC),
    Color(0xFFCC2277),
    // Row 3 — dark tones
    Color(0xFF5C0A0A),
    Color(0xFF6B2F00),
    Color(0xFF4A3A00),
    Color(0xFF0D4A1E),
    Color(0xFF003D30),
    Color(0xFF0A2A5C),
    Color(0xFF2A0D5C),
    Color(0xFF5C0A30),
  ];

  Widget _buildBgPanel() {
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showBgPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Background',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_bgColor != Colors.black)
                  GestureDetector(
                    onTap: () {
                      _saveSnapshot();
                      setState(() => _bgColor = Colors.black);
                      _saveDraft();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          // Color grid
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kBgSwatches.map((c) {
                final isSelected = _bgColor == c;
                return GestureDetector(
                  onTap: () { _saveSnapshot(); setState(() => _bgColor = c); _saveDraft(); },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: const Color(0xFFB8860B), width: 2.5)
                          : c == Colors.white
                              ? Border.all(
                                  color: Colors.white24, width: 1)
                              : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: c == Colors.white ||
                                    c == const Color(0xFFDDDDDD) ||
                                    c == const Color(0xFFBBBBBB)
                                ? Colors.black
                                : Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Border panel ───────────────────────────────────────────────────────────

  Widget _buildBorderPanel() {
    final presets = [
      (label: 'None', value: 0.0),
      (label: 'Thin', value: 2.0),
      (label: 'Medium', value: 6.0),
      (label: 'Thick', value: 14.0),
    ];

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showBorderPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Border',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_borderGap != 2.0)
                  GestureDetector(
                    onTap: () {
                      _saveSnapshot();
                      setState(() => _borderGap = 2.0);
                      _saveDraft();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          // Quick presets
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: presets.map((p) {
                final active = (_borderGap - p.value).abs() < 0.5;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _saveSnapshot();
                      setState(() => _borderGap = p.value);
                      _saveDraft();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF3A2070)
                            : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(10),
                        border: active
                            ? Border.all(
                                color: const Color(0xFF7B35C8),
                                width: 1.5)
                            : null,
                      ),
                      child: Column(
                        children: [
                          // Mini preview of border width
                          Container(
                            width: 32,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _bgColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(
                                  (p.value / 14.0 * 6).clamp(0, 6)),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF555555),
                                  borderRadius:
                                      BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(p.label,
                              style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Fine-grained slider
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Row(
              children: [
                const Icon(Icons.border_all_outlined,
                    color: Color(0xFFFF6B8E), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFFB8860B),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10),
                      trackHeight: 3,
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _borderGap,
                      min: 0,
                      max: 20,
                      onChangeStart: (_) => _saveSnapshot(),
                      onChanged: (v) => setState(() => _borderGap = v),
                      onChangeEnd: (_) => _saveDraft(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${_borderGap.round()}px',
                    style: const TextStyle(
                        color: Color(0xFFFF9500),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio panel ────────────────────────────────────────────────────────────

  String _fmtAudioTime(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.$tenths';
  }

  Future<void> _pickAudio() async {
    _saveSnapshot();
    AppOpenAdManager.instance.suppressNextResume();
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null || !mounted) return;

    _bgAudioPlayer?.stop();
    _bgAudioPlayer?.dispose();
    _bgAudioPlayer = AudioPlayer();
    await _bgAudioPlayer!.setSource(DeviceFileSource(path));
    await Future.delayed(const Duration(milliseconds: 400));
    final dur = await _bgAudioPlayer!.getDuration() ?? Duration.zero;

    if (!mounted) return;
    setState(() {
      _audioPath = path;
      _audioDuration = dur == Duration.zero ? const Duration(minutes: 5) : dur;
      _audioTrimStart = Duration.zero;
      _audioTrimEnd = _audioDuration;
      _bgAudioPlaying = false;
    });
    _saveDraft();
  }

  void _removeAudio() {
    _saveSnapshot();
    _bgAudioPlayer?.stop();
    _bgAudioPlayer?.dispose();
    _bgAudioPlayer = null;
    setState(() {
      _audioPath = null;
      _audioDuration = Duration.zero;
      _audioTrimStart = Duration.zero;
      _audioTrimEnd = Duration.zero;
      _bgAudioPlaying = false;
    });
    _saveDraft();
  }

  Future<void> _toggleBgAudio() async {
    if (_bgAudioPlayer == null || _audioPath == null) return;
    if (_bgAudioPlaying) {
      await _bgAudioPlayer!.pause();
      setState(() => _bgAudioPlaying = false);
    } else {
      await _bgAudioPlayer!.seek(_audioTrimStart);
      await _bgAudioPlayer!.setVolume(_audioVolume);
      await _bgAudioPlayer!.resume();
      setState(() => _bgAudioPlaying = true);
      final trimLen = _audioTrimEnd - _audioTrimStart;
      Future.delayed(trimLen, () {
        if (mounted && _bgAudioPlaying) {
          _bgAudioPlayer?.pause();
          setState(() => _bgAudioPlaying = false);
        }
      });
    }
  }

  Future<void> _stopBgAudio() async {
    await _bgAudioPlayer?.stop();
    setState(() => _bgAudioPlaying = false);
  }

  Future<void> _rewindBgAudio() async {
    await _bgAudioPlayer?.seek(_audioTrimStart);
    if (_bgAudioPlaying) await _bgAudioPlayer?.resume();
  }

  Widget _buildAudioPanel() {
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickAudio,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFCC2255), width: 1.5),
                    ),
                    child: const Text('Add audio',
                        style: TextStyle(
                            color: Color(0xFFFF3366),
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const Spacer(),
                _audioCtrlBtn(Icons.skip_previous, _audioPath != null ? _rewindBgAudio : null),
                const SizedBox(width: 6),
                _audioCtrlBtn(Icons.stop, _audioPath != null ? _stopBgAudio : null),
                const SizedBox(width: 6),
                _audioCtrlBtn(
                  _bgAudioPlaying ? Icons.pause : Icons.play_arrow,
                  _audioPath != null ? _toggleBgAudio : null,
                  highlighted: true,
                ),
              ],
            ),
          ),
          if (_audioPath != null) _buildAudioTrimCard(),
          GestureDetector(
            onTap: () => setState(() => _showAudioPanel = false),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audioCtrlBtn(IconData icon, VoidCallback? onTap, {bool highlighted = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: highlighted ? const Color(0xFF7B35C8) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: onTap != null ? Colors.white : Colors.white30, size: 20),
      ),
    );
  }

  Widget _buildAudioTrimCard() {
    if (_audioDuration == Duration.zero) return const SizedBox();
    final totalMs = _audioDuration.inMilliseconds.toDouble();
    final startFrac = (_audioTrimStart.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final endFrac = (_audioTrimEnd.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_audioTrimStart > Duration.zero || _audioTrimEnd < _audioDuration)
                GestureDetector(
                  onTap: () {
                    _saveSnapshot();
                    setState(() {
                      _audioTrimStart = Duration.zero;
                      _audioTrimEnd = _audioDuration;
                    });
                    _saveDraft();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Reset',
                        style: TextStyle(
                            color: Color(0xFFFF6B8E),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              _buildTimeControl(
                time: _audioTrimStart,
                onDecrement: () { _saveSnapshot(); setState(() {
                  final v = _audioTrimStart - const Duration(milliseconds: 100);
                  _audioTrimStart = v < Duration.zero ? Duration.zero : v;
                }); _saveDraft(); },
                onIncrement: () { _saveSnapshot(); setState(() {
                  final v = _audioTrimStart + const Duration(milliseconds: 100);
                  if (v < _audioTrimEnd) _audioTrimStart = v;
                }); _saveDraft(); },
              ),
              _buildTimeControl(
                time: _audioTrimEnd,
                onDecrement: () { _saveSnapshot(); setState(() {
                  final v = _audioTrimEnd - const Duration(milliseconds: 100);
                  if (v > _audioTrimStart) _audioTrimEnd = v;
                }); _saveDraft(); },
                onIncrement: () { _saveSnapshot(); setState(() {
                  final v = _audioTrimEnd + const Duration(milliseconds: 100);
                  _audioTrimEnd = v > _audioDuration ? _audioDuration : v;
                }); _saveDraft(); },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFFFF6B8E), size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFFFF6B8E),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: const Color(0xFFFF9500),
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 10),
                    trackHeight: 3,
                    overlayColor: Colors.transparent,
                  ),
                  child: RangeSlider(
                    values: RangeValues(startFrac, endFrac),
                    onChangeStart: (_) => _saveSnapshot(),
                    onChanged: (v) => setState(() {
                      _audioTrimStart = Duration(
                          milliseconds: (v.start * totalMs).round());
                      _audioTrimEnd = Duration(
                          milliseconds: (v.end * totalMs).round());
                    }),
                    onChangeEnd: (_) => _saveDraft(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _removeAudio,
                child: const Icon(Icons.close,
                    color: Color(0xFFCC2222), size: 22),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  _saveSnapshot();
                  final newVol = _audioVolume == 0.0 ? 1.0 : 0.0;
                  setState(() => _audioVolume = newVol);
                  _bgAudioPlayer?.setVolume(newVol);
                  _saveDraft();
                },
                child: Icon(
                  _audioVolume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: _audioVolume == 0
                      ? Colors.redAccent
                      : const Color(0xFFFF6B8E),
                  size: 22,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFFAB60D8),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    trackHeight: 3,
                    overlayColor: Colors.transparent,
                  ),
                  child: Slider(
                    value: _audioVolume,
                    min: 0.0,
                    max: 1.0,
                    onChangeStart: (_) => _saveSnapshot(),
                    onChanged: (v) {
                      setState(() => _audioVolume = v);
                      _bgAudioPlayer?.setVolume(v);
                    },
                    onChangeEnd: (_) => _saveDraft(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeControl({
    required Duration time,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onDecrement,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.chevron_left, color: Colors.white70, size: 22),
          ),
        ),
        Text(
          _fmtAudioTime(time),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5),
        ),
        GestureDetector(
          onTap: onIncrement,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.chevron_right, color: Colors.white70, size: 22),
          ),
        ),
      ],
    );
  }

  // ── Edit panel (rotate + flip) ─────────────────────────────────────────────

  Widget _buildEditPanelForCell(int idx) {
    final cell = _cells[idx];
    final s = cell.duration.inSeconds;
    final ms = (cell.duration.inMilliseconds % 1000) ~/ 100;
    final label =
        'Clip ${(idx + 1).toString().padLeft(2, '0')} · '
        '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}.$ms';

    final hasTransform = _cellRotSteps[idx] != 0 ||
        _cellFlipH[idx] || _cellFlipV[idx] ||
        _cellOffsetX[idx] != 0.0 || _cellOffsetY[idx] != 0.0 ||
        _cellScales[idx] != 1.0 || _cellAngles[idx] != 0.0;

    return Container(
      color: _kBg,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showEditPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (hasTransform)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _cellRotSteps[idx] = 0;
                        _cellFlipH[idx] = false;
                        _cellFlipV[idx] = false;
                        _cellOffsetX[idx] = 0.0;
                        _cellOffsetY[idx] = 0.0;
                        _cellScales[idx] = 1.0;
                        _cellAngles[idx] = 0.0;
                      });
                      _saveDraft();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Rotate row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildEditActionTile(
                    icon: Icons.rotate_left,
                    label: 'Rotate Left',
                    sublabel: '90°',
                    onTap: () {
                      setState(() => _cellRotSteps[idx] = (_cellRotSteps[idx] - 1 + 4) % 4);
                      _saveDraft();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildEditActionTile(
                    icon: Icons.rotate_right,
                    label: 'Rotate Right',
                    sublabel: '90°',
                    onTap: () {
                      setState(() => _cellRotSteps[idx] = (_cellRotSteps[idx] + 1) % 4);
                      _saveDraft();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Flip row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildEditActionTile(
                    icon: Icons.flip,
                    label: 'Flip',
                    sublabel: 'HORIZONTAL',
                    active: _cellFlipH[idx],
                    onTap: () {
                      setState(() => _cellFlipH[idx] = !_cellFlipH[idx]);
                      _saveDraft();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildEditActionTile(
                    icon: Icons.flip,
                    label: 'Flip',
                    sublabel: 'VERTICAL',
                    active: _cellFlipV[idx],
                    iconRotated: true,
                    onTap: () {
                      setState(() => _cellFlipV[idx] = !_cellFlipV[idx]);
                      _saveDraft();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildEditActionTile({
    required IconData icon,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
    bool active = false,
    bool iconRotated = false,
  }) {
    final Color bg = active
        ? const Color(0xFF3A2070)
        : const Color(0xFF252525);
    final Color border = active
        ? const Color(0xFF7B35C8)
        : Colors.transparent;
    final Color iconColor = active
        ? const Color(0xFFB880FF)
        : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: iconRotated ? 1 : 0,
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Text(sublabel,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }

  // ── Speed panel ────────────────────────────────────────────────────────────

  static const _kSpeedOptions = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0];

  String _speedLabel(double s) {
    if (s == s.truncateToDouble()) return '${s.toInt()}x';
    return '${s}x';
  }

  void _setCellSpeed(int idx, double speed) {
    setState(() => _cellSpeeds[idx] = speed);
    _vcs[idx]?.setPlaybackSpeed(speed);
    _saveDraft();
  }

  Widget _buildSpeedPanel(int idx) {
    final current = _cellSpeeds[idx];

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showSpeedPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Speed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (current != 1.0)
                  GestureDetector(
                    onTap: () {
                      _saveSnapshot();
                      _setCellSpeed(idx, 1.0);
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Color(0xFFB8860B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                Text(
                  _speedLabel(current),
                  style: const TextStyle(
                      color: Color(0xFFB8860B),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          // Speed tiles
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Row(
              children: _kSpeedOptions.map((s) {
                final active = current == s;
                final isSlow = s < 1.0;
                final isFast = s > 1.0;
                final accentColor = isSlow
                    ? const Color(0xFF40C4FF)
                    : isFast
                        ? const Color(0xFFFF6B8E)
                        : Colors.white70;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _setCellSpeed(idx, s);
                      setState(() => _showSpeedPanel = false);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF3A2070)
                            : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(12),
                        border: active
                            ? Border.all(
                                color: const Color(0xFF7B35C8), width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _speedLabel(s),
                            style: TextStyle(
                              color: active ? Colors.white : accentColor,
                              fontSize: s == 1.0 ? 16 : 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s == 0.25
                                ? 'Slowest'
                                : s == 0.5
                                    ? 'Slow'
                                    : s == 1.0
                                        ? 'Normal'
                                        : s == 1.5
                                            ? 'Fast'
                                            : s == 2.0
                                                ? 'Faster'
                                                : 'Fastest',
                            style: TextStyle(
                              color: active
                                  ? Colors.white60
                                  : Colors.white24,
                              fontSize: 9,
                              letterSpacing: 0.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (active) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFFB8860B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter panel ───────────────────────────────────────────────────────────

  static const List<_CollageFilter> _kFilters = [
    _CollageFilter(label: 'None'),
    _CollageFilter(
      label: 'B&W',
      colorFilter: ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ]),
      ffmpegVf: 'hue=s=0',
    ),
    _CollageFilter(
      label: 'Sepia',
      colorFilter: ColorFilter.matrix([
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0,     0,     0,     1, 0,
      ]),
      ffmpegVf: 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131',
    ),
    _CollageFilter(
      label: 'Vivid',
      colorFilter: ColorFilter.matrix([
         1.7874, -0.7152, -0.0722, 0, 0,
        -0.2126,  1.2848, -0.0722, 0, 0,
        -0.2126, -0.7152,  1.9278, 0, 0,
         0,       0,       0,      1, 0,
      ]),
      ffmpegVf: 'eq=saturation=2.0',
    ),
    _CollageFilter(
      label: 'Warm',
      colorFilter: ColorFilter.matrix([
        1.15, 0,   0,    0, 0,
        0,    1.0, 0,    0, 0,
        0,    0,   0.85, 0, 0,
        0,    0,   0,    1, 0,
      ]),
      ffmpegVf: 'colorchannelmixer=1.15:0:0:0:0:1:0:0:0:0:0.85:0',
    ),
    _CollageFilter(
      label: 'Cool',
      colorFilter: ColorFilter.matrix([
        0.85, 0,   0,    0, 0,
        0,    1.0, 0,    0, 0,
        0,    0,   1.15, 0, 0,
        0,    0,   0,    1, 0,
      ]),
      ffmpegVf: 'colorchannelmixer=0.85:0:0:0:0:1:0:0:0:0:1.15:0',
    ),
    _CollageFilter(
      label: 'Bright',
      colorFilter: ColorFilter.matrix([
        1, 0, 0, 0, 0.12,
        0, 1, 0, 0, 0.12,
        0, 0, 1, 0, 0.12,
        0, 0, 0, 1, 0,
      ]),
      ffmpegVf: 'eq=brightness=0.12',
    ),
    _CollageFilter(
      label: 'Dark',
      colorFilter: ColorFilter.matrix([
        1, 0, 0, 0, -0.15,
        0, 1, 0, 0, -0.15,
        0, 0, 1, 0, -0.15,
        0, 0, 0, 1, 0,
      ]),
      ffmpegVf: 'eq=brightness=-0.15',
    ),
    _CollageFilter(
      label: 'Fade',
      colorFilter: ColorFilter.matrix([
        0.5276, 0.4291, 0.0433, 0, 0.08,
        0.1276, 0.8291, 0.0433, 0, 0.08,
        0.1276, 0.4291, 0.4433, 0, 0.08,
        0,      0,      0,      1, 0,
      ]),
      ffmpegVf: 'eq=saturation=0.4:brightness=0.08',
    ),
    _CollageFilter(
      label: 'Contrast',
      colorFilter: ColorFilter.matrix([
        1.5, 0,   0,   0, -0.25,
        0,   1.5, 0,   0, -0.25,
        0,   0,   1.5, 0, -0.25,
        0,   0,   0,   1, 0,
      ]),
      ffmpegVf: 'eq=contrast=1.5',
    ),
  ];

  static const _kIdentityFilter = ColorFilter.matrix([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  Widget _buildFilterPanel(int idx) {
    final cell = _cells[idx];
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showFilterPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Filters',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_cellFilterIdx[idx] != 0)
                  GestureDetector(
                    onTap: () {
                      _saveSnapshot();
                      setState(() => _cellFilterIdx[idx] = 0);
                      _saveDraft();
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Color(0xFFB8860B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                Text(
                  _kFilters[_cellFilterIdx[idx]].label,
                  style: const TextStyle(
                      color: Color(0xFFB8860B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          // Filter swatches
          SizedBox(
            height: 116,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: _kFilters.length,
              itemBuilder: (_, fi) {
                final f = _kFilters[fi];
                final isActive = _cellFilterIdx[idx] == fi;
                return GestureDetector(
                  onTap: () { setState(() => _cellFilterIdx[idx] = fi); _saveDraft(); },
                  child: Container(
                    width: 68,
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 62,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isActive
                                ? Border.all(
                                    color: const Color(0xFF7B35C8), width: 2)
                                : Border.all(
                                    color: Colors.white12, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: ColorFiltered(
                              colorFilter:
                                  f.colorFilter ?? _kIdentityFilter,
                              child: _buildFilterThumb(idx, cell),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          f.label,
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFFB880FF)
                                : Colors.white54,
                            fontSize: 10,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterThumb(int cellIdx, CollageCellData cell) {
    if (cell.isVideo && _vcs.containsKey(cellIdx)) {
      final vc = _vcs[cellIdx]!;
      final w = vc.value.size.width;
      final h = vc.value.size.height;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w > 0 ? w : 1,
          height: h > 0 ? h : 1,
          child: VideoPlayer(vc),
        ),
      );
    }
    if (cell.filePath != null) {
      return Image.file(File(cell.filePath!), fit: BoxFit.cover);
    }
    // Placeholder: 4-color test gradient
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF87CEEB),
            Color(0xFF228B22),
            Color(0xFFFF7F50),
            Color(0xFFDEB887),
          ],
        ),
      ),
    );
  }

  // ── Text edit panel ────────────────────────────────────────────────────────

  static const _kTextColors = [
    Colors.white, Colors.black,
    Color(0xFFFFE066), Color(0xFFFF5252),
    Color(0xFF69F0AE), Color(0xFF40C4FF),
    Color(0xFFFF80AB), Color(0xFFCE93D8),
  ];

  static const _kTextBgColors = [
    Colors.transparent,
    Color(0xCC000000),
    Color(0xCCFFFFFF),
    Color(0xCCCC2222),
    Color(0xCC1166CC),
  ];

  static const _kTextSizes = [14.0, 20.0, 28.0, 40.0];
  static const _kTextSizeLabels = ['S', 'M', 'L', 'XL'];

  Widget _buildTextEditPanel(int idx) {
    final o = _textOverlays[idx];

    // Sync controller when overlay changes externally
    if (_textCtrl.text != o.text) {
      _textCtrl.value = TextEditingValue(
        text: o.text,
        selection: TextSelection.fromPosition(
            TextPosition(offset: o.text.length)),
      );
    }

    return Container(
      color: _kBg,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () { setState(() => _selectedTextIdx = null); _saveDraft(); },
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white70, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Text',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  // Style toggles
                  _textStyleBtn('B', o.bold, () { setState(() => o.bold = !o.bold); _saveDraft(); },
                      bold: true),
                  const SizedBox(width: 6),
                  _textStyleBtn('I', o.italic, () { setState(() => o.italic = !o.italic); _saveDraft(); },
                      italic: true),
                  const SizedBox(width: 6),
                  _textStyleBtn('S', o.shadow, () { setState(() => o.shadow = !o.shadow); _saveDraft(); }),
                  const SizedBox(width: 12),
                  // Delete
                  GestureDetector(
                    onTap: () { _saveSnapshot(); setState(() {
                      _textOverlays.removeAt(idx);
                      _selectedTextIdx = null;
                    }); _saveDraft(); },
                    child: const Icon(Icons.delete_outline,
                        color: Color(0xFFCC2222), size: 22),
                  ),
                ],
              ),
            ),
            // Text input
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _textCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Enter text…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => o.text = v),
                onSubmitted: (_) => _saveDraft(),
              ),
            ),
            // Font size presets
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: List.generate(_kTextSizes.length, (i) {
                  final active = o.fontSize == _kTextSizes[i];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => o.fontSize = _kTextSizes[i]); _saveDraft(); },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF3A2070)
                              : const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(8),
                          border: active
                              ? Border.all(
                                  color: const Color(0xFF7B35C8),
                                  width: 1.5)
                              : null,
                        ),
                        child: Text(
                          _kTextSizeLabels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white54,
                            fontSize: _kTextSizes[i].clamp(11, 18),
                            fontWeight: active
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Text color swatches
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  const Text('Color',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 0.5)),
                  const SizedBox(width: 10),
                  ..._kTextColors.map((c) {
                    final active = o.color == c;
                    return GestureDetector(
                      onTap: () { setState(() => o.color = c); _saveDraft(); },
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: active
                              ? Border.all(
                                  color: const Color(0xFFB8860B),
                                  width: 2)
                              : Border.all(
                                  color: Colors.white24, width: 1),
                        ),
                        child: active
                            ? Icon(Icons.check,
                                size: 14,
                                color: c == Colors.white
                                    ? Colors.black
                                    : Colors.white)
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
            // Background color swatches
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  const Text('BG   ',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 0.5)),
                  const SizedBox(width: 10),
                  ..._kTextBgColors.map((c) {
                    final active = o.bgColor == c;
                    final isTransparent = c == Colors.transparent;
                    return GestureDetector(
                      onTap: () { setState(() => o.bgColor = c); _saveDraft(); },
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: isTransparent ? null : c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active
                                ? const Color(0xFFB8860B)
                                : Colors.white24,
                            width: active ? 2 : 1,
                          ),
                        ),
                        child: isTransparent
                            ? const Center(
                                child: Icon(Icons.not_interested,
                                    color: Colors.white38, size: 14))
                            : active
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textStyleBtn(String label, bool active, VoidCallback onTap,
      {bool bold = false, bool italic = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3A2070) : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: const Color(0xFF7B35C8), width: 1.5)
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFFB880FF) : Colors.white54,
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ── Sticker panel (picker) ─────────────────────────────────────────────────

  static const _kStickers = [
    '😀','😍','😂','🥰','😎','🤩','😜','🤪',
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍',
    '⭐','🌟','✨','💫','⚡','🔥','💥','🌈',
    '🎉','🎊','🎈','🎁','🏆','🥇','🎯','🎀',
    '🌸','🌺','🌻','🌹','🍀','🌿','🌊','🏔️',
    '🐶','🐱','🦁','🐯','🐼','🦊','🐻','🦋',
    '🍕','🍔','🍦','🎂','🍭','🍫','☕','🥂',
    '📸','🎵','🎸','🎤','🎬','💃','✈️','💎',
  ];

  Widget _buildStickerPanel() {
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showStickerPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Stickers',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // Emoji grid
          SizedBox(
            height: 200,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: _kStickers.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  final o = _StickerOverlay(emoji: _kStickers[i]);
                  _saveSnapshot();
                  setState(() {
                    _stickerOverlays.add(o);
                    _selectedStickerIdx = _stickerOverlays.length - 1;
                    _selectedTextIdx = null;
                    _selectedCell = null;
                    _showStickerPanel = false;
                  });
                  _saveDraft();
                },
                child: Center(
                  child: Text(_kStickers[i],
                      style: const TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticker edit panel ─────────────────────────────────────────────────────

  Widget _buildStickerEditPanel(int idx) {
    final o = _stickerOverlays[idx];
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () { setState(() => _selectedStickerIdx = null); _saveDraft(); },
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                Text(o.emoji,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                const Text('Sticker',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                // Add another sticker
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedStickerIdx = null;
                    _showStickerPanel = true;
                  }),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Add',
                        style: TextStyle(
                            color: Color(0xFF7B35C8), fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                GestureDetector(
                  onTap: () { _saveSnapshot(); setState(() {
                    _stickerOverlays.removeAt(idx);
                    _selectedStickerIdx = null;
                  }); _saveDraft(); },
                  child: const Icon(Icons.delete_outline,
                      color: Color(0xFFCC2222), size: 22),
                ),
              ],
            ),
          ),
          // Scale slider
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Row(
              children: [
                const Icon(Icons.zoom_in,
                    color: Color(0xFFFF6B8E), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFFB8860B),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10),
                      trackHeight: 3,
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: o.scale.clamp(0.2, 4.0),
                      min: 0.2,
                      max: 4.0,
                      onChanged: (v) => setState(() => o.scale = v),
                      onChangeEnd: (_) => _saveDraft(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(o.scale * 100).round()}%',
                    style: const TextStyle(
                        color: Color(0xFFFF9500),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── GIF edit panel ─────────────────────────────────────────────────────────

  Widget _buildGifEditPanel(int idx) {
    final o = _gifOverlays[idx];
    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () { setState(() => _selectedGifIdx = null); _saveDraft(); },
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.gif_box_outlined,
                    color: Color(0xFFD94050), size: 22),
                const SizedBox(width: 6),
                const Text('GIF',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _previewGif(o.filePath),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.play_circle_outline,
                        color: Color(0xFF7B35C8), size: 24),
                  ),
                ),
                GestureDetector(
                  onTap: () { _saveSnapshot(); setState(() {
                    _gifOverlays.removeAt(idx);
                    _selectedGifIdx = null;
                  }); _saveDraft(); },
                  child: const Icon(Icons.delete_outline,
                      color: Color(0xFFCC2222), size: 22),
                ),
              ],
            ),
          ),
          // Scale slider
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Row(
              children: [
                const Icon(Icons.zoom_in,
                    color: Color(0xFFFF6B8E), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFFB8860B),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10),
                      trackHeight: 3,
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: o.scale.clamp(0.1, 5.0),
                      min: 0.1,
                      max: 5.0,
                      onChanged: (v) => setState(() => o.scale = v),
                      onChangeEnd: (_) => _saveDraft(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(o.scale * 100).round()}%',
                    style: const TextStyle(
                        color: Color(0xFFFF9500),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Aspect ratio panel ─────────────────────────────────────────────────────

  Widget _buildAspectPanel() {
    const aspects = [
      (ratio: _CollageAspect.portrait916, label: '9:16', w: 2.0, h: 3.6),
      (ratio: _CollageAspect.portrait34,  label: '3:4',  w: 2.4, h: 3.2),
      (ratio: _CollageAspect.square,      label: '1:1',  w: 2.8, h: 2.8),
      (ratio: _CollageAspect.landscape43, label: '4:3',  w: 3.2, h: 2.4),
      (ratio: _CollageAspect.landscape169,label: '16:9', w: 3.6, h: 2.0),
    ];

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showAspectPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Aspect Ratio',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // Tiles
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: aspects.map((a) {
                final active = _aspectRatio == a.ratio;
                return GestureDetector(
                  onTap: () {
                    _saveSnapshot();
                    setState(() {
                      _aspectRatio = a.ratio;
                      _showAspectPanel = false;
                    });
                    _saveDraft();
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF3A2070)
                              : const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(10),
                          border: active
                              ? Border.all(
                                  color: const Color(0xFF7B35C8), width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Container(
                            width: a.w * 9,
                            height: a.h * 9,
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF7B35C8)
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.label,
                        style: TextStyle(
                            color: active ? Colors.white : Colors.white54,
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w400),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Repeat toggle ──────────────────────────────────────────────────────────

  void _toggleRepeat(int idx) {
    _saveSnapshot();
    final next = !_cellRepeating[idx];
    setState(() => _cellRepeating[idx] = next);
    _vcs[idx]?.setLooping(next);
    _saveDraft();
  }

  // ── Trim panel ─────────────────────────────────────────────────────────────

  String _fmtTrimTime(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.$tenths';
  }

  Widget _buildTrimPanelForCell(int idx) {
    final cell = _cells[idx];
    final totalDur = cell.duration;
    if (totalDur == Duration.zero) {
      return Container(color: _kBg, child: const SizedBox());
    }

    final trimStart = cell.trimStart;
    final trimEnd = cell.trimEnd > Duration.zero ? cell.trimEnd : totalDur;
    final totalMs = totalDur.inMilliseconds.toDouble();
    final startFrac = (trimStart.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final endFrac = (trimEnd.inMilliseconds / totalMs).clamp(0.0, 1.0);

    final s = totalDur.inSeconds;
    final ms = (totalDur.inMilliseconds % 1000) ~/ 100;
    final label =
        'Clip ${(idx + 1).toString().padLeft(2, '0')} · ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.$ms';

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showTrimPanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                // Reset trim button
                if (cell.trimEnd > Duration.zero)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _cells[idx] = cell.copyWith(
                          trimStart: Duration.zero,
                          trimEnd: Duration.zero,
                        );
                      });
                      _vcs[idx]?.seekTo(Duration.zero);
                      _saveDraft();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Reset',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          // Trim card
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Start / End time controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTrimTimeControl(
                      label: 'START',
                      time: trimStart,
                      onDecrement: () {
                        final v = trimStart - const Duration(milliseconds: 100);
                        final next = v < Duration.zero ? Duration.zero : v;
                        setState(() {
                          _cells[idx] = cell.copyWith(
                              trimStart: next,
                              trimEnd: trimEnd);
                        });
                        _vcs[idx]?.seekTo(next);
                      },
                      onIncrement: () {
                        final v = trimStart + const Duration(milliseconds: 100);
                        if (v < trimEnd - const Duration(milliseconds: 200)) {
                          setState(() {
                            _cells[idx] = cell.copyWith(
                                trimStart: v,
                                trimEnd: trimEnd);
                          });
                          _vcs[idx]?.seekTo(v);
                        }
                      },
                    ),
                    Container(
                        width: 1, height: 32,
                        color: Colors.white12),
                    _buildTrimTimeControl(
                      label: 'END',
                      time: trimEnd,
                      onDecrement: () {
                        final v = trimEnd - const Duration(milliseconds: 100);
                        if (v > trimStart + const Duration(milliseconds: 200)) {
                          setState(() {
                            _cells[idx] = cell.copyWith(
                                trimStart: trimStart,
                                trimEnd: v);
                          });
                          _vcs[idx]?.seekTo(v);
                        }
                      },
                      onIncrement: () {
                        final v = trimEnd + const Duration(milliseconds: 100);
                        final next = v > totalDur ? totalDur : v;
                        setState(() {
                          _cells[idx] = cell.copyWith(
                              trimStart: trimStart,
                              trimEnd: next);
                        });
                        _vcs[idx]?.seekTo(next);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Range slider
                Row(
                  children: [
                    const Icon(Icons.content_cut,
                        color: Color(0xFFFF6B8E), size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: const Color(0xFFB8860B),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: const Color(0xFFFF9500),
                          rangeThumbShape: const RoundRangeSliderThumbShape(
                              enabledThumbRadius: 10),
                          trackHeight: 3,
                          overlayColor: Colors.transparent,
                        ),
                        child: RangeSlider(
                          values: RangeValues(startFrac, endFrac),
                          onChanged: (v) {
                            final newStart = Duration(
                                milliseconds: (v.start * totalMs).round());
                            final newEnd = Duration(
                                milliseconds: (v.end * totalMs).round());
                            setState(() {
                              _cells[idx] = cell.copyWith(
                                  trimStart: newStart,
                                  trimEnd: newEnd);
                            });
                            _vcs[idx]?.seekTo(newStart);
                          },
                          onChangeEnd: (_) => _saveDraft(),
                        ),
                      ),
                    ),
                    // Duration badge
                    const SizedBox(width: 6),
                    Text(
                      _fmtTrimTime(trimEnd - trimStart),
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrimTimeControl({
    required String label,
    required Duration time,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    void dec() { onDecrement(); _saveDraft(); }
    void inc() { onIncrement(); _saveDraft(); }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: dec,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.chevron_left,
                    color: Colors.white70, size: 22),
              ),
            ),
            Text(
              _fmtTrimTime(time),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5),
            ),
            GestureDetector(
              onTap: inc,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.chevron_right,
                    color: Colors.white70, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVolumePanelForCell(int idx) {
    final vol = _cellVolumes[idx];
    final isMuted = vol == 0.0;
    final cell = _cells[idx];
    final s = cell.duration.inSeconds;
    final ms = (cell.duration.inMilliseconds % 1000) ~/ 100;
    final label =
        'Clip ${(idx + 1).toString().padLeft(2, '0')} · ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.$ms';

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showVolumePanel = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (cell.isVideo)
                  const Text('VIDEO',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          // Volume slider card
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Volume label + percentage
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Clip Volume',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (vol != 1.0)
                          GestureDetector(
                            onTap: () {
                              _saveSnapshot();
                              setState(() => _cellVolumes[idx] = 1.0);
                              _vcs[idx]?.setVolume(1.0);
                              _saveDraft();
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text('Reset',
                                  style: TextStyle(
                                      color: Color(0xFFFF9500),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        Text(
                          isMuted ? 'Muted' : '${(vol * 100).round()}%',
                          style: TextStyle(
                              color: isMuted
                                  ? Colors.redAccent
                                  : const Color(0xFFFF9500),
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _saveSnapshot();
                        final newVol = isMuted ? 1.0 : 0.0;
                        setState(() => _cellVolumes[idx] = newVol);
                        _vcs[idx]?.setVolume(newVol);
                        _saveDraft();
                      },
                      child: Icon(
                        isMuted ? Icons.volume_off : Icons.volume_up,
                        color: isMuted
                            ? Colors.redAccent
                            : const Color(0xFFFF6B8E),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: const Color(0xFFB8860B),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 10),
                          trackHeight: 3,
                          overlayColor: Colors.transparent,
                        ),
                        child: Slider(
                          value: vol,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            setState(() => _cellVolumes[idx] = v);
                            _vcs[idx]?.setVolume(v);
                          },
                          onChangeEnd: (_) => _saveDraft(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipPanel(CollageCellData cell, int idx) {
    final s = cell.duration.inSeconds;
    final ms = (cell.duration.inMilliseconds % 1000) ~/ 100;
    final label =
        'Clip ${(idx + 1).toString().padLeft(2, '0')} · ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.$ms';

    final actions1 = [
      _ToolBtn(icon: Icons.swap_vert, label: 'Replace',
          sublabel: 'SOURCE', onTap: () => _pickMediaForCell(idx)),
      _ToolBtn(icon: Icons.swap_horiz, label: 'Swap',
          sublabel: 'TWO CLIPS', onTap: () => _enterSwapMode(idx)),
      _ToolBtn(icon: Icons.volume_up_outlined, label: 'Volume',
          onTap: () { _saveSnapshot(); setState(() => _showVolumePanel = true); }),
      _ToolBtn(
        icon: Icons.speed,
        label: 'Speed',
        onTap: cell.isVideo ? () { _saveSnapshot(); setState(() => _showSpeedPanel = true); } : null,
        isHighlighted: cell.isVideo && _cellSpeeds[idx] != 1.0,
      ),
    ];
    final actions2 = [
      _ToolBtn(
        icon: Icons.content_cut,
        label: 'Trim',
        onTap: cell.isVideo
            ? () { _saveSnapshot(); setState(() => _showTrimPanel = true); }
            : null,
        isHighlighted: cell.isVideo && cell.trimEnd > Duration.zero,
      ),
      _ToolBtn(
        icon: Icons.repeat,
        label: 'Repeat',
        onTap: cell.isVideo ? () => _toggleRepeat(idx) : null,
        isHighlighted: cell.isVideo && _cellRepeating[idx],
      ),
      _ToolBtn(
        icon: Icons.rotate_right_outlined,
        label: 'Edit',
        sublabel: 'ROTATE · FLIP',
        onTap: () { _saveSnapshot(); setState(() => _showEditPanel = true); },
        isHighlighted: _cellRotSteps[idx] != 0 ||
            _cellFlipH[idx] ||
            _cellFlipV[idx],
      ),
      _ToolBtn(
        icon: Icons.auto_fix_high,
        label: 'Filter',
        onTap: () { _saveSnapshot(); setState(() => _showFilterPanel = true); },
        isHighlighted: _cellFilterIdx[idx] != 0,
      ),
    ];

    return Container(
      color: _kBg,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: _kOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (cell.isVideo)
                    const Text('VIDEO',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  GestureDetector(
                    onTap: () => setState(() { _selectedCell = null; }),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Icon(Icons.close, color: Colors.white54, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            _buildToolRow(actions1),
            _buildToolRow(actions2),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Path clipper for artistic cells ──────────────────────────────────────────

class _PathClipper extends CustomClipper<Path> {
  final Path path;
  _PathClipper(this.path);

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper old) => false;
}

// ── Path stroke painter for artistic cell selection ───────────────────────────

class _PathStrokePainter extends CustomPainter {
  final Path path;
  final Color color;
  final double strokeWidth;

  _PathStrokePainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PathStrokePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.path != path;
}

// ── Divider model ─────────────────────────────────────────────────────────────

class _Divider {
  final bool isVertical;
  final double position;
  final double spanStart;
  final double spanEnd;
  final int cellA;
  final int cellB;

  const _Divider({
    required this.isVertical,
    required this.position,
    required this.spanStart,
    required this.spanEnd,
    required this.cellA,
    required this.cellB,
  });

  _Divider copyWith({double? position}) => _Divider(
        isVertical: isVertical,
        position: position ?? this.position,
        spanStart: spanStart,
        spanEnd: spanEnd,
        cellA: cellA,
        cellB: cellB,
      );
}

// ── Handle widgets ────────────────────────────────────────────────────────────

class _EdgeHandle extends StatelessWidget {
  final double left, top;
  final bool isHoriz; // true = ≡ (horizontal), false = ||| (vertical)
  final void Function(double dx, double dy)? onDrag;

  const _EdgeHandle({
    required this.left,
    required this.top,
    required this.isHoriz,
    this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFFCC2222),
        shape: BoxShape.circle,
      ),
      child: RotatedBox(
        quarterTurns: isHoriz ? 0 : 1,
        child: const Icon(
          Icons.menu,
          color: Colors.white,
          size: 14,
        ),
      ),
    );
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onPanUpdate: onDrag != null ? (d) => onDrag!(d.delta.dx, d.delta.dy) : null,
        child: btn,
      ),
    );
  }
}

// ── Source picker bottom sheet ────────────────────────────────────────────────

class _SourcePickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tap here to add a video',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('PICK SOURCE',
                style: TextStyle(color: Colors.white38, fontSize: 11,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SourceTile(
                  icon: Icons.video_library_outlined,
                  iconColor: const Color(0xFF5B35C8),
                  title: 'Video',
                  subtitle: 'LIBRARY',
                  isHighlighted: true,
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceTile(
                  icon: Icons.gif_box_outlined,
                  iconColor: const Color(0xFFD94050),
                  title: 'GIF',
                  subtitle: 'ANIMATED',
                  onTap: () => Navigator.pop(context, 'gif'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SourceTile(
                  icon: Icons.camera_alt_outlined,
                  iconColor: const Color(0xFFB8860B),
                  title: 'Capture',
                  subtitle: 'LIVE',
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceTile(
                  icon: Icons.photo_library_outlined,
                  iconColor: const Color(0xFF2C8C6C),
                  title: 'Photos',
                  subtitle: 'LIBRARY',
                  onTap: () => Navigator.pop(context, 'photo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Icon(Icons.keyboard_arrow_down,
                color: Colors.white38, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isHighlighted
              ? const Color(0xFF252535)
              : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: isHighlighted
              ? Border.all(color: const Color(0xFF5B35C8), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10,
                        letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Strip thumbnail ───────────────────────────────────────────────────────────

class _StripThumb extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback onTap;
  const _StripThumb({required this.asset, required this.onTap});

  @override
  State<_StripThumb> createState() => _StripThumbState();
}

class _StripThumbState extends State<_StripThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(120))
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 56,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: _bytes == null
            ? const SizedBox()
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(_bytes!, fit: BoxFit.cover)),
      ),
    );
  }
}

// ── Play mode ─────────────────────────────────────────────────────────────────

enum _PlayMode { sync, sequential, manual }

// ── Aspect ratio ──────────────────────────────────────────────────────────────

enum _CollageAspect { portrait916, portrait34, square, landscape43, landscape169 }

// ── Overlay models ────────────────────────────────────────────────────────────

class _TextOverlay {
  String text;
  double x, y;       // normalized center 0..1
  double fontSize;
  Color color;
  Color bgColor;
  bool bold;
  bool italic;
  bool shadow;
  double scale;
  double rotation;

  _TextOverlay({
    this.text = '',
    this.x = 0.5,
    this.y = 0.38,
    this.fontSize = 20,
    this.color = Colors.white,
    this.bgColor = Colors.transparent,
    this.bold = false,
    this.italic = false,
    this.shadow = false,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'color': color.toARGB32(),
        'bgColor': bgColor.toARGB32(),
        'bold': bold,
        'italic': italic,
        'shadow': shadow,
        'scale': scale,
        'rotation': rotation,
      };

  factory _TextOverlay.fromJson(Map<String, dynamic> j) => _TextOverlay(
        text: j['text'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.38,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 20,
        color: Color((j['color'] as num?)?.toInt() ?? Colors.white.toARGB32()),
        bgColor: Color((j['bgColor'] as num?)?.toInt() ?? Colors.transparent.toARGB32()),
        bold: (j['bold'] as bool?) ?? false,
        italic: (j['italic'] as bool?) ?? false,
        shadow: (j['shadow'] as bool?) ?? false,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

class _StickerOverlay {
  String emoji;
  double x, y;       // normalized center 0..1
  double scale;
  double rotation;

  _StickerOverlay({
    required this.emoji,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory _StickerOverlay.fromJson(Map<String, dynamic> j) => _StickerOverlay(
        emoji: j['emoji'] as String,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

class _GifOverlay {
  String filePath;
  double x, y;       // normalized center 0..1
  double scale;
  double rotation;

  _GifOverlay({
    required this.filePath,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory _GifOverlay.fromJson(Map<String, dynamic> j) => _GifOverlay(
        filePath: j['filePath'] as String,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

// ── Color filter preset ───────────────────────────────────────────────────────

class _CollageFilter {
  final String label;
  final ColorFilter? colorFilter;  // Flutter live preview
  final String? ffmpegVf;          // FFmpeg vf chain fragment for export

  const _CollageFilter({
    required this.label,
    this.colorFilter,
    this.ffmpegVf,
  });
}

// ── Undo / redo snapshot ──────────────────────────────────────────────────────

class _CollageSnapshot {
  final List<CollageCellData> cells;
  final List<_Divider> dividers;
  final Color bgColor;
  final double borderGap;
  final List<double> cellVolumes;
  final List<bool> cellRepeating;
  final List<int> cellRotSteps;
  final List<bool> cellFlipH;
  final List<bool> cellFlipV;
  final List<double> cellScales;
  final List<double> cellAngles;
  final List<double> cellOffsetX;
  final List<double> cellOffsetY;
  final List<_TextOverlay> textOverlays;
  final List<_StickerOverlay> stickerOverlays;
  final List<_GifOverlay> gifOverlays;
  final List<int> cellFilterIdx;
  final List<double> cellSpeeds;
  final _CollageAspect aspectRatio;
  final _PlayMode playMode;
  final String? audioPath;
  final Duration audioDuration;
  final Duration audioTrimStart;
  final Duration audioTrimEnd;
  final double audioVolume;

  const _CollageSnapshot({
    required this.cells,
    required this.dividers,
    required this.bgColor,
    required this.borderGap,
    required this.cellVolumes,
    required this.cellRepeating,
    required this.cellRotSteps,
    required this.cellFlipH,
    required this.cellFlipV,
    required this.cellScales,
    required this.cellAngles,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.textOverlays,
    required this.stickerOverlays,
    required this.gifOverlays,
    required this.cellFilterIdx,
    required this.cellSpeeds,
    required this.aspectRatio,
    required this.playMode,
    required this.audioPath,
    required this.audioDuration,
    required this.audioTrimStart,
    required this.audioTrimEnd,
    required this.audioVolume,
  });
}

// ── Helper models ─────────────────────────────────────────────────────────────

class _ToolBtn {
  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const _ToolBtn({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.onTap,
    this.isHighlighted = false,
  });
}
