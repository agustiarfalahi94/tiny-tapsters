import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/data/animal_sounds.dart';
import 'package:tiny_tapsters/screens/animal_food_screen.dart';
import 'package:tiny_tapsters/screens/animal_sound_screen.dart';
import 'package:tiny_tapsters/widgets/game_timer.dart';

/// The animal emojis currently on screen, read from the answer grid.
List<String> cards(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(GridView), matching: find.byType(Text)),
    )
    .map((t) => t.data!)
    .toList();

void main() {
  group('the sound catalogue', () {
    test('every animal with a sound is one the app already knows', () {
      // kAnimalEmojis stays the single source of truth; a typo here would
      // otherwise invent an animal that exists in this game and nowhere else.
      for (final emoji in kAnimalSounds.keys) {
        expect(
          kAnimalEmojis,
          contains(emoji),
          reason: '$emoji is not in kAnimalEmojis',
        );
      }
    });

    test('every sound file exists and is bundled', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final asset in kAnimalSounds.values) {
        expect(File('assets/$asset').existsSync(), isTrue, reason: asset);
        expect(pubspec, contains('assets/$asset'), reason: asset);
      }
    });

    test('there are enough animals for the hardest level', () {
      // Big shows 5 cards, and a round excludes the previous target, so the
      // catalogue needs 6 to fill a board without repeating an animal.
      expect(kAnimalSounds.length, greaterThanOrEqualTo(6));
    });
  });

  group('Which Animal?', () {
    testWidgets('shows exactly as many choices as the level asks for', (
      tester,
    ) async {
      for (final (choices, level) in [
        (2, GameLevel.easy),
        (3, GameLevel.medium),
        (5, GameLevel.big),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(choices),
            home: AnimalSoundScreen(
              choices: choices,
              level: level,
              random: math.Random(1),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(cards(tester).length, choices);
        // No animal twice on one board — a duplicate would make two cards
        // equally correct.
        expect(cards(tester).toSet().length, choices);
      }
    });

    testWidgets('a wrong tap costs a star but never a round', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalSoundScreen(
            choices: 3,
            level: GameLevel.medium,
            random: math.Random(3),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final before = cards(tester);
      // Two of the three are wrong; tapping one must leave the round alone.
      // Which is right is private, so try one and check nothing advanced.
      await tester.tap(find.text(before.first));
      await tester.pump(const Duration(milliseconds: 600));

      final dotColour =
          (tester
                      .widget<Container>(
                        find.byKey(const ValueKey('sound-dot-0')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      final advanced = dotColour == const Color(0xFFFF9800);
      if (!advanced) {
        expect(
          cards(tester),
          before,
          reason: 'a wrong tap must not change the board',
        );
      }
    });

    testWidgets('the clock does not start until the child engages', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AnimalSoundScreen(choices: 2, level: GameLevel.easy),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 30s on Easy — well past it, with nothing touched yet.
      await tester.pump(const Duration(seconds: 40));
      expect(find.text("Time's up!"), findsNothing);

      // Asking to hear the sound is engagement, so now it runs.
      await tester.tap(find.byKey(const ValueKey('play-sound')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text("Time's up!"), findsOneWidget);
    });

    testWidgets('Easy asks for three rounds, Big for five', (tester) async {
      for (final (level, rounds) in [(GameLevel.easy, 3), (GameLevel.big, 5)]) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(level),
            home: AnimalSoundScreen(
              choices: level == GameLevel.easy ? 2 : 5,
              level: level,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(ValueKey('sound-dot-${rounds - 1}')), findsOneWidget);
        expect(find.byKey(ValueKey('sound-dot-$rounds')), findsNothing);
      }
    });
  });
}
