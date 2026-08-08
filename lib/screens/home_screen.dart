import 'package:flutter/material.dart';

import '../widgets/game_background.dart';
import 'animal_food_screen.dart';
import 'bubble_pop_screen.dart';
import 'companion_screen.dart';
import 'count_game_screen.dart';
import 'find_it_screen.dart';
import 'jigsaw_game_screen.dart';
import 'levels_screen.dart';
import 'memory_game_screen.dart';

/// The app's landing screen: a big, colorful button for each game.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pollie 🦜 — the talking companion, always one tap away.
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(context, const CompanionScreen()),
        backgroundColor: Colors.white,
        elevation: 6,
        tooltip: 'Talk to Pollie',
        child: const Text('🦜', style: TextStyle(fontSize: 32)),
      ),
      body: GameBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              '🌈',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 56),
            ),
            const Text(
              'Tiny Tapsters',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fun games for little learners',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  _GameCard(
                    emoji: '🧩',
                    title: 'Jigsaw Puzzle',
                    subtitle: 'Put the picture back together!',
                    onTap: () => _open(
                      context,
                      LevelsScreen(
                        title: 'Jigsaw Puzzle 🧩',
                        subtitle: 'Put the picture back together!',
                        levels: [
                          LevelOption(
                            emoji: '🐣',
                            name: 'Easy',
                            detail: '4 pieces',
                            color: const Color(0xFF4CAF50),
                            onTap: () => _open(
                              context,
                              const JigsawGameScreen(rows: 2, cols: 2),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐥',
                            name: 'Medium',
                            detail: '6 pieces',
                            color: const Color(0xFFFF9800),
                            onTap: () => _open(
                              context,
                              const JigsawGameScreen(rows: 3, cols: 2),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐤',
                            name: 'Big',
                            detail: '9 pieces',
                            color: const Color(0xFFE91E63),
                            onTap: () => _open(
                              context,
                              const JigsawGameScreen(rows: 3, cols: 3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GameCard(
                    emoji: '🐰',
                    title: 'Animal Food',
                    subtitle: 'Feed each animal its food!',
                    onTap: () => _open(
                      context,
                      LevelsScreen(
                        title: 'Animal Food 🐰',
                        subtitle: 'Feed each animal its favorite food!',
                        levels: [
                          LevelOption(
                            emoji: '🐣',
                            name: 'Easy',
                            detail: '3 animals',
                            color: const Color(0xFF4CAF50),
                            onTap: () => _open(
                              context,
                              const AnimalFoodGameScreen(pairs: 3),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐥',
                            name: 'Medium',
                            detail: '6 animals',
                            color: const Color(0xFFFF9800),
                            onTap: () => _open(
                              context,
                              const AnimalFoodGameScreen(pairs: 6),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐤',
                            name: 'Big',
                            detail: '9 animals',
                            color: const Color(0xFFE91E63),
                            onTap: () => _open(
                              context,
                              const AnimalFoodGameScreen(pairs: 9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GameCard(
                    emoji: '🃏',
                    title: 'Memory Match',
                    subtitle: 'Flip the cards and find the pairs!',
                    onTap: () => _open(
                      context,
                      LevelsScreen(
                        title: 'Memory Match 🃏',
                        subtitle: 'Pick a level!',
                        levels: [
                          LevelOption(
                            emoji: '🐣',
                            name: 'Easy',
                            detail: '2 pairs',
                            color: const Color(0xFF4CAF50),
                            onTap: () => _open(
                              context,
                              const MemoryGameScreen(pairs: 2, columns: 2),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐥',
                            name: 'Medium',
                            detail: '3 pairs',
                            color: const Color(0xFFFF9800),
                            onTap: () => _open(
                              context,
                              const MemoryGameScreen(pairs: 3, columns: 3),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐤',
                            name: 'Big',
                            detail: '6 pairs',
                            color: const Color(0xFFE91E63),
                            onTap: () => _open(
                              context,
                              const MemoryGameScreen(pairs: 6, columns: 4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GameCard(
                    emoji: '🎈',
                    title: 'Bubble Pop',
                    subtitle: 'Pop the floating bubbles!',
                    onTap: () => _open(context, const BubblePopScreen()),
                  ),
                  const SizedBox(height: 12),
                  _GameCard(
                    emoji: '🔍',
                    title: 'Find It!',
                    subtitle: 'Find the animal that matches!',
                    onTap: () => _open(
                      context,
                      LevelsScreen(
                        title: 'Find It! 🔍',
                        subtitle: 'Pick a level!',
                        levels: [
                          LevelOption(
                            emoji: '🐣',
                            name: 'Easy',
                            detail: '6 animals',
                            color: const Color(0xFF4CAF50),
                            onTap: () => _open(
                              context,
                              const FindItScreen(cardsPerRound: 6),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐥',
                            name: 'Medium',
                            detail: '9 animals',
                            color: const Color(0xFFFF9800),
                            onTap: () => _open(
                              context,
                              const FindItScreen(cardsPerRound: 9),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐤',
                            name: 'Big',
                            detail: '12 animals',
                            color: const Color(0xFFE91E63),
                            onTap: () => _open(
                              context,
                              const FindItScreen(cardsPerRound: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GameCard(
                    emoji: '🔢',
                    title: 'Count the Animals!',
                    subtitle: 'Count the animals and tap the number!',
                    onTap: () => _open(
                      context,
                      LevelsScreen(
                        title: 'Count the Animals! 🔢',
                        subtitle: 'Pick a level!',
                        levels: [
                          LevelOption(
                            emoji: '🐣',
                            name: 'Easy',
                            detail: 'Count to 3',
                            color: const Color(0xFF4CAF50),
                            onTap: () => _open(
                              context,
                              const CountGameScreen(maxCount: 3),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐥',
                            name: 'Medium',
                            detail: 'Count to 5',
                            color: const Color(0xFFFF9800),
                            onTap: () => _open(
                              context,
                              const CountGameScreen(maxCount: 5),
                            ),
                          ),
                          LevelOption(
                            emoji: '🐤',
                            name: 'Big',
                            detail: 'Count to 10',
                            color: const Color(0xFFE91E63),
                            onTap: () => _open(
                              context,
                              const CountGameScreen(maxCount: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Made with ❤️ for our toddler',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 46)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 30, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}
