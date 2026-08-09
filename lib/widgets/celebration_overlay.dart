import 'package:flutter/material.dart';

import '../services/sound_effects.dart';
import 'confetti.dart';

/// Full-screen celebration shown when a game is completed: confetti rain,
/// a big emoji, an optional star rating, and action buttons.
///
/// Stateful only so the win sound fires exactly once when the overlay
/// appears. Every game reaches its win through this widget, so playing the
/// fanfare here keeps six screens from each having to remember to.
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.title,
    this.stars,
    this.emoji = '🎉',
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;

  /// Optional star rating (1-3). Hidden when null.
  final int? stars;
  final String emoji;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay> {
  @override
  void initState() {
    super.initState();
    // Games that show no star rating (jigsaw, animal food, bubble pop) still
    // finished successfully, so they get the three-star fanfare.
    SoundEffects.instance.win(widget.stars ?? 3);
  }

  @override
  Widget build(BuildContext context) {
    final stars = widget.stars;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Stack(
          children: [
            const Positioned.fill(child: Confetti()),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.emoji, style: const TextStyle(fontSize: 80)),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (stars != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Icon(
                              i < stars ? Icons.star : Icons.star_border,
                              size: 56,
                              color: i < stars ? Colors.amber : Colors.white54,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: widget.onPrimary,
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
                        widget.primaryLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.secondaryLabel != null &&
                        widget.onSecondary != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: widget.onSecondary,
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
                          widget.secondaryLabel!,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
