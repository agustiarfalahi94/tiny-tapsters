import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pollie 🦜, alive: a slow bob with a little tilt at the top of each rise.
///
/// **Translate and rotate only — never scale.** Scaling text re-rasterises the
/// emoji glyph on every animation frame, which lags and, on this project's
/// test device, eventually stops *every* emoji in the app from painting. The
/// jigsaw has a test guarding the same rule; this is the same trap.
class PollieBird extends StatefulWidget {
  const PollieBird({
    super.key,
    this.emoji = '🦜',
    this.fontSize = 32,
    this.bob = 4,
    this.lean = 0,
    this.active = true,
    this.period = const Duration(milliseconds: 2400),
  });

  /// Which face to animate. The home screen shows the parrot; the companion
  /// screen shows Pollie's current mood.
  final String emoji;

  final double fontSize;

  /// False holds the face still — a sleeping Pollie should not be bobbing,
  /// and a stopped controller is one fewer thing repainting.
  final bool active;

  /// How far it rises and falls, in logical pixels.
  final double bob;

  /// A constant tilt on top of the bob, in radians. Used to make Pollie lean
  /// toward the child while she is listening.
  final double lean;

  final Duration period;

  @override
  State<PollieBird> createState() => _PollieBirdState();
}

class _PollieBirdState extends State<PollieBird>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(PollieBird old) {
    super.didUpdateWidget(old);
    if (widget.period != old.period) _controller.duration = widget.period;
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, -math.sin(phase) * widget.bob),
          // A quarter-turn out of phase with the rise, so the tilt peaks on
          // the way up rather than at the top — which reads as a wingbeat
          // instead of a wobble.
          child: Transform.rotate(
            angle: widget.lean + math.cos(phase) * 0.06,
            child: child,
          ),
        );
      },
      // Built once and reused every frame: the glyph is never re-laid-out.
      child: Text(widget.emoji, style: TextStyle(fontSize: widget.fontSize)),
    );
  }
}

/// "Tap to talk!" — the nudge that tells a grown-up the bird is a button.
///
/// Fades in a few seconds after the home screen settles rather than
/// immediately, so it reads as Pollie noticing you rather than as a label.
class TapToTalkBubble extends StatefulWidget {
  const TapToTalkBubble({
    super.key,
    this.delay = const Duration(seconds: 3),
    this.onTap,
  });

  final Duration delay;
  final VoidCallback? onTap;

  @override
  State<TapToTalkBubble> createState() => _TapToTalkBubbleState();
}

class _TapToTalkBubbleState extends State<TapToTalkBubble> {
  bool _shown = false;
  Timer? _reveal;

  @override
  void initState() {
    super.initState();
    // A real Timer rather than Future.delayed, so leaving the home screen
    // cancels it instead of leaving it to fire into a disposed widget.
    _reveal = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _reveal?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      child: IgnorePointer(
        ignoring: !_shown,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Text(
              'Tap to talk! 💬',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
