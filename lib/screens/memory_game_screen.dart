import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/narrator.dart';
import '../services/app_language.dart';
import '../services/sound_effects.dart';
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

  /// The pair being chosen right now: 0 or 1 cards.
  final List<int> _open = [];

  /// Pairs that have been chosen and are showing while they resolve. A child
  /// can start a new pair immediately instead of waiting — only the cards in
  /// a resolving pair are locked, not the whole board.
  final List<_Pending> _pending = [];

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
    // Tell a non-reader which game they just opened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Narrator.instance.announce(strings.memory),
    );
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
    _cancelPending();
    setState(() {
      _cards = _buildDeck();
      _open.clear();
      _moves = 0;
      _pairsFound = 0;
      _won = false;
    });
  }

  void _cancelPending() {
    for (final pending in _pending) {
      pending.timer.cancel();
    }
    _pending.clear();
  }

  @override
  void dispose() {
    _cancelPending();
    super.dispose();
  }

  /// A card the child cannot touch: already matched, already part of the pair
  /// being chosen, or part of a pair still resolving.
  bool _locked(int index) =>
      _cards[index].matched ||
      _open.contains(index) ||
      _pending.any((p) => p.first == index || p.second == index);

  bool _faceUp(int index) =>
      _cards[index].matched ||
      _open.contains(index) ||
      _pending.any((p) => p.first == index || p.second == index);

  void _tapCard(int index) {
    if (_won || outOfTime || _locked(index)) return;
    startClock();

    setState(() => _open.add(index));
    HapticFeedback.selectionClick();
    if (_open.length < 2) return;

    // The pair is complete: hand it to a timer of its own and free the board
    // straight away, so the next two cards can be turned while this one is
    // still showing.
    _moves++;
    final first = _open[0];
    final second = _open[1];
    _open.clear();
    late final _Pending pending;
    pending = _Pending(
      first: first,
      second: second,
      timer: Timer(const Duration(milliseconds: 750), () {
        if (!mounted) return;
        _resolve(pending);
      }),
    );
    _pending.add(pending);
  }

  void _resolve(_Pending pending) {
    final matched = _cards[pending.first].emoji == _cards[pending.second].emoji;
    setState(() {
      _pending.remove(pending);
      if (matched) {
        _cards[pending.first].matched = true;
        _cards[pending.second].matched = true;
        _pairsFound++;
      }
    });
    if (matched) {
      HapticFeedback.mediumImpact();
      SoundEffects.instance.pop();
    } else {
      SoundEffects.instance.wrong();
    }
    if (_pairsFound == widget.pairs && !_won) {
      winClock();
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted || outOfTime) return;
        setState(() => _won = true);
      });
    }
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
                          strings.pairsLeft(pairsLeft),
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
              title: strings.wonMemory,
              stars: _stars,
              primaryLabel: strings.playAgain,
              onPrimary: _reset,
              secondaryLabel: strings.moreGames,
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
    // No AnimatedScale around the card: animating a scale over the emoji
    // re-rasterises the glyph every frame and eventually stops emoji painting
    // app-wide. A matched card is shown by its green face instead.
    return GestureDetector(
      onTap: () => _tapCard(index),
      child: FlipCard(
        faceUp: _faceUp(index),
        front: _CardFace(emoji: card.emoji, matched: card.matched),
        back: const _CardBack(),
      ),
    );
  }
}

/// A chosen pair waiting to be revealed as a match or not.
class _Pending {
  _Pending({required this.first, required this.second, required this.timer});

  final int first;
  final int second;
  final Timer timer;
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
