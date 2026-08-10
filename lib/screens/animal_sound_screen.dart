import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/animal_sounds.dart';
import '../services/music_service.dart';
import '../services/sound_effects.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/game_timer.dart';
import '../widgets/round_button.dart';

/// Which Animal?: a big speaker button plays a call, and the child taps the
/// animal that made it. 2 choices on Easy, 3 on Medium, 5 on Big.
///
/// The sound replays as many times as the child wants. Re-listening is the
/// skill this game is for, not a way around it.
class AnimalSoundScreen extends StatefulWidget {
  const AnimalSoundScreen({
    super.key,
    required this.choices,
    required this.level,
    this.random,
  });

  /// Cards on screen each round (2 = easy, 3 = medium, 5 = big).
  final int choices;

  /// Sets the clock: 30s / 1m / 2m for the whole game.
  final GameLevel level;

  /// Injectable RNG for tests; production uses a fresh [math.Random].
  final math.Random? random;

  @override
  State<AnimalSoundScreen> createState() => _AnimalSoundScreenState();
}

class _AnimalSoundScreenState extends State<AnimalSoundScreen>
    with WidgetsBindingObserver, TimedGame {
  late final math.Random _rng = widget.random ?? math.Random();

  /// Easy drops to 3 rounds, for the same reason the other games do: five
  /// rounds inside a 30-second clock is six seconds a question.
  int get _roundsToWin => widget.level == GameLevel.easy ? 3 : 5;

  late String _target;
  late List<String> _cards;
  late final List<GlobalKey<_AnimalCardState>> _cardKeys;

  int _found = 0;
  int _wrong = 0;
  int? _happyIndex;

  /// Animals already asked for this game. A five-round game that asks for the
  /// monkey twice wastes a round and reads as a bug, which is what it was.
  final _asked = <String>{};
  bool _won = false;
  bool _busy = false;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    _cardKeys = List.generate(widget.choices, (_) => GlobalKey());
    // Turned down, not off: a child has to make out a cow over the music, but
    // a game that falls silent reads as broken.
    MusicService.instance.setAttenuation(0.35);
    _newRound(play: false);
  }

  @override
  void dispose() {
    MusicService.instance.setAttenuation(1);
    super.dispose();
  }

  void _newRound({bool play = true}) {
    final all = kAnimalSounds.keys.toList();
    // Fall back to "anything but the last one" if a game ever asks for more
    // rounds than there are animals; today it cannot, but a shrunken
    // catalogue should degrade rather than throw.
    var unasked = all.where((e) => !_asked.contains(e)).toList();
    if (unasked.isEmpty) {
      unasked = all.where((e) => e != _target).toList();
    }
    final target = (unasked..shuffle(_rng)).first;
    _asked.add(target);
    // Distractors come from every *other* animal, so no board shows one twice.
    final pool = all.where((e) => e != target).toList()..shuffle(_rng);
    setState(() {
      _target = target;
      _cards = [...pool.take(widget.choices - 1), target]..shuffle(_rng);
      _happyIndex = null;
      _busy = false;
    });
    if (play) _play();
  }

  void _play() {
    if (_won || outOfTime) return;
    // The clock starts when the child first asks to hear something, not when
    // the screen opens.
    startClock();
    SoundEffects.instance.animal(kAnimalSounds[_target]!);
  }

  void _reset() {
    resetClock();
    _asked.clear();
    setState(() {
      _found = 0;
      _wrong = 0;
      _won = false;
    });
    _newRound(play: false);
  }

  void _onTap(int index) {
    if (_won || _busy || outOfTime) return;
    startClock();
    if (_cards[index] == _target) {
      _busy = true;
      setState(() {
        _found++;
        _happyIndex = index;
      });
      HapticFeedback.mediumImpact();
      SoundEffects.instance.pop();
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted || outOfTime || _won) return;
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

  /// 3 stars for a clean game, 2 for a couple of misses, 1 otherwise —
  /// the same scale as Find It!.
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
                      Row(
                        children: [
                          for (var i = 0; i < _roundsToWin; i++)
                            Container(
                              key: ValueKey('sound-dot-$i'),
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
                const SizedBox(height: 8),
                // The speaker: the whole game in one button. Deliberately huge
                // and unlabelled, and it replays as often as the child likes.
                Semantics(
                  button: true,
                  label: 'Play the animal sound',
                  child: GestureDetector(
                    key: const ValueKey('play-sound'),
                    onTap: _play,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🔊', style: TextStyle(fontSize: 64)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Who made that sound?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: _cards.length <= 2 ? 2 : 3,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                    children: [
                      for (var i = 0; i < _cards.length; i++)
                        _AnimalCard(
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
              emoji: '🔊',
              title: 'Great listening!',
              stars: _stars,
              primaryLabel: 'Play again 🔁',
              onPrimary: _reset,
              secondaryLabel: 'Home 🏠',
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

class _AnimalCard extends StatefulWidget {
  const _AnimalCard({
    super.key,
    required this.emoji,
    required this.happy,
    required this.onTap,
  });

  final String emoji;
  final bool happy;
  final VoidCallback onTap;

  @override
  State<_AnimalCard> createState() => _AnimalCardState();
}

class _AnimalCardState extends State<_AnimalCard>
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
          // Decaying wiggle; the red tint rises then falls so the card is
          // white again when it settles. Same treatment as Find It!.
          final angle = math.sin(v * math.pi * 6) * 0.12 * (1 - v);
          final redTint = v < 0.5 ? v * 2 : (1 - v) * 2;
          return Transform.rotate(
            angle: angle,
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.white,
                  const Color(0xFFFF8A80),
                  redTint * 0.8,
                ),
                borderRadius: BorderRadius.circular(20),
                border: widget.happy
                    ? Border.all(color: const Color(0xFF66BB6A), width: 3)
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
                child: Text(widget.emoji, style: const TextStyle(fontSize: 52)),
              ),
            ),
          );
        },
      ),
    );
  }
}
