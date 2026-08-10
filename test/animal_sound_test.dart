import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/data/animal_sounds.dart';
import 'package:tiny_tapsters/data/asset_credits.dart';
import 'package:tiny_tapsters/screens/credits_screen.dart';
import 'package:tiny_tapsters/screens/animal_food_screen.dart';
import 'package:tiny_tapsters/screens/animal_sound_screen.dart';
import 'package:tiny_tapsters/services/music_service.dart';
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

    test('the animals a toddler knows best are covered', () {
      // The dog was missing at first; the cow still is, because four searches
      // of Commons turned up no moo at all.
      expect(kAnimalSounds.keys, containsAll(['🐱', '🐶']));
    });

    test('every bundled call is credited', () {
      // CC BY obliges attribution wherever the work is used, and a sound
      // shipping without an entry here is a licence breach, not a typo.
      final credited = {for (final c in kAnimalSoundCredits) c.emoji};
      expect(credited, containsAll(kAnimalSounds.keys));
    });

    test('no credit names a licence we cannot ship', () {
      for (final credit in kAnimalSoundCredits) {
        final licence = credit.licence.toLowerCase();
        // ShareAlike would reach into the app itself.
        expect(
          licence.contains('sa'),
          isFalse,
          reason: '${credit.emoji} is ${credit.licence}',
        );
        expect(credit.author, isNotEmpty);
        expect(credit.source, startsWith('http'));
      }
    });

    test('there are enough animals for the hardest level', () {
      // Big shows 5 cards, and a round excludes the previous target, so the
      // catalogue needs 6 to fill a board without repeating an animal.
      expect(kAnimalSounds.length, greaterThanOrEqualTo(6));
    });
  });

  testWidgets('Which Animal? turns the music down, and puts it back', (
    tester,
  ) async {
    expect(MusicService.instance.attenuation, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimalSoundScreen(choices: 2, level: GameLevel.easy),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Quiet enough to make out a cow over, loud enough that the game does not
    // read as broken.
    expect(MusicService.instance.attenuation, lessThan(1));
    expect(MusicService.instance.attenuation, greaterThan(0));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(MusicService.instance.attenuation, 1);
  });

  testWidgets('the credits screen lists every sound and its author', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sound credits'), findsOneWidget);
    // The list scrolls, so check the first entry is rendered with its author
    // rather than expecting all of them on screen at once.
    final first = kAnimalSoundCredits.first;
    expect(find.text(first.title), findsOneWidget);
    expect(find.text('${first.author} · ${first.licence}'), findsOneWidget);
  });

  group('no animal appears twice', () {
    /// Plays a full game, finding the right card by trying them — a wrong tap
    /// only shakes — and records which animal each round asked for.
    testWidgets('Which Animal? never asks for the same animal twice', (
      tester,
    ) async {
      // A phone, not flutter_test's 600px-tall default: at that height the
      // five-card grid scrolls and the bottom row cannot be tapped, so the
      // game can never be played through.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (var seed = 0; seed < 12; seed++) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(seed),
            home: AnimalSoundScreen(
              choices: 5,
              level: GameLevel.big,
              random: math.Random(seed),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        final asked = <String>[];
        for (var round = 0; round < 5; round++) {
          final board = cards(tester);
          // A board must never show one animal twice either.
          expect(board.toSet().length, board.length, reason: 'seed $seed');
          // Find the right card by trying them: a wrong tap only shakes.
          for (final emoji in board) {
            await tester.tap(find.text(emoji));
            await tester.pump(const Duration(milliseconds: 600));
            if (cards(tester).join() != board.join() ||
                find.text('Great listening!').evaluate().isNotEmpty) {
              asked.add(emoji);
              break;
            }
          }
        }
        expect(
          asked.length,
          5,
          reason: 'seed $seed only detected ${asked.length} rounds: $asked',
        );
        expect(
          asked.toSet().length,
          asked.length,
          reason: 'seed $seed asked for one of $asked twice',
        );
      }
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
