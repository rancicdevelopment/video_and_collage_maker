import 'package:flutter/material.dart';

import 'recorder_constants.dart';

class RecorderAmplitudeBars extends StatelessWidget {
  final List<double> bars;
  const RecorderAmplitudeBars({super.key, required this.bars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(bars.length, (i) {
        final h = (bars[i] * 64).clamp(3.0, 64.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          width: 4,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Color.lerp(
              kRecRed.withValues(alpha: 0.5),
              kRecRed,
              bars[i],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
