# AGENTS.md — Instructions for AI Coding Agents (Zed)

## Project

Our Toddlers' Journey — Flutter toddler-games app (`com.lilianyoctoria.toddlers_journey`). v1.5.0 · Flutter 3.41.6 · **One external package: audioplayers (SFX)** · **Zero permissions** · Fully offline · Android-first · Emoji-based graphics (no image assets) · Shared signing keystore with the `random_recall` project.

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
- Never commit a Gemini API key: it is passed at build time via `--dart-define=GEMINI_API_KEY=...`.
- Background music plays on home/games, NOT on the Pollie screen; pause/resume with app lifecycle.
- All games must be playable without reading: big emoji, no required text.
- Keep CHANGELOG.md + README.md in sync with real changes.

## Key files

- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food). Piece movement must stay instant; never reintroduce animated slide-backs (they read as "trails").
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/screens/levels_screen.dart` — shared difficulty picker.
- `lib/services/pollie_service.dart` — Gemini wrapper for the Pollie companion (strict safety settings + kid-safe prompt).
- `lib/services/kid_safety.dart` — local adult-word guard (input + output).
- `lib/services/sound_effects.dart` — one-shot SFX (bubble pop); regenerate the asset with `dart run tool/generate_sfx.dart`.
- `tool/generate_icon.dart` — pure-Dart launcher-icon generator (no Flutter engine); writes all mipmap PNGs + adaptive icon resources. Re-run with `dart run tool/generate_icon.dart` after changing the design.
- `test/widget_test.dart` — home screen, all-screens-build smoke test, Find It! tint regression, jigsaw snap tests, companion fallback + kid-safety tests.
