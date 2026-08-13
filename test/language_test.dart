import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/main.dart';
import 'package:tiny_tapsters/services/app_language.dart';

void main() {
  setUp(() {
    AppLanguageService.instance.current.value = AppLanguage.english;
  });

  test('English is the default', () {
    expect(AppLanguageService.instance.current.value, AppLanguage.english);
    expect(strings.findIt, 'Find It!');
  });

  test('the names the user chose are used exactly', () {
    const id = AppStrings(AppLanguage.indonesian);
    expect(id.findIt, 'Cari Hewan Ini!');
    expect(id.animalFood, 'Beri Makan Hewan');
    expect(id.whichAnimal, 'Tebak Suara Hewan');
  });

  test('every string is translated, and none is left in English', () {
    const en = AppStrings(AppLanguage.english);
    const id = AppStrings(AppLanguage.indonesian);
    // Spot-checking would miss the one that was forgotten, so compare the
    // whole surface: every getter must differ between the two languages.
    final pairs = <String, List<String>>{
      'appTagline': [en.appTagline, id.appTagline],
      'talkToPollie': [en.talkToPollie, id.talkToPollie],
      'tapToTalk': [en.tapToTalk, id.tapToTalk],
      'pickALevel': [en.pickALevel, id.pickALevel],
      'easy': [en.easy, id.easy],
      'medium': [en.medium, id.medium],
      'big': [en.big, id.big],
      'jigsaw': [en.jigsaw, id.jigsaw],
      'jigsawSubtitle': [en.jigsawSubtitle, id.jigsawSubtitle],
      'animalFood': [en.animalFood, id.animalFood],
      'animalFoodSubtitle': [en.animalFoodSubtitle, id.animalFoodSubtitle],
      'memory': [en.memory, id.memory],
      'memorySubtitle': [en.memorySubtitle, id.memorySubtitle],
      'bubblePop': [en.bubblePop, id.bubblePop],
      'bubblePopSubtitle': [en.bubblePopSubtitle, id.bubblePopSubtitle],
      'findIt': [en.findIt, id.findIt],
      'findItSubtitle': [en.findItSubtitle, id.findItSubtitle],
      'whichAnimal': [en.whichAnimal, id.whichAnimal],
      'whichAnimalSubtitle': [en.whichAnimalSubtitle, id.whichAnimalSubtitle],
      'countAnimals': [en.countAnimals, id.countAnimals],
      'countAnimalsSubtitle': [
        en.countAnimalsSubtitle,
        id.countAnimalsSubtitle,
      ],
      'feedTheAnimals': [en.feedTheAnimals, id.feedTheAnimals],
      'whoMadeThatSound': [en.whoMadeThatSound, id.whoMadeThatSound],
      'timesUp': [en.timesUp, id.timesUp],
      'tryAgain': [en.tryAgain, id.tryAgain],
      'playAgain': [en.playAgain, id.playAgain],
      'home': [en.home, id.home],
      'levels': [en.levels, id.levels],
      'moreGames': [en.moreGames, id.moreGames],
      'wonJigsaw': [en.wonJigsaw, id.wonJigsaw],
      'wonAnimalFood': [en.wonAnimalFood, id.wonAnimalFood],
      'wonMemory': [en.wonMemory, id.wonMemory],
      'wonBubbles': [en.wonBubbles, id.wonBubbles],
      'wonFindIt': [en.wonFindIt, id.wonFindIt],
      'wonCount': [en.wonCount, id.wonCount],
      'wonSound': [en.wonSound, id.wonSound],
      'soundCredits': [en.soundCredits, id.soundCredits],
      'pollieGreeting': [en.pollieGreeting, id.pollieGreeting],
      'saySomething': [en.saySomething, id.saySomething],
      'listening': [en.listening, id.listening],
      'sleeping': [en.sleeping, id.sleeping],
      'chipStory': [en.chipStory, id.chipStory],
      'pollieLost': [en.pollieLost, id.pollieLost],
      'pollieNoMic': [en.pollieNoMic, id.pollieNoMic],
    };
    for (final entry in pairs.entries) {
      expect(entry.value[0], isNotEmpty, reason: entry.key);
      expect(entry.value[1], isNotEmpty, reason: entry.key);
      expect(
        entry.value[1],
        isNot(entry.value[0]),
        reason: '${entry.key} is still English in Indonesian',
      );
    }
  });

  test('counted phrases keep their number in both languages', () {
    const id = AppStrings(AppLanguage.indonesian);
    expect(id.animals(6), contains('6'));
    expect(id.pieces(9), contains('9'));
    expect(id.countTo(10), contains('10'));
    expect(id.pairsLeft(3), contains('3'));
    expect(id.catchTimes(4), contains('4'));
  });

  test('each language carries the locale speech and TTS need', () {
    expect(AppLanguage.english.localeId, 'en-US');
    expect(AppLanguage.indonesian.localeId, 'id-ID');
  });

  testWidgets('the flag button switches the whole app', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(() {
      AppLanguageService.instance.current.value = AppLanguage.english;
    });

    await tester.pumpWidget(const ToddlerGamesApp());
    await tester.pump(const Duration(milliseconds: 100));
    // Asserting on what is actually on screen: the list scrolls, and the
    // games further down are not built yet.
    expect(find.text('Fun games for little learners'), findsOneWidget);
    expect(find.text('Jigsaw Puzzle'), findsOneWidget);

    await tester.tap(find.text('🇬🇧'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Permainan seru untuk si kecil'), findsOneWidget);
    expect(find.text('Susun Gambar'), findsOneWidget);
    expect(find.text('Jigsaw Puzzle'), findsNothing);
    expect(find.text('🇮🇩'), findsOneWidget);
  });
}
