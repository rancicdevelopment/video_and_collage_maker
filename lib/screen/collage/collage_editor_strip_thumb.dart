part of 'collage_editor_screen.dart';

// ── Strip thumbnail ───────────────────────────────────────────────────────────

class _StripThumb extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback onTap;
  const _StripThumb({required this.asset, required this.onTap});

  @override
  State<_StripThumb> createState() => _StripThumbState();
}

class _StripThumbState extends State<_StripThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(120))
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _isGif =>
      widget.asset.mimeType?.toLowerCase() == 'image/gif' ||
      (widget.asset.title?.toLowerCase().endsWith('.gif') ?? false);

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.asset.type == AssetType.video;
    final isGif   = !isVideo && _isGif;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 56,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: _bytes == null
            ? const SizedBox()
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(_bytes!, fit: BoxFit.cover),
                    // Video: play icon + duration badge
                    if (isVideo) ...[
                      const Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white, size: 20),
                      ),
                      Positioned(
                        bottom: 2,
                        left: 2,
                        right: 2,
                        child: Text(
                          _formatDuration(widget.asset.videoDuration),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                          ),
                        ),
                      ),
                    ],
                    // GIF badge
                    if (isGif)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('GIF',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
