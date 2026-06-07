part of 'collage_editor_screen.dart';

// ── Divider model ─────────────────────────────────────────────────────────────

class _Divider {
  final bool isVertical;
  final double position;
  final double spanStart;
  final double spanEnd;
  final int cellA;
  final int cellB;

  const _Divider({
    required this.isVertical,
    required this.position,
    required this.spanStart,
    required this.spanEnd,
    required this.cellA,
    required this.cellB,
  });

  _Divider copyWith({double? position}) => _Divider(
        isVertical: isVertical,
        position: position ?? this.position,
        spanStart: spanStart,
        spanEnd: spanEnd,
        cellA: cellA,
        cellB: cellB,
      );
}

// ── Handle widgets ────────────────────────────────────────────────────────────

class _EdgeHandle extends StatelessWidget {
  final double left, top;
  final bool isHoriz; // true = ≡ (horizontal), false = ||| (vertical)
  final void Function(double dx, double dy)? onDrag;

  const _EdgeHandle({
    required this.left,
    required this.top,
    required this.isHoriz,
    this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFFCC2222),
        shape: BoxShape.circle,
      ),
      child: RotatedBox(
        quarterTurns: isHoriz ? 0 : 1,
        child: const Icon(
          Icons.menu,
          color: Colors.white,
          size: 14,
        ),
      ),
    );
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onPanUpdate: onDrag != null ? (d) => onDrag!(d.delta.dx, d.delta.dy) : null,
        child: btn,
      ),
    );
  }
}
