# AGENTS.md — Instructions for AI Coding Agents (Zed)

## Project

Tiny Tapsters — Flutter toddler-games app (`com.inkpebble.tiny_tapsters`). v1.15.0+34 · Flutter 3.41.6 · Android-first · Emoji-based graphics (no image assets; bundled audio only: `assets/sfx/*` and `assets/music/*`) · Shared signing keystore with the `random_recall` project.

**Packages**: `audioplayers` (SFX), `google_generative_ai` + `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev.
**Permissions**: `INTERNET` + `RECORD_AUDIO`, both for Pollie's voice chat only. The seven games are fully offline; Pollie is the sole network feature.

## Git flow

- Work on **`develop`** (default branch).
- **Improvements & features: always work on a dedicated branch** (e.g. `feature/<name>`) created from `develop` — never commit feature work directly on `develop`. Merge back to `develop` only after validation passes.
- **Plan before execution**: write the plan in chat first (scope, files touched, validation steps), get user confirmation, then execute. This applies to all tasks, especially multi-agent ones.
- **Sub-agent (multi-agent) tasks**: roles are separated — one implementer (disjoint write scope), one reviewer (read-only, fresh-eyes critique), one tester (runs `flutter analyze` / `dart format` / `flutter test` / release build). Synthesize their results; only merge when all pass.
- Release: merge `develop` → `main` locally → push main → annotated tag `vX.Y.Z` → push tag.

## Validation (run before finishing any task)

```bash
flutter analyze                       # must say "No issues found!"
dart format --set-exit-if-changed lib/ test/
flutter test
flutter build apk --release           # when native config or deps changed
```

## Constraints

- Do NOT commit `android/key.properties` or `android/app/release-keystore.jks` (keystore secrets, git-ignored).
- Do NOT add ads, analytics, or tracking. The app is offline EXCEPT the Pollie companion (Gemini) — the only network feature. Permissions: INTERNET + RECORD_AUDIO (voice chat).
- Never commit a Gemini API key. **It no longer ships in the app at all** — it is a Cloudflare Worker secret (`worker/`, see its README). The app takes `--dart-define=POLLIE_ENDPOINT=https://...`, a URL rather than a secret; CI reads the `POLLIE_ENDPOINT` repo *variable*.
- All games must be playable without reading: big emoji, no required text.
- Keep CHANGELOG.md + README.md in sync with real changes, and CLAUDE.md consistent with this file.

## Key files

- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food). Piece movement must stay instant; never reintroduce animated slide-backs (they read as "trails").
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/screens/levels_screen.dart` — shared difficulty picker.
- `lib/services/pollie_service.dart` — HTTP client for Pollie's proxy. Streams newline-delimited JSON; the model, prompt and safety settings all live in `worker/src/index.ts`.
- `lib/widgets/pollie_bird.dart` — the bobbing bird and the "Tap to talk!" bubble. **Translate and rotate only, never scale**: scaling text re-rasterises emoji glyphs every frame and eventually stops every emoji in the app painting.
- `worker/` — the Cloudflare Worker holding the Gemini key. `worker/README.md` has the account setup.
- `lib/screens/companion_screen.dart` — Pollie. Two things here are easy to break: a listening **turn** is the app's, not the recogniser's (sessions are banked and the mic re-armed until the child is quiet for 5s — Android's short "possibly finished" endpointing is not configurable, so never go back to sending on the first final result); and `flutter_tts` reports voice quality as a **string**, so score voices with `voiceScore`/`pickBestVoice` and never cast `quality` to a number.
- `lib/services/kid_safety.dart` — local adult-word guard (input + output).
- `lib/services/sound_effects.dart` — one-shot SFX (pop, win, lose); regenerate `pop.wav` with `dart run tool/generate_sfx.dart`.
- `lib/services/music_service.dart` + `music_route_observer.dart` — looping background music. Kept separate from `SoundEffects` on purpose: `pop()` stops its player before every play, so one shared player would let every tap kill the music. Track switching lives in the observer, not each screen's `initState`, because popping a game does not re-run `HomeScreen.initState`. Every player must stay on `AudioContextConfigFocus.mixWithOthers` (set once in `main.dart`) — the default `AudioFocus.gain` is exclusive and makes each sound effect stop the music. **Never hand-encode audio** — run `python3 tool/normalize_audio.py <source-dir>`, which rebuilds every asset at one loudness (−16 dBFS RMS, 44.1 kHz). Hand-rolled `afconvert` calls are how the animal calls shipped at 22 kHz and how the mix ended up 20 dB apart.
- `lib/widgets/game_timer.dart` — `GameLevel` (30s/1m/2m), `GameTimerController`, the `GameTimerBar` a non-reader can follow, and the `TimedGame` mixin every game screen uses. The clock starts on first interaction, pauses on background, and stops the instant a game is won.
- `lib/widgets/game_over_overlay.dart` — the "Time's up!" screen. A sibling of `CelebrationOverlay`, not a flag on it.
- `lib/data/animal_sounds.dart` — emoji → call asset for "Which Animal?". Keys must be in `kAnimalEmojis` (tested). CC0, public-domain or CC BY — **never ShareAlike**. Every call needs an entry in `lib/data/asset_credits.dart` (shown by `CreditsScreen`) and in `ASSET_CREDITS.md`; a test enforces it. Sources are Wikimedia Commons and the Internet Archive (the CC0 Designer's Choice library — Commons has no cow moo at all).
- `docs/superpowers/specs/` — design specs; read the relevant one before touching a feature it covers.
- `tool/generate_icon.dart` — pure-Dart launcher-icon generator (no Flutter engine, no packages); derives all mipmap PNGs + adaptive icon resources from `assets/branding/tiny-tapsters-logo.png`. Contains its own PNG decoder and encoder. Re-run with `dart run tool/generate_icon.dart` after changing the logo. The master artwork is build-time only — never add it to `pubspec.yaml`.
- `.github/workflows/release-apk.yml` — on `v*` tag push: analyze + test, sign with the real keystore, attach the APK to the GitHub release.
- `test/widget_test.dart` — **24 tests**: home screen, all-screens-build smoke test, Find It! tint regression, jigsaw snap tests, companion fallback + kid-safety + quota tests, and the count-game flow (seeded RNG: wrong tap doesn't advance, star thresholds, double-tap guard, Big-mode boundary).
- `test/timer_test.dart` — **9 tests**: level durations, start/pause/resume/reset, expiry firing once, loss-not-win on timeout, and Easy's reduced round count.
- `test/audio_test.dart` — **12 tests**: music track switching and mute, ducking, route→track mapping, and the home mute button. Uses a `FakeMusicSink`; anything touching the real `MusicService.instance` must never be awaited in a test, because the audio plugin is not registered and never answers.
