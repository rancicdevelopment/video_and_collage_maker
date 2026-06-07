part of 'video_editor_screen.dart';

extension _VeTimelineExt on _VideoEditorScreenState {
  void _syncLabelsScroll() {
    if (!_labelsScrollCtrl.hasClients) return;
    final maxE = _labelsScrollCtrl.position.maxScrollExtent;
    _labelsScrollCtrl.jumpTo(_vScrollCtrl.offset.clamp(0.0, maxE));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Timeline helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Actual end of all clip content — playhead cannot go past this.
  Duration get _contentEndTime {
    if (_tracks.isEmpty) return Duration.zero;
    Duration max = Duration.zero;
    for (final t in _tracks) {
      if (t.endTime > max) max = t.endTime;
    }
    return max;
  }

  Duration get _totalDuration {
    if (_tracks.isEmpty) return const Duration(minutes: 5);
    return _contentEndTime + const Duration(seconds: 30);
  }

  double _secondsToX(double secs) => secs * _pps;
  double _xToSeconds(double x) => x / _pps;

  bool _isCollapsed(TimelineTrack t) => _collapsedTracks.contains(t.id);

  void _toggleAllTracks() {
    _rebuild(() {
      final trackAllCollapsed = _tracks.isEmpty || _tracks.every(_isCollapsed);
      final emptyAllCollapsed = _collapsedEmptyRows.length == 10;
      final allCollapsed = trackAllCollapsed && emptyAllCollapsed;
      if (allCollapsed) {
        _collapsedTracks.clear();
        _collapsedEmptyRows.clear();
      } else {
        _collapsedTracks.addAll(_tracks.map((t) => t.id));
        _collapsedEmptyRows.addAll(
          List.generate(10, (i) => _tracks.length + i),
        );
      }
    });
  }

  double _trackHeightFor(TimelineTrack t) {
    if (_isCollapsed(t)) return kVeCollapsedTrackHeight;
    return (t.isVideo || t.isText || t.isImage) ? kVeVideoTrackHeight : kVeAudioTrackHeight;
  }

  double _rowHeightFor(TimelineTrack t) =>
      _trackHeightFor(t) + kVeTrackGap;

  // ignore: unused_element
  double _topOffsetForRow(int index) {
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _rowHeightFor(_tracks[i]);
    }
    return offset;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Zoom
  // ─────────────────────────────────────────────────────────────────────────

  void _autoZoomToFit() {
    // Zoom so the actual content (without trailing buffer) fills ~80% of screen
    double contentSecs = 0;
    for (final t in _tracks) {
      final end = t.endTime.inMilliseconds / 1000.0;
      if (end > contentSecs) contentSecs = end;
    }
    if (contentSecs <= 0) return;
    final screenW = MediaQuery.of(context).size.width;
    final targetPps = (screenW * 0.80 / contentSecs).clamp(kVeMinPPS, kVeMaxPPS);
    if (_hScrollCtrl.hasClients) {
      _hScrollCtrl.jumpTo(0);
    }
    _rebuild(() => _pps = targetPps);
  }

  void _zoomAtViewportX(double newPps, double viewportX) {
    final clamped = newPps.clamp(kVeMinPPS, kVeMaxPPS);
    if (clamped == _pps) return;
    final anchorSecs =
        (viewportX + (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0)) /
            _pps;
    if (_hScrollCtrl.hasClients) {
      final viewW = _hScrollCtrl.position.viewportDimension;
      final newMax =
          (_totalDuration.inSeconds.toDouble() * clamped + 60 - viewW)
              .clamp(0.0, double.infinity);
      final target =
          (anchorSecs * clamped - viewportX).clamp(0.0, newMax);
      _hScrollCtrl.jumpTo(target);
    }
    _rebuild(() => _pps = clamped);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Auto-scroll
  // ─────────────────────────────────────────────────────────────────────────

  void _autoScrollToPlayhead(double secs) {
    if (!_hScrollCtrl.hasClients) return;
    const edgePad = 40.0;
    final playheadX = secs * _pps;
    final offset = _hScrollCtrl.offset;
    final viewW = _hScrollCtrl.position.viewportDimension;
    final maxScroll = _hScrollCtrl.position.maxScrollExtent;

    if (playheadX < offset + edgePad) {
      _hScrollCtrl
          .jumpTo((playheadX - edgePad).clamp(0.0, maxScroll));
    } else if (playheadX > offset + viewW - edgePad) {
      _hScrollCtrl
          .jumpTo((playheadX - viewW + edgePad).clamp(0.0, maxScroll));
    }
  }

  /// Returns true if the given viewport position lands on a track block.
  /// Used to suppress cursor seek when the user taps a track rather than
  /// empty timeline space.
  bool _isTapOnTrackBlock(Offset viewportPos) {
    // Taps inside the ruler never hit a track block.
    if (viewportPos.dy <= kVeRulerHeight) return false;

    final contentX = viewportPos.dx +
        (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
    final contentY = (viewportPos.dy - kVeRulerHeight) +
        (_vScrollCtrl.hasClients ? _vScrollCtrl.offset : 0.0);

    double rowTop = 0;
    for (final track in _tracks) {
      final rowH = _rowHeightFor(track);
      if (contentY >= rowTop && contentY < rowTop + rowH) {
        final startX =
            _secondsToX(track.startOffset.inMilliseconds / 1000.0);
        final minW = (_pps * 2.0).clamp(2.0, 40.0);
        final trackW =
            _secondsToX(track.effectiveDuration.inMilliseconds / 1000.0)
                .clamp(minW, double.infinity);
        if (contentX >= startX && contentX <= startX + trackW) {
          return true;
        }
      }
      rowTop += rowH;
    }
    return false;
  }

  void _onPinchDown(PointerDownEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_activePointers.length == 1) {
      _seekTapViewportPos = e.localPosition;
      // Suppress seek when the finger lands directly on a track block;
      // seek only on empty space or via explicit playhead/ruler drag.
      _seekTapValid = !_isTapOnTrackBlock(e.localPosition);
    } else {
      _seekTapValid = false;
      _seekTapViewportPos = null;
    }
    if (_activePointers.length == 2) {
      _pinchActive = true;
      final pts = _activePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartPps = _pps;
      _pinchAnchorViewportX = (pts[0].dx + pts[1].dx) / 2;
      _pinchAnchorSecs =
          (_pinchAnchorViewportX +
                  (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0)) /
              _pps;
    }
    _rebuild(() {});
  }

  void _onPinchMove(PointerMoveEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_seekTapValid && _seekTapViewportPos != null) {
      if ((e.localPosition - _seekTapViewportPos!).distance > 12) {
        _seekTapValid = false;
      }
    }
    if (_activePointers.length == 2 && _pinchStartDistance > 0) {
      final pts = _activePointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final newPps =
          (_pinchStartPps * dist / _pinchStartDistance)
              .clamp(kVeMinPPS, kVeMaxPPS);
      if (newPps != _pps && _hScrollCtrl.hasClients) {
        final viewW = _hScrollCtrl.position.viewportDimension;
        final newMax =
            (_totalDuration.inSeconds.toDouble() * newPps + 60 - viewW)
                .clamp(0.0, double.infinity);
        final target =
            (_pinchAnchorSecs * newPps - _pinchAnchorViewportX)
                .clamp(0.0, newMax);
        _hScrollCtrl.jumpTo(target);
        _rebuild(() => _pps = newPps);
      } else if (newPps != _pps) {
        _rebuild(() => _pps = newPps);
      }
    }
  }

  void _onPinchUp(PointerUpEvent e) {
    final wasPinching = _activePointers.length >= 2;
    if (_seekTapValid &&
        _activePointers.length == 1 &&
        !_trimActive &&
        !_trimHandleDown &&
        !_trackDragActive &&
        !_playheadDragActive) {
      final contentX = e.localPosition.dx +
          (_hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0);
      _applySeek(_contentXToDuration(contentX));
      _scheduleDraftSave();
    }
    _seekTapValid = false;
    _seekTapViewportPos = null;
    _activePointers.remove(e.pointer);
    if (_activePointers.isEmpty) {
      _pinchActive = false;
      _pinchStartDistance = 0;
      if (wasPinching) _scheduleDraftSave(); // zoom gesture ended
    } else if (_activePointers.length < 2) {
      _pinchStartDistance = 0;
      if (_activePointers.length == 1) _pinchStartPps = _pps;
    }
    _rebuild(() {});
  }

  void _onPinchCancel(PointerCancelEvent e) {
    _seekTapValid = false;
    _seekTapViewportPos = null;
    _activePointers.remove(e.pointer);
    _pinchStartDistance = 0;
    if (_activePointers.isEmpty) _pinchActive = false;
    _rebuild(() {});
  }

  /// Called from the vertical drag handle on each row.
  /// [dy] is the raw pointer delta from this move event.
  void _onRowReorderMove(double dy) {
    if (!_rowReorderActive || _rowReorderIdx == null) return;
    _rowReorderAccumDy += dy;
    final curr = _rowReorderIdx!;

    if (_rowReorderAccumDy < 0 && curr > 0) {
      final threshold = _rowHeightFor(_tracks[curr - 1]) / 2;
      if (_rowReorderAccumDy.abs() >= threshold) {
        final consumed = _rowHeightFor(_tracks[curr - 1]);
        _rebuild(() {
          final tmp = _tracks.removeAt(curr);
          _tracks.insert(curr - 1, tmp);
          _rowReorderIdx = curr - 1;
          if (_selectedIndex == curr) _selectedIndex = curr - 1;
        });
        _rowReorderAccumDy += consumed;
      }
    } else if (_rowReorderAccumDy > 0 && curr < _tracks.length - 1) {
      final threshold = _rowHeightFor(_tracks[curr + 1]) / 2;
      if (_rowReorderAccumDy >= threshold) {
        final consumed = _rowHeightFor(_tracks[curr + 1]);
        _rebuild(() {
          final tmp = _tracks.removeAt(curr);
          _tracks.insert(curr + 1, tmp);
          _rowReorderIdx = curr + 1;
          if (_selectedIndex == curr) _selectedIndex = curr + 1;
        });
        _rowReorderAccumDy -= consumed;
      }
    }
  }
}
