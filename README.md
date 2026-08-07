# Our Toddlers' Journey — Toddler Games

Free, offline Android games for toddlers, built with Flutter. No ads, no
permissions, no internet needed — just big colorful buttons and emoji.

## Games

- **Jigsaw Puzzle** — a real picture puzzle: the picture is sliced into pieces
  with a faint reference image behind the board. Easy (2×2), Medium (3×2),
  Big (3×3).
- **Animal Food** — drag each animal to its favorite food (rabbit → carrot,
  cow → clover, horse → apple…). A pool of 15 animal/food pairs, shuffled each
  game. Easy (3), Medium (6), Big (9).
- **Memory Match** — flip cards to find matching animal pairs. Easy (2 pairs),
  Medium (3 pairs), Big (6 pairs). Stars are awarded based on how few moves it
  takes.
- **Bubble Pop** — tap floating bubbles to pop them. Pop 8 per round; bubbles
  get faster each round.
- **Find It!** — "Find the 🐶!": tap the matching animal in the grid. Find 5 to
  win; fewer wrong taps means more stars. Easy (6), Medium (9), Big (12).

## Run it

```sh
flutter run            # on a connected device/emulator
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the shared `random_recall` keystore
(`android/key.properties` + `android/app/release-keystore.jks`, both
git-ignored) and minified with R8.

## Project layout

```
lib/
  main.dart                      # app entry (portrait + immersive mode)
  screens/
    home_screen.dart             # game chooser
    levels_screen.dart           # shared difficulty picker
    jigsaw_game_screen.dart      # picture puzzle
    animal_food_screen.dart      # feed the animals
    memory_game_screen.dart      # matching pairs
    bubble_pop_screen.dart       # bubble popping
    find_it_screen.dart          # find the matching animal
  widgets/
    game_background.dart         # shared gradient background
    round_button.dart            # shared round emoji button
    celebration_overlay.dart     # confetti + stars + buttons
    pair_drag_game.dart          # shared drag-to-slot engine (jigsaw + food)
    flip_card.dart               # 3D card flip animation
    confetti.dart                # celebration effect
```

## Test

```sh
flutter test
```
