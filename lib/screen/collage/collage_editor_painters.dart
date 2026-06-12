part of 'collage_editor_screen.dart';

// ── Path clipper for artistic cells ──────────────────────────────────────────

class _PathClipper extends CustomClipper<Path> {
  final Path path;
  _PathClipper(this.path);

  @override
  Path getClip(Size size) => path;

  // Must reclip when the path changes — artistic layouts rebuild their cell
  // paths while a divider handle is being dragged.
  @override
  bool shouldReclip(_PathClipper old) => old.path != path;
}

// ── Path stroke painter for artistic cell selection ───────────────────────────

class _PathStrokePainter extends CustomPainter {
  final Path path;
  final Color color;
  final double strokeWidth;

  _PathStrokePainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PathStrokePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.path != path;
}