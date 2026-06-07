import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../camera/camera_screen.dart';
import '../settings/settings_screen.dart';
import 'all_projects_screen.dart';
import '../video_editor/video_editor_screen.dart';
import '../explore/explore_screen.dart';
import '../collage/collage_layout_picker.dart';
import '../collage/collage_editor_screen.dart';
import 'all_collage_projects_screen.dart';
import '../collage/collage_models.dart';
import '../recorder/recorder_screen.dart';
import '../../ad/banner_ad_widget.dart';
import '../../ad/exit_dialog.dart';
import '../../data/draft_manager.dart';
import '../../data/collage_draft_manager.dart';
import '../media_picker/media_picker_screen.dart';
import '../video_editor/video_editor_model.dart' show TrackType;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _DraftSort { newestFirst, oldestFirst, nameAZ, nameZA, longestFirst, shortestFirst }

class _HomeScreenState extends State<HomeScreen> {
  List<DraftProject> _drafts = [];
  List<DraftProject> _allDrafts = [];
  bool _loadingDrafts = true;
  final _DraftSort _sortOrder = _DraftSort.newestFirst;
  final String _searchQuery = '';

  List<CollageDraft> _collageDrafts = [];
  bool _loadingCollageDrafts = true;

  List<AssetEntity> _recentVideos = [];
  bool _recentLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
    _loadCollageDrafts();
    _loadRecentVideos();
  }

  Future<void> _loadCollageDrafts() async {
    final drafts = await CollageDraftManager.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _collageDrafts = drafts;
      _loadingCollageDrafts = false;
    });
  }

  Future<void> _loadDrafts() async {
    final drafts = await DraftManager.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _allDrafts = drafts;
      _loadingDrafts = false;
      _applyFilterSort();
    });
    // Generate missing thumbnails in the background.
    _generateMissingThumbnails(drafts);
  }

  // Returns true for regular files that exist OR for content:// URIs (Android media store).
  bool _pathAccessible(String path) {
    if (path.startsWith('content://')) return true;
    return File(path).existsSync();
  }

  Future<void> _generateMissingThumbnails(List<DraftProject> drafts) async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    for (final draft in drafts) {
      if (!mounted) return;
      if (draft.thumbnailPath != null && File(draft.thumbnailPath!).existsSync()) {
        continue;
      }

      // Prefer image tracks first, then video tracks.
      // Accept both regular file paths and content:// URIs.
      final imageTrack = draft.tracks
          .where((t) => t.trackType == TrackType.image && _pathAccessible(t.filePath))
          .firstOrNull;
      final videoTrack = draft.tracks
          .where((t) => t.trackType == TrackType.video && _pathAccessible(t.filePath))
          .firstOrNull;

      if (imageTrack != null) {
        // Use the image file directly as thumbnail — no extraction needed.
        final updated = draft.copyWith(thumbnailPath: imageTrack.filePath);
        await DraftManager.instance.save(updated);
        if (mounted) {
          setState(() {
            final idx = _allDrafts.indexWhere((d) => d.id == draft.id);
            if (idx != -1) _allDrafts[idx] = updated;
            _applyFilterSort();
          });
        }
      } else if (videoTrack != null) {
        try {
          final destPath = '$dir/drafts/thumb_${draft.id}.jpg';
          final result = await VideoThumbnail.thumbnailFile(
            video: videoTrack.filePath,
            thumbnailPath: destPath,
            imageFormat: ImageFormat.JPEG,
            timeMs: 0,
            maxHeight: 300,
            quality: 80,
          );
          final resultFile = result != null ? File(result) : null;
          if (resultFile != null && resultFile.existsSync() && resultFile.lengthSync() > 0 && mounted) {
            final updated = draft.copyWith(thumbnailPath: result);
            await DraftManager.instance.save(updated);
            setState(() {
              final idx = _allDrafts.indexWhere((d) => d.id == draft.id);
              if (idx != -1) _allDrafts[idx] = updated;
              _applyFilterSort();
            });
          }
        } catch (_) {
          // Thumbnail generation failed for this draft — skip.
        }
      }
      // Text-only and audio-only drafts are handled inline in _buildDraftThumbnail.
    }
  }

  void _applyFilterSort() {
    var list = _allDrafts.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    switch (_sortOrder) {
      case _DraftSort.newestFirst:
        list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
        break;
      case _DraftSort.oldestFirst:
        list.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
        break;
      case _DraftSort.nameAZ:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _DraftSort.nameZA:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case _DraftSort.longestFirst:
        list.sort((a, b) => b.totalDuration.compareTo(a.totalDuration));
        break;
      case _DraftSort.shortestFirst:
        list.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
        break;
    }
    _drafts = list;
  }

  Future<void> _openEditor({DraftProject? draft}) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(draft: draft),
      ),
    );
    // Refresh drafts whenever we return from the editor.
    if (mounted) _loadDrafts();
  }

  Future<void> _loadRecentVideos() async {
    final status = await PhotoManager.requestPermissionExtend();
    if (!status.isAuth && status != PermissionState.limited) {
      if (mounted) setState(() => _recentLoaded = true);
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (albums.isEmpty) {
      if (mounted) setState(() => _recentLoaded = true);
      return;
    }
    final assets = await albums.first.getAssetListRange(start: 0, end: 6);
    if (mounted) {
      setState(() {
        _recentVideos = assets;
        _recentLoaded = true;
      });
    }
  }

  Future<void> _openMediaPickerAndEdit() async {
    final picks = await Navigator.push<List<PickedMediaFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const MediaPickerScreen(initialTab: 0),
        fullscreenDialog: true,
      ),
    );
    if (picks == null || picks.isEmpty || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(initialMedia: picks),
      ),
    );
    if (mounted) _loadDrafts();
  }

  Future<void> _openEditorWithAsset(AssetEntity asset) async {
    final file = await asset.originFile;
    if (file == null || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(
          initialMedia: [
            PickedMediaFile(
              path: file.path,
              isVideo: true,
              duration: asset.videoDuration,
            ),
          ],
        ),
      ),
    );
    if (mounted) _loadDrafts();
  }

  Future<void> _showDraftOptions(DraftProject draft) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                draft.title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white70),
              title: const Text('Rename',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _renameDraft(draft);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Color(0xFFFF4D4D)),
              title: const Text('Delete',
                  style: TextStyle(color: Color(0xFFFF4D4D))),
              onTap: () {
                Navigator.pop(ctx);
                _deleteDraft(draft);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDraft(DraftProject draft) async {
    final controller = TextEditingController(text: draft.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Rename draft',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFF5A623)),
            ),
          ),
          onSubmitted: (v) {
            final trimmed = v.trim();
            if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
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
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            child: const Text('Rename',
                style: TextStyle(color: Color(0xFFF5A623))),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (newTitle == null || newTitle == draft.title) return;
    final updated = draft.copyWith(title: newTitle, modifiedAt: DateTime.now());
    await DraftManager.instance.save(updated);
    if (!mounted) return;
    setState(() {
      final idx = _allDrafts.indexWhere((d) => d.id == draft.id);
      if (idx != -1) _allDrafts[idx] = updated;
      _applyFilterSort();
    });
  }

  Future<void> _deleteDraft(DraftProject draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Delete draft?',
            style: TextStyle(color: Colors.white)),
        content: Text('"${draft.title}" will be permanently deleted.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DraftManager.instance.delete(draft.id);
      _loadDrafts();
    }
  }

  // ── Collage draft helpers ──────────────────────────────────────────────────

  Future<void> _openCollageDraft(CollageDraft draft) async {
    // Find the layout def by id — check both rectangular and artistic lists.
    CollageLayoutDef? layout;
    for (final l in [...kCollageLayouts, ...kArtisticLayouts]) {
      if (l.id == draft.layoutId) { layout = l; break; }
    }
    if (layout == null || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CollageEditorScreen(layout: layout!, draft: draft),
      ),
    );
    if (mounted) _loadCollageDrafts();
  }

  Future<void> _deleteCollageDraft(CollageDraft draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Delete collage?',
            style: TextStyle(color: Colors.white)),
        content: Text('"${draft.title}" will be permanently deleted.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await CollageDraftManager.instance.delete(draft.id);
      if (mounted) _loadCollageDrafts();
    }
  }

  Future<void> _renameCollageDraft(CollageDraft draft) async {
    final controller = TextEditingController(text: draft.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Rename collage',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
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
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Rename',
                style: TextStyle(color: Color(0xFF7B35C8))),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (newTitle == null || newTitle == draft.title) return;
    final updated = draft.copyWith(title: newTitle, modifiedAt: DateTime.now());
    await CollageDraftManager.instance.save(updated);
    if (!mounted) return;
    setState(() {
      final idx = _collageDrafts.indexWhere((d) => d.id == draft.id);
      if (idx != -1) _collageDrafts[idx] = updated;
    });
  }

  Future<void> _showCollageDraftOptions(CollageDraft draft) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                draft.title,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white70),
              title: const Text('Rename',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _renameCollageDraft(draft);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Color(0xFFFF4D4D)),
              title: const Text('Delete',
                  style: TextStyle(color: Color(0xFFFF4D4D))),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCollageDraft(draft);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.7),
          builder: (_) => const ExitConfirmationDialog(),
        );
        if (shouldExit == true && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF000016),
      // Banner pinned at the bottom — outside scroll area to prevent
      // accidental clicks while the user is scrolling through content.
      bottomNavigationBar: const SafeArea(
        top: false,
        child: BannerAdWidget(),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDrafts,
          color: const Color(0xFFF5A623),
          backgroundColor: const Color(0xFF2A2A2A),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar()),
              SliverToBoxAdapter(child: _buildNewProjectButton()),
              if (!_recentLoaded)
                const SliverToBoxAdapter(child: _RecentShimmer())
              else if (_recentVideos.isNotEmpty)
                SliverToBoxAdapter(child: _buildRecentMediaSection()),
              SliverToBoxAdapter(child: _buildToolGrid()),
              SliverToBoxAdapter(child: _buildDraftsHeader()),
              if (_loadingDrafts)
                const SliverToBoxAdapter(child: _DraftsShimmer())
              else if (_drafts.isEmpty)
                const SliverToBoxAdapter(child: _EmptyDrafts())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _buildDraftsGrid(),
                ),
              // ── Collage Projects ──────────────────────────────────────────
              SliverToBoxAdapter(child: _buildCollageDraftsHeader()),
              if (_loadingCollageDrafts)
                const SliverToBoxAdapter(child: _DraftsShimmer())
              else if (_collageDrafts.isEmpty)
                const SliverToBoxAdapter(child: _EmptyCollageDrafts())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _buildCollageDraftsGrid(),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                children: [
                  TextSpan(text: 'Video Editor'),
                  TextSpan(
                    text: ' & ',
                    style: TextStyle(color: Color(0xFFFF6B35)),
                  ),
                  TextSpan(text: 'Collage Maker'),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 22),
            onPressed: () => Share.share(
              'https://play.google.com/store/apps/details?id=com.video.rd.editor',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewProjectButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: () => _openEditor(),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF5A623), Color(0xFFE8434A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              const Text(
                'New Project',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              const Text(
                'Recent Videos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.play_circle_outline,
                  color: Colors.white38, size: 16),
              const Spacer(),
              GestureDetector(
                onTap: _openMediaPickerAndEdit,
                child: const Text(
                  'See all',
                  style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentVideos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final asset = _recentVideos[i];
              return GestureDetector(
                onTap: () => _openEditorWithAsset(asset),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 96,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _RecentThumb(asset: asset),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          right: 4,
                          child: Row(
                            children: [
                              const Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  _formatDuration(asset.videoDuration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    shadows: [
                                      Shadow(
                                          blurRadius: 4,
                                          color: Colors.black87)
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  Widget _buildToolGrid() {
    final tools = [
      _ToolItem(
          icon: Icons.video_library_outlined,
          label: 'Video Editor',
          onTap: () => _openEditor()),
      _ToolItem(
          icon: Icons.grid_view_rounded,
          label: 'Video Collage',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CollageLayoutPicker()))),
      _ToolItem(
          icon: Icons.mic_outlined,
          label: 'Recorder',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RecorderScreen()))),
      _ToolItem(
          icon: Icons.camera_alt_outlined,
          label: 'Camera',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CameraScreen()),
            );
            if (mounted) _loadDrafts();
          }),
      _ToolItem(
          icon: Icons.grid_view_outlined,
          label: 'Explore',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ExploreScreen()))),
      _ToolItem(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tools.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.15,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (_, i) => _buildToolTile(tools[i]),
      ),
    );
  }

  Widget _buildToolTile(_ToolItem tool) {
    return GestureDetector(
      onTap: tool.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5A1E8C), Color(0xFF101330)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Stack(
            children: [
              // Diagonal line texture
              Positioned.fill(
                child: CustomPaint(painter: _DiagonalLinePainter()),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tool.icon, color: Colors.white, size: 30),
                    const SizedBox(height: 6),
                    Text(tool.label,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraftsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Text(
            'Recent Projects',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.info_outline, color: Colors.white38, size: 16),
          if (_loadingDrafts) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 24, height: 16, child: _ShimmerBox()),
            ),
          ] else if (_drafts.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF5A623),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_drafts.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
          const Spacer(),
          if (_loadingDrafts)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 40, height: 16, child: _ShimmerBox()),
            )
          else ...[
            if (_drafts.isNotEmpty) ...[
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AllProjectsScreen(),
                    ),
                  );
                  if (mounted) _loadDrafts();
                },
                child: const Text(
                  'See all',
                  style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            GestureDetector(
              onTap: () => _openEditor(),
              child: const Text(
                'New',
                style: TextStyle(
                  color: Color(0xFFF5A623),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  SliverGrid _buildDraftsGrid() {
    final count = _drafts.length.clamp(0, 6);
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (_, i) => _buildDraftTile(_drafts[i]),
        childCount: count,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
    );
  }

  Widget _buildDraftTile(DraftProject draft) {
    final dur = draft.totalDuration;
    final secs = dur.inSeconds;
    final ms = (dur.inMilliseconds % 1000) ~/ 100;
    final durationLabel =
        '${(secs ~/ 60).toString().padLeft(1, '0')}:${(secs % 60).toString().padLeft(2, '0')}.$ms';

    return GestureDetector(
      onTap: () => _openEditor(draft: draft),
      onLongPress: () => _showDraftOptions(draft),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail or placeholder
            _buildDraftThumbnail(draft),
            // Label overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      draft.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatDate(draft.modifiedAt),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 9),
                    ),
                    Row(
                      children: [
                        Text(
                          durationLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showDraftOptions(draft),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_horiz,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftThumbnail(DraftProject draft) {
    if (draft.thumbnailPath != null) {
      final file = File(draft.thumbnailPath!);
      if (file.existsSync() && file.lengthSync() > 0) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    final hue = (draft.id.hashCode % 360).abs().toDouble();
    final gradientBg = BoxDecoration(
      gradient: LinearGradient(
        colors: [
          HSLColor.fromAHSL(1, hue, 0.6, 0.45).toColor(),
          HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.30).toColor(),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );

    // Text-only draft: show text content over gradient.
    final textTrack = draft.tracks
        .where((t) => t.trackType == TrackType.text && t.textContent.isNotEmpty)
        .firstOrNull;
    final hasMedia = draft.tracks.any(
      (t) =>
          (t.trackType == TrackType.video || t.trackType == TrackType.image) &&
          _pathAccessible(t.filePath),
    );
    if (!hasMedia && textTrack != null) {
      return Container(
        decoration: gradientBg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          textTrack.textContent,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
      );
    }

    // Audio-only draft: show a music note icon over gradient.
    final hasAudio = draft.tracks.any(
      (t) => t.trackType == TrackType.audio && _pathAccessible(t.filePath),
    );
    if (!hasMedia && hasAudio) {
      return Container(
        decoration: gradientBg,
        alignment: Alignment.center,
        child: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 40),
      );
    }

    // Fallback: colored gradient based on draft id.
    return Container(decoration: gradientBg);
  }

  // ── Collage drafts section ─────────────────────────────────────────────────

  Widget _buildCollageDraftsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          const Text(
            'Collage Projects',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.grid_view_rounded, color: Colors.white38, size: 16),
          if (_loadingCollageDrafts) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 24, height: 16, child: _ShimmerBox()),
            ),
          ] else if (_collageDrafts.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7B35C8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_collageDrafts.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
          const Spacer(),
          if (!_loadingCollageDrafts && _collageDrafts.isNotEmpty) ...[
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllCollageProjectsScreen(),
                  ),
                );
                if (mounted) _loadCollageDrafts();
              },
              child: const Text(
                'See all',
                style: TextStyle(
                  color: Color(0xFF7B35C8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollageLayoutPicker()),
            ),
            child: const Text(
              'New',
              style: TextStyle(
                color: Color(0xFF7B35C8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverGrid _buildCollageDraftsGrid() {
    final count = _collageDrafts.length.clamp(0, 6);
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (_, i) => _buildCollageDraftTile(_collageDrafts[i]),
        childCount: count,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
    );
  }

  Widget _buildCollageDraftTile(CollageDraft draft) {
    final ago = _formatDate(draft.modifiedAt);

    return GestureDetector(
      onTap: () => _openCollageDraft(draft),
      onLongPress: () => _showCollageDraftOptions(draft),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCollageDraftThumbnail(draft),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      draft.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          ago,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 9),
                        ),
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCollageDraftOptions(draft),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_horiz,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollageDraftThumbnail(CollageDraft draft) {
    if (draft.thumbnailPath != null) {
      final file = File(draft.thumbnailPath!);
      if (file.existsSync() && file.lengthSync() > 0) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    // Look for a media file in the cells to show as thumbnail.
    for (final cell in draft.cells) {
      if (cell.filePath == null) continue;
      final path = cell.filePath!;
      if (path.startsWith('content://')) continue;
      final f = File(path);
      if (!f.existsSync()) continue;
      if (!cell.isVideo) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }

    // Fallback gradient keyed to the layout id.
    final hue = (draft.layoutId.hashCode % 360).abs().toDouble();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue, 0.6, 0.45).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.30).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.grid_view_rounded, color: Colors.white38, size: 32),
      ),
    );
  }
}

// ── Shimmer placeholder while recent videos load ─────────────────────────────

class _RecentShimmer extends StatelessWidget {
  const _RecentShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.play_circle_outline,
                  color: Colors.white38, size: 16),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 96,
                child: _ShimmerBox(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ── Shimmer placeholder while drafts load ────────────────────────────────────

class _DraftsShimmer extends StatelessWidget {
  const _DraftsShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.72,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemBuilder: (_, __) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _ShimmerBox(),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
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
    _anim = Tween<double>(begin: -1, end: 2).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyDrafts extends StatelessWidget {
  const _EmptyDrafts();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined,
              color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'No drafts yet',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Tap "New Project" to start editing',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyCollageDrafts extends StatelessWidget {
  const _EmptyCollageDrafts();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.grid_view_rounded, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'No collage projects yet',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Tap "Video Collage" to create one',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ToolItem(
      {required this.icon, required this.label, this.onTap});
}

// ── Sort / Filter bottom sheet ────────────────────────────────────────────────

class _SortFilterSheet extends StatefulWidget {
  final _DraftSort currentSort;
  final String searchQuery;
  final void Function(_DraftSort sort, String query) onApply;

  const _SortFilterSheet({
    required this.currentSort,
    required this.searchQuery,
    required this.onApply,
  });

  @override
  State<_SortFilterSheet> createState() => _SortFilterSheetState();
}

class _SortFilterSheetState extends State<_SortFilterSheet> {
  late _DraftSort _selected;
  late TextEditingController _searchCtrl;

  static const _options = [
    (_DraftSort.newestFirst, Icons.access_time, 'Newest first'),
    (_DraftSort.oldestFirst, Icons.history, 'Oldest first'),
    (_DraftSort.nameAZ, Icons.sort_by_alpha, 'Name A→Z'),
    (_DraftSort.nameZA, Icons.sort_by_alpha, 'Name Z→A'),
    (_DraftSort.longestFirst, Icons.timer, 'Longest first'),
    (_DraftSort.shortestFirst, Icons.timer_off, 'Shortest first'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentSort;
    _searchCtrl = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sort & Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by name…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setState(() => _searchCtrl.clear()),
                          child: const Icon(Icons.close, color: Colors.white38),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF3A3A3A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            // Sort options
            for (final (sort, icon, label) in _options)
              ListTile(
                leading: Icon(
                  icon,
                  color: _selected == sort
                      ? const Color(0xFFF5A623)
                      : Colors.white54,
                  size: 20,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: _selected == sort ? const Color(0xFFF5A623) : Colors.white,
                    fontWeight: _selected == sort ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: _selected == sort
                    ? const Icon(Icons.check, color: Color(0xFFF5A623), size: 18)
                    : null,
                onTap: () => setState(() => _selected = sort),
              ),
            // Apply button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => widget.onApply(_selected, _searchCtrl.text.trim()),
                  child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Tool tile diagonal texture ────────────────────────────────────────────────

class _DiagonalLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1.0
      ..isAntiAlias = false;
    const spacing = 10.0;
    // Draw diagonal lines from top-left to bottom-right at 45°
    for (double offset = -size.height; offset < size.width + size.height; offset += spacing) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagonalLinePainter oldDelegate) => false;
}

// ── Recent video thumbnail ────────────────────────────────────────────────────

class _RecentThumb extends StatefulWidget {
  final AssetEntity asset;
  const _RecentThumb({required this.asset});

  @override
  State<_RecentThumb> createState() => _RecentThumbState();
}

class _RecentThumbState extends State<_RecentThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(144, 192),
      quality: 80,
    );
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(color: const Color(0xFF2A2A2A));
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}
