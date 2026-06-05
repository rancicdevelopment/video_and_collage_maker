import 'package:flutter/material.dart';

class RecorderTimeLabel extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final bool rightAlign;

  const RecorderTimeLabel({
    super.key,
    required this.label,
    required this.time,
    required this.color,
    this.rightAlign = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        Text(
          time,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
