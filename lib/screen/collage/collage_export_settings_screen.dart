import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'collage_models.dart';
import 'collage_preview_screen.dart';
import '../../service/app_settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Data helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ResOption {
  final String label;
  final String sublabel;
  final int baseW; // target width; height = (baseW * aspectMultiplier).round()
  const _ResOption(this.label, this.sublabel, this.baseW);
}

class _FmtOption {
  final String label;
  final String ext;
  final bool faststart;
  const _FmtOption(this.label, this.ext, {this.faststart = false});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class CollageExportSettingsScreen extends StatefulWidget {
  // ── Collage data forwarded to CollagePreviewScreen ────────────────────────
  final List<CollageCellData> cells;
  final List<Rect> cellRects;
  final Map<int, VideoPlayerController> videoControllers;
  final List<bool>? cellRepeating;
  final Color bgColor;
  final double borderGap;
  final String? audioPath;
  final Duration audioTrimStart;
  final Duration audioTrimEnd;
  final double audioVolume;
  final List<String?>? cellFilterVf;
  final List<ColorFilter?>? cellColorFilters;
  final List<double>? cellSpeeds;
  final List<double>? cellVolumes;
  final List<int>? cellRotSteps;
  final List<bool>? cellFlipH;
  final List<bool>? cellFlipV;
  final List<double>? cellScales;
  final List<double>? cellAngles;
  final List<double>? cellNormOffsetX;
  final List<double>? cellNormOffsetY;
  final String? draftId;

  // ── Artistic / shape layout clipping ──────────────────────────────────────
  final String? layoutId;
  final bool isArtistic;
  final List<double>? artOffsets;

  // ── Needed for dimension calc + size estimate ─────────────────────────────
  /// height = baseW * aspectMultiplier  (rounded to nearest even number)
  final double aspectMultiplier;

  /// Best-effort estimate of total output duration in seconds (for size badge).
  final double estimatedTotalSecs;

  const CollageExportSettingsScreen({
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
    this.cellFilterVf,
    this.cellColorFilters,
    this.cellSpeeds,
    this.cellVolumes,
    this.cellRotSteps,
    this.cellFlipH,
    this.cellFlipV,
    this.cellScales,
    this.cellAngles,
    this.cellNormOffsetX,
    this.cellNormOffsetY,
    this.draftId,
    this.layoutId,
    this.isArtistic = false,
    this.artOffsets,
    required this.aspectMultiplier,
    required this.estimatedTotalSecs,
  });

  @override
  State<CollageExportSettingsScreen> createState() =>
      _CollageExportSettingsScreenState();
}

class _CollageExportSettingsScreenState
    extends State<CollageExportSettingsScreen> {
  // ── Options ────────────────────────────────────────────────────────────────
  static const _resolutions = [
    _ResOption('480p',  'SD',      480),
    _ResOption('720p',  'HD',      720),
    _ResOption('1080p', 'Full HD', 1080),
    _ResOption('2K',    '2K QHD',  1440),
    _ResOption('4K',    '4K UHD',  2160),
  ];

  static const _frameRates = [24, 25, 30, 50, 60];

  // (name, description, crf)
  static const _qualities = [
    ('Recommended', 'Balanced size &\nquality',  23),
    ('High',        'Crisp detail,\nlarger file', 18),
    ('Ultra',       'Maximum\nquality',           14),
  ];

  static const _formats = [
    _FmtOption('MP4', 'mp4', faststart: true),
    _FmtOption('MOV', 'mov', faststart: true),
    _FmtOption('MKV', 'mkv'),
  ];

  // ── Resolution hints ───────────────────────────────────────────────────────
  static const _resolutionHints = [
    'Standard definition',
    'HD ready',
    'Full HD',
    '2K · Quad HD',
    '4K · Ultra HD',
  ];

  // ── Frame-rate hints ───────────────────────────────────────────────────────
  static const _fpsHints = [
    'Cinematic',
    'PAL standard',
    'NTSC standard',
    'PAL HFR',
    'NTSC HFR',
  ];

  // ── Selected state ─────────────────────────────────────────────────────────
  late int _selResolution;
  late int _selFrameRate;
  int _selQuality = 0;
  int _selFormat  = 0;

  // ── Design constants ───────────────────────────────────────────────────────
  static const _red          = Color(0xFFE53935);
  static const _chipUnselect = Color(0xFF2B2B2B);
  static const _sectionLabel = TextStyle(
    color: Color(0xFF888888),
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final _scrollCtrl  = ScrollController();
  bool _showScrollHint = false;

  // ── Init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final s = AppSettings.instance;
    _selResolution = s.defaultResolutionIndex;
    _selFrameRate  = s.defaultFpsIndex;
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 8;
    if (atBottom != !_showScrollHint) {
      setState(() => _showScrollHint = !atBottom);
    }
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Calculates outW / outH for the selected resolution + collage aspect ratio.
  ///
  /// The resolution label ("480p", "720p", …) always refers to the *shorter*
  /// side so that landscape and portrait videos share the same quality tier:
  ///   - portrait / square  (aspectMultiplier ≥ 1): base = width,  height = base × multiplier
  ///   - landscape          (aspectMultiplier < 1): base = height, width  = base / multiplier
  (int outW, int outH) get _outDims {
    final base = _resolutions[_selResolution].baseW;
    final am   = widget.aspectMultiplier;
    if (am >= 1.0) {
      // Portrait or square: base is the width (shorter side).
      final rawH = (base * am).round();
      final outH = rawH % 2 == 0 ? rawH : rawH - 1;
      return (base, outH);
    } else {
      // Landscape: base is the height (shorter side); derive width.
      final rawW = (base / am).round();
      final outW = rawW % 2 == 0 ? rawW : rawW - 1;
      return (outW, base);
    }
  }

  double get _estimatedSizeMB {
    if (widget.estimatedTotalSecs <= 0) return 0;
    // Use the shorter side (resolution tier) for bitrate lookup so that
    // landscape 1080p doesn't fall into the 4K tier just because its width is 1920.
    final shortSide = _resolutions[_selResolution].baseW.toDouble();
    final baseMbps = shortSide <= 480  ? 2.0
                   : shortSide <= 720  ? 5.0
                   : shortSide <= 1080 ? 10.0
                   : shortSide <= 1440 ? 20.0
                   : 50.0;
    final qualMult = [1.0, 1.6, 2.5][_selQuality];
    final fpsMult  = _frameRates[_selFrameRate] / 30.0;
    return baseMbps * qualMult * fpsMult * widget.estimatedTotalSecs / 8;
  }

  String _formatSize(double mb) {
    if (mb < 1000) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResolutionSection(),
                        _buildDivider(),
                        _buildFrameRateSection(),
                        _buildDivider(),
                        _buildQualitySection(),
                        _buildDivider(),
                        _buildFormatSection(),
                        _buildDivider(),
                        _buildSummarySection(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  if (_showScrollHint)
                    Positioned(
                      bottom: 10,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _scrollCtrl.animateTo(
                          _scrollCtrl.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6D00),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildExportButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white, size: 26),
            ),
          ),
          const Text(
            'Export',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      const Divider(color: Color(0xFF252525), height: 1, thickness: 1);

  // ── Resolution slider ──────────────────────────────────────────────────────

  Widget _buildResolutionSection() {
    final hint = _resolutionHints[_selResolution];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Resolution', style: _sectionLabel),
              const Spacer(),
              Text(hint,
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          _buildStepSlider(
            value: _selResolution,
            count: _resolutions.length,
            onChanged: (i) => setState(() => _selResolution = i),
          ),
          const SizedBox(height: 4),
          _buildSliderLabels(
            labels: _resolutions.map((r) => r.label).toList(),
            selectedIndex: _selResolution,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Frame rate slider ──────────────────────────────────────────────────────

  Widget _buildFrameRateSection() {
    final hint = _fpsHints[_selFrameRate];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Frame Rate', style: _sectionLabel),
              const Spacer(),
              Text(hint,
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          _buildStepSlider(
            value: _selFrameRate,
            count: _frameRates.length,
            onChanged: (i) => setState(() => _selFrameRate = i),
          ),
          const SizedBox(height: 4),
          _buildSliderLabels(
            labels: _frameRates.map((f) => '$f').toList(),
            selectedIndex: _selFrameRate,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Shared slider primitives ───────────────────────────────────────────────

  Widget _buildStepSlider({
    required int value,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: _red,
        inactiveTrackColor: const Color(0xFF3A3A3A),
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayColor: _red.withValues(alpha: 0.18),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
        activeTickMarkColor: _red.withValues(alpha: 0.6),
        inactiveTickMarkColor: const Color(0xFF555555),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: value.toDouble(),
        min: 0,
        max: (count - 1).toDouble(),
        divisions: count - 1,
        onChanged: (v) => onChanged(v.round()),
      ),
    );
  }

  Widget _buildSliderLabels({
    required List<String> labels,
    required int selectedIndex,
    int? disabledAfter,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSel      = i == selectedIndex;
          final isDisabled = disabledAfter != null && i > disabledAfter;
          final color = isDisabled
              ? const Color(0xFF3A3A3A)
              : isSel ? _red : const Color(0xFF777777);
          final align = i == 0
              ? TextAlign.left
              : i == labels.length - 1
                  ? TextAlign.right
                  : TextAlign.center;
          return Expanded(
            child: Text(
              labels[i],
              textAlign: align,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Quality chips ──────────────────────────────────────────────────────────

  Widget _buildQualitySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quality', style: _sectionLabel),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(_qualities.length, (i) {
                final (name, desc, _) = _qualities[i];
                final sel = i == _selQuality;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selQuality = i),
                    child: Container(
                      margin: EdgeInsets.only(
                          right: i < _qualities.length - 1 ? 7 : 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFF2D0808)
                            : _chipUnselect,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            sel ? Border.all(color: _red, width: 2) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            sel
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: sel ? _red : const Color(0xFF555555),
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          Text(name,
                              style: TextStyle(
                                  color: sel ? _red : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(desc,
                              style: const TextStyle(
                                  color: Color(0xFF777777),
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Format chips ───────────────────────────────────────────────────────────

  Widget _buildFormatSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Format', style: _sectionLabel),
          const SizedBox(height: 14),
          Row(
            children: List.generate(_formats.length, (i) {
              final fmt = _formats[i];
              final sel = i == _selFormat;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selFormat = i),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i < _formats.length - 1 ? 7 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2D0808) : _chipUnselect,
                      borderRadius: BorderRadius.circular(12),
                      border: sel ? Border.all(color: _red, width: 2) : null,
                    ),
                    child: Center(
                      child: Text(
                        fmt.label,
                        style: TextStyle(
                            color: sel ? _red : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────────

  Widget _buildSummarySection() {
    final res = _resolutions[_selResolution];
    final fps = _frameRates[_selFrameRate];
    final (qualityName, _, _) = _qualities[_selQuality];
    final fmt = _formats[_selFormat];
    final (outW, outH) = _outDims;
    final size = _estimatedSizeMB;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _summaryItem(
                      'Resolution', '${res.label} ($outW×$outH)',
                      align: CrossAxisAlignment.start)),
              Expanded(
                  child: _summaryItem('Frame rate', '$fps fps',
                      align: CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _summaryItem('Quality', qualityName,
                      align: CrossAxisAlignment.start)),
              Expanded(
                  child: _summaryItem('Format', fmt.label,
                      align: CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF252525), height: 1),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Estimated size',
                  style: TextStyle(
                      color: Color(0xFF888888), fontSize: 13)),
              const Spacer(),
              Text(_formatSize(size),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value,
      {required CrossAxisAlignment align}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF888888), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Export button ──────────────────────────────────────────────────────────

  Widget _buildExportButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: GestureDetector(
        onTap: _goToPreview,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6D00), Color(0xFFE53935)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Center(
            child: Text(
              'Continue',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goToPreview() {
    final (outW, outH) = _outDims;
    final (_, _, crf)  = _qualities[_selQuality];
    final fps          = _frameRates[_selFrameRate];
    final fmt          = _formats[_selFormat];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollagePreviewScreen(
          cells:            widget.cells,
          cellRects:        widget.cellRects,
          videoControllers: widget.videoControllers,
          cellRepeating:    widget.cellRepeating,
          bgColor:          widget.bgColor,
          borderGap:        widget.borderGap,
          audioPath:        widget.audioPath,
          audioTrimStart:   widget.audioTrimStart,
          audioTrimEnd:     widget.audioTrimEnd,
          audioVolume:      widget.audioVolume,
          outW:             outW,
          outH:             outH,
          cellFilterVf:     widget.cellFilterVf,
          cellColorFilters: widget.cellColorFilters,
          cellSpeeds:       widget.cellSpeeds,
          cellVolumes:      widget.cellVolumes,
          cellRotSteps:     widget.cellRotSteps,
          cellFlipH:        widget.cellFlipH,
          cellFlipV:        widget.cellFlipV,
          cellScales:       widget.cellScales,
          cellAngles:       widget.cellAngles,
          cellNormOffsetX:  widget.cellNormOffsetX,
          cellNormOffsetY:  widget.cellNormOffsetY,
          draftId:          widget.draftId,
          layoutId:         widget.layoutId,
          isArtistic:       widget.isArtistic,
          artOffsets:       widget.artOffsets,
          // Export settings
          fps:              fps,
          crf:              crf,
          format:           fmt.ext,
          faststart:        fmt.faststart,
        ),
      ),
    );
  }
}
