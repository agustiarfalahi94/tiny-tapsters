import 'package:flutter/material.dart';

import 'confetti.dart';

/// Full-screen celebration shown when a game is completed: confetti rain,
/// a big emoji, an optional star rating, and action buttons.
class CelebrationOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                    Text(emoji, style: const TextStyle(fontSize: 80)),
                    const SizedBox(height: 8),
                    Text(
                      title,
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
                              i < stars! ? Icons.star : Icons.star_border,
                              size: 56,
                              color: i < stars! ? Colors.amber : Colors.white54,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: onPrimary,
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
                        primaryLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (secondaryLabel != null && onSecondary != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: onSecondary,
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
                          secondaryLabel!,
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
