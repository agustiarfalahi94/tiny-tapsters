import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../services/sound_effects.dart';

/// Shown when the clock runs out.
///
/// A sibling of `CelebrationOverlay` rather than a flag on it: the confetti,
/// the stars and the fanfare are all wrong here, and threading an `isLoss`
/// through an already-branchy widget would earn nothing but branches.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    this.title,
    required this.onRetry,
    required this.onHome,
  });

  /// Defaults to the translated "Time's up!".
  final String? title;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> {
  @override
  void initState() {
    super.initState();
    SoundEffects.instance.lose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⏰', style: TextStyle(fontSize: 80)),
                const SizedBox(height: 8),
                Text(
                  widget.title ?? strings.timesUp,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: widget.onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    strings.tryAgain,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: widget.onHome,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    strings.home,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
