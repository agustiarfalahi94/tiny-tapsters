import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/narrator.dart';
import '../services/app_language.dart';
import '../services/sound_effects.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/game_timer.dart' show GameLevel;
import '../widgets/round_button.dart';

/// Bubble Pop: bubbles drift around the screen, and one animal is the one to
/// catch. Pop that animal the required number of times; popping anything else
/// costs a star.
///
/// It has been three games. It was endless escalating rounds, then one timed
/// round of popping anything. Both were just tapping — nothing was being
/// *decided*. Now there is a right answer on screen, which is what makes it a
/// game rather than an activity, and the clock is gone: rushing a child into
/// grabbing the wrong bubble punishes exactly the care the game is asking for.
class BubblePopScreen extends StatefulWidget {
  const BubblePopScreen({
    super.key,
    required this.level,
    required this.popsToWin,
    required this.bubbleCount,
    this.random,
  });

  /// How many times the target animal must be caught (3 / 6 / 10).
  final int popsToWin;

  /// How many bubbles drift at once (5 / 10 / 15).
  final int bubbleCount;

  /// Chooses the numbers only — this screen has no clock.
  final GameLevel level;

  final math.Random? random;

  @override
  State<BubblePopScreen> createState() => _BubblePopScreenState();
}

class _BubblePopScreenState extends State<BubblePopScreen>
    with SingleTickerProviderStateMixin {
  /// Animals only. The game asks the child to "catch the right animal", and
  /// the pool used to include ⭐ 🌸 🌈 🍓 — so it could open by asking for a
  /// rainbow. Twelve faces is enough variety for fifteen bubbles; duplicates
  /// among the ones to avoid are fine and expected.
  static const _bubbleEmojis = [
    '🐶',
    '🐱',
    '🐸',
    '🐢',
    '🦋',
    '🐙',
    '🐰',
    '🐭',
    '🐷',
    '🐥',
    '🐝',
    '🐬',
  ];
  static const _bubbleSize = 90.0;

  /// Roughly how many of the drifting bubbles should be the wanted animal.
  /// Too few and the child hunts; too many and there is nothing to decide.
  static const _targetShare = 0.35;

  int get _popsPerRound => widget.popsToWin;

  /// The animal to catch this game.
  late String _target;

  /// Bubbles popped that were not the target.
  int _wrong = 0;

  late final AnimationController _float;
  late List<_BubbleData> _bubbles;
  late final math.Random _rnd = widget.random ?? math.Random();

  int _popped = 0;
  bool _won = false;

  /// True once the round's pop target is reached. Guards input during the
  /// short beat before `_won` flips and the celebration overlay appears —
  /// without it, bubbles tapped in that window kept incrementing `_popped`
  /// past `_popsPerRound`, showing a negative "more!" count. The beat is
  /// 400ms: exactly the pop animation, so the last bubble is seen to burst
  /// and not a millisecond of dead air more.
  bool _roundComplete = false;

  /// The pending "show the celebration" timer scheduled by the pop that
  /// completes a round. Must be cancelled on every path that resets the
  /// round (manual reset, next round) and on dispose — otherwise it fires
  /// late and sets `_won = true` over a round the player has already
  /// restarted, popping up the celebration overlay mid-attempt.
  Timer? _winTimer;

  @override
  void initState() {
    super.initState();
    // Tell a non-reader which game they just opened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Narrator.instance.announce(strings.bubblePop),
    );
    _float =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..addStatusListener(_onFloatStatus)
          ..forward();
    _target = _bubbleEmojis[_rnd.nextInt(_bubbleEmojis.length)];
    _bubbles = [];
    for (var i = 0; i < widget.bubbleCount; i++) {
      _bubbles.add(_spawn());
    }
  }

  @override
  void dispose() {
    _winTimer?.cancel();
    _float.dispose();
    super.dispose();
  }

  /// Keeps the drifting animation going forever without a visible jump:
  /// when a cycle completes, each bubble's current position is folded into
  /// its base so the next cycle starts exactly where this one ended.
  void _onFloatStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      for (final bubble in _bubbles) {
        bubble.x = (bubble.x + bubble.vx) % 1.0;
        bubble.y = (bubble.y + bubble.vy) % 1.0;
      }
      _float.forward(from: 0);
    }
  }

  /// A fresh bubble.
  ///
  /// Enough of them carry the wanted animal that it is always findable, and
  /// the rest are anything else. Duplicates among the *others* are fine — with
  /// fifteen bubbles and ten faces they are unavoidable, and only the target
  /// needs to be unmistakable.
  _BubbleData _spawn({_BubbleData? replacing}) {
    final others = [
      for (final b in _bubbles)
        if (!identical(b, replacing)) b,
    ];
    final targetsOut = others.where((b) => b.emoji == _target).length;
    final wanted = math.max(1, (widget.bubbleCount * _targetShare).round());
    final needsTarget = targetsOut < wanted;
    final pool = _bubbleEmojis.where((e) => e != _target).toList();
    return _BubbleData(
      emoji: needsTarget ? _target : pool[_rnd.nextInt(pool.length)],
      x: _rnd.nextDouble(),
      y: _rnd.nextDouble(),
      vx: (0.10 + _rnd.nextDouble() * 0.12) * (_rnd.nextBool() ? 1 : -1),
      vy: (0.10 + _rnd.nextDouble() * 0.12) * (_rnd.nextBool() ? 1 : -1),
      phase: _rnd.nextDouble(),
    );
  }

  void _pop(_BubbleData bubble) {
    if (bubble.popping || _won || _roundComplete) return;
    if (bubble.emoji != _target) {
      // Wrong animal: it stays on screen. Popping it would hide the mistake,
      // and the child needs to see that this one is still there to be avoided.
      _wrong++;
      HapticFeedback.lightImpact();
      SoundEffects.instance.wrong();
      return;
    }
    setState(() {
      bubble.popTick++;
      bubble.popping = true;
      _popped++;
      // Set synchronously, not in the delayed callback below — otherwise
      // bubbles tapped during the win beat still count, pushing
      // _popped past _popsPerRound.
      if (_popped >= _popsPerRound) _roundComplete = true;
    });
    HapticFeedback.lightImpact();
    SoundEffects.instance.pop();
    if (_popped >= _popsPerRound) {
      _winTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() => _won = true);
      });
    }
  }

  /// Three stars for catching only the right animal — the same scale the
  /// other games use.
  int get _stars {
    if (_wrong == 0) return 3;
    if (_wrong <= 2) return 2;
    return 1;
  }

  void _reset() {
    _winTimer?.cancel();
    setState(() {
      _target = _bubbleEmojis[_rnd.nextInt(_bubbleEmojis.length)];
      _popped = 0;
      _wrong = 0;
      _won = false;
      _roundComplete = false;
      for (var i = 0; i < _bubbles.length; i++) {
        _bubbles[i] = _spawn();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The bubbles speed up as the round fills, so the last few are the
    // hardest — the escalation the old between-rounds version had.
    final speedFactor = 1 + 0.6 * (_popped / _popsPerRound);
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
                      // Which animal to catch, and how many are still
                      // wanted. The emoji does the work; the number beside it
                      // is for the grown-up.
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_target, style: const TextStyle(fontSize: 34)),
                            const SizedBox(width: 8),
                            Text(
                              '×${math.max(0, _popsPerRound - _popped)}',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: math.min(1.0, _popped / _popsPerRound),
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.4),
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return AnimatedBuilder(
                        animation: _float,
                        builder: (context, _) {
                          final t = _float.value;
                          return Stack(
                            children: [
                              for (final bubble in _bubbles)
                                Positioned(
                                  left:
                                      ((bubble.x +
                                                  t * bubble.vx * speedFactor +
                                                  math.sin(
                                                        2 * math.pi * t * 6 +
                                                            bubble.phase,
                                                      ) *
                                                      0.07) %
                                              1.0) *
                                          w -
                                      _bubbleSize / 2,
                                  top:
                                      ((bubble.y +
                                                  t * bubble.vy * speedFactor +
                                                  math.cos(
                                                        2 * math.pi * t * 6 +
                                                            bubble.phase,
                                                      ) *
                                                      0.07) %
                                              1.0) *
                                          h -
                                      _bubbleSize / 2,
                                  child: bubble.popping
                                      ? _PopSparkle(
                                          bubble: bubble,
                                          onFinished: () => setState(() {
                                            bubble.popping = false;
                                            final fresh = _spawn(
                                              replacing: bubble,
                                            );
                                            bubble
                                              ..emoji = fresh.emoji
                                              ..x = fresh.x
                                              ..y = fresh.y
                                              ..vx = fresh.vx
                                              ..vy = fresh.vy
                                              ..phase = fresh.phase;
                                          }),
                                        )
                                      : _Bubble(
                                          bubble: bubble,
                                          onTap: () => _pop(bubble),
                                        ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🎈',
              title: strings.wonBubbles,
              stars: _stars,
              primaryLabel: strings.playAgainBubbles,
              onPrimary: _reset,
              secondaryLabel: strings.home,
              onSecondary: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}

class _BubbleData {
  _BubbleData({
    required this.emoji,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.phase,
  });

  String emoji;
  double x;
  double y;
  double vx;
  double vy;
  double phase;
  int popTick = 0;
  bool popping = false;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.bubble, required this.onTap});

  final _BubbleData bubble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = _BubblePopScreenState._bubbleSize;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xF2FFFFFF), Color(0x59FFFFFF)],
          ),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: Text(bubble.emoji, style: const TextStyle(fontSize: 40)),
        ),
      ),
    );
  }
}

class _PopSparkle extends StatelessWidget {
  const _PopSparkle({required this.bubble, required this.onFinished});

  final _BubbleData bubble;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final size = _BubblePopScreenState._bubbleSize;
    return TweenAnimationBuilder<double>(
      key: ValueKey('${bubble.popTick}_${bubble.emoji}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      onEnd: onFinished,
      builder: (context, value, _) {
        // Fade and rise rather than grow. Scaling this ✨ ran a transform
        // over text on every frame of every pop, which is the fastest way in
        // this app to exhaust the glyph raster cache and stop emoji painting.
        return Opacity(
          opacity: 1 - value,
          child: Transform.translate(
            offset: Offset(0, -value * size * 0.35),
            child: SizedBox(
              width: size,
              height: size,
              child: const Center(
                child: Text('✨', style: TextStyle(fontSize: 56)),
              ),
            ),
          ),
        );
      },
    );
  }
}
