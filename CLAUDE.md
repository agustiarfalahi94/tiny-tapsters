# CLAUDE.md — Project Memory for AI Agents

## Quick facts

- **Tiny Tapsters**: Flutter toddler-games app (`com.inkpebble.tiny_tapsters`), **v1.6.3+24**, Flutter 3.41.6 (stable), Android-first, emoji-based graphics (no image assets).
- **Dependencies**: `audioplayers` (SFX), `google_generative_ai` + `flutter_tts` + `speech_to_text` (Pollie companion), `cupertino_icons`; `flutter_lints` in dev. Only *bundled* asset: `assets/sfx/pop.wav` — `assets/branding/tiny-tapsters-logo.png` is build-time input for the icon generator and is deliberately not in `pubspec.yaml`.
- **Permissions**: `INTERNET` + `RECORD_AUDIO` — both exist only for Pollie's voice chat. **All six games are fully offline**; Pollie is the sole network feature.
- **Default branch is `develop`**; release = merge to `main` + annotated tag `vX.Y.Z` (push both).
- **Features go on a dedicated `feature/<name>` branch** off `develop` — never commit feature work straight to `develop`. Plan in chat first, then execute.
- **Validation before any commit:** `flutter analyze` (0 issues), `dart format --set-exit-if-changed lib/ test/`, `flutter test` (**22/22**), `flutter build apk --release` (when native config or deps change).
- **Never touch/commit**: `android/key.properties`, `android/app/release-keystore.jks`, or any Gemini API key. The key is injected at build time via `--dart-define=GEMINI_API_KEY=...` (CI reads it from the `GEMINI_API_KEY` repo secret).

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

- `lib/screens/` — `home_screen` (menu), `levels_screen` (shared Easy/Medium/Big picker), `companion_screen` (Pollie), and the games: `jigsaw_game`, `animal_food`, `memory_game`, `bubble_pop`, `find_it`, `count_game`.
- `lib/widgets/pair_drag_game.dart` — shared drag-to-slot engine (jigsaw + Animal Food).
- `lib/widgets/celebration_overlay.dart` — shared win overlay (confetti + stars + buttons).
- `lib/services/` — `pollie_service` (Gemini wrapper, strict safety settings), `kid_safety` (local adult-word guard on input *and* output), `sound_effects` (one-shot SFX).
- `tool/` — dependency-free Dart generators: `generate_icon.dart` (crops the badge out of `assets/branding/tiny-tapsters-logo.png` and writes the legacy + adaptive launcher icons; has its own PNG decoder/encoder), `generate_sfx.dart` (pop.wav), `pixelcheck.dart`.
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
5. Xiaomi's emoji font may render some codepoints oddly — prefer widely-supported emoji (Unicode ≥ 6) for game content.
6. Test on the Xiaomi 15 via wireless adb. `adb install -r` works for *updates* to an already-installed package. Installing a **new** `applicationId` still fails with `INSTALL_FAILED_USER_RESTRICTED` even though `adb_install_need_confirm` is 0 — HyperOS applies a stricter check to first-time installs. Workaround that does work:
   ```bash
   adb push app.apk /data/local/tmp/x.apk && adb shell pm install -r -t /data/local/tmp/x.apk
   ```
7. Renaming the `applicationId` resets the app's identity: runtime permissions are revoked and the old package lingers until `adb uninstall`. Re-grant with `adb shell pm grant <pkg> android.permission.RECORD_AUDIO` so Pollie's mic keeps working.
