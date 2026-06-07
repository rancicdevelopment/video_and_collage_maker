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

  @override
  Widget build(BuildContext context) {
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
                child: Image.memory(_bytes!, fit: BoxFit.cover)),
      ),
    );
  }
}
