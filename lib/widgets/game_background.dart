import 'package:flutter/material.dart';

/// The signature sky-to-pink gradient used across all game screens.
class GameBackground extends StatelessWidget {
  const GameBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7FD8FF), Color(0xFFFFC3E8)],
        ),
      ),
      child: SafeArea(child: child),
    );
  }
}
