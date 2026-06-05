import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media_picker/media_picker_screen.dart';
import '../video_editor/video_editor_screen.dart';

/// Shown after the user captures a video or photo with the camera.
/// They can preview it and either discard it or send it to the video editor.
///
/// If [onCapture] is provided the "Use in Editor" button calls it with the
/// captured [PickedMediaFile] and pops the camera flow instead of opening
/// the standalone VideoEditorScreen. This allows embedding the camera inside
/// other flows (e.g. the collage editor).
class CameraResultPreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  /// Optional callback for callers that want to receive the captured file
  /// themselves (e.g. collage editor). When null the default behaviour of
  /// opening VideoEditorScreen is used.
  final void Function(PickedMediaFile)? onCapture;

  const CameraResultPreviewScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
    this.onCapture,
  });

  @override
  State<CameraResultPreviewScreen> createState() =>
      _CameraResultPreviewScreenState();
}

class _CameraResultPreviewScreenState
    extends State<CameraResultPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final ctrl =
        VideoPlayerController.file(File(widget.filePath));
    _videoController = ctrl;
    await ctrl.initialize();
    await ctrl.setLooping(true);
    if (mounted) {
      setState(() => _videoInitialized = true);
      await ctrl.play();
      setState(() => _isPlaying = true);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final ctrl = _videoController;
    if (ctrl == null) return;
    if (_isPlaying) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  /// Discard — pop back to the camera screen.
  void _discard() {
    Navigator.pop(context);
  }

  /// Use in editor — open VideoEditorScreen with this file preloaded, or
  /// return it to the caller via [onCapture] when embedded in another flow.
  Future<void> _useInEditor() async {
    Duration duration = Duration.zero;
    if (widget.isVideo) {
      final ctrl = _videoController;
      if (ctrl != null && ctrl.value.isInitialized) {
        duration = ctrl.value.duration;
      }
    }

    final mediaFile = PickedMediaFile(
      path: widget.filePath,
      isVideo: widget.isVideo,
      duration: duration,
    );

    if (!mounted) return;

    if (widget.onCapture != null) {
      // Caller handles where the media goes — pop camera + preview screens.
      Navigator.pop(context); // preview screen
      Navigator.pop(context); // camera screen
      widget.onCapture!(mediaFile);
      return;
    }

    // Default: pop both screens back to root, then open standalone editor.
    Navigator.popUntil(context, (route) => route.isFirst);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoEditorScreen(initialMedia: [mediaFile]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Media preview ───────────────────────────────────────────────
          _buildMediaPreview(),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                // Back to camera
                _CircleButton(
                  icon: Icons.arrow_back,
                  onTap: _discard,
                ),
                const Spacer(),
                if (widget.isVideo && _videoInitialized)
                  _CircleButton(
                    icon:
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                    onTap: _togglePlay,
                  ),
              ],
            ),
          ),

          // ── Bottom action buttons ────────────────────────────────────────
          Positioned(
            bottom: botPad + 24,
            left: 24,
            right: 24,
            child: Row(
              children: [
                // Discard
                Expanded(
                  child: OutlinedButton(
                    onPressed: _discard,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Discard',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Use in editor
                Expanded(
                  child: ElevatedButton(
                    onPressed: _useInEditor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5A623),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Use in Editor',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── File type label ──────────────────────────────────────────────
          Positioned(
            top: topPad + 64,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.isVideo ? 'Video Preview' : 'Photo Preview',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.isVideo) {
      if (!_videoInitialized || _videoController == null) {
        return const Center(
          child: CircularProgressIndicator(
              color: Colors.white54, strokeWidth: 2),
        );
      }
      return GestureDetector(
        onTap: _togglePlay,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        ),
      );
    } else {
      return SizedBox.expand(
        child: Image.file(
          File(widget.filePath),
          fit: BoxFit.contain,
        ),
      );
    }
  }
}

// ── Small circular icon button ─────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
