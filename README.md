# Tiny Tapsters — Toddler Games

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
- **Count the Animals!** — count the big animal emojis and tap the number card
  (digit + dot pattern) that matches. Wrong taps shake and let you try again.
  Easy (count to 3), Medium (to 5), Big (to 10).
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
<https://github.com/agustiarfalahi94/tiny-tapsters/releases> —
open a version and grab the `tiny-tapsters-vX.Y.Z.apk` asset.

- The APK is built automatically by the `Release APK` GitHub Actions
  workflow (analyze + tests must pass, then it signs with the real
  keystore and attaches the APK to the release).
- **Repo access**: the repo is private, so only people you invite can
  download. Make the repo public if you want anyone to grab it.
- **First install**: Android will ask to allow installs from the browser
  ("unknown sources") — that's normal for sideloaded APKs. Play Protect
  may also show a scan warning; the APK is signed by your own key.
- **Pollie works out of the box**: the release APK points at the proxy,
  so the companion is fully functional in downloaded copies without
  anyone needing an API key of their own.

## Pollie (Gemini companion)

Pollie talks to a small Cloudflare Worker (`worker/`) that holds the
Gemini key. The app ships only the Worker's URL:

```sh
flutter build apk --release \
  --dart-define=POLLIE_ENDPOINT=https://pollie.your-subdomain.workers.dev
```

The key used to be compiled into the APK. That was a mistake: a
`--dart-define` string ends up in `libapp.so` in the clear, and
`strings libapp.so | grep AIza` recovers it in seconds — the repo being
private did not help, because the signed APK is attached to releases.
Everyone also shared one free-tier quota. `worker/README.md` has the
setup, which takes a free Cloudflare account and about five minutes.

Chat messages and voice input are sent to Google's Gemini and to the
device's speech services. Without an endpoint, Pollie shows a friendly
fallback message and the seven games are unaffected — they are all fully
offline.

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
    count_game_screen.dart       # count the animals
    animal_sound_screen.dart     # guess the animal by its call
    companion_screen.dart        # Pollie chat (via the worker/ proxy)
    credits_screen.dart          # sound attribution (CC BY requires it)
  services/
    pollie_service.dart          # HTTP client for Pollie's proxy (worker/)
    kid_safety.dart              # local adult-word guard (input + output)
    sound_effects.dart           # one-shot SFX (pop, win, lose)
    music_service.dart           # looping background music
    music_route_observer.dart    # keeps the music in step with the screen
  widgets/
    game_background.dart         # shared gradient background
    round_button.dart            # shared round emoji button
    celebration_overlay.dart     # confetti + stars + buttons
    pair_drag_game.dart          # shared drag-to-slot engine (jigsaw + food)
    flip_card.dart               # 3D card flip animation
    confetti.dart                # celebration effect
assets/
  branding/
    tiny-tapsters-logo.png       # master artwork (build-time only, not bundled)
  animal_sounds/*.m4a            # CC0 animal calls (see ASSET_CREDITS.md)
  sfx/pop.wav                    # bubble pop
  sfx/win_high.m4a               # 3-star fanfare
  sfx/win_low.m4a                # 1- and 2-star fanfare
  sfx/lose.m4a                   # out of time
  music/main_theme.m4a           # menus
  music/game_song.m4a            # games
tool/
  generate_icon.dart             # launcher icons, derived from the logo
  generate_sfx.dart              # regenerates pop.wav
```

## Branding

The launcher icon is generated from `assets/branding/tiny-tapsters-logo.png`
(the full Canva artwork) by a pure-Dart tool — no packages, no Flutter engine:

```sh
dart run tool/generate_icon.dart
```

It crops the badge out of the artwork, drops the wordmark (illegible at icon
sizes), knocks the white page colour out of the rounded corners, and writes
both the legacy mipmap PNGs and the adaptive icon — the baby isolated on
transparency as the foreground, over the badge's own mint as a solid
background. Re-run it after changing the logo. The artwork itself is *not*
listed in `pubspec.yaml`, so it never ships inside the APK.

## Test

```sh
flutter test
```
