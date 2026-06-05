import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

import 'video_editor_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Crop screen
// ─────────────────────────────────────────────────────────────────────────────

class VideoCropScreen extends StatefulWidget {
  final TimelineTrack track;
  final void Function(double cropX, double cropY, double cropW, double cropH, double cropRotation) onApply;

  const VideoCropScreen({
    super.key,
    required this.track,
    required this.onApply,
  });

  @override
  State<VideoCropScreen> createState() => _VideoCropScreenState();
}

class _VideoCropScreenState extends State<VideoCropScreen> {
  // Crop rectangle in 0.0–1.0 fractions of the media
  late double _cropX;
  late double _cropY;
  late double _cropW;
  late double _cropH;
  late double _cropRotation;

  // Locked aspect ratio (null = free)
  double? _lockedAspect; // width / height

  // Thumbnail image for preview
  ui.Image? _uiImage;

  // Drag state
  _DragHandle? _activeDrag;

  static const _red = Color(0xFFE5364B);

  static const _ratios = <_RatioChip>[
    _RatioChip('Free',  null,        Icons.crop_free_rounded),
    _RatioChip('1:1',   1.0,         Icons.crop_square_rounded),
    _RatioChip('4:5',   4.0 / 5.0,   Icons.crop_portrait_rounded),
    _RatioChip('9:16',  9.0 / 16.0,  Icons.crop_portrait_rounded),
    _RatioChip('16:9',  16.0 / 9.0,  Icons.crop_landscape_rounded),
    _RatioChip('4:3',   4.0 / 3.0,   Icons.crop_landscape_rounded),
    _RatioChip('2:1',   2.0,         Icons.crop_landscape_rounded),
    _RatioChip('3:4',   3.0 / 4.0,   Icons.crop_portrait_rounded),
    _RatioChip('3:2',   3.0 / 2.0,   Icons.crop_landscape_rounded),
    _RatioChip('2:3',   2.0 / 3.0,   Icons.crop_portrait_rounded),
    _RatioChip('1:2',   1.0 / 2.0,   Icons.crop_portrait_rounded),
    _RatioChip('5:4',   5.0 / 4.0,   Icons.crop_landscape_rounded),
    _RatioChip('21:9',  21.0 / 9.0,  Icons.crop_landscape_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _cropX        = widget.track.cropX;
    _cropY        = widget.track.cropY;
    _cropW        = widget.track.cropW;
    _cropH        = widget.track.cropH;
    _cropRotation = widget.track.cropRotation;
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      ImageProvider? provider;
      if (widget.track.isImage) {
        provider = FileImage(File(widget.track.filePath));
      } else if (widget.track.isVideo) {
        final tmpDir = await getTemporaryDirectory();
        final path = await VideoThumbnail.thumbnailFile(
          video: widget.track.filePath,
          thumbnailPath: '${tmpDir.path}/crop_thumb_${widget.track.id}.jpg',
          imageFormat: ImageFormat.JPEG,
          timeMs: 0,
          maxHeight: 1080,
          quality: 85,
        );
        if (path != null) {
          provider = FileImage(File(path));
        }
      }

      if (provider == null || !mounted) return;

      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (_, __) {
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      final img = await completer.future;

      if (mounted) {
        setState(() {
          _uiImage = img;
        });
      }
    } catch (_) {
      // Ignore preview load errors — the grey placeholder is still usable.
    }
  }

  void _reset() {
    setState(() {
      _cropX        = 0.0;
      _cropY        = 0.0;
      _cropW        = 1.0;
      _cropH        = 1.0;
      _cropRotation = 0.0;
      _lockedAspect = null;
    });
  }

  void _applyAspect(double? aspect) {
    setState(() {
      _lockedAspect = aspect;
      if (aspect == null) return;
      // Compute the largest rect with that aspect centred in the current crop
      final cx = _cropX + _cropW / 2;
      final cy = _cropY + _cropH / 2;
      double w, h;
      if (aspect >= 1.0) {
        w = _cropW;
        h = _cropW / aspect;
        if (h > _cropH) { h = _cropH; w = _cropH * aspect; }
      } else {
        h = _cropH;
        w = _cropH * aspect;
        if (w > _cropW) { w = _cropW; h = _cropW / aspect; }
      }
      _cropX = (cx - w / 2).clamp(0.0, 1.0 - w);
      _cropY = (cy - h / 2).clamp(0.0, 1.0 - h);
      _cropW = w.clamp(0.05, 1.0);
      _cropH = h.clamp(0.05, 1.0);
    });
  }

  // ── Drag handle hit-test ──────────────────────────────────────────────────

  _DragHandle? _hitTest(Offset local, Rect mediaRect) {
    const r = 24.0; // tap radius
    final tl = Offset(mediaRect.left + _cropX * mediaRect.width,
                      mediaRect.top  + _cropY * mediaRect.height);
    final br = Offset(mediaRect.left + (_cropX + _cropW) * mediaRect.width,
                      mediaRect.top  + (_cropY + _cropH) * mediaRect.height);
    final tr = Offset(br.dx, tl.dy);
    final bl = Offset(tl.dx, br.dy);

    if ((local - tl).distance < r) return _DragHandle.topLeft;
    if ((local - tr).distance < r) return _DragHandle.topRight;
    if ((local - bl).distance < r) return _DragHandle.bottomLeft;
    if ((local - br).distance < r) return _DragHandle.bottomRight;
    return null;
  }

  void _onDragUpdate(DragUpdateDetails d, Rect mediaRect) {
    if (_activeDrag == null) return;
    final dx = d.delta.dx / mediaRect.width;
    final dy = d.delta.dy / mediaRect.height;
    setState(() {
      switch (_activeDrag!) {
        case _DragHandle.topLeft:
          _moveTL(dx, dy);
        case _DragHandle.topRight:
          _moveTR(dx, dy);
        case _DragHandle.bottomLeft:
          _moveBL(dx, dy);
        case _DragHandle.bottomRight:
          _moveBR(dx, dy);
      }
    });
  }

  void _moveTL(double dx, double dy) {
    final newX = (_cropX + dx).clamp(0.0, _cropX + _cropW - 0.05);
    final newY = (_cropY + dy).clamp(0.0, _cropY + _cropH - 0.05);
    final dw = _cropX - newX;
    final dh = _cropY - newY;
    if (_lockedAspect != null) {
      final d2 = (dw + dh / _lockedAspect!) / 2;
      _cropX = (_cropX - d2).clamp(0.0, 1.0);
      _cropY = (_cropY - d2 * _lockedAspect!).clamp(0.0, 1.0);
      _cropW = (_cropW + d2).clamp(0.05, 1.0 - _cropX);
      _cropH = (_cropH + d2 * _lockedAspect!).clamp(0.05, 1.0 - _cropY);
    } else {
      _cropW = (_cropW + dw).clamp(0.05, 1.0);
      _cropH = (_cropH + dh).clamp(0.05, 1.0);
      _cropX = newX;
      _cropY = newY;
    }
  }

  void _moveTR(double dx, double dy) {
    if (_lockedAspect != null) {
      final d2 = (dx - dy / _lockedAspect!) / 2;
      _cropW = (_cropW + d2).clamp(0.05, 1.0 - _cropX);
      final dh = _cropW / _lockedAspect! - _cropH;
      _cropY = (_cropY - dh).clamp(0.0, 1.0);
      _cropH = (_cropH + dh).clamp(0.05, 1.0 - _cropY);
    } else {
      _cropW = (_cropW + dx).clamp(0.05, 1.0 - _cropX);
      final newY = (_cropY + dy).clamp(0.0, _cropY + _cropH - 0.05);
      _cropH = (_cropH + (_cropY - newY)).clamp(0.05, 1.0);
      _cropY = newY;
    }
  }

  void _moveBL(double dx, double dy) {
    if (_lockedAspect != null) {
      final d2 = (-dx + dy * _lockedAspect!) / 2;
      _cropH = (_cropH + d2).clamp(0.05, 1.0 - _cropY);
      final dw = _cropH * _lockedAspect! - _cropW;
      _cropX = (_cropX - dw).clamp(0.0, 1.0);
      _cropW = (_cropW + dw).clamp(0.05, 1.0 - _cropX);
    } else {
      final newX = (_cropX + dx).clamp(0.0, _cropX + _cropW - 0.05);
      _cropW = (_cropW + (_cropX - newX)).clamp(0.05, 1.0);
      _cropX = newX;
      _cropH = (_cropH + dy).clamp(0.05, 1.0 - _cropY);
    }
  }

  void _moveBR(double dx, double dy) {
    if (_lockedAspect != null) {
      final d2 = (dx + dy * _lockedAspect!) / 2;
      _cropW = (_cropW + d2).clamp(0.05, 1.0 - _cropX);
      _cropH = (_cropW / _lockedAspect!).clamp(0.05, 1.0 - _cropY);
    } else {
      _cropW = (_cropW + dx).clamp(0.05, 1.0 - _cropX);
      _cropH = (_cropH + dy).clamp(0.05, 1.0 - _cropY);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildPreviewArea()),
            _buildRotationRuler(),
            _buildRatioRow(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Preview area with crop overlay ───────────────────────────────────────

  Widget _buildPreviewArea() {
    return Stack(
      children: [
        // Small play controls top-left corner
        Positioned(
          top: 12,
          left: 16,
          child: Row(
            children: [
              _iconBtn(Icons.skip_previous_rounded, () {}),
              const SizedBox(width: 8),
              _iconBtn(Icons.play_arrow_rounded, () {}),
            ],
          ),
        ),
        // Reset button top-right
        Positioned(
          top: 12,
          right: 16,
          child: _iconBtn(Icons.refresh_rounded, _reset),
        ),
        // Preview + crop drag area
        Center(
          child: LayoutBuilder(builder: (ctx, constraints) {
            return _buildCropCanvas(constraints);
          }),
        ),
      ],
    );
  }

  Widget _buildCropCanvas(BoxConstraints constraints) {
    const padding = 40.0;
    final maxW = constraints.maxWidth  - padding * 2;
    final maxH = constraints.maxHeight - padding * 2 - 40;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        final mediaRect = _computeMediaRect(maxW, maxH, padding);
        _activeDrag = _hitTest(d.localPosition, mediaRect);
      },
      onPanUpdate: (d) {
        final mediaRect = _computeMediaRect(maxW, maxH, padding);
        _onDragUpdate(d, mediaRect);
      },
      onPanEnd: (_) => _activeDrag = null,
      child: SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight - 40,
        child: CustomPaint(
          painter: _CropOverlayPainter(
            uiImage: _uiImage,
            cropX: _cropX,
            cropY: _cropY,
            cropW: _cropW,
            cropH: _cropH,
            rotation: _cropRotation,
            maxW: maxW,
            maxH: maxH,
            padding: padding,
          ),
        ),
      ),
    );
  }

