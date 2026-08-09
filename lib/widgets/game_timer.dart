import 'dart:async';

import 'package:flutter/material.dart';

/// The three difficulties every game offers, and how long each one allows.
enum GameLevel {
  easy(Duration(seconds: 30)),
  medium(Duration(minutes: 1)),
  big(Duration(minutes: 2));

  const GameLevel(this.duration);

  /// The whole game's clock — not per round.
  final Duration duration;
}

/// The countdown behind a game's timer bar.
///
/// Deliberately not started by the screen appearing: a child looking at a
/// fresh board should not be losing time before touching anything. Every game
/// calls [start] from its first interaction, and [start] is idempotent so it
/// can be called on every interaction without thinking about it.
class GameTimerController extends ChangeNotifier {
  GameTimerController({required this.total});

  /// How long the whole game gets.
  final Duration total;

  static const _tick = Duration(milliseconds: 100);

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _started = false;
  bool _expired = false;

  bool get started => _started;
  bool get expired => _expired;
  bool get running => _timer != null;

  Duration get remaining {
    final left = total - _elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// 1.0 when full, 0.0 when out of time. What the bar draws.
  double get fraction => total.inMilliseconds == 0
      ? 0
      : remaining.inMilliseconds / total.inMilliseconds;

  /// Starts the clock on the first call and ignores every later one.
  void start() {
    if (_started || _expired) return;
    _started = true;
    _resume();
    notifyListeners();
  }

  /// Stops the clock without losing the time already spent. Used when the app
  /// goes to the background and when the game ends.
  void pause() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    notifyListeners();
  }

  void resume() {
    if (_expired || !_started || _timer != null) return;
    _resume();
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _elapsed = Duration.zero;
    _started = false;
    _expired = false;
    notifyListeners();
  }

  void _resume() {
    _timer = Timer.periodic(_tick, (_) {
      _elapsed += _tick;
      if (_elapsed >= total) {
        _elapsed = total;
        _expired = true;
        _timer?.cancel();
        _timer = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Wires a [GameTimerController] into a game screen: the clock itself,
/// pausing while the app is in the background, and the out-of-time flag.
///
/// Screens supply [gameLevel] and [hasWon], call [startClock] from their first
/// interaction, [winClock] the moment they are won, and [resetClock] from the
/// reset button. Everything else is handled here, so seven screens do not each
/// grow their own copy of it.
mixin TimedGame<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  /// Which difficulty this screen was opened at.
  GameLevel get gameLevel;

  /// True once the game has been won. A win outranks a timeout: whichever
  /// lands first wins, and the clock is paused the moment either does.
  bool get hasWon;

  late final GameTimerController clock = GameTimerController(
    total: gameLevel.duration,
  )..addListener(_onTick);

  bool _outOfTime = false;
  bool get outOfTime => _outOfTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // No clock running while the child is not looking at the game.
    if (state == AppLifecycleState.resumed) {
      if (!_outOfTime && !hasWon) clock.resume();
    } else {
      clock.pause();
    }
  }

  /// Starts the clock. Idempotent, so every interaction can call it.
  void startClock() => clock.start();

  /// Stops the clock on a win, so a timeout cannot land on top of the
  /// celebration.
  void winClock() => clock.pause();

  void resetClock() {
    _outOfTime = false;
    clock.reset();
  }

  void _onTick() {
    if (!clock.expired || _outOfTime || hasWon) return;
    _outOfTime = true;
    clock.pause();
    if (mounted) setState(() {});
  }
}

/// The countdown a toddler can actually read: a bar that shrinks and changes
/// colour. No digits — the target player cannot read a clock, and the colour
/// is the signal. It pulses in the last stretch.
class GameTimerBar extends StatelessWidget {
  const GameTimerBar({super.key, required this.controller});

  final GameTimerController controller;

  /// Below this much time left, the bar starts pulsing and the clock appears.
  static const _hurry = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final fraction = controller.fraction;
        final hurrying = controller.remaining <= _hurry && !controller.expired;
        return Row(
          children: [
            if (hurrying)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('⏰', style: TextStyle(fontSize: 20)),
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 14,
                  color: Colors.white.withValues(alpha: 0.35),
                  // The fill pulses in place rather than the bar scaling: a
                  // bar that grew would read as more time, not less.
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: _PulsingFill(
                      color: _color(fraction),
                      pulsing: hurrying,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Color _color(double fraction) {
    if (fraction > 0.5) return const Color(0xFF4CAF50);
    if (fraction > 0.2) return const Color(0xFFFF9800);
    return const Color(0xFFE53935);
  }
}

class _PulsingFill extends StatefulWidget {
  const _PulsingFill({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_PulsingFill> createState() => _PulsingFillState();
}

class _PulsingFillState extends State<_PulsingFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void didUpdateWidget(_PulsingFill old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.pulsing && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final alpha = widget.pulsing ? 1 - 0.35 * _pulse.value : 1.0;
        return Container(color: widget.color.withValues(alpha: alpha));
      },
    );
  }
}
