import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toddlers_journey/main.dart';
import 'package:toddlers_journey/screens/animal_food_screen.dart';
import 'package:toddlers_journey/screens/bubble_pop_screen.dart';
import 'package:toddlers_journey/screens/companion_screen.dart';
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

  testWidgets('home title stays centered after returning from a game', (
    tester,
  ) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    final title = find.text("Our Toddlers' Journey");

    expect(
      tester.getCenter(title).dx,
      closeTo(400, 5),
    ); // 800x600 test viewport

    // Find It! → Easy → back → back.
    await tester.scrollUntilVisible(
      find.text('Find It!'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible only guarantees partial visibility — scroll a bit
    // more so the card is fully on screen before tapping it.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find It!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🏠')); // back from the game
    await tester.pumpAndSettle();
    await tester.tap(find.text('🏠')); // back from the level picker
    await tester.pumpAndSettle();

    expect(tester.getCenter(title).dx, closeTo(400, 5));
  });

  testWidgets('jigsaw pieces are exactly slot-sized (picture fills board)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JigsawGameScreen(rows: 2, cols: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Slots are the only CustomPaints with a painter in this screen.
    final slots = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter != null)
        .toList();
    expect(slots.length, 4);
    // Pieces are GestureDetectors with GlobalKeys (the InkWell buttons also
    // build keyless GestureDetectors internally, so filter those out).
    final pieces = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.key is GlobalKey,
    );
    expect(pieces, findsNWidgets(4));

    final slotSize = tester.getSize(find.byWidget(slots.first));
    final pieceSize = tester.getSize(pieces.first);
    expect(pieceSize.width, closeTo(slotSize.width, 0.5));
    expect(pieceSize.height, closeTo(slotSize.height, 0.5));
  });

  testWidgets('jigsaw uses no text scaling and square tiles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: JigsawGameScreen(rows: 2, cols: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Scaling text (FittedBox / non-identity Transform) makes the renderer
    // re-rasterize emoji glyphs every animation frame — lag, and eventually
    // every icon in the app stops painting. Guard against both.
    expect(find.byType(FittedBox), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Transform &&
            (w.transform.getMaxScaleOnAxis() - 1).abs() > 0.01,
      ),
      findsNothing,
    );

    // Tiles are perfectly square boxes.
    final slots = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter != null);
    for (final slot in slots) {
      final size = tester.getSize(find.byWidget(slot));
      expect(size.width, closeTo(size.height, 0.5));
    }
  });

  testWidgets('jigsaw piece snaps when dragged onto its own slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JigsawGameScreen(rows: 2, cols: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final pieceFinder = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.key is GlobalKey,
    );
    final slots = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter != null)
        .toList();
    expect(pieceFinder, findsNWidgets(4));

    // The piece at drawer position 0 belongs to exactly one of the four
    // slots — drag it onto each slot until it snaps (a wrong slot rejects
    // it instantly, its own slot accepts it).
    for (final slot in slots) {
      if (pieceFinder.evaluate().length < 4) break; // snapped already
      final pieceCenter = tester.getCenter(pieceFinder.first);
      final slotCenter = tester.getCenter(find.byWidget(slot));
      final gesture = await tester.startGesture(pieceCenter);
      await gesture.moveTo(slotCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(
      pieceFinder,
      findsNWidgets(3),
      reason: 'one piece should have snapped into its own slot',
    );
  });

  testWidgets('companion shows graceful message without an API key', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CompanionScreen()));
    await tester.pump();

    expect(find.text('Pollie'), findsOneWidget);
    expect(find.text('sleeping… 😴'), findsOneWidget);
    expect(find.text('🎤'), findsOneWidget); // voice button present
    // No GEMINI_API_KEY in the test environment → friendly fallback text.
    expect(find.textContaining('magic key'), findsOneWidget);

    // Tapping a chip without a key must not crash; it shows the same hint.
    await tester.tap(find.textContaining('Tell me a story'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('magic key'), findsWidgets);
  });

  testWidgets('home screen has the Pollie button', (tester) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    expect(find.byTooltip('Talk to Pollie'), findsOneWidget);
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
