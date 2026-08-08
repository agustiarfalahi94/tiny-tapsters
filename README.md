# Our Toddlers' Journey — Toddler Games

Free toddler games for Android, built with Flutter. No ads, no tracking —
just big colorful buttons and emoji. **All games work fully offline**; the
only online feature is the optional **Pollie 🦜 companion** (Google Gemini).

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
- **Pollie 🦜** — a talking companion on the home screen (bottom-right
  button). Pollie sleeps 😴 while offline and smiles 😊 when connected, then
  greets the child. **Talk to him with the 🎤 button** (speech is
  transcribed, answered, and spoken aloud — he listens again automatically
  for a hands-free conversation). Toddler-friendly tap chips plus a text
  field for grown-ups. Powered by Gemini; needs an API key (see below).

## Run it

```sh
flutter run            # on a connected device/emulator
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the shared `random_recall` keystore
(`android/key.properties` + `android/app/release-keystore.jks`, both
git-ignored) and minified with R8.

## Download the APK

Every release has a ready-to-install APK attached to it:
<https://github.com/agustiarfalahi94/our-toddlers-journey/releases> —
open a version and grab the `our-toddlers-journey-vX.Y.Z.apk` asset.

- The APK is built automatically by the `Release APK` GitHub Actions
  workflow (analyze + tests must pass, then it signs with the real
  keystore and attaches the APK to the release).
- **Repo access**: the repo is private, so only people you invite can
  download. Make the repo public if you want anyone to grab it.
- **First install**: Android will ask to allow installs from the browser
  ("unknown sources") — that's normal for sideloaded APKs. Play Protect
  may also show a scan warning; the APK is signed by your own key.
- **Pollie works out of the box**: the release APK is built with the
  Gemini key baked in, so the companion is fully functional in
  downloaded copies too (the key lives in the APK, as with any
  sideloaded app).

## Pollie (Gemini companion)

To enable Pollie, build with your own free API key from
<https://aistudio.google.com/apikey>:

```sh
flutter build apk --release --dart-define=GEMINI_API_KEY=your_key_here
```

The key is compiled into the APK and never committed to the repository.
Chat messages and voice input are sent to Google's Gemini and speech
services. Without a key, Pollie shows a friendly fallback message.

## Project layout

```
lib/
  main.dart                      # app entry (portrait + immersive mode)
  screens/
    home_screen.dart             # game chooser + Pollie button
    levels_screen.dart           # shared difficulty picker
    jigsaw_game_screen.dart      # picture puzzle
    animal_food_screen.dart      # feed the animals
    memory_game_screen.dart      # matching pairs
    bubble_pop_screen.dart       # bubble popping
    find_it_screen.dart          # find the matching animal
    companion_screen.dart        # Pollie chat (Gemini)
  services/
    pollie_service.dart          # Gemini API wrapper
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
