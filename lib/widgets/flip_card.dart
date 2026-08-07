import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A card that flips between [front] and [back] with a 3D rotation whenever
/// [faceUp] changes.
class FlipCard extends StatelessWidget {
  const FlipCard({
    super.key,
    required this.faceUp,
    required this.front,
    required this.back,
  });

  final bool faceUp;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: faceUp ? 1.0 : 0.0, end: faceUp ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        final angle = value * math.pi;
        final showBack = angle < math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: showBack
              ? back
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: front,
                ),
        );
      },
    );
  }
}
