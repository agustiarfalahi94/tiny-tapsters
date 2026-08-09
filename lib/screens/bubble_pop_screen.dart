import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sound_effects.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/round_button.dart';

/// Bubble Pop: friendly bubbles drift around the screen; tap one to pop it
/// into a sparkle. Pop 8 bubbles per round; each round the bubbles float a
/// little faster.
class BubblePopScreen extends StatefulWidget {
  const BubblePopScreen({super.key});

  @override
  State<BubblePopScreen> createState() => _BubblePopScreenState();
}

class _BubblePopScreenState extends State<BubblePopScreen>
    with SingleTickerProviderStateMixin {
  static const _bubbleEmojis = [
    '🐶',
    '🐱',
    '🐸',
    '🐢',
    '🦋',
    '⭐',
    '🌸',
    '🌈',
    '🍓',
    '🐙',
  ];
  static const _bubbleCount = 4;
  static const _popsPerRound = 8;
  static const _bubbleSize = 90.0;

  late final AnimationController _float;
  late final List<_BubbleData> _bubbles;
  final math.Random _rnd = math.Random();

  int _round = 1;
  int _popped = 0;
  bool _won = false;

  /// True once the round's pop target is reached. Guards input during the
  /// 600ms beat before `_won` flips and the celebration overlay appears —
  /// without it, bubbles tapped in that window kept incrementing `_popped`
  /// past `_popsPerRound`, showing a negative "more!" count.
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
    _float =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..addStatusListener(_onFloatStatus)
          ..forward();
    _bubbles = [for (var i = 0; i < _bubbleCount; i++) _spawn()];
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

  _BubbleData _spawn() {
    return _BubbleData(
      emoji: _bubbleEmojis[_rnd.nextInt(_bubbleEmojis.length)],
      x: _rnd.nextDouble(),
      y: _rnd.nextDouble(),
      vx: (0.10 + _rnd.nextDouble() * 0.12) * (_rnd.nextBool() ? 1 : -1),
      vy: (0.10 + _rnd.nextDouble() * 0.12) * (_rnd.nextBool() ? 1 : -1),
      phase: _rnd.nextDouble(),
    );
  }

  void _pop(_BubbleData bubble) {
    if (bubble.popping || _won || _roundComplete) return;
    setState(() {
      bubble.popTick++;
      bubble.popping = true;
      _popped++;
      // Set synchronously, not in the delayed callback below — otherwise
      // bubbles tapped during the 600ms win beat still count, pushing
      // _popped past _popsPerRound.
      if (_popped >= _popsPerRound) _roundComplete = true;
    });
    HapticFeedback.lightImpact();
    SoundEffects.instance.pop();
    if (_popped >= _popsPerRound) {
      _winTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _won = true);
      });
    }
  }

  void _nextRound() {
    _winTimer?.cancel();
    setState(() {
      _round++;
      _popped = 0;
      _won = false;
      _roundComplete = false;
      for (var i = 0; i < _bubbles.length; i++) {
        _bubbles[i] = _spawn();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final speedFactor = 1 + 0.3 * (_round - 1);
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
                      Text(
                        // Clamped defensively: _roundComplete already stops
                        // _popped from overshooting, but this keeps the
                        // label honest even if that guard ever regresses.
                        'Pop ${math.max(0, _popsPerRound - _popped)} more!',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                      ),
                      const Spacer(),
                      RoundButton(
                        emoji: '🔁',
                        onTap: () {
                          _winTimer?.cancel();
                          setState(() {
                            _popped = 0;
                            _roundComplete = false;
                            for (var i = 0; i < _bubbles.length; i++) {
                              _bubbles[i] = _spawn();
                            }
                          });
                        },
                      ),
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
                                            final fresh = _spawn();
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
              title: 'Pop-tastic!',
              primaryLabel: 'Next round 🎈',
              onPrimary: _nextRound,
              secondaryLabel: 'Home 🏠',
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
        return Opacity(
          opacity: 1 - value,
          child: Transform.scale(
            scale: 1 + value * 0.9,
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
