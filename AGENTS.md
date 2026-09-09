# AGENTS.md — Instructions for AI Coding Agents (Zed)

## Start here

**The app is called Tiny Tapsters** — and now everything says so: the checkout
directory `tiny-tapsters`, `pubspec.yaml`, the launcher label, the package id
and the git remote. The CHANGELOG still records the earlier name it was renamed
*from* in v1.6.0; that is history, not an alternative. Do not infer project
facts from the surroundings — read the code. `test/docs_test.dart` enforces
this and the other load-bearing facts; run it if you are unsure whether a
document is current.

Read: this file → `CLAUDE.md` (same instructions, must stay in sync) → the
relevant spec in `docs/superpowers/specs/` → `docs/pollie-architecture-and-costs.md`
for the AI companion.

## Working agreement (read before touching anything)

These are not style preferences. Each one exists because it was broken, and the
breakage reached a public release.

1. **Run `./tool/check.sh` before every commit and paste its output.** It runs
   analyze, format and the tests, then prints the app name, version, package id,
   remote and game list *read from the files*. A summary can be invented; a
   pasted run of this cannot.
2. **Never state a fact about this project from memory.** Not the version, not
   the game count, not the package id, not the test count. Run the command.
3. **Cite `file:line`** for any claim about how the code behaves.
4. **Documentation changes must pass `flutter test test/docs_test.dart`.** It is
   the arbiter for the app name, package id, version, game count, where the
   Gemini key lives, and whether the README maps every service and widget.
5. **Work on a branch off `develop`.** Never commit to `develop` or `main`
   directly, never tag, never cut a release.
6. **Say what you changed and what was already there.** Claiming existing work
   as your own makes it impossible to know what is real.
7. **If you could not run a command, write "unverified".** Do not fill the gap
   with something plausible.

A tell worth naming: tables, checkmarks and "✅ Verified" are where invented
facts hide. Raw terminal output is the only evidence that counts.

## Project

Tiny Tapsters — Flutter toddler-games app (`com.inkpebble.tiny_tapsters`). v1.25.7+60 · Flutter 3.41.6 · Android-first · Emoji-based graphics (no image assets; bundled audio only: `assets/sfx/*`, `assets/music/*` and the 15 `assets/animal_sounds/*` calls "Which Animal?" is built on) · Shared signing keystore with the `random_recall` project.

**Packages**: `audioplayers` (SFX + music), `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev. `google_generative_ai` is gone — Pollie talks to the Worker over plain `HttpClient`.
**Permissions**: `INTERNET` + `RECORD_AUDIO`, both for Pollie's voice chat only. The seven games are fully offline; Pollie is the sole network feature.

## Git flow

- Work on **`develop`** (default branch).
- **Improvements & features: always work on a dedicated branch** (e.g. `feature/<name>`) created from `develop` — never commit feature work directly on `develop`. Merge back to `develop` only after validation passes.
- **Plan before execution**: write the plan in chat first (scope, files touched, validation steps), get user confirmation, then execute. This applies to all tasks, especially multi-agent ones.
- **Sub-agent (multi-agent) tasks**: roles are separated — one implementer (disjoint write scope), one reviewer (read-only, fresh-eyes critique), one tester (runs `flutter analyze` / `dart format` / `flutter test` / release build). Synthesize their results; only merge when all pass.
- Release: merge `develop` → `main` locally → push main → annotated tag `vX.Y.Z` → push tag.

## Validation (run before finishing any task)

`./tool/check.sh` runs all of this and prints the project's facts. The
individual commands, if you need them:

```bash
flutter analyze                       # must say "No issues found!"
dart format --set-exit-if-changed lib/ test/
flutter test
flutter build apk --release           # when native config or deps changed
```

## Constraints

- Do NOT commit `android/key.properties` or `android/app/release-keystore.jks` (keystore secrets, git-ignored).
- Do NOT add ads, analytics, or tracking. The app is offline EXCEPT the Pollie companion (Gemini) — the only network feature. Permissions: INTERNET + RECORD_AUDIO (voice chat).
- Never commit a Gemini API key. **It no longer ships in the app at all** — it is a Cloudflare Worker secret (`worker/`, see its README). The app defaults to the deployed proxy at `https://pollie.inkpebble.workers.dev`; override with `--dart-define=POLLIE_ENDPOINT=...`. A URL is not a secret.
- All games must be playable without reading: big emoji, no required text.
- Keep CHANGELOG.md + README.md in sync with real changes, and CLAUDE.md consistent with this file.

## Key files

- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food). Piece movement must stay instant; never reintroduce animated slide-backs (they read as "trails").
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/screens/levels_screen.dart` — shared difficulty picker.
- `lib/screens/bubble_pop_screen.dart` — catch one named animal (3/6/10 catches among 5/10/15 bubbles). A wrong bubble is rejected and **stays on screen** — popping it would hide the mistake — and costs a star. The emoji pool is animals only, because the game says "catch the right animal".
- `lib/services/pollie_service.dart` — HTTP client for Pollie's proxy. Streams newline-delimited JSON; the model, prompt and safety settings all live in `worker/src/index.ts`.
- `lib/widgets/pollie_bird.dart` — the bobbing bird and the "Tap to talk!" bubble. **Translate and rotate only, never scale**: scaling text re-rasterises emoji glyphs every frame and eventually stops every emoji in the app painting.
- `worker/` — the Cloudflare Worker holding the Gemini key. **Read `docs/pollie-architecture-and-costs.md` before answering anything about the key, rate limits, costs, model choice, other providers, charging users, or the install id** — it records what was measured and why, so none of it has to be researched twice. `worker/README.md` has the account setup.
- `lib/screens/companion_screen.dart` — Pollie. Two things here are easy to break: a listening **turn** is the app's, not the recogniser's (sessions are banked and the mic re-armed until the child is quiet for 4s, with a 12s absolute give-up and a 45s turn cap — so never go back to ending the turn on the first final result); and `flutter_tts` reports voice quality as a **string**, so score voices with `voiceScore`/`pickBestVoice` and never cast `quality` to a number. Android's short "possibly finished" endpointing *is* configurable, but only through the vendored patch in `packages/` — and it is advisory, which is why the banking model exists on top of it.
- `lib/services/kid_safety.dart` — local adult-word guard (input + output).
- `lib/services/tts_service.dart` — **the app's only `FlutterTts`**. The plugin uses a static `MethodChannel` whose handler every constructor re-points, so a second instance silently steals `speak.onComplete` and Pollie's mic never re-opens. Go through `TtsService.instance.acquire()`; a test fails the build if a second one appears. **`acquire()` also picks the engine** — Google's when installed and not already default, once per launch, before anything else is configured (switching rebuilds the platform engine and drops language/voice/pitch/rate with it). This needs `android.intent.action.TTS_SERVICE` in the manifest's `<queries>`: without it Android 11+ hides every engine, `getEngines()` returns empty, and `pickBestVoice` ends up ranking the voices of whatever engine the framework happened to bind — which is how Pollie sounded robotic while the scoring code looked correct. Trace it with `TTS|` from a `--profile` build (golden rule 11).
- `lib/services/speech_sink.dart` + `vad_gate.dart` — Pollie decides a child has finished from **acoustic silence**, not from the recogniser. **Read `docs/superpowers/specs/2026-08-11-pollie-microphone-design.md` before touching any listening timer** — five separate mechanisms used to end turns early, including `pauseFor` (which times the transcript *changing*, not silence) and Android reporting every speech error as permanent.
- `lib/services/sound_effects.dart` — one-shot SFX (pop, wrong, win, lose); regenerate `pop.wav` **and** `wrong.wav` with `dart run tool/generate_sfx.dart` — it writes both, and `test/audio_test.dart` checks `wrong.wav` is generated and bundled.
- `lib/services/music_service.dart` + `music_route_observer.dart` — looping background music. Kept separate from `SoundEffects` on purpose: `pop()` stops its player before every play, so one shared player would let every tap kill the music. Track switching lives in the observer, not each screen's `initState`, because popping a game does not re-run `HomeScreen.initState`. Every player must stay on `AudioContextConfigFocus.mixWithOthers` (set once in `main.dart`) — the default `AudioFocus.gain` is exclusive and makes each sound effect stop the music. **Never hand-encode audio** — run `python3 tool/normalize_audio.py <source-dir>`, which rebuilds every asset at one loudness (−16 dBFS RMS, 44.1 kHz). Hand-rolled `afconvert` calls are how the animal calls shipped at 22 kHz and how the mix ended up 20 dB apart.
- `lib/widgets/game_timer.dart` — `GameLevel` (30s/1m/2m), `GameTimerController`, the `GameTimerBar` a non-reader can follow, and the `TimedGame` mixin. Six of the seven games use it; the clock starts on first interaction, pauses on background, and stops the instant a game is won. **Bubble Pop deliberately does not** — it asks the child to pick the right bubble, and a countdown rewards hurrying over choosing. `GameLevel` still reaches it, for the difficulty numbers only.
- `lib/widgets/game_over_overlay.dart` — the "Time's up!" screen. A sibling of `CelebrationOverlay`, not a flag on it.
- `lib/data/animal_sounds.dart` — emoji → call asset for "Which Animal?". Deliberately NOT limited to `kAnimalEmojis` — a listening game needs no food pairing, so 🐷 🐦 🐯 live only here. **Never ShareAlike** — `animal_sound_test.dart:75` rejects any licence whose name contains `sa`. Every call needs an entry in `lib/data/asset_credits.dart` (shown by `CreditsScreen`) and in `ASSET_CREDITS.md`; a test enforces it. **Fourteen of the fifteen are Pixabay Content License** (no attribution required; credited anyway so provenance stays checkable); 🐶 the dog is CC0 from Wikimedia Commons. Nothing bundled is CC BY. The Wikimedia-and-Internet-Archive sourcing this line used to describe was replaced in v1.17.0, when eight calls were re-recorded from Pixabay.
- `packages/` — vendored, patched `speech_to_text` + platform interface, for the Android silence timer the published package will not expose. See `packages/PATCH.md`; excluded from analysis. "Conflicting overloads" on build means a stale Gradle cache — `flutter clean`.
- `lib/services/app_language.dart` — language switch + all strings (`AppStrings` getters, so a missing translation fails to compile). English default; the choice is stored via a platform channel in `MainActivity`. `home:` in `main.dart` must stay non-`const`.
- `lib/services/narrator.dart` — speaks each game's name on open, in the chosen language.
- `docs/superpowers/specs/` — design specs; read the relevant one before touching a feature it covers.
- `tool/generate_icon.dart` — pure-Dart launcher-icon generator (no Flutter engine, no packages); derives all mipmap PNGs + adaptive icon resources from `assets/branding/tiny-tapsters-logo.png`. Contains its own PNG decoder and encoder. Re-run with `dart run tool/generate_icon.dart` after changing the logo. The master artwork is build-time only — never add it to `pubspec.yaml`.
- `.github/workflows/release-apk.yml` — on `v*` tag push: analyze + test, sign with the real keystore, attach the APK to the GitHub release.
- `test/docs_test.dart` — the load-bearing facts in README/CLAUDE.md/AGENTS.md: app name, package id, version, game count, that no document claims the Gemini key ships in the APK, and that the README maps every service and widget. Added after a docs rewrite renamed the app to the checkout directory and was published.
- `test/pollie_turn_test.dart` — the whole listening turn machine against a fake recogniser: the ready gate, silence endpointing, a recogniser wiping its own guess mid-sentence, hold-to-talk, and that the mic always comes back.
- `test/vad_test.dart` — the sound gate (floor calibration, hysteresis, short words) as pure numbers.
- `test/tts_ownership_test.dart` — one engine, newest owner wins, and a source scan for a second `FlutterTts`.
- `test/tts_engine_test.dart` — which Android TTS engine gets bound: prefer Google's when installed, leave an unknown default alone, choose once, and never let engine trouble stop Pollie speaking.
- `test/speech_plugin_test.dart` — the vendored patch itself: option marshalling and the `readyForSpeech` status, driven through `SpeechToTextPlatform.instance`.
- `test/count_rows_test.dart` — the random row layouts in Count the Animals.
- `test/language_test.dart` — every string translated, and the locale ids speech and TTS need.
- `test/widget_test.dart` — home screen, all-screens-build smoke test, Find It! tint regression, jigsaw snap tests, companion fallback + kid-safety + quota tests, the count-game flow (seeded RNG), and Bubble Pop's target rules (wrong animals rejected, mistakes cost stars, no overshoot past the last catch). The Bubble Pop tests read the live header rather than a hard-coded label — an earlier version asserted on `'Pop 0 more!'` and kept passing after that label was replaced.
- `test/timer_test.dart` — level durations, start/pause/resume/reset, expiry firing once, loss-not-win on timeout, Easy's reduced round count.
- `test/audio_test.dart` — music track switching, mute, ducking, per-screen attenuation, lifecycle pause/resume, route→track mapping, the home mute button, and that `wrong.wav` is generated and bundled. Uses a `FakeMusicSink`; anything touching the real `MusicService.instance` must never be awaited in a test, because the audio plugin is not registered and never answers.
- `test/animal_sound_test.dart` — the sound catalogue (every call bundled, credited, and not ShareAlike), the credits screen, per-screen music attenuation, and that no animal is asked twice in a game.
- `test/pollie_test.dart` — sentence splitting, and the proxy client against a real local HTTP server (streaming, split lines, malformed lines, install id, 429 → quota).
- `test/layout_test.dart` — board bounds and caption room at phone size, no screen overflowing at 360dp, memory-match concurrency, and Find It! not repeating an animal.

Counts deliberately omitted here — the total lives in the validation line above, and per-file numbers went stale every release.

## Device testing gotchas

- **Never `adb uninstall` the app to swap build types.** With "Install via USB" off, HyperOS refuses every *first-time* install — `adb install`, `-t`, and the `/data/local/tmp` + `pm install` workaround all fail with `INSTALL_FAILED_USER_RESTRICTED` and no prompt. Updates over an existing install still work.
- Dart `debugPrint` does not reach `logcat` from a release build; on-device tracing needs `--profile` (debug-signed, so it cannot update a release install).
- Pollie has a trace behind `--dart-define=POLLIE_TRACE=1`: `PT|<event>|<millis>|<payload>`, read with `adb logcat -s flutter:V | grep 'PT|'`.
