import 'package:flutter/material.dart';

import '../widgets/game_background.dart';
import '../widgets/round_button.dart';

class LevelOption {
  const LevelOption({
    required this.emoji,
    required this.name,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final String detail;
  final Color color;
  final VoidCallback onTap;
}

/// Shared "pick a level" screen with big, colorful buttons.
class LevelsScreen extends StatelessWidget {
  const LevelsScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.levels,
  });

  final String title;
  final String subtitle;
  final List<LevelOption> levels;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameBackground(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: RoundButton(
                  emoji: '🏠',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < levels.length; i++) ...[
                _LevelButton(option: levels[i]),
                if (i < levels.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({required this.option});

  final LevelOption option;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: option.color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: option.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    option.detail,
                    style: const TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.play_arrow, size: 36, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
