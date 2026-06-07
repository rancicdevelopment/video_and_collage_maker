part of 'video_editor_screen.dart';

extension _VeTrackEditExt on _VideoEditorScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  //  Undo / Redo
  // ─────────────────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(List.from(_tracks));
    _redoStack.clear();
    _scheduleDraftSave();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(_tracks));
    _rebuild(() {
      _tracks = _undoStack.removeLast();
      _selectedIndex = null;
    });
    _scheduleDraftSave();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(_tracks));
    _rebuild(() {
      _tracks = _redoStack.removeLast();
      _selectedIndex = null;
    });
    _scheduleDraftSave();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Track operations
  // ─────────────────────────────────────────────────────────────────────────

  void _deleteTrack() {
    if (_selectedIndex == null) return;
    _pushUndo();
    final track = _tracks[_selectedIndex!];
    _releaseAudioPlayer(track.id);
    _releaseVideoController(track.id);
    _rebuild(() {
      _tracks.removeAt(_selectedIndex!);
      _selectedIndex = _tracks.isEmpty
          ? null
          : (_selectedIndex! - 1).clamp(0, _tracks.length - 1);
    });
  }

  void _splitTrack() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    final splitAt = _playheadPos - track.startOffset;
    if (splitAt <= Duration.zero || splitAt >= track.effectiveDuration) {
      _snack('Move playhead inside the track to split.', error: true);
      return;
    }
    _pushUndo();
    _releaseAudioPlayer(track.id);
    _releaseVideoController(track.id);
    final ts = DateTime.now().microsecondsSinceEpoch;
    final left = track.copyWith(
      id: '${ts}_L',
      trimEnd: track.trimEnd + (track.effectiveDuration - splitAt),
    );
    final right = track.copyWith(
      id: '${ts}_R',
      startOffset: track.startOffset + splitAt,
      trimStart: track.trimStart + splitAt,
    );
    _rebuild(() {
      _tracks..removeAt(idx)..insert(idx, right)..insert(idx, left);
      _selectedIndex = idx;
    });
    // Re-init controllers for the new split tracks
    if (right.isVideo) {
      _getOrInitVideoController(right);
      _extractThumbnails(right.id, right.filePath);
    } else {
      _extractWaveform(right.id, right.filePath);
    }
    if (left.isVideo) {
      _getOrInitVideoController(left);
      _extractThumbnails(left.id, left.filePath);
    } else {
      _extractWaveform(left.id, left.filePath);
    }
  }

  void _trimTrack() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    final relPos = _playheadPos - track.startOffset;
    if (relPos <= Duration.zero || relPos >= track.effectiveDuration) {
      _snack('Move playhead inside the track to trim.', error: true);
      return;
    }
    _pushUndo();
    _rebuild(() {
      _tracks[idx] = track.copyWith(
        trimEnd: track.trimEnd + (track.effectiveDuration - relPos),
      );
    });
  }

  void _duplicateTrack() {
    if (_selectedIndex == null) return;
    _pushUndo();
    final src = _tracks[_selectedIndex!];
    final dup = src.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startOffset: src.endTime,
    );
    _rebuild(() {
      _tracks.insert(_selectedIndex! + 1, dup);
      _selectedIndex = _selectedIndex! + 1;
    });
    if (dup.isVideo) {
      _getOrInitVideoController(dup);
    }
  }

  void _moveTrackUp() {
    if (_selectedIndex == null || _selectedIndex! <= 0 || _tracks.length < 2) return;
    _pushUndo();
    final idx = _selectedIndex!;
    _rebuild(() {
      final tmp = _tracks.removeAt(idx);
      _tracks.insert(idx - 1, tmp);
      _selectedIndex = idx - 1;
    });
  }

  void _moveTrackDown() {
    if (_selectedIndex == null ||
        _selectedIndex! >= _tracks.length - 1 ||
        _tracks.length < 2) { return; }
    _pushUndo();
    final idx = _selectedIndex!;
    _rebuild(() {
      final tmp = _tracks.removeAt(idx);
      _tracks.insert(idx + 1, tmp);
      _selectedIndex = idx + 1;
    });
  }

  void _rotateTrack() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    _rebuild(() {
      _tracks[_selectedIndex!] =
          track.copyWith(rotation: (track.rotation + 90) % 360);
    });
  }

  void _mirrorTrack() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    _rebuild(() {
      _tracks[_selectedIndex!] = track.copyWith(mirrorH: !track.mirrorH);
    });
  }

  // ── Play Backwards ─────────────────────────────────────────────────────
  Future<void> _reverseTrack() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;
    if (_reversePreviewGenerating) return;
    _pushUndo();
    final updated = track.copyWith(playBackwards: !track.playBackwards);
    _rebuild(() {
      _tracks[_selectedIndex!] = updated;
    });
    await _generateReversePreview(updated);
  }

  // ── Freeze Frame — extract current frame and insert as image track ─────
  Future<void> _freezeFrame() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    // Ask user for freeze duration.
    double freezeSecs = 3.0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF111E2F),
          title: const Text('Freeze Frame',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Duration of the frozen frame:',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Duration',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${freezeSecs.toStringAsFixed(1)}s',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              Slider(
                value: freezeSecs,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                activeColor: const Color(0xFF00C8FF),
                inactiveColor: Colors.white12,
                onChanged: (v) => setS(() => freezeSecs = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C8FF),
                  foregroundColor: Colors.black),
              child: const Text('Freeze'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // Calculate source timestamp.
    final relMs = (_playheadPos - track.startOffset)
        .inMilliseconds
        .clamp(0, track.effectiveDuration.inMilliseconds);
    final sourceMs =
        (relMs * track.speed + track.trimStart.inMilliseconds).toInt();
    final seekSec = sourceMs / 1000.0;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir  = await getTemporaryDirectory();
    final outPath = p.join(tmpDir.path,
        'freeze_${track.id}_${DateTime.now().millisecondsSinceEpoch}.png');

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(width: 16),
          Text('Ekstrakcija kadra…',
              style: TextStyle(color: Colors.white)),
        ]),
      ),
    );

    final session = await FFmpegKit.executeWithArguments([
      '-y', '-ss', seekSec.toStringAsFixed(3),
      '-i', track.filePath,
      '-frames:v', '1', '-q:v', '1', outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!ReturnCode.isSuccess(rc) || !File(outPath).existsSync()) {
      _snack('Ekstrakcija kadra nije uspjela.', error: true);
      return;
    }

    // Insert frozen image track right at the current playhead position.
    _pushUndo();
    final frozenTrack = TimelineTrack(
      id:          TimelineTrack.generateId(),
      filePath:    outPath,
      title:       'Frozen frame',
      trackType:   TrackType.image,
      duration:    Duration(milliseconds: (freezeSecs * 1000).round()),
      startOffset: _playheadPos,
      color:       const Color(0xFF00C8FF),
      overlayScale: track.overlayScale,
      overlayX:     track.overlayX,
      overlayY:     track.overlayY,
    );
    _rebuild(() {
      // Insert directly above the source video track.
      final insertAt = (_selectedIndex! + 1).clamp(0, _tracks.length);
      _tracks.insert(insertAt, frozenTrack);
    });
    _snack('Frozen frame added to the timeline.');
  }

  Future<void> _extractAudio() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir = await getTemporaryDirectory();
    final outName = '${p.basenameWithoutExtension(track.filePath)}_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final outPath = p.join(tmpDir.path, outName);

    // Show progress indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Extracting audio...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    // FFmpeg: extract audio only, no re-encode if possible
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', track.filePath,
      '-vn',
      '-c:a', 'libmp3lame', '-q:a', '2',
      outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close dialog

    if (!ReturnCode.isSuccess(rc)) {
      _snack('Audio extraction failed.', error: true);
      return;
    }

    // Get duration of extracted audio
    Duration duration = track.effectiveDuration;
    try {
      final tmpPlayer = AudioPlayer();
      await tmpPlayer.setSourceDeviceFile(outPath);
      final dur = await tmpPlayer.getDuration();
      if (dur != null) duration = dur;
      await tmpPlayer.dispose();
    } catch (_) {}

    _pushUndo();
    final audioTrack = TimelineTrack.fromFile(
      filePath: outPath,
      title: '${p.basenameWithoutExtension(track.filePath)} (audio)',
      duration: duration,
      trackType: TrackType.audio,
      colorIndex: _tracks.length,
      startOffset: track.startOffset,
    );

    _rebuild(() {
      // Mute the source video track so its embedded audio doesn't double up
      _tracks[_selectedIndex!] = _tracks[_selectedIndex!].copyWith(volume: 0.0);
      _tracks.insert(_selectedIndex! + 1, audioTrack);
      _selectedIndex = _selectedIndex! + 1;
    });

    _extractWaveform(audioTrack.id, outPath);
    _snack('Audio extracted successfully.');
  }

  Future<void> _exportFrame() async {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;

    // Calculate the time within the source video file at the current playhead.
    // Timeline position relative to track start, scaled by speed, plus trim offset.
    final relativeMs =
        (_playheadPos - track.startOffset).inMilliseconds.clamp(0, track.effectiveDuration.inMilliseconds);
    final sourceMs = (relativeMs * track.speed + track.trimStart.inMilliseconds).toInt();
    final seekSec = sourceMs / 1000.0;

    await _stopPlayback();
    if (!mounted) return;

    final tmpDir = await getTemporaryDirectory();
    final outName =
        '${p.basenameWithoutExtension(track.filePath)}_frame_${DateTime.now().millisecondsSinceEpoch}.png';
    final outPath = p.join(tmpDir.path, outName);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF111E2F),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Extracting frame...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', seekSec.toStringAsFixed(3),
      '-i', track.filePath,
      '-frames:v', '1',
      '-q:v', '1',
      outPath,
    ]);
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!ReturnCode.isSuccess(rc)) {
      _snack('Frame extraction failed.', error: true);
      return;
    }

    try {
      await Gal.putImage(outPath, album: 'Video Editor');
    } catch (e) {
      _snack('Frame extracted but could not save to gallery.', error: true);
      return;
    }

    if (!mounted) return;
    _snack('Frame saved to gallery.');
  }

  Duration _filePosFor(int i, Duration timelinePos) {
    final t = _tracks[i];
    if (timelinePos <= t.startOffset) return t.trimStart;
    final elapsed = timelinePos - t.startOffset;
    final fileElapsed =
        Duration(microseconds: (elapsed.inMicroseconds * t.speed).round());
    final candidate = t.trimStart + fileElapsed;
    final maxPos = t.duration - t.trimEnd;
    return candidate > maxPos ? t.trimStart : candidate;
  }
}
