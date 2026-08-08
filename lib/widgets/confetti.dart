import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A looping shower of emoji confetti. Purely decorative: it ignores taps so
/// buttons underneath stay usable.
///
/// Performance: each piece's [TextPainter] is laid out ONCE when the widget
/// is created and reused every frame — laying out text inside `paint()` is
/// expensive and would jank the win celebration (and drain battery while the
/// overlay is open).
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  static const _emojis = ['🎉', '⭐', '🎈', '✨', '🐻', '🌸', '🦄', '🌈'];

  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    final rnd = math.Random();
    _pieces = List.generate(70, (_) {
      final emoji = _emojis[rnd.nextInt(_emojis.length)];
      final size = 18 + rnd.nextDouble() * 26;
      return _Piece(
        emoji: emoji,
        x: rnd.nextDouble(),
        y: rnd.nextDouble() * 1.2 - 0.2,
        size: size,
        speed: 0.25 + rnd.nextDouble() * 0.35,
        drift: 0.5 + rnd.nextDouble() * 1.5,
        rotation: rnd.nextDouble() * math.pi * 2,
        rotationSpeed: (rnd.nextDouble() - 0.5) * 6,
        textPainter: TextPainter(
          text: TextSpan(
            text: emoji,
            style: TextStyle(fontSize: size),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            pieces: _pieces,
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.emoji,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.rotation,
    required this.rotationSpeed,
    required this.textPainter,
  });

  final String emoji;
  final double x;
  final double y;
  final double size;
  final double speed;
  final double drift;
  final double rotation;
  final double rotationSpeed;

  /// Pre-laid-out once; reused every frame.
  final TextPainter textPainter;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.progress});

  final List<_Piece> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final y = (piece.y + progress * piece.speed) % 1.2 - 0.1;
      final x =
          piece.x +
          math.sin(progress * 2 * math.pi * piece.drift + piece.x * 10) * 0.04;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(piece.rotation + progress * piece.rotationSpeed);
      piece.textPainter.paint(
        canvas,
        Offset(-piece.textPainter.width / 2, -piece.textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
