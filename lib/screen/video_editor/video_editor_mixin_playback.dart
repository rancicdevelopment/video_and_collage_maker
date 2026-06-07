part of 'video_editor_screen.dart';

const int _kMaxVideoControllers = 4;
const Duration _kTimerInterval = Duration(milliseconds: 16);

extension _VePlaybackExt on _VideoEditorScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  //  Audio player management
  // ─────────────────────────────────────────────────────────────────────────

  AudioPlayer _getAudioPlayer(String trackId) {
    return _audioPlayers.putIfAbsent(trackId, () {
      final player = AudioPlayer();
      player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
        iOS: AudioContextIOS(options: {AVAudioSessionOptions.mixWithOthers}),
      ));
      _audioSubs[trackId] = player.onPlayerComplete.listen((_) {
        player.setVolume(0.0);
      });
      return player;
    });
  }

  void _releaseAudioPlayer(String trackId) {
    _audioTimers.remove(trackId)?.cancel();
    _audioSubs.remove(trackId)?.cancel();
    _audioPlayers.remove(trackId)?.dispose();
  }

  void _cancelAudioTimers() {
    for (final t in _audioTimers.values) {
      t.cancel();
    }
    _audioTimers.clear();
  }

  void _stopAllAudio() {
    _cancelAudioTimers();
    for (final pl in _audioPlayers.values) {
      pl.stop();
    }
  }

  void _pauseAllAudio() {
    _cancelAudioTimers();
    for (final pl in _audioPlayers.values) {
      pl.pause();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Video controller management
  // ─────────────────────────────────────────────────────────────────────────

  Future<VideoPlayerController?> _getOrInitVideoController(
      TimelineTrack track) async {
    if (!track.isVideo) return null;
    if (_videoControllers.containsKey(track.id)) {
      return _videoControllers[track.id];
    }
    if (!File(track.filePath).existsSync()) return null;

    // Step 1: evict controllers for tracks that are NOT at the current playhead
    // and NOT within the lookahead window (upcoming clips we pre-initialized).
    // Keeping a short lookahead window prevents thrashing: a pre-initialized
    // future clip's controller won't be evicted when another init is requested.
    const kEvictLookahead = Duration(seconds: 8);
    final toEvict = _videoControllers.keys.where((id) {
      final t = _tracks.where((t) => t.id == id).firstOrNull;
      if (t == null) return true;
      // Keep clips currently overlapping the playhead.
      if (_playheadPos >= t.startOffset && _playheadPos < t.endTime) {
        return false;
      }
      // Keep upcoming clips within the lookahead window (pre-initialized).
      if (t.startOffset > _playheadPos &&
          t.startOffset - _playheadPos <= kEvictLookahead) {
        return false;
      }
      return true;
    }).toList();
    for (final id in toEvict) {
      _releaseVideoController(id);
    }

    // Step 2: if we're still at the cap, all remaining controllers are for
    // tracks genuinely overlapping the playhead — don't add another to avoid OOM.
    if (_videoControllers.length >= _kMaxVideoControllers) return null;

    // Priority: reverse preview → stabilizer preview → chromakey preview → raw file.
    final revPath  = _reversePreviewPaths[track.id];
    final stabPath = _stabPreviewPaths[track.id];
    final ckPath   = _chromakeyPreviewPaths[track.id];
    final videoFilePath = (revPath != null && File(revPath).existsSync())
        ? revPath
        : (stabPath != null && File(stabPath).existsSync())
            ? stabPath
            : (ckPath != null && File(ckPath).existsSync())
                ? ckPath
                : track.filePath;

    final controller = VideoPlayerController.file(
      File(videoFilePath),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _videoControllers[track.id] = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0.0); // volume set at playback start
      if (mounted) _rebuild(() {});
    } catch (e) {
      debugPrint('VideoController init failed for "${track.title}": $e');
      _videoControllers.remove(track.id);
      _playStartedIds.remove(track.id);
      controller.dispose();
      return null;
    }

    // If playback is active when this controller finishes initialising (e.g.
    // the controller was still being set up when the user pressed Play and was
    // therefore skipped by _startAllFromPos), seek it to the current position
    // and start it immediately so it doesn't show a frozen frame.
    if (mounted && _isPlaying && !_playStartedIds.contains(track.id)) {
      final idx = _tracks.indexOf(track);
      if (idx >= 0 &&
          _playheadPos >= track.startOffset &&
          _playheadPos < track.endTime) {
        final capturedGen = _playGen;
        _playStartedIds.add(track.id);
        final seekPos = _filePosFor(idx, _playheadPos);
        await controller.seekTo(seekPos);
        if (mounted && _isPlaying && _playGen == capturedGen) {
          await controller.setVolume(_muteVol(track.volume.clamp(0.0, 1.0)));
          await controller.play();
        }
      }
    }

    return _videoControllers[track.id];
  }

  void _releaseVideoController(String trackId) {
    _videoControllers.remove(trackId)?.dispose();
    _previewActiveTrackIds.remove(trackId);
    _playStartedIds.remove(trackId);
  }

  /// Update the preview to reflect all video and image tracks covering [pos].
  ///
  /// For video tracks: lazily initializes controllers that have entered the
  /// playhead range and triggers seek+play when a controller becomes ready
  /// while playback is active.
  /// For image tracks: no controller is needed — they're rendered directly by
  /// _buildPreviewContent from the file path.
  ///
  /// Calls setState when the set of active track IDs changes so the UI rebuilds.
  void _updatePreviewController(Duration pos) {
    final newIds = <String>[];
    for (final t in _tracks) {
      if (!t.isVideo && !t.isImage) continue;
      if (pos < t.startOffset || pos >= t.endTime) continue;

      newIds.add(t.id);

      if (t.isImage) continue; // No controller needed for images.

      // Video track: ensure its controller is initialised.
      final vc = _videoControllers[t.id];
      if (vc != null && vc.value.isInitialized) {
        // Already ready — nothing to do.
        // (Play is started by _getOrInitVideoController when init completes,
        // or by _startAllFromPos for controllers that were already initialised.)
      } else if (vc == null) {
        // Lazily init the controller for this track; evicts stale ones first.
        // Play is handled inside _getOrInitVideoController when init completes.
        _getOrInitVideoController(t).then((_) {
          if (!mounted) return;
          // Refresh the active-track list once the controller is ready.
          _updatePreviewController(_playheadPos);
        });
      }
    }

    if (newIds.join(',') == _previewActiveTrackIds.join(',')) return;

    _previewActiveTrackIds = newIds;
    if (mounted) _rebuild(() {});
  }

  Future<void> _startAllFromPos(Duration pos) async {
    _stopAllAudio();
    for (final vc in _videoControllers.values) {
      vc.pause();
    }
    _uiTimer?.cancel();

    // Pre-compute fade opacity at the starting position so there is no
    // single-frame flash before the first timer tick arrives.
    _syncFadeOpacityAt(pos);

    final gen = ++_playGen;
    // New play session — clear the set so controllers that finish initialising
    // after this point are detected as "not yet started" by _updatePreviewController.
    _playStartedIds.clear();
    _videoStallTick.clear();
    _lastVideoVolume.clear();
    _lastAudioVolume.clear();
    _playheadStartPos = pos;
    _stopwatch.reset();
    _stopwatch.start();

    _uiTimer = Timer.periodic(_kTimerInterval, (timer) {
      if (!mounted || _playGen != gen) {
        timer.cancel();
        return;
      }
      final newPos = _playheadStartPos + _stopwatch.elapsed;
      final contentEnd = _contentEndTime;
      if (newPos >= contentEnd) {
        timer.cancel();
        _stopwatch.stop();
        _stopAllAudio();
        for (final vc in _videoControllers.values) {
          vc.pause();
        }
        if (mounted) {
          _rebuild(() {
            _playheadPos = contentEnd;
            _isPlaying = false;
          });
        }
        return;
      }

      // Per-audio-track: stop ended clips + apply fades
      for (final track in _tracks) {
        if (!track.isAudio) continue;
        final pl = _audioPlayers[track.id];
        if (pl == null) continue;

        if (newPos > track.endTime) {
          if (pl.state == PlayerState.playing) {
            pl.setVolume(0.0);
            pl.stop();
          }
          continue;
        }

        if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) continue;
        if (pl.state != PlayerState.playing) continue;

        final elapsed = newPos - track.startOffset;
        if (elapsed < Duration.zero) continue;
        final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
        final elapsedSecs = elapsed.inMicroseconds / 1e6;
        final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);

        double fade = 1.0;
        if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
          final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
          final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        final newAudioVol = (track.volume * fade).clamp(0.0, 2.0);
        final lastAudioVol = _lastAudioVolume[track.id];
        if (lastAudioVol == null || (newAudioVol - lastAudioVol).abs() > 0.005) {
          _lastAudioVolume[track.id] = newAudioVol;
          pl.setVolume(_muteVol(newAudioVol));
        }
      }

      // Per-video-track: stop ended clips + apply volume/fades
      for (final track in _tracks) {
        if (!track.isVideo && !track.isImage) continue;

        if (track.isImage) {
          // Image tracks have no controller — just update fade opacity.
          if (newPos > track.endTime || newPos < track.startOffset) {
            _videoFadeOpacity.remove(track.id);
          } else if (track.fadeInSecs > 0 || track.fadeOutSecs > 0) {
            final elapsed = newPos - track.startOffset;
            final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
            final elapsedSecs = elapsed.inMicroseconds / 1e6;
            final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);
            double fade = 1.0;
            if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
              final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
              fade *= t * t * (3.0 - 2.0 * t);
            }
            if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
              final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
              fade *= t * t * (3.0 - 2.0 * t);
            }
            _videoFadeOpacity[track.id] = fade;
          } else {
            _videoFadeOpacity.remove(track.id);
          }
          continue;
        }

        final vc = _videoControllers[track.id];
        if (vc == null || !vc.value.isInitialized) continue;

        // Stop clips that have passed their end time.
        if (newPos > track.endTime) {
          if (vc.value.isPlaying) {
            vc.setVolume(0.0);
            vc.pause();
          }
          continue;
        }

        // Stall recovery: if the controller was started but stopped playing
        // unexpectedly (e.g. audio-focus conflict when two clips overlap, or a
        // platform-level stall), restart it after a debounce so we don't
        // hammer play() on every 16 ms tick.
        // Use a longer threshold (25 ticks ≈ 400 ms) to avoid a ping-pong
        // effect where multiple overlapping video controllers repeatedly steal
        // audio focus from each other, which causes audible stuttering.
        if (!vc.value.isPlaying) {
          if (_playStartedIds.contains(track.id)) {
            final stall = (_videoStallTick[track.id] ?? 0) + 1;
            _videoStallTick[track.id] = stall;
            if (stall >= 25) { // ~400 ms threshold
              _videoStallTick.remove(track.id);
              final hasVoiceAudio = track.voiceEffectIndex > 0 &&
                  _voicePreviewPaths.containsKey(track.id);
              final vol = hasVoiceAudio ? 0.0 : track.volume.clamp(0.0, 1.0);
              _lastVideoVolume[track.id] = vol;
              vc.setVolume(_muteVol(vol));
              vc.play(); // fire-and-forget
            }
          }
          continue;
        }
        _videoStallTick.remove(track.id);

        if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) {
          _videoFadeOpacity.remove(track.id);
          continue;
        }

        final elapsed = newPos - track.startOffset;
        if (elapsed < Duration.zero) continue;
        final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
        final elapsedSecs = elapsed.inMicroseconds / 1e6;
        final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);

        double fade = 1.0;
        if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
          final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
          final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
          fade *= t * t * (3.0 - 2.0 * t);
        }
        // Mute the VideoPlayerController when a voice-preview audio player
        // is handling audio for this track.
        final hasVoiceAudio = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        final newVideoVol =
            hasVoiceAudio ? 0.0 : (track.volume * fade).clamp(0.0, 1.0);
        final lastVideoVol = _lastVideoVolume[track.id];
        if (lastVideoVol == null || (newVideoVol - lastVideoVol).abs() > 0.005) {
          _lastVideoVolume[track.id] = newVideoVol;
          vc.setVolume(_muteVol(newVideoVol));
        }
        _videoFadeOpacity[track.id] = fade;
      }

      _rebuild(() => _playheadPos = newPos);
      _updatePreviewController(newPos);

      // Lookahead: pre-initialize controllers for video clips that are about
      // to start, so the controller is warm when the clip's time arrives.
      // Fire-and-forget; _getOrInitVideoController handles the cap and eviction.
      const kTimerLookahead = Duration(seconds: 5);
      for (final t in _tracks) {
        if (!t.isVideo) continue;
        if (_videoControllers.containsKey(t.id)) continue;
        if (t.startOffset <= newPos) continue; // already started or passed
        if (t.startOffset - newPos > kTimerLookahead) continue; // too far away
        _getOrInitVideoController(t); // fire-and-forget
      }
    });

    // Start audio tracks
    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isAudio) continue;
      if (pos > track.endTime) continue;

      final delay = track.startOffset - pos;
      final player = _getAudioPlayer(track.id);

      // Use voice-processed preview file if available, else original.
      final audioPath = _voicePreviewPaths[track.id] ?? track.filePath;

      if (delay <= Duration.zero) {
        try {
          final filePos = _filePosFor(i, pos);
          await player.setVolume(_muteVol(track.volume));
          await player.setPlaybackRate(track.speed);
          await player.play(DeviceFileSource(audioPath));
          if (_playGen != gen) return;
          await player.seek(filePos);
          if (_playGen != gen) return;
        } catch (e) {
          debugPrint('Audio play failed for "${track.title}": $e');
        }
      } else {
        final capturedId   = track.id;
        final capturedPath = audioPath;
        final capturedTrim = track.trimStart;
        final capturedVol  = track.volume;
        final capturedSpd  = track.speed;
        _audioTimers[capturedId] = Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          try {
            final pl = _getAudioPlayer(capturedId);
            await pl.setVolume(_muteVol(capturedVol));
            await pl.setPlaybackRate(capturedSpd);
            await pl.play(DeviceFileSource(capturedPath));
            if (_playGen != gen) return;
            await pl.seek(capturedTrim);
          } catch (e) {
            debugPrint('Delayed audio play failed for "$capturedId": $e');
          }
        });
      }
    }

    // Start voice-audio players for video tracks that have a voice effect.
    // The VideoPlayerController is muted (volume forced to 0 below) and a
    // separate AudioPlayer plays the FFmpeg-processed audio in its place.
    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isVideo) continue;
      if (track.voiceEffectIndex == 0) continue;
      final voicePath = _voicePreviewPaths[track.id];
      if (voicePath == null || !File(voicePath).existsSync()) continue;
      if (pos > track.endTime) continue;

      final delay  = track.startOffset - pos;
      final player = _getAudioPlayer('${track.id}_va');

      if (delay <= Duration.zero) {
        try {
          final filePos = _filePosFor(i, pos);
          await player.setVolume(_muteVol(track.volume));
          await player.play(DeviceFileSource(voicePath));
          if (_playGen != gen) return;
          await player.seek(filePos);
          if (_playGen != gen) return;
        } catch (e) {
          debugPrint('Video voice-audio play failed for "${track.title}": $e');
        }
      } else {
        final capturedId   = '${track.id}_va';
        final capturedPath = voicePath;
        final capturedTrim = _filePosFor(i, track.startOffset);
        final capturedVol  = track.volume;
        _audioTimers[capturedId] = Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          try {
            final pl = _getAudioPlayer(capturedId);
            await pl.setVolume(_muteVol(capturedVol));
            await pl.play(DeviceFileSource(capturedPath));
            if (_playGen != gen) return;
            await pl.seek(capturedTrim);
          } catch (e) {
            debugPrint('Delayed video voice-audio failed for "$capturedId": $e');
          }
        });
      }
    }

    // Start video tracks
    // Collect clips for immediate start and handle delayed ones separately.
    // For immediate clips: seek all in parallel, then play all in parallel so
    // that overlapping clips start as synchronised as possible.
    final immediateEntries = <({VideoPlayerController vc, Duration clipPos, double vol})>[];

    for (int i = 0; i < _tracks.length; i++) {
      if (_playGen != gen) return;
      final track = _tracks[i];
      if (!track.isVideo) continue;
      if (pos > track.endTime) continue;

      final delay = track.startOffset - pos;

      if (delay <= Duration.zero) {
        // Immediate clip — must be initialized already to play right now.
        final vc = _videoControllers[track.id];
        if (vc == null || !vc.value.isInitialized) continue;
        // Mark as started so _updatePreviewController won't restart it.
        _playStartedIds.add(track.id);
        final hasVoicePlayer = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        immediateEntries.add((
          vc: vc,
          clipPos: _filePosFor(i, pos),
          vol: hasVoicePlayer ? 0.0 : _muteVol(track.volume.clamp(0.0, 1.0)),
        ));
      } else {
        // Delayed clip — set up a timer regardless of whether the controller
        // is initialized yet.  Also kick off initialization now (fire-and-
        // forget) so the controller is warm by the time the timer fires.
        final capturedTrack = track;
        final capturedI = i;
        final hasVoicePlayerD = track.voiceEffectIndex > 0 &&
            _voicePreviewPaths.containsKey(track.id);
        final capturedVol =
            hasVoicePlayerD ? 0.0 : track.volume.clamp(0.0, 1.0);
        // Pre-initialize so it's ready when the delay elapses.
        _getOrInitVideoController(capturedTrack);
        Timer(delay, () async {
          if (!mounted || !_isPlaying || _playGen != gen) return;
          // Controller should already be initialized from the pre-init above.
          // If not (e.g., it was evicted or init failed), try once more.
          var ctrl = _videoControllers[capturedTrack.id];
          if (ctrl == null || !ctrl.value.isInitialized) {
            ctrl = await _getOrInitVideoController(capturedTrack);
          }
          if (ctrl == null || !ctrl.value.isInitialized) return;
          if (!mounted || !_isPlaying || _playGen != gen) return;
          // Mark as started before seeking so _updatePreviewController won't
          // also try to start this controller concurrently.
          _playStartedIds.add(capturedTrack.id);
          await ctrl.seekTo(_filePosFor(capturedI, _playheadPos));
          if (!mounted || !_isPlaying || _playGen != gen) return;
          await ctrl.setVolume(_muteVol(capturedVol));
          if (!mounted || !_isPlaying || _playGen != gen) return;
          await ctrl.play();
        });
      }
    }

    if (immediateEntries.isNotEmpty) {
      // Seek all overlapping clips in parallel.
      await Future.wait(
        immediateEntries.map((e) => e.vc.seekTo(e.clipPos)),
      );
      if (_playGen != gen) return;
      // Reset the stopwatch right before play() so that seek latency is not
      // counted as elapsed playback time — otherwise the playhead jumps ahead
      // of the actual video frames, causing visible sync drift or frozen frames.
      _stopwatch.reset();
      _stopwatch.start();
      // Set volume and play all overlapping clips in parallel.
      await Future.wait(
        immediateEntries.map((e) async {
          await e.vc.setVolume(_muteVol(e.vol));
          await e.vc.play();
        }),
      );
      if (_playGen != gen) return;
    }

    _updatePreviewController(pos);
  }

  /// Returns the current fade opacity for [trackId] in the preview panel.
  /// Uses the cached value from [_videoFadeOpacity] if available, otherwise
  /// computes it live so the build method never falls back to 1.0 by default.
  double _previewFadeOpacity(String? trackId) {
    if (trackId == null) return 1.0;
    final cached = _videoFadeOpacity[trackId];
    if (cached != null) return cached;
    final track = _tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return 1.0;
    return _computeFadeOpacity(track, _playheadPos);
  }

  /// Computes the fade opacity [0..1] for [track] at playhead position [pos].
  double _computeFadeOpacity(TimelineTrack track, Duration pos) {
    if (track.fadeInSecs <= 0 && track.fadeOutSecs <= 0) return 1.0;
    final elapsed = pos - track.startOffset;
    if (elapsed < Duration.zero) return 1.0;
    final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
    final elapsedSecs = elapsed.inMicroseconds / 1e6;
    final remainingSecs = (effSecs - elapsedSecs).clamp(0.0, effSecs);
    double fade = 1.0;
    if (track.fadeInSecs > 0 && elapsedSecs < track.fadeInSecs) {
      final t = (elapsedSecs / track.fadeInSecs).clamp(0.0, 1.0);
      fade *= t * t * (3.0 - 2.0 * t);
    }
    if (track.fadeOutSecs > 0 && remainingSecs < track.fadeOutSecs) {
      final t = (remainingSecs / track.fadeOutSecs).clamp(0.0, 1.0);
      fade *= t * t * (3.0 - 2.0 * t);
    }
    return fade;
  }

  /// Pre-populates [_videoFadeOpacity] for all video tracks at position [pos]
  /// so the preview shows the correct opacity immediately (no flash).
  void _syncFadeOpacityAt(Duration pos) {
    for (final track in _tracks) {
      if (!track.isVideo) continue;
      final fade = _computeFadeOpacity(track, pos);
      if (fade < 1.0) {
        _videoFadeOpacity[track.id] = fade;
      } else {
        _videoFadeOpacity.remove(track.id);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      _uiTimer?.cancel();
      _stopwatch.stop();
      _pauseAllAudio();
      for (final vc in _videoControllers.values) {
        vc.pause();
      }
      // Do NOT clear _videoFadeOpacity — keep the current fade so the
      // preview stays at the correct opacity while paused.
      _rebuild(() => _isPlaying = false);
    } else {
      if (_tracks.isEmpty) return;
      _syncFadeOpacityAt(_playheadPos);
      _rebuild(() => _isPlaying = true);
      await _startAllFromPos(_playheadPos);
    }
  }

  Future<void> _stopPlayback() async {
    _uiTimer?.cancel();
    _stopwatch.stop();
    _stopAllAudio();
    for (final vc in _videoControllers.values) {
      vc.pause();
    }
    _syncFadeOpacityAt(_playheadPos);
    _rebuild(() => _isPlaying = false);
  }

  /// Returns 0 when recording is active (all audio muted for clean capture).
  double _muteVol(double v) => _recordingMuted ? 0.0 : v;

  // ─────────────────────────────────────────────────────────────────────────
  //  Seek
  // ─────────────────────────────────────────────────────────────────────────

  void _seekVisualOnly(Duration newPos) {
    final end = _contentEndTime;
    final clamped = newPos.isNegative
        ? Duration.zero
        : (end > Duration.zero && newPos > end ? end : newPos);
    _playheadStartPos = clamped;
    if (_stopwatch.isRunning) _stopwatch.reset();
    _syncFadeOpacityAt(clamped);
    _rebuild(() => _playheadPos = clamped);
    _updatePreviewForSeek(clamped);
  }

  void _applySeek(Duration newPos) {
    final end = _contentEndTime;
    final clamped = newPos.isNegative
        ? Duration.zero
        : (end > Duration.zero && newPos > end ? end : newPos);
    _rebuild(() => _playheadPos = clamped);
    _updatePreviewForSeek(clamped);
    if (!_isPlaying) return;
    _startAllFromPos(clamped);
  }

  void _updatePreviewForSeek(Duration pos) {
    _updatePreviewController(pos);
    // Seek video controllers to show correct frame at new position.
    // Use _filePosFor so that trimStart and playback speed are respected.
    for (int i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      if (!track.isVideo) continue;
      final vc = _videoControllers[track.id];
      if (vc == null || !vc.value.isInitialized) continue;
      if (pos >= track.startOffset && pos < track.endTime) {
        vc.seekTo(_filePosFor(i, pos));
      }
    }
  }

  Duration _contentXToDuration(double contentX) {
    final maxSecs = _contentEndTime.inMilliseconds / 1000.0;
    final secs = (contentX / _pps).clamp(0.0, maxSecs > 0 ? maxSecs : _totalDuration.inSeconds.toDouble());
    return Duration(milliseconds: (secs * 1000).round());
  }
}
