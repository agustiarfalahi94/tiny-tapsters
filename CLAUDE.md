# CLAUDE.md — Project Memory for AI Agents

## Quick facts

- **Our Toddlers' Journey**: Flutter toddler-games app (`com.lilianyoctoria.toddlers_journey`), v1.0.0, Flutter 3.41.6, zero packages/permissions, offline, emoji graphics.
- **Default branch is `develop`**; release = merge to `main` + annotated tag `vX.Y.Z`.
- **Validation before any commit:** `flutter analyze` (0 issues), `dart format --set-exit-if-changed lib/ test/`, `flutter test` (3/3), `flutter build apk --release`.
- **Never touch/commit**: `android/key.properties`, `android/app/release-keystore.jks`.

## Commands

```bash
flutter analyze
dart format --set-exit-if-changed lib/ test/
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Golden rules learned the hard way

1. Xiaomi/HyperOS blocks `adb install` unless `adb_install_need_confirm` is set to 0 (`adb shell settings put global adb_install_need_confirm 0`) — already done on the test device (Xiaomi 15).
2. Wireless debugging sessions expire on their own. Reconnect: `adb mdns services` shows the device; `adb connect <ip>:<port>`; if refused, ask the user to reopen the Wireless debugging screen.
3. Never swap widget types mid-gesture (e.g. `AnimatedPositioned` ↔ `Positioned` while a pan is active) — it cancels the pan. Keep the tree structure stable; if a piece moves, keep it instant (animated returns read as "trails").
4. Emoji glyphs render smaller than their text box — use `FittedBox(fit: BoxFit.fill)` (or a large font size) when an emoji must fill a cell/board.
5. Xiaomi's emoji font may render some codepoints oddly — prefer widely-supported emoji (Unicode ≥ 6) for game content.
6. Test on the Xiaomi 15 via wireless adb; install directly with `adb install -r` (no push-and-tap dance needed anymore).
