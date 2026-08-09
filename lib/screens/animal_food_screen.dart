import 'package:flutter/material.dart';

import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/game_timer.dart';
import '../widgets/pair_drag_game.dart';
import '../widgets/round_button.dart';

/// Animal Food: the slots show each animal's favorite food (carrot, hay,
/// honey…) and the drawer holds the animals. Drag the rabbit to the carrot,
/// the cow to the hay, the bear to the honey! Getting a pair right reveals
/// the food's name under its slot.
///
/// The 15 animals shared across games (Count the Animals! picks its question
/// emojis from this pool). Must stay the single source of truth for the
/// animal half of [_allPairs].
const kAnimalEmojis = [
  '🐰', // 0 rabbit → carrot
  '🐮', // 1 cow → hay
  '🐴', // 2 horse → apple
  '🐶', // 3 dog → bone
  '🐱', // 4 cat → fish
  '🐭', // 5 mouse → cheese
  '🐵', // 6 monkey → banana
  '🐻', // 7 bear → honey
  '🐔', // 8 chicken → corn
  '🦁', // 9 lion → meat
  '🦒', // 10 giraffe → leaves
  '🐘', // 11 elephant → branches
  '🐸', // 12 frog → bug
  '🐧', // 13 penguin → shrimp
  '🦋', // 14 butterfly → flower
];

class AnimalFoodGameScreen extends StatefulWidget {
  const AnimalFoodGameScreen({
    super.key,
    required this.pairs,
    required this.level,
  });

  final int pairs;

  /// Sets the clock: 30s / 1m / 2m for the whole board.
  final GameLevel level;

  @override
  State<AnimalFoodGameScreen> createState() => _AnimalFoodGameScreenState();
}

class _AnimalFoodGameScreenState extends State<AnimalFoodGameScreen>
    with WidgetsBindingObserver, TimedGame {
  /// Animal, the food it eats, and the food's name (shown once the child
  /// gets the match right, so a grown-up can say the word out loud).
  ///
  /// Accuracy notes, because these were picked deliberately:
  /// - Cow eats **hay**, not the seedling 🌱 that used to be here — that
  ///   glyph is a sprout and read as "some plant" rather than grass.
  /// - Horse gets an apple. It is a treat rather than a staple, but feeding
  ///   a horse an apple over the fence is a real, long-standing practice.
  /// - Elephant eats **branches** — grass, leaves and bark are what it
  ///   actually lives on. The watermelon that used to be here is a zoo treat,
  ///   and the peanut everyone pictures is a myth.
  /// - Rabbit/carrot and mouse/cheese are both closer to cartoon lore than
  ///   diet (rabbits live on hay and greens; mice prefer grain). They stay
  ///   because they are how a toddler already understands those animals.
  static final _allPairs = [
    (kAnimalEmojis[0], '🥕', 'carrot'),
    (kAnimalEmojis[1], '🌾', 'hay'),
    (kAnimalEmojis[2], '🍎', 'apple'),
    (kAnimalEmojis[3], '🦴', 'bone'),
    (kAnimalEmojis[4], '🐟', 'fish'),
    (kAnimalEmojis[5], '🧀', 'cheese'),
    (kAnimalEmojis[6], '🍌', 'banana'),
    (kAnimalEmojis[7], '🍯', 'honey'),
    (kAnimalEmojis[8], '🌽', 'corn'),
    (kAnimalEmojis[9], '🥩', 'meat'),
    (kAnimalEmojis[10], '🍃', 'leaves'),
    (kAnimalEmojis[11], '🌿', 'branches'),
    (kAnimalEmojis[12], '🐛', 'bug'),
    (kAnimalEmojis[13], '🦐', 'shrimp'),
    (kAnimalEmojis[14], '🌸', 'flower'),
  ];

  /// Foods that look too alike to share a board. 🍃 and 🌿 are both green
  /// leaves; with both on screen the child cannot tell which belongs to the
  /// giraffe and which to the elephant, so the puzzle stops being solvable by
  /// looking. One of the two is dropped from every game.
  static const _lookAlikeFoods = ['🍃', '🌿'];

  late List<(String, String, String)> _pairs;
  late Key _gameKey;
  bool _won = false;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    _pairs = _shuffledPairs();
    _gameKey = UniqueKey();
  }

  /// Picks this game's pairs, keeping at most one of the look-alike foods so
  /// two near-identical green leaves never share a board.
  List<(String, String, String)> _shuffledPairs() {
    final pool = [..._allPairs]..shuffle();
    final keptLookAlike = (<String>[..._lookAlikeFoods]..shuffle()).first;
    pool.removeWhere(
      (pair) => _lookAlikeFoods.contains(pair.$2) && pair.$2 != keptLookAlike,
    );
    return pool.take(widget.pairs).toList();
  }

  void _reset() {
    resetClock();
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
                      // Expanded rather than Spacer-Text-Spacer: on a 360dp
                      // phone the title plus two buttons is wider than the
                      // row, and Spacers cannot give back space they do not
                      // have.
                      const Expanded(
                        child: Text(
                          'Feed the animals!',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GameTimerBar(controller: clock),
                ),
                Expanded(
                  child: PairDragGame(
                    key: _gameKey,
                    pairCount: pairs.length,
                    maxCols: pairs.length <= 3 ? pairs.length : 3,
                    // The food's name appears here once the child gets the
                    // match right — a reward and a word for a grown-up to say
                    // aloud, never a hint before the answer.
                    slotCaption: (index) => pairs[index].$3,
                    // Room under each slot for that caption; the default 12
                    // would put the word into the next row of slots.
                    gap: 24,
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
                    onFirstMove: startClock,
                    onCompleted: () {
                      winClock();
                      setState(() => _won = true);
                    },
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
          if (outOfTime)
            GameOverOverlay(
              onRetry: _reset,
              onHome: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}
