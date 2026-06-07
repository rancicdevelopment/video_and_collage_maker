part of 'video_editor_screen.dart';

extension _VePreviewExt on _VideoEditorScreenState {
  Widget _buildPreviewContent() {
    return LayoutBuilder(builder: (context, constraints) {
      final cw = constraints.maxWidth;
      final ch = constraints.maxHeight;
      return _buildPreviewLayers(cw, ch);
    });
  }

  /// Returns the content widget of the most recent video/image track that
  /// ended at or before [incoming.startOffset], to be used as the outgoing
  /// frame during a transition.  Returns null when there is no such track.
  Widget? _buildOutgoingContent(TimelineTrack incoming) {
    // Find the last video/image track that STARTS before the incoming track.
    // Using startOffset (not endTime) avoids missing adjacent clips where
    // endTime == incoming.startOffset due to Duration precision.
    TimelineTrack? prev;
    for (final t in _tracks) {
      if (t.id == incoming.id) continue;
      if (!t.isVideo && !t.isImage) continue;
      if (t.startOffset >= incoming.startOffset) continue;
      if (prev == null || t.startOffset > prev.startOffset) prev = t;
    }
    if (prev == null) return null;

    if (prev.isVideo) {
      final vc = _videoControllers[prev.id];

      // Prefer the live VideoPlayerController — it holds the exact last frame
      // that was playing, so there is no visible freeze or snap at the
      // transition start.  The thumbnail is only a fallback for when the
      // controller is not yet initialised.
      if (vc != null && vc.value.isInitialized) {
        Widget w = AspectRatio(
          aspectRatio: vc.value.aspectRatio,
          child: VideoPlayer(vc),
        );
        if (prev.hasColorMatrix) {
          w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
        }
        if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
        return Container(color: Colors.black, child: Center(child: w));
      }

      // Fallback: last filmstrip thumbnail.
      final thumb = prev.thumbnailPaths.isNotEmpty
          ? prev.thumbnailPaths.last
          : null;
      if (thumb != null) {
        Widget w = Image.file(File(thumb), fit: BoxFit.cover);
        if (prev.hasColorMatrix) {
          w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
        }
        if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
        return Container(color: Colors.black, child: Center(child: w));
      }
      return null;
    }

    if (prev.isImage) {
      // Images in the live preview use BoxFit.contain — match that here.
      Widget w = Image.file(File(prev.filePath), fit: BoxFit.contain,
          cacheWidth: 1920);
      if (prev.hasColorMatrix) {
        w = ColorFiltered(colorFilter: prev.colorFilter, child: w);
      }
      if (prev.mirrorH) w = Transform.scale(scaleX: -1, child: w);
      return Container(color: Colors.black, child: Center(child: w));
    }

    return null;
  }

