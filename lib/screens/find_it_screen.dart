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

/// Find It!: the game shows "Find the 🐶!" and a grid of animals; the toddler
/// taps the matching one. Wrong taps just wobble the card. Find 5 animals to
/// win — 3 on Easy, which has only 30 seconds; fewer wrong taps means more
/// stars.
class FindItScreen extends StatefulWidget {
  const FindItScreen({super.key, required this.level, this.cardsPerRound = 6});

  /// Number of cards in the grid (6 = easy, 9 = medium, 12 = big).
  final int cardsPerRound;

  /// Sets the clock: 30s / 1m / 2m for the whole game.
  final GameLevel level;

  @override
  State<FindItScreen> createState() => _FindItScreenState();
}

class _FindItScreenState extends State<FindItScreen>
    with WidgetsBindingObserver, TimedGame {
  static const _pool = [
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐸',
    '🐵',
    '🐔',
    '🐧',
    '🐦',
    '🦄',
    '🐙',
    '🦋',
    '🐢',
  ];

  /// Easy drops to 3 rounds: five rounds inside a 30-second clock is six
  /// seconds a question, which a four-year-old will not make.
  int get _roundsToWin => widget.level == GameLevel.easy ? 3 : 5;

  late final int _cardsPerRound = widget.cardsPerRound;
  late String _target;
  late List<String> _cards;
  late final List<GlobalKey<_FindCardState>> _cardKeys;

  int _found = 0;
  int _wrong = 0;
  int? _happyIndex;

  /// Animals already asked for this game — never ask twice.
  final _asked = <String>{};
  bool _won = false;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    // Tell a non-reader which game they just opened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Narrator.instance.announce(strings.findIt),
    );
    _cardKeys = List.generate(_cardsPerRound, (_) => GlobalKey());
    _newRound();
  }

  void _newRound() {
    // Never ask for the same animal twice in one game.
    var unasked = _pool.where((e) => !_asked.contains(e)).toList();
    if (unasked.isEmpty) unasked = _pool.where((e) => e != _target).toList();
    _target = (unasked..shuffle()).first;
    _asked.add(_target);
    final pool = _pool.where((e) => e != _target).toList()..shuffle();
    _cards = [...pool.take(_cardsPerRound - 1), _target]..shuffle();
    setState(() => _happyIndex = null);
  }

  void _reset() {
    resetClock();
    _asked.clear();
    setState(() {
      _found = 0;
      _wrong = 0;
      _won = false;
    });
    _newRound();
  }

  void _onTap(int index) {
    if (_won || outOfTime) return;
    // The clock starts on the first answer, not on the screen appearing: a
    // child looking at a fresh board should not be losing time yet.
    startClock();
    if (_cards[index] == _target) {
      setState(() {
        _found++;
        _happyIndex = index;
      });
      HapticFeedback.mediumImpact();
      SoundEffects.instance.pop();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        if (_outOfTimeOrWon) return;
        if (_found >= _roundsToWin) {
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

  /// The delayed round advance must not fire onto a game that ran out of
  /// time (or was already won) while the 350ms beat was in flight.
  bool get _outOfTimeOrWon => outOfTime || _won;

  int get _stars {
    if (_wrong == 0) return 3;
    if (_wrong <= 2) return 2;
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
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _found
                                    ? const Color(0xFFFF9800)
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
                // Prompt: "Find the 🐶!"
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.findThe,
                        style: TextStyle(fontSize: 20, color: Colors.black87),
                      ),
                      Text(_target, style: const TextStyle(fontSize: 44)),
                      const Text(
                        '!',
                        style: TextStyle(fontSize: 20, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                    children: [
                      for (var i = 0; i < _cards.length; i++)
                        _FindCard(
                          key: _cardKeys[i],
                          emoji: _cards[i],
                          happy: _happyIndex == i,
                          onTap: () => _onTap(i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🔍',
              title: strings.wonFindIt,
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

class _FindCard extends StatefulWidget {
  const _FindCard({
    super.key,
    required this.emoji,
    required this.happy,
    required this.onTap,
  });

  final String emoji;
  final bool happy;
  final VoidCallback onTap;

  @override
  State<_FindCard> createState() => _FindCardState();
}

class _FindCardState extends State<_FindCard>
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
          // Rotation only. An AnimatedScale here re-rasterised the emoji
          // glyph every frame, and on the test device that eventually stopped
          // animals painting at all — they reappeared only while another
          // repaint (holding the back gesture) forced the raster cache to
          // rebuild. The correct answer is shown by the green border instead.
          return Transform.translate(
            offset: Offset(shift, 0),
            child: Padding(
              padding: EdgeInsets.all(widget.happy ? 0 : 4),
              child: Container(
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
                child: Center(
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 46),
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
