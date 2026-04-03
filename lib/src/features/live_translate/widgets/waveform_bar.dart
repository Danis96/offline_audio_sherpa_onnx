import 'dart:math' as math;

import 'package:flutter/material.dart';

class WaveformBar extends StatelessWidget {
  const WaveformBar({
    super.key,
    required this.levels,
    required this.isRecording,
  });

  final List<double> levels;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: levels
            .map(
              (level) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    height: isRecording ? math.max(8, 8 + (level * 64)) : 10,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF1E293B),
                        const Color(0xFF34D399),
                        isRecording ? level.clamp(0, 1) : 0.15,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