  Widget _buildPreviewLayers(double cw, double ch, {bool interactive = true}) {
    // Build the preview by iterating _tracks in order so that z-ordering
    // matches the timeline (first track = bottom layer, last = top layer).
    final layers = <Widget>[];
    for (final t in _tracks) {
      if (_playheadPos < t.startOffset || _playheadPos >= t.endTime) continue;

      Widget? content;
      if (t.isVideo) {
        final vc = _videoControllers[t.id];
        if (vc == null || !vc.value.isInitialized) continue;
        final fadeOpacity = _previewFadeOpacity(t.id);
        Widget videoWidget = AspectRatio(
          aspectRatio: vc.value.aspectRatio,
          child: VideoPlayer(vc),
        );
        if (t.hasColorMatrix) {
          videoWidget = ColorFiltered(
            colorFilter: t.colorFilter,
            child: videoWidget,
          );
        }
        if (t.blurRadius > 0.0) {
          videoWidget = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: t.blurRadius,
              sigmaY: t.blurRadius,
              tileMode: TileMode.clamp,
            ),
            child: videoWidget,
          );
        }
        Widget rotatedVideo = _applyRotationForPreview(t.rotation, videoWidget);
        if (t.mirrorH) {
          rotatedVideo = Transform.scale(scaleX: -1.0, child: rotatedVideo);
        }
        if (t.hasShadow) {
          rotatedVideo = DecoratedBox(
            decoration: BoxDecoration(boxShadow: [t.boxShadow]),
            child: rotatedVideo,
          );
        }
        Widget videoContent = Center(child: rotatedVideo);
        if (t.grainStrength > 0.0 || t.vignetteStrength > 0.0) {
          videoContent = Stack(children: [
            videoContent,
            if (t.grainStrength > 0.0)
              Positioned.fill(
                child: VeGrainOverlay(strength: t.grainStrength),
              ),
            if (t.vignetteStrength > 0.0)
              Positioned.fill(child: _buildVignetteOverlay(t.vignetteStrength)),
          ]);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: videoContent,
        );
      } else if (t.isImage) {
        final fadeOpacity = _previewFadeOpacity(t.id);
        Widget imageWidget = Image.file(
          File(t.filePath),
          fit: BoxFit.contain,
          cacheWidth: 1920,
        );
        if (t.hasColorMatrix) {
          imageWidget = ColorFiltered(
            colorFilter: t.colorFilter,
            child: imageWidget,
          );
        }
        if (t.blurRadius > 0.0) {
          imageWidget = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: t.blurRadius,
              sigmaY: t.blurRadius,
              tileMode: TileMode.clamp,
            ),
            child: imageWidget,
          );
        }
        Widget rotatedImage = _applyRotationForPreview(t.rotation, imageWidget);
        if (t.mirrorH) {
          rotatedImage = Transform.scale(scaleX: -1.0, child: rotatedImage);
        }
        if (t.hasShadow) {
          rotatedImage = DecoratedBox(
            decoration: BoxDecoration(boxShadow: [t.boxShadow]),
            child: rotatedImage,
          );
        }
        Widget imageContent = Center(child: rotatedImage);
        if (t.grainStrength > 0.0 || t.vignetteStrength > 0.0) {
          imageContent = Stack(children: [
            imageContent,
            if (t.grainStrength > 0.0)
              Positioned.fill(
                child: VeGrainOverlay(strength: t.grainStrength),
              ),
            if (t.vignetteStrength > 0.0)
              Positioned.fill(child: _buildVignetteOverlay(t.vignetteStrength)),
          ]);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: imageContent,
        );
      }
      else if (t.isText) {
        final fadeOpacity = _previewFadeOpacity(t.id);
        final blendMode =
            kVeTextBlendModes[t.textBlendModeIndex.clamp(0, kVeTextBlendModes.length - 1)].mode;
        final isTextSelected = interactive &&
            _selectedIndex != null &&
            _tracks[_selectedIndex!].id == t.id;
        Widget textW = Center(child: _buildTextWidget(t, selected: isTextSelected));
        if (blendMode != BlendMode.srcOver) {
          textW = VeBlendLayer(blendMode: blendMode, child: textW);
        }
        content = Opacity(
          opacity: (t.opacity * fadeOpacity).clamp(0.0, 1.0),
          child: textW,
        );
      }
      if (content == null) continue;

      // Apply crop for video/image tracks.
      if (t.hasCrop && !t.isText) {
        content = _applyCropForPreview(content, t);
      }

      // Apply mask for video/image tracks (after crop, before overlay transforms).
      if (t.hasMask && !t.isText) {
        content = _applyMaskForPreview(content, t);
      }

      // Status badges — shown as small overlay labels in the preview corner.
      if (!t.isText) {
        final badges = <Widget>[];
        if (t.playBackwards) {
          badges.add(_previewBadge('⏪ REVERSE', Colors.orange));
        }
        if (t.isStabilized) {
          badges.add(_previewBadge('⚡ STABILIZED', const Color(0xFF00C8FF)));
        }
        if (t.chromakeyEnabled) {
          badges.add(_previewBadge('🎬 GREEN SCR', const Color(0xFF00D26A)));
        }
        if (t.voiceEffectIndex > 0) {
          const names = ['', 'HALL', 'GIRL', 'WOMAN', 'BOY', 'MULTIPLE', 'ROBOT', 'ALIEN', 'FOREIGNER'];
          final n = names[t.voiceEffectIndex.clamp(0, names.length - 1)];
          badges.add(_previewBadge('🎙 $n', const Color(0xFF1E88E5)));
        }
        if (badges.isNotEmpty) {
          content = Stack(children: [
            content,
            Positioned(
              top: 6, left: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: badges,
              ),
            ),
          ]);
        }
      }

      // Apply overlay scale + position transforms.
      // overlayScale < 1.0 shrinks the clip; overlayX/Y shift the center.
      // canvasScale maps the reference canvas height to the actual canvas height
      // so that text/overlay sizes are consistent across all preview sizes and export.
      final isSelected = interactive &&
          _selectedIndex != null &&
          _tracks[_selectedIndex!].id == t.id;
      final canvasScale = t.isText ? ch / kVeRefCanvasH : 1.0;
      final transformedContent = Transform.translate(
        offset: Offset(t.overlayX * cw / 2, t.overlayY * ch / 2),
        child: Transform.scale(
          scale: t.overlayScale * canvasScale,
          child: content,
        ),
      );

      Widget layer;
      if (isSelected) {
        // Selected track: pan (1 finger) moves, pinch (2 fingers) scales+rotates.
        // Tap detection is done in onScaleEnd (no movement/scale = tap) so that
        // onTap never competes with ScaleGestureRecognizer and causes delay.
        layer = Positioned.fill(
          key: ValueKey('drag_${t.id}'),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (details) {
              _canvasTapDownPosition = details.localFocalPoint;
              if (_selectedIndex == null) return;
              final idx = _selectedIndex!;
              _overlayBaseScale = _tracks[idx].overlayScale;
              _overlayBaseRotation = _tracks[idx].textRotation;
              // Capture undo snapshot before gesture modifies the track.
              _undoStack.add(List<TimelineTrack>.from(_tracks));
              _redoStack.clear();
            },
            onScaleUpdate: (details) {
              if (_selectedIndex == null) return;
              final idx = _selectedIndex!;
              if (details.pointerCount == 1) {
                // Single finger: pan
                final dx = details.focalPointDelta.dx / (cw / 2);
                final dy = details.focalPointDelta.dy / (ch / 2);
                _rebuild(() {
                  _tracks[idx] = _tracks[idx].copyWith(
                    overlayX: (_tracks[idx].overlayX + dx).clamp(-1.0, 1.0),
                    overlayY: (_tracks[idx].overlayY + dy).clamp(-1.0, 1.0),
                  );
                });
              } else {
                // Two fingers: pinch to scale + rotate
                final newScale = (_overlayBaseScale * details.scale).clamp(0.2, 5.0);
                final newRotation = _overlayBaseRotation + details.rotation * 180.0 / pi;
                _rebuild(() {
                  _tracks[idx] = _tracks[idx].copyWith(
                    overlayScale: newScale,
                    textRotation: newRotation,
                  );
                });
              }
            },
            onScaleEnd: (details) {
              // If focal point barely moved and scale/rotation unchanged → treat as tap.
              final tapPos = _canvasTapDownPosition;
              if (tapPos == null) return;
              final moved = details.velocity.pixelsPerSecond.distance;
              if (moved > 200) { _scheduleDraftSave(); return; } // real drag → save
              // Check if scale or rotation changed (two-finger gesture).
              if (_selectedIndex != null) {
                final cur = _tracks[_selectedIndex!];
                final scaleDiff = (cur.overlayScale - _overlayBaseScale).abs();
                final rotDiff   = (cur.textRotation - _overlayBaseRotation).abs();
                if (scaleDiff > 0.05 || rotDiff > 2.0) { _scheduleDraftSave(); return; } // pinch → save
              }
              // Tap — no real change, remove the snapshot we pushed in onScaleStart.
              if (_undoStack.isNotEmpty) _undoStack.removeLast();
              // Looks like a tap — find which text track is at tapPos.
              for (int i = _tracks.length - 1; i >= 0; i--) {
                final track = _tracks[i];
                if (!track.isText) continue;
                final tcx = cw / 2 + track.overlayX * cw / 2;
                final tcy = ch / 2 + track.overlayY * ch / 2;
                final charCount =
                    track.textContent.isEmpty ? 4 : track.textContent.length.clamp(1, 40);
                final halfW = (track.fontSize * 0.52 * charCount * 0.5 +
                        track.textPaddingH + 8.0) *
                    track.overlayScale;
                final halfH = (track.fontSize * 0.65 + track.textPaddingV + 8.0) *
                    track.overlayScale;
                final aRad = track.textRotation * pi / 180.0;
                final cosA = cos(aRad);
                final sinA = sin(aRad);
                final dx = tapPos.dx - tcx;
                final dy = tapPos.dy - tcy;
                final localX =  dx * cosA + dy * sinA;
                final localY = -dx * sinA + dy * cosA;
                if (localX.abs() <= halfW && localY.abs() <= halfH) {
                  _rebuild(() => _selectedIndex = i);
                  return;
                }
              }
              // Tapped on empty space — deselect.
              _rebuild(() => _selectedIndex = null);
            },
            child: transformedContent,
          ),
        );
      } else if (t.isText) {
        // Unselected text: single tap on canvas selects it.
        final tidx = _tracks.indexOf(t);
        layer = Positioned.fill(
          key: ValueKey('tap_${t.id}'),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _rebuild(() => _selectedIndex = tidx),
            child: transformedContent,
          ),
        );
      } else {
        layer = Positioned.fill(
          key: ValueKey(t.id),
          child: transformedContent,
        );
      }
      layers.add(layer);
    }

    if (layers.isEmpty) {
      return Center(
        child: _tracks.any((t) => t.isVideo || t.isImage || t.isText)
            ? const SizedBox.shrink()
            : Text(
                'Add a video, image or text track to preview',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 13),
              ),
      );
    }

    // ── Playback transition overlays ──────────────────────────────────────
    // For each track with an active IN-transition, render it as an outgoing
    // layer on top of the incoming track content.
    for (final t in _tracks) {
      if (!t.isVideo && !t.isImage) continue;
      if (t.transitionInType == TransitionType.none) continue;
      if (_playheadPos < t.startOffset) continue;
      final transDuration = Duration(
        microseconds: (t.transitionInDuration * 1e6).round(),
      );
      final transEnd = t.startOffset + transDuration;
      if (_playheadPos >= transEnd) continue;

      final elapsed =
          (_playheadPos - t.startOffset).inMicroseconds.toDouble();
      final totalUs = transDuration.inMicroseconds.toDouble();
      final progress =
          totalUs > 0 ? (elapsed / totalUs).clamp(0.0, 1.0) : 1.0;

      layers.add(Positioned.fill(
        key: ValueKey('trans_${t.id}'),
        child: VeTransitionOverlay(
          type: t.transitionInType,
          progress: progress,
          outgoingChild: _buildOutgoingContent(t),
        ),
      ));
    }

    // ── Dialog transition preview overlay (looping, shown while dialog open)
    if (_transitionPreviewActive &&
        _transitionPreviewType != TransitionType.none &&
        _selectedIndex != null) {
      final previewTrack = _tracks[_selectedIndex!];
      layers.add(Positioned.fill(
        key: const ValueKey('_transition_overlay'),
        child: VeTransitionOverlay(
          type: _transitionPreviewType,
          progress: _transitionAnimProgress,
          outgoingChild: _buildOutgoingContent(previewTrack),
        ),
      ));
    }

    // ── Canvas-level selection controls for the selected text track ────────
    // Buttons are placed here (not inside the text widget) so they are always
    // within the canvas hit-test bounds and receive tap events correctly.
    if (interactive && _selectedIndex != null) {
      final sel = _tracks[_selectedIndex!];
      if (sel.isText) {
        // Text centre in canvas coordinates (canvas origin = top-left).
        final cx = cw / 2 + sel.overlayX * cw / 2;
        final cy = ch / 2 + sel.overlayY * ch / 2;
        const btnSize = 28.0;
        const btnR = btnSize / 2;

        // Reset measured size when a different track is selected.
        if (_measuredTrackId != sel.id) {
          _textOverlaySize = Size.zero;
          _measuredTrackId = sel.id;
        }
        // Schedule a post-frame measurement so buttons stay exact after every change.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final rb = _textOverlayKey.currentContext?.findRenderObject() as RenderBox?;
          if (rb == null || !rb.hasSize) return;
          final s = rb.size;
          if ((s.width  - _textOverlaySize.width).abs()  > 0.5 ||
              (s.height - _textOverlaySize.height).abs() > 0.5) {
            _rebuild(() { _textOverlaySize = s; _measuredTrackId = sel.id; });
          }
        });

        // Use measured size if available; fall back to estimation on first frame.
        // The total visual scale = overlayScale * canvasScale (same as Transform.scale above).
        const pad = 8.0; // VeTextSelectionPainter._pad
        final double btnCanvasScale = ch / kVeRefCanvasH;
        final double totalScale = sel.overlayScale * btnCanvasScale;
        final double halfW, halfH;
        if (_textOverlaySize != Size.zero) {
          halfW = (_textOverlaySize.width  / 2 + pad) * totalScale;
          halfH = (_textOverlaySize.height / 2 + pad) * totalScale;
        } else {
          final charCount = sel.textContent.isEmpty ? 4 : sel.textContent.length.clamp(1, 40);
          halfW = (sel.fontSize * 0.52 * charCount * 0.5 + sel.textPaddingH + pad) * totalScale;
          halfH = (sel.fontSize * 0.65 + sel.textPaddingV + pad) * totalScale;
        }

        // Rotate a corner offset around the text centre to follow textRotation.
        final angleRad = sel.textRotation * pi / 180.0;
        final cosA = cos(angleRad);
        final sinA = sin(angleRad);
        Offset rotatedCorner(double dx, double dy) {
          return Offset(
            cx + dx * cosA - dy * sinA,
            cy + dx * sinA + dy * cosA,
          );
        }

        final topRightPt    = rotatedCorner( halfW, -halfH);
        final bottomRightPt = rotatedCorner( halfW,  halfH);
        final bottomLeftPt  = rotatedCorner(-halfW,  halfH);

        // X (delete): top-right corner of the bounding box
        final xLeft    = topRightPt.dx - btnR;
        final xTop     = topRightPt.dy - btnR;

        // Edit (pencil): bottom-right corner
        final editLeft = bottomRightPt.dx - btnR;
        final editTop  = bottomRightPt.dy - btnR;

        // Resize (drag): bottom-left corner
        final rzLeft   = bottomLeftPt.dx - btnR;
        final rzTop    = bottomLeftPt.dy - btnR;

        const kBtnBg = Color(0xFF424242);
        const kBtnFg = Colors.white;

        layers.add(
          Positioned.fill(
            key: const ValueKey('_text_sel_btns'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Delete (X) — top-right corner
                Positioned(
                  left: xLeft,
                  top: xTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.close_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onTap: _deleteTrack,
                  ),
                ),
                // Edit (pencil) — bottom-right corner
                Positioned(
                  left: editLeft,
                  top: editTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.edit_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onTap: () => _showTextEditDialog(isNew: false),
                  ),
                ),
                // Resize (drag) — bottom-left corner
                Positioned(
                  left: rzLeft,
                  top: rzTop,
                  child: _VeTextCtrlBtn(
                    icon: Icons.open_in_full_rounded,
                    iconColor: kBtnFg,
                    bgColor: kBtnBg,
                    onPanStart: (_) => _pushUndo(),
                    onPanUpdate: (details) {
                      // Bottom-left corner: drag toward bottom-left = grow,
                      // toward top-right = shrink → use -dx + dy.
                      final delta = -details.delta.dx + details.delta.dy;
                      if (_selectedIndex != null) {
                        _rebuild(() {
                          final t = _tracks[_selectedIndex!];
                          final newSize =
                              (t.fontSize + delta * 0.5).clamp(8.0, 200.0);
                          _tracks[_selectedIndex!] =
                              t.copyWith(fontSize: newSize);
                        });
                      }
                    },
                    onPanEnd: (_) => _scheduleDraftSave(),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Stack(children: layers);
  }

  /// Wraps [child] in the correct rotation widget so that layout bounds change
  /// Radial vignette overlay (transparent centre → dark edges).
  Widget _buildVignetteOverlay(double strength) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.0,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: strength * 0.85),
              ],
              stops: const [0.4, 1.0],
            ),
          ),
        ),
      );

  // ── Text widget renderer ─────────────────────────────────────────────────

  Widget _buildTextWidget(TimelineTrack t, {bool selected = false}) {
    final hasBg = t.textBgOpacity > 0.0;
    final hasOutline = t.textOutlineWidth > 0.0;
    final rawText = t.textContent.isEmpty ? 'Text' : t.textContent;
    final displayText = switch (t.textCaseIndex) {
      1 => rawText.toUpperCase(),
      2 => rawText.toLowerCase(),
      3 => rawText.splitMapJoin(
            RegExp(r'\S+'),
            onMatch: (m) {
              final w = m[0]!;
              return w[0].toUpperCase() + w.substring(1).toLowerCase();
            },
            onNonMatch: (s) => s,
          ),
      _ => rawText,
    };
    final textAlign = const [TextAlign.left, TextAlign.center, TextAlign.right][t.textAlignIndex.clamp(0, 2)];

    final shadowList = <Shadow>[
      if (t.hasShadow)
        Shadow(
          color: t.shadowColor.withValues(alpha: t.shadowOpacity),
          blurRadius: t.shadowRadius,
          offset: Offset(t.shadowOffsetX, t.shadowOffsetY),
        ),
      // Glow: layered concentric shadows at offset (0,0) for smooth spread
      if (t.textGlowRadius > 0) ...[
        Shadow(color: t.textGlowColor.withValues(alpha: 0.9),
            blurRadius: t.textGlowRadius * 0.4),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.7),
            blurRadius: t.textGlowRadius * 0.7),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.5),
            blurRadius: t.textGlowRadius),
        Shadow(color: t.textGlowColor.withValues(alpha: 0.25),
            blurRadius: t.textGlowRadius * 1.6),
      ],
    ];
    List<Shadow>? shadows = shadowList.isEmpty ? null : shadowList;

    TextDecoration? decoration;
    if (t.textUnderline && t.textStrikethrough) {
      decoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
    } else if (t.textUnderline) {
      decoration = TextDecoration.underline;
    } else if (t.textStrikethrough) {
      decoration = TextDecoration.lineThrough;
    }

    TextStyle baseStyle(bool forOutline) => TextStyle(
          fontSize: t.fontSize,
          fontWeight: t.textBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: t.textItalic ? FontStyle.italic : FontStyle.normal,
          fontFamily: t.fontFamily,
          height: t.lineHeight,
          letterSpacing: t.letterSpacing,
          decoration: decoration,
          decorationColor: forOutline ? t.textOutlineColor : t.textColor,
          decorationThickness: 2.0,
          foreground: forOutline
              ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = t.textOutlineWidth * 2
                ..strokeJoin = StrokeJoin.round
                ..color = t.textOutlineColor)
              : null,
          // When gradient is on, use white so ShaderMask colorises it fully
          color: forOutline ? null : (t.textGradientEnabled ? Colors.white : t.textColor),
          shadows: forOutline ? null : shadows,
        );

    Widget fillText = Text(displayText, textAlign: textAlign, style: baseStyle(false));

    // Apply gradient via ShaderMask (srcIn = use text alpha as mask)
    if (t.textGradientEnabled) {
      final rad = t.textGradientAngle * pi / 180.0;
      fillText = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-cos(rad), -sin(rad)),
          end:   Alignment( cos(rad),  sin(rad)),
          colors: [t.textGradientColor1, t.textGradientColor2],
        ).createShader(bounds),
        child: fillText,
      );
    }

    Widget textContent;
    if (t.textPathCurve.abs() > 0.01) {
      // Curved text — render each character along a circular arc
      final approxCharW = t.fontSize * 0.65;
      final curveW = (approxCharW * displayText.length.clamp(1, 60) + 80)
          .clamp(140.0, 900.0);
      final curveH = t.fontSize * 4.0;
      Widget curveWidget = SizedBox(
        width: curveW,
        height: curveH,
        child: CustomPaint(
          painter: VeCurvedTextPainter(
            text: displayText,
            fillStyle: baseStyle(false),
            outlineStyle: hasOutline ? baseStyle(true) : null,
            curve: t.textPathCurve,
          ),
        ),
      );
      // Gradient still works — ShaderMask over the CustomPaint widget
      if (t.textGradientEnabled) {
        final rad = t.textGradientAngle * pi / 180.0;
        curveWidget = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-cos(rad), -sin(rad)),
            end:   Alignment( cos(rad),  sin(rad)),
            colors: [t.textGradientColor1, t.textGradientColor2],
          ).createShader(bounds),
          child: curveWidget,
        );
      }
      textContent = curveWidget;
    } else {
      textContent = hasOutline
          ? Stack(
              alignment: Alignment.center,
              children: [
                Text(displayText, textAlign: textAlign, style: baseStyle(true)),
                fillText,
              ],
            )
          : fillText;
    }

    final hasPadding = t.textPaddingH > 0 || t.textPaddingV > 0;
    Widget result = Container(
      key: selected ? _textOverlayKey : null,
      padding: (hasBg || hasPadding)
          ? EdgeInsets.symmetric(
              horizontal: hasPadding ? t.textPaddingH : 14,
              vertical:   hasPadding ? t.textPaddingV : 8,
            )
          : EdgeInsets.zero,
      decoration: hasBg
          ? BoxDecoration(
              color: t.textBgColor.withValues(alpha: t.textBgOpacity),
              borderRadius: BorderRadius.circular(t.textBgRadius),
            )
          : null,
      child: textContent,
    );
    // Selection overlay: dashed border + move hint icon (visual only).
    // NOTE: interactive buttons (X, edit) are rendered at canvas level
    // in _buildPreviewLayers so they remain within hit-test bounds.
    if (selected) {
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          // Dashed rounded-rect border drawn outside the widget bounds.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: const VeTextSelectionPainter()),
            ),
          ),
          // The actual text content.
          result,
          // ── Move hint — top-left (purely visual, gesture is on outer GD) ──
          Positioned(
            top: -22,
            left: -22,
            child: IgnorePointer(
              child: _VeTextCtrlBtn(
                icon: Icons.open_with_rounded,
                iconColor: Colors.white,
                bgColor: const Color(0xFF424242),
              ),
            ),
          ),
        ],
      );
    }

    if (t.textRotation != 0.0) {
      result = Transform.rotate(
        angle: t.textRotation * pi / 180.0,
        child: result,
      );
    }
    return result;
  }

  /// Wraps [child] in the correct rotation widget so that layout bounds change
  /// along with the visual rotation — matching what FFmpeg does (rotate first,
  /// then scale to fit the canvas).
  /// • 90° / 270° use [RotatedBox] which swaps width ↔ height in layout.
  /// • 180° uses [Transform.rotate] since dimensions don't change.
  Widget _applyRotationForPreview(int degrees, Widget child) {
    if (degrees == 0) return child;
    if (degrees == 180) return Transform.rotate(angle: pi, child: child);
    return RotatedBox(quarterTurns: degrees ~/ 90, child: child);
  }

  /// Applies the mask shape / feathering defined by [t.maskShapeIndex] etc.
  /// Hard clip (feather=0) uses [ClipPath]; feathered clip blurs the clipped result
  /// using [ImageFiltered] with [TileMode.decal] so the transparent boundary softens.
  Widget _applyMaskForPreview(Widget child, TimelineTrack t) {
    if (!t.hasMask) return child;

    Widget masked = ClipPath(
      clipper: VeMaskClipper(
        shapeIndex: t.maskShapeIndex,
        scale:      t.maskScale,
        inverted:   t.maskInverted,
      ),
      child: child,
    );

    if (t.maskFeather > 0) {
      final sigma = t.maskFeather * 22.0;
      masked = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: masked,
      );
    }

    return masked;
  }

  /// Small label badge shown in the preview corner to indicate active effects.
  Widget _previewBadge(String label, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
      );

  /// Applies the track's cropX/Y/W/H to the preview widget.
  /// Crop fractions are relative to the full display area (consistent with
  /// how the crop screen defines them).
  Widget _applyCropForPreview(Widget child, TimelineTrack t) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final fullW = w / t.cropW;
          final fullH = h / t.cropH;
          final tx = -(t.cropX / t.cropW) * w;
          final ty = -(t.cropY / t.cropH) * h;
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: fullW,
            minHeight: 0,
            maxHeight: fullH,
            child: Transform.translate(
              offset: Offset(tx, ty),
              child: SizedBox(
                width: fullW,
                height: fullH,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Container(
      height: _previewHeight,
      color: Colors.black,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Video content — constrained to 16:9 so the preview exactly
          // represents the exported result (FFmpeg always outputs 16:9).
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRect(child: _buildPreviewContent()),
            ),
          ),
            // Playhead time overlay
            Positioned(
              bottom: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(_playheadPos),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
            // Total duration overlay (right side)
            Positioned(
              bottom: 10,
              right: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(_totalDuration),
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
            // Fullscreen button (bottom-right corner)
            Positioned(
              bottom: 6,
              right: 6,
              child: GestureDetector(
                onTap: _showFullscreenPreview,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.fullscreen,
                      color: Colors.white70, size: 20),
                ),
              ),
            ),
            // Resize handle at bottom — gesture only on this strip
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  _rebuild(() {
                    _previewHeight = (_previewHeight + d.delta.dy)
                        .clamp(kVePreviewMinHeight, 320.0);
                  });
                },
                child: Container(
                  height: 16,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
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

  void _showFullscreenPreview() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => _FullscreenPreviewOverlay(editorState: this),
    ).whenComplete(() {
      // Reset measured text size — fullscreen uses a different canvas size so
      // the measurement taken there would corrupt button positions in the editor.
      if (mounted) _rebuild(() { _textOverlaySize = Size.zero; _measuredTrackId = null; });
    });
  }

  Widget _buildBanner() => const BannerAdWidget();
}
