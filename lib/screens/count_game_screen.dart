import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/narrator.dart';
import '../services/app_language.dart';
import '../services/sound_effects.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/game_timer.dart';
import '../widgets/round_button.dart';
import 'animal_food_screen.dart';

/// How to split [count] animals across rows, chosen at random from the
/// arrangements that look natural.
///
/// A single wrapping row is deterministic: six animals always came out as five
/// and one, so a child learns the *shape* of six instead of counting it. Every
/// count now has several shapes — six can be 5+1, 4+2 or 3+3 — so the picture
/// changes between rounds and the only way through is to count.
///
/// Rows are non-increasing and capped at five, which is what keeps the result
/// looking deliberate rather than scattered.
List<int> countRows(int count, math.Random rng) {
  const maxPerRow = 5;
  const maxRows = 3;
  final options = <List<int>>[];

  void build(List<int> rows, int left) {
    if (left == 0) {
      // A lone animal on the top row reads as a mistake rather than a
      // grouping, so the first row always carries at least two.
      if (rows.first < 2 && count != 1) return;
      // One row of a single animal is a natural ending (5-4-1); two of them
      // (4-1-1) look scattered rather than arranged.
      if (rows.where((r) => r == 1).length > 1) return;
      options.add([...rows]);
      return;
    }
    if (rows.length == maxRows) return;
    final ceiling = math.min(rows.isEmpty ? maxPerRow : rows.last, left);
    for (var size = ceiling; size >= 1; size--) {
      build([...rows, size], left - size);
    }
  }

  build([], count);
  if (options.isEmpty) return [count];
  return options[rng.nextInt(options.length)];
}

/// Count the Animals!: the toddler sees a group of animal emojis and taps the
/// answer card (big digit + dot pattern) that matches how many animals there
/// are. 5 rounds per game — 3 on Easy, which has only 30 seconds; fewer wrong
/// taps means more stars.
class CountGameScreen extends StatefulWidget {
  const CountGameScreen({
    super.key,
    required this.maxCount,
    required this.level,
    this.random,
  }) : assert(maxCount >= 3, 'maxCount must be at least 3 (easy = 3)');

  /// Largest count this game ever asks for (3 = easy, 5 = medium, 10 = big).
  final int maxCount;

  /// Sets the clock: 30s / 1m / 2m for the whole game.
  final GameLevel level;

  /// Injectable RNG for tests; production uses a fresh [math.Random].
  final math.Random? random;

  @override
  State<CountGameScreen> createState() => _CountGameScreenState();
}

