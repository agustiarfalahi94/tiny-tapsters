import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A looping shower of emoji confetti. Purely decorative: it ignores taps so
/// buttons underneath stay usable.
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
      return _Piece(
        emoji: _emojis[rnd.nextInt(_emojis.length)],
        x: rnd.nextDouble(),
        y: rnd.nextDouble() * 1.2 - 0.2,
        size: 18 + rnd.nextDouble() * 26,
        speed: 0.25 + rnd.nextDouble() * 0.35,
        drift: 0.5 + rnd.nextDouble() * 1.5,
        rotation: rnd.nextDouble() * math.pi * 2,
        rotationSpeed: (rnd.nextDouble() - 0.5) * 6,
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
  });

  final String emoji;
  final double x;
  final double y;
  final double size;
  final double speed;
  final double drift;
  final double rotation;
  final double rotationSpeed;
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

      final textPainter = TextPainter(
        text: TextSpan(
          text: piece.emoji,
          style: TextStyle(fontSize: piece.size),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(piece.rotation + progress * piece.rotationSpeed);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
