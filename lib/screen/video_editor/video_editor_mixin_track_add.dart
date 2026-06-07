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

    // Show processing dialog while we resolve durations.
    // Tracks appear in the timeline immediately; thumbnails load in background.
    final videoCount = picks.where((p) => p.isVideo).length;
    if (videoCount > 0 && mounted) {
      _showImportProgress(current: 0, total: videoCount);
    }

    _pushUndo();
    const kImageDuration = Duration(seconds: 30);
    int processedVideos = 0;

    for (final pick in picks) {
      if (pick.isVideo) {
        // ── Resolve duration via FFprobe (fast — reads container metadata only,
        //    no video decoder / texture registration needed).
        Duration duration = pick.duration;
        if (duration == Duration.zero) {
          duration = await _probeDuration(pick.path);
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
          // Thumbnails will load in background; show loading shimmer until then.
          thumbnailsLoading: true,
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

        // Fire-and-forget: does not block adding the next track.
        _extractThumbnails(track.id, pick.path);

        processedVideos++;
        if (mounted && processedVideos < videoCount) {
          _showImportProgress(current: processedVideos, total: videoCount);
        }
      } else {
        // Image track — added instantly, no background work needed.
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

    // Dismiss the progress dialog once all tracks are in the timeline.
    if (videoCount > 0 && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Shows (or updates) an import-progress dialog.
  /// Pops any existing dialog before pushing a new one so updates are seamless.
  void _showImportProgress({required int current, required int total}) {
    if (!mounted) return;
    // Pop a previous version of this dialog if already showing.
    if (current > 0) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111E2F),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00C8FF)),
            const SizedBox(height: 16),
            Text(
              total == 1
                  ? 'Adding video…'
                  : 'Adding video ${current + 1} of $total…',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'Thumbnails will load in the background.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Uses FFprobe to read the container duration without initialising a
  /// VideoPlayerController (much faster — no decoder / texture allocation).
  Future<Duration> _probeDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info    = session.getMediaInformation();
      final durStr  = info?.getDuration(); // seconds as decimal string
      if (durStr != null) {
        final secs = double.tryParse(durStr);
        if (secs != null && secs > 0) {
          return Duration(microseconds: (secs * 1e6).round());
        }
      }
    } catch (e) {
      debugPrint('FFprobe duration failed, falling back to VideoPlayerController: $e');
    }
    // Fallback: full VideoPlayerController init (original behaviour).
    try {
      final tmp = VideoPlayerController.file(File(path));
      await tmp.initialize();
      final dur = tmp.value.duration;
      await tmp.dispose();
      return dur;
    } catch (_) {}
    return Duration.zero;
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
          duration = await _probeDuration(pick.path);
        }

        final track = TimelineTrack.fromFile(
          filePath: pick.path,
          title: p.basenameWithoutExtension(pick.path),
          duration: duration,
          trackType: TrackType.video,
          colorIndex: _tracks.length,
          startOffset: _playheadPos,
          thumbnailsLoading: true,
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

        _extractThumbnails(track.id, pick.path); // fire-and-forget
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

  /// Extracts filmstrip thumbnails for [trackId] in the background.
  ///
  /// • Uses adaptive count + quality based on video duration to keep extraction
  ///   time manageable even for 1-hour videos.
  /// • Updates the track progressively (every few thumbnails) so the filmstrip
  ///   fills in visually instead of appearing all at once.
  /// • Sets [thumbnailsLoading] = false when done (or if an error occurs).
  Future<void> _extractThumbnails(String trackId, String videoPath) async {
    if (!File(videoPath).existsSync()) {
      _markThumbsDone(trackId);
      return;
    }

    final initIdx = _tracks.indexWhere((t) => t.id == trackId);
    if (initIdx == -1) return;
    final durationMs = _tracks[initIdx].duration.inMilliseconds;
    if (durationMs <= 0) {
      _markThumbsDone(trackId);
      return;
    }

    // Adaptive settings: fewer / lower-quality thumbs for longer videos.
    final durationSecs = durationMs / 1000.0;
    final int thumbCount;
    final int quality;
    final int maxHeight;
    if (durationSecs < 60) {
      thumbCount = 12; quality = 75; maxHeight = 120;
    } else if (durationSecs < 300) {
      thumbCount = 14; quality = 65; maxHeight = 100;
    } else {
      thumbCount = 16; quality = 55; maxHeight = 80;
    }

    final tmpDir = await getTemporaryDirectory();
    final paths  = <String>[];

    for (int i = 0; i < thumbCount; i++) {
      if (!mounted) break;
      // Check the track still exists (user might have deleted it).
      if (_tracks.indexWhere((t) => t.id == trackId) == -1) return;

      final timeMs = thumbCount == 1
          ? 0
          : (durationMs * i / (thumbCount - 1)).round();
      final outPath = '${tmpDir.path}/thumb_${trackId}_$i.jpg';
      try {
        final path = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: outPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: timeMs,
          maxHeight: maxHeight,
          quality: quality,
        );
        if (path != null) paths.add(path);
      } catch (e) {
        debugPrint('Thumbnail at ${timeMs}ms failed: $e');
      }

      // Progressive update: refresh UI every 4 thumbnails so the filmstrip
      // visually fills in left-to-right without hammering setState.
      if (paths.isNotEmpty && (paths.length % 4 == 0)) {
        if (!mounted) break;
        final ci = _tracks.indexWhere((t) => t.id == trackId);
        if (ci != -1) {
          _rebuild(() {
            _tracks[ci] = _tracks[ci].copyWith(thumbnailPaths: List.from(paths));
          });
        }
      }
    }

    _markThumbsDone(trackId, paths: paths);
  }

  void _markThumbsDone(String trackId, {List<String>? paths}) {
    if (!mounted) return;
    final ci = _tracks.indexWhere((t) => t.id == trackId);
    if (ci == -1) return;
    _rebuild(() {
      _tracks[ci] = _tracks[ci].copyWith(
        thumbnailPaths: paths ?? _tracks[ci].thumbnailPaths,
        thumbnailsLoading: false,
      );
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
