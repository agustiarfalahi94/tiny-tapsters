import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/celebration_overlay.dart';
import '../widgets/flip_card.dart';
import '../widgets/game_background.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/game_timer.dart';
import '../widgets/round_button.dart';

/// A toddler-friendly memory matching game.
///
/// The deck holds `pairs` matching pairs laid out on a grid with `columns`
/// columns. Tapping cards flips them with a 3D animation; matching pairs stay
/// face-up and a confetti celebration appears when the board is complete.
class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({
    super.key,
    required this.pairs,
    required this.columns,
    required this.level,
  });

  final int pairs;
  final int columns;

  /// Sets the clock: 30s / 1m / 2m for the whole board.
  final GameLevel level;

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen>
    with WidgetsBindingObserver, TimedGame {
  static const _emojiPool = [
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
    '🐤',
    '🦄',
    '🐙',
    '🦋',
    '🐢',
    '🐠',
  ];

  late List<_Card> _cards;
  final List<int> _open = [];
  bool _busy = false;
  int _moves = 0;
  int _pairsFound = 0;
  bool _won = false;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    _cards = _buildDeck();
  }

  List<_Card> _buildDeck() {
    final pool = [..._emojiPool]..shuffle();
    final chosen = pool.take(widget.pairs).toList();
    final items = [...chosen, ...chosen]..shuffle();
    return [for (var i = 0; i < items.length; i++) _Card(emoji: items[i])];
  }

  void _reset() {
    resetClock();
    setState(() {
      _cards = _buildDeck();
      _open.clear();
      _busy = false;
      _moves = 0;
      _pairsFound = 0;
      _won = false;
    });
  }

  void _tapCard(int index) {
    if (_busy || _won || outOfTime) return;
    startClock();
    final card = _cards[index];
    if (card.matched || _open.contains(index)) return;

    setState(() => _open.add(index));
    HapticFeedback.selectionClick();

    if (_open.length < 2) return;

    _busy = true;
    _moves++;
    final first = _open[0];
    final second = _open[1];
    Future.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      if (_cards[first].emoji == _cards[second].emoji) {
        setState(() {
          _cards[first].matched = true;
          _cards[second].matched = true;
          _open.clear();
          _pairsFound++;
        });
        HapticFeedback.mediumImpact();
        if (_pairsFound == widget.pairs) {
          winClock();
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted || outOfTime) return;
            setState(() => _won = true);
          });
        }
      } else {
        setState(_open.clear);
      }
      _busy = false;
    });
  }

  /// 3 stars for a quick win, 2 for a decent one, 1 otherwise.
  int get _stars {
    final target = widget.pairs;
    if (_moves <= target + 1) return 3;
    if (_moves <= target * 2 + 1) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final pairsLeft = widget.pairs - _pairsFound;
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
                      // phone the title plus two buttons can be wider than the
                      // row, and Spacers cannot give back space they do not
                      // have.
                      Expanded(
                        child: Text(
                          'Pairs left: $pairsLeft',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  child: GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: widget.columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _cards.length,
                    itemBuilder: (context, index) => _buildCard(index),
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              title: 'Yay! You did it!',
              stars: _stars,
              primaryLabel: 'Play again 🔁',
              onPrimary: _reset,
              secondaryLabel: 'More games 🏠',
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

  Widget _buildCard(int index) {
    final card = _cards[index];
    final faceUp = card.matched || _open.contains(index);
    return GestureDetector(
      onTap: () => _tapCard(index),
      child: AnimatedScale(
        scale: card.matched ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: FlipCard(
          faceUp: faceUp,
          front: _CardFace(emoji: card.emoji, matched: card.matched),
          back: const _CardBack(),
        ),
      ),
    );
  }
}

class _Card {
  _Card({required this.emoji});

  final String emoji;
  bool matched = false;
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.emoji, required this.matched});

  final String emoji;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: matched ? const Color(0xFFC8F7C5) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: matched ? const Color(0xFF66BB6A) : Colors.black12,
              width: 3,
            ),
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
              emoji,
              style: TextStyle(fontSize: constraints.maxWidth * 0.55),
            ),
          ),
        );
      },
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9C6BFF), Color(0xFF6A3DE8)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: const Center(child: Text('⭐', style: TextStyle(fontSize: 34))),
    );
  }
}
