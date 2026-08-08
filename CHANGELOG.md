# Changelog

All notable changes to Our Toddlers' Journey are documented here.
Format: **Added** · **Fixed** · **Changed** · **Removed** · **Improved**

---

## [1.0.4] — 2026-08-08

### Fixed
- **Every icon in the app could disappear while playing the jigsaw** — the
  puzzle picture was rendered as a 300px+ emoji glyph, which can exhaust the
  Android glyph atlas and stop ALL text/emoji from painting anywhere in the
  app (until restart), while the app still looks and feels interactive. The
  picture emoji is now rendered at a moderate 128px and enlarged with a GPU
  transform instead.
- **Laggy piece placement in the jigsaw** — caused by the same giant glyph
  rasterization; gone with the font fix.
- **Jigsaw tiles were rounded while the picture pieces were square** — the
  dashed slot outlines and the board background are now perfectly square.

### Added
- **Regression tests** — jigsaw pieces are slot-sized, no oversized fonts /
  FittedBox in the jigsaw, tiles are square, and a real drag gesture test
  proves a piece snaps only into its own slot (7 tests total).

### Notes
- `flutter analyze`: 0 issues; 7/7 tests passing.

---

## [1.0.3] — 2026-08-08

### Fixed
- **Jigsaw pieces still smaller than the board (v1.0.2 regression)** — the
  previous fix left a comment but never applied `pieceScale: 1.0`, so pieces
  silently fell back to the engine defaults and the picture still assembled
  at half size. Pieces are now truly slot-sized, and a regression test
  asserts piece size == slot size.

### Notes
- `flutter analyze`: 0 issues; 5/5 tests passing.

---

## [1.0.2] — 2026-08-08

### Fixed
- **Jigsaw picture smaller than the board** — pieces were half the slot size
  and scaled their cell region down to fit, so the assembled picture only
  filled half the puzzle square. Pieces are now exactly slot-sized, so the
  picture assembles 1:1 and fills the board.
- **Home title could appear left-aligned** — the header texts now center
  explicitly (regression-tested through game navigation).

### Notes
- `flutter analyze`: 0 issues; 4/4 tests passing.

---

## [1.0.1] — 2026-08-08

### Changed
- **App renamed to "Our Toddlers' Journey"** — the launcher label, app title,
  and home screen header now match the project name.

### Notes
- `flutter analyze`: 0 issues; 3/3 tests passing.

---

## [1.0.0] — 2026-08-08

First release: five toddler games in one offline, permission-free Android app.

### Added
- **Jigsaw Puzzle** — a real picture puzzle: an emoji picture sliced into a
  grid with a faint reference image behind the board. Easy (2×2), Medium (3×2),
  Big (3×3). Pieces snap with a pop; a new random picture each win.
- **Animal Food** — drag each animal to its favorite food. Pool of 15
  stereotype pairs (rabbit → carrot, cow → grass, horse → apple, giraffe →
  leaves, butterfly → flower…), shuffled per game. Easy (3), Medium (6), Big (9).
- **Memory Match** — flip cards to find matching animal pairs. Easy (2 pairs),
  Medium (3 pairs), Big (6 pairs). Star rating based on moves.
- **Bubble Pop** — tap floating bubbles to pop them into sparkles. Pop 8 per
  round; bubbles get faster each round. Drift is endless and seamless.
- **Find It!** — "Find the 🐶!": tap the matching animal in the grid. Find 5 to
  win; stars depend on wrong taps. Easy (6), Medium (9), Big (12) cards.
- **Shared difficulty picker** (`LevelsScreen`) for every tiered game.
- **Shared drag-to-slot engine** (`PairDragGame`) powering jigsaw + Animal Food.
- **Celebration overlays** — confetti rain, stars, and replay buttons on every
  win (shared `CelebrationOverlay`).
- Haptic feedback on every meaningful interaction (flips, matches, pops, snaps,
  wrong answers).

### Fixed
- **Bubble Pop jump every 5 s** — the drift loop reset the position math at
  each cycle boundary. Now a 60 s cycle folds each bubble's position into the
  next cycle, so the motion never visibly restarts.
- **Find It! red tint stuck** — the wrong-tap shake animation ended at value 1,
  leaving cards permanently tinted. The tint is now a triangle wave that
  returns to white.
- **Find It! repeated targets** — the same animal could be asked twice in a
  row. Each round now excludes the previous target.
- **Pieces snapping into wrong slots** — the old shape puzzle only checked
  distance, not the image match. The rebuilt games only accept a piece into
  its own slot.
- **First drag on a piece failing** — swapping widget types mid-gesture
  cancelled the active pan. The drag engine now keeps a stable widget
  structure.
- **"Trail" artifacts while dragging** — pieces could visibly slide after a
  release (including pieces the user wasn't touching). All piece movement is
  now instant; interrupted drags are cleaned up via `onPanCancel`.
- **Jigsaw cut lines visible** — the picture's white border showed up on every
  piece. Removed border/radius; slices blend seamlessly.

### Changed
- **Release signing** — the app is signed with the shared `random_recall`
  keystore (`android/key.properties`, git-ignored) so updates install cleanly
  over each other.
- **Hardened release build** — R8 minification + resource shrinking, ProGuard
  rules, `allowBackup=false` / `fullBackupContent=false`.
- **Jigsaw emoji fills the board** — the emoji now stretches to the full
  picture area instead of floating at ~50%.

### Notes
- `flutter analyze`: 0 issues; 3/3 tests passing.
- Installed and play-tested on a Xiaomi 15 (HyperOS, Android 16).
