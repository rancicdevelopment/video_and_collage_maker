import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../ad/app_open_ad_manager.dart';

// ── Public result type ───────────────────────────────────────────────────────

class PickedMediaFile {
  final String path;
  final bool isVideo;
  final Duration duration;

  const PickedMediaFile({
    required this.path,
    required this.isVideo,
    required this.duration,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

/// Initial tab index: 0 = VIDEO, 1 = PHOTO, 2 = ALL
class MediaPickerScreen extends StatefulWidget {
  final int initialTab;

  /// Maximum number of assets the user can select. null = unlimited.
  final int? maxAssets;

  const MediaPickerScreen({super.key, this.initialTab = 0, this.maxAssets});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  static const _kOrange = Color(0xFFF5A623);
  static const _kBg = Color(0xFF1A1A1A);

  late int _tabIndex;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _permissionDenied = false;

  /// Ordered selection (preserves pick order).
  final List<AssetEntity> _selected = [];

  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    _requestAndLoad();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  // ── Permission + loading ──────────────────────────────────────────────────

  Future<void> _requestAndLoad() async {
    AppOpenAdManager.instance.suppressNextResume();
    final result = await PhotoManager.requestPermissionExtend();
    if (!result.isAuth && result != PermissionState.limited) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    await _loadAlbums();
  }

  RequestType get _requestType {
    switch (_tabIndex) {
      case 0:
        return RequestType.video;
      case 1:
        return RequestType.image;
      default:
        return RequestType.common;
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _loading = true);
    final albums = await PhotoManager.getAssetPathList(
      type: _requestType,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _currentAlbum = albums.isNotEmpty ? albums.first : null;
    });
    await _loadAssets();
  }

  Future<void> _loadAssets() async {
    if (_currentAlbum == null) {
      setState(() {
        _assets = [];
        _loading = false;
      });
      return;
    }
    final count = await _currentAlbum!.assetCountAsync;
    final assets = await _currentAlbum!.getAssetListRange(
      start: 0,
      end: count.clamp(0, 1000),
    );
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  // ── Selection helpers ─────────────────────────────────────────────────────

  int _selIdx(AssetEntity a) => _selected.indexWhere((e) => e.id == a.id);

  void _toggle(AssetEntity a) {
    setState(() {
      final idx = _selIdx(a);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        if (widget.maxAssets != null && _selected.length >= widget.maxAssets!) return;
        _selected.add(a);
      }
    });
  }

  // ── Confirm ───────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    final results = <PickedMediaFile>[];
    for (final asset in _selected) {
      final file = await asset.originFile;
      if (file == null) continue;
      results.add(PickedMediaFile(
        path: file.path,
        isVideo: asset.type == AssetType.video,
        duration: asset.videoDuration,
      ));
    }
    if (mounted) Navigator.pop(context, results);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtDur(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool _is4K(AssetEntity a) {
    final longer = a.width > a.height ? a.width : a.height;
    return longer >= 2160;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildTabBar(),
            Expanded(
              child: _permissionDenied
                  ? _buildPermissionDenied()
                  : _loading
                      ? const _GridShimmer()
                      : _assets.isEmpty
                          ? _buildEmpty()
                          : Stack(children: [
                              _buildGrid(),
                              if (_showHint) _buildHintBadge(),
                            ]),
            ),
            _buildBottomBar(),
            if (_selected.isNotEmpty) _buildSelectedStrip(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          GestureDetector(
            onTap: _openAlbumPicker,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentAlbum?.name ?? 'Recent',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
          const Spacer(),

        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    const labels = ['VIDEO', 'PHOTO', 'ALL'];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_tabIndex == i) return;
                setState(() {
                  _tabIndex = i;
                  _selected.clear();
                });
                _loadAlbums();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? _kOrange : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? _kOrange : Colors.white54,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    return GridView.builder(
      padding: EdgeInsets.zero,
      // Limit pre-render to 2 screen-heights so off-screen thumbnails are not
      // all decoded simultaneously — keeps memory pressure low on large galleries.
      cacheExtent: MediaQuery.sizeOf(context).height * 2,
      itemCount: _assets.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
      ),
      itemBuilder: (_, i) => _buildCell(_assets[i]),
    );
  }

  Widget _buildCell(AssetEntity asset) {
    final selIdx = _selIdx(asset);
    final selected = selIdx >= 0;

    return GestureDetector(
      onTap: () => _toggle(asset),
      onLongPress: () => _previewAsset(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail — 160 px is sufficient for a 4-column grid cell.
          _AssetThumb(asset: asset, size: 160),

          // Orange selection border + tint
          if (selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _kOrange, width: 3),
                color: _kOrange.withValues(alpha: 0.18),
              ),
            ),

          // "4K" badge — top left
          if (_is4K(asset))
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('4K',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),

          // Duration — bottom left (videos only)
          if (asset.type == AssetType.video)
            Positioned(
              bottom: 4,
              left: 5,
              child: Text(
                _fmtDur(asset.videoDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(blurRadius: 6, color: Colors.black),
                    Shadow(blurRadius: 2, color: Colors.black),
                  ],
                ),
              ),
            ),

          // Selection badge — top right
          Positioned(
            top: 4,
            right: 4,
            child: selected
                ? Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: _kOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${selIdx + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                : Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white60, width: 1.5),
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Hint badge ────────────────────────────────────────────────────────────

  Widget _buildHintBadge() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Text(
            'LONG PRESS TO PREVIEW',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final vCount =
        _selected.where((a) => a.type == AssetType.video).length;
    final pCount =
        _selected.where((a) => a.type == AssetType.image).length;
    final hasSelection = _selected.isNotEmpty;

    return Container(
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          if (hasSelection)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              onPressed: () => setState(() => _selected.clear()),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasSelection
                  ? 'Selected $vCount Video(s)/$pCount Photo(s)'
                  : 'You can select video(s) / photo(s)',
              style: TextStyle(
                color: hasSelection ? Colors.white : Colors.white38,
                fontSize: 13,
              ),
            ),
          ),
          // FAB arrow
          GestureDetector(
            onTap: hasSelection ? _confirm : null,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasSelection
                    ? const LinearGradient(
                        colors: [Color(0xFFF5A623), Color(0xFFE8434A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: hasSelection ? null : const Color(0xFF2A2A2A),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: hasSelection ? Colors.white : Colors.white24,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Selected strip ────────────────────────────────────────────────────────

  Widget _buildSelectedStrip() {
    return Container(
      color: const Color(0xFF111111),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 76,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: _selected.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _selected.removeAt(oldIdx);
                  _selected.insert(newIdx, item);
                });
              },
              itemBuilder: (_, i) =>
                  _buildStripItem(_selected[i], i),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Long press and drag to swap order',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStripItem(AssetEntity asset, int index) {
    return ReorderableDragStartListener(
      key: ValueKey(asset.id),
      index: index,
      child: SizedBox(
        width: 68,
        height: 76,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _AssetThumb(asset: asset, size: 160),
              ),
            ),
            // Duration label
            if (asset.type == AssetType.video)
              Positioned(
                bottom: 10,
                left: 6,
                right: 6,
                child: Text(
                  _fmtDur(asset.videoDuration),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
            // X remove button — top right
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () =>
                    setState(() => _selected.remove(asset)),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: _kOrange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Long-press preview ────────────────────────────────────────────────────

  Future<void> _previewAsset(AssetEntity asset) async {
    if (asset.type == AssetType.video) {
      final file = await asset.originFile;
      if (file == null || !mounted) return;
      await showDialog(
        context: context,
        builder: (_) => _VideoPreviewDialog(file: file),
      );
    } else {
      final file = await asset.originFile;
      if (file == null || !mounted) return;
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      );
    }
  }

  // ── Album picker ──────────────────────────────────────────────────────────

  Future<void> _openAlbumPicker() async {
    if (_albums.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Select Album',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _albums.length,
              itemBuilder: (_, i) {
                final album = _albums[i];
                final active = _currentAlbum?.id == album.id;
                return ListTile(
                  title: Text(album.name,
                      style: const TextStyle(color: Colors.white)),
                  trailing: active
                      ? const Icon(Icons.check, color: _kOrange)
                      : null,
                  onTap: () {
                    setState(() {
                      _currentAlbum = album;
                      _selected.clear();
                    });
                    Navigator.pop(ctx);
                    _loadAssets();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Permission denied / empty ─────────────────────────────────────────────

  Widget _buildPermissionDenied() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text('Gallery access denied',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Enable permission in Settings',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            style: TextButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text('No media found',
          style: TextStyle(color: Colors.white38, fontSize: 14)),
    );
  }
}

// ── Thumbnail concurrency limiter ─────────────────────────────────────────────
// Caps simultaneous thumbnailDataWithSize calls to avoid OOM from MediaCodec.

class _ThumbSemaphore {
  final int maxConcurrent;
  int _running = 0;
  final _queue = <void Function()>[];

  _ThumbSemaphore(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() fn) async {
    if (_running < maxConcurrent) {
      _running++;
      try {
        return await fn();
      } finally {
        _running--;
        if (_queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          next();
        }
      }
    }
    final completer = Completer<T>();
    _queue.add(() async {
      _running++;
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _running--;
        if (_queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          next();
        }
      }
    });
    return completer.future;
  }
}

// ── Thumbnail widget ─────────────────────────────────────────────────────────

class _AssetThumb extends StatefulWidget {
  final AssetEntity asset;
  final int size;
  const _AssetThumb({required this.asset, required this.size});

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  // Max 4 concurrent thumbnail decodes — prevents MediaCodec/MediaMetadataRetriever OOM.
  static final _sem = _ThumbSemaphore(4);

  Uint8List? _bytes;
  // Generation counter: incremented on each new load request so that a stale
  // future result from a previous asset is discarded.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AssetThumb old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id || old.size != widget.size) {
      _bytes = null; // clear stale image immediately
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final bytes = await _sem.run(() => widget.asset.thumbnailDataWithSize(
          // 160 px is sufficient for a 4-column grid; 85→70 quality saves memory.
          ThumbnailSize.square(widget.size),
          quality: 70,
        ));
    // Discard result if widget was recycled for a different asset.
    if (mounted && gen == _loadGen) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return const _ShimmerBox();
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  }
}

// ── Shimmer widgets ──────────────────────────────────────────────────────────

class _GridShimmer extends StatelessWidget {
  const _GridShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: 32,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
      ),
      itemBuilder: (_, __) => const _ShimmerBox(),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();
  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              Color(0xFF2A2A2A),
              Color(0xFF3A3A3A),
              Color(0xFF2A2A2A),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Video preview dialog ─────────────────────────────────────────────────────

class _VideoPreviewDialog extends StatefulWidget {
  final File file;
  const _VideoPreviewDialog({required this.file});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.play();
        _ctrl.setLooping(true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      // Shape on Dialog avoids ClipRRect around VideoPlayer.
      // ClipRRect calls canvas.saveLayer() which conflicts with Android's
      // hardware video texture and causes black-frame flickering.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: _ready ? _ctrl.value.aspectRatio : 9 / 16,
        child: _ready
            ? GestureDetector(
                // No setState — VideoPlayer updates itself via the controller.
                onTap: () => _ctrl.value.isPlaying
                    ? _ctrl.pause()
                    : _ctrl.play(),
                child: VideoPlayer(_ctrl),
              )
            : const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFF5A623))),
      ),
    );
  }
}
