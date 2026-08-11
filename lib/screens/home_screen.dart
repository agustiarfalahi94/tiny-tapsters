import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../services/music_route_observer.dart';
import '../services/music_service.dart';
import '../widgets/game_background.dart';
import '../widgets/game_timer.dart';
import '../widgets/pollie_bird.dart';
import '../widgets/round_button.dart';
import 'animal_food_screen.dart';
import 'animal_sound_screen.dart';
import 'bubble_pop_screen.dart';
import 'companion_screen.dart';
import 'count_game_screen.dart';
import 'credits_screen.dart';
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
            tooltip: strings.talkToPollie,
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
            // For the grown-up: several animal calls are CC BY, which obliges
            // us to credit their authors in the app, not just in the repo.
            Positioned(
              top: 8,
              left: 12,
              child: RoundButton(
                emoji: 'ℹ️',
                onTap: () =>
                    _open(context, const CreditsScreen(), MusicTrack.menu),
              ),
            ),
            // The language switch. A flag rather than a word, so it means the
            // same thing whichever language you cannot read.
            Positioned(
              top: 8,
              left: 78,
              child: RoundButton(
                emoji: AppLanguageService.instance.current.value.flag,
                onTap: AppLanguageService.instance.toggle,
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
        Text(
          strings.appTagline,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              _GameCard(
                emoji: '🧩',
                title: strings.jigsaw,
                subtitle: strings.jigsawSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.jigsaw} 🧩',
                    subtitle: strings.jigsawSubtitle,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.pieces(4),
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
                        name: strings.medium,
                        detail: strings.pieces(6),
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
                        name: strings.big,
                        detail: strings.pieces(9),
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
                title: strings.animalFood,
                subtitle: strings.animalFoodSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.animalFood} 🐰',
                    subtitle: strings.animalFoodSubtitleLong,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.animals(3),
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
                        name: strings.medium,
                        detail: strings.animals(6),
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
                        name: strings.big,
                        detail: strings.animals(9),
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
                title: strings.memory,
                subtitle: strings.memorySubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.memory} 🃏',
                    subtitle: strings.pickALevel,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.pairs(2),
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
                        name: strings.medium,
                        detail: strings.pairs(3),
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
                        name: strings.big,
                        detail: strings.pairs(6),
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
                title: strings.bubblePop,
                subtitle: strings.bubblePopSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.bubblePop} 🎈',
                    subtitle: strings.bubblePopGoal,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.bubbles(6),
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
                        name: strings.medium,
                        detail: strings.bubbles(8),
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
                        name: strings.big,
                        detail: strings.bubbles(12),
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
                title: strings.findIt,
                subtitle: strings.findItSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.findIt} 🔍',
                    subtitle: strings.pickALevel,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.animals(6),
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
                        name: strings.medium,
                        detail: strings.animals(9),
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
                        name: strings.big,
                        detail: strings.animals(12),
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
                emoji: '🔊',
                title: strings.whichAnimal,
                subtitle: strings.whichAnimalSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.whichAnimal} 🔊',
                    subtitle: strings.whichAnimalGoal,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.choices(2),
                        color: const Color(0xFF4CAF50),
                        onTap: () => _openGame(
                          context,
                          const AnimalSoundScreen(
                            choices: 2,
                            level: GameLevel.easy,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐥',
                        name: strings.medium,
                        detail: strings.choices(3),
                        color: const Color(0xFFFF9800),
                        onTap: () => _openGame(
                          context,
                          const AnimalSoundScreen(
                            choices: 3,
                            level: GameLevel.medium,
                          ),
                        ),
                      ),
                      LevelOption(
                        emoji: '🐤',
                        name: strings.big,
                        detail: strings.choices(5),
                        color: const Color(0xFFE91E63),
                        onTap: () => _openGame(
                          context,
                          const AnimalSoundScreen(
                            choices: 5,
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
                title: strings.countAnimals,
                subtitle: strings.countAnimalsSubtitle,
                onTap: () => _openLevels(
                  context,
                  LevelsScreen(
                    title: '${strings.countAnimals} 🔢',
                    subtitle: strings.pickALevel,
                    levels: [
                      LevelOption(
                        emoji: '🐣',
                        name: strings.easy,
                        detail: strings.countTo(3),
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
                        name: strings.medium,
                        detail: strings.countTo(5),
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
                        name: strings.big,
                        detail: strings.countTo(10),
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
        Padding(
          // Kept clear of Pollie's button in the corner. The English line is
          // short enough to miss it; the Indonesian one is not, and ran
          // underneath the bird.
          padding: const EdgeInsets.only(left: 68, right: 68, bottom: 10),
          child: Text(
            strings.madeWithLove,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 14, color: Colors.white),
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
