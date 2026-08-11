# CLAUDE.md — Project Memory for AI Agents

## Quick facts

- **Tiny Tapsters**: Flutter toddler-games app (`com.inkpebble.tiny_tapsters`), **v1.25.0+55**, Flutter 3.41.6 (stable), Android-first, emoji-based graphics (no image assets).
- **Dependencies**: `audioplayers` (SFX + music), `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev. Bundled assets: `assets/sfx/*` (pop, win_high, win_low, lose) and `assets/music/*` (main_theme, game_song) — `assets/branding/tiny-tapsters-logo.png` is build-time input for the icon generator and is deliberately not in `pubspec.yaml`.
- **Audio**: `MusicService` (looping music) is separate from `SoundEffects` (one-shots) on purpose — `pop()` stops its player before every play, so one shared player would let every tap kill the music. Track switching lives in `MusicRouteObserver`, not in each screen's `initState`, because popping a game does not re-run `HomeScreen.initState`. Every player must stay on `AudioContextConfigFocus.mixWithOthers` (set once in `main.dart`) — the default `AudioFocus.gain` is exclusive and makes each sound effect stop the music. **Never hand-encode audio** — run `python3 tool/normalize_audio.py <source-dir>`, which rebuilds every asset at one loudness (−16 dBFS RMS, 44.1 kHz). Hand-rolled `afconvert` calls are how the animal calls shipped at 22 kHz and how the mix ended up 20 dB apart.
- **Permissions**: `INTERNET` + `RECORD_AUDIO` — both exist only for Pollie's voice chat. **All seven games are fully offline**; Pollie is the sole network feature.
- **Default branch is `develop`**; release = merge to `main` + annotated tag `vX.Y.Z` (push both).
- **Features go on a dedicated `feature/<name>` branch** off `develop` — never commit feature work straight to `develop`. Plan in chat first, then execute.
- **Validation before any commit:** `flutter analyze` (0 issues), `dart format --set-exit-if-changed lib/ test/`, `flutter test` (**170/170**), `flutter build apk --release` (when native config or deps change).
- **Never touch/commit**: `android/key.properties`, `android/app/release-keystore.jks`, or any Gemini API key. **The key no longer ships in the app at all** — it lives in the Cloudflare Worker under `worker/` (see its README). The app defaults to the deployed proxy at `https://pollie.inkpebble.workers.dev`; override with `--dart-define=POLLIE_ENDPOINT=...`. A URL is not a secret.

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
- `lib/screens/bubble_pop_screen.dart` — catch one named animal (3/6/10 catches among 5/10/15 bubbles). Wrong bubbles are rejected, **stay on screen** (popping them would hide the mistake) and cost a star. The emoji pool is animals only — it once included 🌈 ⭐ 🌸 🍓 and opened by asking a child to catch a rainbow.
- `lib/data/animal_sounds.dart` — emoji → call asset for "Which Animal?". Deliberately NOT limited to `kAnimalEmojis` — a listening game needs no food pairing, so 🐷 🐦 🐯 live only here. CC0, public-domain or CC BY — **never ShareAlike**. Every call needs an entry in `lib/data/asset_credits.dart` (shown by `CreditsScreen`) and in `ASSET_CREDITS.md`; a test enforces it. Sources are Wikimedia Commons and the Internet Archive (the CC0 Designer's Choice library — Commons has no cow moo at all).
- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food).
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons); fires the win sound itself.
- `lib/widgets/game_timer.dart` — `GameLevel` (30s/1m/2m), `GameTimerController`, the no-digits `GameTimerBar`, and the `TimedGame` mixin — used by six of the seven games. Clock starts on first interaction, pauses on background, stops the instant a game is won. **Bubble Pop has no clock on purpose**: it asks which bubble is right, and a countdown rewards hurrying over choosing. It still takes `GameLevel`, for the difficulty numbers only.
- `lib/widgets/game_over_overlay.dart` — the "Time's up!" screen; a sibling of `CelebrationOverlay`, not a flag on it.
- `lib/services/app_language.dart` — the language switch and **every string in the app**, as getters on `AppStrings` so a missing translation is a compile error. English default; the choice is the one thing stored on the device (a small platform channel in `MainActivity`, not a package). `home:` in `main.dart` must stay non-`const` or the switch changes nothing — Flutter skips rebuilding an identical widget.
- `lib/services/narrator.dart` — speaks each game's name on open, via the TTS already present for Pollie, so it follows the language and needs no assets.
- `lib/services/` — `pollie_service` (HTTP client for the `worker/` proxy; model, prompt and safety settings live server-side), `kid_safety` (local adult-word guard on input *and* output), `sound_effects` (one-shot SFX), `music_service` + `music_route_observer` (looping background music).
- `lib/services/tts_service.dart` — **the app's only `FlutterTts`**. `flutter_tts` uses a static `MethodChannel` whose handler every constructor re-points, so a second instance silently steals `speak.onComplete` and Pollie's mic never re-opens. Callers take a session via `TtsService.instance.acquire()`; a test fails the build if a second `FlutterTts(` appears in `lib/`.
- `lib/services/vad_gate.dart` + `speech_sink.dart` — Pollie decides a child has finished from **acoustic silence**, not from the recogniser. Read `docs/superpowers/specs/2026-08-11-pollie-microphone-design.md` before touching any listening timer: four separate mechanisms used to end turns early, including `pauseFor` (which times the *transcript changing*, not silence) and Android reporting every speech error as permanent.
- `docs/superpowers/specs/` — design specs. Read the relevant one before touching a feature it covers.
- `worker/` — the Cloudflare Worker holding Pollie's Gemini key. **Read `docs/pollie-architecture-and-costs.md` before answering anything about the key, rate limits, costs, model choice, other providers, charging users, or the install id** — it records what was measured and why, so none of it has to be researched twice. Setup steps in `worker/README.md`; deploying needs the user (interactive login + secret).
- `packages/` — **vendored, patched** `speech_to_text` and its platform interface. Android's short "probably finished" silence timer (~500 ms) is not settable through the published package and is what cut a child off mid-sentence. Read `packages/PATCH.md` before touching or upgrading them; `analysis_options.yaml` excludes `packages/**`. If the build fails with "Conflicting overloads", run `flutter clean` — it is a stale Gradle cache, not the patch.
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
4. **Never animate a transform over text — scale *or* rotation.** `AnimatedScale`/`Transform.scale` around an emoji re-rasterises the glyph every frame and eventually stops emoji painting app-wide — they come back only when something else forces a repaint. This has caused a visible bug twice (jigsaw, then Find It!). Use translation, padding or colour for feedback; a rotating shake over twelve emoji did it too. A translation only moves pixels already drawn. A *static* `FittedBox` is fine; an animated one is not.
5. Emoji glyphs render smaller than their text box — use `FittedBox(fit: BoxFit.fill)` (or a large font size) when an emoji must fill a cell/board.
6. **Never `write` a string to an `HttpClientRequest`.** It encodes with the request's charset, which is Latin-1 unless one is set — so a single emoji or accented character throws "Contains invalid characters" and, once it is in the chat history, breaks every later request. Send `utf8.encode(...)` bytes with an explicit charset.
7. Widget tests that **tap** must set a phone viewport (`tester.view.physicalSize = Size(1080, 2400)`, dpr 3). At flutter_test's default 800x600 the taller game grids scroll and their bottom row is untappable, so a test can silently "pass" having played no rounds at all.
8. Xiaomi's emoji font may render some codepoints oddly — prefer widely-supported emoji (Unicode ≥ 6) for game content.
9. Test on the Xiaomi 15 via wireless adb. `adb install -r` works for *updates* to an already-installed package. Installing a **new** `applicationId` still fails with `INSTALL_FAILED_USER_RESTRICTED` even though `adb_install_need_confirm` is 0 — HyperOS applies a stricter check to first-time installs. Workaround that does work:
   ```bash
   adb push app.apk /data/local/tmp/x.apk && adb shell pm install -r -t /data/local/tmp/x.apk
   ```
10. **Never `adb uninstall` the app to swap build types.** With "Install via USB" off in Developer options, HyperOS refuses *every* first-time install — `adb install`, `adb install -t`, and the `/data/local/tmp` + `pm install -r -t` workaround in rule 9 all fail with `INSTALL_FAILED_USER_RESTRICTED` and **no on-screen prompt**. Uninstalling therefore strands the device with no way back until the user re-enables that toggle. Updates over an existing install are unaffected, so switch between release and profile builds by other means (or ask first).
11. Dart `print`/`debugPrint` does **not** reach `logcat` from a `--release` build. Any on-device tracing needs `--profile` — which is signed with the debug key, so it cannot be installed over a release build (see rule 10 before reaching for uninstall).
12. Renaming the `applicationId` resets the app's identity: runtime permissions are revoked and the old package lingers until `adb uninstall`. Re-grant with `adb shell pm grant <pkg> android.permission.RECORD_AUDIO` so Pollie's mic keeps working.
