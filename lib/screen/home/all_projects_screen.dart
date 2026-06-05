import 'dart:io';

import 'package:flutter/material.dart';
import '../../data/draft_manager.dart';
import '../video_editor/video_editor_model.dart' show TrackType;
import '../video_editor/video_editor_screen.dart';

enum _Sort { newestFirst, oldestFirst, nameAZ, nameZA, longestFirst, shortestFirst }

class AllProjectsScreen extends StatefulWidget {
  const AllProjectsScreen({super.key});

  @override
  State<AllProjectsScreen> createState() => _AllProjectsScreenState();
}

class _AllProjectsScreenState extends State<AllProjectsScreen> {
  List<DraftProject> _allDrafts = [];
  List<DraftProject> _drafts = [];
  bool _loading = true;
  _Sort _sortOrder = _Sort.newestFirst;
  String _searchQuery = '';

  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    final drafts = await DraftManager.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _allDrafts = drafts;
      _loading = false;
      _applyFilterSort();
    });
  }

  void _applyFilterSort() {
    var list = _allDrafts.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    switch (_sortOrder) {
      case _Sort.newestFirst:
        list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
        break;
      case _Sort.oldestFirst:
        list.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
        break;
      case _Sort.nameAZ:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _Sort.nameZA:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case _Sort.longestFirst:
        list.sort((a, b) => b.totalDuration.compareTo(a.totalDuration));
        break;
      case _Sort.shortestFirst:
        list.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
        break;
    }
    _drafts = list;
  }

  Future<void> _renameDraft(DraftProject draft) async {
    final controller = TextEditingController(text: draft.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            child: const Text('Rename', style: TextStyle(color: Color(0xFFF5A623))),
          ),
        ],
      ),
    );
    controller.dispose();
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
        title: const Text('Delete draft?', style: TextStyle(color: Colors.white)),
        content: Text('"${draft.title}" will be permanently deleted.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DraftManager.instance.delete(draft.id);
      if (!mounted) return;
      setState(() {
        _allDrafts.removeWhere((d) => d.id == draft.id);
        _selected.remove(draft.id);
        _applyFilterSort();
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Delete selected?', style: TextStyle(color: Colors.white)),
        content: Text(
          '$count project${count > 1 ? 's' : ''} will be permanently deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ids = Set<String>.from(_selected);
      for (final id in ids) {
        await DraftManager.instance.delete(id);
      }
      if (!mounted) return;
      setState(() {
        _allDrafts.removeWhere((d) => ids.contains(d.id));
        _selected.clear();
        _selectMode = false;
        _applyFilterSort();
      });
    }
  }

  Future<void> _deleteAll() async {
    if (_allDrafts.isEmpty) return;
    final count = _allDrafts.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Delete all projects?', style: TextStyle(color: Colors.white)),
        content: Text(
          'All $count project${count > 1 ? 's' : ''} will be permanently deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all', style: TextStyle(color: Color(0xFFFF4D4D))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final all = List<DraftProject>.from(_allDrafts);
      for (final d in all) {
        await DraftManager.instance.delete(d.id);
      }
      if (!mounted) return;
      setState(() {
        _allDrafts.clear();
        _selected.clear();
        _selectMode = false;
        _applyFilterSort();
      });
    }
  }

  void _showSortFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SortSheet(
        currentSort: _sortOrder,
        searchQuery: _searchQuery,
        onApply: (sort, query) {
          setState(() {
            _sortOrder = sort;
            _searchQuery = query;
            _applyFilterSort();
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  bool _pathAccessible(String path) {
    if (path.startsWith('content://')) return true;
    return File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = (_sortOrder != _Sort.newestFirst || _searchQuery.isNotEmpty);
    return Scaffold(
      backgroundColor: const Color(0xFF000016),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000016),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const Text(
              'All Projects',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!_loading && _allDrafts.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A623),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_allDrafts.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_loading && _drafts.isNotEmpty)
            IconButton(
              tooltip: _selectMode ? 'Cancel' : 'Select',
              icon: Icon(
                _selectMode ? Icons.close : Icons.checklist_outlined,
                color: _selectMode ? const Color(0xFFF5A623) : Colors.white70,
              ),
              onPressed: () => setState(() {
                _selectMode = !_selectMode;
                _selected.clear();
              }),
            ),
          IconButton(
            tooltip: 'Sort & Filter',
            icon: Icon(
              Icons.sort,
              color: hasActive ? const Color(0xFFF5A623) : Colors.white70,
            ),
            onPressed: _showSortFilterSheet,
          ),
          PopupMenuButton<String>(
            color: const Color(0xFF2A2A2A),
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (v) {
              if (v == 'delete_all') _deleteAll();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined,
                        color: Color(0xFFFF4D4D), size: 20),
                    SizedBox(width: 10),
                    Text('Delete all',
                        style: TextStyle(color: Color(0xFFFF4D4D))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5A623)))
          : _drafts.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _drafts.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: Color(0xFF1E1E1E),
                          height: 1,
                          indent: 96,
                          endIndent: 16,
                        ),
                        itemBuilder: (_, i) => _buildItem(_drafts[i]),
                      ),
                    ),
                    if (_selectMode) _buildSelectBar(),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined,
              color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No results for "$_searchQuery"'
                : 'No projects yet',
            style: const TextStyle(color: Colors.white38, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(DraftProject draft) {
    final dur = draft.totalDuration;
    final secs = dur.inSeconds;
    final ms = (dur.inMilliseconds % 1000) ~/ 100;
    final durationLabel =
        '${(secs ~/ 60).toString().padLeft(1, '0')}:${(secs % 60).toString().padLeft(2, '0')}.$ms';
    final isSelected = _selected.contains(draft.id);

    return InkWell(
      onTap: _selectMode
          ? () => setState(() {
                if (isSelected) {
                  _selected.remove(draft.id);
                } else {
                  _selected.add(draft.id);
                }
              })
          : () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoEditorScreen(draft: draft),
                ),
              );
              if (mounted) _loadDrafts();
            },
      onLongPress: () {
        if (!_selectMode) {
          setState(() {
            _selectMode = true;
            _selected.add(draft.id);
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (_selectMode) ...[
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => setState(() {
                    if (isSelected) {
                      _selected.remove(draft.id);
                    } else {
                      _selected.add(draft.id);
                    }
                  }),
                  activeColor: const Color(0xFFF5A623),
                  side: const BorderSide(color: Colors.white38),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 48,
                child: _buildThumbnail(draft),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: Colors.white38, size: 12),
                      const SizedBox(width: 3),
                      Text(durationLabel,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      const SizedBox(width: 10),
                      const Icon(Icons.calendar_today_outlined,
                          color: Colors.white38, size: 12),
                      const SizedBox(width: 3),
                      Text(_formatDate(draft.modifiedAt),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            // Per-item actions
            if (!_selectMode)
              PopupMenuButton<String>(
                color: const Color(0xFF2A2A2A),
                icon: const Icon(Icons.more_vert,
                    color: Colors.white38, size: 20),
                onSelected: (v) {
                  if (v == 'rename') _renameDraft(draft);
                  if (v == 'delete') _deleteDraft(draft);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline,
                            color: Colors.white70, size: 18),
                        SizedBox(width: 10),
                        Text('Rename',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: Color(0xFFFF4D4D), size: 18),
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(color: Color(0xFFFF4D4D))),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectBar() {
    final allSelected = _selected.length == _drafts.length && _drafts.isNotEmpty;
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              _selected.isEmpty
                  ? 'Select items'
                  : '${_selected.length} selected',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (allSelected) {
                  _selected.clear();
                } else {
                  _selected.addAll(_drafts.map((d) => d.id));
                }
              }),
              child: Text(
                allSelected ? 'Deselect all' : 'Select all',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty
                    ? Colors.white12
                    : const Color(0xFFFF4D4D),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(DraftProject draft) {
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

    final textTrack = draft.tracks
        .where(
            (t) => t.trackType == TrackType.text && t.textContent.isNotEmpty)
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
        padding: const EdgeInsets.all(4),
        child: Text(
          textTrack.textContent,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final hasAudio = draft.tracks.any(
      (t) => t.trackType == TrackType.audio && _pathAccessible(t.filePath),
    );
    if (!hasMedia && hasAudio) {
      return Container(
        decoration: gradientBg,
        alignment: Alignment.center,
        child:
            const Icon(Icons.music_note_rounded, color: Colors.white70, size: 22),
      );
    }

    return Container(decoration: gradientBg);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}.${dt.month}.${dt.year}';
  }
}

// ── Sort / Filter sheet ───────────────────────────────────────────────────────

class _SortSheet extends StatefulWidget {
  final _Sort currentSort;
  final String searchQuery;
  final void Function(_Sort sort, String query) onApply;

  const _SortSheet({
    required this.currentSort,
    required this.searchQuery,
    required this.onApply,
  });

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late _Sort _selected;
  late TextEditingController _searchCtrl;

  static const _options = [
    (_Sort.newestFirst, Icons.access_time, 'Newest first'),
    (_Sort.oldestFirst, Icons.history, 'Oldest first'),
    (_Sort.nameAZ, Icons.sort_by_alpha, 'Name A→Z'),
    (_Sort.nameZA, Icons.sort_by_alpha, 'Name Z→A'),
    (_Sort.longestFirst, Icons.timer, 'Longest first'),
    (_Sort.shortestFirst, Icons.timer_off, 'Shortest first'),
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by name…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white38),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () =>
                                setState(() => _searchCtrl.clear()),
                            child: const Icon(Icons.close,
                                color: Colors.white38),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF3A3A3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
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
                      color: _selected == sort
                          ? const Color(0xFFF5A623)
                          : Colors.white,
                      fontWeight: _selected == sort
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: _selected == sort
                      ? const Icon(Icons.check,
                          color: Color(0xFFF5A623), size: 18)
                      : null,
                  onTap: () => setState(() => _selected = sort),
                ),
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
                    onPressed: () => widget.onApply(
                        _selected, _searchCtrl.text.trim()),
                    child: const Text('Apply',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
