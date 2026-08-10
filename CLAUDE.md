# CLAUDE.md — Project Memory for AI Agents

## Quick facts

- **Tiny Tapsters**: Flutter toddler-games app (`com.inkpebble.tiny_tapsters`), **v1.15.0+34**, Flutter 3.41.6 (stable), Android-first, emoji-based graphics (no image assets).
- **Dependencies**: `audioplayers` (SFX + music), `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev. Bundled assets: `assets/sfx/*` (pop, win_high, win_low, lose) and `assets/music/*` (main_theme, game_song) — `assets/branding/tiny-tapsters-logo.png` is build-time input for the icon generator and is deliberately not in `pubspec.yaml`.
- **Audio**: `MusicService` (looping music) is separate from `SoundEffects` (one-shots) on purpose — `pop()` stops its player before every play, so one shared player would let every tap kill the music. Track switching lives in `MusicRouteObserver`, not in each screen's `initState`, because popping a game does not re-run `HomeScreen.initState`. Every player must stay on `AudioContextConfigFocus.mixWithOthers` (set once in `main.dart`) — the default `AudioFocus.gain` is exclusive and makes each sound effect stop the music. **Never hand-encode audio** — run `python3 tool/normalize_audio.py <source-dir>`, which rebuilds every asset at one loudness (−16 dBFS RMS, 44.1 kHz). Hand-rolled `afconvert` calls are how the animal calls shipped at 22 kHz and how the mix ended up 20 dB apart.
- **Permissions**: `INTERNET` + `RECORD_AUDIO` — both exist only for Pollie's voice chat. **All seven games are fully offline**; Pollie is the sole network feature.
- **Default branch is `develop`**; release = merge to `main` + annotated tag `vX.Y.Z` (push both).
- **Features go on a dedicated `feature/<name>` branch** off `develop` — never commit feature work straight to `develop`. Plan in chat first, then execute.
- **Validation before any commit:** `flutter analyze` (0 issues), `dart format --set-exit-if-changed lib/ test/`, `flutter test` (**86/86**), `flutter build apk --release` (when native config or deps change).
- **Never touch/commit**: `android/key.properties`, `android/app/release-keystore.jks`, or any Gemini API key. **The key no longer ships in the app at all** — it lives in the Cloudflare Worker under `worker/` (see its README). The app takes only `--dart-define=POLLIE_ENDPOINT=https://...`, which is a URL, not a secret; CI reads it from the `POLLIE_ENDPOINT` repo *variable*.

## Multi-part work

- **Sub-agent workflow:** use `superpowers:subagent-driven-development` for tasks spanning multiple files — separate implementer per task, reviewer with fresh eyes, tester running validation (`flutter analyze` / `dart format` / `flutter test`).
- **Skills must be invoked.** They don't run automatically; this file is the reminder to reach for them.

## Commands

```bash
flutter analyze
dart format --set-exit-if-changed lib/ test/
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Layout

- `lib/screens/` — `home_screen` (menu), `levels_screen` (shared Easy/Medium/Big picker), `companion_screen` (Pollie), and the games: `jigsaw_game`, `animal_food`, `memory_game`, `bubble_pop`, `find_it`, `count_game`, `animal_sound`.
- `lib/data/animal_sounds.dart` — emoji → call asset for "Which Animal?". Keys must be in `kAnimalEmojis` (tested). CC0, public-domain or CC BY — **never ShareAlike**. Every call needs an entry in `lib/data/asset_credits.dart` (shown by `CreditsScreen`) and in `ASSET_CREDITS.md`; a test enforces it. Sources are Wikimedia Commons and the Internet Archive (the CC0 Designer's Choice library — Commons has no cow moo at all).
- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food).
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons); fires the win sound itself.
- `lib/widgets/game_timer.dart` — `GameLevel` (30s/1m/2m), `GameTimerController`, the no-digits `GameTimerBar`, and the `TimedGame` mixin every game uses. Clock starts on first interaction, pauses on background, stops the instant a game is won.
- `lib/widgets/game_over_overlay.dart` — the "Time's up!" screen; a sibling of `CelebrationOverlay`, not a flag on it.
- `lib/services/` — `pollie_service` (HTTP client for the `worker/` proxy; model, prompt and safety settings live server-side), `kid_safety` (local adult-word guard on input *and* output), `sound_effects` (one-shot SFX), `music_service` + `music_route_observer` (looping background music).
- `docs/superpowers/specs/` — design specs. Read the relevant one before touching a feature it covers.
- `worker/` — the Cloudflare Worker holding Pollie's Gemini key. Setup steps in `worker/README.md`; deploying needs the user (interactive login + secret).
- `tool/` — dependency-free Dart generators: `generate_icon.dart` (crops the badge out of `assets/branding/tiny-tapsters-logo.png` and writes the legacy + adaptive launcher icons; has its own PNG decoder/encoder), `generate_sfx.dart` (pop.wav + wrong.wav), `pixelcheck.dart`. Also `normalize_audio.py` — the one deviation from the dependency-free-Dart rule, because normalising audio needs macOS `afconvert` anyway.
- `.github/workflows/release-apk.yml` — on `v*` tag push: analyze + test, sign with the real keystore, attach the APK to the GitHub release.

## Constraints

- No ads, no analytics, no tracking. Ever.
- All games must be playable without reading: big emoji, no required text.
- Keep `CHANGELOG.md` and `README.md` in sync with real changes.
- `AGENTS.md` (Zed's copy of these instructions) must stay consistent with this file.

## Golden rules learned the hard way

1. Xiaomi/HyperOS blocks `adb install` unless `adb_install_need_confirm` is set to 0 (`adb shell settings put global adb_install_need_confirm 0`) — already done on the test device (Xiaomi 15).
2. Wireless debugging sessions expire on their own. Reconnect: `adb mdns services` shows the device; `adb connect <ip>:<port>`; if refused, ask the user to reopen the Wireless debugging screen.
3. Never swap widget types mid-gesture (e.g. `AnimatedPositioned` ↔ `Positioned` while a pan is active) — it cancels the pan. Keep the tree structure stable; if a piece moves, keep it instant (animated returns read as "trails").
4. Emoji glyphs render smaller than their text box — use `FittedBox(fit: BoxFit.fill)` (or a large font size) when an emoji must fill a cell/board.
5. Widget tests that **tap** must set a phone viewport (`tester.view.physicalSize = Size(1080, 2400)`, dpr 3). At flutter_test's default 800x600 the taller game grids scroll and their bottom row is untappable, so a test can silently "pass" having played no rounds at all.
6. Xiaomi's emoji font may render some codepoints oddly — prefer widely-supported emoji (Unicode ≥ 6) for game content.
7. Test on the Xiaomi 15 via wireless adb. `adb install -r` works for *updates* to an already-installed package. Installing a **new** `applicationId` still fails with `INSTALL_FAILED_USER_RESTRICTED` even though `adb_install_need_confirm` is 0 — HyperOS applies a stricter check to first-time installs. Workaround that does work:
   ```bash
   adb push app.apk /data/local/tmp/x.apk && adb shell pm install -r -t /data/local/tmp/x.apk
   ```
8. Renaming the `applicationId` resets the app's identity: runtime permissions are revoked and the old package lingers until `adb uninstall`. Re-grant with `adb shell pm grant <pkg> android.permission.RECORD_AUDIO` so Pollie's mic keeps working.