class _CountGameScreenState extends State<CountGameScreen>
    with WidgetsBindingObserver, TimedGame {
  /// Easy drops to 3 rounds: five rounds inside a 30-second clock is six
  /// seconds a question, which a four-year-old will not make.
  int get _roundsToWin => widget.level == GameLevel.easy ? 3 : 5;

  static const _answerColor = Color(0xFFFF9800);

  late final math.Random _rng = widget.random ?? math.Random();

  late int _answer; // how many animals are shown this round
  /// The animals to count, already split into the rows they are shown in.
  late List<List<String>> _rows;
  late List<int> _values; // the 3 card values, shuffled (includes _answer)

  final List<GlobalKey<_CountCardState>> _cardKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  int _round = 0; // rounds completed
  int _wrong = 0;
  bool _busy = false;
  bool _won = false;
  int? _happyIndex;
  Timer? _advance;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    // Tell a non-reader which game they just opened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Narrator.instance.announce(strings.countAnimals),
    );
    _newRound();
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  void _newRound() {
    _advance?.cancel();
    _advance = null;
    final answer = _rng.nextInt(widget.maxCount) + 1; // 1..maxCount
    final animals = [...kAnimalEmojis]..shuffle(_rng);
    final shown = animals.take(answer).toList();
    // Split them into rows before showing, so the arrangement changes from
    // round to round even when the count repeats.
    final rows = <List<String>>[];
    var index = 0;
    for (final size in countRows(answer, _rng)) {
      rows.add(shown.sublist(index, index + size));
      index += size;
    }
    setState(() {
      _answer = answer;
      _rows = rows;
      _values = _buildValues(answer);
      _happyIndex = null;
    });
  }

  /// The answer plus two distinct distractors, nearest counts first
  /// (N±1, then N±2…), always inside 1..maxCount.
  List<int> _buildValues(int answer) {
    final max = widget.maxCount;
    final candidates = [
      for (var v = 1; v <= max; v++)
        if (v != answer) v,
    ]..sort((a, b) => (a - answer).abs().compareTo((b - answer).abs()));
    return [answer, candidates[0], candidates[1]]..shuffle(_rng);
  }

  void _reset() {
    _advance?.cancel();
    _advance = null;
    resetClock();
    setState(() {
      _round = 0;
      _wrong = 0;
      _won = false;
      _busy = false;
    });
    _newRound();
  }

  void _onTap(int index) {
    if (_won || _busy || outOfTime) return;
    // The clock starts on the first answer, not on the screen appearing.
    startClock();
    if (_values[index] == _answer) {
      _busy = true;
      setState(() {
        _round++;
        _happyIndex = index;
      });
      HapticFeedback.mediumImpact();
      SoundEffects.instance.pop();
      // Brief green highlight, then the next round (or the win overlay).
      _advance?.cancel();
      _advance = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || outOfTime) return;
        _busy = false;
        if (_round >= _roundsToWin) {
          winClock();
          setState(() => _won = true);
        } else {
          _newRound();
        }
      });
    } else {
      _cardKeys[index].currentState?.shake();
      _wrong++;
      HapticFeedback.lightImpact();
      SoundEffects.instance.wrong();
    }
  }

  /// 3 stars for at most 1 wrong tap, 2 for up to 3, 1 otherwise.
  int get _stars {
    if (_wrong <= 1) return 3;
    if (_wrong <= 3) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
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
                      // Round progress dots.
                      Row(
                        children: [
                          for (var i = 0; i < _roundsToWin; i++)
                            Container(
                              key: ValueKey('round-dot-$i'),
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _round
                                    ? _answerColor
                                    : Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GameTimerBar(controller: clock),
                ),
                // The question: N animal emojis (wrapped) + a "?" cue.
                Container(
                  key: const ValueKey('question-pill'),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        // Explicit rows, not a Wrap: a Wrap always folds the
                        // same way for a given count, and that shape is what
                        // a child learns to read instead of counting.
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final row in _rows)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final animal in row)
                                    Text(
                                      animal,
                                      style: const TextStyle(fontSize: 40),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('❓', style: TextStyle(fontSize: 26)),
                    ],
                  ),
                ),
                const Spacer(),
                // The 3 answer cards: big digit + count-able dots.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Row(
                    children: [
                      for (var i = 0; i < _values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey('answer-${_values[i]}'),
                            child: _CountCard(
                              key: _cardKeys[i],
                              value: _values[i],
                              happy: _happyIndex == i,
                              onTap: () => _onTap(i),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🔢',
              title: strings.wonCount,
              stars: _stars,
              primaryLabel: strings.playAgain,
              onPrimary: _reset,
              secondaryLabel: strings.home,
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

class _CountCard extends StatefulWidget {
  const _CountCard({
    super.key,
    required this.value,
    required this.happy,
    required this.onTap,
  });

  final int value;
  final bool happy;
  final VoidCallback onTap;

  @override
  State<_CountCard> createState() => _CountCardState();
}

class _CountCardState extends State<_CountCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void shake() => _shake.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, _) {
          final v = _shake.value;
          // Decaying wiggle while shaking; the red tint is a triangle wave
          // (up then back to 0) so the card returns to white when done.
          // Slide, do not rotate. A rotation is still a transform over text, and
          // the glyph has to be re-rendered for every frame of it — with a
          // dozen large emoji on a Big board that is what empties the cache
          // and stops icons painting (golden rule 4). A translation just
          // moves pixels already drawn.
          final shift = math.sin(v * math.pi * 6) * 10 * (1 - v);
          final redTint = v < 0.5 ? v * 2 : (1 - v) * 2;
          // Rotation only — see the note in find_it_screen.dart: animating a
          // scale over text re-rasterises glyphs every frame and eventually
          // breaks emoji rendering app-wide.
          return Transform.translate(
            offset: Offset(shift, 0),
            child: Padding(
              padding: EdgeInsets.all(widget.happy ? 0 : 3),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    Colors.white,
                    const Color(0xFFFF8A80),
                    redTint * 0.8,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: widget.happy
                      ? Border.all(color: const Color(0xFF66BB6A), width: 4)
                      : null,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                // Scale digit + dots down (never up) so huge system text or
                // narrow cards can't push the dots past the card bounds.
                // The card is the digit and nothing else. It used to carry a
                // matching pattern of dots, which was a scaffold for a child
                // who cannot yet read numerals — but both the animals above
                // and the dots below were laid out with a centred `Wrap`, so
                // they wrapped into the *same shape*. Comparing the two
                // outlines answered the question without counting anything,
                // which is the entire point of the game.
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${widget.value}',
                          style: const TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF37474F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Plain circles laid out 5 per row (up to 2 rows for 10), sized to fit the
/// card so toddlers can point and count.
