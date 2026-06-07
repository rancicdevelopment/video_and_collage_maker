part of 'video_editor_screen.dart';

extension _VeTrackAddExt on _VideoEditorScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  //  Add tracks
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _addVideoTrack() => _openMediaPicker(initialTab: 0);

  /// Opens the custom gallery picker and adds the returned files as tracks.
  /// [initialTab]: 0 = VIDEO, 1 = PHOTO, 2 = ALL
  Future<void> _openMediaPicker({int initialTab = 0}) async {
    await _stopPlayback();
    if (!mounted) return;

    final picks = await Navigator.push<List<PickedMediaFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(initialTab: initialTab),
        fullscreenDialog: true,
      ),
    );
    if (picks == null || picks.isEmpty || !mounted) return;

    _pushUndo();
    const kImageDuration = Duration(seconds: 30);

    for (final pick in picks) {
      if (pick.isVideo) {
        // Get accurate duration via a temporary controller.
        Duration duration = pick.duration;
        if (duration == Duration.zero) {
          try {
            final tmp = VideoPlayerController.file(File(pick.path));
            await tmp.initialize();
            duration = tmp.value.duration;
            await tmp.dispose();
          } catch (_) {}
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
        );

        final isFirst = _tracks.isEmpty;
        _rebuild(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }

        _getOrInitVideoController(track).then((_) {
          if (mounted) {
            _rebuild(() {});
            _updatePreviewForSeek(_playheadPos);
          }
        });

        await _extractThumbnails(track.id, pick.path);
      } else {
        // Image track
        final track = TimelineTrack(
          id: TimelineTrack.generateId(),
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          trackType: TrackType.image,
          duration: kImageDuration,
          startOffset: _playheadPos,
          color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        );

        final isFirst = _tracks.isEmpty;
        _rebuild(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }
      }
    }
  }

  Future<void> _addAudioTrack() async {
    await _stopPlayback();
    if (!mounted) return;

    AppOpenAdManager.instance.suppressNextResume();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    _pushUndo();
    for (final file in result.files) {
      if (file.path == null) continue;
      final path = file.path!;

      // Attempt to get audio duration
      Duration duration = const Duration(minutes: 3);
      try {
        final tmpPlayer = AudioPlayer();
        await tmpPlayer.setSourceDeviceFile(path);
        final dur = await tmpPlayer.getDuration();
        if (dur != null) duration = dur;
        await tmpPlayer.dispose();
      } catch (e) {
        debugPrint('Failed to get audio duration for $path: $e');
      }

      final track = TimelineTrack.fromFile(
        filePath: path,
        title: p.basenameWithoutExtension(path),
        duration: duration,
        trackType: TrackType.audio,
        colorIndex: _tracks.length,
        startOffset: _playheadPos,
      );

      final isFirstTrack = _tracks.isEmpty;
      _rebuild(() {
        _tracks.add(track);
        _selectedIndex = _tracks.length - 1;
      });

      if (isFirstTrack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoZoomToFit();
        });
      }

      _extractWaveform(track.id, path);
    }
  }

  /// Adds an audio track from a known file path without showing a file picker.
  /// Used when navigating from the voice recorder preview.
  Future<void> _addAudioFromPath(String path) async {
    if (!File(path).existsSync()) return;
    await _stopPlayback();
    if (!mounted) return;

    Duration duration = const Duration(minutes: 3);
    try {
      final tmpPlayer = AudioPlayer();
      await tmpPlayer.setSourceDeviceFile(path);
      final dur = await tmpPlayer.getDuration();
      if (dur != null) duration = dur;
      await tmpPlayer.dispose();
    } catch (e) {
      debugPrint('Failed to get audio duration for $path: $e');
    }

    final track = TimelineTrack.fromFile(
      filePath: path,
      title: p.basenameWithoutExtension(path),
      duration: duration,
      trackType: TrackType.audio,
      colorIndex: _tracks.length,
      startOffset: Duration.zero,
    );

    _pushUndo();
    _rebuild(() {
      _tracks.add(track);
      _selectedIndex = _tracks.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoZoomToFit();
    });

    _extractWaveform(track.id, path);
  }

  Future<void> _openRecorder() async {
    await _stopPlayback();
    if (!mounted) return;

    final startPos = _playheadPos;

    // Start playback muted so the user can record over the video
    _rebuild(() {
      _isPlaying = true;
      _recordingMuted = true;
    });
    _startAllFromPos(startPos); // fire-and-forget

    final path = await showVeRecordSheet(
      context: context,
      startOffset: startPos,
    );

    // Tear down muted playback
    _rebuild(() => _recordingMuted = false);
    await _stopPlayback();
    if (!mounted) return;

    if (path != null) {
      await _addAudioFromPath(path);
      // Reposition the new track so it starts where recording began
      if (_tracks.isNotEmpty) {
        final idx = _tracks.length - 1;
        _rebuild(() {
          _tracks[idx] = _tracks[idx].copyWith(startOffset: startPos);
        });
        _scheduleDraftSave();
      }
    }
  }

  Future<void> _openCameraRecorder() async {
    await _stopPlayback();
    if (!mounted) return;
    AppOpenAdManager.instance.suppressNextResume();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          onCapture: (picked) => _loadInitialMedia([picked]),
        ),
      ),
    );
  }

  Future<void> _addImageTrack() => _openMediaPicker(initialTab: 1);

  Future<void> _addTextTrack() async {
    await _stopPlayback();
    if (!mounted) return;
    _showTextEditDialog(isNew: true);
  }

  /// Loads a list of already-captured/selected files directly into the
  /// timeline without opening the media-picker UI.  Used by the camera flow.
  Future<void> _loadInitialMedia(List<PickedMediaFile> picks) async {
    if (picks.isEmpty || !mounted) return;
    const kImageDuration = Duration(seconds: 30);

    _pushUndo();

    for (final pick in picks) {
      if (pick.isVideo) {
        Duration duration = pick.duration;
        if (duration == Duration.zero) {
          try {
            final tmp = VideoPlayerController.file(File(pick.path));
            await tmp.initialize();
            duration = tmp.value.duration;
            await tmp.dispose();
          } catch (_) {}
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
        );

        final isFirst = _tracks.isEmpty;
        _rebuild(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }

        _getOrInitVideoController(track).then((_) {
          if (mounted) {
            _rebuild(() {});
            _updatePreviewForSeek(_playheadPos);
          }
        });

        await _extractThumbnails(track.id, pick.path);
      } else {
        // Image track
        final track = TimelineTrack(
          id: TimelineTrack.generateId(),
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          trackType: TrackType.image,
          duration: kImageDuration,
          startOffset: _playheadPos,
          color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        );

        final isFirst = _tracks.isEmpty;
        _rebuild(() {
          _tracks.add(track);
          _selectedIndex = _tracks.length - 1;
        });

        if (isFirst) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _autoZoomToFit();
          });
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Asset loading: thumbnails + waveforms
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _extractThumbnails(String trackId, String videoPath) async {
    if (!File(videoPath).existsSync()) return;
    const thumbCount = 12;
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) return;
    final duration = _tracks[idx].duration.inMilliseconds;
    if (duration <= 0) return;

    final tmpDir = await getTemporaryDirectory();
    final paths = <String>[];

    for (int i = 0; i < thumbCount; i++) {
      final timeMs = (duration * i / (thumbCount - 1)).round();
      final outPath = '${tmpDir.path}/thumb_${trackId}_$i.jpg';
      try {
        final path = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: outPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: timeMs,
          maxHeight: 200,
          quality: 90,
        );
        if (path != null) paths.add(path);
      } catch (e) {
        debugPrint('Thumbnail extraction failed at ${timeMs}ms: $e');
      }
    }

    if (!mounted) return;
    final currentIdx = _tracks.indexWhere((t) => t.id == trackId);
    if (currentIdx == -1) return;
    _rebuild(() {
      _tracks[currentIdx] =
          _tracks[currentIdx].copyWith(thumbnailPaths: paths);
    });
  }

  Future<void> _extractWaveform(String trackId, String audioPath) async {
    if (!File(audioPath).existsSync()) return;
    try {
      final result = await WaveformExtractor()
          .extractWaveform(audioPath, useCache: false);
      final rawSamples = result.waveformData;
      if (rawSamples.isEmpty || !mounted) return;

      final bars = rawSamples.length < 200 ? rawSamples.length : 200;
      if (bars == 0) return;
      final samplesPer = (rawSamples.length / bars).ceil().clamp(1, rawSamples.length);

      final processed = <double>[];
      for (int i = 0; i < bars; i++) {
        final start = i * samplesPer;
        final end = min(start + samplesPer, rawSamples.length);
        int peak = 0;
        for (int j = start; j < end; j++) {
          if (rawSamples[j].abs() > peak) peak = rawSamples[j].abs();
        }
        processed.add(peak.toDouble());
      }

      double globalPeak = processed.reduce(max);
      if (globalPeak == 0) globalPeak = 1;
      final normalized =
          processed.map((v) => (v / globalPeak).clamp(0.01, 1.0)).toList();

      if (!mounted) return;
      final idx = _tracks.indexWhere((t) => t.id == trackId);
      if (idx == -1) return;
      _rebuild(() {
        _tracks[idx] = _tracks[idx].copyWith(waveformBars: normalized);
      });
    } catch (e) {
      debugPrint('Waveform extraction error: $e');
    }
  }
}
