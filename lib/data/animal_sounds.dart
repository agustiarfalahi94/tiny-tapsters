import '../screens/animal_food_screen.dart' show kAnimalEmojis;

/// The animals whose calls the app can play, and where each recording lives.
///
/// Most of these are also in [kAnimalEmojis], the pool Animal Food and Count
/// share — but this game is deliberately *not* limited to that list. Animal
/// Food needs a food for every animal it uses; a listening game does not, so
/// requiring one here would mean inventing a meal for a tiger before it could
/// have a roar. 🐷 🐦 🐯 exist only in this game for that reason.
///
/// Every recording is from Pixabay except the dog, which is CC0 from Wikimedia
/// Commons. See `ASSET_CREDITS.md`. A test checks each has a credit entry, that
/// no two animals share an emoji, and that each file is bundled.
const kAnimalSounds = <String, String>{
  '🐱': 'animal_sounds/cat.m4a',
  '🐶': 'animal_sounds/dog.m4a',
  '🐮': 'animal_sounds/cow.m4a',
  '🐴': 'animal_sounds/horse.m4a',
  '🐷': 'animal_sounds/pig.m4a',
  '🐔': 'animal_sounds/chicken.m4a',
  '🐦': 'animal_sounds/bird.m4a',
  '🐭': 'animal_sounds/mouse.m4a',
  '🐸': 'animal_sounds/frog.m4a',
  '🦁': 'animal_sounds/lion.m4a',
  '🐯': 'animal_sounds/tiger.m4a',
  '🐵': 'animal_sounds/monkey.m4a',
  '🐻': 'animal_sounds/bear.m4a',
  '🐘': 'animal_sounds/elephant.m4a',
  '🐧': 'animal_sounds/penguin.m4a',
};
