part of 'video_editor_screen.dart';

// ── Fullscreen preview overlay ──────────────────────────────────────────────

class _FullscreenPreviewOverlay extends StatefulWidget {
  const _FullscreenPreviewOverlay({required this.editorState});
  final _VideoEditorScreenState editorState;

  @override
  State<_FullscreenPreviewOverlay> createState() =>
      _FullscreenPreviewOverlayState();
}

class _FullscreenPreviewOverlayState extends State<_FullscreenPreviewOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _isSeeking = false;
  double _seekFraction = 0.0;

  _VideoEditorScreenState get _ed => widget.editorState;

  @override
  void initState() {
    super.initState();
    // Refresh at ~15 fps so seek bar tracks playhead smoothly.
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _positionFraction {
    final total = _ed._totalDuration.inMicroseconds;
    if (total <= 0) return 0;
    return (_ed._playheadPos.inMicroseconds / total).clamp(0.0, 1.0);
  }

  void _onSeekStart(double fraction) {
    setState(() {
      _isSeeking = true;
      _seekFraction = fraction;
    });
  }

  void _onSeekUpdate(double fraction) {
    setState(() => _seekFraction = fraction.clamp(0.0, 1.0));
  }

  void _onSeekEnd(double fraction) {
    final total = _ed._totalDuration.inMicroseconds;
    final newPos =
        Duration(microseconds: (fraction.clamp(0.0, 1.0) * total).round());
    _ed._applySeek(newPos);
    setState(() => _isSeeking = false);
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _ed._isPlaying;
    final position = _ed._playheadPos;
    final total = _ed._totalDuration;
    final seekVal = _isSeeking ? _seekFraction : _positionFraction;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Video content ──────────────────────────────────────────────
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(builder: (ctx, constraints) {
                  final cw = constraints.maxWidth;
                  final ch = constraints.maxHeight;
                  return _ed._buildPreviewLayers(cw, ch, interactive: false);
                }),
              ),
            ),
          ),

          // ── Dismiss button (top-right) ─────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white24, width: 1),
                ),
                child: const Text(
                  'Dismiss',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          // ── Bottom controls ────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.70),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          _fmt(_isSeeking
                              ? Duration(
                                  microseconds: (_seekFraction *
                                          total.inMicroseconds)
                                      .round())
                              : position),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                        const Spacer(),
                        Text(
                          _fmt(total),
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),

                  // Seek bar
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14),
                      activeTrackColor: const Color(0xFFFF4D4D),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor:
                          Colors.white.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: seekVal,
                      onChangeStart: _onSeekStart,
                      onChanged: _onSeekUpdate,
                      onChangeEnd: _onSeekEnd,
                    ),
                  ),

                  // Playback buttons row
                  Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Exit fullscreen
                        IconButton(
                          icon: const Icon(Icons.fullscreen_exit,
                              color: Colors.white70, size: 26),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Skip to start
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white70, size: 26),
                          onPressed: () => _ed._applySeek(Duration.zero),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Play / Pause
                        GestureDetector(
                          onTap: _ed._togglePlayback,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                                color: Color(0xFFFF4D4D),
                                shape: BoxShape.circle),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        // Skip to end
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white70, size: 26),
                          onPressed: () => _ed._applySeek(total),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Fullscreen placeholder (right balance)
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Text overlay control button ───────────────────────────────────────────────

/// Small circular icon button used in the text-selection overlay
/// (delete, edit, move-hint).
class _VeTextCtrlBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback? onTap;
  final void Function(DragUpdateDetails)? onPanUpdate;
  final void Function(DragStartDetails)? onPanStart;
  final void Function(DragEndDetails)? onPanEnd;

  const _VeTextCtrlBtn({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.onTap,
    this.onPanUpdate,
    this.onPanStart,
    this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}
