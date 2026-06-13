import 'package:flutter/material.dart';
import 'collage_models.dart';
import 'collage_editor_screen.dart';
import '../media_picker/media_picker_screen.dart';

class CollageLayoutPicker extends StatefulWidget {
  /// Media carried over from a previous layout. When non-empty the gallery
  /// picker is skipped and these files fill the chosen layout's cells.
  final List<PickedMediaFile>? carriedMedia;

  /// Overlays carried over from a previous layout (serialized).
  final List<Map<String, dynamic>>? carriedTextOverlays;
  final List<Map<String, dynamic>>? carriedStickerOverlays;
  final List<Map<String, dynamic>>? carriedGifOverlays;

  const CollageLayoutPicker({
    super.key,
    this.carriedMedia,
    this.carriedTextOverlays,
    this.carriedStickerOverlays,
    this.carriedGifOverlays,
  });

  @override
  State<CollageLayoutPicker> createState() => _CollageLayoutPickerState();
}

class _CollageLayoutPickerState extends State<CollageLayoutPicker> {
  int _filterCount = 0; // 0 = All
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  int? _hoveredIndex;
  OverlayEntry? _tooltip;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _removeTooltip();
    super.dispose();
  }

  List<CollageLayoutDef> get _filtered {
    if (_filterCount == 0) return kCollageLayouts;
    if (_filterCount == 6) {
      return kCollageLayouts.where((l) => l.cellCount >= 6).toList();
    }
    return kCollageLayouts.where((l) => l.cellCount == _filterCount).toList();
  }

  List<CollageLayoutDef> get _artisticFiltered {
    if (_filterCount == 0) return kArtisticLayouts;
    if (_filterCount == 6) {
      return kArtisticLayouts.where((l) => l.cellCount >= 6).toList();
    }
    return kArtisticLayouts.where((l) => l.cellCount == _filterCount).toList();
  }

  // Combined list for page 2: artistic layouts first, then single-clip
  // shape layouts (1 cell, so they only match the "All" filter).
  List<CollageLayoutDef> get _page2Layouts => [
        ..._artisticFiltered,
        if (_filterCount == 0) ...kShapeLayouts,
      ];

  void _removeTooltip() {
    _tooltip?.remove();
    _tooltip = null;
  }

  void _showTooltip(BuildContext cellContext, CollageLayoutDef layout, int idx) {
    _removeTooltip();
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);

    _tooltip = OverlayEntry(
      builder: (_) => Positioned(
        left: 12,
        top: pos.dy + box.size.height + 6,
        width: MediaQuery.of(context).size.width - 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Choose this ${layout.cellCount}-cell layout',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_tooltip!);
    setState(() => _hoveredIndex = idx);
    Future.delayed(const Duration(seconds: 2), _removeTooltip);
  }

  Future<void> _selectLayout(CollageLayoutDef layout) async {
    _removeTooltip();

    // Coming from an existing collage: carry the media into the new layout's
    // cells instead of re-opening the gallery picker.
    final carried = widget.carriedMedia;
    if (carried != null && carried.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollageEditorScreen(
            layout: layout,
            initialPicks: carried,
            carriedTextOverlays: widget.carriedTextOverlays,
            carriedStickerOverlays: widget.carriedStickerOverlays,
            carriedGifOverlays: widget.carriedGifOverlays,
          ),
        ),
      );
      return;
    }

    // Open the media picker limited to the number of cells in this layout.
    final picks = await Navigator.push<List<PickedMediaFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(
          initialTab: 2, // ALL (videos + photos)
          maxAssets: layout.cellCount,
        ),
        fullscreenDialog: true,
      ),
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CollageEditorScreen(
          layout: layout,
          initialPicks: picks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildFilterChips(),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (p) => setState(() => _currentPage = p),
                children: [
                  _buildGridPage(_filtered, isShapes: false),
                  _buildGridPage(_page2Layouts, isShapes: true),
                ],
              ),
            ),
            _buildPageDots(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          const Icon(Icons.arrow_back_ios,
              color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          const Text('Video Collage',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const labels = ['All', '2', '3', '4', '5', '6+'];
    const values = [0, 2, 3, 4, 5, 6];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(labels.length, (i) {
            final active = _filterCount == values[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filterCount = values[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFB8860B)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white54,
                      fontWeight: active
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildGridPage(List<CollageLayoutDef> layouts, {required bool isShapes}) {
    return GestureDetector(
      onTap: _removeTooltip,
      child: GridView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: layouts.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemBuilder: (ctx, i) {
          final layout = layouts[i];
          final isSelected = _hoveredIndex == i && !isShapes;
          return GestureDetector(
            onTap: () => _selectLayout(layout),
            onLongPress: () => _showTooltip(ctx, layout, i),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2D2D2D)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(6),
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: layout.isShape
                  ? _ShapePreview(layout: layout)
                  : layout.isArtistic
                      ? _ArtisticPreview(layout: layout)
                      : _LayoutPreview(layout: layout),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == _currentPage ? 24 : 8,
          height: 4,
          decoration: BoxDecoration(
            color: i == _currentPage
                ? const Color(0xFFB8860B)
                : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ── Layout preview painter ────────────────────────────────────────────────────

class _LayoutPreview extends StatelessWidget {
  final CollageLayoutDef layout;
  const _LayoutPreview({required this.layout});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LayoutPainter(layout.cells),
    );
  }
}

class _LayoutPainter extends CustomPainter {
  final List<Rect> cells;
  _LayoutPainter(this.cells);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF3A3A3A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final cellPaint = Paint()..color = const Color(0xFF1A1A1A);
    const gap = 1.5;

    for (final cell in cells) {
      final r = Rect.fromLTRB(
        cell.left * size.width + gap,
        cell.top * size.height + gap,
        cell.right * size.width - gap,
        cell.bottom * size.height - gap,
      );
      canvas.drawRect(r, cellPaint);
    }
  }

  @override
  bool shouldRepaint(_LayoutPainter old) => old.cells != cells;
}

// ── Shape preview ─────────────────────────────────────────────────────────────

class _ShapePreview extends StatelessWidget {
  final CollageLayoutDef layout;
  const _ShapePreview({required this.layout});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ShapePainter(layout.id));
  }
}

class _ShapePainter extends CustomPainter {
  final String id;
  _ShapePainter(this.id);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF3A3A3A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final fill = Paint()..color = const Color(0xFF1A1A1A);
    final path = shapePathForId(id, size);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.id != id;
}

// ── Artistic preview ──────────────────────────────────────────────────────────

class _ArtisticPreview extends StatelessWidget {
  final CollageLayoutDef layout;
  const _ArtisticPreview({required this.layout});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArtisticPainter(layout.id, layout.cellCount),
    );
  }
}

class _ArtisticPainter extends CustomPainter {
  final String layoutId;
  final int cellCount;

  _ArtisticPainter(this.layoutId, this.cellCount);

  static const _cellColors = [
    Color(0xFF1A1A1A),
    Color(0xFF2E2E2E),
    Color(0xFF222222),
    Color(0xFF333333),
    Color(0xFF1E1E1E),
    Color(0xFF2A2A2A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF3A3A3A),
    );

    final builders = kArtisticCellPaths[layoutId];
    if (builders == null) return;

    final strokePaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < builders.length; i++) {
      final path = builders[i](size);
      final fillPaint = Paint()
        ..color = _cellColors[i % _cellColors.length];
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_ArtisticPainter old) =>
      old.layoutId != layoutId || old.cellCount != cellCount;
}
