import '../screens/animal_food_screen.dart' show kAnimalEmojis;

/// The animals whose calls the app can play, and where each recording lives.
///
/// Every key must be one of [kAnimalEmojis] — that list stays the single
/// source of truth for which animals exist, and a test enforces it, so a typo
/// cannot invent an animal that appears in this game and nowhere else.
///
/// Only animals whose recording is CC0, public domain or CC BY — never
/// ShareAlike, which would reach into the app itself. Licences are verified on
/// each source page and recorded in `ASSET_CREDITS.md`; the CC BY ones are
/// credited in-app by `CreditsScreen`.
///
/// 🐮 the cow is still missing, and not for want of looking: four searches of
/// Commons turn up Lingua Libre recordings of people pronouncing the word
/// "cow", a gospel song, and one fart. There is no moo on Commons. Filling it
/// needs a recording from somewhere else — or a phone held over a fence.
const kAnimalSounds = <String, String>{
  '🐱': 'animal_sounds/cat.m4a',
  '🐶': 'animal_sounds/dog.m4a',
  '🐴': 'animal_sounds/horse.m4a',
  '🐔': 'animal_sounds/chicken.m4a',
  '🦁': 'animal_sounds/lion.m4a',
  '🐵': 'animal_sounds/monkey.m4a',
  '🐘': 'animal_sounds/elephant.m4a',
  '🐸': 'animal_sounds/frog.m4a',
};
