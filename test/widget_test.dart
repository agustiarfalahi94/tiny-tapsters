import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/main.dart';
import 'package:tiny_tapsters/screens/animal_food_screen.dart';
import 'package:tiny_tapsters/screens/bubble_pop_screen.dart';
import 'package:tiny_tapsters/screens/companion_screen.dart';
import 'package:tiny_tapsters/screens/count_game_screen.dart';
import 'package:tiny_tapsters/screens/find_it_screen.dart';
import 'package:tiny_tapsters/screens/jigsaw_game_screen.dart';
import 'package:tiny_tapsters/screens/memory_game_screen.dart';
import 'package:tiny_tapsters/services/kid_safety.dart';
import 'package:tiny_tapsters/services/pollie_service.dart';

void main() {
  testWidgets('home screen shows all six games', (tester) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    final scrollable = find.byType(Scrollable).first;
    for (final title in [
      'Jigsaw Puzzle',
      'Animal Food',
      'Memory Match',
      'Bubble Pop',
      'Find It!',
      'Count the Animals!',
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

    await tester.pumpWidget(
      const MaterialApp(home: CountGameScreen(maxCount: 3)),
    );
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

  testWidgets('bubble pop header never shows a negative remaining count', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BubblePopScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await popBubblesUntilRoundComplete(tester);

    expect(find.text('Pop 0 more!'), findsOneWidget);
    // popBubblesUntilRoundComplete pumps 450ms after every tap — longer
    // than the 400ms pop-sparkle animation — so no sparkle should still be
    // mid-flight here. This is the baseline for the sparkle assertion
    // below: any '✨' found after the next tap can only be a *new* pop.
    expect(find.text('✨'), findsNothing);

    // Tap one more bubble before the 600ms win delay elapses. `_pop` guards
    // on `_roundComplete`, so this must be rejected outright.
    await tester.tap(bubbleTexts().first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('-'), findsNothing);
    expect(find.text('Pop 0 more!'), findsOneWidget);
    // The label alone doesn't prove the tap was rejected — it's clamped
    // with math.max(0, ...) and would keep reading "Pop 0 more!" even if
    // `_popped` climbed past the target. A pop-sparkle ('✨' in
    // _PopSparkle, lib/screens/bubble_pop_screen.dart) only ever appears
    // when `_pop` actually accepts a tap and flips `bubble.popping = true`;
    // since the extra tap should have been rejected by the
    // `_roundComplete` guard, no sparkle should exist 100ms later (well
    // within its 400ms animation window).
    expect(find.text('✨'), findsNothing);

    // Flush the pending 600ms win-delay timer so the test doesn't end
    // with a dangling Future.delayed still outstanding.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('bubble pop reset during the win delay cancels the celebration', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BubblePopScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    // Read the fresh-round label from the live tree rather than
    // hard-coding the pops-per-round count, which is private to the
    // screen and could drift out of sync with a hard-coded value here.
    final freshRoundLabel = tester
        .widget<Text>(find.textContaining('more!'))
        .data!;

    await popBubblesUntilRoundComplete(tester);
    expect(find.text('Pop 0 more!'), findsOneWidget);

    // Hit the manual reset well before the 600ms win delay elapses.
    await tester.tap(find.text('🔁'));
    await tester.pump(const Duration(milliseconds: 100));

    // Advance past when the (now-cancelled) win timer would have fired.
    await tester.pump(const Duration(milliseconds: 600));

    // The celebration must not appear over the freshly-reset round, and
    // the round must be back to its starting count and still playable.
    expect(find.text('Pop-tastic!'), findsNothing);
    expect(find.text(freshRoundLabel), findsOneWidget);

    await tester.tap(bubbleTexts().first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(freshRoundLabel), findsNothing);
    expect(find.textContaining('-'), findsNothing);
  });

  testWidgets('home title stays centered after returning from a game', (
    tester,
  ) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    final title = find.text('Tiny Tapsters');

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

  testWidgets('companion blocks inappropriate input gently', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanionScreen()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'fuck you');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    // The child sees only Pollie's gentle redirect — never the bad word.
    expect(find.textContaining('not a nice thing'), findsOneWidget);
    expect(find.textContaining('fuck'), findsNothing);
  });

  testWidgets('KidSafety catches adult words but not innocent ones', (
    tester,
  ) async {
    expect(KidSafety.containsBlocked('fuck this'), isTrue);
    expect(KidSafety.containsBlocked('kontol'), isTrue);
    expect(KidSafety.containsBlocked('you are stupid'), isTrue);
    // Innocent words with similar substrings must pass.
    expect(KidSafety.containsBlocked('hello friend'), isFalse);
    expect(KidSafety.containsBlocked('my class is fun'), isFalse);
    expect(KidSafety.containsBlocked('tell me a story'), isFalse);
  });

  test('Pollie picks the highest-quality voice, not the first one', () {
    // Android returns quality as a word ("very high"), so the old `as num?`
    // cast scored every voice zero and the ranking collapsed to "first
    // match, preferring female". This list is arranged so that broken
    // ordering picks the low-quality female voice sitting at the front,
    // while correct ranking reaches the far better male neural voice.
    final voices = <Map<dynamic, dynamic>>[
      {
        'name': 'en-us-x-iol#female_1-local',
        'locale': 'en-US',
        'quality': 'normal',
        'network_required': '0',
      },
      {
        'name': 'en-us-x-tpd#male_3-network',
        'locale': 'en-US',
        'quality': 'very high',
        'network_required': '1',
      },
      {
        'name': 'en-gb-x-gba#female_1-local',
        'locale': 'en-GB',
        'quality': 'very high',
        'network_required': '1',
      },
    ];

    final best = pickBestVoice(voices, 'en-US');
    expect(best?['name'], 'en-us-x-tpd#male_3-network');
    // The en-GB voice is just as good on paper, but the conversation is in
    // en-US and the accent should match.
    expect(
      pickBestVoice(voices, 'en-GB')?['name'],
      'en-gb-x-gba#female_1-local',
    );
  });

  test('Pollie voice ranking prefers network and female, avoids eSpeak', () {
    int score(String name, String quality, String network) => voiceScore({
      'name': name,
      'locale': 'en-US',
      'quality': quality,
      'network_required': network,
    });

    // Quality dominates everything else.
    expect(
      score('a-local', 'very high', '0'),
      greaterThan(score('b-network', 'normal', '1')),
    );
    // At equal quality, a network (neural) voice wins.
    expect(
      score('a-network', 'high', '1'),
      greaterThan(score('b-local', 'high', '0')),
    );
    // At equal quality and network, female wins.
    expect(
      score('en-us-x-xxx#female_1-local', 'high', '0'),
      greaterThan(score('en-us-x-xxx#male_1-local', 'high', '0')),
    );
    // eSpeak is last, even at nominally high quality.
    expect(
      score('espeak-en', 'very high', '1'),
      lessThan(score('anything-local', 'very low', '0')),
    );
  });

  test('voice maps survive the shape a platform channel actually returns', () {
    // getVoices hands back List<Object?> of Map<Object?, Object?>. Asserting
    // List<Map<dynamic, dynamic>> on that throws, which is exactly how voice
    // selection silently did nothing. Rebuilt maps must still rank.
    final fromChannel = <Object?>[
      <Object?, Object?>{
        'name': 'en-us-x-iog-local',
        'locale': 'en-US',
        'quality': 'normal',
        'network_required': '0',
      },
      <Object?, Object?>{
        'name': 'en-us-x-tpd-network',
        'locale': 'en-US',
        'quality': 'very high',
        'network_required': '1',
      },
    ];
    expect(
      () => fromChannel as List<Map<dynamic, dynamic>>,
      throwsA(isA<TypeError>()),
      reason: 'the old cast threw; that is the bug being guarded against',
    );

    final rebuilt = fromChannel
        .whereType<Map>()
        .map<Map<dynamic, dynamic>>(Map<dynamic, dynamic>.from)
        .toList();
    expect(pickBestVoice(rebuilt, 'en-US')?['name'], 'en-us-x-tpd-network');
  });

  test('a voice list with nothing for the language yields no pick', () {
    final voices = <Map<dynamic, dynamic>>[
      {'name': 'id-id-x-idc-local', 'locale': 'id-ID', 'quality': 'high'},
    ];
    expect(pickBestVoice(voices, 'en-US'), isNull);
    expect(pickBestVoice(const [], 'en-US'), isNull);
    expect(pickBestVoice(null, 'en-US'), isNull);
    // Matching is by language, not exact locale.
    expect(pickBestVoice(voices, 'id-ID')?['name'], 'id-id-x-idc-local');
  });

  testWidgets('companion mic tap always responds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanionScreen()));
    await tester.pump();

    // Pollie is asleep (no API key in tests) → tapping the mic wakes him
    // instead of doing nothing. He then reports he can't reach the
    // internet — either way, the mic always responds.
    await tester.tap(find.text('🎤'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining("can't reach the internet"), findsOneWidget);
  });

  testWidgets('quota reset label is computed and formatted', (tester) async {
    final label = PollieService().quotaResetLabel();
    expect(
      RegExp(
        r'^at \d{2}:\d{2} \(in about (\d+ h \d+ m|\d+ m)\)$',
      ).hasMatch(label),
      isTrue,
      reason: label,
    );
  });

  testWidgets('count game: wrong tap never advances, correct tap does', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CountGameScreen(maxCount: 3, random: math.Random(42))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Round 1: a wrong tap first — the card shakes but the round does NOT
    // advance (easy cards are always exactly {1, 2, 3}, so any other value
    // is a real wrong card).
    final n = countQuestionAnimals(tester);
    final wrong = n == 1 ? 2 : 1;
    await tester.tap(find.byKey(ValueKey('answer-$wrong')));
    await tester.pump(const Duration(milliseconds: 500)); // shake finishes
    expect(
      countQuestionAnimals(tester),
      n,
      reason: 'wrong tap must not start a new round',
    );
    expect(countRoundDotColor(tester, 0), isNot(const Color(0xFFFF9800)));

    // The correct tap highlights, then advances after the ~600ms delay.
    await tester.tap(find.byKey(ValueKey('answer-$n')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      countRoundDotColor(tester, 0),
      const Color(0xFFFF9800),
      reason: 'round 1 complete',
    );

    // Finish the remaining 4 rounds perfectly.
    for (var i = 0; i < 4; i++) {
      final count = countQuestionAnimals(tester);
      await tester.tap(find.byKey(ValueKey('answer-$count')));
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Exactly 1 wrong tap in the whole game → 3 stars.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('count game: double tap during the advance delay counts once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CountGameScreen(maxCount: 3, random: math.Random(7))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final n = countQuestionAnimals(tester);
    await tester.tap(find.byKey(ValueKey('answer-$n')));
    await tester.pump(
      const Duration(milliseconds: 300),
    ); // inside the 600ms window
    await tester.tap(find.byKey(ValueKey('answer-$n'))); // guarded by _busy
    await tester.pump(const Duration(milliseconds: 400)); // past the window

    expect(
      countRoundDotColor(tester, 0),
      const Color(0xFFFF9800),
      reason: 'round must advance exactly once',
    );
    expect(
      countRoundDotColor(tester, 1),
      isNot(const Color(0xFFFF9800)),
      reason: 'the double tap must not skip a second round',
    );
  });

  testWidgets('count game: big mode with many mistakes earns one star', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CountGameScreen(maxCount: 10, random: math.Random(7))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Answer wrong on every round: 5 mistakes total (≥4) → 1 star.
    // maxCount 10 also exercises the full 10-animal / 10-dot layout.
    for (var round = 0; round < 5; round++) {
      final n = countQuestionAnimals(tester);
      final wrong = countAnswerValues(tester).firstWhere((v) => v != n);
      await tester.tap(find.byKey(ValueKey('answer-$wrong')));
      await tester.pump(const Duration(milliseconds: 400)); // shake finishes
      await tester.tap(find.byKey(ValueKey('answer-$n')));
      await tester.pump(const Duration(milliseconds: 700)); // advance delay
    }

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNWidgets(2));
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

// --- Bubble Pop test helpers ------------------------------------------------

/// Bubble emoji are 40px Text; the pop-sparkle that replaces one while it
/// animates away is 56px, so this finder always lands on a live, tappable
/// bubble (never one mid-pop).
Finder bubbleTexts() => find.byWidgetPredicate(
  (w) => w is Text && w.style?.fontSize == 40 && w.data != null,
);

/// Taps bubbles until the round's header reads "Pop 0 more!", without ever
/// needing to know the pops-per-round count (private to the screen, and a
/// prior version of this test hard-coded it — which is exactly the drift
/// this avoids). Bounded by a generous safety cap so a regression that
/// breaks the win condition fails the test loudly instead of hanging.
Future<void> popBubblesUntilRoundComplete(WidgetTester tester) async {
  const safetyCap = 50;
  for (var i = 0; i < safetyCap; i++) {
    if (find.text('Pop 0 more!').evaluate().isNotEmpty) return;
    await tester.tap(bubbleTexts().first);
    await tester.pump(); // start the pop-sparkle animation
    // Let the sparkle finish and the bubble respawn, staying well under
    // the 600ms win delay so that delay can't mask a bug in this loop.
    await tester.pump(const Duration(milliseconds: 450));
  }
  fail('bubble pop round never reached "Pop 0 more!" within $safetyCap taps');
}

// --- Count the Animals! test helpers --------------------------------------

/// The number of animal emojis in the question pill (each is a 40px Text).
int countQuestionAnimals(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('question-pill')),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 40 && w.data != null,
        ),
      ),
    )
    .length;

/// The three digit values shown on the answer cards this round.
List<int> countAnswerValues(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(KeyedSubtree),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 54 && w.data != null,
        ),
      ),
    )
    .map((t) => int.parse(t.data!))
    .toList();

/// Color of round-progress dot [i] (orange once round i is complete).
Color countRoundDotColor(WidgetTester tester, int i) {
  final box =
      tester.widget<Container>(find.byKey(ValueKey('round-dot-$i'))).decoration!
          as BoxDecoration;
  return box.color!;
}
