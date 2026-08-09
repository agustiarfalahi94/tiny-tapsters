import '../screens/animal_food_screen.dart' show kAnimalEmojis;

/// The animals whose calls the app can play, and where each recording lives.
///
/// Every key must be one of [kAnimalEmojis] — that list stays the single
/// source of truth for which animals exist, and a test enforces it, so a typo
/// cannot invent an animal that appears in this game and nowhere else.
///
/// This map is short on purpose. It holds only animals for which a **CC0 or
/// public-domain** recording was found and its licence verified on the source
/// page; see `ASSET_CREDITS.md`. Animals with no such recording — notably 🐮
/// the cow and 🐶 the dog, the two a toddler knows best — are simply absent
/// here and unchanged in every other game. Adding them means either finding
/// free recordings or accepting CC-BY and shipping a credits screen.
const kAnimalSounds = <String, String>{
  '🐱': 'animal_sounds/cat.m4a',
  '🐴': 'animal_sounds/horse.m4a',
  '🐔': 'animal_sounds/chicken.m4a',
  '🦁': 'animal_sounds/lion.m4a',
  '🐘': 'animal_sounds/elephant.m4a',
  '🐸': 'animal_sounds/frog.m4a',
};
