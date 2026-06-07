part of 'collage_editor_screen.dart';

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
