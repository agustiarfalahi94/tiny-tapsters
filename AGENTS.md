# AGENTS.md — Instructions for AI Coding Agents (Zed)

## Project

Tiny Tapsters — Flutter toddler-games app (`com.inkpebble.tiny_tapsters`). v1.6.1+22 · Flutter 3.41.6 · Android-first · Emoji-based graphics (no image assets, only `assets/sfx/pop.wav`) · Shared signing keystore with the `random_recall` project.

**Packages**: `audioplayers` (SFX), `google_generative_ai` + `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev.
**Permissions**: `INTERNET` + `RECORD_AUDIO`, both for Pollie's voice chat only. The six games are fully offline; Pollie is the sole network feature.

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
- Never commit a Gemini API key: it is passed at build time via `--dart-define=GEMINI_API_KEY=...` (CI reads the `GEMINI_API_KEY` repo secret).
- All games must be playable without reading: big emoji, no required text.
- Keep CHANGELOG.md + README.md in sync with real changes, and CLAUDE.md consistent with this file.

## Key files

- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food). Piece movement must stay instant; never reintroduce animated slide-backs (they read as "trails").
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/screens/levels_screen.dart` — shared difficulty picker.
- `lib/services/pollie_service.dart` — Gemini wrapper for the Pollie companion (strict safety settings + kid-safe prompt).
- `lib/screens/companion_screen.dart` — Pollie. Two things here are easy to break: a listening **turn** is the app's, not the recogniser's (sessions are banked and the mic re-armed until the child is quiet for 5s — Android's short "possibly finished" endpointing is not configurable, so never go back to sending on the first final result); and `flutter_tts` reports voice quality as a **string**, so score voices with `voiceScore`/`pickBestVoice` and never cast `quality` to a number.
- `lib/services/kid_safety.dart` — local adult-word guard (input + output).
- `lib/services/sound_effects.dart` — one-shot SFX (bubble pop); regenerate the asset with `dart run tool/generate_sfx.dart`.
- `tool/generate_icon.dart` — pure-Dart launcher-icon generator (no Flutter engine, no packages); derives all mipmap PNGs + adaptive icon resources from `assets/branding/tiny-tapsters-logo.png`. Contains its own PNG decoder and encoder. Re-run with `dart run tool/generate_icon.dart` after changing the logo. The master artwork is build-time only — never add it to `pubspec.yaml`.
- `.github/workflows/release-apk.yml` — on `v*` tag push: analyze + test, sign with the real keystore, attach the APK to the GitHub release.
- `test/widget_test.dart` — **19 tests**: home screen, all-screens-build smoke test, Find It! tint regression, jigsaw snap tests, companion fallback + kid-safety + quota tests, and the count-game flow (seeded RNG: wrong tap doesn't advance, star thresholds, double-tap guard, Big-mode boundary).
