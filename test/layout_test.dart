import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/screens/animal_food_screen.dart';
import 'package:tiny_tapsters/screens/animal_sound_screen.dart';
import 'package:tiny_tapsters/screens/bubble_pop_screen.dart';
import 'package:tiny_tapsters/screens/count_game_screen.dart';
import 'package:tiny_tapsters/screens/find_it_screen.dart';
import 'package:tiny_tapsters/screens/home_screen.dart';
import 'package:tiny_tapsters/screens/jigsaw_game_screen.dart';
import 'package:tiny_tapsters/screens/memory_game_screen.dart';
import 'package:tiny_tapsters/widgets/game_timer.dart';
import 'package:tiny_tapsters/widgets/pair_drag_game.dart';

/// The bordered boxes the food sits in.
List<Rect> slotRects(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(PairDragGame),
        matching: find.byType(Container),
      ),
    )
    .where((c) => (c.decoration as BoxDecoration?)?.border != null)
    .map((c) => tester.getRect(find.byWidget(c)))
    .toList();

/// The rounded panel the animals wait in at the bottom.
Rect drawerRect(WidgetTester tester) {
  final panels = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(PairDragGame),
          matching: find.byType(Container),
        ),
      )
      .where((c) {
        final d = c.decoration as BoxDecoration?;
        return d != null && d.border == null && d.borderRadius != null;
      })
      .toList();
  return tester.getRect(find.byWidget(panels.last));
}

/// A real phone, not flutter_test's 800x600 desktop-ish default.
///
/// This matters: the out-of-bounds bug only appears once the width is tight
/// enough for the board to hit its width limit, which never happens at 800.
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Find It! shows its target in the prompt at fontSize 44, so a test can read
/// it directly instead of guessing which card is right.
String findItTarget(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .firstWhere((t) => t.style?.fontSize == 44)
    .data!;

void main() {
  testWidgets('Find It! never asks for the same animal twice in a game', (
    tester,
  ) async {
    usePhoneViewport(tester);
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(attempt),
          home: const FindItScreen(cardsPerRound: 6, level: GameLevel.big),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final asked = <String>[];
      for (var round = 0; round < 5; round++) {
        final target = findItTarget(tester);
        asked.add(target);
        // The grid holds one of each animal, so the prompt names exactly the
        // card to tap.
        await tester.tap(
          find
              .descendant(
                of: find.byType(GridView),
                matching: find.text(target),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(
        asked.toSet().length,
        asked.length,
        reason: 'attempt $attempt asked for one of $asked twice',
      );
    }
  });

  for (final (label, pairs, level) in [
    ('Easy', 3, GameLevel.easy),
    ('Medium', 6, GameLevel.medium),
    ('Big', 9, GameLevel.big),
  ]) {
    testWidgets('animal food $label keeps every slot on screen', (
      tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalFoodGameScreen(pairs: pairs, level: level),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final board = tester.getRect(find.byType(PairDragGame));
      final slots = slotRects(tester);
      expect(slots.length, pairs);

      for (final slot in slots) {
        // The slot size used to ignore the gaps between columns, so the board
        // came out (maxCols - 1) x gap too wide and the outer food boxes hung
        // off both edges.
        expect(
          slot.left,
          greaterThanOrEqualTo(board.left - 0.5),
          reason: '$label: a slot starts left of the board',
        );
        expect(
          slot.right,
          lessThanOrEqualTo(board.right + 0.5),
          reason: '$label: a slot ends right of the board',
        );
        expect(slot.top, greaterThanOrEqualTo(board.top - 0.5));
      }
    });

    testWidgets('animal food $label leaves room for the food names', (
      tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalFoodGameScreen(pairs: pairs, level: level),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final slots = slotRects(tester);
      final lowest = slots.map((s) => s.bottom).reduce((a, b) => a > b ? a : b);
      final drawer = drawerRect(tester);

      // A caption hangs in the gap beneath its slot. The bottom row needs that
      // gap to exist below it, or the words land on top of the animals.
      const captionGap = 24.0;
      expect(
        lowest + captionGap,
        lessThanOrEqualTo(drawer.top + 0.5),
        reason: '$label: the bottom row of food names would overlap the drawer',
      );
    });
  }

  // flutter_test turns a RenderFlex overflow into a test failure, so simply
  // building every screen at phone size is the guard. This is how the Animal
  // Food header was found overflowing by 93px at 360dp — at the default
  // 800x600 test viewport it fits, and nothing ever complained.
  testWidgets('every screen builds on a phone without overflowing', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final screens = <String, Widget>{
      'jigsaw': const JigsawGameScreen(rows: 3, cols: 3, level: GameLevel.big),
      'animal food': const AnimalFoodGameScreen(pairs: 9, level: GameLevel.big),
      'memory': const MemoryGameScreen(
        pairs: 6,
        columns: 4,
        level: GameLevel.big,
      ),
      'find it': const FindItScreen(cardsPerRound: 12, level: GameLevel.big),
      'count': const CountGameScreen(maxCount: 10, level: GameLevel.big),
      'bubble pop': const BubblePopScreen(popsToWin: 12, level: GameLevel.big),
      'which animal': const AnimalSoundScreen(choices: 5, level: GameLevel.big),
      'home': const HomeScreen(),
    };
    for (final entry in screens.entries) {
      await tester.pumpWidget(
        MaterialApp(key: ValueKey(entry.key), home: entry.value),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key} overflowed at 360dp',
      );
    }
  });

  testWidgets('the jigsaw board still fits its own width', (tester) async {
    // The jigsaw shares this engine with no gaps and no captions, so the fix
    // must not have moved it.
    usePhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: JigsawGameScreen(rows: 3, cols: 3, level: GameLevel.big),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byType(PairDragGame));
    final tiles = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter != null)
        .map((c) => tester.getRect(find.byWidget(c)));

    for (final tile in tiles) {
      expect(tile.left, greaterThanOrEqualTo(board.left - 0.5));
      expect(tile.right, lessThanOrEqualTo(board.right + 0.5));
    }
  });
}
