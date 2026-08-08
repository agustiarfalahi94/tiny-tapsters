# AGENTS.md — Instructions for AI Coding Agents (Zed)

## Project

Our Toddlers' Journey — Flutter toddler-games app (`com.lilianyoctoria.toddlers_journey`). v1.0.0 · Flutter 3.41.6 · **Zero external packages** · **Zero permissions** · Fully offline · Android-first · Emoji-based graphics (no image assets) · Shared signing keystore with the `random_recall` project.

## Git flow

- Work on **`develop`** (default branch).
- Release: merge `develop` → `main` locally → push main → annotated tag `vX.Y.Z` → push tag.

## Validation (run before finishing any task)

```bash
flutter analyze                       # must say "No issues found!"
dart format --set-exit-if-changed lib/ test/
flutter test                          # 3/3
flutter build apk --release           # when native config or deps changed
```

## Constraints

- Do NOT commit `android/key.properties` or `android/app/release-keystore.jks` (keystore secrets, git-ignored).
- Do NOT add ads, analytics, or tracking. The app is offline EXCEPT the Pollie companion (Gemini) — the only network feature, and the only permission (INTERNET).
- Never commit a Gemini API key: it is passed at build time via `--dart-define=GEMINI_API_KEY=...`.
- All games must be playable without reading: big emoji, no required text.
- Keep CHANGELOG.md + README.md in sync with real changes.

## Key files

- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food). Piece movement must stay instant; never reintroduce animated slide-backs (they read as "trails").
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/screens/levels_screen.dart` — shared difficulty picker.
- `lib/services/pollie_service.dart` — Gemini wrapper for the Pollie companion.
- `test/widget_test.dart` — home screen, all-screens-build smoke test, Find It! tint regression, jigsaw snap tests, companion fallback.
