import 'package:flutter/material.dart';

import '../services/music_route_observer.dart';
import '../services/music_service.dart';
import '../widgets/game_background.dart';
import '../widgets/game_timer.dart';
import '../widgets/pollie_bird.dart';
import '../widgets/round_button.dart';
import 'animal_food_screen.dart';
import 'bubble_pop_screen.dart';
import 'companion_screen.dart';
import 'count_game_screen.dart';
import 'find_it_screen.dart';
import 'jigsaw_game_screen.dart';
import 'levels_screen.dart';
import 'memory_game_screen.dart';

/// The app's landing screen: a big, colorful button for each game.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _musicOn = MusicService.instance.enabled;

  void _toggleMusic() {
    setState(() => _musicOn = !_musicOn);
    MusicService.instance.setEnabled(_musicOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pollie 🦜 — the talking companion, always one tap away. She bobs, and
      // after a few seconds says so, because nothing else on this screen tells
      // a grown-up the bird is a button.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TapToTalkBubble(onTap: () => _openPollie(context)),
          FloatingActionButton(
            onPressed: () => _openPollie(context),
            backgroundColor: Colors.white,
            elevation: 6,
            tooltip: 'Talk to Pollie',
            child: const PollieBird(),
          ),
        ],
      ),
      body: GameBackground(
        child: Stack(
          children: [
            _menu(context),
            // Floated over the column rather than placed in a row with the
            // title: anything beside the title pushes it off centre.
            Positioned(
              top: 8,
              right: 12,
              child: RoundButton(
                emoji: _musicOn ? '🔊' : '🔇',
                onTap: _toggleMusic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return Column(
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
                onTap: () => _openLevels(
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
                        onTap: () => _openGame(
                          context,
                          const JigsawGameScreen(
                            rows: 2,
                            cols: 2,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: '6 pieces',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const JigsawGameScreen(
                            rows: 3,
                            cols: 2,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: '9 pieces',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const JigsawGameScreen(
                            rows: 3,
                            cols: 3,
                            level: GameLevel.big,
                          ),
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
                onTap: () => _openLevels(
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
                        onTap: () => _openGame(
                          context,
                          const AnimalFoodGameScreen(
                            pairs: 3,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: '6 animals',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const AnimalFoodGameScreen(
                            pairs: 6,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: '9 animals',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const AnimalFoodGameScreen(
                            pairs: 9,
                            level: GameLevel.big,
                          ),
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
                onTap: () => _openLevels(
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
                        onTap: () => _openGame(
                          context,
                          const MemoryGameScreen(
                            pairs: 2,
                            columns: 2,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: '3 pairs',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const MemoryGameScreen(
                            pairs: 3,
                            columns: 3,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: '6 pairs',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const MemoryGameScreen(
                            pairs: 6,
                            columns: 4,
                            level: GameLevel.big,
                          ),
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
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: 'Bubble Pop 🎈',
                    subtitle: 'Pop them all before the time runs out!',
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: 'Easy',
                        detail: '6 bubbles',
                        color: const Color(0xFF4CAF50),
                        onTap: () => _openGame(
                          context,
                          const BubblePopScreen(
                            popsToWin: 6,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: '8 bubbles',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const BubblePopScreen(
                            popsToWin: 8,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: '12 bubbles',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const BubblePopScreen(
                            popsToWin: 12,
                            level: GameLevel.big,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _GameCard(
                emoji: '🔍',
                title: 'Find It!',
                subtitle: 'Find the animal that matches!',
                onTap: () => _openLevels(
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
                        onTap: () => _openGame(
                          context,
                          const FindItScreen(
                            cardsPerRound: 6,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: '9 animals',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const FindItScreen(
                            cardsPerRound: 9,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: '12 animals',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const FindItScreen(
                            cardsPerRound: 12,
                            level: GameLevel.big,
                          ),
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
                onTap: () => _openLevels(
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
                        onTap: () => _openGame(
                          context,
                          const CountGameScreen(
                            maxCount: 3,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: 'Medium',
                        detail: 'Count to 5',
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const CountGameScreen(
                            maxCount: 5,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: 'Big',
                        detail: 'Count to 10',
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const CountGameScreen(
                            maxCount: 10,
                            level: GameLevel.big,
                          ),
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
    );
  }

  /// Pollie's screen asks for silence: music there would fight her voice, and
  /// the microphone would hear it.
  void _openPollie(BuildContext context) =>
      _open(context, const CompanionScreen(), null);

  /// A level picker is still a menu, so the main theme keeps playing.
  void _openLevels(BuildContext context, Widget screen) =>
      _open(context, screen, MusicTrack.menu);

  void _openGame(BuildContext context, Widget screen) =>
      _open(context, screen, MusicTrack.game);

  /// Pushes [screen], tagging the route with the music it wants so
  /// [MusicRouteObserver] can switch tracks on both push and pop.
  void _open(BuildContext context, Widget screen, MusicTrack? track) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen, settings: musicRoute(track)),
    );
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