  Rect _computeMediaRect(double maxW, double maxH, double padding) {
    // Approximate media rect centred in the available area
    final canvasW = maxW;
    final canvasH = maxH;
    // We'll position it centred
    final left = padding;
    final top  = padding;
    return Rect.fromLTWH(left, top, canvasW, canvasH);
  }

  // ── Rotation ruler ────────────────────────────────────────────────────────

  Widget _buildRotationRuler() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_cropRotation.toStringAsFixed(0)}°',
          style: const TextStyle(
              color: _red, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: GestureDetector(
            onHorizontalDragUpdate: (d) {
              setState(() {
                _cropRotation =
                    (_cropRotation + d.delta.dx * 0.3).clamp(-45.0, 45.0);
              });
            },
            child: CustomPaint(
              painter: _RulerPainter(value: _cropRotation),
              size: Size(double.infinity, 36),
            ),
          ),
        ),
      ],
    );
  }

  // ── Aspect ratio chips ────────────────────────────────────────────────────

  Widget _buildRatioRow() {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _ratios.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = _ratios[i];
          final sel = _lockedAspect == r.aspect;
          return GestureDetector(
            onTap: () => _applyAspect(r.aspect),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: sel ? _red : const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(r.icon,
                      color: sel ? Colors.white : Colors.white60, size: 22),
                ),
                const SizedBox(height: 3),
                Text(r.label,
                    style: TextStyle(
                        color: sel ? _red : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Bottom action bar ─────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF222222))),
      ),
      child: Row(
        children: [
          // Cancel
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white70, size: 24),
            ),
          ),
          // Title
          const Expanded(
            flex: 2,
            child: Center(
              child: Text('Crop',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          // Confirm
          Expanded(
            child: TextButton(
              onPressed: () {
                widget.onApply(
                    _cropX, _cropY, _cropW, _cropH, _cropRotation);
                Navigator.of(context).pop();
              },
              child: const Icon(Icons.check, color: _red, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Drag handle enum
// ─────────────────────────────────────────────────────────────────────────────

enum _DragHandle { topLeft, topRight, bottomLeft, bottomRight }

// ─────────────────────────────────────────────────────────────────────────────
//  Crop overlay painter
// ─────────────────────────────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final ui.Image? uiImage;
  final double cropX, cropY, cropW, cropH, rotation;
  final double maxW, maxH, padding;

  _CropOverlayPainter({
    required this.uiImage,
    required this.cropX,
    required this.cropY,
    required this.cropW,
    required this.cropH,
    required this.rotation,
    required this.maxW,
    required this.maxH,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The media box centred in the canvas
    final mediaRect = Rect.fromLTWH(padding, padding, maxW, maxH);

    // Draw dark background behind everything
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    if (uiImage != null) {
      // Fit the image inside mediaRect preserving aspect ratio
      final imgW = uiImage!.width.toDouble();
      final imgH = uiImage!.height.toDouble();
      final scale = (mediaRect.width / imgW).clamp(0.0, mediaRect.height / imgH);
      final drawW = imgW * scale;
      final drawH = imgH * scale;
      final drawRect = Rect.fromLTWH(
        mediaRect.left + (mediaRect.width - drawW) / 2,
        mediaRect.top  + (mediaRect.height - drawH) / 2,
        drawW,
        drawH,
      );
      canvas.save();
      canvas.clipRect(mediaRect);
      canvas.drawImageRect(
        uiImage!,
        Rect.fromLTWH(0, 0, imgW, imgH),
        drawRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      // Grey placeholder while image loads
      canvas.drawRect(mediaRect, Paint()..color = const Color(0xFF1A1A1A));
    }

    // Compute crop rect in canvas coordinates
    final cropRect = Rect.fromLTWH(
      mediaRect.left   + cropX * mediaRect.width,
      mediaRect.top    + cropY * mediaRect.height,
      cropW * mediaRect.width,
      cropH * mediaRect.height,
    );

    // Dark overlay outside the crop area
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropPath = Path()..addRect(cropRect);
    final overlayPath = Path.combine(
        PathOperation.difference, outerPath, cropPath);
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Corner brackets (L-shaped, red)
    _drawCorners(canvas, cropRect);
  }

  void _drawCorners(Canvas canvas, Rect r) {
    const arm = 18.0;
    const thick = 3.0;
    const color = Color(0xFFE5364B);
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(arm, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, arm), paint);
    // Top-right
    canvas.drawLine(r.topRight, r.topRight + const Offset(-arm, 0), paint);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, arm), paint);
    // Bottom-left
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(arm, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -arm), paint);
    // Bottom-right
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-arm, 0), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -arm), paint);

    // Grid lines (rule-of-thirds)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    final w3 = r.width / 3;
    final h3 = r.height / 3;
    canvas.drawLine(r.topLeft + Offset(w3, 0), r.bottomLeft + Offset(w3, 0), gridPaint);
    canvas.drawLine(r.topLeft + Offset(w3 * 2, 0), r.bottomLeft + Offset(w3 * 2, 0), gridPaint);
    canvas.drawLine(r.topLeft + Offset(0, h3), r.topRight + Offset(0, h3), gridPaint);
    canvas.drawLine(r.topLeft + Offset(0, h3 * 2), r.topRight + Offset(0, h3 * 2), gridPaint);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.uiImage != uiImage ||
      old.cropX != cropX || old.cropY != cropY ||
      old.cropW != cropW || old.cropH != cropH ||
      old.rotation != rotation;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Rotation ruler painter
// ─────────────────────────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final double value; // -45..45

  const _RulerPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    const totalRange = 90.0; // -45..45 visible range
    final pxPerDeg = size.width / totalRange;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    final tickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    final redPaint = Paint()
      ..color = const Color(0xFFE5364B)
      ..strokeWidth = 2;

    // Draw tick marks
    for (int deg = -45; deg <= 45; deg++) {
      final screenX = size.width / 2 + (deg - value) * pxPerDeg;
      if (screenX < 0 || screenX > size.width) continue;
      final isMajor = deg % 5 == 0;
      final tickH = isMajor ? size.height * 0.7 : size.height * 0.4;
      canvas.drawLine(
        Offset(screenX, (size.height - tickH) / 2),
        Offset(screenX, (size.height + tickH) / 2),
        deg == 0 ? redPaint : tickPaint,
      );
    }

    // Centre indicator (red vertical line)
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = const Color(0xFFE5364B)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.value != value;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Aspect ratio chip data
// ─────────────────────────────────────────────────────────────────────────────

class _RatioChip {
  final String label;
  final double? aspect; // null = free
  final IconData icon;
  const _RatioChip(this.label, this.aspect, this.icon);
}
