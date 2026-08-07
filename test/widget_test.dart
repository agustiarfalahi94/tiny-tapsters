import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddlers_journey/main.dart';
import 'package:toddlers_journey/screens/animal_food_screen.dart';
import 'package:toddlers_journey/screens/bubble_pop_screen.dart';
import 'package:toddlers_journey/screens/find_it_screen.dart';
import 'package:toddlers_journey/screens/jigsaw_game_screen.dart';
import 'package:toddlers_journey/screens/memory_game_screen.dart';

void main() {
  testWidgets('home screen shows all five games', (tester) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    final scrollable = find.byType(Scrollable).first;
    for (final title in [
      'Jigsaw Puzzle',
      'Animal Food',
      'Memory Match',
      'Bubble Pop',
      'Find It!',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        100,
        scrollable: scrollable,
      );
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('all game screens build without errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: JigsawGameScreen(rows: 2, cols: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      const MaterialApp(home: AnimalFoodGameScreen(pairs: 3)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const MaterialApp(home: FindItScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    // Bubble Pop runs an endless animation; pump frames instead of settling.
    await tester.pumpWidget(const MaterialApp(home: BubblePopScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(
      const MaterialApp(home: MemoryGameScreen(pairs: 2, columns: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('wrong tap in Find It! fades back to white', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FindItScreen()));

    // The target is the big emoji in the prompt (fontSize 44).
    final target = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.style?.fontSize == 44)
        .data!;
    // Pick a grid card that is not the target.
    final cardEmojis = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .toList();
    final wrong = cardEmojis.firstWhere((e) => e != target);

    await tester.tap(find.text(wrong));
    await tester.pump(); // start the shake
    await tester.pump(const Duration(milliseconds: 500)); // let it finish

    final cardBox =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(wrong),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(cardBox.color, Colors.white);
  });
}
