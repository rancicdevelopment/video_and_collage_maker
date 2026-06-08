part of 'video_editor_screen.dart';

const Color _kVeBgColor = Color(0xFF0D1623);
const Color _kVeSurfaceColor = Color(0xFF111E2F);
const Color _kVeOnSurface = Colors.white;
const double _kLabelPanelW = 54.0;

extension _VeBuildExt on _VideoEditorScreenState {

  // ── App bar ──────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _kVeBgColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: _kVeOnSurface),
        onPressed: _confirmDiscard,
      ),
      title: const Text(
        'Video Editor',
        style: TextStyle(
            color: _kVeOnSurface, fontWeight: FontWeight.w600, fontSize: 17),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.undo,
            color: _undoStack.isEmpty
                ? _kVeOnSurface.withValues(alpha: 0.3)
                : _kVeOnSurface,
          ),
          onPressed: _undoStack.isEmpty ? null : _undo,
        ),
        IconButton(
          icon: Icon(
            Icons.redo,
            color: _redoStack.isEmpty
                ? _kVeOnSurface.withValues(alpha: 0.3)
                : _kVeOnSurface,
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
                        color: _kVeOnSurface, strokeWidth: 2),
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

  // ── Labels panel ──────────────────────────────────────────────────────────

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
            _rebuild(() => _selectedIndex = trackIdx);
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
        onTap: () => _rebuild(() => _selectedIndex = index),
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
                    _rebuild(() {
                      _selectedIndex = index;
                      _rowReorderActive = true;
                    });
                  },
                  onPointerMove: (e) => _onRowReorderMove(e.delta.dy),
                  onPointerUp: (_) {
                    _rowReorderIdx = null;
                    _scheduleDraftSave();
                    _rebuild(() => _rowReorderActive = false);
                  },
                  onPointerCancel: (_) {
                    _rowReorderIdx = null;
                    _rebuild(() => _rowReorderActive = false);
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
                  onTap: () => _rebuild(() {
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
              width: max(timelineW + 60, constraints.maxWidth * 30),
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
                        _rebuild(() => _rulerScrubActive = true),
                    onHorizontalDragUpdate: (details) {
                      final contentX = details.localPosition.dx +
                          (_hScrollCtrl.hasClients
                              ? _hScrollCtrl.offset
                              : 0.0);
                      _seekVisualOnly(_contentXToDuration(contentX));
                    },
                    onHorizontalDragEnd: (_) {
                      _rebuild(() => _rulerScrubActive = false);
                      _applySeek(_playheadPos);
                      _scheduleDraftSave();
                    },
                    onHorizontalDragCancel: () =>
                        _rebuild(() => _rulerScrubActive = false),
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
            _rebuild(() => _playheadDragActive = true),
        onHorizontalDragUpdate: (details) {
          final newSecs =
              (_playheadPos.inMilliseconds / 1000.0 +
                      details.delta.dx / _pps)
                  .clamp(0.0, double.infinity);
          _seekVisualOnly(
              Duration(milliseconds: (newSecs * 1000).round()));
          _autoScrollToPlayhead(newSecs);
        },
        onHorizontalDragEnd: (_) {
          _rebuild(() => _playheadDragActive = false);
          if (_isPlaying) _startAllFromPos(_playheadPos);
        },
        onHorizontalDragCancel: () =>
            _rebuild(() => _playheadDragActive = false),
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
            onTap: () => _rebuild(() => _selectedIndex = index),
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
                _rebuild(() => _trimActive = true);
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
                _rebuild(() {
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
                _scheduleDraftSave();
                _rebuild(() => _trimActive = false);
              },
              onTrimRightStart: (_) {
                _trimHandleDown = true;
                _pushUndo();
                _trimTrackIndex = index;
                _rebuild(() => _trimActive = true);
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
                _rebuild(() {
                  _tracks[index] = curr.copyWith(
                    trimEnd: Duration(
                        milliseconds: (newTrimSecs * 1000).round()),
                  );
                });
              },
              onTrimRightEnd: (_) {
                _trimHandleDown = false;
                _trimTrackIndex = null;
                _scheduleDraftSave();
                _rebuild(() => _trimActive = false);
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
              _pushUndo();
              _trackDragIndex = index;
              _trackDragStartX = e.position.dx;
              _trackDragOriginalOffset = track.startOffset;
              _rebuild(() {
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
              _rebuild(() {
                _tracks[index] = _tracks[index].copyWith(
                  startOffset: Duration(
                      milliseconds: (newSecs * 1000).round()),
                );
              });
            },
            onPointerUp: (_) {
              if (_trackDragIndex == index) {
                _trackDragIndex = null;
                _scheduleDraftSave();
                _rebuild(() => _trackDragActive = false);
                if (_isPlaying) _startAllFromPos(_playheadPos);
              }
            },
            onPointerCancel: (_) {
              _trackDragIndex = null;
              _rebuild(() => _trackDragActive = false);
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
                  color: _kVeOnSurface.withValues(alpha: 0.55),
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
                onTap: () => _rebuild(() {
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
      color: _kVeSurfaceColor,
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
              _scheduleDraftSave();
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
              _scheduleDraftSave();
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
    const double arrowW = 32.0;
    return Container(
      height: 62,
      color: _kVeSurfaceColor,
      child: Row(
        children: [
          // Left arrow button — fixed, not part of scroll
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _toolbarCanScrollLeft ? arrowW : 0.0,
            child: AnimatedOpacity(
              opacity: _toolbarCanScrollLeft ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () => _toolbarScrollBy(-180),
                child: Container(
                  width: arrowW,
                  color: _kVeSurfaceColor,
                  alignment: Alignment.center,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Scrollable tool buttons
          Expanded(
            child: SingleChildScrollView(
              controller: _toolbarScrollCtrl,
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
          ),
          // Right arrow button — fixed, not part of scroll
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _toolbarCanScrollRight ? arrowW : 0.0,
            child: AnimatedOpacity(
              opacity: _toolbarCanScrollRight ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () => _toolbarScrollBy(180),
                child: Container(
                  width: arrowW,
                  color: _kVeSurfaceColor,
                  alignment: Alignment.center,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 20,
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

  Widget _greenScreenToolBtn(bool enabled) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
                      color: _kVeOnSurface.withValues(alpha: 0.75),
                    )
                  : Icon(
                      Icons.blur_circular_outlined,
                      color: enabled
                          ? _kVeOnSurface
                          : _kVeOnSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Green Screen',
              style: TextStyle(
                color: enabled
                    ? _kVeOnSurface.withValues(alpha: 0.75)
                    : _kVeOnSurface.withValues(alpha: 0.22),
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
      behavior: HitTestBehavior.opaque,
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
                              ? _kVeOnSurface
                              : _kVeOnSurface.withValues(alpha: 0.25),
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
                        ? _kVeOnSurface.withValues(alpha: 0.75)
                        : _kVeOnSurface.withValues(alpha: 0.22),
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
      behavior: HitTestBehavior.opaque,
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
                              ? _kVeOnSurface
                              : _kVeOnSurface.withValues(alpha: 0.25),
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
                        ? _kVeOnSurface.withValues(alpha: 0.75)
                        : _kVeOnSurface.withValues(alpha: 0.22),
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
      behavior: HitTestBehavior.opaque,
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
                      color: _kVeOnSurface.withValues(alpha: 0.75),
                    )
                  : Icon(
                      Icons.record_voice_over_outlined,
                      color: enabled
                          ? _kVeOnSurface
                          : _kVeOnSurface.withValues(alpha: 0.25),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              'Voice',
              style: TextStyle(
                color: enabled
                    ? _kVeOnSurface.withValues(alpha: 0.75)
                    : _kVeOnSurface.withValues(alpha: 0.22),
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
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: !enabled
                  ? _kVeOnSurface.withValues(alpha: 0.25)
                  : isActive
                      ? activeColor
                      : _kVeOnSurface,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: !enabled
                    ? _kVeOnSurface.withValues(alpha: 0.22)
                    : isActive
                        ? activeColor
                        : _kVeOnSurface.withValues(alpha: 0.75),
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
