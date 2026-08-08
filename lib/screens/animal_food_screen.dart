import 'package:flutter/material.dart';

import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/pair_drag_game.dart';
import '../widgets/round_button.dart';

/// Animal Food: the slots show each animal's favorite food (carrot, grass,
/// hay…) and the drawer holds the animals. Drag the rabbit to the carrot, the
/// cow to the grass, the horse to the hay!
/// The 15 animals shared across games (Count the Animals! picks its question
/// emojis from this pool). Must stay the single source of truth for the
/// animal half of [_allPairs].
const kAnimalEmojis = [
  '🐰', // 0 rabbit → carrot
  '🐮', // 1 cow → grass
  '🐴', // 2 horse → apple (a classic horse treat)
  '🐶', // 3 dog → bone
  '🐱', // 4 cat → fish
  '🐭', // 5 mouse → cheese
  '🐵', // 6 monkey → banana
  '🐻', // 7 bear → honey
  '🐔', // 8 chicken → corn
  '🦁', // 9 lion → meat
  '🦒', // 10 giraffe → leaves
  '🐘', // 11 elephant → watermelon
  '🐸', // 12 frog → bug
  '🐧', // 13 penguin → shrimp
  '🦋', // 14 butterfly → flower
];

class AnimalFoodGameScreen extends StatefulWidget {
  const AnimalFoodGameScreen({super.key, required this.pairs});

  final int pairs;

  @override
  State<AnimalFoodGameScreen> createState() => _AnimalFoodGameScreenState();
}

class _AnimalFoodGameScreenState extends State<AnimalFoodGameScreen> {
  // 15 animal/food pairs with strong toddler stereotypes and clearly
  // distinct food emojis. Each game picks a shuffled subset.
  static final _allPairs = [
    (kAnimalEmojis[0], '🥕'), // rabbit → carrot
    (kAnimalEmojis[1], '🌱'), // cow → grass
    (kAnimalEmojis[2], '🍎'), // horse → apple (a classic horse treat)
    (kAnimalEmojis[3], '🦴'), // dog → bone
    (kAnimalEmojis[4], '🐟'), // cat → fish
    (kAnimalEmojis[5], '🧀'), // mouse → cheese
    (kAnimalEmojis[6], '🍌'), // monkey → banana
    (kAnimalEmojis[7], '🍯'), // bear → honey
    (kAnimalEmojis[8], '🌽'), // chicken → corn
    (kAnimalEmojis[9], '🥩'), // lion → meat
    (kAnimalEmojis[10], '🍃'), // giraffe → leaves
    (kAnimalEmojis[11], '🍉'), // elephant → watermelon
    (kAnimalEmojis[12], '🐛'), // frog → bug
    (kAnimalEmojis[13], '🦐'), // penguin → shrimp
    (kAnimalEmojis[14], '🌸'), // butterfly → flower
  ];

  late List<(String, String)> _pairs;
  late Key _gameKey;
  bool _won = false;

  @override
  void initState() {
    super.initState();
    _pairs = _shuffledPairs();
    _gameKey = UniqueKey();
  }

  List<(String, String)> _shuffledPairs() {
    return ([..._allPairs]..shuffle()).take(widget.pairs).toList();
  }

  void _reset() {
    setState(() {
      _pairs = _shuffledPairs();
      _won = false;
      _gameKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pairs = _pairs;
    return Scaffold(
      body: Stack(
        children: [
          GameBackground(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      RoundButton(
                        emoji: '🏠',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      const Text(
                        'Feed the animals!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                      ),
                      const Spacer(),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                Expanded(
                  child: PairDragGame(
                    key: _gameKey,
                    pairCount: pairs.length,
                    maxCols: pairs.length <= 3 ? pairs.length : 3,
                    slotBuilder: (context, index, slotSize) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white70, width: 3),
                        ),
                        child: Center(
                          child: Text(
                            pairs[index].$2,
                            style: TextStyle(fontSize: slotSize * 0.5),
                          ),
                        ),
                      );
                    },
                    pieceBuilder: (context, index, pieceSize, slotSize) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            pairs[index].$1,
                            style: TextStyle(fontSize: pieceSize * 0.55),
                          ),
                        ),
                      );
                    },
                    onCompleted: () => setState(() => _won = true),
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🥕',
              title: 'Yay! All fed!',
              primaryLabel: 'Play again 🔁',
              onPrimary: _reset,
              secondaryLabel: 'Levels 🏠',
              onSecondary: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}
