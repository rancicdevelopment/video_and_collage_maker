part of 'collage_editor_screen.dart';

// ── Source picker bottom sheet ────────────────────────────────────────────────

class _SourcePickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tap here to add a video',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('PICK SOURCE',
                style: TextStyle(color: Colors.white38, fontSize: 11,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SourceTile(
                  icon: Icons.video_library_outlined,
                  iconColor: const Color(0xFF5B35C8),
                  title: 'Video',
                  subtitle: 'LIBRARY',
                  isHighlighted: true,
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceTile(
                  icon: Icons.gif_box_outlined,
                  iconColor: const Color(0xFFD94050),
                  title: 'GIF',
                  subtitle: 'ANIMATED',
                  onTap: () => Navigator.pop(context, 'gif'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SourceTile(
                  icon: Icons.camera_alt_outlined,
                  iconColor: const Color(0xFFB8860B),
                  title: 'Capture',
                  subtitle: 'LIVE',
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceTile(
                  icon: Icons.photo_library_outlined,
                  iconColor: const Color(0xFF2C8C6C),
                  title: 'Photos',
                  subtitle: 'LIBRARY',
                  onTap: () => Navigator.pop(context, 'photo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Icon(Icons.keyboard_arrow_down,
                color: Colors.white38, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isHighlighted
              ? const Color(0xFF252535)
              : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: isHighlighted
              ? Border.all(color: const Color(0xFF5B35C8), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10,
                        letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
