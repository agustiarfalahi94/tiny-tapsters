import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/screens/count_game_screen.dart';
import 'package:tiny_tapsters/screens/find_it_screen.dart';
import 'package:tiny_tapsters/widgets/celebration_overlay.dart';
import 'package:tiny_tapsters/widgets/game_over_overlay.dart';
import 'package:tiny_tapsters/widgets/game_timer.dart';

void main() {
  test('each level allows the time it promises', () {
    expect(GameLevel.easy.duration, const Duration(seconds: 30));
    expect(GameLevel.medium.duration, const Duration(minutes: 1));
    expect(GameLevel.big.duration, const Duration(minutes: 2));
  });

  // These tests stop their clock before returning: flutter_test asserts no
  // Timer is pending at the end of a test body, and that check runs before
  // tear-downs do.
  testWidgets('the clock does not run until the game says so', (tester) async {
    final clock = GameTimerController(total: const Duration(seconds: 30));
    addTearDown(clock.dispose);

    // A child looking at a fresh board is not losing time yet.
    await tester.pump(const Duration(seconds: 5));
    expect(clock.running, isFalse);
    expect(clock.remaining, const Duration(seconds: 30));

    clock.start();
    await tester.pump(const Duration(seconds: 5));
    expect(clock.remaining, lessThan(const Duration(seconds: 30)));
    clock.pause();
  });

  testWidgets('starting twice does not run two clocks', (tester) async {
    final clock = GameTimerController(total: const Duration(seconds: 30));
    addTearDown(clock.dispose);

    clock.start();
    await tester.pump(const Duration(seconds: 5));
    final afterFirst = clock.remaining;

    // Games call start() on every interaction rather than tracking whether
    // they already did, so a second call must change nothing.
    clock.start();
    await tester.pump(const Duration(seconds: 5));

    expect(afterFirst - clock.remaining, const Duration(seconds: 5));
    clock.pause();
  });

  testWidgets('pausing holds the remaining time and resuming continues it', (
    tester,
  ) async {
    final clock = GameTimerController(total: const Duration(seconds: 30));
    addTearDown(clock.dispose);

    clock.start();
    await tester.pump(const Duration(seconds: 5));
    clock.pause();
    final held = clock.remaining;

    await tester.pump(const Duration(seconds: 10));
    expect(clock.remaining, held, reason: 'a paused clock must not tick');

    clock.resume();
    await tester.pump(const Duration(seconds: 3));
    expect(clock.remaining, lessThan(held));
    clock.pause();
  });

  testWidgets('the clock expires exactly once and stops', (tester) async {
    final clock = GameTimerController(total: const Duration(seconds: 2));
    addTearDown(clock.dispose);

    var expiredNotifications = 0;
    clock.addListener(() {
      if (clock.expired) expiredNotifications++;
    });

    clock.start();
    await tester.pump(const Duration(seconds: 5));

    expect(clock.expired, isTrue);
    expect(clock.remaining, Duration.zero);
    expect(clock.fraction, 0);
    expect(clock.running, isFalse);
    expect(
      expiredNotifications,
      1,
      reason: 'ticking past zero must not keep firing the loss',
    );
  });

  testWidgets('reset gives the whole clock back and stops it', (tester) async {
    final clock = GameTimerController(total: const Duration(seconds: 2));
    addTearDown(clock.dispose);

    clock.start();
    await tester.pump(const Duration(seconds: 5));
    expect(clock.expired, isTrue);

    clock.reset();
    expect(clock.expired, isFalse);
    expect(clock.running, isFalse);
    expect(clock.remaining, const Duration(seconds: 2));
  });

  testWidgets('running out of time ends the game with a loss, not a win', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: FindItScreen(level: GameLevel.easy)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Tap something to start the clock, then let it run out.
    await tester.tap(find.byType(GridView));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 31));

    expect(find.byType(GameOverOverlay), findsOneWidget);
    expect(find.byType(CelebrationOverlay), findsNothing);
    expect(find.text("Time's up!"), findsOneWidget);
  });

  testWidgets('the loss overlay retries into a fresh clock', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FindItScreen(level: GameLevel.easy)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(GridView));
    await tester.pump(const Duration(seconds: 31));
    expect(find.byType(GameOverOverlay), findsOneWidget);

    await tester.tap(find.text('Try again 🔁'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameOverOverlay), findsNothing);
    // And the fresh clock is not running yet, so the child gets a full look
    // at the new board before it starts.
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(GameOverOverlay), findsNothing);
  });

  testWidgets('Easy asks for fewer rounds so the 30s clock is winnable', (
    tester,
  ) async {
    // Five rounds inside 30 seconds is six seconds a question. Easy is three.
    for (final (level, dots) in [
      (GameLevel.easy, 3),
      (GameLevel.medium, 5),
      (GameLevel.big, 5),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(level),
          home: CountGameScreen(maxCount: 3, level: level),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(ValueKey('round-dot-${dots - 1}')),
        findsOneWidget,
        reason: '$level should show $dots rounds',
      );
      expect(find.byKey(ValueKey('round-dot-$dots')), findsNothing);
    }
  });
}
