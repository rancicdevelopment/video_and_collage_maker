import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'video_editor_constants.dart';
import 'video_editor_model.dart';
import 'video_editor_painters.dart';

/// Visual block for a single track on the timeline.
/// Video tracks show a filmstrip; audio tracks show a waveform; image tracks
/// show a tiled preview of the image itself.
class VeTrackBlock extends StatelessWidget {
  final TimelineTrack track;
  final bool isSelected;
  final bool isCollapsed;
  final double width;
  final double height;

  final ValueChanged<double> onTrimLeftStart;
  final ValueChanged<double> onTrimLeftUpdate;
  final ValueChanged<double> onTrimLeftEnd;
  final ValueChanged<double> onTrimRightStart;
  final ValueChanged<double> onTrimRightUpdate;
  final ValueChanged<double> onTrimRightEnd;

  const VeTrackBlock({
    super.key,
    required this.track,
    required this.isSelected,
    required this.width,
    required this.height,
    this.isCollapsed = false,
    required this.onTrimLeftStart,
    required this.onTrimLeftUpdate,
    required this.onTrimLeftEnd,
    required this.onTrimRightStart,
    required this.onTrimRightUpdate,
    required this.onTrimRightEnd,
  });

  double _fadeFraction(double fadeSecs) {
    final effSecs = track.effectiveDuration.inMicroseconds / 1e6;
    if (effSecs <= 0 || fadeSecs <= 0) return 0.0;
    return (fadeSecs / effSecs).clamp(0.0, 0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildMainBlock(),
        _buildLeftHandle(),
        _buildRightHandle(),
      ],
    );
  }

  Widget _buildMainBlock() {
    // When video thumbnails or an image file are available, let the visual
    // content be the background (no color tint on top of it).
    final hasThumbs = track.isVideo && track.thumbnailPaths.isNotEmpty;
    final hasImageBg = track.isImage;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: (hasThumbs || hasImageBg) && !isCollapsed
              ? Colors.black
              : track.color.withValues(alpha: 0.3),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : track.color.withValues(alpha: 0.65),
            width: isSelected ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: track.hasShadow
              ? [
                  BoxShadow(
                    color: track.shadowColor.withValues(alpha: track.shadowOpacity * 0.7),
                    blurRadius: track.shadowRadius * 0.5,
                    offset: Offset(track.shadowOffsetX * 0.3, track.shadowOffsetY * 0.3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Content area – hidden when collapsed
            if (!isCollapsed)
              Positioned.fill(
                child: track.isVideo
                    ? _buildVideoContent()
                    : track.isImage
                        ? _buildImageContent()
                        : track.isText
                            ? _buildTextContent()
                            : _buildAudioContent(),
              ),
            // Fade overlays – only in expanded mode (video + image)
            if (!isCollapsed && (track.isVideo || track.isImage) && track.fadeInSecs > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _fadeFraction(track.fadeInSecs),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!isCollapsed && (track.isVideo || track.isImage) && track.fadeOutSecs > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerRight,
                  widthFactor: _fadeFraction(track.fadeOutSecs),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Dark scrim so icon/title are readable (expanded only)
            if (!isCollapsed && (hasThumbs || hasImageBg))
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: height * 0.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            // Collapsed: centered title only
            if (isCollapsed)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: kVeHandleWidth + 4),
                  child: Center(
                    child: Text(
                      track.title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            // Expanded: track type icon badge (top-left)
            if (!isCollapsed)
              Positioned(
                top: 4,
                left: kVeHandleWidth + 4,
                child: Icon(
                  track.isVideo
                      ? Icons.videocam_rounded
                      : track.isImage
                          ? Icons.image_rounded
                          : track.isText
                              ? Icons.title_rounded
                              : Icons.music_note_rounded,
                  color: Colors.white.withValues(alpha: 0.75),
                  size: 13,
                ),
              ),
            // EQ badge (top-right) — shown when EQ is baked in
            if (!isCollapsed && track.eqApplied)
              Positioned(
                top: 4,
                right: kVeHandleWidth + 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'EQ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            // Shadow/Glow badge — shown when effect is active
            if (!isCollapsed && track.hasShadow)
              Positioned(
                top: 4,
                right: kVeHandleWidth + (track.eqApplied ? 36 : 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: track.shadowColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    track.shadowOffsetX == 0.0 && track.shadowOffsetY == 0.0
                        ? 'GLW'
                        : 'SHD',
                    style: TextStyle(
                      color: track.shadowColor.computeLuminance() > 0.4
                          ? Colors.black
                          : Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            // Transition badge — shown at left edge when a transition is set
            if (!isCollapsed &&
                (track.isVideo || track.isImage) &&
                track.transitionInType != TransitionType.none)
              Positioned(
                top: 0,
                bottom: 0,
                left: kVeHandleWidth,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C8FF).withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            // Expanded: title at bottom
            if (!isCollapsed)
              Positioned(
                bottom: 4,
                left: kVeHandleWidth + 4,
                right: kVeHandleWidth + 4,
                child: Text(
                  track.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Video content: filmstrip thumbnails ────────────────────────────────────

  Widget _buildVideoContent() {
    if (track.thumbnailPaths.isEmpty) {
      return _buildVideoPlaceholder();
    }
    return _buildFilmstrip();
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      color: track.color.withValues(alpha: 0.25),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: track.color.withValues(alpha: 0.7),
          size: 28,
        ),
      ),
    );
  }

  // Vignette radial gradient overlay for timeline thumbnails
  Widget _buildVignetteOverlay(double strength) => Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.15,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: strength * 0.8),
                ],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
        ),
      );

  Widget _buildFilmstrip() {
    final tileW = height; // square tiles
    final tilesNeeded = (width / tileW).ceil() + 1;
    final thumbCount = track.thumbnailPaths.length;
    final durMs = track.duration.inMilliseconds.toDouble();
    final trimStartMs = track.trimStart.inMilliseconds.toDouble();
    final effectiveDurMs = track.effectiveDuration.inMilliseconds.toDouble();

    final filmstrip = ClipRect(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: List.generate(tilesNeeded, (i) {
            // Map tile centre to its actual video-time position, then pick
            // the thumbnail whose extraction time is closest.
            int thumbIdx;
            if (thumbCount == 1 || durMs <= 0 || effectiveDurMs <= 0) {
              thumbIdx = 0;
            } else {
              final tileCentreFraction = ((i + 0.5) * tileW) / width;
              final effectiveMs = tileCentreFraction * effectiveDurMs;
              // account for trim and speed to get original-file time, then loop
              final videoMs =
                  (trimStartMs + effectiveMs * track.speed) % durMs;
              thumbIdx = (videoMs / durMs * (thumbCount - 1))
                  .round()
                  .clamp(0, thumbCount - 1);
            }
            final path = track.thumbnailPaths[thumbIdx];
            return Positioned(
              left: i * tileW,
              top: 0,
              width: tileW,
              height: height,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Container(
                  color: track.color.withValues(alpha: 0.4),
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.white30, size: 20),
                ),
              ),
            );
          }),
        ),
      ),
    );
    Widget result = track.hasColorMatrix
        ? ColorFiltered(colorFilter: track.colorFilter, child: filmstrip)
        : filmstrip;
    if (track.blurRadius > 0.0) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: track.blurRadius * 0.5,
          sigmaY: track.blurRadius * 0.5,
          tileMode: TileMode.clamp,
        ),
        child: result,
      );
    }
    if (track.vignetteStrength > 0.0 || track.grainStrength > 0.0) {
      result = SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            result,
            if (track.grainStrength > 0.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: VeGrainPainter(
                      strength: track.grainStrength,
                      seed: 0, // static in thumbnails
                    ),
                  ),
                ),
              ),
            if (track.vignetteStrength > 0.0)
              _buildVignetteOverlay(track.vignetteStrength),
          ],
        ),
      );
    }
    return result;
  }

  // ── Image content: tiled preview of the still image ───────────────────────

  Widget _buildImageContent() {
    final tileW = height; // square tiles (1:1 aspect)
    final tilesNeeded = (width / tileW).ceil() + 1;
    final imageFile = File(track.filePath);

    final content = ClipRect(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: List.generate(tilesNeeded, (i) {
            return Positioned(
              left: i * tileW,
              top: 0,
              width: tileW,
              height: height,
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Container(
                  color: track.color.withValues(alpha: 0.4),
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.white30, size: 20),
                ),
              ),
            );
          }),
        ),
      ),
    );
    Widget result = track.hasColorMatrix
        ? ColorFiltered(colorFilter: track.colorFilter, child: content)
        : content;
    if (track.blurRadius > 0.0) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: track.blurRadius * 0.5,
          sigmaY: track.blurRadius * 0.5,
          tileMode: TileMode.clamp,
        ),
        child: result,
      );
    }
    if (track.vignetteStrength > 0.0 || track.grainStrength > 0.0) {
      result = SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            result,
            if (track.grainStrength > 0.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: VeGrainPainter(
                      strength: track.grainStrength,
                      seed: 0, // static in thumbnails
                    ),
                  ),
                ),
              ),
            if (track.vignetteStrength > 0.0)
              _buildVignetteOverlay(track.vignetteStrength),
          ],
        ),
      );
    }
    return result;
  }

  // ── Audio content: waveform ────────────────────────────────────────────────

  Widget _buildAudioContent() {
    return CustomPaint(
      size: Size(width, height),
      painter: VeWaveformPainter(
        bars: track.waveformBars,
        color: track.color,
        trimStartFraction: track.duration.inMicroseconds > 0
            ? (track.trimStart.inMicroseconds / track.duration.inMicroseconds)
                .clamp(0.0, 1.0)
            : 0.0,
        trimEndFraction: track.duration.inMicroseconds > 0
            ? (track.trimEnd.inMicroseconds / track.duration.inMicroseconds)
                .clamp(0.0, 1.0)
            : 0.0,
        volume: track.volume,
        fadeInFraction: _fadeFraction(track.fadeInSecs),
        fadeOutFraction: _fadeFraction(track.fadeOutSecs),
      ),
    );
  }

  // ── Text content: centered text preview ───────────────────────────────────

  Widget _buildTextContent() {
    final content = track.textContent.isEmpty ? 'Text' : track.textContent;
    return Container(
      color: track.color.withValues(alpha: 0.15),
      padding: EdgeInsets.symmetric(horizontal: kVeHandleWidth + 6),
      child: Center(
        child: Text(
          content,
          style: TextStyle(
            color: track.textColor.withValues(alpha: 0.95),
            fontSize: (track.fontSize * 0.22).clamp(8.0, 18.0),
            fontWeight: track.textBold ? FontWeight.bold : FontWeight.w500,
            fontStyle: track.textItalic ? FontStyle.italic : FontStyle.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Trim handles ──────────────────────────────────────────────────────────

  Widget _buildLeftHandle() {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onTrimLeftStart(0),
        onPointerMove: (e) => onTrimLeftUpdate(e.delta.dx),
        onPointerUp: (_) => onTrimLeftEnd(0),
        onPointerCancel: (_) => onTrimLeftEnd(0),
        child: Container(
          width: kVeHandleWidth,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              bottomLeft: Radius.circular(6),
            ),
          ),
          child: const Center(
            child:
                Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildRightHandle() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onTrimRightStart(0),
        onPointerMove: (e) => onTrimRightUpdate(e.delta.dx),
        onPointerUp: (_) => onTrimRightEnd(0),
        onPointerCancel: (_) => onTrimRightEnd(0),
        child: Container(
          width: kVeHandleWidth,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: const Center(
            child: Icon(Icons.chevron_left, color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }
}
