import 'dart:async';

import 'package:flutter/material.dart';

import 'recorder_constants.dart';

class RecorderNudgeButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onNudge;

  const RecorderNudgeButton({
    super.key,
    required this.icon,
    required this.onNudge,
  });

  @override
  State<RecorderNudgeButton> createState() => _RecorderNudgeButtonState();
}

class _RecorderNudgeButtonState extends State<RecorderNudgeButton> {
  Timer? _repeatTimer;
  bool _pressed = false;

  void _startRepeat() {
    if (_pressed) return;
    _pressed = true;
    widget.onNudge();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) { if (_pressed) widget.onNudge(); },
    );
  }

  void _stopRepeat() {
    _pressed = false;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown:   (_) => _startRepeat(),
      onPointerUp:     (_) => _stopRepeat(),
      onPointerCancel: (_) => _stopRepeat(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: kRecCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kRecAccent.withValues(alpha: 0.45)),
        ),
        child: Icon(widget.icon, color: kRecAccent, size: 18),
      ),
    );
  }
}
