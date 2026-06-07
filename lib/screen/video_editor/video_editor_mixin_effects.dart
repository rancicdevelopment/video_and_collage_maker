part of 'video_editor_screen.dart';

extension _VeEffectsExt on _VideoEditorScreenState {
  // ── Voice Effect ───────────────────────────────────────────────────────

  static String _voiceFilterFor(int index) {
    switch (index) {
      case 1: return 'aecho=0.8:0.88:60:0.4';
      case 2: return 'asetrate=55125,aresample=44100';
      case 3: return 'asetrate=49392,aresample=44100';
      case 4: return 'asetrate=38808,aresample=44100';
      case 5: return 'aecho=0.8:0.88:40|70|100:0.3|0.2|0.1';
      case 6: return 'tremolo=f=20:d=0.9,aecho=0.9:0.7:6:0.6';
      case 7: return 'asetrate=66150,aresample=44100,aecho=0.6:0.5:5:0.7';
      case 8: return 'asetrate=33075,aresample=44100,aecho=0.7:0.7:80:0.3';
      default: return '';
    }
  }

  Future<void> _generateVoicePreview(TimelineTrack track) async {
    if (track.voiceEffectIndex == 0) {
      _voicePreviewPaths.remove(track.id);
      return;
    }
    final filter = _voiceFilterFor(track.voiceEffectIndex);
    if (filter.isEmpty) return;

    final tmpDir = await getTemporaryDirectory();
    // Key includes effect index so switching effects regenerates the file.
    final outPath =
        '${tmpDir.path}/ve_vp_${track.id}_${track.voiceEffectIndex}.aac';

    // Reuse cached file if it already exists for this track+effect combo.
    if (File(outPath).existsSync()) {
      if (mounted) _rebuild(() => _voicePreviewPaths[track.id] = outPath);
      return;
    }

    // Remove any stale preview for a different effect on the same track.
    if (mounted) {
      _rebuild(() {
        _voicePreviewPaths.remove(track.id);
        _voicePreviewGenerating = true;
      });
    }

    // Process only the first 30 s — fast enough to finish in 2-3 s.
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', track.filePath,
      '-vn',
      '-t', '30',
      '-af', filter,
      '-c:a', 'aac',
      '-b:a', '128k',
      outPath,
    ]);
    final rc = await session.getReturnCode();
    if (mounted) {
      _rebuild(() {
        _voicePreviewGenerating = false;
        if (ReturnCode.isSuccess(rc)) {
          _voicePreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Voice preview gen failed for ${track.title}');
        }
      });
    }
  }

  // ── Chroma Key video preview generation ───────────────────────────────────
  // Processes the first 30 s of the track with the chromakey filter applied
  // over a black background, stores the result in _chromakeyPreviewPaths, and
  // reinitialises the VideoPlayerController so the editor preview shows the effect.
  Future<void> _generateChromakeyPreview(TimelineTrack track) async {
    if (!track.chromakeyEnabled || !track.isVideo) {
      // Effect removed — release preview and reinit with original file.
      _chromakeyPreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final c   = track.chromakeyColor;
    final rh  = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final gh  = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final bh  = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    final sim = track.chromakeySimilarity.toStringAsFixed(3);
    final bld = track.chromakeyBlend.toStringAsFixed(3);

    final tmpDir  = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/ck_video_${track.id}.mp4';

    if (mounted) {
      _rebuild(() {
        _chromakeyPreviewPaths.remove(track.id);
        _chromakeyPreviewGenerating = true;
      });
    }

    // Split input into background (black fill) + chromakeyed overlay, composite.
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '30',
      '-i', track.filePath,
      '-filter_complex',
      '[0:v]split[orig][copy];'
      '[orig]chromakey=color=0x$rh$gh$bh:similarity=$sim:blend=$bld[ck];'
      '[copy]drawbox=x=0:y=0:w=iw:h=ih:color=black@1:t=fill[bg];'
      '[bg][ck]overlay=format=auto[out]',
      '-map', '[out]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'copy',
      outPath,
    ]);

    final rc = await session.getReturnCode();
    if (mounted) {
      _rebuild(() {
        _chromakeyPreviewGenerating = false;
        if (ReturnCode.isSuccess(rc)) {
          _chromakeyPreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Chromakey preview gen failed for ${track.title}');
        }
      });
      // Force the controller to reinit using the processed video.
      _releaseVideoController(track.id);
    }
  }

  // ── Stabilizer video preview generation ──────────────────────────────────
  // 2-pass VidStab on the full track (capped at 60 s for speed). Stores the
  // processed clip in _stabPreviewPaths and reinitialises the controller so
  // the editor preview shows the stabilised result immediately after toggle.
  Future<void> _generateStabPreview(TimelineTrack track) async {
    if (!track.isStabilized || !track.isVideo) {
      // Stabilization removed — release preview and reinit with original.
      _stabPreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final tmpDir  = await getTemporaryDirectory();
    final trfPath = '${tmpDir.path}/stab_${track.id}.trf';
    final outPath = '${tmpDir.path}/stab_video_${track.id}.mp4';

    if (mounted) {
      _rebuild(() {
        _stabPreviewPaths.remove(track.id);
        _stabPreviewGenerating = true;
      });
    }

    // Pass 1: analyse camera motion.
    final pass1 = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '60',
      '-i', track.filePath,
      '-vf', 'vidstabdetect=stepsize=6:shakiness=8:accuracy=9:result=$trfPath',
      '-f', 'null', '/dev/null',
    ]);

    final rc1 = await pass1.getReturnCode();
    if (!mounted || !ReturnCode.isSuccess(rc1)) {
      if (mounted) _rebuild(() => _stabPreviewGenerating = false);
      debugPrint('Stabilizer pass-1 failed for ${track.title}');
      return;
    }

    // Pass 2: apply stabilisation + mild sharpening to compensate for crop.
    final pass2 = await FFmpegKit.executeWithArguments([
      '-y',
      '-t', '60',
      '-i', track.filePath,
      '-vf',
      'vidstabtransform=input=$trfPath:zoom=1:smoothing=10'
      ',unsharp=5:5:-0.8:3:3:-0.4',
      '-map', '0:v',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'copy',
      outPath,
    ]);

    final rc2 = await pass2.getReturnCode();
    if (mounted) {
      _rebuild(() {
        _stabPreviewGenerating = false;
        if (ReturnCode.isSuccess(rc2)) {
          _stabPreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Stabilizer pass-2 failed for ${track.title}');
        }
      });
      // Force controller to reinit using the stabilised clip.
      _releaseVideoController(track.id);
    }
  }

  // Runs FFmpeg `reverse` on the trimmed segment (capped at 60 s for speed),
  // stores the result in _reversePreviewPaths, and reinitialises the controller
  // so the preview shows the reversed clip immediately after toggle.
  Future<void> _generateReversePreview(TimelineTrack track) async {
    if (!track.playBackwards || !track.isVideo) {
      // Reverse removed — release preview and reinit with original file.
      _reversePreviewPaths.remove(track.id);
      _releaseVideoController(track.id);
      return;
    }

    final tmpDir  = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/reverse_video_${track.id}.mp4';

    if (mounted) {
      _rebuild(() {
        _reversePreviewPaths.remove(track.id);
        _reversePreviewGenerating = true;
      });
    }

    final ts = track.trimStart.inMicroseconds / 1e6;
    final rawDur = track.duration - track.trimStart - track.trimEnd;
    // Cap at 60 s so the preview renders quickly on mobile.
    final capSecs = (rawDur.inMicroseconds / 1e6).clamp(0.1, 60.0);

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', ts.toStringAsFixed(3),
      '-t',  capSecs.toStringAsFixed(3),
      '-i',  track.filePath,
      '-vf', 'reverse',
      '-an',             // skip audio — avoids areverse errors on silent clips
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      outPath,
    ]);

    final rc = await session.getReturnCode();
    if (mounted) {
      _rebuild(() {
        _reversePreviewGenerating = false;
        if (ReturnCode.isSuccess(rc)) {
          _reversePreviewPaths[track.id] = outPath;
        } else {
          debugPrint('Reverse preview failed for ${track.title}');
        }
      });
      // Force controller to reinit using the reversed clip.
      _releaseVideoController(track.id);
    }
  }

  void _showVoiceDialog() {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isAudio && !track.isVideo) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeVoiceDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        // Kick off preview audio generation so playback uses the effect.
        _generateVoicePreview(_tracks[idx]);
      },
      onCancel: () {
        _rebuild(() => _tracks[idx] = snapshot[idx]);
        _voicePreviewPaths.remove(track.id);
      },
    );
  }

  // ── Chroma Key / Green Screen ──────────────────────────────────────────
  void _showChromakeyDialog() {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeChromakeyDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
      onConfirm: (finalTrack) {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        _rebuild(() => _tracks[idx] = finalTrack);
        _stopPlayback();
        _generateChromakeyPreview(finalTrack);
      },
      onCancel: () {
        _rebuild(() => _tracks[idx] = snapshot[idx]);
        _chromakeyPreviewPaths.remove(track.id);
        _releaseVideoController(track.id);
      },
    );
  }

  // ── Stabilizer ─────────────────────────────────────────────────────────
  void _toggleStabilizer() {
    if (_selectedIndex == null) return;
    if (_stabPreviewGenerating) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo) return;
    _pushUndo();
    final newTrack = track.copyWith(isStabilized: !track.isStabilized);
    _rebuild(() {
      _tracks[_selectedIndex!] = newTrack;
    });
    _stopPlayback();
    // Kick off 2-pass VidStab preview (or release preview if toggled off).
    _generateStabPreview(newTrack);
  }

  Future<void> _showEqSheet() async {
    if (_selectedIndex == null) return;
    final idx   = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isAudio) return;

    await _stopPlayback();
    if (!mounted) return;

    await showVeEqSheet(
      context: context,
      track: track,
      onApplied: (tempPath, gains) {
        _pushUndo();
        _releaseAudioPlayer(track.id);
        final savedOriginal = track.preEqFilePath ?? track.filePath;
        final updated = track.copyWith(
          filePath: tempPath,
          duration: track.effectiveDuration,
          trimStart: Duration.zero,
          trimEnd: Duration.zero,
          eqApplied: true,
          preEqFilePath: savedOriginal,
          eqGains: gains,
        );
        _rebuild(() => _tracks[idx] = updated);
        _extractWaveform(updated.id, tempPath);
      },
      onRestored: () {
        _pushUndo();
        final origPath = track.preEqFilePath!;
        _releaseAudioPlayer(track.id);
        final restored = track.copyWith(
          filePath: origPath,
          duration: track.duration,
          trimStart: Duration.zero,
          trimEnd: Duration.zero,
          eqApplied: false,
          preEqFilePath: null,
          eqGains: null,
        );
        _rebuild(() => _tracks[idx] = restored);
        _extractWaveform(restored.id, origPath);
      },
    );
  }

  void _showVolumeDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeVolumeDialog(
      context: context,
      track: track,
      onSetVolume: (v) {
        if (track.isVideo) { _videoControllers[track.id]?.setVolume(v.clamp(0.0, 1.0)); }
        else { _audioPlayers[track.id]?.setVolume(v); }
      },
      onApply: (v) {
        _pushUndo();
        _rebuild(() => _tracks[idx] = _tracks[idx].copyWith(volume: v));
        if (track.isVideo) { _videoControllers[track.id]?.setVolume(v.clamp(0.0, 1.0)); }
        else { _audioPlayers[track.id]?.setVolume(v); }
      },
    );
  }

  void _showSpeedDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeSpeedDialog(
      context: context,
      track: track,
      onSetSpeed: (v) {
        if (track.isVideo) { _videoControllers[track.id]?.setPlaybackSpeed(v); }
        else { _audioPlayers[track.id]?.setPlaybackRate(v); }
      },
      onApply: (v) {
        _pushUndo();
        _rebuild(() => _tracks[idx] = _tracks[idx].copyWith(speed: v));
        if (track.isVideo) { _videoControllers[track.id]?.setPlaybackSpeed(v); }
        else { _audioPlayers[track.id]?.setPlaybackRate(v); }
      },
    );
  }

  void _showFadeDialog({required bool isFadeIn}) {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    showVeFadeDialog(
      context: context,
      track: track,
      isFadeIn: isFadeIn,
      onLiveUpdate: (v) => _rebuild(() {
        _tracks[idx] = isFadeIn
            ? _tracks[idx].copyWith(fadeInSecs: v)
            : _tracks[idx].copyWith(fadeOutSecs: v);
      }),
      onConfirm: _pushUndo,
      onCancel: () => _rebuild(() => _tracks[idx] = track),
    );
  }

  void _showOpacityDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    showVeOpacityDialog(
      context: context,
      track: track,
      onLiveUpdate: (v) =>
          _rebuild(() => _tracks[idx] = _tracks[idx].copyWith(opacity: v)),
      onConfirm: _pushUndo,
      onCancel: () => _rebuild(() => _tracks[idx] = track),
    );
  }

  // ── Filters bottom sheet ─────────────────────────────────────────────────
  void _showFiltersDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeFiltersDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        _rebuild(() {});
        _stopPlayback();
      },
      onCancel: () => _rebuild(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Shadow / glow — see video_editor_glow_shadow_dialog.dart ──────────────
  void _showGlowShadowDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeGlowShadowDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        _rebuild(() {});
        _stopPlayback();
      },
      onCancel: () => _rebuild(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Mask — see video_editor_mask_dialog.dart ──────────────────────────────
  void _showMaskDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);
    showVeMaskDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        _rebuild(() {});
        _stopPlayback();
      },
      onCancel: () => _rebuild(() => _tracks[idx] = snapshot[idx]),
    );
  }

  // ── Transition dialog ────────────────────────────────────────────────────
  void _showTransitionDialog() {
    if (_selectedIndex == null) return;
    final idx = _selectedIndex!;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    final snapshot = List<TimelineTrack>.from(_tracks);

    // Start looping transition preview animation
    _transitionAnimTimer?.cancel();
    _rebuild(() {
      _transitionPreviewActive = true;
      _transitionPreviewType = track.transitionInType;
      _transitionAnimProgress = 0.0;
    });

    int ticks = 0;
    _transitionAnimTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        ticks++;
        // Loop: 0→1 over 1.4s, then hold at 0 for 0.2s before repeating
        final raw = (ticks * 16 / 1400.0) % 1.2;
        final progress = (raw / 1.0).clamp(0.0, 1.0);
        if (mounted) _rebuild(() => _transitionAnimProgress = progress);
      },
    );

    showVeTransitionsDialog(
      context: context,
      track: track,
      onLiveUpdate: (t) {
        _rebuild(() {
          _tracks[idx] = t;
          _transitionPreviewType = t.transitionInType;
        });
      },
      onConfirm: () {
        _undoStack.add(snapshot);
        _redoStack.clear();
        _scheduleDraftSave();
        _rebuild(() {});
      },
      onCancel: () => _rebuild(() => _tracks[idx] = snapshot[idx]),
    ).then((_) {
      _transitionAnimTimer?.cancel();
      _transitionAnimTimer = null;
      if (mounted) {
        _rebuild(() {
          _transitionPreviewActive = false;
          _transitionAnimProgress = 0.0;
          _transitionPreviewType = TransitionType.none;
        });
      }
    });
  }

  // ── Open crop screen ─────────────────────────────────────────────────────
  void _openCropScreen() {
    final idx = _selectedIndex;
    if (idx == null) return;
    final track = _tracks[idx];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoCropScreen(
        track: track,
        onApply: (cx, cy, cw, ch, rot) {
          if (!mounted) return;
          _rebuild(() {
            _tracks[idx] = _tracks[idx].copyWith(
              cropX: cx,
              cropY: cy,
              cropW: cw,
              cropH: ch,
              cropRotation: rot,
            );
          });
          _scheduleDraftSave();
        },
      ),
    ));
  }

  void _showScaleDialog() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    showVeScaleDialog(
      context: context,
      track: track,
      onApply: (v) {
        _pushUndo();
        final idx = _selectedIndex!;
        _rebuild(() => _tracks[idx] = _tracks[idx].copyWith(overlayScale: v));
      },
    );
  }

  void _resetOverlayPosition() {
    if (_selectedIndex == null) return;
    final track = _tracks[_selectedIndex!];
    if (!track.isVideo && !track.isImage) return;
    _pushUndo();
    _rebuild(() {
      _tracks[_selectedIndex!] = _tracks[_selectedIndex!].copyWith(
        overlayX: 0.0,
        overlayY: 0.0,
      );
    });
  }

  /// Max height for bottom sheet popups — stays below the video preview panel.
  double get _sheetMaxHeight {
    final mq = MediaQuery.of(context);
    const double kBannerH = 50;
    return (mq.size.height - mq.padding.top - kToolbarHeight - kBannerH - _previewHeight)
        .clamp(200.0, double.infinity);
  }

  void _showTextEditDialog({required bool isNew}) {
    final existingIdx = isNew ? null : _selectedIndex;
    if (!isNew && existingIdx == null) return;

    if (isNew) {
      final snapshot = List<TimelineTrack>.from(_tracks);
      final isFirstTrack = _tracks.isEmpty;
      final newTrack = TimelineTrack(
        id: TimelineTrack.generateId(),
        filePath: '',
        title: 'Text',
        trackType: TrackType.text,
        duration: const Duration(seconds: 30),
        startOffset: _playheadPos,
        color: kVeTrackColors[_tracks.length % kVeTrackColors.length],
        textContent: '',
        fontSize: 48.0,
        textColor: Colors.white,
        textBgColor: Colors.black,
        textBgOpacity: 0.0,
        textBold: false,
        textItalic: false,
        overlayX: 0.0,
        overlayY: 0.0,
      );
      _rebuild(() {
        _tracks.add(newTrack);
        _selectedIndex = _tracks.length - 1;
      });
      final trackIdx = _tracks.length - 1;
      if (isFirstTrack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoZoomToFit();
        });
      }
      showVeTextEditDialog(
        context: context,
        baseTrack: newTrack,
        maxHeight: _sheetMaxHeight,
        onLiveUpdate: (t) => _rebuild(() => _tracks[trackIdx] = t),
        onConfirm: () {
          _undoStack.add(snapshot);
          _redoStack.clear();
          _scheduleDraftSave();
          _rebuild(() {});
        },
        onCancel: () => _rebuild(() {
          _tracks.removeLast();
          _selectedIndex = _tracks.isEmpty ? null : _tracks.length - 1;
        }),
      );
    } else {
      final idx = existingIdx!;
      final snapshot = List<TimelineTrack>.from(_tracks);
      showVeTextEditDialog(
        context: context,
        baseTrack: _tracks[idx],
        maxHeight: _sheetMaxHeight,
        onLiveUpdate: (t) => _rebuild(() => _tracks[idx] = t),
        onConfirm: () {
          _undoStack.add(snapshot);
          _redoStack.clear();
          _scheduleDraftSave();
          _rebuild(() {});
        },
        onCancel: () => _rebuild(() => _tracks[idx] = snapshot[idx]),
      );
    }
  }
}
